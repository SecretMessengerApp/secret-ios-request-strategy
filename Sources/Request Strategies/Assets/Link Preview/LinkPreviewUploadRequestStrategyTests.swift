//

import XCTest
import WireRequestStrategy
import WireDataModel
import WireTransport

class LinkPreviewUploadRequestStrategyTests: MessagingTestBase {

    private var sut: LinkPreviewUploadRequestStrategy!
    private var applicationStatus: MockApplicationStatus!

    override func setUp() {
        super.setUp()
        self.syncMOC.performGroupedAndWait { syncMOC in
            self.applicationStatus = MockApplicationStatus()
            self.applicationStatus.mockSynchronizationState = .eventProcessing
            self.sut = LinkPreviewUploadRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: self.applicationStatus)
        }
    }
    
    override func tearDown() {
        applicationStatus = nil
        sut = nil
        super.tearDown()
    }

    func testThatItDoesNotCreateARequestInState_Done() {
        self.verifyThatItDoesNotCreateARequest(for: .done)
    }

    func testThatItDoesNotCreateARequestInState_WaitingToBeProcessed() {
        self.verifyThatItDoesNotCreateARequest(for: .waitingToBeProcessed)
    }

    func testThatItDoesNotCreateARequestInState_Downloaded() {
        self.verifyThatItDoesNotCreateARequest(for: .downloaded)
    }

    func testThatItDoesNotCreateARequestInState_Processed() {
        self.verifyThatItDoesNotCreateARequest(for: .processed)
    }
    
    func testThatItDoesNotCreateARequestInState_Uploaded_ForOtherUser() {
        self.syncMOC.performGroupedAndWait { moc in
            // Given
            let message = self.insertMessage(with: .uploaded)
            message.sender = self.otherUser
            
            // When
            self.process(message)
        }
        self.syncMOC.performGroupedAndWait { moc in
            
            // Then
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    func testThatItDoesCreateARequestInState_Uploaded() {
        self.syncMOC.performGroupedAndWait { moc in
            // Given
            let message = self.insertMessage(with: .uploaded)

            // When
            self.process(message)
        }
        self.syncMOC.performGroupedAndWait { moc in
            // Then
            self.verifyItCreatesARequest(in: self.groupConversation)
        }
    }

    func testThatItDoesCreateARequestInState_Uploaded_WhenTheFirstRequestFailed() {
        var message: ZMClientMessage!

        self.syncMOC.performGroupedAndWait { moc in

            // Given
            message = self.insertMessage(with: .uploaded)

            // When
            self.process(message)
        }
        self.syncMOC.performGroupedAndWait { moc in
            guard let request = self.verifyItCreatesARequest(in: self.groupConversation) else { return }

            // When
            let response = ZMTransportResponse(transportSessionError: NSError.tryAgainLaterError())
            request.complete(with: response)
        }
        self.syncMOC.performGroupedAndWait { moc in

            XCTAssertEqual(message.linkPreviewState, .uploaded)

            // Then
            self.verifyItCreatesARequest(in: self.groupConversation)
        }
    }
    
    func testThatItReturnsSelfClientAsDependentObjectForMessageIfItHasMissingClients() {
        var message: ZMClientMessage!
        self.syncMOC.performGroupedAndWait { moc in
            // Given
            message = self.insertMessage(with: .uploaded)
            self.selfClient.missesClient(self.otherClient)

            // When
            self.process(message)
        }
        self.syncMOC.performGroupedAndWait { moc in
            // Then
            let dependency = self.sut.dependentObjectNeedingUpdate(beforeProcessingObject: message)
            XCTAssertEqual(dependency as? UserClient, self.selfClient)
        }
    }

    func testThatItDoesNotCreateARequestAfterGettingsAResponseForIt() {
        var message: ZMClientMessage!
        self.syncMOC.performGroupedAndWait { moc in
            // Given
            message = self.insertMessage(with: .uploaded)
            self.process(message)
        }
        self.syncMOC.performGroupedAndWait { moc in
            // Then
            guard let request = self.verifyItCreatesARequest(in: self.groupConversation) else { return }

            // When
            let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
            request.complete(with: response)
        }
        self.syncMOC.performGroupedAndWait { moc in
            // Then
            XCTAssertEqual(message.linkPreviewState, .done)
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    // MARK: - Helper

    func insertMessage(with state: ZMLinkPreviewState, file: StaticString = #file, line: UInt = #line) -> ZMClientMessage {
        let message = groupConversation.append(text: "Test message") as! ZMClientMessage
        message.linkPreviewState = state
        XCTAssert(syncMOC.saveOrRollback(), file: file, line: line)

        return message
    }

    func verifyThatItDoesNotCreateARequest(for state: ZMLinkPreviewState, file: StaticString = #file, line: UInt = #line) {
        self.syncMOC.performGroupedAndWait { moc in
            // Given
            let message = self.insertMessage(with: state)

            // When
            self.process(message)
        }
        self.syncMOC.performGroupedAndWait { moc in

            // Then
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    @discardableResult
    func verifyItCreatesARequest(in conversation: ZMConversation, file: StaticString = #file, line: UInt = #line) -> ZMTransportRequest? {
        let request = sut.nextRequest()
        XCTAssertNotNil(request, "No request generated", file: file, line: line)
        XCTAssertEqual(request?.method, .methodPOST, file: file, line: line)
        XCTAssertEqual(request?.path, "/conversations/\(conversation.remoteIdentifier!.transportString())/otr/messages", file: file, line: line)
        return request
    }

    func process(_ message: ZMClientMessage) {
        sut.contextChangeTrackers.forEach {
            $0.objectsDidChange([message])
        }
    }
}
