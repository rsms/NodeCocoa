#ifndef NODEJS_NSOBJECT_PROXY_H
#define NODEJS_NSOBJECT_PROXY_H

#include <NodeJS/node.h>

typedef void (^NSObjectProxyConfigBlock)(v8::Handle<v8::Template>,
                                         v8::Handle<v8::ObjectTemplate>);

/**
 * An object that acts as a proxy to a NSObject.
 *
 * In Objective-C++:
 *   NSObject *obj = ...;
 *   Local<Object> global = Context::GetCurrent()->Global();
 *   global->Set(String::New("obj"), NSObjectProxy::New(obj));
 *
 * Calling from v8-land:
 *   obj.foo
 *   obj.bar_withCode("bararg", "codearg")
 *
 * Will retrieve @property "foo" and invoke method |bar:withCode:| on the
 * NSObject instance.
 */
class NSObjectProxy : public node::ObjectWrap {
 public:
  NSObjectProxy(NSObject *target);
  virtual ~NSObjectProxy();
  static v8::Handle<v8::Value> New(const v8::Arguments& args);
  static v8::Local<v8::Object> New(NSObject *target,
                                    NSObjectProxyConfigBlock configBlock=NULL);
  static void SetTarget(v8::Handle<v8::Object> self, NSObject *target);
  
  void SetTarget(NSObject *target);
  inline NSObject *Target() { return target_; }

 protected:
  NSObject *target_;
};

inline NSObject* NSObjectProxyUnwrap(v8::Handle<v8::Object> self) {
  assert(!self.IsEmpty());
  return (NSObject*)self->GetPointerFromInternalField(0);
}

#endif // NODEJS_NSOBJECT_PROXY_H
