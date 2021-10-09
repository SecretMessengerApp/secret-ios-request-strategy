//
//

import Foundation
import WireDataModel

@objcMembers public class NotificationsTracker: NSObject {

    public let eventName = "notifications.processing"

    public enum Attributes: String {
        case startedProcessing
        case startedFetchingStream
        case finishedFetchingStream
        case finishedProcessing
        case processingExpired
        case abortedProcessing
        case tokenMismatch

        public var identifier: String {
            return "notifications_" + rawValue
        }
    }
    private let isolationQueue = DispatchQueue(label: "NotificationsProcessing")

    weak var analytics: AnalyticsType?
    @objc public init(analytics: AnalyticsType) {
        self.analytics = analytics
    }

    public func registerReceivedPush() {
        increment(attribute: .startedProcessing)
    }

    public func registerNotificationProcessingCompleted() {
        increment(attribute: .finishedProcessing)
    }

    public func registerFinishStreamFetching() {
        increment(attribute: .finishedFetchingStream)
    }

    public func registerStartStreamFetching() {
        increment(attribute: .startedFetchingStream)
    }

    public func registerProcessingExpired() {
        increment(attribute: .processingExpired)
    }
    
    public func registerProcessingAborted() {
        increment(attribute: .abortedProcessing)
    }

    public func registerTokenMismatch() {
        increment(attribute: .tokenMismatch)
    }

    private func increment(attribute: Attributes, by amount: Double = 1) {
        isolationQueue.sync {
            var currentAttributes = analytics?.persistedAttributes(for: eventName) ?? [:]
            var value = (currentAttributes[attribute.identifier] as? Double) ?? 0
            value += amount
            currentAttributes[attribute.identifier] = value as NSObject
            analytics?.setPersistedAttributes(currentAttributes, for: eventName)
        }
    }

    public func dispatchEvent() {
        isolationQueue.sync {
            if let analytics = analytics, let attributes = analytics.persistedAttributes(for: eventName), !attributes.isEmpty {
                analytics.tagEvent(eventName, attributes: attributes)
                analytics.setPersistedAttributes(nil, for: eventName)
            }
        }
    }
}

extension NotificationsTracker {
    override public var debugDescription: String {
        return "Current values: \(analytics?.persistedAttributes(for: eventName) ?? [:])"
    }
}
