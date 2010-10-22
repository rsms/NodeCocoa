#import <NodeCocoa/node.h>

// A cocoa wrapper for a v8::Script object
@interface NodeJSScript : NSObject {
  v8::Persistent<v8::Script> script_;
}

/// Compile a script from JavaScript source code
+ (NodeJSScript*)compiledScriptFromSource:(NSString*)source
                                   origin:(NSString*)origin
                                  context:(v8::Context*)context
                                    error:(NSError**)error;

/// Convenience: No |origin| or |context|.
+ (NodeJSScript*)compiledScriptFromSource:(NSString*)source
                                    error:(NSError**)error;

/// Convenience: No |origin| or |context| (errors printed to stderr).
+ (NodeJSScript*)compiledScriptFromSource:(NSString*)source;

/// Initialize with a V8 script object
- (id)initWithScript:(v8::Local<v8::Script>)script;

/// Run/execute the script, passing errors in |error|, returning the result.
- (v8::Local<v8::Value>)run:(NSError**)error;

@end
