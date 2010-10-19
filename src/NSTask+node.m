#import "NSTask+node.h"

@implementation NSTask (node)

+ (NSString*)outputForShellCommand:(NSString*)cmd status:(int*)status {
  cmd = [cmd stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
  cmd = [NSString stringWithFormat:@"/bin/bash -lc '%@'", cmd];
  NSMutableString* output = [NSMutableString string];
  const int bufsize = 4096;
  FILE *fpipe;
  char buf[bufsize];
  if ( !(fpipe = (FILE*)popen([cmd UTF8String], "r")) ) {
    if (status) *status = -1;
    return nil;
  }
  fflush(fpipe);
  while (fgets(buf, sizeof(char)*bufsize, fpipe)) {
    [output appendString:[NSString stringWithUTF8String:buf]];
    fflush(fpipe);
  }
  fflush(fpipe);
  while (fgets(buf, sizeof(char)*bufsize, fpipe)) {
    [output appendString:[NSString stringWithUTF8String:buf]];
    fflush(fpipe);
  }
  int st = pclose(fpipe);
  if (status) *status = st;
  return output;
}

+ (NSString*)outputForShellCommand:(NSString*)cmd {
  return [self outputForShellCommand:cmd status:nil];
}

@end