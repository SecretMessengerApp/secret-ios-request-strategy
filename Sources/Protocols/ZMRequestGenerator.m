// 


@import WireUtilities;

#import "ZMRequestGenerator.h"


@implementation NSArray (ZMRequestGeneratorSource)

- (ZMTransportRequest *)nextRequest;
{
    ZMTransportRequest *request = [self firstNonNilReturnedFromSelector:@selector(nextRequest)];
    return request;
}

@end
