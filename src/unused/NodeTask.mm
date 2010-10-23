#import "NodeTask.h"
#import "NSTask+node.h"

#define BLOCK_EXCH(dst, src) {\
  id old = (dst);\
  (dst) = (src) ? [(src) copy] : nil;\
  if ((old)) [(old) release];\
}

@implementation NodeTask

@synthesize libraryPaths = libraryPaths_;

static NSString* kNodeExecutablePath = nil;

+ (NSString*)findNodeExecutablePath {
  NSString* s = nil;
  NSFileManager* fm = [NSFileManager defaultManager];

  // look in user defaults
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  s = [defaults stringForKey:@"nodeExecutablePath"];
  if (s && [fm isExecutableFileAtPath:s])
    return s;
  
  // look for NODE_PATH in env
  // Note: Will only work if set in ~/.MacOSX/environment.plist or passed at
  // cocoa application launch (i.e. ~/.bashrc et. al. will not affect this)
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  s = [env objectForKey:@"NODE_PATH"];
  BOOL isDir = NO;
  if (s && [fm fileExistsAtPath:s isDirectory:&isDir] && isDir) {
    s = [s stringByAppendingPathComponent:@"../../bin/node"];
    s = [s stringByStandardizingPath];
    if ([fm isExecutableFileAtPath:s])
      return s;
  }
  
  // test a few common locations
  static NSString* commonLocations[] = {
    @"/usr/local/bin/node",
    @"/usr/bin/node",
    @"/opt/local/bin/node"
  };
  int i, L = sizeof(commonLocations) / sizeof(void*);
  for (i=0; i<L; i++) {
    if ([fm fileExistsAtPath:commonLocations[i]]) {
      return commonLocations[i];
      break;
    }
  }
  
  // consult which (this uses a real login shell, so might be slow)
  int status;
  s = [NSTask outputForShellCommand:@"which node" status:&status];
  if (status == 0) return s;
  
  return nil;
}


+ (void)load {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  kNodeExecutablePath = [[self findNodeExecutablePath] retain];
  [pool drain];
}


+ (NSString*)nodeExecutablePath {
  return kNodeExecutablePath;
}


+ (void)setNodeExecutablePath:(NSString*)path {
  id old = kNodeExecutablePath;
  kNodeExecutablePath = path ? [path retain] : nil;
  if (old) [old release];
}


- (id)init {
  if ((self = [super init])) {
    NSBundle* bundle = [NSBundle mainBundle];
    libraryPaths_ = [[NSArray alloc] initWithObjects:
        [[bundle resourcePath] stringByAppendingPathComponent:@"lib"], nil];
  }
  return self;
}


- (BOOL)isRunning { return (task_ && [task_ isRunning]); }
- (int)terminationStatus { return task_ ? [task_ terminationStatus] : -1; }
- (int)processIdentifier { return task_ ? [task_ processIdentifier] : -1; }

- (void(^)(NodeTask*, NSData*))onStandardOutput { return onStandardOutput_; }
- (void)setOnStandardOutput:(void(^)(NodeTask*, NSData*))block {
  BLOCK_EXCH(onStandardOutput_, block);
}

- (void(^)(NodeTask*, NSData*))onStandardError { return onStandardError_; }
- (void)setOnStandardError:(void(^)(NodeTask*, NSData*))block {
  BLOCK_EXCH(onStandardError_, block);
}

- (void(^)(NodeTask*))onExit { return onExit_; }
- (void)setOnExit:(void(^)(NodeTask*))block {
  BLOCK_EXCH(onExit_, block);
}


- (BOOL)startWithArguments:(NSArray*)arguments {
  // already started or node not found
  if (self.isRunning || !kNodeExecutablePath) {
    return NO;
  }
  
  /*
  - forks child
  - creates two (input & output) pipes
  - 
  */
  
  // create communication pipes
  NSPipe* cocoaToNodePipe = [NSPipe pipe];
  NSPipe* nodeToCocoaPipe = [NSPipe pipe];
  
  
  // create task
  id oldTask = task_;
  task_ = [[NSTask alloc] init];
  if (oldTask) [oldTask release];
  // node -arg -arg -arg
  task_.launchPath = kNodeExecutablePath;
  if (arguments)
    task_.arguments = arguments;
  // cd <bundle>/Resources
  task_.currentDirectoryPath = [[NSBundle mainBundle] resourcePath];
  // setup env
  NSString* nodeLibPath = [libraryPaths_ componentsJoinedByString:@":"];
  NSMutableDictionary *env =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  [env setObject:nodeLibPath forKey:@"NODE_PATH"];
  task_.environment = env;
  // setup standard I/O
  task_.standardInput = [NSPipe pipe];
  task_.standardOutput = [NSPipe pipe];
  task_.standardError = [NSPipe pipe];
  NSFileHandle* standardOutput = [task_.standardOutput fileHandleForReading];
  NSFileHandle* standardError = [task_.standardError fileHandleForReading];
  
  // register for notifications
  NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self 
         selector:@selector(taskDidTerminate:) 
             name:NSTaskDidTerminateNotification 
           object:task_];
  
  [nc addObserver:self
         selector:@selector(standardOutputHasData:)
             name:NSFileHandleDataAvailableNotification
           object:standardOutput];
  
  [nc addObserver:self
         selector:@selector(standardErrorHasData:)
             name:NSFileHandleDataAvailableNotification
           object:standardError];
  
  // setup "async" I/O
  [standardOutput waitForDataInBackgroundAndNotify];
  [standardError waitForDataInBackgroundAndNotify];
  
  // launch task (raises NSInvalidArgumentException on error)
  [task_ launch];
  return YES;
}

-(NSData*)_availableDataOrError:(NSFileHandle *)file {
  for (;;) {
    @try {
      return [file availableData];
    } @catch (NSException *e) {
      if ([[e name] isEqualToString:NSFileHandleOperationException]) {
        if ([[e reason] isEqualToString:@"*** -[NSConcreteFileHandle "
                                        @"availableData]: Interrupted "
                                        @"system call"]) {
          continue;
        }
        return nil;
      }
      @throw;
    }
  }
}

- (void)standardOutputHasData:(NSNotification*)notification {
  NSFileHandle *fileHandle = (NSFileHandle*)[notification object];
  NSData* data = [self _availableDataOrError:fileHandle];
  if (data && [data length] && onStandardOutput_) {
    ((void(^)(NodeTask*, NSData*))onStandardOutput_)(self, data);
  }
  [fileHandle waitForDataInBackgroundAndNotify];
}

- (void)standardErrorHasData:(NSNotification*)notification {
  NSFileHandle *fileHandle = (NSFileHandle*)[notification object];
  NSData* data = [self _availableDataOrError:fileHandle];
  if (data && [data length] && onStandardError_) {
    ((void(^)(NodeTask*, NSData*))onStandardError_)(self, data);
  }
  [fileHandle waitForDataInBackgroundAndNotify];
}

- (void)taskDidTerminate:(NSNotification*)notification {
  assert([notification object] == task_);
  NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self
                name:NSTaskDidTerminateNotification
              object:task_];
  [nc removeObserver:self
                name:NSFileHandleDataAvailableNotification
              object:[task_.standardOutput fileHandleForReading]];
  [nc removeObserver:self
                name:NSFileHandleDataAvailableNotification
              object:[task_.standardError fileHandleForReading]];
  if (onExit_) {
    ((void(^)(NodeTask*))onExit_)(self);
  }
}

- (BOOL)stop:(void(^)(NodeTask*))onExit {
  if (onExit) BLOCK_EXCH(onExit_, onExit);
  if (!self.isRunning) {
    if (onExit) ((void(^)(NodeTask*))onExit)(self); // don't call onExit_
    return NO;
  } else {
    [task_ terminate];
    return YES;
  }
}

- (BOOL)terminate {
  [[task_.standardError fileHandleForWriting] synchronizeFile];
  return [self sendSignal:9];
}


- (BOOL)restart:(void(^)(NodeTask*, int, NSException*))callback {
  id origOnExit = onExit_;
  callback = [callback copy];
  return [self stop:^(NodeTask* self){
    // reset onExit handler
    BLOCK_EXCH(onExit_, origOnExit);
    if (onExit_) ((void(^)(NodeTask*))onExit_)(self);
    // save task info before we replace the task
    int terminationStatus = self.terminationStatus;
    NSException *startError = nil;
    @try {
      [self startWithArguments:task_ ? task_.arguments : nil];
    } @catch (NSException *e) {
      startError = e;
    }
    if (callback) {
      callback(self, terminationStatus, startError);
      [callback release];
    }
  }];
}

- (BOOL)forceRestart {
  [self terminate];
  return [self startWithArguments:task_ ? task_.arguments : nil];
}


- (BOOL)sendSignal:(int)signal {
  if (!self.isRunning) return NO;
  kill((pid_t)self.processIdentifier, signal);
  return YES;
}

@end
