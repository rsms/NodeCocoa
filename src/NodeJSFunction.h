#import <NodeCocoa/node.h>

typedef v8::Handle<v8::Value> (^NodeJSFunctionBlock)(const v8::Arguments& args);

@interface NodeJSFunction : NSObject {
  v8::Persistent<v8::Function> function_;
  id block_;
}

@property(nonatomic, readonly) v8::Persistent<v8::Function> function;

/**
 * Create a new function by compiling JavaScript |source|, passing any errors in
 * |error|.
 *
 * Examples:
 *
 *   functionFromString:@"function name(x, y) { return x * y }"
 *   functionFromString:@"function (arg1) { return arg1+'.bar' }"
 *   functionFromString:@"require('util').log"
 *
 * @param source    JavaScript source (a function definition).
 * @param origin    Optional identifier (e.g. filename).
 * @param context   An optional custom context in which to compile the function.
 * @param error     Optional output-pointer, providing error information. No
 *                  matter if this is |nil| or not, you should always check
 *                  the returned handle's |IsEmpty()| method for success.
 */
+ (NodeJSFunction*)functionFromString:(NSString*)source
                               origin:(NSString*)origin
                              context:(v8::Context*)context
                                error:(NSError**)error;

/// Convenience: passing |nil| for |context|.
+ (NodeJSFunction*)functionFromString:(NSString*)source
                               origin:(NSString*)origin
                                error:(NSError**)error;

/// Convenience: passing |nil| for |origin| and |context|.
+ (NodeJSFunction*)functionFromString:(NSString*)source error:(NSError**)error;

// See the "init" instance methods for details regarding the following
// convenience methods.
+ (NodeJSFunction*)functionWithFunction:(v8::Local<v8::Function>)function;
+ (NodeJSFunction*)functionWithCFunction:(v8::InvocationCallback)funptr;
+ (NodeJSFunction*)functionWithBlock:(NodeJSFunctionBlock)block;

/// Function based on a V8 function.
- (id)initWithFunction:(v8::Local<v8::Function>)function;

/**
 * Function based on a C function.
 *
 * This is a thin wrapper around the standard V8 API where a FunctionTemplate is
 * created, referencing |funptr| and passing |data| as External data, then
 * returning the resulting function from template->GetFunction().
 *
 * Example:
 *
 *   static v8::Handle<v8::Value> Foo(const v8::Arguments& args) {
 *     FooObj *obj = (FooObj*)v8::External::Unwrap(args.Data());
 *     // do something useful here
 *     return v8::Undefined();
 *   }
 *   FooObj *obj = [[FooObj alloc] init];
 *   NodeJSFunction *fun =
 *       [[NodeJSFunction alloc] initWithCFunction:&Foo data:obj];
 *   [fun call...
 *
 * If you pass |nil| to |data|, the NodeJSFunction instance (aka "self") will be
 * used as |data|.
 */
- (id)initWithCFunction:(v8::InvocationCallback)funptr data:(void*)data;

/**
 * Function based on a C block.
 *
 * Block-based functions are suitable for functions which live for the duration
 * of the process life time (i.e. statically allocated) and for quick throw-away
 * uses.
 *
 * Example of a process-life-time block function which is lazily allocated:
 *
 *   static NodeJSFunction *fun = nil;
 *   if (!fun) {
 *     fun = [[NodeJSFunction alloc] initWithBlock:^(const Arguments& args){
 *       HandleScope scope;
 *       // do something useful here
 *       return v8::Handle<v8::Value>(scope.Close(Undefined()));
 *     }];
 *   }
 *   [fun call...
 *   // fun will live on and be valid until released or the program terminates.
 *
 * Example of a temporary throw-away block function:
 *
 *   NodeJSFunction *fun =
 *       [NodeJSFunction functionWithBlock:^(const Arguments& args){
 *     HandleScope scope;
 *     // do something useful here
 *     return v8::Handle<v8::Value>(scope.Close(Undefined()));
 *   }];
 *   [fun call];
 *   // here, fun will be autoreleased when returning, thus is no longer valid.
 *
 * Blocks are _not_ very suitable for being used as event callbacks or otherwise
 * passed into JavaScript-land where we have no control. Doing so might lead to
 * memory leaks and/or hard-to-debug segmentation violations.
 *
 * Example of a one-shot callback block:
 *
 *   __block NodeJSFunction *callback;
 *   callback = [[NodeJSFunction alloc] initWithBlock:^(const Arguments& args){
 *     HandleScope scope;
 *     Local<Value> result = Local<Value>::New(Undefined());
 *     // your code here, which possibly sets |result|
 *     [callback release];
 *     return v8::Handle<v8::Value>(scope.Close(result));
 *   }];
 *   v8::Local<Value> argv[] = { callback.v8Value };
 *   [someAsyncFunc callWithV8Arguments:argv count:1 error:nil];
 *
 * Once again, in the above use case it's not recommended to use blocks. If you
 * need coupling with C-land, go with |initWithCFunction:|, otherwise use
 * |functionFromString:..|.
 */
- (id)initWithBlock:(NodeJSFunctionBlock)block;

/**
 * Invoke the function, passing v8 arguments.
 *
 * @param argv        Argument values.
 * @param argc        Number of arguments.
 * @param thisObject  Object referred to as "this" within the function body.
 * @param error       Optional output-pointer, providing error information. No
 *                    matter if this is |nil| or not, you should always check
 *                    the returned handle's |IsEmpty()| method for success.
 * Returns the return value from the function.
 */
- (v8::Local<v8::Value>)callWithV8Arguments:(v8::Handle<v8::Value> [])argv
                                      count:(int)argc
                                 thisObject:(v8::Local<v8::Object>)thisObject
                                      error:(NSError**)error;

/// Convenience: No |thisObject| (will use a built-in default object).
- (v8::Local<v8::Value>)callWithV8Arguments:(v8::Handle<v8::Value> [])argv
                                      count:(int)argc
                                      error:(NSError**)error;

/// Convenience: No arguments.
- (v8::Local<v8::Value>)callWithThisObject:(v8::Local<v8::Object>)thisObject
                                     error:(NSError**)error;

/// Convenience: No arguments and no |thisObject|.
- (v8::Local<v8::Value>)callAndSetError:(NSError**)error;

/// Convenience: No arguments and no |thisObject| (errors printed to stderr).
- (v8::Local<v8::Value>)call;

@end
