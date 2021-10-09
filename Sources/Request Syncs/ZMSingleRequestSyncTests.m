// 


@import WireTransport;
@import WireTesting;

#import "MockModelObjectContextFactory.h"
#import "ZMSingleRequestSync.h"



@interface ZMSingleRequestSyncTests : ZMTBaseTest

@property (nonatomic, readonly) NSManagedObjectContext *moc;
@property (nonatomic, readonly) ZMSingleRequestSync *sut;
@property (nonatomic, readonly) id transcoder;

@end



@implementation ZMSingleRequestSyncTests

- (void)setUp {
    [super setUp];
    
    _moc = [MockModelObjectContextFactory testContext];
    _transcoder = [OCMockObject mockForProtocol:@protocol(ZMSingleRequestTranscoder)];
    [self verifyMockLater:self.transcoder];
    
    _sut = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self.transcoder groupQueue:self.moc];
}

- (void)tearDown {

    _sut = nil;
    _transcoder = nil;
    [super tearDown];
}

- (void)sendRequestAndReplyWithResponse:(ZMTransportResponse *)response
{
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/baa"];
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [self.sut readyForNextRequest];
    [[[self.transcoder stub] andReturn:expectedRequest] requestForSingleRequestSync:self.sut];
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)sendRequestAndReplyWithStatus:(NSInteger)status
{
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:status transportSessionError:nil];
    [self sendRequestAndReplyWithResponse:response];
}

- (void)testThatItStartsInStateIdle
{
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
}

- (void)testThatItExposesTheRightTranscoder
{
    id transcoder = self.sut.transcoder;
    XCTAssertEqual(transcoder, self.transcoder);
}

- (void)testThatItReturnsReadyWhenAskedToRequest
{
    // given
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [[[self.transcoder stub] andReturn:nil] requestForSingleRequestSync:self.sut];
    
    // when
    [self.sut readyForNextRequest];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestReady);
}

- (void)testThatItReturnsInProgressWhenRequestIsCreated
{
    // given
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [[[self.transcoder stub] andReturn:[ZMTransportRequest requestGetFromPath:@"/foo"]] requestForSingleRequestSync:self.sut];

    // when
    [self.sut readyForNextRequest];
    [self.sut nextRequest];

    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
}

- (void)testThatItReturnsReadyWhenAskedToPrepareForNextRequest
{
    // given
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [[[self.transcoder stub] andReturn:nil] requestForSingleRequestSync:self.sut];
    
    // when
    [self.sut readyForNextRequestIfNotBusy];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestReady);
}

- (void)testThatItReturnsNoRequestWhenIdle
{
    // given
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    
    // expect
    [[self.transcoder reject] requestForSingleRequestSync:OCMOCK_ANY];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNil(request);
}


- (void)testThatItAsksRequestToTranscoderWhenStartingRequestAndTheStatusIsInProgress
{
    // given
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/baa"];
    [self.sut readyForNextRequest];
    
    // expect
    [[[self.transcoder expect] andReturn:expectedRequest] requestForSingleRequestSync:self.sut];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqualObjects(expectedRequest, request);
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
}

- (void)testThatItAsksRequestToTranscoderOnlyOnce
{
    // given
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/baa"];
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [self.sut readyForNextRequest];
    
    // expect
    [[[self.transcoder expect] andReturn:expectedRequest] requestForSingleRequestSync:self.sut];
    [[self.transcoder reject] requestForSingleRequestSync:OCMOCK_ANY];
    
    // when
    [self.sut nextRequest];
    [self.sut nextRequest];
}

- (void)testThatItSetsTheStatusToCompletedIfTheTranscoderReturnsANilRequest
{
    // given
    [self.sut readyForNextRequest];
    
    // expect
    [[[self.transcoder expect] andReturn:nil] requestForSingleRequestSync:self.sut];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNil(request);
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
}

- (void)testThatItCallsDidReceiveResponseOnTranscoder
{
    
    // given
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil];
    
    // expect
    [[self.transcoder expect] didReceiveResponse:response forSingleRequest:self.sut];
    
    // when
    [self sendRequestAndReplyWithResponse:response];
}

- (void)testThatItSetsTheStatusToCompletedAndReturnsNoRequestWhenTheRequestCompletesSuccessfully
{
    // expect
    [[self.transcoder expect] didReceiveResponse:OCMOCK_ANY forSingleRequest:self.sut];
    
    // given
    [self sendRequestAndReplyWithStatus:200];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItSetsTheStatusToCompletedAndReturnsNoRequestWhenTheRequestCompletesFailsOnPermantentError
{
    // expect
    [[self.transcoder expect] didReceiveResponse:OCMOCK_ANY forSingleRequest:self.sut];
    
    // given
    [self sendRequestAndReplyWithStatus:404];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItLeavesTheStatusToReadyAndFiresAnotherRequestWhenTheRequestFailsOnNetwork
{
    // given
    [self sendRequestAndReplyWithStatus:500];
    
    // expect
    [[self.transcoder reject] didReceiveResponse:OCMOCK_ANY forSingleRequest:OCMOCK_ANY];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestReady);
    ZMTransportRequest *secondRequest = [self.sut nextRequest];
    XCTAssertNotNil(secondRequest);
}

- (void)testThatItLeavesTheStatusToReadyAndFiresAnotherRequestWhenTheRequestFailsWith_TryAgainLater
{
    // given
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    ZMTransportResponse *response = [ZMTransportResponse responseWithTransportSessionError:error];
    [self sendRequestAndReplyWithResponse:response];
    
    // expect
    [[self.transcoder reject] didReceiveResponse:OCMOCK_ANY forSingleRequest:OCMOCK_ANY];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestReady);
    ZMTransportRequest *secondRequest = [self.sut nextRequest];
    XCTAssertNotNil(secondRequest);
}

- (void)testThatTheStatusIsIdleAfterCallingResetCompletionStateWhenItWasCompleted
{
    
    // expect
    [[self.transcoder stub] didReceiveResponse:OCMOCK_ANY forSingleRequest:self.sut];
    
    // given
    [self sendRequestAndReplyWithStatus:200];
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);

    
    // when
    [self.sut resetCompletionState];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
}

- (void)testThatItReturnsReadyWhenAskedToPrepareForNextRequest_WhenItWasCompleted
{
    // expect
    [[self.transcoder stub] didReceiveResponse:OCMOCK_ANY forSingleRequest:self.sut];
    
    // given
    [self sendRequestAndReplyWithStatus:200];
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
    
    // when
    [self.sut readyForNextRequestIfNotBusy];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestReady);
}


- (void)testThatResetCompletionStateDoesNotDoAnythingIfTheRequestIsReady
{
    // given
    [self.sut readyForNextRequest];
    XCTAssertEqual(self.sut.status, ZMSingleRequestReady);
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetCompletionState];
    }];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestReady);
}

- (void)testThatItCreatesAnotherRequestWhenNeedDonwloadIsCalledWhileInProgress
{
    // given
    ZMTransportRequest *request1 = [ZMTransportRequest requestGetFromPath:@"one"];
    ZMTransportRequest *request2 = [ZMTransportRequest requestGetFromPath:@"one"];
    [self.sut readyForNextRequest];
    
    // expect
    [[[self.transcoder expect] andReturn:request1] requestForSingleRequestSync:self.sut];
    [[[self.transcoder expect] andReturn:request2] requestForSingleRequestSync:self.sut];
    
    // when
    ZMTransportRequest *generatedRequest1 = [self.sut nextRequest];
    [self.sut readyForNextRequest];
    ZMTransportRequest *generatedRequest2 = [self.sut nextRequest];
    
    // then
    XCTAssertEqualObjects(request1, generatedRequest1);
    XCTAssertEqualObjects(request2, generatedRequest2);

}

- (void)testThatIfReadyForNextRequestIsCalledWhileDownloadingANewRequestIsGeneratedAndTheFirstIsIgnored
{
    // given
    ZMTransportRequest *requestThatShouldNotComplete = [ZMTransportRequest requestGetFromPath:@"req-nope"];
    ZMTransportRequest *requestThatShouldComplete = [ZMTransportRequest requestGetFromPath:@"req-yep"];
    
    ZMTransportResponse *responseThatShouldNotProcess = [ZMTransportResponse responseWithPayload:@[@"resp-nope"] HTTPStatus:200 transportSessionError:nil];
    ZMTransportResponse *responseThatShouldProcess = [ZMTransportResponse responseWithPayload:@[@"resp-yep"] HTTPStatus:200 transportSessionError:nil];
    
    [[[self.transcoder expect] andReturn:requestThatShouldNotComplete] requestForSingleRequestSync:self.sut];
    [[[self.transcoder expect] andReturn:requestThatShouldComplete] requestForSingleRequestSync:self.sut];
    
    
    // expect
    [[self.transcoder reject] didReceiveResponse:responseThatShouldNotProcess forSingleRequest:self.sut];
    [[self.transcoder expect] didReceiveResponse:responseThatShouldProcess forSingleRequest:self.sut];
    
    // given - first download
    [self.sut readyForNextRequest];
    ZMTransportRequest *request1 = [self.sut nextRequest];
    XCTAssertEqualObjects(request1, requestThatShouldNotComplete);
    
    // given - second download
    [self.sut readyForNextRequest];
    ZMTransportRequest *request2 = [self.sut nextRequest];
    XCTAssertEqualObjects(request2, requestThatShouldComplete);
    
    // when
    [request1 completeWithResponse:responseThatShouldNotProcess];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
    
    // when
    [request2 completeWithResponse:responseThatShouldProcess];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
}

@end
