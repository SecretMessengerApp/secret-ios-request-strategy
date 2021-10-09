//

import Foundation
import XCTest
import WireRequestStrategy
import WireDataModel

extension ClientMessageTranscoderTests {
    
    func recreateSut() {
        self.sut  = ClientMessageTranscoder(in: self.syncMOC, localNotificationDispatcher: self.localNotificationDispatcher, applicationStatus: mockApplicationStatus)
    }
    
    func testThatItDoesNotObfuscatesEphemeralMessagesOnStart_SenderSelfUser_TimeNotPassed() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            self.sut = nil
            self.groupConversation.messageDestructionTimeout = .local(.tenSeconds)
            let message = self.groupConversation.append(text: "Foo")! as! ZMClientMessage
            message.markAsSent()
            self.syncMOC.saveOrRollback()
            
            // WHEN
            self.recreateSut()
            
            // THEN
            XCTAssertFalse(message.isObfuscated)
        }
    }
    
    func testThatItObfuscatesEphemeralMessagesOnStart_SenderSelfUser_TimePassed() {
        
        // GIVEN
        var message: ZMClientMessage!
        self.syncMOC.performGroupedBlockAndWait {
            
            self.groupConversation.messageDestructionTimeout = .local(MessageDestructionTimeoutValue(rawValue: 1))
            message = self.groupConversation.append(text: "Foo")! as? ZMClientMessage
            message.markAsSent()
            self.syncMOC.saveOrRollback()
            XCTAssertFalse(message.isObfuscated)
            XCTAssertNotNil(message.sender)
            XCTAssertNotNil(message.destructionDate)
        }
        
        // WHEN
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        self.recreateSut()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.spinMainQueue(withTimeout: 2)
        
        // THEN
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(message.isObfuscated)
            XCTAssertTrue(self.groupConversation.allMessages.contains(message))
        }
    }

    @available(iOS 8.3, *)
    func testThatItDeletesEphemeralMessagesOnStart_SenderOtherUser_TimePassed() {
        
        // GIVEN
        let text = "Come fosse antani"
        self.syncMOC.performGroupedBlockAndWait {
            // the timeout here has to be at least 5. If I return something smaller, it will anyway be approximated to 5 internally
            // as it's the lowest allowed timeout
            let generic = ZMGenericMessage.message(content: ZMText.text(with: text), expiresAfter: 5)
            let event = self.decryptedUpdateEventFromOtherClient(message: generic)
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            self.syncMOC.saveOrRollback()
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    
        // simulate "reading it"
        let uiConversation = try! self.uiMOC.existingObject(with: self.groupConversation.objectID) as! ZMConversation
        let message = uiConversation.lastMessage!
        _ = message.startSelfDestructionIfNeeded()
        self.uiMOC.saveOrRollback()
        
        // stop all timers
        self.stopEphemeralMessageTimers()
        
        // WHEN
        self.spinMainQueue(withTimeout: 8)
        self.syncMOC.performGroupedBlockAndWait {
            self.syncMOC.refreshAllObjects()
        }
        self.recreateSut()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        self.syncMOC.performGroupedBlock {
            self.syncMOC.saveOrRollback()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        self.uiMOC.refreshAllObjects()
        XCTAssertNotEqual(message.textMessageData?.messageText, text) // or at least, it should not be one with that message
    }
    
    @available(iOS 8.3, *)
    func testThatItDoesNotDeletesEphemeralMessagesOnStart_SenderOtherUser_TimeNotPassed() {
        
        // GIVEN
        let text = "Come fosse antani"
        self.syncMOC.performGroupedBlockAndWait {
            // the timeout here has to be at least 5. If I return something smaller, it will anyway be approximated to 5
            let generic = ZMGenericMessage.message(content: ZMText.text(with: text), expiresAfter: 5)
            let event = self.decryptedUpdateEventFromOtherClient(message: generic)
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            self.syncMOC.saveOrRollback()
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // simulate "reading it"
        let uiConversation = try! self.uiMOC.existingObject(with: self.groupConversation.objectID) as! ZMConversation
        let message = uiConversation.lastMessage!
        _ = message.startSelfDestructionIfNeeded()
        self.uiMOC.saveOrRollback()
        
        // stop all timers
        self.stopEphemeralMessageTimers()
        
        // WHEN
        self.syncMOC.performGroupedBlockAndWait {
            self.syncMOC.refreshAllObjects()
            self.recreateSut()
            self.syncMOC.saveOrRollback()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        self.uiMOC.refreshAllObjects()
        XCTAssertEqual(message.textMessageData?.messageText, text) // or at least, it should not be one with that message
    }
}

