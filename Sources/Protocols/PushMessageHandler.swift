//

import Foundation
import WireDataModel

@objc public protocol PushMessageHandler: NSObjectProtocol {
    
    /// Create a notification for the message if needed
    ///
    /// - Parameter genericMessage: generic message that was received
    @objc(processGenericMessage:)
    func process(_ genericMessage: ZMGenericMessage)
    
    
    /// Creates a notification for the message if needed
    ///
    /// - Parameter message: message that was received
    @objc(processMessage:)
    func process(_ message: ZMMessage)
    
    
    /// Shows a notification for a failure to send
    ///
    /// - Parameter message: message that failed to send
    func didFailToSend(_ message: ZMMessage)
}
