//


import Foundation
import WireTransport
import WireImages
import WireDataModel

private let zmLog = ZMSLog(tag: "Network")

public final class ClientMessageRequestFactory: NSObject {
    
    let protobufContentType = "application/x-protobuf"
    let octetStreamContentType = "application/octet-stream"
    
    public func upstreamRequestForFetchingClients(conversationId: UUID, selfClient: UserClient) -> ZMTransportRequest? {
        let originalPath = "/" + ["conversations", conversationId.transportString(), "otr", "messages"].joined(separator: "/")
        let newOtrMessage = ZMNewOtrMessage.message(withSender: selfClient, nativePush: false, recipients: [])
        let path = originalPath.pathWithMissingClientStrategy(strategy: .doNotIgnoreAnyMissingClient)
        let request = ZMTransportRequest(path: path, method: .methodPOST, binaryData: newOtrMessage.data(), type: protobufContentType, contentDisposition: nil)
        return request
    }

    public func upstreamRequestForMessage(_ message: ZMClientMessage) -> ZMTransportRequest? {
        guard
            let conversation = message.conversation,
            let cid = conversation.remoteIdentifier else { return nil }
        return conversation.conversationType == .hugeGroup
            ? upstreamRequestForUnencryptedClientMessage(message, forConversationWithId: cid)
            : upstreamRequestForEncryptedClientMessage(message, forConversationWithId: cid)
    }

    public func upstreamRequestForMessage(_ message: EncryptedPayloadGenerator, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {
        return upstreamRequestForEncryptedClientMessage(message, forConversationWithId: conversationId);
    }
    
    fileprivate func upstreamRequestForEncryptedClientMessage(_ message: EncryptedPayloadGenerator, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {
        let originalPath = "/" + ["conversations", conversationId.transportString(), "otr", "messages"].joined(separator: "/")
        guard let dataAndMissingClientStrategy = message.encryptedMessagePayloadData() else {
            return nil
        }
        let path = originalPath.pathWithMissingClientStrategy(strategy: dataAndMissingClientStrategy.strategy)
        let request = ZMTransportRequest(path: path, method: .methodPOST, binaryData: dataAndMissingClientStrategy.data, type: protobufContentType, contentDisposition: nil)
        request.addContentDebugInformation(message.debugInfo)
        request.priorityLevel = .highLevel
        return request
    }

    public func upstreamRequestForUnencryptedClientMessage(_ message: UnencryptedMessagePayloadGenerator, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {
        let originalPath =  "/" + ["conversations", conversationId.transportString(), "bgp", "messages"].joined(separator: "/")
        guard let payload = message.unencryptedMessagePayload() else {
            return nil
        }
        let path = originalPath.pathWithMissingClientStrategy(strategy: .doNotIgnoreAnyMissingClient)
        let request = ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
        request.addContentDebugInformation(message.unencryptedMessageDebugInfo)
        request.priorityLevel = .highLevel
        return request
    }
    
    public func requestToGetAsset(_ assetId: String, inConversation conversationId: UUID) -> ZMTransportRequest {
        let path = "/" + ["conversations", conversationId.transportString(), "otr", "assets", assetId].joined(separator: "/")
        let request = ZMTransportRequest.imageGet(fromPath: path)
        request.forceToBackgroundSession()
        request.priorityLevel = .lowLevel
        return request
    }
    
}

// MARK: - Downloading
extension ClientMessageRequestFactory {
    func downstreamRequestForEcryptedOriginalFileMessage(_ message: ZMAssetClientMessage) -> ZMTransportRequest? {
        guard let conversation = message.conversation, let identifier = conversation.remoteIdentifier else { return nil }
        let path = "/conversations/\(identifier.transportString())/otr/assets/\(message.assetId!.transportString())"
        
        let request = ZMTransportRequest(getFromPath: path)
        request.addContentDebugInformation("Downloading file (Asset)\n\(String(describing: message.dataSetDebugInformation))")
        request.forceToBackgroundSession()
        request.priorityLevel = .lowLevel
        return request
    }
}

// MARK: - Testing Helper
extension ZMClientMessage {
    public var encryptedMessagePayloadDataOnly : Data? {
        return self.encryptedMessagePayloadData()?.data
    }
}


extension String {

    func pathWithMissingClientStrategy(strategy: MissingClientsStrategy) -> String {
        switch strategy {
        case .doNotIgnoreAnyMissingClient:
            return self
        case .ignoreAllMissingClients:
            return self + "?ignore_missing"
        case .ignoreAllMissingClientsNotFromUsers(let users):
            let userIDs = users.compactMap { $0.remoteIdentifier?.transportString() }
            return self + "?report_missing=\(userIDs.joined(separator: ","))"
        case .ignoreAllMissingClientsFromUsers(let users):
        let userIDs = users.compactMap { $0.remoteIdentifier?.transportString() }
        return self + "?ignore_missing=\(userIDs.joined(separator: ","))"
        }
    }
}
