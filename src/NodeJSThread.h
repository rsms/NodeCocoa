#import <NodeCocoa/node.h>
#import <libkern/OSAtomic.h>

@class NodeJSThread;

typedef void (^NodeJSCallbackBlock)(void (^block)(void));
typedef void (^NodeJSPerformBlock)(NodeJSCallbackBlock);

namespace nodejs {

// Input/Output queue entry
class PerformEntry {
 public:
  PerformEntry(NodeJSPerformBlock block);
  ~PerformEntry();
  void Perform();
  
  PerformEntry *next_;
 protected:
  NodeJSPerformBlock performBlock_;
  CFRunLoopRef originRunloop_;
};

}; // namespace nodejs


// ----------------------------------------------------------------------------

@interface NodeJSThread : NSThread {
  NSString *scriptPath_;
  NSArray *searchPaths_;
  v8::Persistent<v8::Context> mainContext_;
  ev_async inputQueueNotifier_;
 @public
  OSQueueHead inputQueue_;
  OSQueueHead outputQueue_;
}

@property(readonly) NSString *scriptPath;
@property(readonly) NSArray *searchPaths;
@property(readonly) const v8::Persistent<v8::Context> &mainContext;

/// Convenience method
+ (NodeJSThread*)detachNewNodeJSThreadRunningScript:(NSString*)filename;

/// Returns the oldest node.js thread still alive or nil if none
+ (NodeJSThread*)mainNodeJSThread;

/// Initialize a Node.js thread running script at |filename|.
- (id)initWithScriptPath:(NSString*)filename searchPaths:(NSArray*)paths;

/// Execute |block| in this thread, with an optional return callback
- (void)performBlock:(NodeJSPerformBlock)block;

/// Export |func| in the global scope as |name|.
- (void)exportGlobalFunction:(v8::InvocationCallback)func as:(NSString*)name;

@end
