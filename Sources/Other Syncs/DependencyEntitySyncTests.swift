//
//

import Foundation
import WireTesting

@testable import WireRequestStrategy

class MockDependencyEntity : DependencyEntity, Hashable {
    public var isExpired: Bool = false
    fileprivate let uuid = UUID()
    
    public func expire() {
         isExpired = true
    }

    var dependentObjectNeedingUpdateBeforeProcessing: NSObject?

    var hashValue: Int {
        return self.uuid.hashValue
    }
}

func ==(lhs: MockDependencyEntity, rhs: MockDependencyEntity) -> Bool {
    return lhs === rhs
}

class MockEntityTranscoder : EntityTranscoder {
    
    var didCallRequestForEntity : Bool = false
    var didCallRequestForEntityDidCompleteWithResponse : Bool = false
    var didCallShouldTryToResendAfterFailure : Bool = false
    
    var shouldResendOnFailure = false
    var generatedRequest : ZMTransportRequest?
    
    var requestForEntityExpectation : XCTestExpectation?
    var requestForEntityDidCompleteWithResponseExpectation : XCTestExpectation?
    var shouldTryToResendAfterFailureExpectation : XCTestExpectation?
    
    func request(forEntity entity: MockDependencyEntity) -> ZMTransportRequest? {
        requestForEntityExpectation?.fulfill()
        didCallRequestForEntity = true
        return generatedRequest
    }
    
    func request(forEntity entity: MockDependencyEntity, didCompleteWithResponse response: ZMTransportResponse) {
        requestForEntityDidCompleteWithResponseExpectation?.fulfill()
        didCallRequestForEntityDidCompleteWithResponse = true
    }
    
    func shouldTryToResend(entity: MockDependencyEntity, afterFailureWithResponse response: ZMTransportResponse) -> Bool {
        shouldTryToResendAfterFailureExpectation?.fulfill()
        didCallShouldTryToResendAfterFailure = true
        return shouldResendOnFailure
    }
    
}

class DependencyEntitySyncTests : ZMTBaseTest {

    var context : NSManagedObjectContext!
    var mockTranscoder = MockEntityTranscoder()
    var sut : DependencyEntitySync<MockEntityTranscoder>!
    var dependency : MockEntity!
    var anotherDependency : MockEntity!
    
    override func setUp() {
        super.setUp()
        
        context = MockModelObjectContextFactory.testContext()
        dependency = MockEntity.insertNewObject(in: context)
        anotherDependency = MockEntity.insertNewObject(in: context)
        
        sut = DependencyEntitySync(transcoder: mockTranscoder, context: context)
    }
    
    // Mark - Request creation

    func testThatTranscoderIsAskedToCreateRequest_whenEntityHasNoDependencies() {
    
        // given
        let entity = MockDependencyEntity()
        
        // when
        sut.synchronize(entity: entity)
        _ = sut.nextRequest()
        
        // then
        XCTAssertTrue(mockTranscoder.didCallRequestForEntity)
    }
    
    func testThatTranscoderIsNotAskedToCreateRequest_whenEntityHasDependencies() {
        
        // given
        let entity = MockDependencyEntity()
        entity.dependentObjectNeedingUpdateBeforeProcessing = dependency
        
        // when
        sut.synchronize(entity: entity)
        _ = sut.nextRequest()
        
        // then
        XCTAssertFalse(mockTranscoder.didCallRequestForEntity)
    }
    
    func testThatEntityIsExpired_whenExpiringEntitiesWithDependencies() {
        // given
        let entity = MockDependencyEntity()
        entity.dependentObjectNeedingUpdateBeforeProcessing = dependency
        sut.synchronize(entity: entity)
        
        // when
        sut.expireEntities(withDependency: dependency)
        
        // then
        XCTAssertTrue(entity.isExpired)
    }
    
    func testThatTranscoderIsNotAskedToCreateRequest_whenEntityHasSwappedDependenciesAfterAnUpdate() {
        
        // given
        let entity = MockDependencyEntity()
        entity.dependentObjectNeedingUpdateBeforeProcessing = dependency
        sut.synchronize(entity: entity)
        
        // when
        entity.dependentObjectNeedingUpdateBeforeProcessing = anotherDependency
        sut.objectsDidChange(Set(arrayLiteral: dependency))
        _ = sut.nextRequest()
        
        // then
        XCTAssertFalse(mockTranscoder.didCallRequestForEntity)
    }
    
    func testThatTranscoderIsNotAskedToCreateRequest_whenEntityHasExpired() {
        
        // given
        let entity = MockDependencyEntity()
        sut.synchronize(entity: entity)
        entity.expire()
        
        // when
        _ = sut.nextRequest()
        
        // then
        XCTAssertFalse(mockTranscoder.didCallRequestForEntity)
    }
    
    func testThatTranscoderIsAskedToCreateRequest_whenEntityHasNoDependenciesAfterAnUpdate() {
        
        // given
        let entity = MockDependencyEntity()
        entity.dependentObjectNeedingUpdateBeforeProcessing = dependency
        sut.synchronize(entity: entity)
        
        // when
        entity.dependentObjectNeedingUpdateBeforeProcessing = nil
        sut.objectsDidChange(Set(arrayLiteral: dependency))
        _ = sut.nextRequest()
        
        // then
         XCTAssertTrue(mockTranscoder.didCallRequestForEntity)
    }
    
    // Mark - Response handling
    
    func testThatTranscoderIsAskedToHandleSuccessfullResponse() {
        // given
        mockTranscoder.generatedRequest = ZMTransportRequest(getFromPath: "/foo")
        mockTranscoder.requestForEntityDidCompleteWithResponseExpectation = expectation(description: "Was asked to handle response")
        
        let entity = MockDependencyEntity()
        sut.synchronize(entity: entity)
        let request = sut.nextRequest()
        
        // when
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
        request?.complete(with: response)
        
        // then
         XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTranscoderIsAskedToHandleFailureResponse() {
        // given
        mockTranscoder.generatedRequest = ZMTransportRequest(getFromPath: "/foo")
        mockTranscoder.shouldTryToResendAfterFailureExpectation = expectation(description: "Was asked to resend request")
        
        let entity = MockDependencyEntity()
        sut.synchronize(entity: entity)
        let request = sut.nextRequest()
        
        // when
        let response = ZMTransportResponse(payload: nil, httpStatus: 403, transportSessionError: nil)
        request?.complete(with: response)
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTranscoderIsAskedToCreateRequest_whenTranscoderWantsToResendRequest() {
        // given
        mockTranscoder.generatedRequest = ZMTransportRequest(getFromPath: "/foo")
        mockTranscoder.shouldTryToResendAfterFailureExpectation = expectation(description: "Was asked to resend request")
        mockTranscoder.shouldResendOnFailure = true
        
        let entity = MockDependencyEntity()
        sut.synchronize(entity: entity)
        let request = sut.nextRequest()
        
        let response = ZMTransportResponse(payload: nil, httpStatus: 403, transportSessionError: nil)
        request?.complete(with: response)
        
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5)) // wait for response to fail
        mockTranscoder.didCallRequestForEntity = false //reset since we expect it be called again
        
        // when
        _ = sut.nextRequest()
        
        // then
        XCTAssertTrue(mockTranscoder.didCallRequestForEntity)
    }
    
}
