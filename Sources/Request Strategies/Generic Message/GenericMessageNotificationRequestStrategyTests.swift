//
//


@testable import WireRequestStrategy
import XCTest
import WireRequestStrategy
import WireDataModel
import WireTransport

class GenericMessageNotificationRequestStrategyTests: MessagingTestBase {

    let mockClientRegistrationStatus = MockClientRegistrationStatus()
    var sut: GenericMessageNotificationRequestStrategy!

    override func setUp() {
        super.setUp()

        self.syncMOC.performGroupedAndWait { moc in
            self.sut = GenericMessageNotificationRequestStrategy(managedObjectContext: moc, clientRegistrationDelegate: self.mockClientRegistrationStatus)
        }

    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testThatItDoesNotCreateARequestWhenNoNotificationWasFired() {
        self.syncMOC.performGroupedAndWait { _ in
            // WHEN & then
            XCTAssertNil(self.sut.nextRequest())
        }
    }

    func testThatItCreatesARequestWhenPostingAGenericMessageScheduleNotification() {
        self.syncMOC.performGroupedAndWait { moc in
            // GIVEN
            let genericMessage = ZMGenericMessage.clientAction(.RESETSESSION)

            // WHEN
            GenericMessageScheduleNotification.post(message: genericMessage, conversation: self.groupConversation)
        }
        self.syncMOC.performGroupedAndWait { syncMOC in
            // THEN
            guard let request = self.sut.nextRequest() else { XCTFail("No request created"); return }
            XCTAssertEqual(request.method, .methodPOST)
            XCTAssertEqual(request.path, "/conversations/\(self.groupConversation.remoteIdentifier!.transportString())/otr/messages")
        }
    }
    
}
