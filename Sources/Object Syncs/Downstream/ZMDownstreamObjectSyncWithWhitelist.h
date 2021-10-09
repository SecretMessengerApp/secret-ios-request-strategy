// 

@import  CoreData;

#import <WireRequestStrategy/ZMObjectSync.h>

@protocol ZMDownstreamTranscoder;
@class ZMManagedObject;

/// ZMDownstreamObjectSync with support for whitelisting. Only whitelisted objects matching the predicate will be downloaded

@interface ZMDownstreamObjectSyncWithWhitelist : NSObject <ZMObjectSync>

/// @param predicateForObjectsToDownload the predicate that will be used to select which object to download
- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
     predicateForObjectsToDownload:(NSPredicate *)predicateForObjectsToDownload
              managedObjectContext:(NSManagedObjectContext *)moc;

/// Adds an object to the whitelist. It will later be removed once downloaded and not matching the whitelist predicate
- (void)whiteListObject:(ZMManagedObject *)object;

/// Returns a request to download the next object
- (ZMTransportRequest *)nextRequest;

@end
