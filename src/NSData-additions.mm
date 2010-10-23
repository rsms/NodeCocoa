#import <node_buffer.h>

using namespace v8;

@implementation NSData (node)

- (Local<Value>)v8Representation {
  HandleScope scope;
  
  // Note: The following _might_ cause a race condition if called at the same
  // time by two node threads and might cause unknown magic spooky stuff if
  // called by one node thread and later used by another.
  static Persistent<Function> BufferConstructor;
  if (BufferConstructor.IsEmpty()) {
    HandleScope tmplscope;
    Local<Object> global = Context::GetCurrent()->Global();
    Local<Value> Buffer_v = global->Get(String::NewSymbol("Buffer"));
    assert(Buffer_v->IsFunction());
    BufferConstructor = Persistent<Function>::New(
        tmplscope.Close(Local<Function>::Cast(Buffer_v)));
  }
  
  Local<Value> argv[] = {Integer::New([self length])};
  Local<Value> buf = BufferConstructor->NewInstance(1, argv);
  
  char *dataptr = node::Buffer::Data(Local<Object>::Cast(buf));
  assert(dataptr != NULL);
  [self getBytes:dataptr length:[self length]];
  
  return scope.Close(buf);
}

@end
