#ifndef NODECOCOA_NODEJS_H_
#define NODECOCOA_NODEJS_H_

#import <NodeCocoa/node.h>

/**
 * Program entry point -- replaces use of NSApplicationMain.
 *
 * Tip: You can utilize the NSApplication delegate method
 * |applicationWillFinishLaunching:| to perform environment setup if needed.
 */
int NodeJSApplicationMain(int argc, const char** argv);

#ifdef __OBJC__

// NSError additions
@interface NSError (v8)
/**
 * Create a NSError from a valid TryCatch struct.
 *
 * The userInfo dict includes the following keys:
 *
 *   NSLocalizedDescriptionKey -- formatted error message with stack trace.
 *   filename -- filename of origin where the exception was raised.
 *   lineno -- line number where the exception was raised.
 *   sourceline -- origin source line.
 */
+ (NSError*)errorFromV8TryCatch:(v8::TryCatch &)try_catch;

/**
 * Convenience: create an NSError in the |NodeJSNSErrorDomain| with the
 * |userInfo| key |NSLocalizedDescriptionKey| set to |description|.
 */
+ (NSError*)nodeErrorWithLocalizedDescription:(NSString*)description;
@end

/// NSError domain for errors related to Node.js.
extern const NSString* NodeJSNSErrorDomain;

// Objective-C++ interface to node.js
@interface NodeJS : NSObject {
}

/**
 * Initialize graceful shutdown.
 *
 * If there are pending events in node NSTerminateCancel is returned and the
 * process will exit as soon as there are no more events on the node runloop.
 *
 * Note: calling this function a second time will cause immediate termination.
 */
+ (NSApplicationTerminateReply)gracefulShutdown;

/// Returns the number of registered events currently in the node runloop.
+ (int)registeredEvents;

/// The main v8 context.
+ (v8::Persistent<v8::Context>)mainContext;

/// The global "process" object in node
+ (v8::Local<v8::Object>)process;

/**
 * Compile |source| in |context| identified by |name| passing |error|.
 *
 * @param source   JavaScript source.
 * @param origi    Optional identifier (e.g. filename).
 * @param context  An optional custom context in which to compile the script.
 * @param error    Optional output-pointer, providing error information. No
 *                 matter if this is |nil| or not, you should always check the
 *                 returned handle's |IsEmpty()| method for success.
 */
+ (v8::Local<v8::Script>)compile:(NSString*)source
                          origin:(NSString*)origin
                         context:(v8::Context*)context
                           error:(NSError**)error;

/**
 * Compile and run |source| in |context| identified by |name| passing |error|
 * returning the result.
 */
+ (v8::Local<v8::Value>)eval:(NSString*)source
                      origin:(NSString*)origin
                     context:(v8::Context*)context
                       error:(NSError**)error;

@end

#endif // __OBJC__
#endif // NODECOCOA_NODEJS_H_
