#import <NodeJS/node.h>
#import <NodeJS/NSObjectProxy.h>

@interface NodeJSProxy : NSObject {
}

+ (v8::Local<v8::Object>)proxyForNSObject:(NSObject*)target;
+ (v8::Local<v8::Object>)proxyForNSObject:(NSObject*)target
                        configuredByBlock:(NSObjectProxyConfigBlock)block;

@end

