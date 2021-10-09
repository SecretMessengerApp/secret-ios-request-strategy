//
//

import Foundation

@objcMembers public class GenericMessageEntity : NSObject, OTREntity {

    public var message : ZMGenericMessage
    public var conversation : ZMConversation?
    public var completionHandler : ((_ response: ZMTransportResponse) -> Void)?
    public var isExpired: Bool = false
    
    init(conversation: ZMConversation, message: ZMGenericMessage, completionHandler: ((_ response: ZMTransportResponse) -> Void)?) {
        self.conversation = conversation
        self.message = message
        self.completionHandler = completionHandler
    }
    
    public var context: NSManagedObjectContext {
        return conversation!.managedObjectContext!
    }
    
    public var dependentObjectNeedingUpdateBeforeProcessing: NSObject? {
        guard let conversation  = conversation else { return nil }
        
        return self.dependentObjectNeedingUpdateBeforeProcessingOTREntity(in: conversation)
    }
    
    public func missesRecipients(_ recipients: Set<UserClient>!) {
        // no-op
    }
    
    public func detectedRedundantClients() {
        // if the BE tells us that these users are not in the
        // conversation anymore, it means that we are out of sync
        // with the list of participants
        conversation?.needsToBeUpdatedFromBackend = true
    }
    
    public func detectedMissingClient(for user: ZMUser) {
        conversation?.addParticipantIfMissing(user, date: nil)
    }
    
    public func expire() {
        isExpired = true
    }
    
    public override var hash: Int {
        return self.message.hashValue
    }
}

public func ==(lhs: GenericMessageEntity, rhs: GenericMessageEntity) -> Bool {
    return lhs === rhs
}

extension GenericMessageEntity : EncryptedPayloadGenerator {
    
    public func encryptedMessagePayloadData() -> (data: Data, strategy: MissingClientsStrategy)? {
        return message.encryptedMessagePayloadData(conversation!, externalData: nil)
    }
    
    public var debugInfo: String {
        if message.hasCalling() {
            return "Calling Message"
        } else if message.hasClientAction() {
            switch message.clientAction {
            case .RESETSESSION: return "Reset Session Message"
            @unknown default:
                return "unknown Message"
            }
        }

        return "\(self)"
    }
    
}

/// This should not be used as a standalone strategy but either subclassed or used within another
/// strategy. Please have a look at `CallingRequestStrategy` and `GenericMessageNotificationRequestStrategy`
/// before modifying the behaviour of this class.
@objcMembers public class GenericMessageRequestStrategy : OTREntityTranscoder<GenericMessageEntity>, ZMRequestGenerator, ZMContextChangeTracker {
    
    private var sync : DependencyEntitySync<GenericMessageRequestStrategy>?
    private var requestFactory = ClientMessageRequestFactory()
    
    public override init(context: NSManagedObjectContext, clientRegistrationDelegate: ClientRegistrationDelegate) {
        super.init(context: context, clientRegistrationDelegate: clientRegistrationDelegate)
        
        sync = DependencyEntitySync(transcoder: self, context: context)
    }
    
    public func schedule(message: ZMGenericMessage, inConversation conversation: ZMConversation, completionHandler: ((_ response: ZMTransportResponse) -> Void)?) {
        sync?.synchronize(entity: GenericMessageEntity(conversation: conversation, message: message, completionHandler: completionHandler))
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
    public func expireEntities(withDependency dependency: AnyObject) {
        guard let dependency = dependency as? NSManagedObject else { return }
        sync?.expireEntities(withDependency: dependency)
    }
    
    public override func request(forEntity entity: GenericMessageEntity) -> ZMTransportRequest? {
        return requestFactory.upstreamRequestForMessage(entity, forConversationWithId: entity.conversation!.remoteIdentifier!)
    }
    
    public override func shouldTryToResend(entity: GenericMessageEntity, afterFailureWithResponse response: ZMTransportResponse) -> Bool {
        entity.completionHandler?(response)
        return super.shouldTryToResend(entity: entity, afterFailureWithResponse: response)
    }
    
    public override func request(forEntity entity: GenericMessageEntity, didCompleteWithResponse response: ZMTransportResponse) {
        super.request(forEntity: entity, didCompleteWithResponse: response)
        
        entity.completionHandler?(response)
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        return sync?.nextRequest()
    }
    
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        sync?.objectsDidChange(object)
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        return sync?.fetchRequestForTrackedObjects()
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        sync?.addTrackedObjects(objects)
    }
}
