//
//

import WireDataModel

@objcMembers
public final class GenericMessageNotificationRequestStrategy: NSObject, RequestStrategy {

    private var token: Any?
    private let managedObjectContext: NSManagedObjectContext
    fileprivate let genericMessageStrategy: GenericMessageRequestStrategy

    public init(managedObjectContext: NSManagedObjectContext, clientRegistrationDelegate: ClientRegistrationDelegate) {
        self.managedObjectContext = managedObjectContext
        self.genericMessageStrategy = GenericMessageRequestStrategy(
            context: managedObjectContext,
            clientRegistrationDelegate: clientRegistrationDelegate
        )
        super.init()
        setupObserver()
    }

    private func setupObserver() {
        self.token = GenericMessageScheduleNotification.addObserver(managedObjectContext: self.managedObjectContext) { [weak self] (message, conversation) in
            guard let `self` = self  else { return }
            let identifier = conversation.objectID
            self.managedObjectContext.performGroupedBlock {
                guard let syncConversation = (try? self.managedObjectContext.existingObject(with: identifier)) as? ZMConversation else { return }
                self.genericMessageStrategy.schedule(message: message, inConversation: syncConversation, completionHandler: nil)
            }
        }
    }

    public func nextRequest() -> ZMTransportRequest? {
        return genericMessageStrategy.nextRequest()
    }

}


extension GenericMessageNotificationRequestStrategy: ZMContextChangeTracker, ZMContextChangeTrackerSource {

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [genericMessageStrategy]
    }

    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        return nil
    }

    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        // no-op
    }

    public func objectsDidChange(_ objects: Set<NSManagedObject>) {
        // no-op
    }

}
