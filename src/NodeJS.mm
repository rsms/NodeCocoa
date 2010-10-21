#import "NodeJS.h"
#import <ev.h>
#import <node_stdio.h>
#import "NodeJSProxy.h"

@interface NodeJS (Private)
+ (NodeJS*)sharedInstance;
@end

using namespace v8;

// acquire a pointer to an UTF-8 representation of |value|s
inline const char* ToCString(const v8::String::Utf8Value& value) {
  return *value ? *value : "<str conversion failed>";
}

// This function come from the Node.js project. Please see deps/node/LICENSE.
static void ReportException(TryCatch &try_catch, bool show_line) {
  v8::Handle<Message> message = try_catch.Message();

  node::Stdio::DisableRawMode(STDIN_FILENO);
  fprintf(stderr, "\n");

  if (show_line && !message.IsEmpty()) {
    // Print (filename):(line number): (message).
    String::Utf8Value filename(message->GetScriptResourceName());
    const char* filename_string = ToCString(filename);
    int linenum = message->GetLineNumber();
    fprintf(stderr, "%s:%i\n", filename_string, linenum);
    // Print line of source code.
    String::Utf8Value sourceline(message->GetSourceLine());
    const char* sourceline_string = ToCString(sourceline);

    // HACK HACK HACK
    //
    // FIXME
    //
    // Because of how CommonJS modules work, all scripts are wrapped with a
    // "function (function (exports, __filename, ...) {"
    // to provide script local variables.
    //
    // When reporting errors on the first line of a script, this wrapper
    // function is leaked to the user. This HACK is to remove it. The length
    // of the wrapper is 62. That wrapper is defined in src/node.js
    //
    // If that wrapper is ever changed, then this number also has to be
    // updated. Or - someone could clean this up so that the two peices
    // don't need to be changed.
    //
    // Even better would be to get support into V8 for wrappers that
    // shouldn't be reported to users.
    int offset = linenum == 1 ? 62 : 0;

    fprintf(stderr, "%s\n", sourceline_string + offset);
    // Print wavy underline (GetUnderline is deprecated).
    int start = message->GetStartColumn();
    for (int i = offset; i < start; i++) {
      fprintf(stderr, " ");
    }
    int end = message->GetEndColumn();
    for (int i = start; i < end; i++) {
      fprintf(stderr, "^");
    }
    fprintf(stderr, "\n");
  }

  String::Utf8Value trace(try_catch.StackTrace());

  if (trace.length() > 0) {
    fprintf(stderr, "%s\n", *trace);
  } else {
    // this really only happens for RangeErrors, since they're the only
    // kind that won't have all this info in the trace.
    Local<Value> er = try_catch.Exception();
    String::Utf8Value msg(!er->IsObject() ? er->ToString()
                         : er->ToObject()->Get(String::New("message"))->ToString());
    fprintf(stderr, "%s\n", *msg);
  }

  fflush(stderr);
}


static NSString *ExceptionToNSString(Local<Value> &er) {
  if (er.IsEmpty()) return [NSString stringWithString:@"undefined"];
  String::Utf8Value msg(!er->IsObject() ? er->ToString()
                                        : er->ToObject()->Get(
                                         String::New("message"))->ToString());
  return [NSString stringWithUTF8String:*msg];
}


static NSMutableDictionary* TryCatchToErrorDict(TryCatch &try_catch) {
  v8::Handle<Message> message = try_catch.Message();
  NSMutableDictionary* info = [NSMutableDictionary dictionary];
  if (!message.IsEmpty()) {
    String::Utf8Value filename(message->GetScriptResourceName());
    [info setObject:[NSString stringWithUTF8String:ToCString(filename)]
             forKey:@"filename"];
    [info setObject:[NSNumber numberWithInt:message->GetLineNumber()]
             forKey:@"lineno"];
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

static NSError *NSErrorFromV8TryCatch(TryCatch &try_catch) {
  NSMutableDictionary* info = nil;
  if (try_catch.HasCaught())
    info = TryCatchToErrorDict(try_catch);
  return [NSError errorWithDomain:@"node" code:0 userInfo:info];
}


// ----------------------------------------------------------------------------

using namespace v8;

static Persistent<Context> gMainContext;
static int gTerminationState = 0; // 0=running, 1=exit-deferred, 2=exit-asap

// ev_loop until no more queued events
static void PumpNode() {
  ev_now_update();  // Bring the clock forward since the last ev_loop().
  ev_loop(EV_DEFAULT_UC_ EVLOOP_NONBLOCK);
  while(ev_loop_fdchangecount() != 0) {
    ev_loop(EV_DEFAULT_UC_ EVLOOP_NONBLOCK);
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


// objcSendMessage(target, "errorWithMessage:code:", "A message", 123)
static v8::Handle<Value> host_objcSendMessage(const Arguments& args) {
  HandleScope scope;
  
  /*if (args.Length() < 1 || !args[0]->IsString()) {
    return ThrowException(Exception::Error(String::New("Bad argument")));
  }
  
  String::Utf8Value selectorSignature(args[0]->ToString());
  
  SEL sel = sel_registerName(*selectorSignature);*/
  
  return Undefined();
}


// called when node has been setup and is about to enter its runloop
static void NodeMain(const Arguments& args) {
  NSLog(@"NodeMain");
  
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
  
  // set/extend module search path to <bundle>/Contents/Resources/lib
  if (resourcePath) {
    NSString *libPath = [resourcePath stringByAppendingPathComponent:@"lib"];
    char *node_path = getenv("NODE_PATH");
    if (node_path != NULL)
      libPath = [libPath stringByAppendingFormat:@":%s", node_path];
    setenv("NODE_PATH", [libPath UTF8String], 1);
  }
    
  // pass control over to node (we'll get control soon when NodeMain is called)
  int rc = node::Start(argc+1, (char**)argv2);
  
  // we will probably never get here
  free(argv2);
  [pool drain];
  return rc;
}

// ----------------------------------------------------------------------------

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

+ (Local<Object>)hostObject {
  // process.host
  Local<Object> global = gMainContext->Global();
  Local<Object> process =
      Local<Object>::Cast(global->Get(String::NewSymbol("process")));
  if (!process.IsEmpty()) {
    Local<Value> v = process->Get(String::NewSymbol("host"));
    assert(v->IsObject());
    return Local<Object>::Cast(v);
  }
  return Local<Object>();
}

+ (void)setHostObject:(NSObject*)hostObject {
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
}

+ (Local<Value>)eval:(NSString*)source
                name:(NSString*)name
               error:(NSError**)error {
  
  // compile script in the main module's context
  assert(!gMainContext.IsEmpty());
  gMainContext->Enter();
  HandleScope scope;
  
  TryCatch try_catch;
  
  // Compile
  Local<v8::Script> script = v8::Script::Compile(
      String::New([source UTF8String]),
      name ? String::New([name UTF8String])
           : String::NewSymbol("<string>"));
  Local<Value> result;
  if (script.IsEmpty()) {
    if (try_catch.HasCaught()) {
      *error = NSErrorFromV8TryCatch(try_catch);
    } else {
      *error = [NSError errorWithDomain:@"node" code:0 userInfo:
          [NSDictionary dictionaryWithObject:@"internal error"
                                      forKey:NSLocalizedDescriptionKey]];
    }
  } else {
    // Execute script
    result = script->Run();
    if (result.IsEmpty()) {
      *error = NSErrorFromV8TryCatch(try_catch);
    }
  }
  
  gMainContext->Exit();
  return scope.Close(result);
}

@end
