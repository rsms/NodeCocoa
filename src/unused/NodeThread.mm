#import "NodeThread.h"
#import "NS+node.h"
#import "JSON.h"
#import <ChromiumTabs/common.h>
#import <node.h>
#import <node_events.h>
#import <node_stdio.h>
#import <node_buffer.h>

using namespace v8;

// FIXME: this means only one thread can run
static v8::Persistent<v8::Function> gJSONStringify; // JSON.stringify

inline const char* ToCString(const v8::String::Utf8Value& value) {
  return *value ? *value : "<str conversion failed>";
}

static inline Persistent<Object>* PersistObject(const Local<Value> &v) {
  Persistent<Object> *o = new Persistent<Object>();
  *o = Persistent<Object>::New(Local<Object>::Cast(v));
  return o;
}

static inline Persistent<Object>* UnwrapPersistentObject(void *data) {
  return reinterpret_cast<Persistent<Object>*>(data);
}

// called when node has been setup and is about to enter its runloop
static v8::Handle<v8::Value> _ProcessStartCallback(const v8::Arguments& args) {
  HandleScope scope;
  
  // Create process.host
  Local<FunctionTemplate> t = FunctionTemplate::New();
  node::EventEmitter::Initialize(t);
  Local<Object> processHost = t->GetFunction()->NewInstance();
  
  // Setup process.host
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
  processHost->Set(String::NewSymbol("bundlePath"),
                   String::New([bundlePath UTF8String]));
  
  // Export process.host
  Local<Object> global = Context::GetCurrent()->Global();
  Local<Value> process_v = global->Get(String::NewSymbol("process"));
  Local<Object> process = Local<Object>::Cast(process_v);
  process->Set(String::NewSymbol("host"), processHost);
  
  // Save in thread-local storage
  NSMutableDictionary* tinfo = [[NSThread currentThread] threadDictionary];
  Persistent<Object> *funptr = PersistObject(processHost);
  [tinfo setObject:[NSValue valueWithPointer:funptr]
            forKey:@"node.process.host"];
  
  // JSON
  Local<Script> script = Script::New(String::New("JSON.stringify"));
  Local<Value> JSON_stringify_v = script->Run();
  assert(JSON_stringify_v->IsFunction());
  gJSONStringify =
      Persistent<Function>::New(Local<Function>::Cast(JSON_stringify_v));
  
  return Undefined();
}


// Input/Output queue entry
struct IOQueueEntry {
  NSString* functionName;
  union {
    NSArray* args;
    id result;
  };
  NSError *error; // carries error from invocation (i.e. when in outputQueue_)
  id callback;
  struct IOQueueEntry *next;
  __weak NodeThread* nodeThread;
};


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


static NSDictionary *TryCatchToErrorDict(TryCatch &try_catch) {
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
    [info setObject:ExceptionToNSString(er) forKey:NSLocalizedDescriptionKey];
  }
  return info;
}


static void AssignErrorDictToEntry(NSDictionary* einfo, IOQueueEntry* entry) {
  id old = entry->error;
  entry->error = [NSError errorWithDomain:@"node" code:0 userInfo:einfo];
  [entry->error retain];
  if (old) [old release];
}

static void AssignExceptionToEntry(Local<Value> &er, IOQueueEntry* entry) {
  NSDictionary* einfo =
      [NSDictionary dictionaryWithObject:ExceptionToNSString(er)
                                  forKey:NSLocalizedDescriptionKey];
  AssignErrorDictToEntry(einfo, entry);
}

static void AssignTryCatchToEntry(TryCatch &try_catch, IOQueueEntry* entry) {
  NSDictionary* einfo = TryCatchToErrorDict(try_catch);
  AssignErrorDictToEntry(einfo, entry);
}


static void EnqueueOutput(IOQueueEntry* entry) {
  // Enqueue output
  OSAtomicEnqueue(&entry->nodeThread->outputQueue_, entry,
                  offsetof(struct IOQueueEntry, next));
  
  // Ask main thread to execute a block, taking care of callback invocation
  CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
    // Invoke callback
    NodeThreadCallback callback = entry->callback;
    callback(entry->error, entry->result);
    // Dispose of entry
    if (entry->functionName) [entry->functionName release];
    if (entry->error) [entry->error release];
    if (entry->result) [entry->result release];
    if (entry->callback) [entry->callback release];
    CFAllocatorDeallocate(NULL, entry);
  });
}


static NSObject *NSObjectFromV8Value(Local<Value> &v) {
  NSObject *obj = nil;
  if (v.IsEmpty() || v->IsNull() || v->IsUndefined() || v->IsExternal()) {
    return [NSNull null];
  }
  if (v->IsBoolean()) return [NSNumber numberWithBool:v->BooleanValue()];
  if (v->IsInt32())   return [NSNumber numberWithInt:v->Int32Value()];
  if (v->IsUint32())  return [NSNumber numberWithUnsignedInt:v->Uint32Value()];
  if (v->IsNumber())  return [NSNumber numberWithDouble:v->NumberValue()];
  if (v->IsString()) {
    String::Utf8Value utf8(v);
    return [NSString stringWithUTF8String:ToCString(utf8)];
  }
  
  // Node Buffers
  if (v->IsObject() && node::Buffer::HasInstance(v)) {
    Local<Object> bufobj = v->ToObject();
    char* data = node::Buffer::Data(bufobj);
    size_t length = node::Buffer::Length(bufobj);
    return [NSData dataWithBytes:data length:length];
  }
  
  // Objects, Arrays and Functions are transcoded as JSON
  // TODO: optimized implementation
  Local<Value> str_v = gJSONStringify->Call(gJSONStringify, 1, &v);
  assert(str_v->IsString());
  String::Utf8Value utf8(str_v);
  const char *pch = *utf8;
  if (pch) {
    return [[NSString stringWithUTF8String:pch] JSONValue];
  } else {
    // TODO: Maybe raise an error since we failed to read the string?
    return [NSNull null];
  }
}


static v8::Handle<Value> CallbackProxy(const Arguments& args) {
  HandleScope scope;
  Local<Value> data_v = args.Data();
  //assert(data_v->IsExternal()); // v8 bug
  IOQueueEntry* entry = (IOQueueEntry*)External::Unwrap(data_v);
  assert(entry);
  //DLOG("<%p> CallbackProxy", entry);
  // Parse arguments
  const int argc = args.Length();
  if (argc > 0) {
    // Check for error
    Local<Value> err = args[0];
    if (!err.IsEmpty() && !err->IsNull() && err->IsUndefined()) {
      AssignExceptionToEntry(err, entry);
    } else {
      // convert remaining arguments
      Local<Value>* argv = new Local<Value>[argc];
      NSMutableArray* arga = [NSMutableArray arrayWithCapacity:argc-1];
      for (int i = 1; i < argc; ++i) {
        Local<Value> v = args[i];
        [arga insertObject:NSObjectFromV8Value(v) atIndex:i-1];
      }
      entry->result = [arga retain];
    }
  }
  EnqueueOutput(entry);
  return Undefined();
}


// Triggered by host program, executed by node (in its thread), to dequeue
static void DequeueInput(EV_P_ ev_async *watcher, int revents) {
  assert(watcher->data != NULL);
  NodeThread* self = (NodeThread*)watcher->data;
  //DLOG("node: dequeueing input from host");
  
  // Extract and assign nodeProcessHost_ first time we get called
  if (self->nodeProcessHost_.IsEmpty()) {
    NSMutableDictionary* tinfo = [[NSThread currentThread] threadDictionary];
    NSValue *v = [tinfo objectForKey:@"node.process.host"];
    if (v) {
      Persistent<Object>* ptr = UnwrapPersistentObject([v pointerValue]);
      self->nodeProcessHost_ = *ptr;
      delete ptr;
      [tinfo removeObjectForKey:@"node.process.host"];
    }
  }
  
  IOQueueEntry* entry;
  
  while ( (entry = (IOQueueEntry*)OSAtomicDequeue(
      &self->inputQueue_, offsetof(struct IOQueueEntry, next))) ) {
    HandleScope scope;
    DLOG("node: dequeued %p", entry);
    entry->error = nil;
    
    // Get function recv(what, args)
    Local<Value> recv_v = self->nodeProcessHost_->Get(String::NewSymbol("recv"));
    assert(recv_v->IsFunction());
    Local<Function> recv = Local<Function>::Cast(recv_v);
    int argc = 2, i = 0;
    Local<Value> undef = Local<Value>::New(Undefined());
    Local<Value> argv[2] = {undef,undef};
    argv[0] = String::New([entry->functionName UTF8String]);
    
    // Encode args
    if (entry->args || entry->callback) {
      uint32_t i, count = entry->args ? [entry->args count] : 0;
      Local<Array> args_a = Array::New(entry->callback ? count + 1 : count);
      for (i = 0; i < count; i++) {
        NSObject *obj = [entry->args objectAtIndex:i];
        args_a->Set(i, [obj v8Representation]);
      }
      // Setup callback proxy
      if (entry->callback) {
        entry->nodeThread = self;
        v8::Handle<Value> data = External::Wrap(entry);
        Local<FunctionTemplate> t = FunctionTemplate::New(&CallbackProxy, data);
        Local<Function> fun = t->GetFunction();
        args_a->Set(i++, fun);
      }
      argv[1] = args_a;
    }
    
    // Invoke
    TryCatch try_catch;
    Local<Value> ret = recv->Call(self->nodeProcessHost_, argc, argv);
    
    // Release args since its part of a union with ->payload
    [entry->args release];
    entry->result = nil;
    
    if (!entry->callback) {
      // no callback -- report exception and dispose of entry
      if (try_catch.HasCaught()) {
        // Note: Since there is no callback for this entry, we can't pass on the
        // error to the caller. Instead, we report the error on stderr.
        ReportException(try_catch, true);
      }
      if (entry->functionName) [entry->functionName release];
      if (entry->callback) [entry->callback release];
      CFAllocatorDeallocate(NULL, entry);
    } else {
      // callback-based entry
      // caught exception causes immediate callback invocation
      if (try_catch.HasCaught()) {
        #if DEBUG
        ReportException(try_catch, true);
        #endif
        // Convert v8 error to NSError and queue
        AssignTryCatchToEntry(try_catch, entry);
        EnqueueOutput(entry);
      }
      // else: callback will be invoked in the future
    }
    
    scope.Close(Undefined());
  }
}

static NodeThread* gMainInstance_ = nil;

@implementation NodeThread


+ (NodeThread*)mainNodeThread {
  if (!gMainInstance_) {
    [self detachNewNodeThreadRunningScript:@"main.js"];
  }
  return gMainInstance_;
}

+ (void)setNodeSearchPaths:(NSArray*)paths {
  assert([NSThread isMainThread]);  // since setenv is not thread safe
  setenv("NODE_PATH", [[paths componentsJoinedByString:@":"] UTF8String], 1);
}


+ (NodeThread*)detachNewNodeThreadRunningScript:(NSString *)scriptPath {
  // searchPaths defaults to ["<bundle>/Resources/lib"]
  NSString *libPath = [[[NSBundle mainBundle] resourcePath]
      stringByAppendingPathComponent:@"lib"];
  NSArray *searchPaths = [NSArray arrayWithObject:libPath];
  return [self detachNewNodeThreadRunningScript:scriptPath
                                withSearchPaths:searchPaths];
}


+ (NodeThread*)detachNewNodeThreadRunningScript:(NSString *)scriptPath
                                withSearchPaths:(NSArray *)searchPaths {
  if (searchPaths) {
    // Note: Starting multiple node threads with different search paths might
    // lead to a race condition since we setenv() in the calling thread but
    // -main might get called async. to the setenv()s.
    [NodeThread setNodeSearchPaths:searchPaths];
  }
  if (scriptPath && ![scriptPath isAbsolutePath]) {
    // we need an absolute path, so assume the basename to the relative path is
    // "<bundle>/Resources"
    scriptPath = [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:scriptPath];
  }
  NodeThread *t = [[self alloc] initWithScriptPath:scriptPath];
  [t start];
  return [t autorelease];
}


-(id)initWithScriptPath:(NSString *)scriptPath {
  self = [super init];
  if (scriptPath) {
    // defaults to "<bundle>/Resources/main.js" (controller in -main)
    scriptPath_ = [scriptPath retain];
  }
  if (!gMainInstance_) {
    gMainInstance_ = self;
  }
  return self;
}


-(void)dealloc {
  if (gMainInstance_ == self)
    gMainInstance_ = nil;
  if (scriptPath_)
    [scriptPath_ release];
  [super dealloc];
}


- (void)invoke:(NSString*)functionName args:(NSArray*)args callback:(id)callback {
  // Create queue entry
  IOQueueEntry* entry = (IOQueueEntry*)CFAllocatorAllocate(
      NULL, sizeof(struct IOQueueEntry), 0);
  entry->functionName = [functionName retain];
  entry->args = args ? [args retain] : nil;
  entry->callback = callback ? [callback copy] : nil;
  OSAtomicEnqueue(&inputQueue_, entry, offsetof(struct IOQueueEntry, next));
  // Notify node thread that we have input queued
  ev_async_send(EV_DEFAULT_UC_ &dequeueInputNotifier_);
}

- (void)emit:(NSString *)name {
  [self invoke:@"emit" args:[NSArray arrayWithObject:name] callback:nil];
}

- (void)emit:(NSArray*)args callback:(NodeThreadCallback)callback {
  [self invoke:@"emit" args:args callback:nil];
}


- (void)cancel {
  if (![self isCancelled]) {
    // causes the node runloop to exit as soon as it's empty
    ev_unref(EV_DEFAULT_UC);
  }
  [super cancel];
}


- (void)main {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  // Set name
  [[NSThread currentThread] setName:NSStringFromClass([self class])];
  
  // Setup node arguments
  const char *argv[2] = {"node", NULL};
  if (scriptPath_) {
    argv[1] = [scriptPath_ UTF8String];
  } else {
    // defaults to "<bundle>/Resources/main.js"
    argv[1] = [[[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"main.js"] UTF8String];
  }
  
  // Register start callback
  node::ProcessStartCallback = &_ProcessStartCallback;
  
  // Setup ev_async traits
  dequeueInputNotifier_.data = self;
  ev_async_init(&dequeueInputNotifier_, &DequeueInput);
  ev_async_start(EV_DEFAULT_UC_ &dequeueInputNotifier_);
  // Note: This creates a new reference (count) to the loop. We release the ref
  // in -(void)cancel.
  
  // Start node runloop
  DLOG("node: thread starting %s", argv[1]);
  int ec = node::Start(2, (char**)argv);
  DLOG("node: thread exited with %d", ec);
  [pool drain];
}


@end
