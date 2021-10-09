//

import Foundation
import XCTest
import WireDataModel


// MARK: - Dependency
extension ClientMessageTranscoderTests {
    
    func testThatItReturnsNewClientAsDependentObjectForMessageIfItHasNotBeenFetched() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            
            // WHEN
            self.otherClient.needsToBeUpdatedFromBackend = true
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message)
            XCTAssertEqual(dependency as? UserClient, self.otherClient)
        }
    }
    
    func testThatItReturnsSelfClientAsDependentObjectForMessageIfItHasMissingClients() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            
            // WHEN
            self.selfClient.missesClient(self.otherClient)
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message)
            XCTAssertEqual(dependency as? UserClient, self.selfClient)
        }
    }
    
    func testThatItReturnsConversationIfNeedsToBeUpdatedFromBackendBeforeMissingClients() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            
            // WHEN
            self.selfClient.missesClient(self.otherClient)
            self.groupConversation.needsToBeUpdatedFromBackend = true
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message)
            XCTAssertEqual(dependency as? ZMConversation, self.groupConversation)
        }
    }
    
    func testThatItReturnsConnectionIfNeedsToBeUpdatedFromBackendBeforeMissingClients() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let message = self.oneToOneConversation.append(text: "foo") as! ZMClientMessage
            
            // WHEN
            self.selfClient.missesClient(self.otherClient)
            self.oneToOneConversation.connection?.needsToBeUpdatedFromBackend = true
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message)
            XCTAssertEqual(dependency as? ZMConnection, self.oneToOneConversation.connection)
        }
    }
    
    func testThatItDoesNotReturnSelfClientAsDependentObjectForMessageIfConversationIsNotAffectedByMissingClients() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let user2 = self.createUser()
            let conversation2 = self.createGroupConversation(with: user2)
            let message = conversation2.append(text: "foo") as! ZMClientMessage
            
            // WHEN
            self.selfClient.missesClient(self.otherClient)
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message)
            XCTAssertNil(dependency)
        }
    }
    
    func testThatItReturnsNilAsDependentObjectForMessageIfItHasNoMissingClients() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message)
            XCTAssertNil(dependency)
        }
    }
    
    func testThatItReturnsAPreviousPendingMessageAsDependency() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let timeZero = Date(timeIntervalSince1970: 10000)
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            message.serverTimestamp = timeZero
            message.markAsSent()
            
            let nextMessage = self.groupConversation.append(text: "bar") as! ZMClientMessage
            // nextMessage.serverTimestamp = timeZero.addingTimeInterval(100) // this ensures the sorting
            
            // WHEN
            let lastMessage = self.groupConversation.append(text: "zoo") as! ZMClientMessage
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: lastMessage)
            XCTAssertEqual(dependency as? ZMClientMessage, nextMessage)
        }
    }
    
    func testThatItDoesNotReturnAPreviousSentMessageAsDependency() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let timeZero = Date(timeIntervalSince1970: 10000)
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            message.serverTimestamp = timeZero
            message.markAsSent()
            
            // WHEN
            let lastMessage = self.groupConversation.append(text: "zoo") as! ZMClientMessage
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: lastMessage)
            XCTAssertNil(dependency)
        }
    }
    
    func testThatItReturnConversationAsDependencyIfSecurityLevelIsSecureWithIgnored() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            
            // WHEN
            self.set(conversation: self.groupConversation, securityLevel: .secureWithIgnored)
            
            // THEN
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message)
            XCTAssertEqual(dependency as? ZMConversation, self.groupConversation)
        }
    }
    
    func testThatItDoesNotReturnConversationAsDependencyIfSecurityLevelIsNotSecure() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            
            // WHEN
            self.set(conversation: self.groupConversation, securityLevel: .notSecure)
            
            // THEN
            XCTAssertNil(self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message))
        }
    }
    
    func testThatItDoesNotReturnConversationAsDependencyIfSecurityLevelIsSecure() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let message = self.groupConversation.append(text: "foo") as! ZMClientMessage
            
            // WHEN
            self.set(conversation: self.groupConversation, securityLevel: .secure)
            
            // THEN
            XCTAssertNil(self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message))
        }
    }
}
