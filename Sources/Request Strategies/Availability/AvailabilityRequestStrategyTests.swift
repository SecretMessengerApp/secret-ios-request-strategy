//


import XCTest
import WireRequestStrategy

class AvailabilityRequestStrategyTests: MessagingTestBase {
    
    var applicationStatus: MockApplicationStatus!
    var sut : AvailabilityRequestStrategy!
    
    override func setUp() {
        super.setUp()

        self.syncMOC.performGroupedAndWait { moc in
            self.applicationStatus = MockApplicationStatus()
            self.applicationStatus.mockSynchronizationState = .eventProcessing
            self.sut = AvailabilityRequestStrategy(withManagedObjectContext: moc, applicationStatus: self.applicationStatus)
        }
    }
    
    override func tearDown() {
        sut = nil
        applicationStatus = nil
        
        super.tearDown()
    }
    
    func testThatItGeneratesARequestWhenAvailabilityIsModified() {
        self.syncMOC.performGroupedAndWait { moc in

            // given
            let selfUser = ZMUser.selfUser(in: moc)
            selfUser.needsToBeUpdatedFromBackend = false
            selfUser.setLocallyModifiedKeys(Set(arrayLiteral: AvailabilityKey))
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: selfUser)) })

            // when
            let request = self.sut.nextRequest()


            // then
            XCTAssertNotNil(request)
        }
    }
    
    func testThatItDoesntGenerateARequestWhenAvailabilityIsModifiedForOtherUsers() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            self.otherUser.needsToBeUpdatedFromBackend = false
            self.otherUser.modifiedKeys = Set(arrayLiteral: AvailabilityKey)
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: self.otherUser)) })

            // when
            let request = self.sut.nextRequest()

            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItUpdatesAvailabilityFromUpdateEvent() {
        self.syncMOC.performGroupedAndWait { moc in

            // given
            let selfUser = ZMUser.selfUser(in: moc)
            _ = ZMConversation(remoteID: selfUser.remoteIdentifier!, createIfNeeded: true, in: moc) // create self conversation

            let message = ZMGenericMessage.message(content: ZMAvailability.availability(.away))
            let dict = ["recipient": self.selfClient.remoteIdentifier!,
                        "sender": self.selfClient.remoteIdentifier!,
                        "text": message.data().base64String()] as NSDictionary

            let updateEvent = ZMUpdateEvent(fromEventStreamPayload: ([
                "type": "conversation.otr-message-add",
                "data":dict,
                "from" : selfUser.remoteIdentifier!,
                "conversation":ZMConversation.selfConversation(in: moc).remoteIdentifier!.transportString(),
                "time":Date(timeIntervalSince1970: 555555).transportString()] as NSDictionary), uuid: nil)!

            // when
            self.sut.processEvents([updateEvent], liveEvents: true, prefetchResult: nil)

            // then
            XCTAssertEqual(selfUser.availability, .away)
        }
    }
    
    func testThatItRequestSlowSyncIfWeAreSendingToRedudantClients() {
        self.syncMOC.performGroupedAndWait { _ in
            // given when
            self.sut.detectedRedundantClients()

            // then
            XCTAssertTrue(self.applicationStatus.slowSyncWasRequested)
        }
    }
    
    func testThatItRequestSlowSyncIfWeAreMissingAUser() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let missingUser = ZMUser(remoteID: UUID(), createIfNeeded: true, in: moc)!

            // when
            self.sut.detectedMissingClient(for: missingUser)

            // then
            XCTAssertTrue(self.applicationStatus.slowSyncWasRequested)
        }
    }
    
    func testThatItDoesNotRequestSlowSyncIfWeAreNotMissingAUser() {
        self.syncMOC.performGroupedAndWait { _ in
            // given
            let connectedUser = self.otherUser!

            // when
            self.sut.detectedMissingClient(for: connectedUser)

            // then
            XCTAssertFalse(self.applicationStatus.slowSyncWasRequested)
        }
    }
    
}
