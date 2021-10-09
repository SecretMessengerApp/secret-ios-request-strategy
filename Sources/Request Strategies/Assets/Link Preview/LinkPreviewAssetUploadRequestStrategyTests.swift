//


import Foundation
import WireLinkPreview
import WireDataModel
import WireRequestStrategy
import XCTest

// MARK: - Tests setup
class LinkPreviewAssetUploadRequestStrategyTests: MessagingTestBase {
    
    fileprivate var sut: LinkPreviewAssetUploadRequestStrategy!
    fileprivate var mockApplicationStatus: MockApplicationStatus!
    
    override func setUp() {
        super.setUp()
        
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing

        self.sut = LinkPreviewAssetUploadRequestStrategy(managedObjectContext: self.syncMOC, applicationStatus: mockApplicationStatus, linkPreviewPreprocessor: nil, previewImagePreprocessor: nil)
    }
    
    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
        super.tearDown()
    }
    
    /// Creates a message that should generate request
    func createMessage(_ text: String, linkPreviewState: ZMLinkPreviewState = .waitingToBeProcessed, linkPreview: LinkMetadata, isEphemeral: Bool = false) -> ZMClientMessage {
        let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
        conversation.remoteIdentifier = UUID.create()
        if isEphemeral {
            conversation.messageDestructionTimeout = .local(.tenSeconds)
        }
        let message = conversation.append(text: text) as! ZMClientMessage
        message.linkPreviewState = linkPreviewState
        if isEphemeral {
            XCTAssertTrue(message.isEphemeral)
            message.add(ZMGenericMessage.message(content: ZMText.text(with: text, mentions: [], linkPreviews: [linkPreview.protocolBuffer]), nonce: message.nonce!, expiresAfter: 10).data())
        } else {
            message.add(ZMGenericMessage.message(content: ZMText.text(with: text, mentions: [], linkPreviews: [linkPreview.protocolBuffer]), nonce: message.nonce!).data())
        }
        self.syncMOC.saveOrRollback()
        
        return message
    }
    
    func createArticle() -> ArticleMetadata {
        let article = ArticleMetadata(
            originalURLString: "example.com/article",
            permanentURLString: "https://example.com/permament",
            resolvedURLString: "https://example.com/permament",
            offset: 0
        )
        article.title = "title"
        article.summary = "summary"
        article.imageData = [mediumJPEGData()]
        
        return article
    }
    
    /// Forces the strategy to process the message
    func process(_ strategy: LinkPreviewAssetUploadRequestStrategy, message: ZMClientMessage) {
        strategy.contextChangeTrackers.forEach {
            $0.objectsDidChange([message])
        }
    }
        
    func encryptLinkPreview(inMessage message: ZMClientMessage) -> (Data, Data) {
        let otrKey = "1".data(using: String.Encoding.utf8, allowLossyConversion: false)!
        let sha256 = "2".data(using: String.Encoding.utf8, allowLossyConversion: false)!
        
        var linkPreview = message.genericMessage!.linkPreviews.first!
        linkPreview = linkPreview.update(withOtrKey: otrKey, sha256: sha256)
        
        message.add(ZMGenericMessage.message(content: ZMText.text(with: message.textMessageData!.messageText!, mentions: [], linkPreviews: [linkPreview]), nonce: message.nonce!, expiresAfter: message.deletionTimeout).data())
        
        return (otrKey, sha256)
    }
    
    func completeRequest(_ message: ZMClientMessage, request: ZMTransportRequest?, assetId: String, token: String) {
        let response = ZMTransportResponse(payload: ["key" : assetId, "token": token] as ZMTransportData, httpStatus: 201, transportSessionError: nil)
        _ = sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: [ZMClientMessageLinkPreviewStateKey])
    }
}

// MARK: - Tests
extension LinkPreviewAssetUploadRequestStrategyTests {
    
    func testThatItCreatesRequestForProcessedLinkPreview() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let article = self.createArticle()
            let message = self.createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
            self.syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: true, data: article.imageData.first!)
            
            self.syncMOC.saveOrRollback()
            self.process(self.sut, message: message)
            
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertNotNil(request)
            XCTAssertEqual(request?.path, "/assets/v3")
            XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodPOST)
        }
    }
    
    func testThatItDoesntCreateUnauthenticatedRequests() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let article = self.createArticle()
            let message = self.createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
            self.syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: true, data: article.imageData.first!)
            self.process(self.sut, message: message)
            self.mockApplicationStatus.mockSynchronizationState = .unauthenticated
            
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertNil(request)
        }
    }
    
    func testThatItDoesntCreateRequestsForUnprocessedLinkPreview() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let article = self.createArticle()
            let message = self.createMessage(article.permanentURL!.absoluteString, linkPreviewState: .waitingToBeProcessed, linkPreview: article)
            self.syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: true, data: article.imageData.first!)
            self.process(self.sut, message: message)
            
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertNil(request)
        }
    }
    
    func testThatItDoesntCreateRequestsForLinkPreviewStateDone() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let article = self.createArticle()
            let message = self.createMessage(article.permanentURL!.absoluteString, linkPreviewState: .done, linkPreview: article)
            self.syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: true, data: article.imageData.first!)
            self.process(self.sut, message: message)
            
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertNil(request)
        }
    }
    
    func testThatItDoesNotCreateARequestIfThereIsNoImageInTheCache() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let article = self.createArticle()
            let message = self.createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
            self.process(self.sut, message: message)
            
            // WHEN & THEN
            XCTAssertNil(self.sut.nextRequest())
        }
    }
    
    func testThatItUpdatesMessageWithAssetKeyAndToken() {
        // GIVEN
        let assetId = "id123"
        let token = "qJ8JPFLsiYGx7fnrlL+7Yk9="
        var message: ZMClientMessage! = nil
        var otrKey: Data! = nil
        var sha256: Data! = nil
        
        syncMOC.performGroupedBlock {
            let article = self.createArticle()
            message = self.createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
            let keys = self.encryptLinkPreview(inMessage: message)
            otrKey = keys.0
            sha256 = keys.1
            
            self.syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: true, data: article.imageData.first!)
            _ = self.encryptLinkPreview(inMessage: message)
            message.linkPreviewState = .waitingToBeProcessed
            self.syncMOC.saveOrRollback()
            
            self.process(self.sut, message: message)
            let request = self.sut.nextRequest()
            
            // WHEN
            self.completeRequest(message, request: request, assetId: assetId, token: token)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        syncMOC.performGroupedBlockAndWait {
            let linkPreviews = message.genericMessage!.linkPreviews
            let articleProtocol: ZMArticle = linkPreviews.first!.article
            XCTAssertEqual(articleProtocol.image.uploaded.otrKey, otrKey)
            XCTAssertEqual(articleProtocol.image.uploaded.sha256, sha256)
            XCTAssertEqual(articleProtocol.image.uploaded.assetId, assetId)
            XCTAssertEqual(articleProtocol.image.uploaded.assetToken, token)
        }
    }
    
    func testThatItUpdatesTheLinkPreviewState() {
        // GIVEN
        var message: ZMClientMessage! = nil
        
        syncMOC.performGroupedBlock {
            let article = self.createArticle()
            message = self.createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
            _ = self.encryptLinkPreview(inMessage: message)
            self.syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: true, data: article.imageData.first!)
            message.linkPreviewState = .processed
            self.syncMOC.saveOrRollback()
            
            self.process(self.sut, message: message)
            let request = self.sut.nextRequest()
            
            let assetId = "id123"
            let token = "qJ8JPFLsiYGx7fnrlL+7Yk9="
            
            // WHEN
            self.completeRequest(message, request: request, assetId: assetId, token: token)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.uploaded)
        }
    }
    
}



extension LinkPreviewAssetUploadRequestStrategyTests {
    
    func testThatItUpdatesEphemeralMessageWithAssetKeyAndToken() {
        // GIVEN
        let assetId = "id123"
        let token = "qJ8JPFLsiYGx7fnrlL+7Yk9="
        var message: ZMClientMessage! = nil
        var otrKey: Data! = nil
        var sha256: Data! = nil

        syncMOC.performGroupedBlock {
            let article = self.createArticle()
            message = self.createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article, isEphemeral : true)
            let keys = self.encryptLinkPreview(inMessage: message)
            otrKey = keys.0
            sha256 = keys.1
            
            self.syncMOC.zm_fileAssetCache.storeAssetData(message, format: .medium, encrypted: true, data: article.imageData.first!)
            _ = self.encryptLinkPreview(inMessage: message)
            message.linkPreviewState = .waitingToBeProcessed
            self.syncMOC.saveOrRollback()
            
            self.process(self.sut, message: message)
            let request = self.sut.nextRequest()
            

            
            XCTAssertTrue(message.isEphemeral)
            
            // WHEN
            self.completeRequest(message, request: request, assetId: assetId, token: token)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlock {
            // THEN
            XCTAssertTrue(message.isEphemeral)
            XCTAssertTrue(message.genericMessage!.hasEphemeral())
            XCTAssertFalse(message.genericMessage!.hasText())
            
            let linkPreviews = message.genericMessage!.linkPreviews
            let articleProtocol: ZMArticle = linkPreviews.first!.article
            XCTAssertEqual(articleProtocol.image.uploaded.otrKey, otrKey)
            XCTAssertEqual(articleProtocol.image.uploaded.sha256, sha256)
            XCTAssertEqual(articleProtocol.image.uploaded.assetId, assetId)
            XCTAssertEqual(articleProtocol.image.uploaded.assetToken, token)
        }
    }


}
