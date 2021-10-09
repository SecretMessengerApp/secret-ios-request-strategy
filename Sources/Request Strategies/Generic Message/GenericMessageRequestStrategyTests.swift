//
//

import Foundation
import XCTest
import WireDataModel
@testable import WireRequestStrategy

class GenericMessageRequestStrategyTests : MessagingTestBase {
    
    var mockClientRegistrationStatus: MockClientRegistrationStatus!
    var conversation: ZMConversation!
    var sut : GenericMessageRequestStrategy!
    
    override func setUp() {
        super.setUp()
        mockClientRegistrationStatus = MockClientRegistrationStatus()
        
        sut = GenericMessageRequestStrategy(context: syncMOC, clientRegistrationDelegate: mockClientRegistrationStatus)
        
        syncMOC.performGroupedBlockAndWait {
            let user = ZMUser.insertNewObject(in: self.syncMOC)
            user.remoteIdentifier = UUID.create()
            
            self.conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.conversation.conversationType = .group
            self.conversation.remoteIdentifier = UUID.create()
            self.conversation.internalAddParticipants([user])
        }
    }
    
    override func tearDown() {
        sut = nil
        conversation = nil
        mockClientRegistrationStatus = nil
        super.tearDown()
    }

    
    func testThatItCallsEntityCompletionHandlerOnRequestCompletion() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let expectation = self.expectation(description: "Should complete")
            let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
            let genericMessage = ZMGenericMessage.message(content: ZMMessageEdit.edit(with: ZMText.text(with: "bar"), replacingMessageId: UUID.create()))
            let message = GenericMessageEntity(conversation: self.conversation, message: genericMessage) {
                XCTAssertEqual($0, response)
                expectation.fulfill()
            }
            
            // WHEN
            self.sut.request(forEntity: message, didCompleteWithResponse: response)
            
            // THEN
            XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
        }
    }
    
    func testThatItCallsEntityCompletionHandlerOnShouldRetry() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let expectation = self.expectation(description: "Should complete")
            let response = ZMTransportResponse(payload: nil, httpStatus: 412, transportSessionError: nil)
            let genericMessage = ZMGenericMessage.message(content: ZMMessageEdit.edit(with: ZMText.text(with: "bar"), replacingMessageId: UUID.create()))
            let message = GenericMessageEntity(conversation: self.conversation, message: genericMessage) {
                XCTAssertEqual($0, response)
                expectation.fulfill()
            }
            
            // WHEN
            _ = self.sut.shouldTryToResend(entity: message, afterFailureWithResponse: response)
            
            // THEN
            XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
        }
    }

    
    func testThatItCreatesARequestForAGenericMessage() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let genericMessage = ZMGenericMessage.message(content: ZMMessageEdit.edit(with: ZMText.text(with: "bar"), replacingMessageId: UUID.create()))
            self.sut.schedule(message: genericMessage, inConversation: self.groupConversation) { ( _ ) in }
            
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertEqual(request!.method, .methodPOST)
            XCTAssertEqual(request!.path, "/conversations/\(self.groupConversation.remoteIdentifier!.transportString())/otr/messages")
        }
    }
    
    func testThatItForwardsObjectDidChangeToTheSync(){
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            self.selfClient.missesClient(self.otherClient)
            
            let genericMessage = ZMGenericMessage.message(content: ZMMessageEdit.edit(with: ZMText.text(with: "bar"), replacingMessageId: UUID.create()))
            self.sut.schedule(message: genericMessage, inConversation: self.groupConversation) { ( _ ) in }
            
            // WHEN
            let request1 = self.sut.nextRequest()
            
            // THEN
            XCTAssertNil(request1)
            
            // and when
            self.selfClient.removeMissingClient(self.otherClient)
            self.sut.objectsDidChange(Set([self.selfClient]))
            let request2 = self.sut.nextRequest()
            
            // THEN
            XCTAssertEqual(request2!.method, .methodPOST)
            XCTAssertEqual(request2!.path, "/conversations/\(self.groupConversation.remoteIdentifier!.transportString())/otr/messages")
        }
    }
    
}
