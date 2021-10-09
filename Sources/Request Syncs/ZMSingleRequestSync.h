// 


@import Foundation;
@import CoreData;

@class ZMTransportRequest;
@class ZMTransportResponse;
@class ZMSingleRequestSync;

NS_ASSUME_NONNULL_BEGIN

@protocol ZMSingleRequestTranscoder <NSObject>

- (ZMTransportRequest * __nullable)requestForSingleRequestSync:(ZMSingleRequestSync *)sync;
- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync *)sync;

@end

typedef NS_ENUM(int, ZMSingleRequestProgress) {
    ZMSingleRequestIdle = 0,
    ZMSingleRequestReady,
    ZMSingleRequestInProgress,
    ZMSingleRequestCompleted
};


@interface ZMSingleRequestSync : NSObject

@property (nonatomic, readonly, weak) id<ZMSingleRequestTranscoder> __nullable transcoder;
@property (nonatomic, readonly) ZMSingleRequestProgress status;
@property (nonatomic, readonly) id<ZMSGroupQueue> groupQueue;

- (instancetype)initWithSingleRequestTranscoder:(id<ZMSingleRequestTranscoder>)transcoder groupQueue:(id<ZMSGroupQueue>)groupQueue;

+ (instancetype)syncWithSingleRequestTranscoder:(id<ZMSingleRequestTranscoder>)transcoder groupQueue:(id<ZMSGroupQueue>)groupQueue;

/// Marks as need to request, even if it's already performing a request (will abort that request)
- (void)readyForNextRequest;
/// Marks as need request, only if it's not requesting already
- (void)readyForNextRequestIfNotBusy;

/// mark the completion as "noted" by the client, and goes back to the idle state
- (void)resetCompletionState;

- (ZMTransportRequest *__nullable)nextRequest;

@end

NS_ASSUME_NONNULL_END
