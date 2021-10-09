////

import Foundation
import WireDataModel

fileprivate let zmLog = ZMSLog(tag: "rich-profile")

public class UserRichProfileRequestStrategy : AbstractRequestStrategy {
    
    var modifiedSync: ZMDownstreamObjectSync!
    
    override public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus?) {
        
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        self.modifiedSync = ZMDownstreamObjectSync(transcoder: self,
                                                         entityName: ZMUser.entityName(),
                                                         predicateForObjectsToDownload: ZMUser.predicateForUsersToUpdateRichProfile(),
                                                         managedObjectContext: managedObjectContext)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return modifiedSync.nextRequest()
    }
}

extension UserRichProfileRequestStrategy : ZMDownstreamTranscoder {
    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let user = object as? ZMUser else { fatal("Object \(object.classForCoder) is not ZMUser") }
        guard let remoteIdentifier = user.remoteIdentifier else { fatal("User does not have remote identifier") }
        let path = "/users/\(remoteIdentifier)/rich-info"
        return ZMTransportRequest(path: path, method: .methodGET, payload: nil)
    }
    
    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard let user = object as? ZMUser else { fatal("Object \(object.classForCoder) is not ZMUser") }
        user.needsRichProfileUpdate = false
    }
    
    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        struct Response: Decodable {
            struct Field: Decodable {
                var type: String
                var value: String
            }
            var fields: [Field]
        }
        
        guard let user = object as? ZMUser else { fatal("Object \(object.classForCoder) is not ZMUser") }
        guard let data = response.rawData else { zmLog.error("Response has no rawData"); return }
        do {
            let values = try JSONDecoder().decode(Response.self, from: data)
            user.richProfile = values.fields.map { UserRichProfileField(type: $0.type, value: $0.value) }
        } catch {
            zmLog.error("Failed to decode response: \(error)"); return
        }
        user.needsRichProfileUpdate = false
    }
}

extension UserRichProfileRequestStrategy : ZMContextChangeTrackerSource {
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [modifiedSync]
    }
}
