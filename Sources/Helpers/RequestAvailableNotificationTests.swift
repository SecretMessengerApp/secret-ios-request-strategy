//
//

import XCTest
@testable import WireRequestStrategy


@objc class NotificationObserver : NSObject, RequestAvailableObserver {
    
    var requestsAvailable = false
    
    func newRequestsAvailable() {
        requestsAvailable = true
    }
    
}

class RequestAvailableNotificationTests: XCTestCase {
    
    var sut = NotificationObserver()
    
    override func setUp() {
        super.setUp()
        
        sut = NotificationObserver()
    }
    
    override func tearDown() {
        RequestAvailableNotification.removeObserver(sut)
        
        super.tearDown()
    }
    
    func testObserverIsReceivingNotificationsAfterSubscribing() {
        
        // given
        RequestAvailableNotification.addObserver(sut)
        
        // when
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
        
        // then 
        XCTAssertTrue(sut.requestsAvailable)
    }
    
    func testObserverIsNotReceivingNotificationsAfterUnsubscribing() {
        
        // given
        RequestAvailableNotification.addObserver(sut)
        RequestAvailableNotification.removeObserver(sut)
        
        // when
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
        
        // then
        XCTAssertFalse(sut.requestsAvailable)
    }
    
}
