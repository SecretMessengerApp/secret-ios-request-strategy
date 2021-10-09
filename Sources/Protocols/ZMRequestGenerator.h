// 


@class ZMTransportRequest;



@protocol ZMRequestGenerator <NSObject>

- (ZMTransportRequest * __nullable)nextRequest;

@end



@protocol ZMRequestGeneratorSource <NSObject>

@property (nonatomic, readonly, nonnull) NSArray<id<ZMRequestGenerator>> *requestGenerators; /// Array of objects that implement nextRequest

@end



@interface NSArray (ZMRequestGeneratorSource)

- (ZMTransportRequest * __nullable)nextRequest;

@end
