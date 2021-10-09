//

import XCTest
@testable import WireRequestStrategy

class AssetV3UploadRequestStrategyTests: MessagingTestBase {
    
    var sut: AssetV3UploadRequestStrategy!
    var mockApplicationStatus: MockApplicationStatus!

    override func setUp() {
        super.setUp()
        
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing
        sut = AssetV3UploadRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: mockApplicationStatus)
    }

    override func tearDown() {
        
        sut = nil
        mockApplicationStatus = nil
        
        super.tearDown()
    }
    
    // MARK: - Helpers
    
    @discardableResult func createFileMessage(transferState: AssetTransferState = .uploading, hasCompletedPreprocessing: Bool = true,  line: UInt = #line) -> ZMAssetClientMessage {
        let targetConversation = groupConversation!
        let url = Bundle(for: AssetClientMessageRequestStrategyTests.self).url(forResource: "Lorem Ipsum", withExtension: "txt")!
        let message = targetConversation.append(file: ZMFileMetadata(fileURL: url, thumbnail: verySmallJPEGData())) as! ZMAssetClientMessage
        message.updateTransferState(transferState, synchronize: true)
        
        if hasCompletedPreprocessing {
            for asset in message.assets {
                if asset.needsPreprocessing {
                    asset.updateWithPreprocessedData(verySmallJPEGData(), imageProperties: ZMIImageProperties(size: CGSize(width: 100, height: 100), length: 100, mimeType: "image/jpeg"))
                }
                asset.encrypt()
            }
        }
        
        syncMOC.saveOrRollback()
        
        return message
    }
    
    @discardableResult func createImageMessage(transferState: AssetTransferState = .uploading, line: UInt = #line) -> ZMAssetClientMessage {
        let targetConversation = groupConversation!
        let message = targetConversation.append(imageFromData: verySmallJPEGData()) as! ZMAssetClientMessage
        message.updateTransferState(transferState, synchronize: true)
        
        for asset in message.assets {
            if asset.needsPreprocessing {
                asset.updateWithPreprocessedData(verySmallJPEGData(), imageProperties: ZMIImageProperties(size: CGSize(width: 100, height: 100), length: 100, mimeType: "image/jpeg"))
            }
            asset.encrypt()
        }
        
        syncMOC.saveOrRollback()
        
        return message
    }
    
    // MARK: - Request generation
    
    func testThatItGeneratesRequestWhenAssetIsPreprocessed() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let message = self.createFileMessage()
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNotNil(request)
        }
    }
    
    func testThatItDoesNotGenerateRequestForVersion2Assets() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let message = self.createFileMessage()
            message.version = 2
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItDoesNotGenerateRequestForDeliveredMessages() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let message = self.createFileMessage()
            message.delivered = true
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItDoesNotGenerateRequestWhilePreprocessingIsNotCompleted() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let message = self.createFileMessage(hasCompletedPreprocessing: false)
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItDoesNotGenerateRequestWhenTransferStateIsNotUploading() {
        let allTransferStatesExpectUploading: [AssetTransferState] = [.uploaded, .uploadingFailed, .uploadingCancelled]
        
        allTransferStatesExpectUploading.forEach { transferState in
            syncMOC.performGroupedBlockAndWait {
                // given
                let message = self.createFileMessage(transferState: transferState)
                self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
                
                // when
                let request = self.sut.nextRequest()
                
                // then
                XCTAssertNil(request)
            }
        }
    }
    
    // MARK: - Request cancellation
    
    func testThatItCancelsRequest_WhenTransferStateChangesToUploadingCancelled() {
        let expectedIdentifier: UInt = 42
        var message: ZMAssetClientMessage!
        syncMOC.performGroupedBlockAndWait {
            // given
            message = self.createFileMessage()
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            request.callTaskCreationHandlers(withIdentifier: expectedIdentifier, sessionIdentifier: self.name)
        }
        
        self.syncMOC.performGroupedBlock {
            // when
            message.fileMessageData?.cancelTransfer()
            self.sut.objectsDidChange(Set(arrayLiteral: message)) // this would be called after a save
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // then - the cancellation provider should be informed to cancel the request
            let cancelledIdentifier = self.mockApplicationStatus.cancelledIdentifiers.first
            XCTAssertEqual(self.mockApplicationStatus.cancelledIdentifiers.count, 1)
            XCTAssertEqual(cancelledIdentifier?.identifier, expectedIdentifier)
            XCTAssertNil(message.associatedTaskIdentifier, "Should nil-out the identifier after it has been cancelled")
        }
    }
    
    // MARK: - Response handling
    
    func testThatItUpdatesUploadProgress() {
        let expectedProgress: Float = 0.5
        var message: ZMAssetClientMessage!
        syncMOC.performGroupedBlockAndWait {
            // given
            message = self.createFileMessage()
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            let request = self.sut.nextRequest()
            
            // when
            request?.updateProgress(expectedProgress)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            // then
            XCTAssertEqual(message.progress, expectedProgress)
        }
    }
    
    func testThatItUpdatesTransferState_OnSuccessfulResponse() {
        var message: ZMAssetClientMessage!
        syncMOC.performGroupedBlockAndWait {
            // given
            message = self.createImageMessage()
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            let request = self.sut.nextRequest()
            
            // when
            request?.complete(with: ZMTransportResponse(payload: ["key": "asset-id-123"] as ZMTransportData, httpStatus: 201, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(message.transferState, .uploaded)
        }
    }
    
    func testThatItDoesNotUpdateTransferState_OnSuccessfulResponse_WhenThereIsMoreAssetsToUpload() {
        var message: ZMAssetClientMessage!
        syncMOC.performGroupedBlockAndWait {
            // given
            message = self.createFileMessage() // has two assets (file and thumbnail)
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            let request = self.sut.nextRequest()
            
            // when
            request?.complete(with: ZMTransportResponse(payload: ["key": "asset-id-123"] as ZMTransportData, httpStatus: 201, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(message.transferState, .uploading)
        }
    }
    
    func testThatItAddsAssetId_OnSuccessfulResponse() {
        let expectedAssetId = "asset-id-123"
        var message: ZMAssetClientMessage!
        syncMOC.performGroupedBlockAndWait {
            // given
            message = self.createImageMessage()
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            let request = self.sut.nextRequest()
            
            // when
            request?.complete(with: ZMTransportResponse(payload: ["key": expectedAssetId] as ZMTransportData, httpStatus: 201, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(message?.genericMessage?.assetData?.uploaded?.assetId, expectedAssetId)
        }
    }
    
    func testThatItExpiresTheMessage_OnPermanentFailureResponse() {
        var message: ZMAssetClientMessage!
        syncMOC.performGroupedBlockAndWait {
            // given
            message = self.createImageMessage()
            self.sut.upstreamSync?.objectsDidChange(Set(arrayLiteral: message))
            let request = self.sut.nextRequest()
            
            // when
            request?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(message.isExpired)
            XCTAssertEqual(message.transferState, .uploadingFailed)
        }
    }

}
