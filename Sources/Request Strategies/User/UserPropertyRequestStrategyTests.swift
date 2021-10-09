//
//


import XCTest
@testable import WireRequestStrategy

class UserPropertyRequestStrategyTests: MessagingTestBase {
    
    var applicationStatus: MockApplicationStatus!
    var sut : UserPropertyRequestStrategy!
    
    override func setUp() {
        super.setUp()
        
        self.syncMOC.performGroupedAndWait { moc in
            self.applicationStatus = MockApplicationStatus()
            self.applicationStatus.mockSynchronizationState = .eventProcessing
            self.sut = UserPropertyRequestStrategy(withManagedObjectContext: moc, applicationStatus: self.applicationStatus)
        }
    }
    
    override func tearDown() {
        sut = nil
        applicationStatus = nil
        
        super.tearDown()
    }
    
    func testThatItGeneratesARequestWhenSettingIsModified() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let selfUser = ZMUser.selfUser(in: moc)
            selfUser.needsToBeUpdatedFromBackend = false
            selfUser.readReceiptsEnabled = true
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: selfUser)) })
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNotNil(request)
        }
    }
    
    func testThatItUpdatesPropertyFromUpdateEvent() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let selfUser = ZMUser.selfUser(in: moc)
            selfUser.needsPropertiesUpdate = false
            
            let updateEvent = ZMUpdateEvent(fromEventStreamPayload: ([
                "type": "user.properties-set",
                "key": "WIRE_RECEIPT_MODE",
                "value": 1] as ZMTransportData), uuid: nil)!
            
            // when
            self.sut.processEvents([updateEvent], liveEvents: true, prefetchResult: nil)
            
            // then
            XCTAssertTrue(selfUser.readReceiptsEnabled)
            XCTAssertTrue(selfUser.readReceiptsEnabledChangedRemotely)
        }
    }
    
    func testThatItUpdatesPropertyFromUpdateEvent_false() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let selfUser = ZMUser.selfUser(in: moc)
            selfUser.needsPropertiesUpdate = false
            selfUser.readReceiptsEnabled = true
            
            let updateEvent = ZMUpdateEvent(fromEventStreamPayload: ([
                "type": "user.properties-set",
                "key": "WIRE_RECEIPT_MODE",
                "value": 0] as ZMTransportData), uuid: nil)!
            
            // when
            self.sut.processEvents([updateEvent], liveEvents: true, prefetchResult: nil)
            
            // then
            XCTAssertFalse(selfUser.readReceiptsEnabled)
            XCTAssertTrue(selfUser.readReceiptsEnabledChangedRemotely)
        }
    }
    
    func testThatItUpdatesPropertyFromUpdateEvent_delete() {
        self.syncMOC.performGroupedAndWait { moc in
            
            // given
            let selfUser = ZMUser.selfUser(in: moc)
            selfUser.needsPropertiesUpdate = false
            selfUser.readReceiptsEnabled = true
            
            let updateEvent = ZMUpdateEvent(fromEventStreamPayload: ([
                "type": "user.properties-delete",
                "key": "WIRE_RECEIPT_MODE"] as ZMTransportData), uuid: nil)!
                
            // when
            self.sut.processEvents([updateEvent], liveEvents: true, prefetchResult: nil)
            
            // then
            XCTAssertFalse(selfUser.readReceiptsEnabled)
            XCTAssertTrue(selfUser.readReceiptsEnabledChangedRemotely)
        }
    }
}

// MARK: - Downstream sync
extension UserPropertyRequestStrategyTests {
    func testThatItIsFetchingPropertyValue() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let selfUser = ZMUser.selfUser(in: moc)
            
            // when
            let request = self.sut.nextRequestIfAllowed()
            
            XCTAssertNotNil(request)
            XCTAssertEqual(request!.method, .methodGET)
            XCTAssertEqual(request!.path, "properties/WIRE_RECEIPT_MODE")
            
            let response = ZMTransportResponse(payload: "1" as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            
            self.sut.didReceive(response, forSingleRequest: self.sut.downstreamSync)
            
            // then
            XCTAssertFalse(selfUser.needsPropertiesUpdate)
            XCTAssertTrue(selfUser.readReceiptsEnabled)
            XCTAssertFalse(selfUser.readReceiptsEnabledChangedRemotely)
        }
    }
    
    func testThatItIsFetchingPropertyValue_404() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let selfUser = ZMUser.selfUser(in: moc)
            
            // when
            let request = self.sut.nextRequestIfAllowed()
            
            XCTAssertNotNil(request)
            XCTAssertEqual(request!.method, .methodGET)
            XCTAssertEqual(request!.path, "properties/WIRE_RECEIPT_MODE")
            
            let response = ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)
            
            self.sut.didReceive(response, forSingleRequest: self.sut.downstreamSync)
            
            // then
            XCTAssertFalse(selfUser.needsPropertiesUpdate)
            XCTAssertFalse(selfUser.readReceiptsEnabled)
            XCTAssertFalse(selfUser.readReceiptsEnabledChangedRemotely)
        }
    }
}
