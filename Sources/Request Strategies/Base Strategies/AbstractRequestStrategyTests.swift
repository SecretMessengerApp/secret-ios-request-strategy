//
//

import Foundation
import XCTest

@testable import WireRequestStrategy


protocol TestableAbstractRequestStrategy : class {
    
    var mutableConfiguration : ZMStrategyConfigurationOption { get set }
    
}


class TestRequestStrategyObjc : ZMAbstractRequestStrategy, TestableAbstractRequestStrategy {
    
    internal var mutableConfiguration: ZMStrategyConfigurationOption = []

    override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return ZMTransportRequest(getFromPath: "dummy/request")
    }
    
    override var configuration: ZMStrategyConfigurationOption {
        get {
            return mutableConfiguration
        }
    }
    
}


class TestRequestStrategy : AbstractRequestStrategy, TestableAbstractRequestStrategy {
    
    internal var mutableConfiguration: ZMStrategyConfigurationOption = []
    
    override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return ZMTransportRequest(getFromPath: "dummy/request")
    }
    
    override var configuration: ZMStrategyConfigurationOption {
        get {
            return mutableConfiguration
        }
        set {
            mutableConfiguration = configuration
        }
    }
    
}


class AbstractRequestStrategyTests : MessagingTestBase {
    
    let mockApplicationStatus = MockApplicationStatus()
    
    func checkAllPermutations(on sut : RequestStrategy & TestableAbstractRequestStrategy) {
        
        assertPass(withConfiguration: [.allowsRequestsDuringEventProcessing], operationState: .foreground, synchronizationState: .eventProcessing, sut: sut)
        assertPass(withConfiguration: [.allowsRequestsDuringSync], operationState: .foreground, synchronizationState: .synchronizing, sut: sut)
        assertPass(withConfiguration: [.allowsRequestsWhileUnauthenticated], operationState: .foreground, synchronizationState: .unauthenticated, sut: sut)
        
        assertFail(withConfiguration: [.allowsRequestsDuringEventProcessing], operationState: .foreground, synchronizationState: .synchronizing, sut: sut)
        assertFail(withConfiguration: [.allowsRequestsDuringEventProcessing], operationState: .foreground, synchronizationState: .unauthenticated, sut: sut)
        
        assertFail(withConfiguration: [.allowsRequestsDuringSync], operationState: .foreground, synchronizationState: .eventProcessing, sut: sut)
        assertFail(withConfiguration: [.allowsRequestsDuringSync], operationState: .foreground, synchronizationState: .unauthenticated, sut: sut)
        
        assertFail(withConfiguration: [.allowsRequestsWhileUnauthenticated], operationState: .foreground, synchronizationState: .eventProcessing, sut: sut)
        assertFail(withConfiguration: [.allowsRequestsWhileUnauthenticated], operationState: .foreground, synchronizationState: .synchronizing, sut: sut)
        
        assertPass(withConfiguration: [.allowsRequestsDuringEventProcessing, .allowsRequestsWhileInBackground], operationState: .background, synchronizationState: .eventProcessing, sut: sut)
        assertPass(withConfiguration: [.allowsRequestsDuringSync, .allowsRequestsWhileInBackground], operationState: .background, synchronizationState: .synchronizing, sut: sut)
        assertPass(withConfiguration: [.allowsRequestsWhileUnauthenticated, .allowsRequestsWhileInBackground], operationState: .background, synchronizationState: .unauthenticated, sut: sut)
    }
    
    func assertPass(withConfiguration configuration: ZMStrategyConfigurationOption, operationState: OperationState, synchronizationState: SynchronizationState, sut: RequestStrategy & TestableAbstractRequestStrategy) {
        
        // given
        sut.mutableConfiguration = configuration
        mockApplicationStatus.mockOperationState = operationState
        mockApplicationStatus.mockSynchronizationState = synchronizationState
        
        // then
        XCTAssertNotNil(sut.nextRequest(), "expected \(configuration) to pass")
    }
    
    func assertFail(withConfiguration configuration: ZMStrategyConfigurationOption, operationState: OperationState, synchronizationState: SynchronizationState, sut: RequestStrategy & TestableAbstractRequestStrategy) {
        
        // given
        sut.mutableConfiguration = configuration
        mockApplicationStatus.mockOperationState = operationState
        mockApplicationStatus.mockSynchronizationState = synchronizationState
        
        // then
        XCTAssertNil(sut.nextRequest(), "expected \(configuration) to fail")
    }
    
    func testAbstractRequestStrategy() {
        checkAllPermutations(on: TestRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: mockApplicationStatus))
    }
    
    func testAbstractRequestStrategyObjC() {
        checkAllPermutations(on: TestRequestStrategyObjc(managedObjectContext: syncMOC, applicationStatus: mockApplicationStatus))
    }
    
}
