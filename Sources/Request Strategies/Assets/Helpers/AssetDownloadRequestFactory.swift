// 


import Foundation
import WireTransport

public final class AssetDownloadRequestFactory: NSObject {

    public func requestToGetAsset(withKey key: String, token: String?) -> ZMTransportRequest? {
        let path = "/assets/v3/\(key)"
        let request = ZMTransportRequest.assetGet(fromPath: path, assetToken: token)
        request?.forceToBackgroundSession()
        return request
    }

}
