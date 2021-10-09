//
//


import XCTest
import WireProtos
import WireDataModel
import WireUtilities
@testable import WireRequestStrategy

class ClientMessageRequestFactoryTests: MessagingTestBase {
}

// MARK: - Text messages
extension ClientMessageRequestFactoryTests {
    
    func testThatItCreatesRequestToPostOTRTextMessage() {
        
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let text = "Antani"
            let message = self.groupConversation.append(text: text) as! ZMClientMessage
            
            // WHEN
            guard let request = ClientMessageRequestFactory().upstreamRequestForMessage(message, forConversationWithId: self.groupConversation.remoteIdentifier!) else {
                return XCTFail("No request")
            }
            
            // THEN
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
            XCTAssertEqual(request.path, "/conversations/\(self.groupConversation.remoteIdentifier!.transportString())/otr/messages")
            
            guard let receivedMessage = self.outgoingEncryptedMessage(from: request, for: self.otherClient) else {
                return XCTFail("Invalid message")
            }
            XCTAssertEqual(receivedMessage.textData?.content, text)
        }
    }
}

// MARK: - Confirmation Messages
extension ClientMessageRequestFactoryTests {
    
    func testThatItCreatesRequestToPostOTRConfirmationMessage() {
        
        self.syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let text = "Antani"
            let message = self.oneToOneConversation.append(text: text) as! ZMClientMessage
            message.sender = self.otherUser
            let confirmation = ZMConfirmation.confirm(messageId: message.nonce!, type: .DELIVERED)
            let confirmationMessage = self.oneToOneConversation.appendClientMessage(with: ZMGenericMessage.message(content: confirmation), expires: false, hidden: true)!
            
            print("CLIENT ID", (message.conversation?.lastServerSyncedActiveParticipants.firstObject! as! ZMUser).remoteIdentifier!)
            print("OTHER USER", self.otherUser.remoteIdentifier!)
            // WHEN
            guard let request = ClientMessageRequestFactory().upstreamRequestForMessage(confirmationMessage, forConversationWithId: self.oneToOneConversation.remoteIdentifier!) else {
                return XCTFail("No request")
            }
            
            // THEN
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
            XCTAssertEqual(request.path, "/conversations/\(self.oneToOneConversation.remoteIdentifier!.transportString())/otr/messages?report_missing=\(self.otherUser.remoteIdentifier!.transportString())")
            guard let receivedMessage = self.outgoingEncryptedMessage(from: request, for: self.otherClient) else {
                return XCTFail("Invalid message")
            }
            XCTAssertTrue(receivedMessage.hasConfirmation())
        }
    }
}

// MARK: Ephemeral Messages
extension ClientMessageRequestFactoryTests {
    
    func testThatItCreatesRequestToPostEphemeralTextMessage() {
        self.syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let text = "Boo"
            self.groupConversation.messageDestructionTimeout = .local(.tenSeconds)
            let message = self.groupConversation.append(text: text) as! ZMClientMessage
            
            // WHEN
            guard let request = ClientMessageRequestFactory().upstreamRequestForMessage(message, forConversationWithId: self.groupConversation.remoteIdentifier!) else {
                return XCTFail()
            }
            
            // THEN
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
            XCTAssertEqual(request.path, "/conversations/\(self.groupConversation.remoteIdentifier!.transportString())/otr/messages")
            guard let receivedMessage = self.outgoingEncryptedMessage(from: request, for: self.otherClient) else {
                return XCTFail("Invalid message")
            }
            XCTAssertEqual(receivedMessage.textData?.content, text)
        }
    }
    
}
