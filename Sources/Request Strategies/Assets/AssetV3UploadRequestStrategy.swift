//

import Foundation

/// AssetV3UploadRequestStrategy is responsible for uploading all the assets associated with a asset message
/// after they've been preprocessed (downscaled & encrypted). After all the assets have been uploaded
/// transfer state is changed to .uploaded which is the signal that the asset message is ready to be sent.
public final class AssetV3UploadRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource {
    
    internal let requestFactory = AssetRequestFactory()
    internal var upstreamSync: ZMUpstreamModifiedObjectSync!
    internal var preprocessor: AssetsPreprocessor
    
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus?) {
        preprocessor = AssetsPreprocessor(managedObjectContext: managedObjectContext)
        
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        configuration = [.allowsRequestsDuringEventProcessing,
                         .allowsRequestsDuringSync,
                         .allowsRequestsWhileInBackground,
                         .allowsRequestsDuringNotificationStreamFetch]
        
        upstreamSync = ZMUpstreamModifiedObjectSync(
            transcoder: self,
            entityName: ZMAssetClientMessage.entityName(),
            update: AssetV3UploadRequestStrategy.updatePredicate,
            filter: AssetV3UploadRequestStrategy.filterPredicate,
            keysToSync: [#keyPath(ZMAssetClientMessage.transferState)],
            managedObjectContext: managedObjectContext
        )
    }
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [preprocessor, upstreamSync, self]
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return upstreamSync.nextRequest()
    }
    
    private static var updatePredicate: NSPredicate {
        return NSPredicate(format: "version == 3 && delivered == NO && transferState == \(AssetTransferState.uploading.rawValue)")
    }
    
    private static var filterPredicate: NSPredicate {
        return NSPredicate(format: "processingState == \(AssetProcessingState.uploading.rawValue)")
    }
}


extension AssetV3UploadRequestStrategy: ZMContextChangeTracker {
    
    // we need to cancel the requests manually as the upstream modified object sync
    // will not pick up a change to keys which are already being synchronized (transferState)
    // WHEN the user cancels a file upload
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        let assetClientMessages = object.compactMap { object -> ZMAssetClientMessage? in
            guard let message = object as? ZMAssetClientMessage,
                message.version == 3,
                message.transferState == .uploadingCancelled
                else { return nil }
            return message
        }
        
        assetClientMessages.forEach(cancelOutstandingUploadRequests)
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        return nil
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        // no op
    }
    
    fileprivate func cancelOutstandingUploadRequests(forMessage message: ZMAssetClientMessage) {
        guard let identifier = message.associatedTaskIdentifier else { return }
        applicationStatus?.requestCancellation.cancelTask(with: identifier)
        message.associatedTaskIdentifier = nil
    }
    
}


extension AssetV3UploadRequestStrategy: ZMUpstreamTranscoder {
    
    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil // no-op
    }
    
    public func dependentObjectNeedingUpdate(beforeProcessingObject dependant: ZMManagedObject) -> Any? {
        return (dependant as? ZMMessage)?.dependentObjectNeedingUpdateBeforeProcessing
    }
    
    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        // no-op
    }
    
    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard let message = managedObject as? AssetMessage else { fatal("Could not cast to ZMAssetClientMessage, it is \(type(of: managedObject)))") }
        guard let asset = message.assets.first(where: { !$0.isUploaded} ) else { return nil } // TODO jacob are we sure we only have one upload per message active?
        
        return requestForUploadingAsset(asset, for: managedObject as! ZMAssetClientMessage)
    }
    
    private func requestForUploadingAsset(_ asset: Asset, for message: ZMAssetClientMessage) -> ZMUpstreamRequest {
        guard let data = asset.encrypted else { fatal("Encrypted data not available") }
        guard let retention = message.conversation.map(AssetRequestFactory.Retention.init) else { fatal("Trying to send message that doesn't have a conversation") }
        guard let request = requestFactory.backgroundUpstreamRequestForAsset(message: message, withData: data, shareable: false, retention: retention) else { fatal("Could not create asset request") }
        
        request.add(ZMTaskCreatedHandler(on: managedObjectContext) { identifier in
            message.associatedTaskIdentifier = identifier
        })
        request.add(ZMTaskProgressHandler(on: self.managedObjectContext) { progress in
            message.progress = progress
            self.managedObjectContext.enqueueDelayedSave()
        })
        
        return ZMUpstreamRequest(keys: [#keyPath(ZMAssetClientMessage.transferState)], transportRequest: request)
    }
    
    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable : Any]? = nil, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        
        guard response.result == .success else { return false }
        guard let message = managedObject as? ZMAssetClientMessage else { return false }
        guard let asset = message.assets.first(where: { !$0.isUploaded}) else {return false }
        guard let payload = response.payload?.asDictionary(),
              let assetId = payload["key"] as? String else {
            fatal("No asset ID present in payload")
        }
        
        let token = payload["token"] as? String
        
        asset.updateWithAssetId(assetId, token: token)
        
        if message.processingState == .done {
            message.updateTransferState(.uploaded, synchronize: true)
        }
        
        return true // We always need to make one more request to send OTR message in the conversation
    }
    
    public func shouldRetryToSyncAfterFailed(toUpdate managedObject: ZMManagedObject,
                                             request upstreamRequest: ZMUpstreamRequest,
                                             response: ZMTransportResponse,
                                             keysToParse keys: Set<String>)-> Bool {
        guard let message = managedObject as? ZMAssetClientMessage else { return false }
        
        message.expire()
        
        return false
    }
    
    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
    
}
