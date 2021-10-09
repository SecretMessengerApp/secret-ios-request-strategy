//
//

@import WireSystem;
@import WireTransport;
@import WireDataModel;

#import "ZMSimpleListRequestPaginator+Internal.h"
#import <WireRequestStrategy/WireRequestStrategy-Swift.h>
#import "ZMSingleRequestSync.h"

@interface ZMSimpleListRequestPaginator () <ZMSingleRequestTranscoder>

@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, copy) NSString *startKey;
@property (nonatomic) NSUInteger pageSize;
@property (nonatomic) NSManagedObjectContext *moc;
@property (nonatomic) ZMSingleRequestSync *singleRequestSync;
@property (nonatomic) BOOL hasMoreToFetch;
@property (nonatomic) NSUUID *lastUUIDOfPreviousPage;
@property (nonatomic) NSDate *lastResetFetchDate;

@property (nonatomic) BOOL includeClientID;

@property (nonatomic, weak) id<ZMSimpleListRequestPaginatorSync> transcoder;

@property (nonatomic) BOOL inProgress;
@end


@implementation ZMSimpleListRequestPaginator

ZM_EMPTY_ASSERTING_INIT()

- (instancetype)initWithBasePath:(NSString *)basePath
                        startKey:(NSString *)startKey
                        pageSize:(NSUInteger)pageSize
            managedObjectContext:(NSManagedObjectContext *)moc
                 includeClientID:(BOOL)includeClientID
                      transcoder:(id<ZMSimpleListRequestPaginatorSync>)transcoder;
{
    Require(startKey != nil);
    Require(basePath != nil);

    self = [super init];
    if(self) {
        self.basePath = basePath;
        self.startKey = startKey;
        self.pageSize = pageSize;
        self.moc = moc;
        self.includeClientID = includeClientID;
        self.transcoder = transcoder;
        self.singleRequestSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self groupQueue:self.moc];
    }
    return self;
}

- (ZMTransportRequest *)nextRequest
{
    if(!self.hasMoreToFetch) {
        return nil;
    }
    return self.singleRequestSync.nextRequest;
}

- (ZMSingleRequestProgress)status
{
    return self.singleRequestSync.status;
}

- (ZMTransportRequest *)requestForSingleRequestSync:(ZMSingleRequestSync * __unused)sync
{
    if(!self.hasMoreToFetch) {
        return nil;
    }
    self.inProgress = YES;
    NSMutableArray *queryItems = [NSMutableArray array];
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"size" value:[@(self.pageSize) stringValue]]];
    
    if (self.lastUUIDOfPreviousPage != nil) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:self.startKey value:self.lastUUIDOfPreviousPage.transportString]];
    }
    if (self.includeClientID) {
        UserClient *selfClient = [ZMUser selfUserInContext:self.moc].selfClient;
        if (selfClient.remoteIdentifier != nil) {
            [queryItems addObject:[NSURLQueryItem queryItemWithName:@"client" value:selfClient.remoteIdentifier]];
        }
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:self.basePath];
    components.queryItems = queryItems;
    
    ZMTransportRequest *request = [ZMTransportRequest requestGetFromPath:components.string];
    return request;
}

- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync * __unused)sync
{
    if(response.result == ZMTransportResponseStatusSuccess) {
        [self updateStateWithResponse:response];
    }
    else if(response.result == ZMTransportResponseStatusPermanentError) {
        id strongTranscoder = self.transcoder;
        if ([strongTranscoder respondsToSelector:@selector(shouldParseErrorForResponse:)]) {
            if ([strongTranscoder shouldParseErrorForResponse:response]) {
                [self updateStateWithResponse:response];
                return;
            }
        }
        self.hasMoreToFetch = NO;
        self.inProgress = NO;
    }
    [self.singleRequestSync readyForNextRequest];
}

- (void)updateStateWithResponse:(ZMTransportResponse *)response
{
    if (response == nil) {
        self.hasMoreToFetch = NO;
        self.inProgress = NO;
        return;
    }
    id strongTranscoder = self.transcoder;
    if ([strongTranscoder respondsToSelector:@selector(nextUUIDFromResponse:forListPaginator:)]) {
        self.hasMoreToFetch = [[[response.payload asDictionary] optionalNumberForKey:@"has_more"] boolValue];
        self.lastUUIDOfPreviousPage = [strongTranscoder nextUUIDFromResponse:response forListPaginator:self];
        if (!self.hasMoreToFetch) {
            self.inProgress = NO;
        }
    }
    else {
        self.inProgress = NO;
        self.hasMoreToFetch = NO;
    }
}

- (void)resetFetching
{
    self.hasMoreToFetch = YES;
    self.lastResetFetchDate = [NSDate date];
    self.lastUUIDOfPreviousPage = nil;
    id strongTranscoder = self.transcoder;
    if ([strongTranscoder respondsToSelector:@selector(startUUID)]) {
        self.lastUUIDOfPreviousPage = [strongTranscoder startUUID];
    }
    [self.singleRequestSync readyForNextRequest];
}

@end

