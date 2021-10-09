//

import XCTest
import WireTesting
@testable import WireRequestStrategy

class MockTranscoder: IdentifierObjectSyncTranscoder {
    
    typealias T = UUID
    
    var fetchLimit: Int = 1
    
    var lastRequestedIdentifiers: Set<UUID> = Set()
    func request(for identifiers: Set<UUID>) -> ZMTransportRequest? {
        lastRequestedIdentifiers = identifiers
        return ZMTransportRequest(getFromPath: "/dummy/path")
    }
    
    var lastReceivedResponse: (response: ZMTransportResponse, identifiers: Set<UUID>)? = nil
    func didReceive(response: ZMTransportResponse, for identifiers: Set<UUID>) {
        lastReceivedResponse = (response, identifiers)
    }
    
}

class IdentifierObjectSyncTests: ZMTBaseTest {
    
    var moc: NSManagedObjectContext!
    var transcoder: MockTranscoder!
    var sut: IdentifierObjectSync<MockTranscoder>!

    override func setUp() {
        super.setUp()
    
        moc = MockModelObjectContextFactory.testContext()
        transcoder = MockTranscoder()
        sut = IdentifierObjectSync(managedObjectContext: moc, transcoder: transcoder)
    }

    override func tearDown() {
        super.tearDown()
    }

    func testThatItAsksTranscoderForRequestToSyncIdentifier() {
        // given
        let uuid = UUID()
        
        // when
        sut.sync(identifiers: [uuid])
        _ = sut.nextRequest()
        
        // then
        XCTAssertTrue(transcoder.lastRequestedIdentifiers.contains(uuid))
    }
    
    func testThatItAsksTranscoderForRequestToSyncIdentifier_OnlyOnce() {
        // given
        let uuid = UUID()
        
        // when
        sut.sync(identifiers: [uuid])
        _ = sut.nextRequest()
        XCTAssertTrue(transcoder.lastRequestedIdentifiers.contains(uuid))
        
        
        // then
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItRespectsTheFetchLimit_WhenBelowNumberOfAvailableIdentifiers() {
        // given
        let uuid1 = UUID()
        let uuid2 = UUID()
        
        transcoder.fetchLimit = 1
        
        // when
        sut.sync(identifiers: [uuid1])
        sut.sync(identifiers: [uuid2])
        _ = sut.nextRequest()
        
        // then
        XCTAssertEqual(transcoder.lastRequestedIdentifiers.count, 1)
    }
    
    func testThatItRespectsTheFetchLimit_WhenEqualOrLargerThanNumberOfAvailableIdentifiers() {
        // given
        let uuid1 = UUID()
        let uuid2 = UUID()
        
        transcoder.fetchLimit = 2
        
        // when
        sut.sync(identifiers: [uuid1])
        sut.sync(identifiers: [uuid2])
        _ = sut.nextRequest()
        
        // then
        XCTAssertEqual(transcoder.lastRequestedIdentifiers.count, 2)
        XCTAssertEqual(transcoder.lastRequestedIdentifiers, Set(arrayLiteral: uuid1, uuid2))
    }
    
    func testThatItForwardsIdentifiersTogetherWithTheResponse() {
        // given
        let uuid = UUID()
        
        // when
        sut.sync(identifiers: [uuid])
        let request = sut.nextRequest()
        request?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(transcoder.lastReceivedResponse)
        XCTAssertEqual(transcoder.lastReceivedResponse?.identifiers, Set(arrayLiteral: uuid))
    }
    
    func testThatItRetriesToSyncIdentifierstOnFailure() {
        // given
        let uuid = UUID()
        let failuresCodes: [ZMTransportSessionErrorCode] = [.tryAgainLater, .requestExpired]
        
        // when
        sut.sync(identifiers: [uuid])
        var request = sut.nextRequest()
        
        for failureCode in failuresCodes {
            request?.complete(with: ZMTransportResponse(transportSessionError: NSError(domain: ZMTransportSessionErrorDomain, code: failureCode.rawValue, userInfo: nil)))
            transcoder.lastRequestedIdentifiers = Set()
            XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
            request = sut.nextRequest()
            
            // then
            XCTAssertTrue(transcoder.lastRequestedIdentifiers.contains(uuid))
        }
    }
    
    func testThatItDoesNotRetryToSyncIdentifierstOnSuccess() {
        // given
        let uuid = UUID()
        
        // when
        sut.sync(identifiers: [uuid])
        let request = sut.nextRequest()
        request?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDoesNotRetryToSyncIdentifierstOnPermanentError() {
        // given
        let uuid = UUID()
        
        // when
        sut.sync(identifiers: [uuid])
        let request = sut.nextRequest()
        request?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(sut.nextRequest())
    }

}
