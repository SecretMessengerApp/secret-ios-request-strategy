//

import Foundation
import WireDataModel

fileprivate let zmLog = ZMSLog(tag: "Network")

/// Creates network requests to send client messages,
/// and parses received client messages
public class ClientMessageTranscoder: AbstractRequestStrategy {

    
    fileprivate let requestFactory: ClientMessageRequestFactory
    private(set) fileprivate var upstreamObjectSync: ZMUpstreamInsertedObjectSync!
    fileprivate let messageExpirationTimer: MessageExpirationTimer
    fileprivate let linkAttachmentsPreprocessor: LinkAttachmentsPreprocessor
    fileprivate weak var localNotificationDispatcher: PushMessageHandler?
    
    public init(in moc:NSManagedObjectContext,
         localNotificationDispatcher: PushMessageHandler?,
         applicationStatus: ApplicationStatus?)
    {
        self.localNotificationDispatcher = localNotificationDispatcher
        self.requestFactory = ClientMessageRequestFactory()
        self.messageExpirationTimer = MessageExpirationTimer(moc: moc, entityNames: [ZMClientMessage.entityName(), ZMAssetClientMessage.entityName()], localNotificationDispatcher: localNotificationDispatcher)
        self.linkAttachmentsPreprocessor = LinkAttachmentsPreprocessor(linkAttachmentDetector: LinkAttachmentDetectorHelper.defaultDetector(), managedObjectContext: moc)
        
        super.init(withManagedObjectContext: moc, applicationStatus: applicationStatus)
        
        self.configuration =
            [.allowsRequestsDuringSync,
             .allowsRequestsDuringEventProcessing,.allowsRequestsWhileInBackground,
                    .allowsRequestsDuringNotificationStreamFetch]
        self.upstreamObjectSync = ZMUpstreamInsertedObjectSync(transcoder: self, entityName: ZMClientMessage.entityName(), filter: ClientMessageTranscoder.insertFilter, managedObjectContext: moc)
        if moc.zm_isSyncContext {
            self.deleteOldEphemeralMessages()
        }
    }
    
    deinit {
        self.messageExpirationTimer.tearDown()
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return self.upstreamObjectSync.nextRequest()
    }
    
    static var insertFilter: NSPredicate {
        return NSPredicate { object, _ in
            if object is ZMSystemMessage {
                return false
            }
            if  let message = object as? ZMMessage,
                let sender = message.sender,
                sender.isSelfUser,
                message.delivered == false,
                message.isExpired == false
                {
                return true
            }
            return false
        }
    }
}

extension ClientMessageTranscoder: ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self.upstreamObjectSync, self.messageExpirationTimer, self.linkAttachmentsPreprocessor]
    }
}

extension ClientMessageTranscoder: ZMUpstreamTranscoder {
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
    
    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        return nil
    }
    
    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        
        guard
            let message = managedObject as? ZMClientMessage,
            let conversation = message.conversation,
            let cid = conversation.remoteIdentifier,
            !message.isExpired else {
                zmLog.info("Cannot create request: message = \(managedObject) message.isExpired = \((managedObject as? ZMClientMessage)?.isExpired ?? false)")
                return nil
        }
        
        requireInternal(true == message.sender?.isSelfUser, "Trying to send message from sender other than self: \(message.nonce?.uuidString ?? "nil nonce")")

        if message.conversation?.conversationType == .oneOnOne {
            // Update expectsReadReceipt flag to reflect the current user setting
            if let updatedGenericMessage = message.genericMessage?.setExpectsReadConfirmation(ZMUser.selfUser(in: managedObjectContext).readReceiptsEnabled) {
                message.add(updatedGenericMessage.data())
            }
        }

       
//        if let legalHoldStatus = message.conversation?.legalHoldStatus {
//            // Update the legalHoldStatus flag to reflect the current known legal hold status
//            if let updatedGenericMessage = message.genericMessage?.setLegalHoldStatus(legalHoldStatus.denotesEnabledComplianceDevice ? .ENABLED : .DISABLED) {
//                message.add(updatedGenericMessage.data())
//            }
//        }

        let request = conversation.conversationType == .hugeGroup
            ? requestFactory.upstreamRequestForUnencryptedClientMessage(message, forConversationWithId: cid)!
            : requestFactory.upstreamRequestForMessage(message, forConversationWithId: cid)!
        
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

        self.messageExpirationTimer.stop(for: message)
        if let expiration = message.expirationDate {
            request.expire(at: expiration)
        }
        return ZMUpstreamRequest(keys: keys, transportRequest: request)
    }
    
    public func requestExpired(for managedObject: ZMManagedObject, forKeys keys: Set<String>) {
        guard let message = managedObject as? ZMOTRMessage else { return }
        message.expire()
        self.localNotificationDispatcher?.didFailToSend(message)
    }
    
    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        guard let message = managedObject as? ZMOTRMessage else { return nil }
        return message.conversation
    }
}

extension ClientMessageTranscoder {

    public var hasPendingMessages: Bool {
        return self.messageExpirationTimer.hasMessageTimersRunning || self.upstreamObjectSync.hasCurrentlyRunningRequests
    }
    
    func insertMessage(from event: ZMUpdateEvent, prefetchResult: ZMFetchRequestBatchResult?) {
        switch event.type {
        case .conversationClientMessageAdd,
             .conversationOtrMessageAdd,
             .conversationOtrAssetAdd,
             .conversationServiceMessageAdd,
             .conversationJsonMessageAdd,
             .conversationMemberJoinask,
             .conversationBgpMessageAdd:
            
            // process generic message first, b/c if there is no updateResult, then
            // a the event from a deleted message wouldn't delete the notification.
            if event.source == .pushNotification || event.source == .webSocket {
                if let genericMessage = ZMGenericMessage(from: event) {
                    self.localNotificationDispatcher?.process(genericMessage)
                }
            }
            
            guard let message = ZMOTRMessage.createOrUpdate(from: event, in: managedObjectContext, prefetchResult: prefetchResult) else { return }
            
            message.markAsSent()
            
            if event.source == .pushNotification || event.source == .webSocket {
                self.localNotificationDispatcher?.process(message)
            }
            
        default:
            break
        }
        
        managedObjectContext.processPendingChanges()
    }
    
    fileprivate func deleteOldEphemeralMessages() {
        self.managedObjectContext.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            ZMMessage.deleteOldEphemeralMessages(self.managedObjectContext)
            self.managedObjectContext.saveOrRollback()
        }
    }

    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        
        guard let message = managedObject as? ZMClientMessage,
            !managedObject.isZombieObject,
            let genericMessage = message.genericMessage else {
                return
        }

        self.update(message, from: response, keys: upstreamRequest.keys ?? Set())
        _ = message.parseMissingClientsResponse(response, clientRegistrationDelegate: self.applicationStatus!.clientRegistrationDelegate)
        
        if genericMessage.hasReaction() {
            message.managedObjectContext?.delete(message)
        }
        if genericMessage.hasConfirmation() {
            self.applicationStatus?.deliveryConfirmation.didConfirmMessage(message.nonce!)
            message.managedObjectContext?.delete(message)
        }
    }
    
    private func update(_ message: ZMClientMessage, from response: ZMTransportResponse, keys: Set<String>) {
        guard !message.isZombieObject else {
            return
        }
        
        self.messageExpirationTimer.stop(for: message)
        message.markAsSent()
        
        if let payload = response.payload?.asDictionary(),
            let code = payload["code"] as? Int,
            [1015,1014].contains(code) {
            message.removeClearingSender(true)
            return
        }
        
        if let payload = response.payload?.asDictionary(),
            let code = payload["code"] as? Int,
            code == 1016 {
            if !(message.conversation?.blocked ?? true) {
                message.conversation?.blocked = true
            }
            message.removeClearingSender(true)
            return
        }
        if let jsonText = message.jsonTextMessageData?.jsonMessageText,
            let jsonData = jsonText.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: jsonData, options: JSONSerialization.ReadingOptions.allowFragments) as? Dictionary<String, Any> {
            if let type = dict["msgType"] as? String, type == "23",
                let msgData = dict["msgData"] as? Dictionary<String, String>,
                let bid = msgData["fromUserId"],
                let biduuid = UUID(uuidString: bid) {
                message.sender = ZMUser(remoteID: biduuid, createIfNeeded: false, in: self.managedObjectContext)
            }
        }
        
        message.update(withPostPayload: response.payload?.asDictionary() ?? [:], updatedKeys: keys)
        _ = message.parseMissingClientsResponse(response, clientRegistrationDelegate: self.applicationStatus!.clientRegistrationDelegate)

    }

    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable : Any]? = nil, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard let message = managedObject as? ZMClientMessage,
            !managedObject.isZombieObject else {
                return false
        }
        self.update(message, from: response, keys: keysToParse)
        _ = message.parseMissingClientsResponse(response, clientRegistrationDelegate: self.applicationStatus!.clientRegistrationDelegate)
        return false
    }

    public func shouldRetryToSyncAfterFailed(toUpdate managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse, keysToParse keys: Set<String>) -> Bool {
        guard let message = managedObject as? ZMOTRMessage,
            !managedObject.isZombieObject else {
                return false
        }
        return message.parseMissingClientsResponse(response, clientRegistrationDelegate: self.applicationStatus!.clientRegistrationDelegate)
    }
    
    public func shouldCreateRequest(toSyncObject managedObject: ZMManagedObject, forKeys keys: Set<String>, withSync sync: Any) -> Bool {
        guard
            let message = managedObject as? ZMClientMessage,
            !managedObject.isZombieObject,
            let genericMessage = message.genericMessage else {
            return false
        }
        if message.conversation?.conversationType == .hugeGroup {
            return true
        }
        if genericMessage.hasConfirmation() == true {
            let messageNonce = UUID(uuidString: genericMessage.confirmation.firstMessageId)
            let sentMessage = ZMMessage.fetch(withNonce: messageNonce, for: message.conversation!, in: message.managedObjectContext!)
            return (sentMessage?.sender != nil)
                || (message.conversation?.connectedUser != nil)
                || (message.conversation?.lastServerSyncedActiveParticipants.count > 0)
        }
        return true
    }
    
    public func dependentObjectNeedingUpdate(beforeProcessingObject dependant: ZMManagedObject) -> Any? {
        guard
            let message = dependant as? ZMClientMessage,
            !dependant.isZombieObject,
            message.conversation?.conversationType != ZMConversationType.hugeGroup else {
            return nil
        }
        
        return message.dependentObjectNeedingUpdateBeforeProcessing
    }
}

// MARK: - Update events
extension ClientMessageTranscoder : ZMEventConsumer {
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        events.forEach { _ = self.insertMessage(from: $0, prefetchResult: prefetchResult) }
    }    
    
    public func messageNoncesToPrefetch(toProcessEvents events: [ZMUpdateEvent]) -> Set<UUID> {
        return Set(events.compactMap {
            switch $0.type {
            case .conversationClientMessageAdd,
                 .conversationOtrMessageAdd,
                 .conversationOtrAssetAdd,
                 .conversationBgpMessageAdd:
                return $0.messageNonce()
            default:
                return nil
            }
        })
    }
    
    private func nonces(for updateEvents: [ZMUpdateEvent]) -> [UpdateEventWithNonce] {
        return updateEvents.compactMap {
            switch $0.type {
            case .conversationClientMessageAdd,
                 .conversationOtrMessageAdd,
                 .conversationOtrAssetAdd,
                 .conversationBgpMessageAdd:
                if let nonce = $0.messageNonce() {
                    return UpdateEventWithNonce(event: $0, nonce: nonce)
                }
                return nil
            default:
                return nil
            }
        }
    }
}

// MARK: - Helpers
private struct UpdateEventWithNonce {
    let event: ZMUpdateEvent
    let nonce: UUID
}
