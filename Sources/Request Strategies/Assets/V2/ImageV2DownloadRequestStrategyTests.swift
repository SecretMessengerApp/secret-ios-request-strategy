//
//

import Foundation
@testable import WireRequestStrategy
import XCTest
import WireDataModel

class ImageV2DownloadRequestStrategyTests: MessagingTestBase {
    
    fileprivate var applicationStatus: MockApplicationStatus!
    
    fileprivate var sut: ImageV2DownloadRequestStrategy!
    
    override func setUp() {
        super.setUp()
        applicationStatus = MockApplicationStatus()
        applicationStatus.mockSynchronizationState = .eventProcessing
        sut = ImageV2DownloadRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: applicationStatus)
    }
    
    override func tearDown() {
        super.tearDown()
        applicationStatus = nil
        sut = nil
    }
    
    // MARK: Helpers
    
    func createV2ImageMessage(withAssetId assetId: UUID?) -> (ZMAssetClientMessage, Data) {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = UUID.create()
        
        let sender = ZMUser.insertNewObject(in: syncMOC)
        sender.remoteIdentifier = UUID.create()
        
        let message = ZMAssetClientMessage(nonce: UUID(), managedObjectContext: syncMOC)
        let imageData = verySmallJPEGData() // message.imageAssetStorage.originalImageData()
        let imageSize = ZMImagePreprocessor.sizeOfPrerotatedImage(with: imageData)
        let properties = ZMIImageProperties(size: imageSize, length: UInt(imageData.count), mimeType: "image/jpeg")
        let key = Data.randomEncryptionKey()
        let encryptedData = imageData.zmEncryptPrefixingPlainTextIV(key: key)
        let sha = encryptedData.zmSHA256Digest()
        let keys = ZMImageAssetEncryptionKeys(otrKey: key, sha256: sha)
        
        message.add(ZMGenericMessage.message(content: ZMImageAsset(mediumProperties: properties, processedProperties: properties, encryptionKeys: keys, format: .medium), nonce: message.nonce!))
        message.add(ZMGenericMessage.message(content: ZMImageAsset(mediumProperties: properties, processedProperties: properties, encryptionKeys: keys, format: .preview), nonce: message.nonce!))
        message.version = 2
        message.assetId = assetId
        message.sender = sender
        conversation.append(message)
        syncMOC.saveOrRollback()
        
        return (message, encryptedData)
    }
    
    func createFileMessage() -> ZMAssetClientMessage {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = UUID.create()
        
        let nonce = UUID.create()
        let fileURL = Bundle(for: ImageV2DownloadRequestStrategyTests.self).url(forResource: "Lorem Ipsum", withExtension: "txt")!
        let metadata = ZMFileMetadata(fileURL: fileURL)
        let message = conversation.append(file: metadata, nonce: nonce) as! ZMAssetClientMessage
        
        syncMOC.saveOrRollback()
        
        return message
    }
    
    func requestToDownloadAsset(withMessage message: ZMAssetClientMessage) -> ZMTransportRequest {
        // remove image data or it won't be downloaded
        syncMOC.zm_fileAssetCache.deleteAssetData(message, format: .original, encrypted: false)
        message.imageMessageData?.requestFileDownload()
        return sut.nextRequest()!
    }
    
    // MARK: - Request Generation
    
    func testRequestToDownloadAssetIsCreated() {
        // GIVEN
        var message: ZMAssetClientMessage!
        self.syncMOC.performGroupedBlock {
            message = self.createV2ImageMessage(withAssetId: UUID()).0
            
            // remove image data or it won't be downloaded
            self.syncMOC.zm_fileAssetCache.deleteAssetData(message, format: .original, encrypted: false)
            message.imageMessageData?.requestFileDownload()
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertEqual(request?.path, "/conversations/\(message.conversation!.remoteIdentifier!.transportString())/otr/assets/\(message.assetId!.transportString())")
        }
    }
    
    func testRequestToDownloadAssetIsNotCreated_WhenAssetIdIsNotAvailable() {
        // GIVEN
        self.syncMOC.performGroupedBlock {
            let (message, _) = self.createV2ImageMessage(withAssetId: nil)
            
            // remove image data or it won't be downloaded
            self.syncMOC.zm_fileAssetCache.deleteAssetData(message, format: .original, encrypted: false)
            message.imageMessageData?.requestFileDownload()
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertNil(request)
        }
    }
    
    func testRequestToDownloadFileAssetIsNotCreated_BeforeRequestingDownloaded() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let (message, _) = self.createV2ImageMessage(withAssetId: nil)
            
            // remove image data or it won't be downloaded
            self.syncMOC.zm_fileAssetCache.deleteAssetData(message, format: .original, encrypted: false)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertNil(request)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testRequestToDownloadFileAssetIsNotCreated_WhenAlreadyDownloaded() {
        syncMOC.performGroupedBlock {
            // GIVEN
            let (message, _) = self.createV2ImageMessage(withAssetId: nil)
            message.imageMessageData?.requestFileDownload()
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            // WHEN
            let request = self.sut.nextRequest()
            
            // THEN
            XCTAssertNil(request)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    // MARK: - Response Handling
    
    func testThatMessageIsDeleted_WhenResponseSaysItDoesntExistOnBackend() {
        let (nonce, conversation) = syncMOC.performGroupedAndWait { moc -> (UUID, ZMConversation) in
            // GIVEN
            let (message, _) = self.createV2ImageMessage(withAssetId: UUID.create())
            let nonceAndConversation = (message.nonce!, message.conversation!)
            
            // WHEN
            let response = ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)
            self.sut.delete(message, with: response, downstreamSync: nil)
            
            // THEN
            XCTAssert(message.isDeleted)
            return nonceAndConversation
        }
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedAndWait { moc in
            // GIVEN
            let message = ZMMessage.fetch(withNonce: nonce, for: conversation, in: moc, prefetchResult: nil)
            
            // THEN
            XCTAssertNil(message)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testThatMessageIsStored_OnSuccessResponse() {
        // GIVEN
        var message: ZMAssetClientMessage!
        var encryptedData: Data!
        self.syncMOC.performGroupedBlock {
            let messageAndEncryptedData = self.createV2ImageMessage(withAssetId: UUID())
            message = messageAndEncryptedData.0
            encryptedData = messageAndEncryptedData.1
            
            // remove image data or it won't be downloaded
            self.syncMOC.zm_fileAssetCache.deleteAssetData(message, format: .original, encrypted: false)
            message.imageMessageData?.requestFileDownload()
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlock {
            // WHEN
            let request = self.sut.nextRequest()
            request?.complete(with: ZMTransportResponse(imageData: encryptedData, httpStatus: 200, transportSessionError: nil, headers: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            // THEN
            XCTAssertTrue(message.hasDownloadedFile)
        }
    }
    
}
