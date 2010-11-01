#import <Cocoa/Cocoa.h>
#import <NodeCocoa/NodeCocoa.h>

int main(int argc, char *argv[]) {
  NSAutoreleasePool* pool = [NSAutoreleasePool new];
  [NodeJSThread detachNewNodeJSThreadRunningScript:@"main.js"];
  return NSApplicationMain(argc, (const char **)argv);
  [pool drain];
}
