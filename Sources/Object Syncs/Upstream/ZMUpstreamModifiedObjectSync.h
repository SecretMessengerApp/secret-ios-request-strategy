// 


@import WireTransport;

#import <WireRequestStrategy/ZMContextChangeTracker.h>
#import <WireRequestStrategy/ZMOutstandingItems.h>
#import <WireRequestStrategy/ZMRequestGenerator.h>

@class ZMTransportRequest;
@class ZMTransportResponse;
@protocol ZMUpstreamTranscoder;


@interface ZMUpstreamModifiedObjectSync : NSObject <ZMContextChangeTracker, ZMOutstandingItems, ZMRequestGenerator>

- (instancetype)initWithTranscoder:(id<ZMUpstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
              managedObjectContext:(NSManagedObjectContext *)context;


- (instancetype)initWithTranscoder:(id<ZMUpstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
                        keysToSync:(NSArray<NSString *> *)keysToSync
              managedObjectContext:(NSManagedObjectContext *)context;


/// The @c ZMUpstreamTranscoder can use @c keysToSync to limit the keys that are supposed to be synchronized.
/// If not implemented or nil, all keys will be synchronized, otherwise only those in the set.
- (instancetype)initWithTranscoder:(id<ZMUpstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
                   updatePredicate:(NSPredicate *)updatePredicate
                            filter:(NSPredicate *)filter
                        keysToSync:(NSArray<NSString *> *)keysToSync
              managedObjectContext:(NSManagedObjectContext *)context;

- (ZMTransportRequest *)nextRequest;

@end

