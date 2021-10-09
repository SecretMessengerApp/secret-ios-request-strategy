
import Foundation
import CoreData

@objc(StoredHugeUpdateEvent)
public final class StoredHugeUpdateEvent: NSManagedObject {
    
    static let entityName =  "StoredHugeUpdateEvent"
    static let SortIndexKey = "sortIndex"
    static let UUIDStringKey = "uuidString"
    static let SourceKey = "source"
    @NSManaged public var uuidString: String?
    @NSManaged public var debugInformation: String?
    @NSManaged public var isTransient: Bool
    @NSManaged public var payload: NSDictionary
    @NSManaged public var source: Int16
    @NSManaged public var sortIndex: Int64
    
    static func insertNewObject(_ context: NSManagedObjectContext) -> StoredHugeUpdateEvent? {
        return NSEntityDescription.insertNewObject(forEntityName: self.entityName, into: context) as? StoredHugeUpdateEvent
    }
    
    /// Maps a passed in `ZMUpdateEvent` to a `StoredHugeUpdateEvent` which is persisted in a database
    /// The passed in `index` is used to enumerate events to be able to fetch and sort them later on in the order they were received
    @discardableResult
    public static func create(_ event: ZMUpdateEvent, managedObjectContext: NSManagedObjectContext, index: Int64) -> StoredHugeUpdateEvent? {
        guard let storedEvent = StoredHugeUpdateEvent.insertNewObject(managedObjectContext) else { return nil }
        storedEvent.debugInformation = event.debugInformation
        storedEvent.isTransient = event.isTransient
        storedEvent.payload = event.payload as NSDictionary
        storedEvent.source = Int16(event.source.rawValue)
        storedEvent.sortIndex = index
        storedEvent.uuidString = event.uuid?.transportString()
        return storedEvent
    }

    
    @discardableResult
    public static func toUpdateEvent(_ event: StoredHugeUpdateEvent) -> ZMUpdateEvent? {
        guard let uuid = event.uuidString else {return nil}
        let updateEvent = ZMUpdateEvent(uuid: UUID(uuidString: uuid), payload: event.payload as! [String: Any], transient: event.isTransient, decrypted: true, source: .download)
        return updateEvent
    }
    
    /// Returns stored events sorted by and up until (including) the defined `stopIndex`
    /// Returns a maximum of `batchSize` events at a time
    public static func nextEvents(_ context: NSManagedObjectContext, batchSize: Int) -> [StoredHugeUpdateEvent] {
        let fetchRequest = NSFetchRequest<StoredHugeUpdateEvent>(entityName: self.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: StoredHugeUpdateEvent.SortIndexKey, ascending: true)]
        fetchRequest.fetchLimit = batchSize
        fetchRequest.returnsObjectsAsFaults = false
        let result = context.fetchOrAssert(request: fetchRequest)
        return result
    }
    
    /// Returns the highest index of all stored events
    public static func highestIndex(_ context: NSManagedObjectContext) -> Int64 {
        let fetchRequest = NSFetchRequest<StoredHugeUpdateEvent>(entityName: self.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: StoredHugeUpdateEvent.SortIndexKey, ascending: false)]
        fetchRequest.fetchBatchSize = 1
        let result = context.fetchOrAssert(request: fetchRequest)
        return result.first?.sortIndex ?? 0
    }
    
    /// Maps passed in objects of type `StoredHugeUpdateEvent` to `ZMUpdateEvent`
    public static func eventsFromStoredEvents(_ storedEvents: [StoredHugeUpdateEvent]) -> [ZMUpdateEvent] {
        let events : [ZMUpdateEvent] = storedEvents.compactMap {
            var eventUUID : UUID?
            if let uuid = $0.uuidString {
                eventUUID = UUID(uuidString: uuid)
            }
            let decryptedEvent = ZMUpdateEvent.decryptedUpdateEvent(fromEventStreamPayload: $0.payload, uuid:eventUUID, transient: $0.isTransient, source: ZMUpdateEventSource(rawValue:Int($0.source))!)
            if let debugInfo = $0.debugInformation {
                decryptedEvent?.appendDebugInformation(debugInfo)
            }
            return decryptedEvent
        }
        return events
    }
}
