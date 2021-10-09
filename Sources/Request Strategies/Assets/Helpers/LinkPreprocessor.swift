//
//

import Foundation

@objcMembers public class LinkPreprocessor<Result>: NSObject, ZMContextChangeTracker {

    let managedObjectContext: NSManagedObjectContext
    let zmLog: ZMSLog

    /// List of objects currently being processed
    fileprivate var objectsBeingProcessed = Set<ZMClientMessage>()

    init(managedObjectContext: NSManagedObjectContext, zmLog: ZMSLog) {
        self.managedObjectContext = managedObjectContext
        self.zmLog = zmLog
    }

    // MARK: - ZMContextChangeTracker

    public func objectsDidChange(_ objects: Set<NSManagedObject>) {
        processObjects(objects)
    }

    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        fatalError("Subclasses need to override fetchRequestForTrackedObjects")
    }

    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        processObjects(objects)
    }

    // MARK: - Processing

    func processObjects(_ objects: Set<NSObject>) {
        objects
            .compactMap(objectsToPreprocess)
            .filter(!objectsBeingProcessed.contains)
            .forEach(processMessage)
    }

    func objectsToPreprocess(_ object: NSObject) -> ZMClientMessage? {
        fatalError("Subclasses need to override objectsToPreprocess(_:)")
    }

    func finishProcessing(_ message: ZMClientMessage) {
        objectsBeingProcessed.remove(message)
    }

    func processMessage(_ message: ZMClientMessage) {
        objectsBeingProcessed.insert(message)

        if let textMessageData = (message as ZMConversationMessage).textMessageData,
            let messageText = textMessageData.messageText {
            zmLog.debug("fetching previews for: \(message.nonce?.uuidString ?? "nil")")

            // We DONT want to generate link previews inside a mentions
            let mentionRanges = textMessageData.mentions.map(\.range)

            // We DONT want to generate link previews for markdown links such as
            // [click me!](www.example.com).
            let markdownRanges = markdownLinkRanges(in: messageText)

            processLinks(in: message, text: messageText, excluding: mentionRanges + markdownRanges)
        } else {
            didProcessMessage(message, result: [])
        }
    }

    func processLinks(in message: ZMClientMessage, text: String, excluding excludedRanges: [NSRange]) {
        fatalError("Subclasses need to override processLinks(inText:excluding:)")
    }

    func didProcessMessage(_ message: ZMClientMessage, result: [Result]) {
        fatalError("Subclasses need to override didProcessMessage(_:result:)")
    }

    fileprivate func markdownLinkRanges(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: "\\[.+\\]\\((.+)\\)", options: []) else { return [] }
        let wholeRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: wholeRange).compactMap { $0.range(at: 0) }
    }

}
