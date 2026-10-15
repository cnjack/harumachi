// Temporary visual-test display; no persistent display settings or application activation.
// API declarations cross-checked against Chromium's macOS virtual display test utility:
// https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
@interface CGVirtualDisplayDescriptor : NSObject
@property(strong) NSString *name;
@property unsigned int maxPixelsWide,maxPixelsHigh,vendorID,productID,serialNum,serialNumber;
@property CGSize sizeInMillimeters;
@property CGPoint redPrimary,greenPrimary,bluePrimary,whitePoint;
@property(strong) id queue;
@end
@interface CGVirtualDisplayMode : NSObject
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property unsigned int hiDPI,rotation;
@property(strong) NSArray *modes;
@end
@interface CGVirtualDisplay : NSObject
- (id)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(readonly) unsigned int displayID;
@end
int main(void) {
 @autoreleasepool {
  Class descriptorClass=NSClassFromString(@"CGVirtualDisplayDescriptor");
  if (!descriptorClass) { fprintf(stderr,"Virtual display API unavailable\n");return 2; }
  CGDirectDisplayID existing[32];uint32_t count=0;CGGetActiveDisplayList(32,existing,&count);
  int x=0;for(uint32_t i=0;i<count;i++){CGRect b=CGDisplayBounds(existing[i]);x=MAX(x,(int)CGRectGetMaxX(b));}
  CGVirtualDisplayDescriptor *desc=[[descriptorClass alloc] init];
  desc.name=@"Harumachi isolated visual QA";desc.maxPixelsWide=1600;desc.maxPixelsHigh=1000;
  desc.vendorID=505;desc.productID=2026;desc.serialNum=101501;desc.serialNumber=101501;
  desc.sizeInMillimeters=CGSizeMake(400,250);desc.queue=dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0);
  desc.redPrimary=CGPointMake(.6797,.3203);desc.greenPrimary=CGPointMake(.2559,.6983);
  desc.bluePrimary=CGPointMake(.1494,.0557);desc.whitePoint=CGPointMake(.3125,.3291);
  CGVirtualDisplay *display=[[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:desc];
  if(!display){fprintf(stderr,"Virtual display creation unavailable\n");return 3;}
  CGVirtualDisplaySettings *settings=[[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
  settings.hiDPI=0;settings.rotation=0;
  CGVirtualDisplayMode *mode=[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:1600 height:1000 refreshRate:60];
  settings.modes=@[mode];if(![display applySettings:settings])return 4;
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
  CGDisplayConfigRef config;CGBeginDisplayConfiguration(&config);
  CGConfigureDisplayMirrorOfDisplay(config,display.displayID,kCGNullDirectDisplay);
  CGConfigureDisplayOrigin(config,display.displayID,x+80,0);
  CGError configured=CGCompleteDisplayConfiguration(config,kCGConfigureForSession);
  if(configured!=kCGErrorSuccess)fprintf(stderr,"Origin configuration returned %d; use active default bounds\n",configured);
  if(!CGDisplayIsActive(display.displayID)||CGDisplayIsInMirrorSet(display.displayID))return 5;
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
  CGRect bounds=CGDisplayBounds(display.displayID);int screen=-1,index=0;
  for(NSScreen *s in [NSScreen screens]){if([s.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==display.displayID)screen=index;index++;}
  NSDictionary *result=@{@"id":@(display.displayID),@"screen":@(screen),@"x":@((int)bounds.origin.x),@"y":@((int)bounds.origin.y),@"width":@((int)bounds.size.width),@"height":@((int)bounds.size.height),@"temporary":@YES};
  NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
  fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);fflush(stdout);
  // The parent keeps this process alive while its own render windows exist.
  // Closing stdin releases the only strong display reference and removes it.
  getchar();(void)display.displayID;
 }
 return 0;
}
