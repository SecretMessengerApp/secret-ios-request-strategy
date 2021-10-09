//
//

import Foundation

/// Holds a list of received event IDs
@objc
public protocol PreviouslyReceivedEventIDsCollection: NSObjectProtocol {
    func discardListOfAlreadyReceivedPushEventIDs()
    func discardListOfAlreadyReceivedHugePushEventIDs()
}

@objc
public protocol UpdateEventProcessor: class {
    @objc(decryptUpdateEventsAndGenerateNotification:)
    func decryptUpdateEventsAndGenerateNotification(_ updateEvents: [ZMUpdateEvent])
    
    @objc(processUpdateEvents:)
    func processUpdateEvents(_ updateEvents: [ZMUpdateEvent])
}

public protocol NotificationStreamSyncDelegate: class {
    func fetchedEvents(_ events: [ZMUpdateEvent])
    func failedFetchingEvents()
}

private var exLog = ExLog(tag: "NotificationStreamSync")

public class NotificationStreamSync: NSObject, ZMRequestGenerator, ZMSingleRequestTranscoder {
    
    public var fetchNotificationSync: ZMSingleRequestSync!
    private unowned var managedObjectContext: NSManagedObjectContext!
    private weak var notificationStreamSyncDelegate: NotificationStreamSyncDelegate?
    private var accountIdentifier: UUID
    
    deinit {
        print("NotificationStreamSync deinit")
    }

    public init(moc: NSManagedObjectContext,
                delegate: NotificationStreamSyncDelegate,
                accountid: UUID) {
        accountIdentifier = accountid
        super.init()
        managedObjectContext = moc
        fetchNotificationSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: moc)
        fetchNotificationSync.readyForNextRequest()
        notificationStreamSyncDelegate = delegate
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        return fetchNotificationSync.nextRequest()
    }
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        let clientIdentifier = ZMUser.selfUser(in: self.managedObjectContext).selfClient()?.remoteIdentifier
        guard let cid = clientIdentifier else {return nil}
        var queryItems = [URLQueryItem]()
        let sizeItem = URLQueryItem(name: "size", value: "50")
        var startKeyItem: URLQueryItem?
        if let lastEventId = AppGroupInfo.instance.sharedUserDefaults.value(forKey: lastUpdateEventIDKey + self.accountIdentifier.transportString()) as? String {
            startKeyItem = URLQueryItem(name: "since", value: lastEventId)
            exLog.info("request for sync eventId:\(lastEventId)")
        } else {
            exLog.info("can't create request for sync that no lastEventId")
            return nil
        }
        let cidItem = URLQueryItem(name: "client", value: cid)
        if let startItem = startKeyItem {
            queryItems.append(startItem)
        }
        queryItems.append(sizeItem)
        queryItems.append(cidItem)
        var components = URLComponents(string: "/notifications/user")
        components?.queryItems = queryItems
        guard let compString = components?.string else {return nil}
        let request = ZMTransportRequest(getFromPath: compString)
        exLog.info("generate new stream request \(request)")
        return request
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        if let timestamp = response.payload?.asDictionary()?["time"] {
            updateServerTimeDeltaWith(timestamp: timestamp as! String)
        }
        processUpdateEvents(from: response.payload)
    }
    
    @objc(processUpdateEventsFromPayload:)
    func processUpdateEvents(from payload: ZMTransportData?) {
        let source = ZMUpdateEventSource.pushNotification
        guard let eventsDictionaries = eventDictionariesFrom(payload: payload) else {
            return
        }
        var pEvents: [ZMUpdateEvent] = []
        for eventDictionary in eventsDictionaries {
            guard let events = ZMUpdateEvent.eventsArray(from: eventDictionary as ZMTransportData, source: source) else {
                return
            }
            pEvents.append(contentsOf: events)
        }
        notificationStreamSyncDelegate?.fetchedEvents(pEvents)
    }
}

// MARK: Private

extension NotificationStreamSync {
    private func updateServerTimeDeltaWith(timestamp: String) {
        let serverTime = NSDate(transport: timestamp)
        guard let serverTimeDelta = serverTime?.timeIntervalSinceNow else {
            return
        }
        self.managedObjectContext.serverTimeDelta = serverTimeDelta
    }
    
    private func eventDictionariesFrom(payload: ZMTransportData?) -> [[String: Any]]? {
        return payload?.asDictionary()?["notifications"] as? [[String: Any]]
    }
}
