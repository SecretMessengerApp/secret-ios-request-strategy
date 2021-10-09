
import Foundation

/// This strategy observes the `needsToVerifyLegalHold` flag on conversations and fetches an updated list of available clients
/// and verifies that the legal hold status is correct.

@objc
public final class VerifyLegalHoldRequestStrategy: AbstractRequestStrategy {
    
    fileprivate let requestFactory =  ClientMessageRequestFactory()
    fileprivate var conversationSync: IdentifierObjectSync<VerifyLegalHoldRequestStrategy>!
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return conversationSync.nextRequest()
    }
    
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus?) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        configuration = [.allowsRequestsDuringEventProcessing, .allowsRequestsDuringNotificationStreamFetch, .allowsRequestsWhileInBackground]
        conversationSync = IdentifierObjectSync(managedObjectContext: managedObjectContext, transcoder: self)
    }
    
}

extension VerifyLegalHoldRequestStrategy:  ZMContextChangeTracker, ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self]
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        //return ZMConversation.sortedFetchRequest(with: NSPredicate(format: "needsToVerifyLegalHold != 0"))
    
        return ZMConversation.sortedFetchRequest(with: NSPredicate(format: "needsToVerifyLegalHold = 1"))
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        let conversationsNeedingToVerifyClients = objects.compactMap({ $0 as? ZMConversation})
        
        conversationSync.sync(identifiers: conversationsNeedingToVerifyClients)
    }
    
    
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        let conversationsNeedingToVerifyClients = object.compactMap({ $0 as? ZMConversation}).filter(\.needsToVerifyLegalHold)
        
        if !conversationsNeedingToVerifyClients.isEmpty {
            conversationSync.sync(identifiers: conversationsNeedingToVerifyClients)
        }
    }
    
}

extension VerifyLegalHoldRequestStrategy: IdentifierObjectSyncTranscoder {
    public typealias T = ZMConversation
    
    public var fetchLimit: Int {
        return 1
    }
    
    public func request(for identifiers: Set<ZMConversation>) -> ZMTransportRequest? {
        guard let conversationID = identifiers.first?.remoteIdentifier, identifiers.count == 1,
              let selfClient = ZMUser.selfUser(in: managedObjectContext).selfClient(),
              identifiers.first?.conversationType != .hugeGroup 
        else { return nil }
        
        return requestFactory.upstreamRequestForFetchingClients(conversationId: conversationID, selfClient: selfClient)
    }
    
    public func didReceive(response: ZMTransportResponse, for identifiers: Set<ZMConversation>) {
        guard let conversation = identifiers.first else { return }
        
        let verifyClientsParser = VerifyClientsParser(context: managedObjectContext, conversation: conversation)

        let changeSet = verifyClientsParser.parseEmptyUploadResponse(response, in: conversation, clientRegistrationDelegate: applicationStatus!.clientRegistrationDelegate)
        conversation.updateSecurityLevelIfNeededAfterFetchingClients(changes: changeSet)
    }
    
}

fileprivate class VerifyClientsParser: OTREntity {
    
    var context: NSManagedObjectContext
    let conversation: ZMConversation
    
    init(context: NSManagedObjectContext, conversation: ZMConversation) {
        self.context = context
        self.conversation = conversation
    }
    
    func missesRecipients(_ recipients: Set<UserClient>!) {
        // no-op
    }
    
    func detectedRedundantClients() {
        conversation.needsToBeUpdatedFromBackend = true
    }
    
    func detectedMissingClient(for user: ZMUser) {
        // no-op
    }
    
    var dependentObjectNeedingUpdateBeforeProcessing: NSObject? = nil
    
    var isExpired: Bool = false
    
    func expire() {
        // no-op
    }
    
}
