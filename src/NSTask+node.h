@interface NSTask (node)
+ (NSString*)outputForShellCommand:(NSString*)cmd status:(int*)status;
+ (NSString*)outputForShellCommand:(NSString*)cmd;
@end
