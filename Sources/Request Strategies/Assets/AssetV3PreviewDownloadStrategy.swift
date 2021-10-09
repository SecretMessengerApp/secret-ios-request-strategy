//
//


import WireImages
import WireTransport

private let zmLog = ZMSLog(tag: "AssetPreviewDownloading")


@objcMembers public final class AssetV3PreviewDownloadRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource {

    fileprivate var downstreamSync: ZMDownstreamObjectSyncWithWhitelist!
    private var token: Any? = nil
    
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus?) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)

        let filter = NSPredicate { object, _ in
            guard let message = object as? ZMAssetClientMessage, nil != message.fileMessageData else { return false }
            guard message.version == 3, message.visibleInConversation != nil else { return false }
            guard nil != message.genericAssetMessage?.previewAssetId else { return false }
            return !message.hasDownloadedPreview
        }

        downstreamSync = ZMDownstreamObjectSyncWithWhitelist(
            transcoder: self,
            entityName: ZMAssetClientMessage.entityName(),
            predicateForObjectsToDownload: filter,
            managedObjectContext: managedObjectContext
        )
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

    fileprivate func handleResponse(_ response: ZMTransportResponse, forMessage assetClientMessage: ZMAssetClientMessage) {
        guard let asset = assetClientMessage.genericAssetMessage?.assetData, response.result == .success else { return }
        guard let remote = asset.preview.remote, assetClientMessage.visibleInConversation != nil else { return }

        let cache = managedObjectContext.zm_fileAssetCache
        cache.storeAssetData(assetClientMessage, format: .medium, encrypted: true, data: response.rawData!)

        // Decrypt the preview image file
        let success = cache.decryptImageIfItMatchesDigest(
            assetClientMessage,
            format: .medium,
            encryptionKey: remote.otrKey,
            sha256Digest: remote.sha256
        )

        if !success {
            zmLog.error("Unable to decrypt preview image for file message: \(assetClientMessage), \(asset)")
        }

        // Notify about the changes
        guard let uiMOC = managedObjectContext.zm_userInterface else { return }
        NotificationDispatcher.notifyNonCoreDataChanges(objectID: assetClientMessage.objectID,
                                                        changedKeys: [#keyPath(ZMAssetClientMessage.hasDownloadedPreview)],
                                                        uiContext: uiMOC)
    }

    // MARK: - ZMContextChangeTrackerSource

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [downstreamSync]
    }

}

// MARK: - ZMDownstreamTranscoder

extension AssetV3PreviewDownloadRequestStrategy: ZMDownstreamTranscoder {

    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        if let assetClientMessage = object as? ZMAssetClientMessage,
            let asset = assetClientMessage.genericAssetMessage?.assetData,
            let remote = asset.preview.remote,
            assetClientMessage.version == 3 {

            let token = remote.hasAssetToken() ? remote.assetToken : nil
            if let request = AssetDownloadRequestFactory().requestToGetAsset(withKey: remote.assetId, token: token) {
                request.add(ZMCompletionHandler(on: self.managedObjectContext) { response in
                    self.handleResponse(response, forMessage: assetClientMessage)
                })
                return request
            }
        }

        fatal("Cannot generate request to download v3 file preview for \(object.safeForLoggingDescription)")
    }

    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // no-op
    }

    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // no-op
    }

}
