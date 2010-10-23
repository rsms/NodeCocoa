
@interface NodeTask : NSObject {
  NSTask* task_;
  NSArray* libraryPaths_;
  id onStandardOutput_;
  id onStandardError_;
  id onExit_;
}
// NODE_PATH equivalent
@property(retain) NSArray* libraryPaths;

// Process status
@property(assign, readonly) int terminationStatus;
@property(assign, readonly) int processIdentifier;
@property(assign, readonly) BOOL isRunning;

// Called with data from node when it arrives (i.e. when I/O is flushed by the
// OS or explicitly by node).
@property(retain) void(^onStandardOutput)(NodeTask*, NSData*);
@property(retain) void(^onStandardError)(NodeTask*, NSData*);

// Called when node exits. Query |terminationStatus| to get the exit code.
@property(retain) void(^onExit)(NodeTask*);

// Path to "node" executable. Automatically resolved at program launch.
+ (NSString*)nodeExecutablePath;
+ (void)setNodeExecutablePath:(NSString*)path;

// Starting node, passing optional |arguments| to node. Returns false if node is
// already running or +nodeExecutablePath is nil. May rise
// NSInvalidArgumentException if process birth fail (kind of internal error).
- (BOOL)startWithArguments:(NSArray*)arguments;

// Stop node. Returns false if not running. If onExit is non-nil (a onExit
// block) this will _replace_ any previous value of |onExit|. |onExit| is called
// immediately if node is not running (and false is returned).
- (BOOL)stop:(void(^)(NodeTask*))onExit;

// Like |stop| but sends signal 9 to node, causing immediate termination.
- (BOOL)terminate;

// Restart node in a graceful manner -- if node is running, node is first asked
// stop (by calling |stop|), we wait for node to exit by itself, then
// |startWithArguments:| is called, passing the same arguments as previously
// used (or none if never before started).
// The optional |callback| is called when node has started (or failed to start)
// with |terminationStatus| from the |stop| action and possibly a |startError|.
// Returns false if node was not running.
- (BOOL)restart:(void(^)(NodeTask*,
                         int terminationStatus, 
                         NSException* startError))callback;

// Like |restart| but terminates node immediately (using |terminate|) and then
// starting node again. See |restart| and |startWithArguments:| for details.
// Synchronous and may raise a NSInvalidArgumentException. Returns the result
// from calling |startWithArguments:|.
- (BOOL)forceRestart;

// Send a OS-level signal to node. Returns false if node is not running.
- (BOOL)sendSignal:(int)signal;

@end
