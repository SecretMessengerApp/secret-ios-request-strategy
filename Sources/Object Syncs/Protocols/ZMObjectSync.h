// 


#import <WireRequestStrategy/ZMContextChangeTracker.h>
#import <WireRequestStrategy/ZMRequestGenerator.h>
#import <WireRequestStrategy/ZMOutstandingItems.h>

@protocol ZMObjectSync <NSObject, ZMContextChangeTracker, ZMOutstandingItems, ZMRequestGenerator>
@end
