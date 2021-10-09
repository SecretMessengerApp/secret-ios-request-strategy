//
//


import Foundation


@objc public protocol ClientRegistrationDelegate : NSObjectProtocol  {

    /// Returns true if the client is registered
    var clientIsReadyForRequests : Bool { get }
    
    /// Notify that the current client was deleted remotely
    func didDetectCurrentClientDeletion()

}


@objc public protocol DeliveryConfirmationDelegate : NSObjectProtocol {
    /// If set to false, no delivery receipts are sent
    static var sendDeliveryReceipts : Bool { get }
    
    /// If set to true, we need to send delivery receipts
    var needsToSyncMessages : Bool { get }
    
    /// Adds the messageNonce to a collection of messages to be synced and starts a background activity for sending the request
    func needsToConfirmMessage(_ messageNonce: UUID)
    
    /// Removes the messageNonce from a collection of messages to be synced and ends the background activity for sending the request
    func didConfirmMessage(_ messageNonce: UUID)
}


