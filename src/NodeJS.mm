#import "NodeJS.h"
#import <ev.h>
#import <node_stdio.h>

@interface NodeJS (Private)
+ (NodeJS*)sharedInstance;
@end

using namespace v8;

// acquire a pointer to an UTF-8 representation of |value|s
inline const char* ToCString(const v8::String::Utf8Value& value) {
  return *value ? *value : "<str conversion failed>";
}


static NSString *ExceptionToNSString(Local<Value> &er) {
  if (er.IsEmpty()) return [NSString stringWithString:@"undefined"];
  String::Utf8Value msg(!er->IsObject() ? er->ToString()
                                        : er->ToObject()->Get(
                                         String::New("message"))->ToString());
  return [NSString stringWithUTF8String:*msg];
}


static NSMutableDictionary* TryCatchToErrorDict(TryCatch &try_catch) {
  NSMutableDictionary* info = [NSMutableDictionary dictionary];
  v8::Handle<Message> message = try_catch.Message();
  if (!message.IsEmpty()) {
    String::Utf8Value filename(message->GetScriptResourceName());
    [info setObject:[NSString stringWithUTF8String:ToCString(filename)]
             forKey:@"filename"];
    [info setObject:[NSNumber numberWithInt:message->GetLineNumber()]
             forKey:@"lineno"];
    String::Utf8Value sourceline(message->GetSourceLine());
    [info setObject:[NSString stringWithUTF8String:ToCString(sourceline)]
             forKey:@"sourceline"];
  }
  String::Utf8Value trace(try_catch.StackTrace());
  if (trace.length() > 0) {
    [info setObject:[NSString stringWithUTF8String:*trace]
             forKey:NSLocalizedDescriptionKey];
  } else {
    // this really only happens for RangeErrors, since they're the only
    // kind that won't have all this info in the trace.
    Local<Value> er = try_catch.Exception();
    if (!er.IsEmpty())
      [info setObject:ExceptionToNSString(er) forKey:NSLocalizedDescriptionKey];
  }
  return info;
}

// Note: See NSError additions in NodeJS.h for useful helpers.

// ----------------------------------------------------------------------------

using namespace v8;

static Persistent<Context> gMainContext;
static int gTerminationState = 0; // 0=running, 1=exit-deferred, 2=exit-asap

// ev_run until no more queued events
static void PumpNode() {
  ev_now_update();  // Bring the clock forward since the last ev_run().
  ev_run(EV_DEFAULT_UC_ EVLOOP_NONBLOCK);
  while(ev_loop_fdchangecount() != 0) {
    ev_run(EV_DEFAULT_UC_ EVLOOP_NONBLOCK);
  }
}


// called when something is pending in node's I/O
static void KqueueCallback(CFFileDescriptorRef backendFile,
                           CFOptionFlags callBackTypes,
                           void* info) {
  PumpNode();
  CFFileDescriptorEnableCallBacks(backendFile, kCFFileDescriptorReadCallBack);
}


static Local<Value> _NodeEval(v8::Handle<String> source,
                              v8::Handle<String> name) {
  assert(!gMainContext.IsEmpty());
  //gMainContext->Enter();
  HandleScope scope;
  Local<v8::Script> script =
      v8::Script::Compile(source, name);
  Local<Value> result;
  if (!script.IsEmpty())
    result = script->Run();
  //gMainContext->Exit();
  return scope.Close(result);
}


// called when node has been setup and is about to enter its runloop
static void NodeMain(const Arguments& args) {
  // Keep a reference to the main module's context
  gMainContext = Persistent<Context>::New(Context::GetCurrent());

  // load main nib file if applicable
  NSBundle *mainBundle = [NSBundle mainBundle];
  if (mainBundle) {
    NSDictionary *info = [mainBundle infoDictionary];
    NSString *mainNibFile = [info objectForKey:@"NSMainNibFile"];
    if (mainNibFile)
      [NSBundle loadNibNamed:mainNibFile owner:NSApp];
  }

  // our app has finished its bootstrapping process. The following will cause
  // |NSApplicationWillFinishLaunchingNotification| and queue its "did"
  // counterpart which will be emitted on "next tick".
  [NSApp finishLaunching];
  //[NSApp activateIgnoringOtherApps:NO];
  //[NSApp setWindowsNeedUpdate:YES];
  
  // make sure the singleton NodeJS object is initialized (it will register
  // itself as the app delegate to handle graceful termination, etc).
  [NodeJS sharedInstance];
  
  // increase reference count (or: aquire our reference to the runloop). Matched
  // by a unref in [NodeJS terminate];
  ev_ref(EV_DEFAULT_UC);
  
  // Make sure the kqueue is initialized and the kernel state is up to date.
  // Note: This need to happen after app initialization (since it will
  // effectively perform one runloop iteration).
  PumpNode();
  
  // add node's I/O backend to the CFRunLoop as a runloop source
  int backendFD = ev_backend_fd();
  CFFileDescriptorRef backendFile =
      CFFileDescriptorCreate(NULL, backendFD, true, &KqueueCallback, NULL);
  CFRunLoopSourceRef backendRunLoopSource =
      CFFileDescriptorCreateRunLoopSource(NULL, backendFile, 0);
  CFRunLoopAddSource(CFRunLoopGetCurrent(), backendRunLoopSource,
                     kCFRunLoopDefaultMode);
  CFRelease(backendRunLoopSource);
  CFFileDescriptorEnableCallBacks(backendFile, kCFFileDescriptorReadCallBack);
  
  // main runloop
  while (ev_refcount(EV_DEFAULT_UC) && gTerminationState != 2) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    PumpNode();
    if (ev_refcount(EV_DEFAULT_UC) == 0)
      break;
    double next_waittime = ev_loop_next_waittime(EV_DEFAULT_UC);
    NSDate* next_date = [NSDate dateWithTimeIntervalSinceNow:next_waittime];
    //NSLog(@"Running a loop iteration with timeout %f", next_waittime);
    NSEvent* event = [NSApp nextEventMatchingMask:NSAnyEventMask
                            untilDate:next_date
                            inMode:NSDefaultRunLoopMode
                            dequeue:YES];
    if (event != nil) {  // event is nil on a timeout.
      //NSLog(@"Event: %@\n", event);
      [event retain];
      [NSApp sendEvent:event];
      [event release];
    }
    [pool drain];
  }
  //NSLog(@"exited from main runloop -- delegating to NSRunLoop...");
  
  // signal app termination and let the default runloop act on appkit cleanup
  [NSApp terminate:NSApp];
  [[NSRunLoop currentRunLoop] run];
}


// cf-aware memory allocator which uses the cf memory pool
//   alloc:   MemAlloc(NULL, long size)
//   realloc: MemAlloc(void *ptr, long size)
//   free:    MemAlloc(void *ptr, 0)
static void *MemAlloc(void *ptr, long size) {
  if (size)
    return CFAllocatorReallocate(kCFAllocatorDefault, ptr, (CFIndex)size, 0);
  CFAllocatorDeallocate(kCFAllocatorDefault, ptr);
  return NULL;
}


int NodeJSApplicationMain(int argc, const char** argv) {
  NSAutoreleasePool* pool = [NSAutoreleasePool new];
  
  // Make sure NSApp is initialized.
  [NSApplication sharedApplication];
  
  // Have node use our custom main
  node::Main = &NodeMain;
  
  // Have libev use our memory allocator
  ev_set_allocator(&MemAlloc);
  
  // Manipulate process.argv to contain main.js
  assert(argc >= 1);
  NSBundle* mainBundle = [NSBundle mainBundle];
  NSString* mainScriptPath = @"main.js";
  NSString* resourcePath = nil;
  if (mainBundle) {
    // Resolve absolute path to main.js if we are running in a bundle
    resourcePath = [mainBundle resourcePath];
    mainScriptPath =
        [resourcePath stringByAppendingPathComponent:mainScriptPath];
  }
  // TODO: create empty temporary file if |mainScriptPath| is missing.
  // Note: We need to load a module though, since we use some tricks enabled by
  // loading the main module in node.
  const char **argv2 = (const char **)MemAlloc(NULL, sizeof(char*)*argc+1);
  argv2[0] = argv[0];
  argv2[1] = [mainScriptPath UTF8String];
  for (int i = 1; i < argc; i++) {
    argv2[i+1] = argv[i];
  }
  
  // Tell node to load modules in separate contexts -- a trick to get access to
  // require() and friends. This works together with |gMainContext| in the way
  // that after the main module has loaded, node will export global "require",
  // "exports", "__filename", "__dirname" and "module" objects. These will then
  // be reachable by any code executing in the |gMainContext| context. See
  // implementation of [NodeJS eval:name:error:] for an example.
  setenv("NODE_MODULE_CONTEXTS", "1", 1);
  
  // set module search path to <mainbundle>/Contents/Resources/lib
  if (resourcePath) {
    // TODO: respect v8 arguments -- currently they are moved to after main.js
    //       thus not causing any effect.
    NSString *libPath = [resourcePath stringByAppendingPathComponent:@"lib"];
    char *node_path = getenv("NODE_PATH");
    if (node_path != NULL)
      libPath = [libPath stringByAppendingFormat:@":%s", node_path];
    setenv("NODE_PATH", [libPath UTF8String], 1);
  }
    
  // pass control over to node (we'll get control soon when NodeMain is called)
  int rc = node::Start(argc+1, (char**)argv2);
  
  // we will probably never get here
  MemAlloc(argv2, 0);
  [pool drain];
  return rc;
}

// ----------------------------------------------------------------------------

const NSString* NodeJSNSErrorDomain = @"node.js";

@implementation NSError (v8)

+ (NSError*)errorFromV8TryCatch:(TryCatch &)try_catch {
  NSMutableDictionary* info = nil;
  if (try_catch.HasCaught())
    info = TryCatchToErrorDict(try_catch);
  return [NSError errorWithDomain:NodeJSNSErrorDomain code:0 userInfo:info];
}

+ (NSError*)nodeErrorWithLocalizedDescription:(NSString*)description {
  return [NSError errorWithDomain:NodeJSNSErrorDomain code:0 userInfo:
              [NSDictionary dictionaryWithObject:description
                                          forKey:NSLocalizedDescriptionKey]];
}

@end


@implementation NodeJS
static NodeJS* sharedInstance_ = nil;

- (id)init {
  if ((self = [super init])) {
    // ...
  }
  return self;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)s {
  return [NodeJS gracefulShutdown];
}

+ (NodeJS*)sharedInstance { // private
  if (!sharedInstance_) {
    sharedInstance_ = [[self alloc] init];
    [NSApp setDelegate:sharedInstance_];
  }
  return sharedInstance_;
}

+ (NSApplicationTerminateReply)gracefulShutdown {
  if (!gTerminationState) {
    // release our reference to the node runloop, causing exit as soon as all
    // other events have been handled.
    ev_unref(EV_DEFAULT_UC);
    // defer termination if there are pending events
    if (ev_refcount(EV_DEFAULT_UC) > 0) {
      // TODO: emit "cocoaExit" event on process object
      gTerminationState = 1;
    } else {
      gTerminationState = 2;
    }
  } else {
    gTerminationState = 2;
  }
  return gTerminationState == 1 ? NSTerminateCancel : NSTerminateNow;
}

+ (int)registeredEvents {
  int n = ev_refcount(EV_DEFAULT_UC);
  if (!gTerminationState) n--; // don't count our own reference
  return n;
}

+ (Persistent<Context>)mainContext {
  return gMainContext;
}

static Persistent<String> process_symbol;

+ (Local<Object>)process {
  HandleScope scope;
  if (process_symbol.IsEmpty())
    process_symbol = NODE_PSYMBOL("process");
  Local<Value> process = gMainContext->Global()->Get(process_symbol);
  return scope.Close(Local<Object>::Cast(process));
}

/*+ (void)setHostObject:(NSObject*)hostObject {
  Local<Object> global = gMainContext->Global();
  Local<Object> process =
      Local<Object>::Cast(global->Get(String::NewSymbol("process")));
  if (!process.IsEmpty()) {
    Local<Object> host =
        Local<Object>::Cast(process->Get(String::NewSymbol("host")));
    if (!host.IsEmpty()) {
      NSObject* obj = (NSObject*)host->GetPointerFromInternalField(0);
      if (obj) [obj release];
    }
    host = [NodeJSProxy proxyForNSObject:hostObject
                       configuredByBlock:
    ^(v8::Handle<Template> proto_t, v8::Handle<ObjectTemplate> instance_t) {
      NSLog(@"in configuredByBlock");
    }];
    process->Set(String::NewSymbol("host"), host);
  }
}*/

+ (Local<v8::Script>)compile:(NSString*)source
                      origin:(NSString*)origin
                     context:(Context*)context
                       error:(NSError**)error {
  // compile script in the main module's context
  assert(!gMainContext.IsEmpty());
  gMainContext->Enter();
  if (context) context->Enter();
  HandleScope scope;
  TryCatch try_catch;
  
  // Compile
  Local<String> sourcestr = String::New([source UTF8String]);
  Local<v8::Script> script;
  if (origin) {
    script = Script::Compile(sourcestr, String::New([origin UTF8String]));
  } else {
    script = Script::Compile(sourcestr);
  }
  if (script.IsEmpty() && error) {
    if (try_catch.HasCaught()) {
      *error = [NSError errorFromV8TryCatch:try_catch];
      if (!try_catch.CanContinue()) {
        NSLog(@"fatal: %@", *error);
        exit(3);
      }
    } else {
      *error = [NSError nodeErrorWithLocalizedDescription:@"internal error"];
    }
  }
  
  // unroll contexts
  if (context) context->Exit();
  gMainContext->Exit();
  return scope.Close(script);
}

+ (Local<Value>)eval:(NSString*)source
              origin:(NSString*)origin
             context:(v8::Context*)context
               error:(NSError**)error {
  HandleScope scope;
  Local<Value> result;
  Local<v8::Script> script =
      [self compile:source origin:origin context:context error:error];
  if (!script.IsEmpty()) {
    TryCatch try_catch;
    result = script->Run();
    if (result.IsEmpty() && error) {
      *error = [NSError errorFromV8TryCatch:try_catch];
      if (try_catch.HasCaught() && !try_catch.CanContinue()) {
        NSLog(@"fatal: %@", *error);
        exit(3);
      }
    }
  }
  return scope.Close(result);
}

@end

// -----------------------------------------------------------------------------

/*class BlockInvocation {
 public:
  enum Type {
    VoidReturn = 1,
    HandleValueReturn = 2,
  };
  
  virtual ~BlockInvocation() {
    if (block_) {
      [(NodeJSFunctionBlock1)block_ release];
      block_ = NULL;
    }
  }
  
  inline Type type() { return type_; }
  inline void* block() { return block_; }
  
  Persistent<Function> handle_;
  
  static v8::Local<Function> New(NodeJSFunctionBlock1 block) {
    HandleScope scope;
    BlockInvocation* self = new BlockInvocation(block, VoidReturn);
    Persistent<Function> phandle;
    Local<FunctionTemplate> fun_t =
        FunctionTemplate::New(&Handler, External::Wrap(self));
    phandle = Persistent<Function>::New(fun_t->GetFunction());
    //assert(phandle->InternalFieldCount() > 0);
    //phandle->SetPointerInInternalField(0, self);
    phandle.MakeWeak(self, &WeakCallback);
    return scope.Close(phandle);
  }
  
  static v8::Handle<Value> Handler(const Arguments& args) {
    Local<Value> data = args.Data(); assert(!data.IsEmpty());
    BlockInvocation* ctx = (BlockInvocation*)External::Unwrap(data);
    switch (ctx->type()) {
      case BlockInvocation::VoidReturn:
        ((NodeJSFunctionBlock1)ctx->block())(args);
    }
    return Undefined();
  }
  
 protected:
  BlockInvocation(void* block, Type type) : block_(block)
                                             , type_(type) {
    // Note: block should be copied already, so we "steal" a reference.
  }
 
  void *block_;
  Type type_;
  
 private:
  static void WeakCallback(v8::Persistent<v8::Value> value, void *data) {
    NSLog(@"WeakCallback"); fflush(stderr);
    return;
    BlockInvocation *obj = static_cast<BlockInvocation*>(data);
    assert(value == obj->handle_);
    //assert(!obj->refs_);
    assert(value.IsNearDeath());
    delete obj;
  }
};*/

/*class NodeJSBlock : NodeJSFunctionWrap {
 public:
  enum Type {
    VoidReturn = 1,
    HandleValueReturn = 2,
  };
  
  static v8::Persistent<v8::FunctionTemplate> constructor_template;
  
  static void Initialize(v8::Handle<v8::Object> target);
  static v8::Handle<v8::Value> New (const v8::Arguments& args);
  static v8::Local<Function> Create(NodeJSFunctionBlock1 block);
  
  NodeJSBlock() : NodeJSFunctionWrap() {
    
  }
  
  virtual NodeJSBlock() {
    NSLog(@"~NodeJSBlock");
    if (block_) {
      [(NodeJSFunctionBlock1)block_ release];
      block_ = NULL;
    }
  }
  
  inline Type type() { return type_; }
  inline void* block() { return block_; }

 private:
  void *block;
  Type type;
};

v8::Handle<Value> NodeJSBlock::New (const Arguments& args) {
  if (!args.IsConstructCall()) {
    return FromConstructorTemplate(constructor_template, args);
  }
  HandleScope scope;

  NodeJSBlock *obj = new NodeJSBlock();
  obj->Wrap(args.Holder());

  return args.This();
}

v8::Local<Function> NodeJSBlock::Create(NodeJSFunctionBlock1 block) {
  HandleScope scope;

  Local<FunctionTemplate> t = FunctionTemplate::New(, External::Wrap(self));
  constructor_template = Persistent<FunctionTemplate>::New(t);
  constructor_template->InstanceTemplate()->SetInternalFieldCount(1);
  constructor_template->SetClassName(String::NewSymbol("NodeJSBlock"));
  
  Local<Function> function = constructor_template->GetFunction();
  Local<Object> instance = function->NewInstance();
}*/

/*typedef struct {
  void *block;
  int type;
} BlockCtx;

static v8::Handle<Value> Handler(const Arguments& args) {
  HandleScope scope;
  NSLog(@"! Handler");
  Local<Value> data = args.Data(); assert(!data.IsEmpty());
  BlockCtx* ctx = (BlockCtx*)External::Unwrap(data);
  switch (ctx->type) {
    case 1:
      ((NodeJSFunctionBlock1)ctx->block)(args);
  }
  return Undefined();
}

static void WeakCallback(v8::Persistent<v8::Value> value, void *data) {
  NSLog(@"! WeakCallback"); fflush(stderr);
  BlockCtx* ctx = (BlockCtx*)data;
  //assert(value == obj->handle_);
  //assert(!obj->refs_);
  assert(value.IsNearDeath());
  if (ctx->block) [(id)ctx->block release];
  delete ctx;
}

v8::Local<Function> NodeJS_function(NodeJSFunctionBlock1 block) {
  HandleScope scope;
  
  // ctx
  BlockCtx *ctx = new BlockCtx;
  ctx->block = [block copy];
  ctx->type = 1;
  
  // create a function
  Local<FunctionTemplate> t =
        FunctionTemplate::New(&Handler, External::Wrap(ctx));
  Local<Function> fun = t->GetFunction();
  
  // register for a "destroy" callback
  Persistent<Function> phandle = Persistent<Function>::New(fun);
  phandle.MakeWeak(ctx, &WeakCallback);
  
  return fun;
}*/

//namespace nodejs {
//typedef void (^FunctionBlockWithoutArgs)(void);
//typedef void (^FunctionBlockWithV8Args)(const v8::Arguments&);
//typedef v8::Local<v8::Value> (^FunctionBlockWithV8ArgsResult)(const v8::Arguments&);
//}
