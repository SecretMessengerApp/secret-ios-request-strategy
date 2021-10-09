//

private let zmLog = ZMSLog(tag: "link previews")

public final class LinkPreviewUploadRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource {

    fileprivate let requestFactory = ClientMessageRequestFactory()

    /// Upstream sync
    fileprivate var upstreamSync: ZMUpstreamModifiedObjectSync!

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus?) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        self.configuration =  [
            .allowsRequestsDuringSync,
            .allowsRequestsDuringEventProcessing,
            .allowsRequestsWhileInBackground,
            .allowsRequestsDuringNotificationStreamFetch
        ]

        upstreamSync = ZMUpstreamModifiedObjectSync(
            transcoder: self,
            entityName: ZMClientMessage.entityName(),
            update: LinkPreviewUploadRequestStrategy.updatePredicate,
            filter: LinkPreviewUploadRequestStrategy.updateFilter,
            keysToSync: [ZMClientMessageLinkPreviewStateKey],
            managedObjectContext: managedObjectContext
        )
    }
    
    static var updatePredicate: NSPredicate {
        return NSPredicate(format: "%K == %d", #keyPath(ZMClientMessage.linkPreviewState), ZMLinkPreviewState.uploaded.rawValue)
    }
    
    static var updateFilter: NSPredicate {
        return NSPredicate { object, _ in
            guard let message = object as? ZMMessage, let sender = message.sender  else { return false }
            
            return sender.isSelfUser
        }
    }

    public var contextChangeTrackers : [ZMContextChangeTracker] {
        return [upstreamSync]
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return upstreamSync.nextRequest()
    }

}


// MAR: - ZMUpstreamTranscoder


extension LinkPreviewUploadRequestStrategy : ZMUpstreamTranscoder {

    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard let message = managedObject as? ZMClientMessage else { return nil }
        guard keys.contains(ZMClientMessageLinkPreviewStateKey) else { return nil }
        requireInternal(true == message.sender?.isSelfUser, "Trying to send message from sender other than self: \(message.nonce?.uuidString ?? "nil nonce")")
        let request = requestFactory.upstreamRequestForMessage(message)
        zmLog.debug("request to send: \(message.nonce?.uuidString ?? "nil"), linkPreview: \(String(describing: message.genericMessage))")
        return ZMUpstreamRequest(keys: [ZMClientMessageLinkPreviewStateKey], transportRequest: request)
    }
    
    public func dependentObjectNeedingUpdate(beforeProcessingObject dependant: ZMManagedObject) -> Any? {
        guard
            let message = dependant as? ZMClientMessage,
            !dependant.isZombieObject,
            message.conversation?.conversationType != ZMConversationType.hugeGroup
            else {
            return nil
        }
        return message.dependentObjectNeedingUpdateBeforeProcessing
    }

    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil
    }

    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }

    public func shouldRetryToSyncAfterFailed(toUpdate managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse, keysToParse keys: Set<String>) -> Bool {
        guard let message = managedObject as? ZMClientMessage else { return false }
        return message.parseUploadResponse(response, clientRegistrationDelegate: applicationStatus!.clientRegistrationDelegate).contains(.missing)
    }

    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }

    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable: Any]?, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard keysToParse.contains(ZMClientMessageLinkPreviewStateKey) else { return false }
        guard let message = managedObject as? ZMClientMessage else { return false }

        // We do not update the message with the response to avoid updating the timestamp.
        message.linkPreviewState = .done
        return false
    }

    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        // nop
    }
    
}
