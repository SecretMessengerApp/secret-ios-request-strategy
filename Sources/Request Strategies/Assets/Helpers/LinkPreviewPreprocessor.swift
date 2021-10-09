//


import Foundation
import WireLinkPreview
import WireDataModel
import WireUtilities

@objcMembers public final class LinkPreviewPreprocessor : LinkPreprocessor<LinkMetadata> {
        
    fileprivate let linkPreviewDetector: LinkPreviewDetectorType

    public init(linkPreviewDetector: LinkPreviewDetectorType, managedObjectContext: NSManagedObjectContext) {
        self.linkPreviewDetector = linkPreviewDetector
        let log = ZMSLog(tag: "link previews")
        super.init(managedObjectContext: managedObjectContext, zmLog: log)
    }

    public override func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let predicate = NSPredicate(format: "%K == %d", ZMClientMessageLinkPreviewStateKey, ZMLinkPreviewState.waitingToBeProcessed.rawValue)
        return ZMClientMessage.sortedFetchRequest(with: predicate)
    }

    override func objectsToPreprocess(_ object: NSObject) -> ZMClientMessage? {
        guard let message = object as? ZMClientMessage else { return nil }
        return message.linkPreviewState == .waitingToBeProcessed ? message : nil
    }

    override func processLinks(in message: ZMClientMessage, text: String, excluding excludedRanges: [NSRange]) {
        linkPreviewDetector.downloadLinkPreviews(inText: text, excluding: excludedRanges) { [weak self] linkPreviews in
            message.managedObjectContext?.performGroupedBlock {
                self?.zmLog.debug("\(linkPreviews.count) previews for: \(message.nonce?.uuidString ?? "nil")\n\(linkPreviews)")
                self?.didProcessMessage(message, result: linkPreviews)
            }
        }
    }

    override func didProcessMessage(_ message: ZMClientMessage, result linkPreviews: [LinkMetadata]) {
        
        guard let managedObjectContext = message.managedObjectContext else {return}
        
        finishProcessing(message)

        if let preview = linkPreviews.first, let messageText = message.textMessageData?.messageText, let mentions = message.textMessageData?.mentions, !message.isObfuscated {
            let updatedText = ZMText.text(with: messageText, mentions: mentions, linkPreviews: [preview.protocolBuffer])
            let updatedMessage = ZMGenericMessage.message(content: updatedText, nonce: message.nonce!, expiresAfter: message.deletionTimeout)
            message.add(updatedMessage.data())

            if let imageData = preview.imageData.first {
                zmLog.debug("image in linkPreview (need to upload), setting state to .downloaded for: \(message.nonce?.uuidString ?? "nil")")
                managedObjectContext.zm_fileAssetCache.storeAssetData(message, format: .original, encrypted: false, data: imageData)
                message.linkPreviewState = .downloaded
            } else {
                zmLog.debug("no image in preview, setting state to .uploaded for: \(message.nonce?.uuidString ?? "nil")")
                message.linkPreviewState = .uploaded
            }
        } else {
            zmLog.debug("no linkpreview or obfuscated message, setting state to .done for: \(message.nonce?.uuidString ?? "nil")")
            message.linkPreviewState = .done
        }

        // The change processor is called as a response to a context save,
        // which is why we need to enque a save maually here
        managedObjectContext.enqueueDelayedSave()
    }

}
