//
//

import WireDataModel
@testable import WireRequestStrategy
import XCTest


@objcMembers class MockOTREntity: OTREntity, Hashable {
    
    var context: NSManagedObjectContext
    public var isExpired: Bool = false
    public func expire() {
        isExpired = true
    }
    
    public func missesRecipients(_ recipients: Set<UserClient>!) {
        // no-op
    }
    public var conversation: ZMConversation?
    
    var isMissingClients = false
    var didCallHandleClientUpdates = false
    
    var dependentObjectNeedingUpdateBeforeProcessing: NSObject?
    
    init(conversation: ZMConversation, context: NSManagedObjectContext) {
        self.conversation = conversation
        self.context = context
    }
    
    var hashValue: Int {
        return self.conversation!.hashValue
    }
    
    func detectedRedundantClients() {
        conversation?.needsToBeUpdatedFromBackend = true
    }
    
    func detectedMissingClient(for user: ZMUser) {
        conversation?.addParticipantIfMissing(user, date: nil)
    }
    
}

func ==(lhs: MockOTREntity, rhs: MockOTREntity) -> Bool {
    return lhs === rhs
}

class OTREntityTranscoderTests : MessagingTestBase {
    
    let mockClientRegistrationStatus = MockClientRegistrationStatus()
    var mockEntity : MockOTREntity!
    var sut : OTREntityTranscoder<MockOTREntity>!
    
    override func setUp() {
        super.setUp()

        self.syncMOC.performGroupedAndWait { moc in
            self.mockEntity = MockOTREntity(conversation: self.groupConversation, context: moc)
            self.sut = OTREntityTranscoder(context: moc, clientRegistrationDelegate: self.mockClientRegistrationStatus)
        }
    }
    
    override func tearDown() {
        self.mockEntity = nil
        self.sut = nil
        super.tearDown()
    }
    
    func testThatItHandlesDeletionOfSelfClient() {
        self.syncMOC.performGroupedAndWait { _ in
            // GIVEN
            let payload = [
                "label" : "unknown-client"
            ]

            let response = ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 403, transportSessionError: nil)

            // WHEN
            XCTAssertFalse(self.sut.shouldTryToResend(entity: self.mockEntity, afterFailureWithResponse: response))

            // THEN
            XCTAssertEqual(self.mockClientRegistrationStatus.deletionCalls, 1)
        }
    }
    
    func testThatItHandlesDeletionOfClient() {
        self.syncMOC.performGroupedAndWait { _ in
            // GIVEN
            let payload = [
                "deleted" : ["\(self.otherUser.remoteIdentifier!)" : [self.otherClient.remoteIdentifier!] ]
            ]
            let response = ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 200, transportSessionError: nil)

            // WHEN
            self.sut.request(forEntity: self.mockEntity, didCompleteWithResponse: response)

            // THEN
            XCTAssertTrue(self.otherClient.isDeleted)
        }
    }
    
    func testThatItHandlesMissingClient_addsClientToListOfMissingClients() {
        self.syncMOC.performGroupedAndWait { moc in
            // GIVEN
            let user = ZMUser.insertNewObject(in: moc)
            user.remoteIdentifier = UUID.create()
            let clientId = "ajsd9898u13a"

            let payload = [
                "missing" : ["\(user.remoteIdentifier!)" : [clientId] ]
            ]
            let response = ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 200, transportSessionError: nil)

            // WHEN
            self.sut.request(forEntity: self.mockEntity, didCompleteWithResponse: response)

            // THEN
            XCTAssertEqual(self.selfClient.missingClients!.count, 1)
            XCTAssertEqual(self.selfClient.missingClients!.first!.remoteIdentifier, clientId)
        }
    }
    
    func testThatItHandlesMissingClient_MarkAsNeedsToDownloadNotAlreadyThere() {
        self.syncMOC.performGroupedAndWait { _ in
            // GIVEN
            let user = self.createUser()
            let clientId = "ajsd9898u13a"

            let payload = [
                "missing" : ["\(user.remoteIdentifier!)" : [clientId] ]
            ]
            let response = ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 200, transportSessionError: nil)

            // WHEN
            self.sut.request(forEntity: self.mockEntity, didCompleteWithResponse: response)

            // THEN
            XCTAssertTrue(self.groupConversation.needsToBeUpdatedFromBackend)
        }
    }
    
}
