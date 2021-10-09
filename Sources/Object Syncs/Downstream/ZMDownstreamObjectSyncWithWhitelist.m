// 



#import "ZMDownstreamObjectSyncWithWhitelist.h"
#import "ZMDownstreamObjectSync.h"
#import <WireDataModel/ZMManagedObject.h>

@interface ZMDownstreamObjectSyncWithWhitelist () <ZMDownstreamTranscoder>

@property (nonatomic) NSMutableSet *whitelist;
@property (nonatomic) ZMDownstreamObjectSync *innerDownstreamSync;
@property (nonatomic, weak) id<ZMDownstreamTranscoder> transcoder;

@end

@implementation ZMDownstreamObjectSyncWithWhitelist

- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
     predicateForObjectsToDownload:(NSPredicate *)predicateForObjectsToDownload
              managedObjectContext:(NSManagedObjectContext *)moc
{
    self = [super init];
    if(self) {
        self.transcoder = transcoder;
        self.innerDownstreamSync = [[ZMDownstreamObjectSync alloc] initWithTranscoder:self entityName:entityName predicateForObjectsToDownload:predicateForObjectsToDownload filter:nil managedObjectContext:moc];
        self.whitelist = [NSMutableSet set];
    }
    return self;
}

- (void)whiteListObject:(ZMManagedObject *)object;
{
    [self.whitelist addObject:object];
    [self.innerDownstreamSync objectsDidChange:[NSSet setWithObject:object]];
}

- (void)objectsDidChange:(NSSet *)objects;
{
    NSMutableSet *whitelistedObjectsThatChanges = [self.whitelist mutableCopy];
    [whitelistedObjectsThatChanges intersectSet:objects];
    [self.innerDownstreamSync objectsDidChange:whitelistedObjectsThatChanges];
}

- (NSFetchRequest *)fetchRequestForTrackedObjects
{
    // I don't want to fetch. Only objects that are whitelisted should go through
    return nil;
}

- (void)addTrackedObjects:(NSSet __unused *)objects;
{
    // no-op
}

- (BOOL)hasOutstandingItems
{
    return self.innerDownstreamSync.hasOutstandingItems;
}

- (ZMTransportRequest *)nextRequest
{
    return [self.innerDownstreamSync nextRequest];
}

- (ZMTransportRequest *)requestForFetchingObject:(ZMManagedObject *)object downstreamSync:(id<ZMObjectSync> __unused)downstreamSync
{
    return [self.transcoder requestForFetchingObject:object downstreamSync:self];
}

- (void)deleteObject:(ZMManagedObject *)object withResponse:(ZMTransportResponse *)response downstreamSync:(id<ZMObjectSync> __unused)downstreamSync
{
    return [self.transcoder deleteObject:object withResponse:response downstreamSync:self];
}

- (void)updateObject:(ZMManagedObject *)object withResponse:(ZMTransportResponse *)response downstreamSync:(id<ZMObjectSync> __unused)downstreamSync
{
    return [self.transcoder updateObject:object withResponse:response downstreamSync:self];
}

@end
