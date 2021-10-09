//
//

import Foundation

@objc public protocol BackgroundNotificationFetchStatusProvider {
    var status: BackgroundNotificationFetchStatus { get }
}

@objc public enum BackgroundNotificationFetchStatus: UInt8 {
    case done, inProgress
}

@objc(ZMSynchronizationState)
public enum SynchronizationState : UInt {
    case unauthenticated
    case synchronizing
    case eventProcessing
}

@objc(ZMOperationState)
public enum OperationState : UInt {
    case background
    case foreground
}

@objc(ZMApplicationStatus)
public protocol ApplicationStatus : class {
    var synchronizationState : SynchronizationState { get }
    var operationState : OperationState { get }
    
    var clientRegistrationDelegate : ClientRegistrationDelegate { get }
    var requestCancellation : ZMRequestCancellation { get }
    var deliveryConfirmation : DeliveryConfirmationDelegate { get }

    var notificationFetchStatus: BackgroundNotificationFetchStatus { get }
    
    var notificationHugeFetchStatus: BackgroundNotificationFetchStatus { get }
    
    func requestSlowSync()

}
