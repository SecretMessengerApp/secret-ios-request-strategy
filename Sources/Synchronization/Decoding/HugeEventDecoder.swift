
import Foundation
import WireCryptobox
import WireDataModel

private let zmLog = ZMSLog(tag: "HugeEventDecoder")

/// Key used in persistent store metadata
private let previouslyReceivedHugeEventIDsKey = "zm_previouslyReceivedHugeEventIDsKey"

/// Decodes and stores events from various sources to be processed later
@objcMembers public final class HugeEventDecoder: NSObject {
    
    public typealias ConsumeBlock = (([ZMUpdateEvent]) -> Void)
    
    static var BatchSize : Int {
        return 500
    }
    
    /// Set this for testing purposes only
    public static var testingBatchSize : Int?
    
    unowned let eventMOC : NSManagedObjectContext
    unowned let syncMOC: NSManagedObjectContext
    private let userDefault: UserDefaults?
    
    fileprivate typealias EventsWithStoredEvents = (storedEvents: [StoredHugeUpdateEvent], updateEvents: [ZMUpdateEvent])
    
    public init(eventMOC: NSManagedObjectContext, syncMOC: NSManagedObjectContext) {
        self.eventMOC = eventMOC
        self.syncMOC = syncMOC
        let groupIdentifier = UserDefaults.standard.string(forKey: EnvironmentType.groupIdentifier)
        self.userDefault = UserDefaults(suiteName: groupIdentifier)
        super.init()
        self.eventMOC.performGroupedBlockAndWait {
            self.createReceivedHugePushEventIDsStoreIfNecessary()
        }
    }
}

// MARK: - Process events
extension HugeEventDecoder {
    
    /// Decrypts passed in events and stores them in chronological order in a persisted database. It then saves the database and cryptobox
    /// It then calls the passed in block (multiple times if necessary), returning the decrypted events
    /// If the app crashes while processing the events, they can be recovered from the database
    public func processEvents(_ events: [ZMUpdateEvent], block: ConsumeBlock, isNewNotificationVersion: Bool = false) {
        var lastIndex: Int64?
        
        eventMOC.performGroupedBlockAndWait {
            
            let filteredEvents = self.filterAlreadyReceivedEvents(from: events)
            self.storeReceivedPushEventIDs(from: events)
            
            // Get the highest index of events in the DB
            lastIndex = StoredHugeUpdateEvent.highestIndex(self.eventMOC)
            
            guard let index = lastIndex else { return }
            self.storeEvents(filteredEvents, startingAtIndex: index)
        }
        
        if !events.isEmpty {
            Logging.eventProcessing.info("Decrypted/Stored \( events.count) event(s)")
        }
        
        process(block, firstCall: true, isNewNotificationVersion: isNewNotificationVersion)
    }
    
    /// Decrypts and stores the decrypted events as `StoreUpdateEvent` in the event database.
    /// The encryption context is only closed after the events have been stored, which ensures
    /// they can be decrypted again in case of a crash.
    /// - parameter events The new events that should be decrypted and stored in the database.
    /// - parameter startingAtIndex The startIndex to be used for the incrementing sortIndex of the stored events.
    fileprivate func storeEvents(_ events: [ZMUpdateEvent], startingAtIndex startIndex: Int64) {
        self.eventMOC.performGroupedBlockAndWait {
            // Insert the decryted events in the event database using a `storeIndex`
            // incrementing from the highest index currently stored in the database
            for (idx, event) in events.enumerated() {
                _ = StoredHugeUpdateEvent.create(event, managedObjectContext: self.eventMOC, index: Int64(idx) + startIndex + 1)
            }
            
            self.eventMOC.saveOrRollback()
        }
    }
    
    // Processes the stored events in the database in batches of size EventDecoder.BatchSize` and calls the `consumeBlock` for each batch.
    // After the `consumeBlock` has been called the stored events are deleted from the database.
    // This method terminates when no more events are in the database.
    private func process(_ consumeBlock: ConsumeBlock, firstCall: Bool, isNewNotificationVersion: Bool = false) {
        let events = fetchNextEventsBatch()
        guard events.storedEvents.count > 0 else {
            if firstCall {
                consumeBlock([])
            }
            return
        }

        processBatch(events.updateEvents, storedEvents: events.storedEvents, block: consumeBlock, isNewNotificationVersion: isNewNotificationVersion)
        process(consumeBlock, firstCall: false)
    }
    
    /// Calls the `ComsumeBlock` and deletes the respective stored events subsequently.
    private func processBatch(_ events: [ZMUpdateEvent], storedEvents: [NSManagedObject], block: ConsumeBlock, isNewNotificationVersion: Bool = false) {
        if !events.isEmpty {
            Logging.eventProcessing.info("Forwarding \(events.count) event(s) to consumers")
        }
        
        block(filterInvalidEvents(from: events))
        
        if !isNewNotificationVersion {
            eventMOC.performGroupedBlockAndWait {
                storedEvents.forEach(self.eventMOC.delete(_:))
                self.eventMOC.saveOrRollback()
            }
        }
    }
    
    /// Fetches and returns the next batch of size `EventDecoder.BatchSize`
    /// of `StoredEvents` and `ZMUpdateEvent`'s in a `EventsWithStoredEvents` tuple.
    private func fetchNextEventsBatch() -> EventsWithStoredEvents {
        var (storedEvents, updateEvents)  = ([StoredHugeUpdateEvent](), [ZMUpdateEvent]())

        eventMOC.performGroupedBlockAndWait {
            storedEvents = StoredHugeUpdateEvent.nextEvents(self.eventMOC, batchSize: HugeEventDecoder.BatchSize)
            updateEvents = StoredHugeUpdateEvent.eventsFromStoredEvents(storedEvents)
        }
        return (storedEvents: storedEvents, updateEvents: updateEvents)
    }
    
}

// MARK: - List of already received event IDs
extension HugeEventDecoder {
    
    /// create event ID store if needed
    fileprivate func createReceivedHugePushEventIDsStoreIfNecessary() {
        if self.eventMOC.persistentStoreMetadata(forKey: previouslyReceivedHugeEventIDsKey) as? [String] == nil {
            self.eventMOC.setPersistentStoreMetadata(array: [String](), key: previouslyReceivedHugeEventIDsKey)
        }
    }
    
    
    /// List of already received event IDs
    fileprivate var alreadyReceivedHugePushEventIDs : Set<UUID> {
        let array = self.eventMOC.persistentStoreMetadata(forKey: previouslyReceivedHugeEventIDsKey) as! [String]
        return Set(array.compactMap { UUID(uuidString: $0) })
    }
    
    /// List of already received event IDs as strings
    fileprivate var alreadyReceivedPushEventIDsStrings : Set<String> {
        return Set(self.eventMOC.persistentStoreMetadata(forKey: previouslyReceivedHugeEventIDsKey) as! [String])
    }
    
    /// Store received event IDs

    fileprivate func storeReceivedPushEventIDs(from: [ZMUpdateEvent]) {
        let uuidToAdd = from
            .filter { $0.source != .webSocket}
            .compactMap { $0.uuid }
            .map { $0.transportString() }
        let allUuidStrings = self.alreadyReceivedPushEventIDsStrings.union(uuidToAdd)
        
        self.eventMOC.setPersistentStoreMetadata(array: Array(allUuidStrings), key: previouslyReceivedHugeEventIDsKey)
    }
    
    /// Filters out events that have been received before

    fileprivate func filterAlreadyReceivedEvents(from: [ZMUpdateEvent]) -> [ZMUpdateEvent] {
        let eventIDsToDiscard = self.alreadyReceivedHugePushEventIDs
        return from.compactMap { event -> ZMUpdateEvent? in
            if /*event.source != .pushNotification, */let uuid = event.uuid {
                return eventIDsToDiscard.contains(uuid) ? nil : event
            } else {
                return event
            }
        }
    }
    
    /// Filters out events that shouldn't be processed
    fileprivate func filterInvalidEvents(from events: [ZMUpdateEvent]) -> [ZMUpdateEvent] {
        let selfConversation = ZMConversation.selfConversation(in: syncMOC)
        let selfUser = ZMUser.selfUser(in: syncMOC)
        
        return events.filter { event in
            // The only message we process arriving in the self conversation from other users is availability updates
            if event.conversationUUID() == selfConversation.remoteIdentifier, event.senderUUID() != selfUser.remoteIdentifier, let genericMessage = ZMGenericMessage(from: event) {
                return genericMessage.hasAvailability()
            }
            
            return true
        }
    }
}

@objc extension HugeEventDecoder: PreviouslyReceivedEventIDsCollection {
    
    public func discardListOfAlreadyReceivedPushEventIDs() {
        
    }

    /// Discards the list of already received events
    public func discardListOfAlreadyReceivedHugePushEventIDs() {
        self.eventMOC.performGroupedBlockAndWait {
            self.eventMOC.setPersistentStoreMetadata(array: [String](), key: previouslyReceivedHugeEventIDsKey)
        }
    }
}
