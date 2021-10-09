// 


@import WireTransport;
@import WireTesting;
@import WireRequestStrategy;

#import "MockModelObjectContextFactory.h"
#import <objc/runtime.h>


@interface ZMRemoteIdentifierObjectTranscoderTests : ZMTBaseTest

@property (nonatomic) NSManagedObjectContext *moc;
@property (nonatomic) ZMRemoteIdentifierObjectSync *sut;
@property (nonatomic) id transcoder;

@end


@implementation ZMRemoteIdentifierObjectTranscoderTests

- (void)setUp
{
    [super setUp];
    
    self.moc = [MockModelObjectContextFactory testContext];
    self.transcoder = [OCMockObject mockForProtocol:@protocol(ZMRemoteIdentifierObjectTranscoder)];
    [self verifyMockLater:self.transcoder];
    self.sut = [[ZMRemoteIdentifierObjectSync alloc] initWithTranscoder:self.transcoder managedObjectContext:self.moc];
}

- (void)tearDown
{
    self.sut = nil;
    self.transcoder = nil;
    
    [super tearDown];
}

- (void)testThatItStartsOutAsDone;
{
    XCTAssertTrue(self.sut.isDone);
}


- (void)testThatReturnsNotDoneWhenYouAddRemoteIDsThatNeedToBeDownloaded;
{
    // given
    NSSet *remoteIDs = [NSSet setWithArray:@[NSUUID.createUUID, NSUUID.createUUID]];
    
    // when
    [self.sut setRemoteIdentifiersAsNeedingDownload:remoteIDs];
    
    // then
    XCTAssertFalse(self.sut.isDone);
}

- (void)testThatItAskForARequestWhenItHasRemoteIdentifiers;
{
    // given
    NSSet *remoteIDs = [NSSet setWithArray:@[NSUUID.createUUID, NSUUID.createUUID]];
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];
    
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 10)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    [[[self.transcoder expect] andReturn:dummyRequest] requestForObjectSync:self.sut remoteIdentifiers:remoteIDs];
    
    // when
    [self.sut setRemoteIdentifiersAsNeedingDownload:remoteIDs];
    (void) [self.sut nextRequest];
    
    // finally
    [self.transcoder verify];
}

- (void)testThatItDoesNotAskForARequestWhenItHasNoRemoteIdentifiers;
{
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE(10)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    [[self.transcoder reject] requestForObjectSync:self.sut remoteIdentifiers:OCMOCK_ANY];
    
    // when
    (void) [self.sut nextRequest];
    
    // finally
    [self.transcoder verify];
}

- (void)testThatItDoesNotAskForTheSameRemoteIdentifiersMultipleTimes;
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID];
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];

    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 2)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    
    __block NSMutableSet *requestedIDs = [NSMutableSet set];
    __block NSUInteger numRequests = 0;
    
    [[[self.transcoder stub] andReturn:dummyRequest] requestForObjectSync:self.sut remoteIdentifiers: [OCMArg checkWithBlock:^BOOL(NSSet* set) {
        [requestedIDs unionSet:set];
        XCTAssertTrue(set.count <= 2);
        ++numRequests;
        return YES;
    } ]];
    
    [[[self.transcoder reject] andReturn:dummyRequest] requestForObjectSync:self.sut remoteIdentifiers:OCMOCK_ANY];
    
    // when
    [self.sut setRemoteIdentifiersAsNeedingDownload:[NSSet setWithArray:remoteIDs]];
    (void) [self.sut nextRequest];
    (void) [self.sut nextRequest];
    (void) [self.sut nextRequest];
    (void) [self.sut nextRequest];

    // then
    XCTAssertEqual(numRequests, 2u);
    XCTAssertEqualObjects(requestedIDs, [NSSet setWithArray:remoteIDs]);
    
    // finally
    [self.transcoder verify];
}

typedef ZMTransportRequest * (^stubbedRequestForObjectSync_t)(id self, ZMRemoteIdentifierObjectSync *sync, NSSet *identifiers);

- (void)testThatItAsksForTheSameRemoteIdentifiersAgainWhenReceivingA_TryAgainLater_Response
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID];
    NSSet *firstSet = [NSSet setWithObjects:remoteIDs[0], remoteIDs[1], nil];
    NSSet *secondSet = [NSSet setWithObject:remoteIDs[2]];
    
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    ZMTransportResponse *tryAgainResponse = [ZMTransportResponse responseWithTransportSessionError:error];
    NSUInteger const identifiersPerRequest = 2;
    
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE(identifiersPerRequest)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    
    NSMutableArray *requestedIDs = [NSMutableArray array];
    __block NSUInteger numRequests = 0;
    
    // This hack add the given block and forwards all method calls to that block:
    {
        stubbedRequestForObjectSync_t requestForObjectSync = ^(id obj, ZMRemoteIdentifierObjectSync *sync, NSSet *identifiers){
            NOT_USED(obj);
            NOT_USED(sync);
            [requestedIDs addObject:identifiers];
            XCTAssertTrue(identifiers.count <= 2);
            ++numRequests;
            ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];
            return dummyRequest;
        };
        IMP imp = imp_implementationWithBlock(requestForObjectSync);
        SEL sel = NSSelectorFromString([self.name stringByAppendingString:@"_requestForObjectSync:remoteIdentifiers:"]);
        XCTAssert(class_addMethod(self.class, sel, imp, "@@"));
        [[[self.transcoder stub] andCall:sel onObject:self] requestForObjectSync:OCMOCK_ANY remoteIdentifiers:OCMOCK_ANY];
    }
    [[self.transcoder stub] didReceiveResponse:OCMOCK_ANY remoteIdentifierObjectSync:OCMOCK_ANY forRemoteIdentifiers:OCMOCK_ANY];
    
    // when
    [self.sut setRemoteIdentifiersAsNeedingDownload:[NSSet setWithArray:remoteIDs]];
    // Request all IDs:
    ZMTransportRequest *firstRequest = [self.sut nextRequest];
    XCTAssertNotNil(firstRequest);
    ZMTransportRequest *secondRequest = [self.sut nextRequest];
    XCTAssertNotNil(secondRequest);
    XCTAssertNil([self.sut nextRequest]);
    
    
    
    // Remove requested IDs and fail:
    WaitForAllGroupsToBeEmpty(0.5);
    [requestedIDs removeAllObjects];
    [firstRequest completeWithResponse:tryAgainResponse];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil([self.sut nextRequest]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(requestedIDs.count, 1u);
    XCTAssertEqualObjects(requestedIDs.firstObject, firstSet);
    
    // and when (2)
    [secondRequest completeWithResponse:tryAgainResponse];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil([self.sut nextRequest]);
    
    // then
    XCTAssertEqual(requestedIDs.count, 2u);
    XCTAssertEqualObjects(requestedIDs.lastObject, secondSet);
    
    // finally
    [self.transcoder verify];
}

- (void)testThatItDoesNotForwardTheResponseToTheTranscoderWhenReceivingA_TryAgainLater_Response
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID];
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    ZMTransportResponse *tryAgainResponse = [ZMTransportResponse responseWithTransportSessionError:error];
    
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 2)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    
    [[[self.transcoder stub] andReturn:dummyRequest] requestForObjectSync:self.sut remoteIdentifiers:OCMOCK_ANY];
    [[self.transcoder reject] didReceiveResponse:OCMOCK_ANY remoteIdentifierObjectSync:OCMOCK_ANY forRemoteIdentifiers:OCMOCK_ANY];
    
    // when
    [self.sut setRemoteIdentifiersAsNeedingDownload:[NSSet setWithArray:remoteIDs]];
    // Request all IDs:
    ZMTransportRequest *request = [self.sut nextRequest];
    [request completeWithResponse:tryAgainResponse];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // finally
    [self.transcoder verify];
}

- (void)testThatItIsNotDoneWhenItHasRequestedAllRemoteIdentifiers;
{
    // given
    NSSet *remoteIDs = [NSSet setWithArray:@[NSUUID.createUUID, NSUUID.createUUID]];
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];
    
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 10)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    [[[self.transcoder expect]  andReturn:dummyRequest] requestForObjectSync:self.sut remoteIdentifiers:remoteIDs];
    
    // when
    [self.sut setRemoteIdentifiersAsNeedingDownload:remoteIDs];
    (void) [self.sut nextRequest];
    
    // then
    XCTAssertFalse(self.sut.isDone);

    // finally
    [self.transcoder verify];
}

- (void)testThatItIsDoneWhenItAllRequestedAreCompleted
{
    // given
    NSSet *remoteIDs = [NSSet setWithArray:@[NSUUID.createUUID, NSUUID.createUUID]];
    ZMTransportRequest *request = [ZMTransportRequest requestGetFromPath:@"asdf"];
    
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 10)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    [[[self.transcoder expect] andReturn:request] requestForObjectSync:self.sut remoteIdentifiers:remoteIDs];
    NSDictionary *payload = @{@"a": @"b"};
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:payload HTTPStatus:200 transportSessionError:nil headers:nil];
    [[self.transcoder stub] didReceiveResponse:OCMOCK_ANY remoteIdentifierObjectSync:OCMOCK_ANY forRemoteIdentifiers:OCMOCK_ANY];
    
    [self.sut setRemoteIdentifiersAsNeedingDownload:remoteIDs];
    ZMTransportRequest *transportRequest = [self.sut nextRequest];
    
    // when
    [transportRequest completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.sut.isDone);
    
    // finally
    [self.transcoder verify];
}

- (void)testThatItIsPassesTheTransportResponseToTheTranscoder;
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID];
    ZMTransportRequest *request1 = [ZMTransportRequest requestGetFromPath:@"foo1"];
    ZMTransportRequest *request2 = [ZMTransportRequest requestGetFromPath:@"foo2"];
    
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 2)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];

    __block NSMutableSet *requestedIDs = [NSMutableSet set];
    __block NSSet *requestedIDsRequest1;
    __block NSSet *requestedIDsRequest2;
    
    [[[self.transcoder expect] andReturn:request1] requestForObjectSync:self.sut remoteIdentifiers: [OCMArg checkWithBlock:^BOOL(NSSet* set) {
        [requestedIDs unionSet:set];
        requestedIDsRequest1 = set;
        XCTAssertTrue(set.count <= 2);
        return YES;
    } ]];
    
    [[[self.transcoder expect] andReturn:request2] requestForObjectSync:self.sut remoteIdentifiers: [OCMArg checkWithBlock:^BOOL(NSSet* set) {
        [requestedIDs unionSet:set];
        requestedIDsRequest2 = set;
        XCTAssertTrue(set.count <= 2);
        return YES;
    } ]];

    
    NSDictionary *payload1 = @{@"a": @"b"};
    ZMTransportResponse *response1 = [[ZMTransportResponse alloc] initWithPayload:payload1 HTTPStatus:200 transportSessionError:nil headers:nil];
    [[self.transcoder expect] didReceiveResponse:response1 remoteIdentifierObjectSync:self.sut forRemoteIdentifiers:[OCMArg checkWithBlock:^BOOL(NSSet *set) {
        return [set isEqualToSet:requestedIDsRequest1];
    }]];
    
    NSDictionary *payload2 = @{@"a": @"c"};
    ZMTransportResponse *response2 = [[ZMTransportResponse alloc] initWithPayload:payload2 HTTPStatus:200 transportSessionError:nil headers:nil];
    [[self.transcoder expect] didReceiveResponse:response2 remoteIdentifierObjectSync:self.sut forRemoteIdentifiers:[OCMArg checkWithBlock:^BOOL(NSSet *set) {
        return [set isEqualToSet:requestedIDsRequest2];
    }]];
    
    [[self.transcoder reject] didReceiveResponse:OCMOCK_ANY remoteIdentifierObjectSync:OCMOCK_ANY forRemoteIdentifiers:OCMOCK_ANY];

    [self.sut setRemoteIdentifiersAsNeedingDownload:[NSSet setWithArray:remoteIDs]];
    
    // when
    ZMTransportRequest *transportRequest1 = [self.sut nextRequest];
    [transportRequest1 completeWithResponse:response1];
    WaitForAllGroupsToBeEmpty(0.5);

    ZMTransportRequest *transportRequest2 = [self.sut nextRequest];
    [transportRequest2 completeWithResponse:response2];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMTransportRequest *transportRequest3 = [self.sut nextRequest];
    
    // then
    XCTAssertNil(transportRequest3);
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(self.sut.isDone);
    
    XCTAssertEqualObjects(requestedIDs, [NSSet setWithArray:remoteIDs]);
    
    // finally
    [self.transcoder verify];
}


- (void)testThatItRequestsFromAUserWhenAddingAUserRemoteID;
{
    // given
    NSUUID *userID = [NSUUID createUUID];
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];
    
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 10)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    [[[self.transcoder expect] andReturn:dummyRequest] requestForObjectSync:self.sut remoteIdentifiers:[NSSet setWithObject:userID]];
    
    // when
    [self.sut addRemoteIdentifiersThatNeedDownload:[NSSet setWithObject:userID]];
    (void) [self.sut nextRequest];
    
    // finally
    [self.transcoder verify];
}

- (void)testThatItDoesNotReturnARequestForTheSameIdentifierAsLongAsTheFirstRequestIsNotCompleted;
{
    // given
    NSUUID *userID = [NSUUID createUUID];
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];
    
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 10)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    [[[self.transcoder expect] andReturn:dummyRequest] requestForObjectSync:self.sut remoteIdentifiers:[NSSet setWithObject:userID]];
    
    // when
    [self.sut addRemoteIdentifiersThatNeedDownload:[NSSet setWithObject:userID]];
    
    XCTAssertNotNil([self.sut nextRequest]);
    XCTAssertNil([self.sut nextRequest]);
    
    // finally
    [self.transcoder verify];
}

- (void)testThatWeOnlyGetOneRequestWhenWeAddTheSameRemoteIDTwice;
{
    // given
    NSUUID *userID = [NSUUID createUUID];
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];
    
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE((NSUInteger) 10)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    [[[self.transcoder expect] andReturn:dummyRequest] requestForObjectSync:self.sut remoteIdentifiers:[NSSet setWithObject:userID]];
    [[self.transcoder stub] didReceiveResponse:OCMOCK_ANY remoteIdentifierObjectSync:OCMOCK_ANY forRemoteIdentifiers:OCMOCK_ANY];
    
    // when
    [self.sut addRemoteIdentifiersThatNeedDownload:[NSSet setWithObject:userID]];
    [self.sut addRemoteIdentifiersThatNeedDownload:[NSSet setWithObject:userID]];

    // then
    ZMTransportRequest *request1 = [self.sut nextRequest];
    [request1 completeWithResponse:[ZMTransportResponse responseWithPayload:@[] HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNil([self.sut nextRequest]);
    
    // finally
    [self.transcoder verify];
}

- (void)testThatWhenAddingAUserThenItIsInTheListOfRemoteIdentifiersThatWillBeDownloaded
{
    // given
    NSUUID *userID1 = [NSUUID createUUID];
    NSUUID *userID2 = [NSUUID createUUID];
    
    // when
    [self.sut addRemoteIdentifiersThatNeedDownload:[NSSet setWithObject:userID2]];
    [self.sut addRemoteIdentifiersThatNeedDownload:[NSSet setWithObject:userID1]];

    
    // then
    NSSet *expected = [NSSet setWithObjects:userID1, userID2, nil];
    XCTAssertEqualObjects(self.sut.remoteIdentifiersThatWillBeDownloaded, expected);
}

- (void)testThatWhenSettingASetOfUserThenTheyAreInTheListOfRemoteIdentifiersThatWillBeDownloaded
{
    // given
    NSUUID *userID1 = [NSUUID createUUID];
    NSUUID *userID2 = [NSUUID createUUID];
    
    // when
    [self.sut setRemoteIdentifiersAsNeedingDownload:[NSSet setWithObjects:userID1, userID2, nil]];
    
    
    // then
    NSSet *expected = [NSSet setWithObjects:userID1, userID2, nil];
    XCTAssertEqualObjects(self.sut.remoteIdentifiersThatWillBeDownloaded, expected);
}

- (void)testThatItLimitsTheNumberOfUUIDsPerRequest;
{
    // given
    NSMutableSet *allIdentifiers = [NSMutableSet set];
    NSUInteger const maxCount = 47;
    NSUInteger const count = maxCount * 2 + 10;
    for (NSUInteger i = 0; i < count; ++i) {
        [allIdentifiers addObject:NSUUID.createUUID];
    }
    [self.sut setRemoteIdentifiersAsNeedingDownload:allIdentifiers];
    ZMTransportRequest *request = [OCMockObject niceMockForClass:ZMTransportRequest.class];
    
    // expect
    [[[self.transcoder stub] andReturnValue:OCMOCK_VALUE(maxCount)] maximumRemoteIdentifiersPerRequestForObjectSync:OCMOCK_ANY];
    [[[self.transcoder expect] andReturn:request] requestForObjectSync:self.sut remoteIdentifiers:[OCMArg checkWithBlock:^BOOL(NSSet *set) {
        return (set.count == maxCount);
    }]];
    
    // when
    (void) [self.sut nextRequest];
}

@end
