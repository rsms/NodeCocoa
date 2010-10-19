#import "NSObject+v8.h"

using namespace v8;

@implementation NSObject (v8)
- (Local<Value>)v8Representation {
  return String::New([[self description] UTF8String]);
}
@end

@implementation NSNumber (v8)
- (Local<Value>)v8Representation {
  const char *t = [self objCType];
  if (t == @encode(int) || t == @encode(char)) {
    return Integer::New([self intValue]);
  } else if (t == @encode(unsigned int) || t == @encode(unsigned char)) {
    return Integer::New([self unsignedIntValue]);
  } else if (t == @encode(BOOL)) {
    return Local<Value>::New(v8::Boolean::New([self boolValue] == YES));
  }
  return Number::New([self doubleValue]);
}
@end

@implementation NSNull (v8)
- (Local<Value>)v8Representation {
  return Local<Value>::New(v8::Null());
}
@end


