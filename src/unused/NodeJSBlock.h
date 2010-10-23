#ifndef NODECOCOA_NODEJS_BLOCK_OBJECT_H_
#define NODECOCOA_NODEJS_BLOCK_OBJECT_H_

#include <NodeCocoa/node.h>

typedef void (^NSObjectProxyConfigBlock)(v8::Handle<v8::Template>,
                                         v8::Handle<v8::ObjectTemplate>);

class NodeJSBlockObject : public node::ObjectWrap {
 public:
  static v8::Persistent<v8::FunctionTemplate> constructor_template;
  
  static void Initialize(v8::Handle<v8::Object> target);
  static v8::Handle<v8::Value> New(const v8::Arguments& args);
  static v8::Local<v8::Object> New(void *block);
  
  static v8::Handle<Value> Call(const Arguments& args) {
    fprintf(stderr, "BlockObject::Call\n"); fflush(stderr);
    return Undefined();
  }

  BlockObject(void *block);
  virtual ~BlockObject();
  inline void *Block() { return block_; }

 protected:
  void *block_;
};

#endif // NODECOCOA_NODEJS_BLOCK_OBJECT_H_
