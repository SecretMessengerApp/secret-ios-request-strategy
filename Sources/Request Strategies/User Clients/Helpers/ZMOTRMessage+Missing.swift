//


import Foundation
import WireDataModel

@objc public protocol SelfClientDeletionDelegate {
    
    /// Invoked when the self client needs to be deleted
    func deleteSelfClient()
}


/// MARK: - Missing and deleted clients
public extension ZMOTRMessage {

    @objc func parseMissingClientsResponse(_ response: ZMTransportResponse, clientRegistrationDelegate: ClientRegistrationDelegate) -> Bool {
        return self.parseUploadResponse(response, clientRegistrationDelegate: clientRegistrationDelegate).contains(.missing)
    }

}
