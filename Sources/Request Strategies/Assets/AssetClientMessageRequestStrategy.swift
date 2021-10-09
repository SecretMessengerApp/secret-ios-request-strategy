//
//


import Foundation

/// The `AssetClientMessageRequestStrategy` for creating requests to insert the genericMessage of a `ZMAssetClientMessage`
/// remotely. This is only necessary for the `/assets/v3' endpoint as we upload the asset, receive the asset ID in the response,
/// manually add it to the genericMessage and send it using the `/otr/messages` endpoint like any other message.
/// This is an additional step required as the fan-out was previously done by the backend when uploading a v2 asset.
/// There are mutliple occasions where we might want to send the genericMessage of a `ZMAssetClientMessage` again:
///
/// * We just inserted the message and want to upload the `Asset.Original` containing the metadata about the asset.
/// * (Optional) If the asset has data that can be used to show a preview of it, we want to upload the `Asset.Preview` as soon as the preview data has been preprocessed and uploaded using the `/assets/v3` endpoint.
/// * When the actual asset data has been preprocessed (encrypted) and uploaded we want to insert the `Asset.Uploaded` message.
/// * If we fail to upload the preview or uploaded message we will upload an `Asset.NOTUploaded` genericMessage.
public final class AssetClientMessageRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource {

    fileprivate let requestFactory = ClientMessageRequestFactory()
    fileprivate var upstreamSync: ZMUpstreamModifiedObjectSync! // TODO jacob this can be a insertion sync now

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus?) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        configuration = [.allowsRequestsDuringEventProcessing,  .allowsRequestsWhileInBackground,
            .allowsRequestsDuringNotificationStreamFetch,
            .allowsRequestsDuringSync]

        upstreamSync = ZMUpstreamModifiedObjectSync(
            transcoder: self,
            entityName: ZMAssetClientMessage.entityName(),
            update: AssetClientMessageRequestStrategy.updatePredicate,
            filter: AssetClientMessageRequestStrategy.updateFilter,
            keysToSync: [#keyPath(ZMAssetClientMessage.transferState)],
            managedObjectContext: managedObjectContext
        )
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return upstreamSync.nextRequest()
    }

    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [upstreamSync]
    }
    
    static var updatePredicate: NSPredicate {
        return NSPredicate(format: "delivered == NO && isExpired == NO && version == 3 && transferState == \(AssetTransferState.uploaded.rawValue)")
    }
    
    static var updateFilter: NSPredicate {
        return NSPredicate { object, _ in
            guard let message = object as? ZMMessage, let sender = message.sender  else { return false }
                        
            return sender.isSelfUser
        }
    }

}


// MARK: - ZMUpstreamTranscoder


extension AssetClientMessageRequestStrategy: ZMUpstreamTranscoder {

    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil
    }

    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        // no-op
    }

    public func dependentObjectNeedingUpdate(beforeProcessingObject dependant: ZMManagedObject) -> Any? {
        return (dependant as? ZMMessage)?.dependentObjectNeedingUpdateBeforeProcessing
    }

    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard
            let message = managedObject as? ZMAssetClientMessage,
            let conversation = message.conversation,
            let cid = conversation.remoteIdentifier else { return nil }
        
        if message.conversation?.conversationType == .oneOnOne {
            // Update expectsReadReceipt flag to reflect the current user setting
            if let updatedGenericMessage = message.genericMessage?.setExpectsReadConfirmation(ZMUser.selfUser(in: managedObjectContext).readReceiptsEnabled) {
                message.add(updatedGenericMessage)
            }
        }

        
//        if let legalHoldStatus = message.conversation?.legalHoldStatus {
//            if let updatedGenericMessage = message.genericMessage?.setLegalHoldStatus(legalHoldStatus.denotesEnabledComplianceDevice ? .ENABLED : .DISABLED) {
//                message.add(updatedGenericMessage)
//            }
//        }
        
        let req = conversation.conversationType == .hugeGroup
            ? requestFactory.upstreamRequestForUnencryptedClientMessage(message, forConversationWithId: cid)
            : requestFactory.upstreamRequestForMessage(message, forConversationWithId: cid)
        
        guard let request = req else { fatal("Unable to generate request for \(message.description)") }
        
        requireInternal(true == message.sender?.isSelfUser, "Trying to send message from sender other than self: \(message.nonce?.uuidString ?? "nil nonce")")
        
        // We need to flush the encrypted payloads cache, since the client is online now (request succeeded).
        let completionHandler = ZMCompletionHandler(on: self.managedObjectContext) { response in
            guard let selfClient = ZMUser.selfUser(in: self.managedObjectContext).selfClient(),
                response.result == .success else {
                return
            }
            selfClient.keysStore.encryptionContext.perform { (session) in
                session.purgeEncryptedPayloadCache()
            }
        }
        request.add(completionHandler)
        
        return ZMUpstreamRequest(keys: [#keyPath(ZMAssetClientMessage.transferState)], transportRequest: request)
    }

    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable : Any]? = nil, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard let message = managedObject as? ZMAssetClientMessage else { return false }
        
        message.update(withPostPayload: response.payload?.asDictionary() ?? [:], updatedKeys: keysToParse)
        if let delegate = applicationStatus?.clientRegistrationDelegate{
            _ = message.parseUploadResponse(response, clientRegistrationDelegate: delegate)
        }

        if response.result == .success {
            message.markAsSent()
        }
     
        if let payload = response.payload?.asDictionary(),
            let code = payload["code"] as? Int,
            [1015,1014].contains(code) {
            message.removeClearingSender(true)
        }
        return false
    }

    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }

    public func shouldRetryToSyncAfterFailed(toUpdate managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse, keysToParse keys: Set<String>) -> Bool {
        guard let message = managedObject as? ZMAssetClientMessage else { return false }
        var failedBecauseOfMissingClients = false
        if let delegate = applicationStatus?.clientRegistrationDelegate {
            failedBecauseOfMissingClients = message.parseUploadResponse(response, clientRegistrationDelegate: delegate).contains(.missing)
        }
        
        if !failedBecauseOfMissingClients {
            message.expire()
        }

        return failedBecauseOfMissingClients
    }
    
}
