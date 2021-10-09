

import Foundation

private var exLog = ExLog(tag: "NotificationSingleSync")

public protocol NotificationSingleSyncDelegate: class {
    func fetchedEvent(_ event: ZMUpdateEvent)
}

public class NotificationSingleSync: NSObject, ZMRequestGenerator {
    
    private weak var delegate: NotificationSingleSyncDelegate?
    
    private var notificationSingleSync: ZMSingleRequestSync!
    
    private var managedObjectContext: NSManagedObjectContext!
    
    private var eventId: String?
    
    private var hugeConvId: String?
    
    public init(moc: NSManagedObjectContext, delegate: NotificationSingleSyncDelegate, eventId: String, hugeConvId: String? = nil) {
        super.init()
        self.managedObjectContext = moc
        self.delegate = delegate
        self.eventId = eventId
        self.hugeConvId = hugeConvId
        notificationSingleSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: moc)
        exLog.info("NotificationSingleSync init eventId: \(eventId)")
        notificationSingleSync.readyForNextRequest()
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        return notificationSingleSync.nextRequest()
    }
    
    deinit {
        exLog.info("NotificationSingleSync deinit")
    }
    
}


extension NotificationSingleSync: ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        exLog.info("request for sync eventId \(String(describing: self.eventId))")
        guard let eventId = self.eventId else {return nil}
        var params = "/notifications"
        if let hugeConvid = self.hugeConvId {
            params += "/bgp/\(hugeConvid)/\(eventId)"
        } else {
            params += "/user/\(eventId)"
        }
        let components = URLComponents(string: params)
        guard let path = components?.string else { return nil }
        exLog.info("generate single request path \(path)")
        return ZMTransportRequest(getFromPath: path)
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        exLog.info("didReceive single request payload \(String(describing: response.payload))")
        guard let payload = response.payload else {
            return
        }
        let source = ZMUpdateEventSource.pushNotification
        guard let event = ZMUpdateEvent.eventsArray(from: payload as ZMTransportData, source: source)?.first else {
            return
        }
        delegate?.fetchedEvent(event)
    }
    
}
