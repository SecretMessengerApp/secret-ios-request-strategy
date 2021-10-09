// 


#import "ZMUpstreamRequest.h"


@implementation ZMUpstreamRequest

- (instancetype)initWithKeys:(NSSet *)keys transportRequest:(ZMTransportRequest *)transportRequest;
{
    return [self initWithKeys:keys transportRequest:transportRequest userInfo:nil];
}

- (instancetype)initWithKeys:(NSSet *)keys transportRequest:(ZMTransportRequest *)transportRequest userInfo:(NSDictionary *)info;
{
    self = [super init];
    if (self) {
        _keys = [keys copy] ?: [NSSet set];
        _transportRequest = transportRequest;
        _userInfo = [info copy] ?: [NSDictionary dictionary];
    }
    return self;
}


- (instancetype)initWithTransportRequest:(ZMTransportRequest *)transportRequest;
{
    self = [self initWithKeys:nil transportRequest:transportRequest userInfo:nil];
    return self;
}

- (NSString *)debugDescription;
{
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p>", self.class, self];
    if (self.keys.count == 0) {
        [description appendString:@" no keys"];
    } else {
        [description appendFormat:@" keys = {%@}", [self.keys.allObjects componentsJoinedByString:@", "]];
    }
    [description appendString:@", transport request: "];
    [description appendString:self.transportRequest.debugDescription];
    return description;
}

@end

