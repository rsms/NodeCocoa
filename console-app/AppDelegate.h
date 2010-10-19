@interface AppDelegate : NSObject <NSApplicationDelegate,
                                   NSTextViewDelegate,
                                   NSTextStorageDelegate> {
  NSWindow* window_;
  NSTextView* textView_;
  NSScrollView* scrollView_;
  NSTextView* outputTextView_;
  NSScrollView* outputScrollView_;
  NSPipe* nodeStdoutPipe_;
  NSPipe* nodeStderrPipe_;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSTextView *textView, *outputTextView;
@property (assign) IBOutlet NSScrollView* scrollView, *outputScrollView;

- (void)appendText:(NSString*)text attributes:(NSDictionary*)attrs;
- (void)appendLine:(NSString*)line attributes:(NSDictionary*)attrs;
- (void)appendLine:(NSString*)line;

@end
