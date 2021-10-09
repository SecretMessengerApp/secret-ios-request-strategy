//
//

import Foundation
import WireDataModel

public final class MissingClientsRequestFactory {
    
    let pageSize : Int
    public init(pageSize: Int = 128) {
        self.pageSize = pageSize
    }
    
    public func fetchMissingClientKeysRequest(_ missingClients: Set<UserClient>) -> ZMUpstreamRequest! {
        let map = MissingClientsMap(Array(missingClients), pageSize: pageSize)
        let request = ZMTransportRequest(path: "/users/prekeys", method: ZMTransportRequestMethod.methodPOST, payload: map.payload as ZMTransportData?)
        return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientMissingKey), transportRequest: request, userInfo: map.userInfo)
    }
    
}

public func identity<T>(value: T) -> T {
    return value
}

public struct MissingClientsMap {
    
    /// The mapping from user-id's to an array of missing clients for that user `{ <user-id>: [<client-id>] }`
    let payload: [String: [String]]
    /// The `MissingClientsRequestUserInfoKeys.clients` key holds all missing clients
    let userInfo: [String: [String]]
    
    public init(_ missingClients: [UserClient], pageSize: Int) {
        
        let addClientIdToMap = { (clientsMap: [String : Set<String>], missingClient: UserClient) -> [String: Set<String>] in
            var clientsMap = clientsMap
            let missingUserId = missingClient.user!.remoteIdentifier!.transportString()
            var clientSet = clientsMap[missingUserId] ?? Set<String>()
            clientSet.insert(missingClient.remoteIdentifier!)
            clientsMap[missingUserId] = clientSet
            return clientsMap
        }
        
        var users = Set<ZMUser>()
        let missing = missingClients.filter {
            guard let user = $0.user,
                let _ = user.remoteIdentifier else { return false }
            users.insert(user)
            return users.count <= pageSize
        }
        
        let setPayload = missing.reduce([String: Set<String>](), addClientIdToMap)
        
        payload = setPayload.mapKeysAndValues(keysMapping: identity, valueMapping: { return Array($1) })
        userInfo = [MissingClientsRequestUserInfoKeys.clients: missing.map { $0.remoteIdentifier! }]
    }
}
