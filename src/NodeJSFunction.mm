#import "NodeJSFunction.h"
#import "NodeJS.h"
#import "NS-additions.h"

using namespace v8;

@implementation NodeJSFunction

+ (NodeJSFunction*)functionFromString:(NSString*)source
                               origin:(NSString*)origin
                              context:(v8::Context*)context
                                error:(NSError**)error {
  HandleScope scope;
  // prepare source
  source = [source stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (source.length == 0) {
    if (error)
      *error = [NSError nodeErrorWithLocalizedDescription:@"empty source"];
    return nil;
  }
  if ([source hasPrefix:@"function"]) {
    source = [NSString stringWithFormat:@"(%@)", source];
  }
  // Compile
  Local<Value> result =
      [NodeJS eval:source origin:origin context:context error:error];
  if (!result.IsEmpty()) {
    if (result->IsFunction()) {
      return [self functionWithFunction:Local<Function>::Cast(result)];
    }
    if (error) {
      *error = [NSError nodeErrorWithLocalizedDescription:
          @"CompileError: not a function"];
    }
  } // else: error set by |eval:origin:context:error:|
  return nil;
}


+ (NodeJSFunction*)functionFromString:(NSString*)source
                               origin:(NSString*)originName
                                error:(NSError**)error {
  return [self functionFromString:source origin:nil context:nil error:error];
}


+ (NodeJSFunction*)functionFromString:(NSString*)source error:(NSError**)error {
  return [self functionFromString:source origin:nil context:nil error:error];
}

+ (NodeJSFunction*)functionWithFunction:(v8::Local<v8::Function>)function {
  return [[[self alloc] initWithFunction:function] autorelease];
}

+ (NodeJSFunction*)functionWithCFunction:(v8::InvocationCallback)funptr {
  return [[[self alloc] initWithCFunction:funptr data:nil] autorelease];
}

+ (NodeJSFunction*)functionWithCFunction:(v8::InvocationCallback)funptr
                                    data:(void*)data {
  return [[[self alloc] initWithCFunction:funptr data:data] autorelease];
}

+ (NodeJSFunction*)functionWithBlock:(NodeJSFunctionBlock)block {
  return [[[self alloc] initWithBlock:block] autorelease];
}


- (id)initWithFunction:(v8::Local<v8::Function>)function {
  if ((self = [super init])) {
    assert(function_.IsEmpty());
    HandleScope scope;
    function_ = Persistent<Function>::New(function);
  }
  return self;
}


- (id)initWithCFunction:(v8::InvocationCallback)funptr data:(void*)data {
  if ((self = [super init])) {
    assert(function_.IsEmpty());
    HandleScope scope;
    Local<FunctionTemplate> t =
        FunctionTemplate::New(funptr, External::Wrap(data ? data:(void*)self));
    function_ = Persistent<Function>::New(t->GetFunction());
  }
  return self;
}


static v8::Handle<Value> _InvocationProxy(const Arguments& args) {
  Local<Value> data = args.Data();
  assert(!data.IsEmpty());
  NodeJSFunction* self = (NodeJSFunction*)External::Unwrap(data);
  assert(self->block_ != nil);
  return ((NodeJSFunctionBlock)self->block_)(args);
}


- (id)initWithBlock:(NodeJSFunctionBlock)block {
  if ((self = [super init])) {
    assert(function_.IsEmpty());
    assert(block_ == nil);
    HandleScope scope;
    block_ = [block copy];
    Local<FunctionTemplate> t =
        FunctionTemplate::New(_InvocationProxy, External::Wrap(self));
    function_ = Persistent<Function>::New(t->GetFunction());
  }
  return self;
}


- (void)dealloc {
  if (!function_.IsEmpty()) {
    function_.Dispose();
    function_.Clear();
  }
  if (block_) {
    [block_ release];
    block_ = nil;
  }
  [super dealloc];
}


- (v8::Persistent<v8::Function>)function {
  return function_;
}


// NSObject v8 additions implementation
- (v8::Local<v8::Value>)v8Value {
  HandleScope scope;
  return scope.Close(Local<Value>(*function_));
}


- (v8::Local<v8::Value>)callWithV8Arguments:(v8::Handle<v8::Value> [])argv
                                      count:(int)argc
                                 thisObject:(v8::Local<v8::Object>)thisObject
                                      error:(NSError**)error {
  assert(!function_.IsEmpty());
  HandleScope scope;
  TryCatch try_catch;
  if (thisObject.IsEmpty()) {
    thisObject = Local<Object>(*function_);
  } else if (!thisObject->IsObject()) {
    if (error) {
      *error = [NSError nodeErrorWithLocalizedDescription:
          @"thisObject is not an object"];
    }
    return Local<Value>();
  }
  Local<Value> result = function_->Call(thisObject, argc, argv);
  if (result.IsEmpty() && error)
    *error = [NSError errorFromV8TryCatch:try_catch];
  return scope.Close(result);
}


- (v8::Local<v8::Value>)callWithV8Arguments:(v8::Handle<v8::Value> [])argv
                                      count:(int)argc
                                      error:(NSError**)error {
  return [self callWithV8Arguments:argv
                             count:argc
                        thisObject:Local<Object>(*function_)
                             error:error];
}


- (v8::Local<v8::Value>)callWithThisObject:(v8::Local<v8::Object>)thisObject
                                     error:(NSError**)error {
  return [self callWithV8Arguments:NULL
                             count:0
                        thisObject:thisObject
                             error:error];
}


- (v8::Local<v8::Value>)callAndSetError:(NSError**)error {
  return [self callWithV8Arguments:NULL
                             count:0
                        thisObject:Local<Object>(*function_)
                             error:error];
}


- (v8::Local<v8::Value>)call {
  HandleScope scope;
  NSError *error = nil;
  Local<Value> r = [self callWithV8Arguments:NULL
                                       count:0
                                  thisObject:Local<Object>(*function_)
                                       error:&error];
  if (r.IsEmpty())
    NSLog(@"error in %s: %@", __PRETTY_FUNCTION__, error);
  return scope.Close(r);
}


- (NSString*)description {
  if (!function_.IsEmpty())
    return [NSString stringWithV8String:function_->ToString()];
  else
    return [[NSNull null] description];
}

@end
