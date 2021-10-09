
import XCTest
@testable import WireRequestStrategy

struct ClientUpdateResponse: Codable {
    
    typealias ClientList = [String: [String]]
    
    enum ErrorLabel: String, Codable {
        case unknownClient = "unknown-client"
    }
    
    var label: ErrorLabel?
    var missing: ClientList?
    var deleted: ClientList?
    var redundant: ClientList?
    
}

class VerifyLegalHoldRequestStrategyTests: MessagingTestBase {

    var sut: VerifyLegalHoldRequestStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    
    override func setUp() {
        super.setUp()
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing
        sut = VerifyLegalHoldRequestStrategy(withManagedObjectContext: self.syncMOC, applicationStatus: mockApplicationStatus)
    }
    
    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
        super.tearDown()
    }
    
    func missingClientsResponse(_ clientUpdateResponse: ClientUpdateResponse) -> ZMTransportData {
        let encoder = JSONEncoder()
        let encoded = try! encoder.encode(clientUpdateResponse)
        return try! JSONSerialization.jsonObject(with: encoded, options: []) as! ZMTransportData
    }
    
    // MARK: Request generation
    
    func testThatItCreatesARequest_WhenConversationNeedsToVerifyLegalHold() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let conversation = self.createGroupConversation(with: self.otherUser)
            
            // WHEN
            conversation.setValue(true, forKey: #keyPath(ZMConversation.needsToVerifyLegalHold))
            self.sut.objectsDidChange(Set(arrayLiteral: conversation))
            
            // THEN
            XCTAssertEqual(self.sut.nextRequest()?.path, "/conversations/\(conversation.remoteIdentifier!.transportString())/otr/messages")
        }
    }
    
    // MARK: Response handling
    
    func testThatItResetsNeedsToVerifyLegalHoldFlag_WhenReceivingTheResponse() {
        var conversation: ZMConversation!
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            conversation = self.createGroupConversation(with: self.otherUser)
            conversation.setValue(true, forKey: #keyPath(ZMConversation.needsToVerifyLegalHold))
            self.sut.objectsDidChange(Set(arrayLiteral: conversation))
            let request = self.sut.nextRequest()
            
            // WHEN
            request?.complete(with: ZMTransportResponse(payload: [:] as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        syncMOC.performGroupedBlockAndWait {
            XCTAssertFalse(conversation.needsToVerifyLegalHold)
        }
    }
    
    func testThatItRegistersMissingClients() {
        var conversation: ZMConversation!
        let clientID = "client123"
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            conversation = self.createGroupConversation(with: self.otherUser)
            conversation.setValue(true, forKey: #keyPath(ZMConversation.needsToVerifyLegalHold))
            self.sut.objectsDidChange(Set(arrayLiteral: conversation))
            let request = self.sut.nextRequest()
            let payload = self.missingClientsResponse(ClientUpdateResponse(label: nil, missing: [self.otherUser.remoteIdentifier.transportString(): [clientID]], deleted: nil, redundant: nil))

            // WHEN
            request?.complete(with: ZMTransportResponse(payload: payload, httpStatus: 412, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        syncMOC.performGroupedBlockAndWait {
            guard let client = UserClient.fetchUserClient(withRemoteId: clientID, forUser: self.otherUser, createIfNeeded: false) else { return XCTFail() }
            
            XCTAssertEqual(client.remoteIdentifier, clientID)
        }
    }
    
    func testThatItDeletesDeletedClients() {
        var conversation: ZMConversation!
        let deletedClientID = "client1"
        let existingClientID = "client2"
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            XCTAssertNotNil(UserClient.fetchUserClient(withRemoteId: deletedClientID, forUser: self.otherUser, createIfNeeded: true))
            XCTAssertNotNil(UserClient.fetchUserClient(withRemoteId: existingClientID, forUser: self.otherUser, createIfNeeded: true))
            
            conversation = self.createGroupConversation(with: self.otherUser)
            conversation.setValue(true, forKey: #keyPath(ZMConversation.needsToVerifyLegalHold))
            self.sut.objectsDidChange(Set(arrayLiteral: conversation))
            
            let request = self.sut.nextRequest()
            let payload = self.missingClientsResponse(ClientUpdateResponse(label: nil, missing: [self.otherUser.remoteIdentifier.transportString(): [existingClientID]], deleted: nil, redundant: nil))
            
            // WHEN
            request?.complete(with: ZMTransportResponse(payload: payload, httpStatus: 412, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        syncMOC.performGroupedBlockAndWait {
            guard let existingClient = UserClient.fetchUserClient(withRemoteId: existingClientID, forUser: self.otherUser, createIfNeeded: false) else { return XCTFail() }
            
            XCTAssertNil(UserClient.fetchUserClient(withRemoteId: deletedClientID, forUser: self.otherUser, createIfNeeded: false))
            XCTAssertEqual(existingClient.remoteIdentifier, existingClientID)
        }
    }
    
    func testThatItDeletesAllClients_WhenUserHasNoMissingClientEntry() {
        var conversation: ZMConversation!
        let deletedClientID = "client1"
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            XCTAssertNotNil(UserClient.fetchUserClient(withRemoteId: deletedClientID, forUser: self.otherUser, createIfNeeded: true))
            
            conversation = self.createGroupConversation(with: self.otherUser)
            conversation.setValue(true, forKey: #keyPath(ZMConversation.needsToVerifyLegalHold))
            self.sut.objectsDidChange(Set(arrayLiteral: conversation))
            
            let request = self.sut.nextRequest()
            let payload = self.missingClientsResponse(ClientUpdateResponse(label: nil, missing: [:], deleted: nil, redundant: nil))
            
            // WHEN
            request?.complete(with: ZMTransportResponse(payload: payload, httpStatus: 412, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(UserClient.fetchUserClient(withRemoteId: deletedClientID, forUser: self.otherUser, createIfNeeded: false))
        }
    }
    
    func testThatItIgnoresMissingSelfClients() {
        var conversation: ZMConversation!
        let selfClientID = "selfClient1"
    
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            conversation = self.createGroupConversation(with: self.otherUser)
            conversation.setValue(true, forKey: #keyPath(ZMConversation.needsToVerifyLegalHold))
            self.sut.objectsDidChange(Set(arrayLiteral: conversation))
            
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let request = self.sut.nextRequest()
            let payload = self.missingClientsResponse(ClientUpdateResponse(label: nil, missing: [selfUser.remoteIdentifier.transportString(): [selfClientID]], deleted: nil, redundant: nil))
            
            // WHEN
            request?.complete(with: ZMTransportResponse(payload: payload, httpStatus: 412, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        syncMOC.performGroupedBlockAndWait {
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            
            XCTAssertNotNil(selfUser.selfClient())
        }
    }

}
