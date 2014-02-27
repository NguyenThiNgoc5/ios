/*
     File: CrumbPathView.m 
 Abstract: 
 CrumbPathView is an MKOverlayView subclass that displays a path that changes over time.
 This class also demonstrates the fastest way to convert a list of MKMapPoints into a CGPath for drawing in an overlay view.
  
  Version: 1.6 
  
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple 
 Inc. ("Apple") in consideration of your agreement to the following 
 terms, and your use, installation, modification or redistribution of 
 this Apple software constitutes acceptance of these terms.  If you do 
 not agree with these terms, please do not use, install, modify or 
 redistribute this Apple software. 
  
 In consideration of your agreement to abide by the following terms, and 
 subject to these terms, Apple grants you a personal, non-exclusive 
 license, under Apple's copyrights in this original Apple software (the 
 "Apple Software"), to use, reproduce, modify and redistribute the Apple 
 Software, with or without modifications, in source and/or binary forms; 
 provided that if you redistribute the Apple Software in its entirety and 
 without modifications, you must retain this notice and the following 
 text and disclaimers in all such redistributions of the Apple Software. 
 Neither the name, trademarks, service marks or logos of Apple Inc. may 
 be used to endorse or promote products derived from the Apple Software 
 without specific prior written permission from Apple.  Except as 
 expressly stated in this notice, no other rights or licenses, express or 
 implied, are granted by Apple herein, including but not limited to any 
 patent rights that may be infringed by your derivative works or by other 
 works in which the Apple Software may be incorporated. 
  
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE 
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION 
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS 
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND 
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS. 
  
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL 
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, 
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED 
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE), 
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE 
 POSSIBILITY OF SUCH DAMAGE. 
  
 Copyright (C) 2012 Apple Inc. All Rights Reserved. 
  
 */

#import "CrumbPathView.h"

#import "CrumbPath.h"
#import "CSPointVO.h"

#define MIN_POINT_DELTA 5.0

/*
 CGColorRef dashColor=[UIColor redColor].CGColor;
 CGColorRef solidColor=[UIColor blueColor].CGColor;
 
 float dashes[] = { 4/zoomScale, 4/zoomScale };
 float normal[]={1};
*/


@interface CrumbPathView (FileInternal)
//- (CGPathRef)newPathForPoints:(MKMapPoint *)points
//                      pointCount:(NSUInteger)pointCount
//                        clipRect:(MKMapRect)mapRect
//					zoomScale:(MKZoomScale)zoomScale isDashed:(BOOL)isDashed;

- (CGPathRef)newPathForPoints:(NSMutableArray*)points clipRect:(MKMapRect)mapRect zoomScale:(MKZoomScale)zoomScale isDashed:(BOOL)isDashed;

@end

@implementation CrumbPathView


- (void)drawMapRect:(MKMapRect)mapRect
          zoomScale:(MKZoomScale)zoomScale
          inContext:(CGContextRef)context
{
    CrumbPath *crumbs = (CrumbPath *)(self.overlay);
    
    CGFloat lineWidth = MKRoadWidthAtZoomScale(zoomScale);
    
    NSLog(@"lineWidth=%g",lineWidth);
    
    // outset the map rect by the line width so that points just outside
    // of the currently drawn rect are included in the generated path.
    MKMapRect clipRect = MKMapRectInset(mapRect, -lineWidth, -lineWidth);
	
	CGColorRef dashColor=[UIColor redColor].CGColor;
	CGColorRef solidColor=[UIColor blueColor].CGColor;
	
	float dashes[] = { 4/zoomScale, 4/zoomScale };
	//float normal[]={1};
    
    [crumbs lockForReading];
    CGPathRef normalPath = [self newPathForPoints:crumbs.routePoints clipRect:clipRect zoomScale:zoomScale isDashed:NO];
    [crumbs unlockForReading];
    
    if (normalPath != nil)
    {
        CGContextSaveGState(context);
        CGContextAddPath(context, normalPath);
        CGContextSetStrokeColorWithColor(context, solidColor);
        CGContextSetLineJoin(context, kCGLineJoinRound);
        CGContextSetLineWidth(context, lineWidth);
        CGContextStrokePath(context);
        CGPathRelease(normalPath);
        CGContextRestoreGState(context);
    }
    
    [crumbs lockForReading];
    CGPathRef dashedPath = [self newPathForPoints:crumbs.routePoints clipRect:clipRect zoomScale:zoomScale isDashed:YES];
    [crumbs unlockForReading];
    
    if (dashedPath != nil)
    {
        CGContextSaveGState(context);
        CGContextAddPath(context, dashedPath);
        CGContextSetStrokeColorWithColor(context, dashColor);
        CGContextSetLineJoin(context, kCGLineJoinRound);
        CGContextSetLineDash(context, 0, dashes, 1);
        CGContextSetLineWidth(context, lineWidth);
        CGContextStrokePath(context);
        CGPathRelease(dashedPath);
        CGContextRestoreGState(context);
    }
}


@end

@implementation CrumbPathView (FileInternal)

static BOOL lineIntersectsRect(MKMapPoint p0, MKMapPoint p1, MKMapRect r)
{
    double minX = MIN(p0.x, p1.x);
    double minY = MIN(p0.y, p1.y);
    double maxX = MAX(p0.x, p1.x);
    double maxY = MAX(p0.y, p1.y);
    
    MKMapRect r2 = MKMapRectMake(minX, minY, maxX - minX, maxY - minY);
    return MKMapRectIntersectsRect(r, r2);
}


- (CGPathRef)newPathForPoints:(NSMutableArray*)points clipRect:(MKMapRect)mapRect zoomScale:(MKZoomScale)zoomScale isDashed:(BOOL)isDashed{
    
    if (points.count < 2)
        return NULL;
    
    CGMutablePathRef path = NULL;
    
    BOOL needsMove = YES;
    
	#define POW2(a) ((a) * (a))
    
    double minPointDelta = MIN_POINT_DELTA / zoomScale;
    double c2 = POW2(minPointDelta);
    
    MKMapPoint point;
	CSPointVO *firstpoint=points[0];
	MKMapPoint lastPoint = firstpoint.mapPoint;
	int pointCount=points.count;
    NSUInteger i;
    int segmentIndex=0;
	
    for (i = 1; i < pointCount - 1; i++){
		
		CSPointVO *cspoint=points[i];
        point = cspoint.mapPoint;
        double a2b2 = POW2(point.x - lastPoint.x) + POW2(point.y - lastPoint.y);
		
        if (a2b2 >= c2) {
            if (lineIntersectsRect(point, lastPoint, mapRect)){
                
                if (!path)
                    path = CGPathCreateMutable();
                
                if (needsMove){
                    CGPoint lastCGPoint = [self pointForMapPoint:lastPoint];
                    CGPathMoveToPoint(path, NULL, lastCGPoint.x, lastCGPoint.y);
                }
                
                BOOL shouldDrawSegment=cspoint.isWalking!=isDashed;
                
                CGPoint cgPoint = [self pointForMapPoint:point];
                
                if(shouldDrawSegment==YES){
                    CGPathMoveToPoint(path, NULL, cgPoint.x, cgPoint.y);
                }else{
                    CGPathAddLineToPoint(path, NULL, cgPoint.x, cgPoint.y);
                }
                
                
				segmentIndex++;
            }
            else
            {
                // discontinuity, lift the pen
                needsMove = YES;
            }
            lastPoint = point;
        }
    }
    
	#undef POW2
    
   
	CSPointVO *lastCSpoint=points.lastObject;
    point = lastCSpoint.mapPoint;
    if (lineIntersectsRect(lastPoint, point, mapRect)) {
		
        if (!path)
            path = CGPathCreateMutable();
		
        if (needsMove) {
            CGPoint lastCGPoint = [self pointForMapPoint:lastPoint];
            CGPathMoveToPoint(path, NULL, lastCGPoint.x, lastCGPoint.y);
        }
		
        BOOL shouldDrawSegment=lastCSpoint.isWalking!=isDashed;
		
		CGPoint cgPoint = [self pointForMapPoint:point];
		
		if(shouldDrawSegment==YES){
			CGPathMoveToPoint(path, NULL, cgPoint.x, cgPoint.y);
		}else{
			CGPathAddLineToPoint(path, NULL, cgPoint.x, cgPoint.y);
		}
    }
    
	NSLog(@"segmentcount=%i",segmentIndex);
    
    return path;
}





- (CGPathRef)ApplenewPathForPoints:(MKMapPoint *)points
                      pointCount:(NSUInteger)pointCount
                        clipRect:(MKMapRect)mapRect
                       zoomScale:(MKZoomScale)zoomScale
                     isDashed:(BOOL)isDashed
{
    // The fastest way to draw a path in an MKOverlayView is to simplify the
    // geometry for the screen by eliding points that are too close together
    // and to omit any line segments that do not intersect the clipping rect.  
    // While it is possible to just add all the points and let CoreGraphics 
    // handle clipping and flatness, it is much faster to do it yourself:
    //
    
    NSLog(@"%i",pointCount);
    
    if (pointCount < 2)
        return NULL;
    
    CGMutablePathRef path = NULL;
    
    BOOL needsMove = YES;
    
#define POW2(a) ((a) * (a))
    
    // Calculate the minimum distance between any two points by figuring out
    // how many map points correspond to MIN_POINT_DELTA of screen points
    // at the current zoomScale.
    double minPointDelta = MIN_POINT_DELTA / zoomScale;
    double c2 = POW2(minPointDelta);
    
    MKMapPoint point, lastPoint = points[0];
    NSUInteger i;
    int segmentIndex=0;
    for (i = 1; i < pointCount - 1; i++)
    {
        point = points[i];
        double a2b2 = POW2(point.x - lastPoint.x) + POW2(point.y - lastPoint.y);
        if (a2b2 >= c2) {
            if (lineIntersectsRect(point, lastPoint, mapRect)){
                
                if (!path) 
                    path = CGPathCreateMutable();
                
                if (needsMove){
                    CGPoint lastCGPoint = [self pointForMapPoint:lastPoint];
                    CGPathMoveToPoint(path, NULL, lastCGPoint.x, lastCGPoint.y);
                }
                
                BOOL dashed=segmentIndex%2==isDashed ? 1 :0;
                
                CGPoint cgPoint = [self pointForMapPoint:point];
                
                if(dashed==YES){
                    CGPathMoveToPoint(path, NULL, cgPoint.x, cgPoint.y);
                }else{
                    CGPathAddLineToPoint(path, NULL, cgPoint.x, cgPoint.y);
                }
                
                
                 segmentIndex++;
            }
            else
            {
                // discontinuity, lift the pen
                needsMove = YES;
            }
            lastPoint = point;
        }
    }
    
#undef POW2
    
    // If the last line segment intersects the mapRect at all, add it unconditionally
    point = points[pointCount - 1];
    if (lineIntersectsRect(lastPoint, point, mapRect))
    {
        if (!path)
            path = CGPathCreateMutable();
        if (needsMove)
        {
            CGPoint lastCGPoint = [self pointForMapPoint:lastPoint];
            CGPathMoveToPoint(path, NULL, lastCGPoint.x, lastCGPoint.y);
        }
        CGPoint cgPoint = [self pointForMapPoint:point];
        CGPathAddLineToPoint(path, NULL, cgPoint.x, cgPoint.y);
    }
    
     NSLog(@"segmentcount=%i",segmentIndex);
    
    return path;
}

@end
