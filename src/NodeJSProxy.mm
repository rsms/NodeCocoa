#import "NodeJSProxy.h"

using namespace v8;

@implementation NodeJSProxy

+ (Local<Object>)proxyForNSObject:(NSObject*)target
                configuredByBlock:(NSObjectProxyConfigBlock)block {
  HandleScope scope;
  Local<Object> proxy = NSObjectProxy::New(target, block);
  return proxy;
}

+ (Local<Object>)proxyForNSObject:(NSObject*)target {
  return [self proxyForNSObject:target configuredByBlock:nil];
}

@end
