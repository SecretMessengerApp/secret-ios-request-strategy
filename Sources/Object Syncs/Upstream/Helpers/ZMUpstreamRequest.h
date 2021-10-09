//
//


@import WireTransport;


@interface ZMUpstreamRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithKeys:(NSSet<NSString *> *)keys transportRequest:(ZMTransportRequest *)transportRequest;
- (instancetype)initWithKeys:(NSSet<NSString *> *)keys transportRequest:(ZMTransportRequest *)transportRequest userInfo:(NSDictionary *)info NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithTransportRequest:(ZMTransportRequest *)transportRequest;


@property (nonatomic, readonly) NSSet<NSString *> *keys;
@property (nonatomic, readonly) ZMTransportRequest *transportRequest;
@property (nonatomic) ZMTransportResponse *transportResponse;
@property (nonatomic, readonly) NSDictionary *userInfo;

@end
