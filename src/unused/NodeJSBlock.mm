#include "NSObjectProxy.h"
#include <objc/objc-runtime.h>

using namespace v8;

inline NSObject* NSObjectProxyUnwrap(const v8::AccessorInfo& info) {
  assert(!info.Holder().IsEmpty());
  return (NSObject*)info.This()->GetPointerFromInternalField(0);
}

inline NSObject* NSObjectProxyUnwrap(const v8::Arguments& args) {
  assert(!args.Holder().IsEmpty());
  return (NSObject*)args.This()->GetPointerFromInternalField(0);
}

static v8::Handle<Value> _Get(Local<String> property, const AccessorInfo& info){
  NSObject* obj = NSObjectProxyUnwrap(info);
  String::Utf8Value utf8str(property);
  NSLog(@"_Get %s (obj=%p)", *utf8str, obj);
  if (obj) {
    Class cls = [obj class];
    String::Utf8Value utf8str(property);
    objc_property_t objcProp = class_getProperty(cls, *utf8str);
    if (objcProp) {
      // it's a property
      const char *attrs = property_getAttributes(objcProp);
      // @property (assign) IBOutlet NSWindow *window = window_;
      // T@"NSWindow",Vwindow_
      NSLog(@"attrs %s", attrs);
    } else {
      // it might be a method
      /*NSString* sel = [NSString stringWithUTF8String:*utf8str];
      sel = [sel stringByReplacingOccurrencesOfString:@"_" withString:@":"];
      Method method = class_getInstanceMethod(cls, SEL name);
      struct objc_method_description *method_getDescription(Method m)*/
    }
  }
  return Local<Value>();
}

// Returns the value if the setter intercepts the request.
// Otherwise, returns an empty handle.
static v8::Handle<Value> _Set(Local<String> property,
                                  Local<Value> value,
                                  const AccessorInfo& info) {
  //NSObject* obj = NSObjectProxyUnwrap(info);
  String::Utf8Value utf8str(property->ToString());
  NSLog(@"_Set %s", *utf8str);
  return Local<Value>();
}

// Returns a non-empty handle if the interceptor intercepts the request.
// The result is an integer encoding property attributes (like v8::None,
// v8::DontEnum, etc.)
static v8::Handle<Integer> _Query(Local<String> property,
                                      const AccessorInfo& info) {
  String::Utf8Value utf8str(property->ToString());
  NSLog(@"_Query %s", *utf8str);
  return Local<Integer>();
}

// Returns a non-empty handle if the deleter intercepts the request.
// The return value is true if the property could be deleted and false
// otherwise.
static v8::Handle<v8::Boolean> _Delete(Local<String> property,
                                          const AccessorInfo& info) {
  String::Utf8Value utf8str(property->ToString());
  NSLog(@"_Delete %s", *utf8str);
  return Local<v8::Boolean>();
}

// Returns an array containing the names of the properties the named
// property getter intercepts.
static v8::Handle<Array> _Enumerator(const AccessorInfo& info) {
  NSLog(@"_Enumerator");
  //unsigned int propertyCount;
	//objc_property_t* properties = class_copyPropertyList(self, &propertyCount);
  //Method *class_copyMethodList(Class cls, unsigned int *outCount)
  return Local<Array>();
}

// -----------------------------------------------------------------------------
// NSObjectProxy implementation

NSObjectProxy::NSObjectProxy(NSObject *target) {
  if (target)
    target_ = [target retain];
}

NSObjectProxy::~NSObjectProxy() {
  if (target_)
    [target_ release];
}

v8::Handle<Value> NSObjectProxy::New(const Arguments& args) {
  (new NSObjectProxy(NULL))->Wrap(args.This());
  return args.This();
}

Local<Object> NSObjectProxy::New(NSObject *target,
                                 NSObjectProxyConfigBlock configBlock) {
  HandleScope scope;
  Local<FunctionTemplate> t = FunctionTemplate::New(New);
  t->SetClassName(String::NewSymbol("NSObjectProxy"));
  Local<Template> proto_t = t->PrototypeTemplate();
  Local<ObjectTemplate> instance_t = t->InstanceTemplate();
  if (configBlock)
    configBlock(proto_t, instance_t);
  instance_t->SetInternalFieldCount(1);
  instance_t->SetNamedPropertyHandler(&_Get,
                                      &_Set,
                                      &_Query,
                                      &_Delete,
                                      &_Enumerator);
  Local<Object> obj = t->GetFunction()->NewInstance();
  obj->SetPointerInInternalField(0, (void*)(target ? [target retain] : nil));
  return obj;
}

void NSObjectProxy::SetTarget(v8::Handle<Object> self, NSObject *target) {
  HandleScope scope;
  NSObject *old = NSObjectProxyUnwrap(self);
  self->SetPointerInInternalField(0, (void*)(target ? [target retain] : nil));
  if (old) [old release];
}

void NSObjectProxy::SetTarget(NSObject *target) {
  NSObject *old = target_;
  target_ = target ? [target retain] : nil;
  if (old) [old release];
}
