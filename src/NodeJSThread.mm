void DummyFunction() { }
#define KnownAddress ((char *) ::DummyFunction)
#define cxx_offsetof(type, member) \
  (((char *) &((type *) KnownAddress)->member) - KnownAddress)

#import "NodeJSThread.h"
#import "NodeJS.h"

using namespace v8;
using namespace nodejs;

static NodeJSThread* gMainNodeJSThread_ = nil;

// ----------------------------------------------------------------------------

@interface NodeJSThread (Private)
- (void)_setMainContextFromCurrentContext;
@end
@implementation NodeJSThread (Private)
- (void)_setMainContextFromCurrentContext {
  assert(mainContext_.IsEmpty());
  mainContext_ = Persistent<Context>::New(Context::GetCurrent());
}
@end

// ----------------------------------------------------------------------------

PerformEntry::PerformEntry(NodeJSPerformBlock block) :
    performBlock_([block copy]) {
  originRunloop_ = CFRunLoopGetCurrent();
  CFRetain(originRunloop_);
}


PerformEntry::~PerformEntry() {
  [performBlock_ release];
  CFRelease(originRunloop_);
};


void PerformEntry::Perform() {
  performBlock_(^(void (^block)(void)) {
    CFRunLoopPerformBlock(originRunloop_, kCFRunLoopCommonModes, block);
  });
  delete this;
}

// ----------------------------------------------------------------------------


// called when node has been setup and is about to enter its runloop
static void NodeMain(const Arguments& args) {
  NodeJSThread* self = (NodeJSThread*)[NSThread currentThread];

  // Keep a reference to the main module's context
  [self _setMainContextFromCurrentContext];

  // increase reference count (or: aquire our reference to the runloop). Matched
  // by a unref in [NodeJS terminate];
  ev_ref(EV_DEFAULT_UC);

  // enter a blocking runloop
  ev_run(EV_DEFAULT_UC_ 0);
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


// Triggered when there are stuff on inputQueue_
static void InputQueueNotification(EV_P_ ev_async *watcher, int revents) {
  HandleScope scope;

  // retrieve our thread instance
  NodeJSThread* self = (NodeJSThread*)watcher->data;
  //NSLog(@"InputQueueNotification");

  // enumerate queue
  PerformEntry* entry;
  while ( (entry = (PerformEntry*)OSAtomicDequeue(
      &self->inputQueue_, cxx_offsetof(PerformEntry, next_))) ) {
    //NSLog(@"dequeued %p", entry);
    entry->Perform();
  }
}


// ----------------------------------------------------------------------------

@implementation NodeJSThread

@synthesize scriptPath = scriptPath_,
            searchPaths = searchPaths_;

+ (void)load {
  // Have node use our custom main
  node::Main = &NodeMain;

  // Have libev use our memory allocator
  ev_set_allocator(&MemAlloc);

  // Tell node to load modules in separate contexts -- a trick to get access to
  // require() and friends. This works together with |gMainContext| in the way
  // that after the main module has loaded, node will export global "require",
  // "exports", "__filename", "__dirname" and "module" objects. These will then
  // be reachable by any code executing in the |gMainContext| context. See
  // implementation of [NodeJS eval:name:error:] for an example.
  setenv("NODE_MODULE_CONTEXTS", "1", 1);
}


+ (NodeJSThread*)mainNodeJSThread {
  return gMainNodeJSThread_;
}


+ (NodeJSThread*)detachNewNodeJSThreadRunningScript:(NSString*)filename {
  NodeJSThread *t = [[NodeJSThread alloc] initWithScriptPath:filename
                                                 searchPaths:nil];
  [t start];
  return [t autorelease];
}


- (id)init {
  if ((self = [super init])) {
    if (!gMainNodeJSThread_)
      gMainNodeJSThread_ = self;
  }
  return self;
}

- (id)initWithScriptPath:(NSString*)scriptPath searchPaths:(NSArray*)paths {
  if ((self = [super init])) {
    // defaults to "<bundle>/Resources/main.js" (controller in -main)
    if (scriptPath)
      scriptPath_ = [scriptPath retain];
    if (paths)
      searchPaths_ = [paths retain];
    if (!gMainNodeJSThread_)
      gMainNodeJSThread_ = self;
  }
  return self;
}


-(void)dealloc {
  if (gMainNodeJSThread_ == self)
    gMainNodeJSThread_ = nil;
  if (scriptPath_)
    [scriptPath_ release];
  [super dealloc];
}


- (const v8::Persistent<v8::Context>&)mainContext {
  return mainContext_;
}


- (void)_preparePaths {
  // Find our bundle
  NSBundle* mainBundle = [NSBundle mainBundle];
  NSString* resourcePath = mainBundle ? [mainBundle resourcePath] : nil;

  /* If no scriptPath_ is set, derive it from our bundle (fall back to main.js)
  if (!scriptPath_) {
    scriptPath_ = @"main.js";
    if (resourcePath)
      scriptPath_ = [resourcePath stringByAppendingPathComponent:scriptPath_];
  }/*/
  // If scriptPath_ is just a filename, add resourcePath in front
  if (scriptPath_ && [scriptPath_ pathComponents].count == 1 && resourcePath) {
    scriptPath_ = [resourcePath stringByAppendingPathComponent:scriptPath_];
  }
  //*/

  // Clear searchPaths_ if empty
  if (searchPaths_ && searchPaths_.count == 0) {
    [searchPaths_ release];
    searchPaths_ = nil;
  }

  // Append <mainbundle>/Contents/Resources/lib
  if (resourcePath) {
    NSString *libPath = [resourcePath stringByAppendingPathComponent:@"lib"];
    if (!searchPaths_) {
      searchPaths_ = [[NSArray alloc] initWithObjects:libPath, nil];
    } else {
      id old = searchPaths_;
      searchPaths_ = [[searchPaths_ arrayByAddingObject:libPath] retain];
      [old release];
    }
  }

  // Set/expand NODE_PATH
  if (searchPaths_) {
    char *node_path = getenv("NODE_PATH");
    NSString *paths = [searchPaths_ componentsJoinedByString:@":"];
    if (node_path != NULL)
      paths = [NSString stringWithFormat:@"%s:%@", node_path, paths];
    setenv("NODE_PATH", [paths UTF8String], 1);
  }
}


- (void)main {
  NSAutoreleasePool* pool = [NSAutoreleasePool new];

  // Prepare scriptPath_ and searchPaths_
  [self _preparePaths];

  // Setup ev_async traits
  inputQueueNotifier_.data = self;
  ev_async_init(&inputQueueNotifier_, &InputQueueNotification);
  ev_async_start(EV_DEFAULT_UC_ &inputQueueNotifier_);
  // Note: This creates a new reference (count) to the loop. We release the ref
  // in -(void)cancel.

  NSLog(@"%@ starting", self);
  
  // Start node
  int ec;
  if (scriptPath_) {
    const char *argv[] = {"node", [scriptPath_ UTF8String]};
    ec = node::Start(2, (char**)argv);
  } else {
    // eval basically nothing. Since the result of eval is passed through
    // console.log, we temporarily reassign console.log to a noop, an then at
    // next tick we restore it.
    const char *argv[] = {"node", "-e",
      "var x=console.log;console.log=function(){};"
      "process.nextTick(function(){console.log=x})"};
    ec = node::Start(3, (char**)argv);
  }
  
  NSLog(@"%@ exited with %d", self, ec);
  [pool drain];
}


- (void)performEntry:(PerformEntry*)entry {
  OSAtomicEnqueue(&inputQueue_, entry, cxx_offsetof(PerformEntry, next_));
  ev_async_send(EV_DEFAULT_UC_ &inputQueueNotifier_);
}


- (void)performBlock:(NodeJSPerformBlock)block {
  PerformEntry* entry = new PerformEntry(block);
  [self performEntry:entry];
}


- (void)exportGlobalFunction:(v8::InvocationCallback)func as:(NSString*)name {
  [self performBlock:^(NodeJSCallbackBlock callback){
    HandleScope scope;
    Local<Function> function = FunctionTemplate::New(func)->GetFunction();
    Local<Object> global = mainContext_->Global();
    if (!global->Set(String::NewSymbol([name UTF8String]), function)) {
      NSLog(@"error in exportGlobalFunction:as: -- invalid function name '%@'",
            name);
    }
  }];
}


- (void)cancel {
  if (![self isCancelled]) {
    // causes the node runloop to exit as soon as it's empty
    ev_unref(EV_DEFAULT_UC);
  }
  [super cancel];
}


//- (NSString*)description {}

@end
