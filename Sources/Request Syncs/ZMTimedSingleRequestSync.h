// 


#import <Foundation/Foundation.h>
#import <WireRequestStrategy/ZMSingleRequestSync.h>

@class ZMTransportRequest;
@protocol ZMSGroupQueue;

@interface ZMTimedSingleRequestSync : ZMSingleRequestSync

/// setting this stops the current timer
@property (nonatomic) NSTimeInterval timeInterval;


- (instancetype)initWithSingleRequestTranscoder:(id<ZMSingleRequestTranscoder>)transcoder
                                     groupQueue:(id<ZMSGroupQueue>)groupQueue NS_UNAVAILABLE;

- (instancetype)initWithSingleRequestTranscoder:(id<ZMSingleRequestTranscoder>)transcoder
                              everyTimeInterval:(NSTimeInterval) timeInterval
                                     groupQueue:(id<ZMSGroupQueue>)groupQueue NS_DESIGNATED_INITIALIZER;

/// cancels the timer and stop returning requests
- (void)invalidate;

@end
