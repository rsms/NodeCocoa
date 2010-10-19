#import "AppDelegate.h"
#import "NodeJS.h"

using namespace v8;

@implementation AppDelegate

static NSString* kLinePrefixFormat = @"HH:mm:ss > ";
static NSFont* kDefaultFont = nil;
static NSColor* kInputLineColor = nil;
static NSAttributedString* kNewlineAttrStr = nil;
static NSDictionary *kInputStringAttributes,
                    *kLinePrefixAttributes,
                    *kResultStringAttributes,
                    *kStdoutStringAttributes,
                    *kStderrStringAttributes,
                    *kErrorStringAttributes;

#define RGBA(r,g,b,a) \
  [NSColor colorWithDeviceRed:(r) green:(g) blue:(b) alpha:(a)]

@synthesize window = window_,
            textView = textView_,
            scrollView = scrollView_,
            outputTextView = outputTextView_,
            outputScrollView = outputScrollView_;

+ (void)load {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  
  // Font
  kDefaultFont = [NSFont fontWithName:@"M+ 1m light" size:13.0];
  if (!kDefaultFont) kDefaultFont = [NSFont userFixedPitchFontOfSize:13.0];
  kDefaultFont = [kDefaultFont retain];
  // Newline
  kNewlineAttrStr = [[NSAttributedString alloc] initWithString:@"\n"];
  // Input line color
  kInputLineColor = [[NSColor colorWithDeviceWhite:1.0 alpha:0.8] retain];
  // Input prefix attributes
  kLinePrefixAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                            kDefaultFont, NSFontAttributeName,
                            [NSColor colorWithDeviceWhite:1.0 alpha:0.4],
                            NSForegroundColorAttributeName,
                            nil];
  // Input text attrs
  kInputStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             kDefaultFont, NSFontAttributeName,
                             kInputLineColor, NSForegroundColorAttributeName,
                             nil];
  // Returned result text attrs
  kResultStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             kDefaultFont, NSFontAttributeName,
                             RGBA(0.7, 0.9, 1.0, 0.8),
                                NSForegroundColorAttributeName,
                             nil];
  // Stdout text attrs
  kStdoutStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             kDefaultFont, NSFontAttributeName,
                             RGBA(0.8, 1.0, 0.8, 0.8),
                                NSForegroundColorAttributeName,
                             nil];
  // Stdout text attrs
  kStderrStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             kDefaultFont, NSFontAttributeName,
                             RGBA(1.0, 0.8, 0.8, 0.8),
                                NSForegroundColorAttributeName,
                             nil];
  // Error text attrs
  kErrorStringAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                             kDefaultFont, NSFontAttributeName,
                             RGBA(1.0, 0.5, 0.5, 0.9),
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
  [textView_ setFont:kDefaultFont];
  [textView_ setTextContainerInset:NSMakeSize(2.0, 4.0)];
  [textView_ setDelegate:self];
  NSTextStorage* textStorage = [textView_ textStorage];
  [textStorage appendAttributedString:[isa linePrefix]];
  [textStorage setDelegate:self];
  
  // setup output text view
  [outputTextView_ setTextColor:kInputLineColor];
  [outputTextView_ setFont:kDefaultFont];
  [outputTextView_ setTextContainerInset:NSMakeSize(2.0, 4.0)];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
  NSLog(@"applicationWillFinishLaunching");
  
  [NodeJS setHostObject:self];
  
  // Get the global "process" object
  Local<Object> global = Context::GetCurrent()->Global();
  //Local<Object> global = [NodeJS mainContext]->Global();
  Local<Object> process =
      Local<Object>::Cast(global->Get(String::NewSymbol("process")));
  /*
  // Setup custom stdout
  nodeStdoutPipe_ = [NSPipe pipe];
  // use |ForceSet| since it's originally a read-only property
  Local<Integer> fd =
      Integer::New([[nodeStdoutPipe_ fileHandleForWriting] fileDescriptor]);
  process->ForceSet(String::New("stdout"), fd);
  
  // Setup custom stderr
  nodeStderrPipe_ = [NSPipe pipe];
  // use |ForceSet| since it's originally a read-only property
  Local<Integer> fd =
      Integer::New([[nodeStderrPipe_ fileHandleForWriting] fileDescriptor]);
  process->ForceSet(String::New("stderr"), fd);*/
  
  
  // redirect stdout and stderr
  nodeStdoutPipe_ = [NSPipe pipe];
  NSFileHandle* pipeReadHandle = [nodeStdoutPipe_ fileHandleForReading];
  dup2([[nodeStdoutPipe_ fileHandleForWriting] fileDescriptor], fileno(stdout));
  [[NSNotificationCenter defaultCenter] addObserver:self
      selector:@selector(stdoutReadCompletion:)
      name:NSFileHandleReadCompletionNotification
      object:pipeReadHandle];
  [pipeReadHandle readInBackgroundAndNotify];
  
  // hey, this will cause funky crashes...
  /*nodeStderrPipe_ = [NSPipe pipe];
  pipeReadHandle = [nodeStderrPipe_ fileHandleForReading];
  dup2([[nodeStderrPipe_ fileHandleForWriting] fileDescriptor], fileno(stderr));
  [[NSNotificationCenter defaultCenter] addObserver:self
      selector:@selector(stderrReadCompletion:)
      name:NSFileHandleReadCompletionNotification
      object:pipeReadHandle];
  [pipeReadHandle readInBackgroundAndNotify];*/
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

- (void)stdoutReadCompletion:(NSNotification*)notification {
  NSDictionary* info = [notification userInfo];
  NSData* data = [info objectForKey: NSFileHandleNotificationDataItem];
  NSString* text = [self stringFromData:data];
  NSAttributedString* as =
      [[NSAttributedString alloc] initWithString:text
                                      attributes:kStdoutStringAttributes];
  [outputTextView_.textStorage appendAttributedString:as];
  [outputTextView_.textStorage appendAttributedString:kNewlineAttrStr];
  [as release];
  [[notification object] readInBackgroundAndNotify];
}

- (void)stderrReadCompletion:(NSNotification*)notification {
  NSDictionary* info = [notification userInfo];
  NSData* data = [info objectForKey: NSFileHandleNotificationDataItem];
  NSString* text = [self stringFromData:data];
  NSAttributedString* as =
      [[NSAttributedString alloc] initWithString:text
                                      attributes:kStderrStringAttributes];
  [outputTextView_.textStorage appendAttributedString:as];
  [outputTextView_.textStorage appendAttributedString:kNewlineAttrStr];
  [as release];
  [[notification object] readInBackgroundAndNotify];
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

- (void)eval:(NSString*)line {
  line = [line stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceCharacterSet]];
  if ([line length] == 0) return;
  line = [NSString stringWithFormat:@"require('sys').inspect(%@)", line];
  HandleScope scope;
  NSError *error;
  Local<Value> result = [NodeJS eval:line name:@"<input>" error:&error];
  if (result.IsEmpty()) {
    NSLog(@"eval exception: %@", error);
    [self appendLine:[error localizedDescription]
          attributes:kErrorStringAttributes];
  } else {
    String::Utf8Value utf8str(result->ToString());
    //NSLog(@"eval success: %s", *utf8str);
    [self appendLine:[NSString stringWithUTF8String:*utf8str]
          attributes:kResultStringAttributes];
  }
}


#pragma mark -
#pragma mark NSTextStorageDelegate implementation

/*- (void)textStorageDidProcessEditing:(NSNotification *)notification {
  NSLog(@"textStorageDidProcessEditing");
  [scrollView_ scrollToEndOfDocument:self];
  NSTextStorage	*textStorage = [notification object];
	NSRange	editRange = [textStorage editedRange];
	NSInteger changeInLen = [textStorage changeInLength];
	BOOL wasInUndoRedo = [[textView_ undoManager] isUndoing] ||
                       [[textView_ undoManager] isRedoing];
  NSLog(@"textStorageDidProcessEditing:\n"
        @"  editRange: %@\n"
        @"  changeInLength: %d\n"
        @"  wasInUndoRedo: %s",
        NSStringFromRange(editRange), changeInLen, wasInUndoRedo ? "YES":"NO");
  if (changeInLen > 0) {
    // insertion (or additive replacement)
    
    NSString* str = [[textStorage mutableString] substringWithRange:editRange];
    NSLog(@"added: '%@'", str);
    str = [str stringByReplacingOccurrencesOfString:@"\n" withString:@"\n> "];
    [textStorage replaceCharactersInRange:editRange withString:str];
  }
}*/


#pragma mark -
#pragma mark NSTextViewDelegate implementation


/*- (void)textDidChange:(NSNotification *)notification {
  NSTextStorage* textStorage = textView_.textStorage;
	NSInteger changeInLen = [textStorage changeInLength];
  if (changeInLen > 0) {
    // content was added, so make sure we see everything
    [scrollView_ scrollToEndOfDocument:self];
  }
}*/

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
        [[scrollView_ documentView] scrollToEndOfDocument:self];
      }
    }
  } else {
    // never allow editing of history (prior lines)
    alowEdit = NO;
  }
  
  NSLog(@"alowEdit = %s", alowEdit ? "YES":"NO");
  return alowEdit;
}


- (NSRange)textView:(NSTextView *)aTextView
    willChangeSelectionFromCharacterRange:(NSRange)oldSelectedCharRange
                         toCharacterRange:(NSRange)newSelectedCharRange {
  return newSelectedCharRange;
}

@end
