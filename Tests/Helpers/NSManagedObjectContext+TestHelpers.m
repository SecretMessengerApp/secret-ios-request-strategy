// 

@import WireTesting;

#import "NSManagedObjectContext+TestHelpers.h"

@implementation NSManagedObjectContext (TestHelpers)

- (void)performGroupedBlockAndWaitWithReasonableTimeout:(dispatch_block_t)block;
{
    NSTimeInterval timeInterval2 = [ZMTBaseTest timeToUseForOriginalTime:100];
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeInterval2];

    __block BOOL done = NO;
    [self performGroupedBlock:^{
        block();
        done = YES;
    }];
    
    while (! done && (0. < [end timeIntervalSinceNow])) {
        [ZMTBaseTest performRunLoopTick];
    }
    NSAssert(done, @"Wait failed");
}

@end
