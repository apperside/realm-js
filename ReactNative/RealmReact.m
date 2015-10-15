////////////////////////////////////////////////////////////////////////////
//
// Copyright 2015 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RealmReact.h"
#import "Base/RCTBridge.h"

@import GCDWebServers;
@import RealmJS;
@import ObjectiveC;
@import Darwin;

@interface NSObject (RCTJavaScriptContext)
- (instancetype)initWithJSContext:(JSGlobalContextRef)context;
- (JSGlobalContextRef)ctx;
@end

JSGlobalContextRef RealmReactGetJSGlobalContextForExecutor(id executor) {
    Ivar contextIvar = class_getInstanceVariable([executor class], "_context");
    id rctJSContext = contextIvar ? object_getIvar(executor, contextIvar) : nil;

    return [rctJSContext ctx];
}

@interface RealmReact () <RCTBridgeModule>
@end

@implementation RealmReact

@synthesize bridge = _bridge;

+ (void)load {
    void (*RCTRegisterModule)(Class) = dlsym(RTLD_DEFAULT, "RCTRegisterModule");

    if (RCTRegisterModule) {
        RCTRegisterModule(self);
    }
    else {
        NSLog(@"Failed to load RCTRegisterModule symbol - %s", dlerror());
    }
}

+ (NSString *)moduleName {
    return @"Realm";
}

- (void)setBridge:(RCTBridge *)bridge {
    _bridge = bridge;

    Ivar executorIvar = class_getInstanceVariable([bridge class], "_javaScriptExecutor");
    id executor = object_getIvar(bridge, executorIvar);
    Ivar contextIvar = class_getInstanceVariable([executor class], "_context");

    // The executor could be a RCTWebSocketExecutor, in which case it won't have a JS context.
    if (!contextIvar) {
        [GCDWebServer setLogLevel:3];
        GCDWebServer *webServer = [[GCDWebServer alloc] init];
        RJSRPCServer *rpcServer = [[RJSRPCServer alloc] init];

        // Add a handler to respond to POST requests on any URL
        [webServer addDefaultHandlerForMethod:@"POST"
                                 requestClass:[GCDWebServerDataRequest class]
                                 processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
            NSError *error;
            NSData *data = [(GCDWebServerDataRequest *)request data];
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            GCDWebServerResponse *response;

            if (error || ![json isKindOfClass:[NSDictionary class]]) {
                NSLog(@"Invalid RPC request - %@", error ?: json);
                response = [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_UnprocessableEntity underlyingError:error message:@"Invalid RPC request"];
            }
            else {
                response = [GCDWebServerDataResponse responseWithJSONObject:[rpcServer performRequest:request.path args:json]];
            }

            [response setValue:@"http://localhost:8081" forAdditionalHeader:@"Access-Control-Allow-Origin"];
            return response;
         }];

        [webServer startWithPort:8082 bonjourName:nil];
        return;
    }

    [executor executeBlockOnJavaScriptQueue:^{
        id rctJSContext = object_getIvar(executor, contextIvar);
        JSGlobalContextRef ctx;

        if (rctJSContext) {
            ctx = [rctJSContext ctx];
        }
        else {
            Class RCTJavaScriptContext = NSClassFromString(@"RCTJavaScriptContext");

            if (RCTJavaScriptContext) {
                ctx = JSGlobalContextCreate(NULL);
                object_setIvar(executor, contextIvar, [[RCTJavaScriptContext alloc] initWithJSContext:ctx]);
            }
            else {
                NSLog(@"Failed to load RCTJavaScriptContext class");
            }
        }

        [RealmJS initializeContext:ctx];
    }];
}

@end
