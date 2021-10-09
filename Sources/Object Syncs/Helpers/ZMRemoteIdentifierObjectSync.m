// 


@import WireTransport;
@import WireDataModel;

#import "ZMRemoteIdentifierObjectSync.h"

@interface ZMRemoteIdentifierObjectSync ()

@property (nonatomic, weak) id <ZMRemoteIdentifierObjectTranscoder> transcoder;
@property (nonatomic) NSManagedObjectContext *managedObjectContext;
@property (nonatomic) NSMutableOrderedSet *remoteIdentifiersThatNeedToBeDownloaded;
@property (nonatomic) NSMutableSet *remoteIdentifiersInProgress;


@end



@implementation ZMRemoteIdentifierObjectSync


- (instancetype)initWithTranscoder:(id<ZMRemoteIdentifierObjectTranscoder>)transcoder managedObjectContext:(NSManagedObjectContext *)moc;
{
    self = [super init];
    if (self) {
        self.transcoder = transcoder;
        self.managedObjectContext = moc;
        self.remoteIdentifiersInProgress = [NSMutableSet set];
        self.remoteIdentifiersThatNeedToBeDownloaded = [NSMutableOrderedSet orderedSet];
    }
    return self;
}

- (ZMTransportRequest *)nextRequest;
{
    if (self.remoteIdentifiersThatNeedToBeDownloaded.count == 0) {
        return nil;
    }

    id <ZMRemoteIdentifierObjectTranscoder> transcoder = self.transcoder;
    NSUInteger count = [transcoder maximumRemoteIdentifiersPerRequestForObjectSync:self];
    count = MIN(count, self.remoteIdentifiersThatNeedToBeDownloaded.count);
    
    NSSet *IDs = [[NSOrderedSet orderedSetWithOrderedSet:self.remoteIdentifiersThatNeedToBeDownloaded range:NSMakeRange(0, count) copyItems:NO] set];
                         
    [self.remoteIdentifiersInProgress unionSet:IDs];
    [self.remoteIdentifiersThatNeedToBeDownloaded minusSet:IDs];
    
    ZMTransportRequest *request = [transcoder requestForObjectSync:self remoteIdentifiers:IDs];
    [request setDebugInformationTranscoder:transcoder];

    Require(request != nil);
    ZM_WEAK(self);
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.managedObjectContext block:^(ZMTransportResponse *response) {
        ZM_STRONG(self);
        switch (response.result) {
            case ZMTransportResponseStatusPermanentError:
            case ZMTransportResponseStatusSuccess: {
                [self.remoteIdentifiersInProgress minusSet:IDs];
                [self.transcoder didReceiveResponse:response remoteIdentifierObjectSync:self forRemoteIdentifiers:IDs];
                break;
            }
            case ZMTransportResponseStatusExpired:
                break;
            case ZMTransportResponseStatusTemporaryError:
            case ZMTransportResponseStatusTryAgainLater: {
                [self.remoteIdentifiersThatNeedToBeDownloaded unionSet:IDs];
                [self.remoteIdentifiersInProgress minusSet:IDs];
                [self sortIdentifiers];
                break;
            }
        }
        [self.managedObjectContext enqueueDelayedSave];
    }]];
    return request;
}

- (void)setRemoteIdentifiersAsNeedingDownload:(NSSet<NSUUID *> *)remoteIdentifiers;
{
    [self.remoteIdentifiersThatNeedToBeDownloaded removeAllObjects];
    [self.remoteIdentifiersThatNeedToBeDownloaded addObjectsFromArray:remoteIdentifiers.allObjects];
    [self sortIdentifiers];
}

- (void)addRemoteIdentifiersThatNeedDownload:(NSSet<NSUUID *> *)remoteIdentifiers;
{
    if ( ![remoteIdentifiers isSubsetOfSet:self.remoteIdentifiersInProgress]) {
        [self.remoteIdentifiersThatNeedToBeDownloaded unionSet:remoteIdentifiers];
        [self sortIdentifiers];
    }
}

- (void)sortIdentifiers;
{
    [self.remoteIdentifiersThatNeedToBeDownloaded sortUsingComparator:^NSComparisonResult(NSUUID *uuid1, NSUUID *uuid2) {
        uuid_t u1;
        uuid_t u2;
        [uuid1 getUUIDBytes:u1];
        [uuid2 getUUIDBytes:u2];
        return memcmp(u1, u2, sizeof(u1));
    }];
}

- (BOOL)isDone
{
    return (self.remoteIdentifiersThatNeedToBeDownloaded.count == 0 && self.remoteIdentifiersInProgress.count == 0);
}

- (NSSet *)remoteIdentifiersThatWillBeDownloaded
{
    NSMutableOrderedSet *remoteIDsThatWillBeDownloaded =  [self.remoteIdentifiersThatNeedToBeDownloaded mutableCopy];
    [remoteIDsThatWillBeDownloaded unionSet:self.remoteIdentifiersInProgress];
    return [remoteIDsThatWillBeDownloaded set];
}

@end
