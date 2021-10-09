// 

import Foundation

public final class AssetRequestFactory : NSObject {
    
    public enum Retention : String {
        /// The asset will be automatically removed from the backend
        /// storage after a short-ish amount of time.
        case volatile = "volatile"
        
        /// The asset will be automatically removed from the backend storage
        /// after a certain, long-ish amount of time.
        case expiring = "expiring"
        
       
        case persistent = "persistent"
        /// The asset will never be removed from the backend storage unless the
        /// user requests the deletion explicitly. Used for profile pictures.
        case eternal = "eternal"
        
        /// The same as eternal, however this is cost-optimized
        /// on the backend for infrequent access. Used for team conversations.
        case eternalInfrequentAccess = "eternal-infrequent_access"
    }
    
    private enum Constant {
        static let path = "/assets/v3"
        static let md5 = "Content-MD5"
        static let accessLevel = "public"
        static let retention = "retention"
        static let boundary = "frontier"
        
        enum ContentType {
            static let json = "application/json"
            static let octetStream = "application/octet-stream"
            static let multipart = "multipart/mixed; boundary=frontier"
        }
    }

    public func backgroundUpstreamRequestForAsset(message: ZMAssetClientMessage, withData data: Data, shareable: Bool = true, retention: Retention) -> ZMTransportRequest? {
        guard let uploadURL = uploadURL(for: message, in: message.managedObjectContext!, shareable: shareable, retention: retention, data: data) else { return nil }
        let request = ZMTransportRequest.uploadRequest(withFileURL: uploadURL, path: Constant.path, contentType: Constant.ContentType.multipart)
        request.addContentDebugInformation("Uploading full asset to /assets/v3")
        return request
    }

    public func upstreamRequestForAsset(withData data: Data, shareable: Bool = true, retention: Retention) -> ZMTransportRequest? {
        guard let multipartData = try? dataForMultipartAssetUploadRequest(data, shareable: shareable, retention: retention) else { return nil }
        return ZMTransportRequest(path: Constant.path, method: .methodPOST, binaryData: multipartData, type: Constant.ContentType.multipart, contentDisposition: nil)
    }

    func dataForMultipartAssetUploadRequest(_ data: Data, shareable: Bool, retention : Retention) throws -> Data {
        let fileDataHeader = [Constant.md5: (data as NSData).zmMD5Digest().base64String()]
        let metaData = try JSONSerialization.data(withJSONObject: [Constant.accessLevel: shareable, Constant.retention: retention.rawValue], options: [])

        return NSData.multipartData(withItems: [
            ZMMultipartBodyItem(data: metaData, contentType: Constant.ContentType.json, headers: nil),
            ZMMultipartBodyItem(data: data, contentType: Constant.ContentType.octetStream, headers: fileDataHeader),
            ], boundary: Constant.boundary)
    }

    private func uploadURL(for message: ZMAssetClientMessage, in moc: NSManagedObjectContext, shareable: Bool, retention: Retention, data: Data) -> URL? {
        guard let multipartData = try? dataForMultipartAssetUploadRequest(data, shareable: shareable, retention: retention) else { return nil }
        return moc.zm_fileAssetCache.storeRequestData(message, data: multipartData)
    }
    
}

public extension AssetRequestFactory.Retention {
    init(conversation: ZMConversation) {
        if ZMUser.selfUser(in: conversation.managedObjectContext!).hasTeam || conversation.hasTeam || conversation.containsTeamUser {
            self = .eternalInfrequentAccess
        } else {
            self = .expiring
        }
    }
}

extension ZMConversation {
    var containsTeamUser: Bool {
        //return lastServerSyncedActiveParticipants.any { ($0 as? ZMUser)?.hasTeam == true }
        return false
    }
    
    var hasTeam: Bool {
        return nil != team
    }
}
