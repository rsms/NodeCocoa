#import "NS-additions.h"
#import "NodeJSFunction.h"
#import <node_buffer.h>

using namespace v8;

@implementation NSObject (v8)

+ (id)fromV8Value:(v8::Local<v8::Value>)v {
  if (v.IsEmpty()) return nil;
  if (v->IsUndefined() || v->IsNull()) return [NSNull null];
  if (v->IsBoolean()) return [NSNumber numberWithBool:v->BooleanValue()];
  if (v->IsInt32())   return [NSNumber numberWithInt:v->Int32Value()];
  if (v->IsUint32())  return [NSNumber numberWithUnsignedInt:v->Uint32Value()];
  if (v->IsNumber())  return [NSNumber numberWithDouble:v->NumberValue()];
  HandleScope scope;
  if (v->IsExternal())
    return [NSValue valueWithPointer:(External::Unwrap(v))];
  if (v->IsString() || v->IsRegExp())
    return [NSString stringWithV8String:v->ToString()];
  if (v->IsFunction())
    return [NodeJSFunction functionWithFunction:Local<Function>::Cast(v)];
  
  if (v->IsArray()) {
    Local<Array> a = Local<Array>::Cast(v);
    uint32 i = 0, count = a->Length();
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:count];
    for (; i < count; ++i) {
      NSObject *obj = [self fromV8Value:a->Get(i)];
      if (obj) [array addObject:obj];
    }
    return array;
  }
  
  // node::Buffer --> NSData
  if (v->IsObject() && node::Buffer::HasInstance(v)) {
    Local<Object> bufobj = v->ToObject();
    char* data = node::Buffer::Data(bufobj);
    size_t length = node::Buffer::Length(bufobj);
    return [NSData dataWithBytes:data length:length];
  }

  // Date --> NSDate
  if (v->IsDate()) {
    double ms = Local<Date>::Cast(v)->NumberValue();
    return [NSDate dateWithTimeIntervalSince1970:ms/1000.0];
  }

  // Object --> Dictionary
  if (v->IsObject()) {
    Local<Object> o = v->ToObject();
    Local<Array> props = o->GetPropertyNames();
    uint32 i = 0, count = props->Length();
    NSMutableDictionary* dict =
        [NSMutableDictionary dictionaryWithCapacity:count];
    for (; i < count; ++i) {
      Local<String> k = props->Get(i)->ToString();
      NSString *kobj = [NSString stringWithV8String:k];
      NSObject *vobj = [self fromV8Value:o->Get(k)];
      if (vobj)
        [dict setObject:vobj forKey:kobj];
    }
    return dict;
  }
  
  return nil;
}

- (Local<Value>)v8Value {
  // generic converter
  HandleScope scope;
  return scope.Close(String::New([[self description] UTF8String]));
}

@end

@implementation NSNumber (v8)
- (Local<Value>)v8Value {
  HandleScope scope;
  const char *t = [self objCType];
  if (t == @encode(int) || t == @encode(char)) {
    return scope.Close(Integer::New([self intValue]));
  } else if (t == @encode(unsigned int) || t == @encode(unsigned char)) {
    return scope.Close(Integer::New([self unsignedIntValue]));
  } else if (t == @encode(BOOL)) {
    return scope.Close(Local<Value>::New(
        v8::Boolean::New([self boolValue] == YES)));
  }
  return scope.Close(Number::New([self doubleValue]));
}
@end

@implementation NSString (v8)
- (Local<Value>)v8Value {
  HandleScope scope;
  return scope.Close(String::New([self UTF8String]));
}
+ (NSString*)stringWithV8String:(Local<String>)str {
  String::Utf8Value utf8(str);
  return [NSString stringWithUTF8String:*utf8];
}
@end

@implementation NSNull (v8)
- (Local<Value>)v8Value {
  HandleScope scope;
  return scope.Close(Local<Value>::New(v8::Null()));
}
@end

@implementation NSDate (v8)
- (Local<Value>)v8Value {
  HandleScope scope;
  return scope.Close(Date::New((double)[self timeIntervalSince1970] * 1000.0));
}
@end

@implementation NSValue (v8)
- (Local<Value>)v8Value {
  HandleScope scope;
  return scope.Close(External::Wrap([self pointerValue]));
}
@end

@implementation NSArray (v8)
- (Local<Value>)v8Value {
  HandleScope scope;
  NSUInteger i = 0, count = [self count];
  Local<Array> a = Array::New(count);
  for (; i < count; i++) {
    a->Set(i, [[self objectAtIndex:i] v8Value]);
  }
  return scope.Close(a);
}
@end

@implementation NSSet (v8)
- (Local<Value>)v8Value {
  HandleScope scope;
  NSUInteger i = 0, count = [self count];
  Local<Array> a = Array::New(count);
  for (NSObject* obj in self) {
    a->Set(i++, [obj v8Value]);
  }
  return scope.Close(a);
}
@end

@implementation NSDictionary (v8)
- (Local<Value>)v8Value {
  HandleScope scope;
  Local<Object> o = Object::New();
  [self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
    assert([key isKindOfClass:[NSString class]]);
    o->Set(String::New([key UTF8String]), [obj v8Value]);
  }];
  return scope.Close(o);
}
@end
