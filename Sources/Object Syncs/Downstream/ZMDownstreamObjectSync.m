// 


@import CoreData;
@import WireTransport;
@import WireDataModel;

#import "ZMDownstreamObjectSync.h"
#import "ZMSyncOperationSet.h"

@interface ZMDownstreamObjectSync ()

@property (nonatomic, weak) id<ZMDownstreamTranscoder> transcoder;
@property (nonatomic) ZMSyncOperationSet *objectsToDownload;
@property (nonatomic) NSManagedObjectContext *context;
@property (nonatomic) NSEntityDescription *entity;
@property (nonatomic) NSPredicate *predicateForObjectsToDownload;
@property (nonatomic) NSPredicate *filter; //additional optional predication to filter objectis by not persisted properties

@end



@implementation ZMDownstreamObjectSync

- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
              managedObjectContext:(NSManagedObjectContext *)moc;
{
    NSPredicate *predicateForObjectsToDownload = [NSPredicate predicateWithFormat:@"needsToBeUpdatedFromBackend == YES"];
    return [self initWithTranscoder:transcoder entityName:entityName predicateForObjectsToDownload:predicateForObjectsToDownload managedObjectContext:moc];
}

- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
     predicateForObjectsToDownload:(NSPredicate *)predicateForObjectsToDownload
              managedObjectContext:(NSManagedObjectContext *)moc;
{
    ZMSyncOperationSet *set = [[ZMSyncOperationSet alloc] init];
    return [self initWithTranscoder:transcoder operationSet:set entityName:entityName predicateForObjectsToDownload:predicateForObjectsToDownload filter:nil managedObjectContext:moc];
}

- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
     predicateForObjectsToDownload:(NSPredicate *)predicateForObjectsToDownload
                            filter:(NSPredicate *)filter
              managedObjectContext:(NSManagedObjectContext *)moc;
{
    ZMSyncOperationSet *set = [[ZMSyncOperationSet alloc] init];
    return [self initWithTranscoder:transcoder operationSet:set entityName:entityName predicateForObjectsToDownload:predicateForObjectsToDownload filter:filter managedObjectContext:moc];
}

- (instancetype)initWithTranscoder:(id<ZMDownstreamTranscoder>)transcoder
                      operationSet:(ZMSyncOperationSet *)operationSet
                        entityName:(NSString *)entityName
     predicateForObjectsToDownload:(NSPredicate *)predicateForObjectsToDownload
                            filter:(NSPredicate *)filter
              managedObjectContext:(NSManagedObjectContext *)moc;
{
    VerifyReturnNil(transcoder != nil);
    VerifyReturnNil(operationSet != nil);
    VerifyReturnNil(entityName != nil);
    VerifyReturnNil(predicateForObjectsToDownload != nil);
    VerifyReturnNil(moc != nil);
    self = [super init];
    if (self) {
        self.transcoder = transcoder;
        self.objectsToDownload = operationSet;
        self.context = moc;
        self.entity = self.context.persistentStoreCoordinator.managedObjectModel.entitiesByName[entityName];
        VerifyReturnNil(self.entity != nil);
        self.objectsToDownload.sortDescriptors = [NSClassFromString(self.entity.managedObjectClassName) sortDescriptorsForUpdating];
        self.predicateForObjectsToDownload = predicateForObjectsToDownload;
        self.filter = filter;
    }
    return self;
}

- (NSFetchRequest *)fetchRequestForTrackedObjects
{
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    request.entity = self.entity;
    request.predicate = self.predicateForObjectsToDownload;
    return request;
}

- (void)addTrackedObjects:(NSSet *)objects;
{
    for (ZMManagedObject *mo in objects) {
        if(self.filter == nil || [self.filter evaluateWithObject:mo]) {
            [self.objectsToDownload addObjectToBeSynchronized:mo];
        }
    }
}

- (BOOL)needsToSyncObject:(NSObject *)object
{
    return [self.predicateForObjectsToDownload evaluateWithObject:object] &&
           (self.filter == nil || [self.filter evaluateWithObject:object]);
}

- (void)objectsDidChange:(NSSet *)objects
{
    for (ZMManagedObject* mo in objects) {
        if (mo.entity != self.entity) {
            continue;
        }
        if ([self needsToSyncObject:mo]) {
            [self.objectsToDownload addObjectToBeSynchronized:mo];
        }
    }
}

- (ZMTransportRequest *)nextRequest;
{
    id<ZMDownstreamTranscoder> transcoder = self.transcoder;

    ZMManagedObject *nextObject;
    while ( (nextObject = [self.objectsToDownload nextObjectToSynchronize]) != nil) {

        if(![self.predicateForObjectsToDownload evaluateWithObject:nextObject]) {
            [self.objectsToDownload removeObject:nextObject];
            continue;
        }
    
        ZMTransportRequest *request = [transcoder requestForFetchingObject:nextObject downstreamSync:self];
        if(request == nil) {
            [self.objectsToDownload removeObject:nextObject];
            continue;
        }
        [request setDebugInformationTranscoder:transcoder];
        
        ZMSyncToken *token = [self.objectsToDownload didStartSynchronizingKeys:nil forObject:nextObject];
        ZM_WEAK(self);
        [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:nextObject.managedObjectContext block:^(ZMTransportResponse *response) {
            ZM_STRONG(self);
            [self processResponse:response forObject:nextObject token:token transcoder:self.transcoder];
        }]];
        return request;
    }
    
    return nil;
}

- (BOOL)hasOutstandingItems;
{
    return (0 < self.objectsToDownload.count);
}

- (void)processResponse:(ZMTransportResponse *)response forObject:(ZMManagedObject *)object token:(ZMSyncToken *)token transcoder:(id<ZMDownstreamTranscoder>)transcoder
{
    NSSet *keys = [self.objectsToDownload keysForWhichToApplyResultsAfterFinishedSynchronizingSyncWithToken:token forObject:object result:response.result];
    switch (response.result) {
        case ZMTransportResponseStatusTryAgainLater: {
            break;
        }
        case ZMTransportResponseStatusSuccess: {
            [self.objectsToDownload removeUpdatedObject:object syncToken:token synchronizedKeys:keys];
            
            if(! object.isZombieObject) {
                [transcoder updateObject:object withResponse:response downstreamSync:self];
            }
            break;
        }
        case ZMTransportResponseStatusTemporaryError:
        case ZMTransportResponseStatusPermanentError:
        case ZMTransportResponseStatusExpired: {
            [self.objectsToDownload removeObject:object];
            [transcoder deleteObject:object withResponse:response downstreamSync:self];
            break;
        }
    }
    [object.managedObjectContext enqueueDelayedSaveWithGroup:response.dispatchGroup];
}

- (NSString *)debugDescription;
{
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p>", self.class, self];
    [description appendFormat:@" %@", self.entity.name];
    NSObject *t = (id) self.transcoder;
    [description appendFormat:@", transcoder: <%@ %p>", t.class, t];
    [description appendFormat:@", context: \"%@\"", self.context];
    return description;
}

@end
