#import "AppDelegate.h"
#import <NodeCocoa/NodeCocoa.h>

#define ENABLE_REDIRECT_STDERR 1

using namespace v8;

@implementation AppDelegate

static Persistent<Function> kInspectFunction;
static NSString* kLinePrefixFormat = @"HH:mm:ss > ";
static NSColor* kInputLineColor = nil;
static NSAttributedString* kNewlineAttrStr = nil;
static NSDictionary *kInputStringAttributes,
                    *kLinePrefixAttributes,
                    *kResultStringAttributes,
                    *kStdoutStringAttributes,
                    *kStderrStringAttributes,
                    *kErrorStringAttributes,
                    *kMetaStringAttributes;

#define RGBA(r,g,b,a) \
  [NSColor colorWithDeviceRed:(r) green:(g) blue:(b) alpha:(a)]

@synthesize window = window_,
            textView = textView_,
            scrollView = scrollView_,
            outputTextView = outputTextView_,
            outputScrollView = outputScrollView_,
            uncommitedHistoryEntry = uncommitedHistoryEntry_;

+ (void)load {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  // Font
  NSFont* fontNormal = [NSFont fontWithName:@"M+ 1m light" size:13.0];
  if (fontNormal) {
    [NSFont setUserFixedPitchFont:fontNormal];
  } else {
    fontNormal = [NSFont userFixedPitchFontOfSize:13.0];
  }
  NSFont* fontSmall = [NSFont userFixedPitchFontOfSize:11.0];
  // Newline
  kNewlineAttrStr = [[NSAttributedString alloc] initWithString:@"\n"];
  // Input line color
  kInputLineColor = [[NSColor colorWithDeviceWhite:1.0 alpha:0.8] retain];
  // Input prefix attributes
  kLinePrefixAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                            fontNormal, NSFontAttributeName,
                            [NSColor colorWithDeviceWhite:1.0 alpha:0.4],
                            NSForegroundColorAttributeName,
                            nil];
  // Input text attrs
  kInputStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             fontNormal, NSFontAttributeName,
                             kInputLineColor, NSForegroundColorAttributeName,
                             nil];
  // Input result text attrs
  kResultStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             fontNormal, NSFontAttributeName,
                             RGBA(0.7, 0.9, 1.0, 0.8),
                                NSForegroundColorAttributeName,
                             nil];
  // Error text attrs
  kErrorStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             fontNormal, NSFontAttributeName,
                             RGBA(1.0, 0.5, 0.5, 0.9),
                                NSForegroundColorAttributeName,
                             nil];
  // Stdout text attrs
  kStdoutStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             fontSmall, NSFontAttributeName,
                             RGBA(0.8, 1.0, 0.8, 0.8),
                                NSForegroundColorAttributeName,
                             nil];
  // Stdout text attrs
  kStderrStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             fontSmall, NSFontAttributeName,
                             RGBA(1.0, 0.8, 0.8, 0.8),
                                NSForegroundColorAttributeName,
                             nil];
  // Output meta text attrs
  kMetaStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             fontSmall, NSFontAttributeName,
                             RGBA(1.0, 1.0, 1.0, 0.4),
                                NSForegroundColorAttributeName,
                             nil];
  [pool drain];
}

+ (NSAttributedString*)linePrefix {
  NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
  [dateFormatter setDateFormat:kLinePrefixFormat];
  NSString* str = [dateFormatter stringFromDate:[NSDate date]];
  return [[NSAttributedString alloc] initWithString:str
                                         attributes:kLinePrefixAttributes];
}

- (void)awakeFromNib {
  // Setup NSTextView
  [textView_ setTextColor:kInputLineColor];
  [textView_ setFont:[NSFont userFixedPitchFontOfSize:13.0]];
  [textView_ setTextContainerInset:NSMakeSize(2.0, 4.0)];
  [textView_ setDelegate:self];
  [textView_.textStorage appendAttributedString:[isa linePrefix]];
  //[textView_.textStorage setDelegate:self];
  
  // setup output text view
  [outputTextView_ setTextColor:kInputLineColor];
  [outputTextView_ setFont:[NSFont userFixedPitchFontOfSize:11.0]];
  [outputTextView_ setTextContainerInset:NSMakeSize(2.0, 4.0)];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
  NSLog(@"applicationWillFinishLaunching");
  
  // Get the global "process" object
  Local<Object> process = Local<Object>::Cast(
      Context::GetCurrent()->Global()->Get(String::NewSymbol("process")));
  
  // redirect stdout to a pipe
  nodeStdoutPipe_ = [[NSPipe pipe] retain];
  NSFileHandle* pipeReadHandle = [nodeStdoutPipe_ fileHandleForReading];
  dup2([[nodeStdoutPipe_ fileHandleForWriting] fileDescriptor], fileno(stdout));
  [[NSNotificationCenter defaultCenter] addObserver:self
      selector:@selector(stdoutReadCompletion:)
      name:NSFileHandleReadCompletionNotification
      object:pipeReadHandle];
  [pipeReadHandle readInBackgroundAndNotify];
  
#if ENABLE_REDIRECT_STDERR
  // redirect stderr to a pipe
  // Alternative 1: Might cause funky crashes if NSLog is invoked at an
  // inapropriate time (e.g. during reading of stderr).
  nodeStderrPipe_ = [[NSPipe pipe] retain];
  dup2([[nodeStderrPipe_ fileHandleForWriting] fileDescriptor], fileno(stderr));
  // Alternative 2: Redirect stderr using custom code in our main.js.
  // Pass our stderr pipe fd to node as |process._stderrfd|
  //nodeStderrPipe_ = [[NSPipe pipe] retain];
  //int fd = [[nodeStderrPipe_ fileHandleForWriting] fileDescriptor];
  //process->ForceSet(String::New("_stderrfd"), Integer::New(fd));
  pipeReadHandle = [nodeStderrPipe_ fileHandleForReading];
  [[NSNotificationCenter defaultCenter] addObserver:self
      selector:@selector(stderrReadCompletion:)
      name:NSFileHandleReadCompletionNotification
      object:pipeReadHandle];
  [pipeReadHandle readInBackgroundAndNotify];
#endif // ENABLE_REDIRECT_STDERR
}

// string from data with best guess encoding (utf8, latin-1)
- (NSString*)stringFromData:(NSData*)data {
  NSString *text = [NSString alloc], *ptr;
  if ((ptr = [text initWithData:data encoding:NSUTF8StringEncoding])) {
    text = ptr;
  } else {
    text = [text initWithData:data encoding:NSISOLatin1StringEncoding];
  }
  return [text autorelease];
}

- (void)appendOutput:(NSString*)text withAttributes:(NSDictionary*)attrs {
  NSAttributedString* as =
      [[NSAttributedString alloc] initWithString:text attributes:attrs];
  static NSTextStorage* textStorage = nil;
  if (!textStorage) textStorage = outputTextView_.textStorage;
  [textStorage appendAttributedString:as];
  [as release];
}

-(void)_handleOutput:(NSNotification*)notification attrs:(NSDictionary*)attrs {
  NSDictionary* info = [notification userInfo];
  NSData* data = [info objectForKey: NSFileHandleNotificationDataItem];
  [self appendOutput:[self stringFromData:data] withAttributes:attrs];
  [[notification object] readInBackgroundAndNotify];
  [[outputScrollView_ documentView] scrollToEndOfDocument:self];
}

- (void)stdoutReadCompletion:(NSNotification*)notification {
  [self _handleOutput:notification attrs:kStdoutStringAttributes];
}

- (void)stderrReadCompletion:(NSNotification*)notification {
  [self _handleOutput:notification attrs:kStderrStringAttributes];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSLog(@"applicationDidFinishLaunching");
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication*)sender {
  NSLog(@"applicationShouldTerminate");
  return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
  NSLog(@"applicationWillTerminate");
  if (nodeStdoutPipe_) {
    [nodeStdoutPipe_.fileHandleForWriting synchronizeFile];
    [nodeStdoutPipe_.fileHandleForReading synchronizeFile];
  }
  if (nodeStderrPipe_) {
    [nodeStderrPipe_.fileHandleForWriting synchronizeFile];
    [nodeStderrPipe_.fileHandleForReading synchronizeFile];
  }
}

- (void)appendLine:(NSString*)line {
  [self appendLine:line attributes:nil];
}

- (void)appendLine:(NSString*)line attributes:(NSDictionary*)attrs {
  if (line)
    [self appendText:line attributes:attrs];
  [textView_.textStorage appendAttributedString:kNewlineAttrStr];
}

- (void)appendText:(NSString*)text attributes:(NSDictionary*)attrs {
  NSAttributedString* as =
      [[NSAttributedString alloc] initWithString:text attributes:attrs];
  [textView_.textStorage appendAttributedString:as];
  [as release];
}

- (void)appendToInputHistory:(NSString*)text {
  NSUserDefaults* ud = [NSUserDefaults standardUserDefaults];
  NSArray* history = [ud arrayForKey:@"history"];
  if (!history || history.count == 0) {
    history = [NSArray arrayWithObject:text];
  } else {
    // avoid consecutive duplicates
    if ([[history lastObject] isEqualToString:text])
      return;  // no need to modify history
    // max 1000 items in history
    if ([history count] >= 1000) {
      history = [history subarrayWithRange:
          NSMakeRange([history count]-999, 999)];
    }
    history = [history arrayByAddingObject:text];
  }
  [ud setObject:history forKey:@"history"];
}

- (IBAction)clearHistory:(id)sender {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"history"];
  self.uncommitedHistoryEntry = nil;
  historyCursor_ = 0;
}

- (IBAction)clearScrollback:(id)sender {
  // Remove everything except the last/current line
  NSTextStorage *textStorage = textView_.textStorage;
  NSString* str = textStorage.string;
  NSRange lastNLRange =
      [str rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                           options:NSBackwardsSearch];
  if (lastNLRange.location != NSNotFound && lastNLRange.location != 0) {
    [textStorage deleteCharactersInRange:
        NSMakeRange(0, lastNLRange.location+1)];
  }
}

- (void)eval:(NSString*)script {
  NSError *error;
  
  // Aquire reference to sys.inspect
  if (kInspectFunction.IsEmpty()) {
    HandleScope scope;
    Local<Value> result = [NodeJS eval:@"require('util').inspect"
                                origin:nil context:nil error:nil];
    kInspectFunction =
        Persistent<Function>::New(Local<Function>::Cast(result));
  }

  // Prepare input
  script = [script stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([script length] == 0) return;
  
  // Save to history & reset history cursor
  [self appendToInputHistory:script];
  historyCursor_ = 0;
  if (uncommitedHistoryEntry_)
    self.uncommitedHistoryEntry = nil;
  
  // If the line starts with a '{' or '[' (or is a function) we need to wrap it
  // in ( and ) for eval to function properly
  unichar ch0 = [script characterAtIndex:0];
  if (ch0 == '{' || ch0 == '[' || [script hasPrefix:@"function"]) {
    script = [NSString stringWithFormat:@"(%@)", script];
  }
  
  // result = eval(script)
  HandleScope scope;
  Local<Value> result =
      [NodeJS eval:script origin:@"<input>" context:nil error:&error];
  
  // Handle result
  if (result.IsEmpty()) {
    NSLog(@"eval: %@", error);
    [self appendLine:[error localizedDescription]
          attributes:kErrorStringAttributes];
  } else if (!result->IsUndefined()) {
    result = kInspectFunction->Call(kInspectFunction, 1, &result);
    String::Utf8Value utf8str(result->ToString());
    [self appendLine:[NSString stringWithUTF8String:*utf8str]
          attributes:kResultStringAttributes];
  }
}

#pragma mark -
#pragma mark NSTextViewDelegate implementation


- (NSRange)rangeOfCurrentInputLinePrefix {
  NSMutableString* mstr = [textView_.textStorage mutableString];
  NSRange lastNLRange =
      [mstr rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                            options:NSBackwardsSearch];
  NSUInteger rLocation =
        (lastNLRange.location == NSNotFound) ? 0 : lastNLRange.location;
  return NSMakeRange((lastNLRange.location == NSNotFound) ? 0
                                                          : (rLocation+1),
                     [kLinePrefixFormat length]);
}


- (BOOL)textView:(NSTextView *)aTextView
    shouldChangeTextInRange:(NSRange)editRange
          replacementString:(NSString *)replacementString {
  // Find current line offset
  NSTextStorage* textStorage = textView_.textStorage;
  NSMutableString* mstr = [textStorage mutableString];
  NSRange lastNLRange =
      [mstr rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                            options:NSBackwardsSearch];
  BOOL alowEdit = YES;
  BOOL atLastLine = (lastNLRange.location == NSNotFound) ||
                    (editRange.location > lastNLRange.location);
  
  if (atLastLine) {
    NSRange rstrNLRange = [replacementString
        rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                        options:NSBackwardsSearch];
    // don't allow deleting of the line prefix
    NSUInteger charsDeleted = editRange.length;
    NSUInteger rLocation =
        (lastNLRange.location == NSNotFound) ? 0 : lastNLRange.location;
    NSRange linePrefixRange =
        NSMakeRange((lastNLRange.location == NSNotFound) ? 0 : (rLocation+1),[kLinePrefixFormat length]);
    NSUInteger linePrefixEnd = linePrefixRange.location + linePrefixRange.length;
    //NSLog(@"%@ (linePrefixEnd: %u)", NSStringFromRange(editRange), linePrefixEnd);
    if (charsDeleted) {
      if (editRange.location < linePrefixEnd) {
        // don't allow deleting beyond last line prefix
        alowEdit = NO;
        if (charsDeleted > 1) {
          // if the delete involves several characters, remove all up until
          // line prefix.
          NSRange rmRange = NSMakeRange(linePrefixEnd,
              editRange.length - (linePrefixEnd - editRange.location));
          //NSLog(@"rmRange %@", NSStringFromRange(rmRange));
          if (rmRange.length > 0) {
            [textView_.textStorage deleteCharactersInRange:rmRange];
          }
        }
      }
    } else { // case: text is to be inserted
      // check for a newline entry
      BOOL gotNewline = (rstrNLRange.location != NSNotFound);
      if (gotNewline) {
        // user performed at least one linebreak
        alowEdit = NO;
        NSString* strUpToLastNewline =
            [replacementString substringToIndex:rstrNLRange.location];
        if ([strUpToLastNewline length] > 0) {
          // user performed more than one line break.
          // If something was pasted with multiple lines -- execute all
          // text before the last new line.
          [strUpToLastNewline enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            [self appendLine:line attributes:kInputStringAttributes];
            [self eval:line];
            [textStorage appendAttributedString:[isa linePrefix]];
          }];
          if (rstrNLRange.location+1 < [replacementString length]) {
            NSString* line =
                [replacementString substringFromIndex:rstrNLRange.location+1];
            [self appendText:line attributes:kInputStringAttributes];
          }
        } else {
          // User entered only a single new line
          // Extract eval line
          NSString* evalLine =
              [[textStorage mutableString] substringFromIndex:linePrefixEnd];
          [self appendLine:nil attributes:kInputStringAttributes];
          [self eval:evalLine];
          [textStorage appendAttributedString:[isa linePrefix]];
        }
        [[scrollView_ documentView] performSelector:@selector(scrollToEndOfDocument:) 
                                         withObject:self
                                         afterDelay:0.01];
        [textView_ setSelectedRange:NSMakeRange(textStorage.length, 0)];
      }
    }
  } else {
    // never allow editing of history (prior lines)
    alowEdit = NO;
  }
  
  //NSLog(@"alowEdit = %s", alowEdit ? "YES":"NO");
  return alowEdit;
}


- (NSRange)textView:(NSTextView *)aTextView
    willChangeSelectionFromCharacterRange:(NSRange)oldRange
                         toCharacterRange:(NSRange)newRange {
  // limit selection and cursor position to be somewhere after the input prefix
  //NSLog(@"change selection: %@ --> %@", NSStringFromRange(oldRange),
  //      NSStringFromRange(newRange));
  NSRange linePrefixRange = [self rangeOfCurrentInputLinePrefix];
  NSUInteger minLocation = linePrefixRange.location + linePrefixRange.length;
  if (newRange.location < minLocation) {
    if (newRange.length > 0) {
      // since the user can't hit Cmd+C (because we change her selection) we put
      // the selected text in clipboard before changing it
      static NSPasteboard *pboard = nil;
      if (pboard == nil) pboard = [NSPasteboard generalPasteboard];
      [pboard clearContents];
      NSString *str =
          [textView_.textStorage.string substringWithRange:newRange];
      [pboard setString:str forType:NSPasteboardTypeString];
      str = @"Copied selection to pasteboard\n";
      [self appendOutput:str withAttributes:kMetaStringAttributes];
      
      // create subrange
      NSUInteger newEndLocation = newRange.location + newRange.length;
      if (newEndLocation < minLocation) {
        newRange = NSMakeRange(minLocation, 0);
      } else {
        newRange.length = newRange.length - (newRange.location - minLocation);
        newRange.location = minLocation;
      }
    } else {
      newRange = NSMakeRange(minLocation, 0);
    }
  }
  return newRange;
}

- (NSAttributedString*)currentInputLineSettingRange:(NSRange*)outrange {
  NSTextStorage *textStorage = textView_.textStorage;
  NSRange range = [self rangeOfCurrentInputLinePrefix];
  range.location += range.length;
  range.length = textView_.textStorage.length - range.location;
  NSAttributedString* previous =
      [textStorage attributedSubstringFromRange:range];
  if (outrange) *outrange = range;
  return previous;
}

- (NSAttributedString*)replaceInputLineWithAttributedString:
    (NSAttributedString*)as {
  NSRange range;
  NSAttributedString* previous = [self currentInputLineSettingRange:&range];
  [textView_.textStorage replaceCharactersInRange:range withAttributedString:as];
  [[outputScrollView_ documentView] scrollToEndOfDocument:self]; // FIXME: buggy
  return previous;
}

- (NSAttributedString*)replaceInputLineWithString:(NSString*)text {
  NSAttributedString* as =
      [[NSAttributedString alloc] initWithString:text
                                      attributes:kInputStringAttributes];
  NSAttributedString* previous = [self replaceInputLineWithAttributedString:as];
  [as release];
  return previous;
}

- (void)_replaceInputLineFromHistory:(NSArray*)history {
  NSUInteger i = history.count - historyCursor_;
  NSString *text = [history objectAtIndex:i];
  NSAttributedString* previous = [self replaceInputLineWithString:text];
  if (!uncommitedHistoryEntry_)
    self.uncommitedHistoryEntry = previous;
}

//-----------------------

static v8::Handle<v8::Value> readdirCallback(const Arguments& args){
  HandleScope scope;
  NSLog(@"readdir returned");
  return Undefined();
}

- (void)_testAsync {
  HandleScope scope;
  static NodeJSFunction *readdirFunc = nil;
  if (!readdirFunc) {
    readdirFunc = [[NodeJSFunction functionFromString:@"require('fs').readdir"
                                                error:nil] retain];
    //NSLog(@"%@", [NSObject fromV8Value:readdirFunc.v8Value]);
  }
  Local<Value> argv[] = {
    String::New("/"),
    [NodeJSFunction functionWithCFunction:&readdirCallback].v8Value
  };
  Local<Value> r = [readdirFunc callWithV8Arguments:argv count:2 error:nil];
}

- (void)consoleTextViewArrowUpKeyEvent:(NSEvent*)event {
  // get an older item from history
  NSArray* history =
      [[NSUserDefaults standardUserDefaults] arrayForKey:@"history"];
  if (history) {
    // 0 = current/uncommitted
    // 1 = last item in history
    // ...
    // 4 = (history.count - 3)
    if (history.count >= (historyCursor_ + 1)) {
      historyCursor_++;
      [self _replaceInputLineFromHistory:history];
    } else {
      historyCursor_ = history.count;
    }
  }
  
  // Demonstrates using a NodeJSFunction wrapper, emitting an event on |process|
  static NodeJSFunction *func = nil;
  if (!func) {
    func = [[NodeJSFunction functionFromString:
        @"function emitKeyCode(keyCode){ process.emit('keyPress', keyCode) }"
                                         error:nil] retain];
  }
  HandleScope scope;
  Local<Value> argv[] = { v8::Integer::New([event keyCode]) };
  [func callWithV8Arguments:argv count:1 error:nil];
  
  //[self _testAsync];
  
  /* test type conversion:
  NSError *error;
  Local<Value> v = [NodeJS eval:
    @"({key: 'str', ls: [1.2, new Date, {k:'v'}], foo: {'0':'00', '1':'11'}})"
                         origin:nil context:nil error:&error];
  if (v.IsEmpty()) {
    NSLog(@"eval: %@", error);
    return;
  }
  
  // v8 --> Cocoa
  NSObject *obj = [NSObject fromV8Value:v];
  NSLog(@"v8 -> cocoa: %@", obj);
  
  // Cocoa --> v8
  v = [obj v8Value];
  assert(!v.IsEmpty());
  Local<Value> printv = [NodeJS eval:@"(function(x) {"
        @"var u = require('util');"
        @"u.error('cocoa -> v8: ' + u.inspect(x));"
      @"})" origin:nil context:nil error:nil];
  assert(!printv.IsEmpty());
  Local<Function>::Cast(printv)->Call(Context::GetCurrent()->Global(), 1, &v);*/
}

- (void)consoleTextViewArrowDownKeyEvent:(NSEvent*)event {
  // get a newer item from history
  NSArray* history =
      [[NSUserDefaults standardUserDefaults] arrayForKey:@"history"];
  if (history && historyCursor_ >= 2) {
    historyCursor_--;
    [self _replaceInputLineFromHistory:history];
  } else if (historyCursor_ == 1 && uncommitedHistoryEntry_) {
    [self replaceInputLineWithAttributedString:uncommitedHistoryEntry_];
    self.uncommitedHistoryEntry = nil;
    historyCursor_ = 0;
  }
  
  // Demonstrates compiling and reusing a script in the default (main) context
  // which emits an event on |process|
  static NodeJSScript *emitScript = nil;
  if (!emitScript) {
    emitScript = [[NodeJSScript compiledScriptFromSource:
                   @"process.emit('keyPress', 125)"] retain];
  }
  [emitScript run:nil];
}

- (void)consoleTextViewTabKeyEvent:(NSEvent*)event {
  // TODO: auto-complete
}

- (void)consoleTextViewEscKeyEvent:(NSEvent*)event {
  // TODO: suggest completions
}

@end
