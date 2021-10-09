//


import Foundation
import XCTest
import WireDataModel
import WireRequestStrategy

// MARK: - Confirmation message
extension ClientMessageTranscoderTests {
    
    func testThatItSendsAConfirmationMessage() {
        self.syncMOC.performGroupedBlockAndWait {
            
            // GIVEN
            let confirmationMessage = self.oneToOneConversation.appendClientMessage(with: ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: UUID(), type: .DELIVERED)))!
            self.syncMOC.saveOrRollback()
            self.sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set([confirmationMessage])) }
            
            // WHEN
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            
            // THEN
            guard let message = self.outgoingEncryptedMessage(from: request, for: self.otherClient) else { return XCTFail() }
            XCTAssertTrue(message.hasConfirmation())
        }
    }

    func testThatItDoesNotSendAnyConfirmationWhenItIsStillFetchingNotificationsInTheBackground() {
        syncMOC.performGroupedBlockAndWait {

            // Given
            let confirmationMessage = self.oneToOneConversation.appendClientMessage(with: ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: UUID(), type: .DELIVERED)))!
            self.syncMOC.saveOrRollback()
            self.sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set([confirmationMessage])) }

            // When
            self.mockApplicationStatus.notificationFetchStatus = .inProgress

            // Then
            XCTAssertNil(self.sut.nextRequest())

            // When
            self.mockApplicationStatus.notificationFetchStatus = .done
            // Then
            guard let request = self.sut.nextRequest() else { return XCTFail() }

            // THEN
            guard let message = self.outgoingEncryptedMessage(from: request, for: self.otherClient) else { return XCTFail() }
            XCTAssertTrue(message.hasConfirmation())
        }
    }

    func testThatItDeletesTheConfirmationMessageWhenSentSuccessfully() {

        // GIVEN
        var confirmationMessage: ZMMessage!
        self.syncMOC.performGroupedBlockAndWait {

            confirmationMessage = self.oneToOneConversation.appendClientMessage(with: ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: UUID(), type: .DELIVERED)))
            self.syncMOC.saveOrRollback()
            self.sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set([confirmationMessage])) }

            // WHEN
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            request.complete(with: ZMTransportResponse(payload: NSDictionary(), httpStatus: 200, transportSessionError: nil))
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(confirmationMessage.isZombieObject)
        }
    }
    
}
