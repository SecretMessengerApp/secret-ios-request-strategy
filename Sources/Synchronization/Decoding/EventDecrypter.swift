

import Foundation

private var exLog = ExLog(tag: "NotificationExtension")

@objcMembers public final class EventDecrypter: NSObject {
    
    unowned let syncMOC: NSManagedObjectContext
    
    public init(syncMOC: NSManagedObjectContext) {
        self.syncMOC = syncMOC
        super.init()
    }
        
    /// Decrypted events
    @discardableResult
    public func decryptEvents(_ events: [ZMUpdateEvent]) -> [ZMUpdateEvent] {
        var decryptedEvents: [ZMUpdateEvent] = []
        exLog.info("eventDecrypter ready decryptEvents: \(String(describing: events.first?.uuid?.transportString()))")
        syncMOC.zm_cryptKeyStore.encryptionContext.perform { [weak self] (sessionsDirectory) -> Void in
            guard let `self` = self else { return }
            decryptedEvents = events.compactMap { event -> ZMUpdateEvent? in
                if event.type == .conversationOtrMessageAdd || event.type == .conversationOtrAssetAdd {
                     let e = sessionsDirectory.decryptAndAddClient(event, in: self.syncMOC)
                    sessionsDirectory.discardCache()
                    return e
                } else {
                    return event
                }
            }
            exLog.info("eventDecrypter already decryptEvents: \(String(describing: decryptedEvents.first?.uuid?.transportString()))")
            
            exLog.info("eventDecrypter discardCache decryptEvents: \(String(describing: decryptedEvents.first?.uuid?.transportString()))")
        }
        return decryptedEvents
    }
    
    deinit {
        print("EventDecrypter deinit")
    }
    
}
