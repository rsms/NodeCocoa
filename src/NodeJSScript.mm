#import "NodeJSScript.h"
#import "NodeJS.h"

using namespace v8;

@implementation NodeJSScript

+ (NodeJSScript*)scriptWithScript:(Local<v8::Script>)script {
  return [[[NodeJSScript alloc] initWithScript:script] autorelease];
}

+ (NodeJSScript*)compiledScriptFromSource:(NSString*)source
                                   origin:(NSString*)origin
                                  context:(v8::Context*)context
                                    error:(NSError**)error {
  HandleScope scope;
  Local<v8::Script> script =
      [NodeJS compile:source origin:origin context:context error:error];
  if (!script.IsEmpty())
    return [NodeJSScript scriptWithScript:script];
  return nil;
}


+ (NodeJSScript*)compiledScriptFromSource:(NSString*)source
                                    error:(NSError**)error {
  return [self compiledScriptFromSource:source
                                 origin:nil
                                context:nil
                                  error:error];
}

// If an error occurs, it will be logged to stderr.
+ (NodeJSScript*)compiledScriptFromSource:(NSString*)source {
  NSError* error = nil;
  NodeJSScript* obj = [self compiledScriptFromSource:source
                                              origin:nil
                                             context:nil
                                               error:&error];
  if (!obj && error)
    NSLog(@"%s %@", __PRETTY_FUNCTION__, error);
  return obj;
}


- (id)initWithScript:(v8::Local<v8::Script>)script {
  if ((self = [super init])) {
    script_ = Persistent<Script>::New(script);
  }
  return self;
}


- (void)dealloc {
  if (!script_.IsEmpty()) {
    script_.Dispose();
    script_.Clear();
  }
  [super dealloc];
}


- (v8::Local<v8::Value>)run:(NSError**)error {
  HandleScope scope;
  TryCatch try_catch;
  Local<Value> result = script_->Run();
  if (result.IsEmpty() && error)
    *error = [NSError errorFromV8TryCatch:try_catch];
  return scope.Close(result);
}

@end
