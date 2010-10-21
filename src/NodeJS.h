#ifndef NODECOCOA_NODEJS_H_
#define NODECOCOA_NODEJS_H_

#import <NodeCocoa/node.h>

// Program entry point -- replaces use of NSApplicationMain
// You can utilize the NSApplication delegate method
// |applicationWillFinishLaunching:| to perform environment setup if needed.
int NodeJSApplicationMain(int argc, const char** argv);

#ifdef __OBJC__

// Objective-C++ interface to node.js
@interface NodeJS : NSObject {
}

// Initialize graceful shutdown.
//
// If there are pending events in node NSTerminateCancel is returned and the
// process will exit as soon as there are no more events on the node runloop.
//
// Note: calling this function a second time will cause immediate termination.
// 
+ (NSApplicationTerminateReply)gracefulShutdown;

// Returns the number of registered events currently in the node runloop.
+ (int)registeredEvents;

// The main v8 context.
+ (v8::Persistent<v8::Context>)mainContext;

// Objective-C object exposed as "process.host" in node
+ (v8::Local<v8::Object>)hostObject;
+ (void)setHostObject:(NSObject*)hostObject;

// Compile and run |script| identified by |name| passing |error|.
+ (v8::Local<v8::Value>)eval:(NSString*)script
                        name:(NSString*)name
                       error:(NSError**)error;

@end

#endif // __OBJC__
#endif // NODECOCOA_NODEJS_H_
