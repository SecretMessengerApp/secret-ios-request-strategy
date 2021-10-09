////
//

#import <Foundation/Foundation.h>
@import WireTransport;

/// A request strategy decides what is the next request to send
@protocol RequestStrategy <NSObject>

- (nullable ZMTransportRequest *)nextRequest;

@end
