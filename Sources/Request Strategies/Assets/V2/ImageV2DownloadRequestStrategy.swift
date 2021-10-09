//
//

import Foundation

public final class ImageV2DownloadRequestStrategy : AbstractRequestStrategy {
    
    fileprivate var downstreamSync : ZMDownstreamObjectSyncWithWhitelist!
    fileprivate let requestFactory : ClientMessageRequestFactory = ClientMessageRequestFactory()
    private var token: Any? = nil

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus?) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        let downloadPredicate = NSPredicate { (object, _) -> Bool in
            guard let message = object as? ZMAssetClientMessage else { return false }
            guard message.version < 3 else { return false }
            
            let missingMediumImage = message.imageMessageData != nil && !message.hasDownloadedFile && message.assetId != nil
            let missingVideoThumbnail = message.fileMessageData != nil && !message.hasDownloadedPreview && message.fileMessageData?.thumbnailAssetID != nil
            
            return (missingMediumImage || missingVideoThumbnail) && message.hasEncryptedAsset
        }
        
        downstreamSync = ZMDownstreamObjectSyncWithWhitelist(transcoder: self,
                                                             entityName: ZMAssetClientMessage.entityName(),
                                                             predicateForObjectsToDownload: downloadPredicate,
                                                             managedObjectContext: managedObjectContext)

        registerForWhitelistingNotification()
    }
    
    func registerForWhitelistingNotification() {
        self.token = NotificationInContext.addObserver(name: ZMAssetClientMessage.imageDownloadNotificationName,
                                          context: self.managedObjectContext.notificationContext,
                                          object: nil)
        { [weak self] note in
            guard let objectID = note.object as? NSManagedObjectID else { return }
            self?.didRequestToDownloadImage(objectID)
        }
    }
    
    func didRequestToDownloadImage(_ objectID: NSManagedObjectID) {
        managedObjectContext.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            guard let object = try? self.managedObjectContext.existingObject(with: objectID) else { return }
            guard let message = object as? ZMAssetClientMessage else { return }
            self.downstreamSync.whiteListObject(message)
            RequestAvailableNotification.notifyNewRequestsAvailable(self)
        }
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return downstreamSync.nextRequest()
    }

}

extension ImageV2DownloadRequestStrategy : ZMDownstreamTranscoder {
    
    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let message = object as? ZMAssetClientMessage, let conversation = message.conversation else { return nil }
        
        if let existingData = managedObjectContext.zm_fileAssetCache.assetData(message, format: .medium, encrypted: false) {
            updateMediumImage(forMessage: message, imageData: existingData)
            managedObjectContext.enqueueDelayedSave()
            return nil
        } else {
            if message.imageMessageData != nil {
                guard let assetId = message.assetId?.transportString() else { return nil }
                return requestFactory.requestToGetAsset(assetId, inConversation: conversation.remoteIdentifier!)
            } else if (message.fileMessageData != nil) {
                guard let assetId = message.fileMessageData?.thumbnailAssetID else { return nil }
                return requestFactory.requestToGetAsset(assetId, inConversation: conversation.remoteIdentifier!)
            }
        }
        
        return nil
    }
    
    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard let message = object as? ZMAssetClientMessage else { return }
        updateMediumImage(forMessage: message, imageData: response.rawData!)
    }
    
    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard let message = object as? ZMAssetClientMessage else { return }
        message.managedObjectContext?.delete(message)
    }
    
    fileprivate func updateMediumImage(forMessage message: ZMAssetClientMessage, imageData: Data) {
        storeMediumImage(forMessage: message, imageData: imageData)
        
        guard let uiMOC = managedObjectContext.zm_userInterface else { return }
        NotificationDispatcher.notifyNonCoreDataChanges(objectID: message.objectID,
                                                        changedKeys: [#keyPath(ZMAssetClientMessage.hasDownloadedFile)],
                                                        uiContext: uiMOC)
    }
    
    fileprivate func storeMediumImage(forMessage message: ZMAssetClientMessage, imageData: Data) {
        managedObjectContext.zm_fileAssetCache.storeAssetData(message,
                                                              format: .medium,
                                                              encrypted: message.hasEncryptedAsset,
                                                              data: imageData)
        if message.hasEncryptedAsset {
            let otrKey: Data?
            let sha256: Data?
            
            if message.fileMessageData != nil {
                let remote = message.genericAssetMessage?.assetData?.preview.remote
                otrKey = remote?.otrKey
                sha256 = remote?.sha256
            } else if message.imageMessageData != nil {
                let imageAsset = message.mediumGenericMessage?.imageAssetData
                otrKey = imageAsset?.otrKey
                sha256 = imageAsset?.sha256
            } else {
                otrKey = nil
                sha256 = nil
            }
            
            var decrypted = false
            if let otrKey = otrKey, let sha256 = sha256 {
                decrypted = managedObjectContext.zm_fileAssetCache.decryptImageIfItMatchesDigest(message,
                                                                                                 format: .medium,
                                                                                                 encryptionKey: otrKey,
                                                                                                 sha256Digest: sha256)
            }
            
            if !decrypted && message.imageMessageData != nil {
                managedObjectContext.delete(message)
            }
        }
    }
    
}
