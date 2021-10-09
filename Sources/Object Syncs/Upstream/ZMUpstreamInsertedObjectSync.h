// 


@import Foundation;

#import "ZMContextChangeTracker.h"
#import <WireRequestStrategy/ZMRequestGenerator.h>

@protocol ZMTransportData;
@class ZMTransportRequest;
@class ZMManagedObject;
@class ZMUpstreamRequest;
@class ZMTransportResponse;
@protocol ZMUpstreamTranscoder;



@interface ZMUpstreamInsertedObjectSync : NSObject <ZMContextChangeTracker, ZMRequestGenerator>

@property (nonatomic, readonly) BOOL hasCurrentlyRunningRequests;
@property (nonatomic)           BOOL logPredicateActivity;

- (instancetype)initWithTranscoder:(id<ZMUpstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
              managedObjectContext:(NSManagedObjectContext *)context;

- (instancetype)initWithTranscoder:(id<ZMUpstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
                            filter:(NSPredicate *)filter
              managedObjectContext:(NSManagedObjectContext *)context;

- (ZMTransportRequest *)nextRequest;

@end
