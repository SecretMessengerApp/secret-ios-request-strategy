////

import XCTest
@testable import WireRequestStrategy

class UserRichProfileRequestStrategyTests: MessagingTestBase {

    var applicationStatus: MockApplicationStatus!
    var sut : UserRichProfileRequestStrategy!
    
    override func setUp() {
        super.setUp()
        
        self.syncMOC.performGroupedAndWait { moc in
            self.applicationStatus = MockApplicationStatus()
            self.applicationStatus.mockSynchronizationState = .eventProcessing
            self.sut = UserRichProfileRequestStrategy(withManagedObjectContext: moc, applicationStatus: self.applicationStatus)
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
            let userID = UUID()
            let user = ZMUser(remoteID: userID, createIfNeeded: true, in: self.syncMOC)!
            user.needsRichProfileUpdate = true
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: user)) })
            
            // when
            guard let request = self.sut.nextRequest() else { XCTFail(); return }
            
            // then
            XCTAssertEqual(request.path, "/users/\(userID)/rich-info")
            XCTAssertEqual(request.method, .methodGET)
        }
    }
    
    func testThatItParsesAResponse() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let userID = UUID()
            let user = ZMUser(remoteID: userID, createIfNeeded: true, in: self.syncMOC)!
            user.needsRichProfileUpdate = true
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: user)) })
            let request = self.sut.nextRequest()
            XCTAssertNotNil(request)
            
            // when
            let type = "some"
            let value = "value"
            let payload = [
                "fields" : [
                    ["type" : type, "value" : value]
                ]
            ]
            let response = ZMTransportResponse(payload: payload as NSDictionary as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            self.sut.update(user, with: response, downstreamSync: nil)
            
            // then
            XCTAssertFalse(user.needsRichProfileUpdate)
            XCTAssertEqual(user.richProfile, [UserRichProfileField(type: type, value: value)])
        }
    }
    
    func testThatItResetsTheFlagOnError() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let userID = UUID()
            let user = ZMUser(remoteID: userID, createIfNeeded: true, in: self.syncMOC)!
            user.needsRichProfileUpdate = true
            self.sut.contextChangeTrackers.forEach({ $0.addTrackedObjects(Set<NSManagedObject>(arrayLiteral: user)) })
            let request = self.sut.nextRequest()
            XCTAssertNotNil(request)
            
            // when
            let response = ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)
            self.sut.delete(user, with: response, downstreamSync: nil)
            
            // then
            XCTAssertFalse(user.needsRichProfileUpdate)
        }
    }

}
