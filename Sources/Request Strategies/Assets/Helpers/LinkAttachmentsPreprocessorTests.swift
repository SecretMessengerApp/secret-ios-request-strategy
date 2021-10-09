//


import XCTest
import WireLinkPreview
import WireDataModel
import WireImages

@testable import WireRequestStrategy

final class MockAttachmentDetector: LinkAttachmentDetectorType {

    var nextResult = [LinkAttachment]()
    var downloadCount: Int = 0
    var excludedRanges: [NSRange] = []

    func downloadLinkAttachments(inText text: String, excluding: [NSRange], completion: @escaping ([LinkAttachment]) -> Void) {
        downloadCount += 1
        excludedRanges = excluding
        completion(nextResult)
    }

}

class LinkAttachmentsPreprocessorTests: MessagingTestBase {

    var sut: LinkAttachmentsPreprocessor!
    var mockDetector: MockAttachmentDetector!

    override func setUp() {
        super.setUp()
        mockDetector = MockAttachmentDetector()
        sut = LinkAttachmentsPreprocessor(linkAttachmentDetector: mockDetector, managedObjectContext: syncMOC)
    }

    override func tearDown() {
        mockDetector = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Helper

    func createMessage(text: String = "text message 123", mentions: [Mention] = [], needsUpdate: Bool = true, isEphemeral : Bool = false) -> ZMClientMessage {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = UUID.create()
        if isEphemeral {
            conversation.messageDestructionTimeout = .local(.tenSeconds)
        }
        let message = conversation.append(text: text, mentions: mentions) as! ZMClientMessage
        message.needsLinkAttachmentsUpdate = needsUpdate
        return message
    }

    var thumbnailURL: URL {
        return URL(string: "https://i.ytimg.com/vi/hyTNGkBSjyo/hqdefault.jpg")!
    }

    func createAttachment(withCachedImage: Bool = true) -> LinkAttachment {
        let attachment = LinkAttachment(type: .youTubeVideo, title: "Pingu Season 1 Episode 1",
                                       permalink: URL(string: "https://www.youtube.com/watch?v=hyTNGkBSjyo")!,
                                       thumbnails: [thumbnailURL],
                                       originalRange: NSRange(location: 20, length: 43))

        return attachment
    }

    func assertThatItProcessesMessageWithLinkAttachmentState(_ needsUpdate: Bool, line: UInt = #line) {
        self.syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let message = self.createMessage(needsUpdate: needsUpdate)

            // WHEN
            self.sut.objectsDidChange([message])
        }

        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            let callCount: Int = needsUpdate ? 1 : 0
            XCTAssertEqual(self.mockDetector.downloadCount, callCount, "Failure processing for update state \(needsUpdate)", line: line)
            self.mockDetector.downloadCount = 0
        }
    }

    func testThatItOnlyProcessesMessagesNeedingUpdate_WaitingToBeProcessed() {
        assertThatItProcessesMessageWithLinkAttachmentState(true)
        assertThatItProcessesMessageWithLinkAttachmentState(false)
    }

    func testThatItDoesNotStoreTheOriginalImageDataInTheCacheAndFinishesWhenItReceivesAPreviewWithImage() {
        var message : ZMClientMessage!
        let attachment = self.createAttachment(withCachedImage: true)

        self.syncMOC.performGroupedBlockAndWait {
            // GIVEN
            self.mockDetector.nextResult = [attachment]
            message = self.createMessage()

            // WHEN
            self.sut.objectsDidChange([message])
        }

        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(self.mockDetector.downloadCount, 1)
            XCTAssertEqual(message.linkAttachments, [attachment])
            let data = self.syncMOC.zm_fileAssetCache.assetData(message, format: .original, encrypted: false)
            XCTAssertNil(data)
            XCTAssertFalse(message.needsLinkAttachmentsUpdate)
        }
    }

    func testThatItFinishesIfNoAttachmentsAreReturned() {
        var message : ZMClientMessage!
        self.syncMOC.performGroupedBlockAndWait {

            // GIVEN
            message = self.createMessage()

            // WHEN
            self.sut.objectsDidChange([message])
        }

        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(self.mockDetector.downloadCount, 1)
            XCTAssertFalse(message.needsLinkAttachmentsUpdate)
        }
    }

    func testThatItFinishesIfTheMessageDoesNotHaveTextMessageData() {
        var message : ZMClientMessage!

        self.syncMOC.performGroupedBlockAndWait {

            // GIVEN
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.remoteIdentifier = UUID.create()
            message = conversation.appendKnock() as? ZMClientMessage

            // WHEN
            self.sut.objectsDidChange([message])
        }

        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertFalse(message.needsLinkAttachmentsUpdate)
        }
    }

    func testThatItShouldExcludeMentionsFromLinkAttachmentsGeneration() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let text = "@john - www.sunet.se hello"
            let message = self.createMessage(text: text, mentions: [Mention(range: NSMakeRange(0, 20), user: self.otherUser)])

            // WHEN
            self.sut.processMessage(message)

            // THEN
            XCTAssertEqual(self.mockDetector.excludedRanges, [NSRange(location: 0, length: 20)])
        }
    }

    func testThatItShouldExcludeMarkdownLinksFromLinkAttachmentsGeneration() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let text = "[click me!](www.example.com) hello"
            let message = self.createMessage(text: text)

            // WHEN
            self.sut.processMessage(message)

            // THEN
            XCTAssertEqual(self.mockDetector.excludedRanges, [NSRange(location: 0, length: 28)])
        }
    }

    func testThatItShouldNotExcludeNonMarkdownLinksFromLinkAttachmentsGeneration() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let text = "click this: www.example.com"
            let message = self.createMessage(text: text)

            // WHEN
            self.sut.processMessage(message)

            // THEN
            XCTAssertTrue(self.mockDetector.excludedRanges.isEmpty)
        }
    }

    // MARK: - Ephemeral

    func testThatItReturnsAnEphemeralMessageAfterPreProcessingAnEphemeral() {
        var message : ZMClientMessage!
        var attachment : LinkAttachment!
        self.syncMOC.performGroupedBlockAndWait {

            // GIVEN
            attachment = self.createAttachment()
            self.mockDetector.nextResult = [attachment]
            message = self.createMessage(isEphemeral: true)
            XCTAssertTrue(message.isEphemeral)

            // WHEN
            self.sut.objectsDidChange([message])
        }

        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(self.mockDetector.downloadCount, 1)
            XCTAssertFalse(message.needsLinkAttachmentsUpdate)
            let data = self.syncMOC.zm_fileAssetCache.assetData(message, format: .original, encrypted: false)
            XCTAssertNil(data)
            guard let genericMessage = message.genericMessage else { return XCTFail("No generic message") }
            XCTAssertTrue(genericMessage.hasEphemeral())
            XCTAssertTrue(message.linkAttachments?.isEmpty == false)
        }
    }

    func testThatItDoesNotUpdateMessageWhenMessageHasBeenObfuscatedAndSetsPreviewStateToDone() {
        var message: ZMClientMessage!
        self.syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let attachment = self.createAttachment()
            self.mockDetector.nextResult = [attachment]
            message = self.createMessage(isEphemeral: true)
            XCTAssertTrue(message.isEphemeral)
            message.obfuscate()
            XCTAssertTrue(message.needsLinkAttachmentsUpdate)

            // WHEN
            self.sut.objectsDidChange([message])
        }

        self.syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertEqual(message.linkAttachments, [])
            XCTAssertFalse(message.needsLinkAttachmentsUpdate)
        }
    }

}
