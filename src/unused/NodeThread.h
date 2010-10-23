#import <node.h>
#include <libkern/OSAtomic.h>
//extern v8::Persistent<v8::Object> gNodeProcessHost;

typedef void (^NodeThreadCallback)(NSError *err, id result);

@interface NodeThread : NSThread {
  NSString *scriptPath_;
  ev_async dequeueInputNotifier_;
 @public
  OSQueueHead inputQueue_;
  OSQueueHead outputQueue_;
  v8::Persistent<v8::Object> nodeProcessHost_;
}

+ (NodeThread*)mainNodeThread;
+ (void)setNodeSearchPaths:(NSArray*)paths;
+ (NodeThread*)detachNewNodeThreadRunningScript:(NSString *)scriptPath;
+ (NodeThread*)detachNewNodeThreadRunningScript:(NSString *)scriptPath
                                withSearchPaths:(NSArray *)searchPaths;

- (id)initWithScriptPath:(NSString *)scriptPath;

- (void)invoke:(NSString*)functionName args:(NSArray*)args callback:(id)callback;
- (void)emit:(NSString *)name;
- (void)emit:(NSArray*)args callback:(NodeThreadCallback)callback;

@end
