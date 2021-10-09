//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//


import Foundation

extension ZMAssetClientMessage {

    static var v3_imageUploadPredicate: NSPredicate {
        return NSPredicate(
            format: "version == 3 && %K != %d && %K == %d",
            #keyPath(ZMAssetClientMessage.uploadState), AssetUploadState.done.rawValue,
            #keyPath(ZMAssetClientMessage.transferState), ZMFileTransferState.uploading.rawValue
        )
    }

    static var v3_imageProcessingFilter: NSPredicate {
        return NSPredicate { (object, _) in
            guard let message = object as? ZMAssetClientMessage, !message.delivered, message.version == 3 else { return false }
            return message.v3_isReadyToProcessImage
                || message.v3_isReadyToProcessThumbnail
        }
    }

    var v3_isReadyToProcessImage: Bool {
        guard let asset = genericAssetMessage?.assetData else { return false }
        return asset.original.hasImage()
            && asset.original.image.width == 0
    }

    var v3_isReadyToProcessThumbnail: Bool {
        guard let asset = genericAssetMessage?.assetData, let fileData = fileMessageData else { return false }
        return !asset.original.hasImage()
            && !asset.hasPreview()
            && fileData.previewData != nil
    }

    static var v3_imageUploadFilter: NSPredicate {
        return NSPredicate(format: "v3_isReadyToUploadImageData == YES OR v3_isReadyToUploadThumbnailData == YES")
    }

    /// We want to upload file messages that represent an image where the transfer state is `.uploading`and only if we are not done uploading.
    /// We also want to wait for the preprocessing of the file data (encryption) to finish (thus the check for an existing otrKey).
    /// We also need to ensure this file message actually represents an image and that the image preprocessing finished.
    var v3_isReadyToUploadImageData: Bool {
        guard let assetData = genericAssetMessage?.assetData else { return false }
        return fileMessageData != nil
            && transferState == .uploading
            && uploadState != .done
            && assetData.hasUploaded()
            && !assetData.uploaded.hasAssetId()
            && assetData.uploaded.otrKey.count > 0
            && assetData.original.hasImage()
            && assetData.original.image.width > 0
    }

    /// We want to upload file messages that DO NOT represent an image but have a preview image associated with them. 
    /// The transfer state is `.uploading` and the uploadState is `.uploadingThumbnail`.
    /// We also want to wait for the preprocessing of the image preview data (encryption) to finish (thus the check for an existing preview otrKey).
    /// When the preprocessing is finished the message will have a preview generic message set (and an otrKey and image metadata).
    var v3_isReadyToUploadThumbnailData: Bool {
        guard let assetData = genericAssetMessage?.assetData, !assetData.original.hasImage() else { return false }
        return fileMessageData != nil
            && transferState == .uploading
            && uploadState == .uploadingThumbnail
            && assetData.hasPreview()
            && !assetData.preview.remote.hasAssetId()
            && assetData.preview.remote.otrKey.count > 0
            && assetData.preview.hasImage()
            && assetData.preview.image.width > 0
    }

}

/// This strategy is used to upload images to the `/assets/v3` endpoint.
/// It uploads images for (v3) `ZMAssetClientMessage` that represent an image and
/// for those that represent any other file but have a preview / thumbnail image.
/// Images are stored in the ImageAsset cache to ensure they are not discarded to fast when the
/// user also downloaded a lot of files.
/// After the image has been uploaded either the `Asset.Uploaded` generic message (in case of images), or the
/// `Asset.Preview` generic message will be updated and the state of the message updated accordingly.
public final class AssetV3ImageUploadRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource {

    fileprivate let zmLog = ZMSLog(tag: "Asset V3")
    
    fileprivate let preprocessor: ZMImagePreprocessingTracker
    fileprivate let requestFactory = AssetRequestFactory()
    fileprivate var upstreamSync: ZMUpstreamModifiedObjectSync!

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        preprocessor = ZMImagePreprocessingTracker(
            managedObjectContext: managedObjectContext,
            imageProcessingQueue: OperationQueue(),
            fetch: NSPredicate(format: "delivered == NO && version == 3"),
            needsProcessingPredicate: ZMAssetClientMessage.v3_imageProcessingFilter,
            entityClass: ZMAssetClientMessage.self
        )

        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        configuration = [.allowsRequestsDuringEventProcessing]

        upstreamSync = ZMUpstreamModifiedObjectSync(
            transcoder: self,
            entityName: ZMAssetClientMessage.entityName(),
            update: ZMAssetClientMessage.v3_imageUploadPredicate,
            filter: ZMAssetClientMessage.v3_imageUploadFilter,
            keysToSync: [#keyPath(ZMAssetClientMessage.uploadState)],
            managedObjectContext: managedObjectContext
        )
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [preprocessor, upstreamSync, self]
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return upstreamSync.nextRequest()
    }
}

extension AssetV3ImageUploadRequestStrategy: ZMContextChangeTracker {

    // we need to cancel the requests manually as the upstream modified object sync
    // will not pick up a change to keys which are already being synchronized (uploadState)
    // WHEN the user cancels a file upload
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        let assetClientMessages = object.compactMap { object -> ZMAssetClientMessage? in
            guard let message = object as? ZMAssetClientMessage,
                message.version == 3,
                message.genericAssetMessage?.assetData?.hasPreview() == true,
                nil != message.fileMessageData && message.transferState == .cancelledUpload
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
    }
    
}


extension AssetV3ImageUploadRequestStrategy: ZMUpstreamTranscoder {

    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil // no-op
    }

    public func dependentObjectNeedingUpdate(beforeProcessingObject dependant: ZMManagedObject) -> Any? {
        return (dependant as? ZMMessage)?.dependentObjectNeedingUpdateBeforeProcessing
    }

    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        // no-op
    }

    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable : Any]? = nil, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard let message = managedObject as? ZMAssetClientMessage, let genericMessage = message.genericAssetMessage, let asset = genericMessage.assetData else { return false }
        guard let payload = response.payload?.asDictionary(), let assetId = payload["key"] as? String else { fatal("No asset ID present in payload") }

        let token: String? = payload["token"] as? String

        // We either uploaded the full asset if this file is an image, or we uploaded the preview image in case this
        // file does not represent an image but has a thumbnail image. We need to make sure that we update the correct
        // generic message (Asset.Uploaded in case of an image and Asset.Preview in case of a file with preview).an
        if let updated = genericMessage.updatedUploaded(withAssetId: assetId, token: token),
            asset.original.hasImage(),
            message.uploadState == .uploadingFullAsset {

            // The AssetClientMessageTranscoder will send the genericMessage as soon as there is an
            // asset ID, and will mark this message as sent afterwards.
            message.add(updated)
            managedObjectContext.zm_fileAssetCache.deleteAssetData(message, format: .medium, encrypted: true)
            managedObjectContext.zm_fileAssetCache.deleteRequestData(message)
            // We need more requests to actually upload the message data (see AssetClientMessageRequestStrategy)
            return true
        } else if let updated = genericMessage.updatedPreview(withAssetId: assetId, token: token),
            message.uploadState == .uploadingThumbnail,
            !asset.original.hasImage(),
            asset.preview.hasImage() {

            // The AssetClientMessageTranscoder will send the genericMessage as soon as there is an
            // preview asset ID, afterwards the full asset will be uploaded.
            message.add(updated)
            managedObjectContext.zm_fileAssetCache.deleteAssetData(message, format: .medium, encrypted: true)
            managedObjectContext.zm_fileAssetCache.deleteRequestData(message)
            // We need more requests to actually upload the message data (see AssetClientMessageRequestStrategy)
            return true
        }

        return false
    }

    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard let message = managedObject as? ZMAssetClientMessage else { fatal("Could not cast to ZMAssetClientMessage, it is \(type(of: managedObject)))") }
        let imageFormat: ZMImageFormat = message.isUploadOriginalImage ? .original : .medium
        guard let data = managedObjectContext.zm_fileAssetCache.assetData(message, format: imageFormat, encrypted: true) else { fatal("Could not find image in cache") }
        guard let retention = message.conversation.map(AssetRequestFactory.Retention.init) else { fatal("Trying to send message that doesn't have a conversation") }
        guard let request = requestFactory.upstreamRequestForAsset(withData: data, shareable: false, retention: retention) else { fatal("Could not create asset request") }
        
        if message.uploadState == .uploadingThumbnail {
            request.add(ZMCompletionHandler(on: managedObjectContext) { [weak request, weak self] response in
                message.associatedTaskIdentifier = nil
                if response.result == .expired || response.result == .temporaryError || response.result == .tryAgainLater {
                    self?.failUpload(of: message, keys: [#keyPath(ZMAssetClientMessage.uploadState)], request: request)
                }
            })
            
            request.add(ZMTaskCreatedHandler(on: managedObjectContext) { identifier in
                message.associatedTaskIdentifier = identifier
            })
        }
        
        if message.uploadState == .uploadingFullAsset {
            request.add(ZMTaskProgressHandler(on: self.managedObjectContext) { progress in
                message.setExpirationDate()
            })
            
            request.add(ZMCompletionHandler(on: managedObjectContext) { response in
                message.associatedTaskIdentifier = nil
                if response.result == .success {
                    message.removeExpirationDate()
                }
            })
        }
        
        return ZMUpstreamRequest(keys: [#keyPath(ZMAssetClientMessage.uploadState)], transportRequest: request)
    }

    public func shouldCreateRequest(toSyncObject managedObject: ZMManagedObject, forKeys keys: Set<String>, withSync sync: Any) -> Bool {
        guard let message = managedObject as? ZMAssetClientMessage else { return false }
        let imageFormat: ZMImageFormat = message.isUploadOriginalImage ? .original : .medium
        guard managedObjectContext.zm_fileAssetCache.hasDataOnDisk(message, format: imageFormat, encrypted: true) else {
            // if the asset data is missing, we should delete the message
            managedObjectContext.delete(message)
            managedObjectContext.enqueueDelayedSave()
            zmLog.warn("Asset data is missing from image cache. Message nonce: \(message.nonce!)")
            return false
        }
        
        let imageAssetStorage = message.imageAssetStorage
        if imageAssetStorage.shouldReprocess(for: imageFormat) && true == message.fileMessageData?.v3_isImage {
            // before we create an upstream request we should check if we can (and should) process image data again
            // if we can we reschedule processing, this might cause a loop if the message can not be processed whatsoever
            scheduleImageProcessing(forMessage: message, format: .original)
            managedObjectContext.saveOrRollback()
            return false
        }

        return true
    }

    public func shouldRetryToSyncAfterFailed(toUpdate managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse, keysToParse keys: Set<String>) -> Bool {
        guard let message = managedObject as? ZMAssetClientMessage else { return false }
        if message.uploadState == .uploadingThumbnail {
            failUpload(of: message, keys: keys, request: upstreamRequest.transportRequest)
            return true
        } else {
            message.uploadState = .uploadingFailed
            return false
        }
    }

    private func failUpload(of message: ZMAssetClientMessage, keys: Set<String>, request: ZMTransportRequest?) {
        if message.transferState != .cancelledUpload {
            message.transferState = .failedUpload
            message.expire()
        }

        guard keys.contains(#keyPath(ZMAssetClientMessage.uploadState)) else { return }
        message.didFailToUploadFileData()
        managedObjectContext.zm_fileAssetCache.deleteRequestData(message)
        message.uploadState = .uploadingFailed
    }

    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }

    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }

    func scheduleImageProcessing(forMessage message: ZMAssetClientMessage, format: ZMImageFormat) {
        let genericMessage = ZMGenericMessage.message(content: ZMAsset.asset(originalWithImageSize: .zero,
                                                                             mimeType: "",
                                                                             size: message.size),
                                                      nonce: message.nonce!,
                                                      expiresAfter: message.deletionTimeout)
        message.add(genericMessage)
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }

}
