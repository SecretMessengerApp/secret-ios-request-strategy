//


import Foundation
import WireDataModel

private let zmLog = ZMSLog(tag: "Dependencies")

// MARK: - Dependent objects
extension ZMOTRMessage: OTREntity {

    public var context: NSManagedObjectContext {
        return managedObjectContext!
    }

    /// Which object this message depends on when sending
    @objc public override var dependentObjectNeedingUpdateBeforeProcessing: NSObject? {
        guard let conversation = conversation else { return nil }
        
        let dependent = self.dependentObjectNeedingUpdateBeforeProcessingOTREntity(in: conversation)
        return dependent ?? super.dependentObjectNeedingUpdateBeforeProcessing
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
    
}

/// Message that can block following messages
//@objc private protocol BlockingMessage {
//
//    /// If true, no other messages should be sent until this message is sent
//    var shouldBlockFurtherMessages : Bool { get }
//}

extension ZMMessage {
    
    /// Which object this message depends on when sending
    @objc public var dependentObjectNeedingUpdateBeforeProcessing: NSObject? {
        
        // conversation not created yet on the BE?
        guard let conversation = self.conversation else { return nil }
        
        guard conversation.conversationType != .hugeGroup else {return nil}
        
        if conversation.remoteIdentifier == nil {
            zmLog.debug("conversation has no remote identifier")
            return conversation
        }
        
        return nil
        // Messages should time out within 1 minute. But image messages never time out. In case there is a bug
        // and one image message gets stuck in a non-sent state (but not expired), that message will block any future
        // message in that conversation forver. This happened with some buggy builds (ie.g. internal 2838).
        // In order to recover from this situation for people that used a buggy client, we can set a cap
        // to the amount of time that a "non-delivered" message will block future messages.
        // This will also prevent looking too far back in time for ALL messages in a conversation. Only messages
        // that are more recent than X minutes will be considered. The expected "pending messages" should expire
        // within a minute anyway. The server timestamp of the pending messages (since they are not delivered)
        // is set using the local timestamp so we can safely check with the current messge timestamp (not delivered,
        // so also a local timestamp). Of course the user could change the local clock in between sending messages
        // but this is quite an edge case.
//        let MaxDelayToConsiderForBlockingObject = Double(3 * 60); // 3 minutes

//        var blockingMessage : ZMMessage?
        
        // we don't want following messages to block this one, only previous ones.
        // so we iterate backwards and we ignore everything until we find this one
//        var selfMessageFound = false
//
//        for previousMessage in conversation.lastMessages() {
//            if let currentTimestamp = self.serverTimestamp,
//                let previousTimestamp = previousMessage.serverTimestamp {
//
//                // to old?
//                let tooOld = currentTimestamp.timeIntervalSince(previousTimestamp) > MaxDelayToConsiderForBlockingObject
//                if tooOld {
//                    break
//                }
//            }
//
//            let sameMessage = previousMessage === self || previousMessage.nonce == self.nonce
//            if sameMessage {
//                selfMessageFound = true
//            }
//
//            if selfMessageFound && !sameMessage && previousMessage.shouldBlockFurtherMessages {
//                blockingMessage = previousMessage
//                break
//            }
//        }
//        return blockingMessage
    }
    
}

//extension ZMMessage : BlockingMessage {
//
//    var shouldBlockFurtherMessages : Bool {
//        
//        if let videoMessage = self as? ZMAssetClientMessage, videoMessage.isVideo {
//            return false
//        }
//        return self.deliveryState == .pending && !self.isExpired
//    }
//}
