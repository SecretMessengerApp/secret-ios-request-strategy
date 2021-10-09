// 


@import WireTransport;
@import WireTesting;
@import WireRequestStrategy;



@interface FakeRequestGenerator : NSObject <ZMRequestGenerator>

@property (nonatomic) ZMTransportRequest *nextRequest;

@end



@implementation FakeRequestGenerator
@end



@interface ZMRequestGeneratorTests : ZMTBaseTest

@property (nonatomic) ZMTransportRequest *requestA;
@property (nonatomic) ZMTransportRequest *requestB;
@property (nonatomic) FakeRequestGenerator *generatorA;
@property (nonatomic) FakeRequestGenerator *generatorB;

@end



@implementation ZMRequestGeneratorTests

- (void)setUp
{
    [super setUp];
    self.requestA = [ZMTransportRequest requestGetFromPath:@"/foo/A"];
    self.requestB = [ZMTransportRequest requestGetFromPath:@"/bar/B"];
    self.generatorA = [[FakeRequestGenerator alloc] init];
    self.generatorB = [[FakeRequestGenerator alloc] init];
}

- (void)tearDown
{
    self.requestA = nil;
    self.requestB = nil;
    self.generatorA = nil;
    self.generatorB = nil;
    [super tearDown];
}

- (void)testThatItReturnsARequest;
{
    // given
    self.generatorA.nextRequest = self.requestA;
    NSArray *sut = @[self.generatorA];
    
    // when
    ZMTransportRequest *request = [sut nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertTrue([request isKindOfClass:ZMTransportRequest.class]);
    XCTAssertEqual(request, self.requestA);
}

- (void)testThatItReturnsTheFirstRequest;
{
    // given
    self.generatorA.nextRequest = nil;
    self.generatorB.nextRequest = self.requestB;
    NSArray *sut = @[self.generatorA, self.generatorB];
    
    // when
    ZMTransportRequest *request = [sut nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertTrue([request isKindOfClass:ZMTransportRequest.class]);
    XCTAssertEqual(request, self.requestB);
}

@end
