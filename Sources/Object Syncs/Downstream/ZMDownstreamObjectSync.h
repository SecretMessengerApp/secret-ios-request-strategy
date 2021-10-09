// 


@import Foundation;
@import CoreData;
#import <WireRequestStrategy/ZMObjectSync.h>

@protocol ZMTransportData;
@class ZMTransportRequest;
@class ZMManagedObject;
@class ZMSyncOperationSet;
@class NSManagedObjectContext;
@protocol ZMDownstreamTranscoder;
@class ZMTransportResponse;


@interface ZMDownstreamObjectSync : NSObject <ZMObjectSync>

- (instancetype)init NS_UNAVAILABLE;

/// Calls @c -initWithTranscoder:entityName:predicate:managedObjectContext:
/// with @c predicate set to
/// @code
/// [NSPredicate predicateWithFormat:@"needsToBeUpdatedFromBackend == YES"]
/// @endcode
- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
              managedObjectContext:(NSManagedObjectContext *)moc;

/// The @c predicate is used to filter objects that need to be downloaded. It should return
/// @c YES if the object needs to be downloaded and @c NO otherwise.
- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
     predicateForObjectsToDownload:(NSPredicate *)predicateForObjectsToDownload
              managedObjectContext:(NSManagedObjectContext *)moc;

- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
     predicateForObjectsToDownload:(NSPredicate *)predicateForObjectsToDownload
                            filter:(NSPredicate *)filter
              managedObjectContext:(NSManagedObjectContext *)moc;

- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                      operationSet:(ZMSyncOperationSet *)operationSet
                        entityName:(NSString *)entityName
     predicateForObjectsToDownload:(NSPredicate *)predicateForObjectsToDownload
                            filter:(NSPredicate *)filter
              managedObjectContext:(NSManagedObjectContext *)moc NS_DESIGNATED_INITIALIZER;

- (ZMTransportRequest *)nextRequest;

@property (nonatomic, readonly) NSPredicate *predicateForObjectsToDownload;
@property (nonatomic, readonly) NSEntityDescription *entity;

@end



@protocol ZMDownstreamTranscoder <NSObject>

- (ZMTransportRequest *)requestForFetchingObject:(ZMManagedObject *)object downstreamSync:(id<ZMObjectSync>)downstreamSync;
- (void)deleteObject:(ZMManagedObject *)object withResponse:(ZMTransportResponse *)response downstreamSync:(id<ZMObjectSync>)downstreamSync;
- (void)updateObject:(ZMManagedObject *)object withResponse:(ZMTransportResponse *)response downstreamSync:(id<ZMObjectSync>)downstreamSync;

@end
