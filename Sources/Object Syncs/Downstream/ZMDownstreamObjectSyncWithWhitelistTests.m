// 

@import WireDataModel;
@import WireTransport;
@import WireTesting;

#import "MockEntity.h"
#import "MockModelObjectContextFactory.h"
#import "ZMDownstreamObjectSyncWithWhitelist+Internal.h"
#import "ZMChangeTrackerBootstrap+Testing.h"



@interface ZMDownstreamObjectSyncWithWhitelistTests : ZMTBaseTest

@property (nonatomic) NSManagedObjectContext *moc;
@property (nonatomic) id<ZMDownstreamTranscoder> transcoder;
@property (nonatomic) ZMDownstreamObjectSyncWithWhitelist *sut;
@property (nonatomic) ZMDownstreamObjectSyncWithWhitelist *sutWithRealTranscoder;

@property (nonatomic) NSPredicate *predicateForObjectsToDownload;
@property (nonatomic) NSPredicate *predicateForObjectsRequiringWhitelisting;
@end

@implementation ZMDownstreamObjectSyncWithWhitelistTests

- (void)setUp {
    [super setUp];
    
    self.moc = [MockModelObjectContextFactory testContext];
    self.transcoder = [OCMockObject niceMockForProtocol:@protocol(ZMDownstreamTranscoder)];
    
    [self verifyMockLater:self.transcoder];
    
    self.predicateForObjectsToDownload = [NSPredicate predicateWithFormat:@"needsToBeUpdatedFromBackend == YES"];
    self.sut = [[ZMDownstreamObjectSyncWithWhitelist alloc] initWithTranscoder:self.transcoder
                                                                    entityName:@"MockEntity"
                                                 predicateForObjectsToDownload:self.predicateForObjectsToDownload
                                                          managedObjectContext:self.moc];
    
    self.sutWithRealTranscoder = [[ZMDownstreamObjectSyncWithWhitelist alloc] initWithTranscoder:nil entityName:@"MockEntity" predicateForObjectsToDownload:self.predicateForObjectsToDownload managedObjectContext:self.moc];
}

- (void)tearDown {
    self.transcoder = nil;
    self.sut = nil;
    self.sutWithRealTranscoder = nil;
    self.predicateForObjectsToDownload = nil;
    self.predicateForObjectsRequiringWhitelisting = nil;
    [super tearDown];
}

- (void)makeSureFetchObjectsToDownloadHasBeenCalled;
{
    XCTAssertNil([self.sut nextRequest], @"Make sure -fetchObjectsToDownload has been called.");
}

- (void)testThatOnNextRequestsItDoesNotCreateARequestWhenTheObjectIsNotWhiteListed;
{
    // given
    [self makeSureFetchObjectsToDownloadHasBeenCalled];
    MockEntity *entity = [MockEntity insertNewObjectInManagedObjectContext:self.moc];
    entity.needsToBeUpdatedFromBackend = YES;

    [self.sut objectsDidChange:[NSSet setWithObject:entity]];
    
    // expect
    [[(id)self.transcoder reject] requestForFetchingObject:OCMOCK_ANY downstreamSync:OCMOCK_ANY];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNil(request);
    [(id)self.transcoder verify];
}

- (void)testThatOnNextRequestsItDoesCreateARequestWhenTheObjectIsWhiteListed;
{
    // given
    [self makeSureFetchObjectsToDownloadHasBeenCalled];
    MockEntity *entity = [MockEntity insertNewObjectInManagedObjectContext:self.moc];
    entity.needsToBeUpdatedFromBackend = YES;
    [self.sut objectsDidChange:[NSSet setWithObject:entity]];
    
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"dummy"];
    
    // expect
    [[[(id)self.transcoder expect] andReturn:dummyRequest] requestForFetchingObject:entity downstreamSync:self.sut];
    
    // when
    [self.sut whiteListObject:entity];
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqualObjects(dummyRequest, request);
    [(id) self.transcoder verify];
}

- (void)testThatItAddsObjectsMatchingThePredicate
{
    // given
    MockEntity *entity = [MockEntity insertNewObjectInManagedObjectContext:self.moc];
    entity.needsToBeUpdatedFromBackend = YES;

    // when
    [self.sutWithRealTranscoder whiteListObject:entity];
    
    // then
    XCTAssertTrue([self.sutWithRealTranscoder.whitelist containsObject:entity]);
    XCTAssertTrue(self.sutWithRealTranscoder.hasOutstandingItems);
}

- (void)testThatItDoesNotRemoveAnObjectStillMatchingThePredicate
{
    // given
    MockEntity *entity = [MockEntity insertNewObjectInManagedObjectContext:self.moc];
    entity.needsToBeUpdatedFromBackend = YES;
    [self.sutWithRealTranscoder whiteListObject:entity];
    
    XCTAssertTrue([self.sutWithRealTranscoder.whitelist containsObject:entity]);
    XCTAssertTrue(self.sutWithRealTranscoder.innerDownstreamSync.hasOutstandingItems);
    
    // when
    entity.needsToBeUpdatedFromBackend = YES;
    [self.sutWithRealTranscoder objectsDidChange:[NSSet setWithObject:entity]];
    
    // then
    XCTAssertTrue([self.sutWithRealTranscoder.whitelist containsObject:entity]);
    XCTAssertTrue(self.sutWithRealTranscoder.hasOutstandingItems);
}

@end
