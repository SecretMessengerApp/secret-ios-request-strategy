// 


@import WireImages;
@import WireDataModel;
@import WireTesting;

#import <WireRequestStrategy/ZMImagePreprocessingTracker+Testing.h>


@interface ZMImagePreprocessingTrackerTests : ZMTBaseTest

@property (nonatomic) id preprocessor;
@property (nonatomic) ZMTestSession *testSession;
@property (nonatomic) NSOperationQueue *imagePreprocessingQueue;
@property (nonatomic) ZMImagePreprocessingTracker *sut;
@property (nonatomic) NSPredicate *fetchPredicate;
@property (nonatomic) NSPredicate *needsProcessingPredicate;

@property (nonatomic)  ZMClientMessage *linkPreviewMessage1;
@property (nonatomic)  ZMClientMessage *linkPreviewMessage2;
@property (nonatomic)  ZMClientMessage *linkPreviewMessage3;
@property (nonatomic)  ZMClientMessage *linkPreviewMessageExcludedByPredicate;

@end



@implementation ZMImagePreprocessingTrackerTests

- (void)setUp {
    [super setUp];
    
    self.testSession = [[ZMTestSession alloc] initWithDispatchGroup:self.dispatchGroup];
    [self.testSession prepareForTestNamed:self.name];
    
    
    self.linkPreviewMessage1 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.testSession.uiMOC];
    self.linkPreviewMessage2 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.testSession.uiMOC];
    self.linkPreviewMessage3 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.testSession.uiMOC];
    self.linkPreviewMessageExcludedByPredicate = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.testSession.uiMOC];
    self.linkPreviewMessageExcludedByPredicate.nonce = nil;
    
    self.fetchPredicate = [NSPredicate predicateWithValue:NO];
    self.needsProcessingPredicate = [NSPredicate predicateWithFormat:@"nonce_data != nil"];
    self.preprocessor = [OCMockObject niceMockForClass:[ZMAssetsPreprocessor class]];
    self.imagePreprocessingQueue = [[NSOperationQueue alloc] init];
    self.sut = [[ZMImagePreprocessingTracker alloc] initWithManagedObjectContext:self.testSession.uiMOC
                                                            imageProcessingQueue:self.imagePreprocessingQueue
                                                                  fetchPredicate:self.fetchPredicate
                                                        needsProcessingPredicate:self.needsProcessingPredicate
                                                                     entityClass:[ZMClientMessage class] preprocessor:self.preprocessor];
    
    [[[self.preprocessor stub] andReturn:@[[[NSOperation alloc] init]]] operationsForPreprocessingImageOwner:self.linkPreviewMessage1];
    [[[self.preprocessor stub] andReturn:@[[[NSOperation alloc] init]]] operationsForPreprocessingImageOwner:self.linkPreviewMessage2];
    [[[self.preprocessor stub] andReturn:@[[[NSOperation alloc] init]]] operationsForPreprocessingImageOwner:self.linkPreviewMessage3];
}

- (void)tearDown
{
    self.imagePreprocessingQueue.suspended = NO;
    WaitForAllGroupsToBeEmpty(0.5);
    self.linkPreviewMessage1 = nil;
    self.linkPreviewMessage2 = nil;
    self.linkPreviewMessage3 = nil;
    self.preprocessor = nil;
    self.imagePreprocessingQueue = nil;
    [self.sut tearDown];
    self.sut = nil;
    [self.testSession tearDown];
    self.testSession = nil;
    [super tearDown];
}

- (void)testThatItReturnsTheCorrectFetchRequest
{
    // when
    NSFetchRequest *request = [self.sut fetchRequestForTrackedObjects];
    
    // then
    NSFetchRequest *expectedRequest = [ZMClientMessage sortedFetchRequestWithPredicate:self.fetchPredicate];
    XCTAssertEqualObjects(request, expectedRequest);
}


- (void)testThatItAddsTrackedObjects
{
    // given
    NSSet *objects = [NSSet setWithArray:@[self.linkPreviewMessage1, self.linkPreviewMessage2]];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut addTrackedObjects:objects];
    
    // then
    XCTAssertTrue([self.sut.imageOwnersBeingPreprocessed containsObject:self.linkPreviewMessage1]);
    XCTAssertTrue([self.sut.imageOwnersBeingPreprocessed containsObject:self.linkPreviewMessage2]);
    self.imagePreprocessingQueue.suspended = NO;
}

- (void)testThatItDoesNotAddTrackedObjectsThatDoNotMatchPredicateForNeedToPreprocess
{
    // given
    NSSet *objects = [NSSet setWithObject:self.linkPreviewMessageExcludedByPredicate];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut addTrackedObjects:objects];
    
    // then
    XCTAssertFalse(self.sut.hasOutstandingItems);
    XCTAssertEqual(self.sut.imageOwnersThatNeedPreprocessing.count, 0u);
}

@end



@implementation ZMImagePreprocessingTrackerTests (OutstandingItems)

- (void)testThatItHasNoOutstandingItems;
{
    XCTAssertFalse(self.sut.hasOutstandingItems, @"%u / %u",
                   (unsigned) self.sut.imageOwnersThatNeedPreprocessing, (unsigned) self.sut.imageOwnersBeingPreprocessed);
}

- (void)testThatItHasOutstandingItemsWhenItemsAreAdded
{
    // given
    [self.testSession.uiMOC.zm_fileAssetCache storeAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"1" length:1]];
    [self.testSession.uiMOC.zm_fileAssetCache storeAssetData:self.linkPreviewMessage2 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"2" length:1]];
    NSSet *objects = [NSSet setWithArray:@[self.linkPreviewMessage1, self.linkPreviewMessage2]];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut objectsDidChange:objects];

    // then
    XCTAssertTrue(self.sut.hasOutstandingItems, @"%u / %u",
                  (unsigned) self.sut.imageOwnersThatNeedPreprocessing.count, (unsigned) self.sut.imageOwnersBeingPreprocessed.count);
    self.imagePreprocessingQueue.suspended = NO;
}

- (void)testThatItHasOutstandingItemsWhenItemsAreAddedAndOneIsRemoved
{
    // given
    [self.testSession.uiMOC.zm_fileAssetCache storeAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"1" length:1]];
    [self.testSession.uiMOC.zm_fileAssetCache storeAssetData:self.linkPreviewMessage2 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"2" length:1]];
    NSSet *objects = [NSSet setWithArray:@[self.linkPreviewMessage1, self.linkPreviewMessage2]];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut objectsDidChange:objects];
    [self.testSession.uiMOC.zm_fileAssetCache deleteAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO];
    [self.sut objectsDidChange:objects];
    
    // then
    XCTAssertTrue(self.sut.hasOutstandingItems, @"%u / %u",
                  (unsigned) self.sut.imageOwnersThatNeedPreprocessing.count, (unsigned) self.sut.imageOwnersBeingPreprocessed.count);
    self.imagePreprocessingQueue.suspended = NO;
}

- (void)testThatItHasNoOutstandingItemsWhenItemsAreAddedAndThenRemoved;
{
    // given
    [self.testSession.uiMOC.zm_fileAssetCache storeAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"1" length:1]];
    [self.testSession.uiMOC.zm_fileAssetCache storeAssetData:self.linkPreviewMessage2 format:ZMImageFormatOriginal encrypted:NO data:[NSData dataWithBytes:"2" length:1]];
    NSSet *objects = [NSSet setWithArray:@[self.linkPreviewMessage1, self.linkPreviewMessage2]];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut objectsDidChange:objects];
    self.imagePreprocessingQueue.suspended = NO;
    [self.imagePreprocessingQueue waitUntilAllOperationsAreFinished];
    [self.testSession.uiMOC.zm_fileAssetCache deleteAssetData:self.linkPreviewMessage1 format:ZMImageFormatOriginal encrypted:NO];
    [self.testSession.uiMOC.zm_fileAssetCache deleteAssetData:self.linkPreviewMessage2 format:ZMImageFormatOriginal encrypted:NO];
    [self.sut objectsDidChange:objects];
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout:0.3]);
    
    // then
    XCTAssertFalse(self.sut.hasOutstandingItems, @"%u / %u",
                   (unsigned) self.sut.imageOwnersThatNeedPreprocessing, (unsigned) self.sut.imageOwnersBeingPreprocessed);
}

- (void)testThatItHasNoOutstandingItemsWhenItemsNotMatchingThePredicateChange
{
    // given
    NSSet *objects = [NSSet setWithObject:self.linkPreviewMessageExcludedByPredicate];
    
    // when
    self.imagePreprocessingQueue.suspended = YES;
    [self.sut objectsDidChange:objects];
    
    // then
    XCTAssertFalse(self.sut.hasOutstandingItems);
    XCTAssertEqual(self.sut.imageOwnersThatNeedPreprocessing.count, 0u);
}

@end
