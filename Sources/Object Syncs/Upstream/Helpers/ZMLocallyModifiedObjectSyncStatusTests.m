// 

@import WireDataModel;
@import WireTesting;
@import WireRequestStrategy;


static NSString * Key1;
static NSString * Key2;


@interface ZMLocallyModifiedObjectSyncStatusTests : ZMTBaseTest

@property (nonatomic) ZMTestSession *testSession;
@property (nonatomic) ZMConversation *conversation;
@property (nonatomic) NSSet *trackedKeys;
@property (nonatomic) NSSet *trackedKeysB;

@end


@implementation ZMLocallyModifiedObjectSyncStatusTests

- (void)setUp {
    [super setUp];
    
    self.testSession = [[ZMTestSession alloc] initWithDispatchGroup:self.dispatchGroup];
    [self.testSession prepareForTestNamed:self.name];

    Key1 = ZMConversationSilencedChangedTimeStampKey;
    Key2 = ZMConversationUserDefinedNameKey;
    
    self.trackedKeys = [NSSet setWithObjects:Key1, Key2, nil];
    self.conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.testSession.uiMOC];

    self.trackedKeysB = [NSSet setWithObject:Key1];
}

- (void)tearDown {

    [self.testSession tearDown];
    self.conversation = nil;
    self.trackedKeys = nil;
    self.trackedKeysB = nil;
    
    [super tearDown];
}


- (void)testThatInitOnAnObjectWithNoLocalModificationReturnsNil
{
    // when
    ZMLocallyModifiedObjectSyncStatus *status = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // then
    XCTAssertNil(status);
}


- (void)testThatInitOnAnObjectWithLocalModificationReturnsTheModifiedKeys
{
    // when
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *status = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // then
    XCTAssertNotNil(status);
    XCTAssertEqualObjects(status.keysToSynchronize, self.trackedKeys);
}


- (void)testThatItIsDoneIfAllTrackedKeysNoLongerHaveLocalModifications
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    [self.conversation resetLocallyModifiedKeys:self.trackedKeys];
    
    // then
    XCTAssertTrue(sut.isDone);
}

- (void)testThatItDoesNotReturnKeysToSyncAfterTheyHaveBeenStarted
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];

    // when
    [sut startSynchronizingKeys:[NSSet setWithObject:Key1]];
    
    // then
    NSSet *expectedRemainingKeys = [NSSet setWithObject:Key2];
    XCTAssertEqualObjects(sut.keysToSynchronize, expectedRemainingKeys);
}

- (void)testThatItIsNotDoneWhenAllKeysHaveStartedButNotFinished;
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    [sut startSynchronizingKeys:self.trackedKeys];
    [self.conversation resetLocallyModifiedKeys:self.trackedKeys];
    
    // then
    XCTAssertFalse(sut.isDone);
    XCTAssertEqual(sut.keysToSynchronize.count, 0u);
}

- (void)testThatItIsDoneWhenAllKeysHaveStartedAndFinished;
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    ZMLocallyModifiedObjectSyncStatusToken *token = [sut startSynchronizingKeys:self.trackedKeys];
    [self.conversation resetLocallyModifiedKeys:self.trackedKeys];
    [sut returnChangedKeysAndFinishTokenSync:token];
    
    // then
    XCTAssertTrue(sut.isDone);
}

- (void)testThatItIsNotDoneWhenAllKeysHaveStartedAndOnlyOneFinished;
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    ZMLocallyModifiedObjectSyncStatusToken *token = [sut startSynchronizingKeys:self.trackedKeys];
    [self.conversation resetLocallyModifiedKeys:[NSSet setWithObject:Key1]];
    [sut returnChangedKeysAndFinishTokenSync:token];
    
    // then
    XCTAssertFalse(sut.isDone);
}

- (void)testThatItReAddsKeysToSynchronizeWhenASynchronizationFailed
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    ZMLocallyModifiedObjectSyncStatusToken *token = [sut startSynchronizingKeys:self.trackedKeys];
    [sut returnChangedKeysAndFinishTokenSync:token];
    
    // then
    XCTAssertEqualObjects(sut.keysToSynchronize, self.trackedKeys);
}

- (void)testThatItReturnsKeysThatChangedInTheMeanwhileAfterSynchronization
{
    // given
    self.conversation.userDefinedName = @"xxxxxx";
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    ZMLocallyModifiedObjectSyncStatusToken *token = [sut startSynchronizingKeys:self.trackedKeys];
    self.conversation.userDefinedName = @"Fooooooooo";
    NSSet *changed = [sut returnChangedKeysAndFinishTokenSync:token];
    
    // then
    XCTAssertEqualObjects(changed, [NSSet setWithObject:Key2]);
}

- (void)testThatItReturnsKeysThatChangedInTheMeanwhileAfterSynchronization_nilValue
{
    // given
    self.conversation.userDefinedName = nil;
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    ZMLocallyModifiedObjectSyncStatusToken *token = [sut startSynchronizingKeys:self.trackedKeys];
    self.conversation.userDefinedName = @"Fooooooooo";
    NSSet *changed = [sut returnChangedKeysAndFinishTokenSync:token];
    
    // then
    XCTAssertEqualObjects(changed, [NSSet setWithObject:Key2]);
}


- (void)testThatItDoesNotReturnAnyLocallyModifiedKeysWhenSyncFinishes;
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    ZMLocallyModifiedObjectSyncStatusToken *token = [sut startSynchronizingKeys:self.trackedKeys];
    NSSet *changed = [sut returnChangedKeysAndFinishTokenSync:token];
    
    // then
    XCTAssertEqual(changed.count, 0u);
}

- (void)testThatItResetsTheLocallyModifiedStatusOfKeysInAToken
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    ZMLocallyModifiedObjectSyncStatusToken *token = [sut startSynchronizingKeys:self.trackedKeys];
    [sut resetLocallyModifiedKeysForToken:token];
    
    // then
    XCTAssertEqual(self.conversation.keysThatHaveLocalModifications.count, 0u);
    
}

- (void)testThatItPartiallyResetsTheLocallyModifiedStatusOfKeysInAToken
{
    // given
    [self.conversation setLocallyModifiedKeys:self.trackedKeys];
    ZMLocallyModifiedObjectSyncStatus *sut = [[ZMLocallyModifiedObjectSyncStatus alloc] initWithObject:self.conversation trackedKeys:self.trackedKeys];
    
    // when
    ZMLocallyModifiedObjectSyncStatusToken *token = [sut startSynchronizingKeys:[NSSet setWithObject:Key1]];
    [sut resetLocallyModifiedKeysForToken:token];
    
    // then
    XCTAssertEqualObjects(self.conversation.keysThatHaveLocalModifications, [NSSet setWithObject:Key2]);
    
}

@end
