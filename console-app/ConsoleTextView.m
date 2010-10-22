#import "ConsoleTextView.h"

@interface NSObject (ConsoleTextView)
- (void)consoleTextViewArrowUpKeyEvent:(NSEvent*)event;
- (void)consoleTextViewArrowDownKeyEvent:(NSEvent*)event;
- (void)consoleTextViewEscKeyEvent:(NSEvent*)event;
- (void)consoleTextViewTabKeyEvent:(NSEvent*)event;
@end

@implementation ConsoleTextView

- (void)interpretKeyEvents:(NSArray *)events {
  NSEvent* ev0 = [events objectAtIndex:0];
  unsigned short keyCode = [ev0 keyCode];
  switch (keyCode) {
    case 126:
    case 125:
    case 53:
    case 48: {
      id d = [self delegate];
      if (!d) break;
      if (keyCode == 126) {  // arrow up
        if ([d respondsToSelector:@selector(consoleTextViewArrowUpKeyEvent:)])
          [d consoleTextViewArrowUpKeyEvent:ev0];
      } else if (keyCode == 125) {  // arrow down
        if ([d respondsToSelector:@selector(consoleTextViewArrowDownKeyEvent:)])
          [d consoleTextViewArrowDownKeyEvent:ev0];
      } else if (keyCode == 53) {  // ESC
        if ([d respondsToSelector:@selector(consoleTextViewEscKeyEvent:)])
          [d consoleTextViewEscKeyEvent:ev0];
      } else if (keyCode == 48) {  // TAB
        if ([d respondsToSelector:@selector(consoleTextViewTabKeyEvent:)])
          [d consoleTextViewTabKeyEvent:ev0];
      }
      break;
    }
    default:
      //printf("(ev 1 of %lu) keyCode = %u\n",
      //       (unsigned long)events.count, keyCode);
      [super interpretKeyEvents:events];
  }
}

@end
