//

import XCTest
@testable import WireRequestStrategy

class AssetsPreprocessorTests: MessagingTestBase {
    
    var sut: AssetsPreprocessor!
    var conversation: ZMConversation!
    
    override func setUp() {
        super.setUp()
        
        sut = AssetsPreprocessor(managedObjectContext: uiMOC)
        conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.remoteIdentifier = UUID()
    }
    
    override func tearDown() {
        sut = nil
        conversation = nil
        
        super.tearDown()
    }

    func testThatItPreprocessAssetMessage() {
        // given
        let message = conversation.append(imageFromData: verySmallJPEGData()) as! ZMAssetClientMessage
        let asset = message.assets.first!
        
        // when
        sut.objectsDidChange(Set(arrayLiteral: message))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(asset.hasEncrypted)
        XCTAssertTrue(asset.hasPreprocessed)
    }
    
    func testThatItPreprocessAssetMessageWithMultipleAssets() {
        // given
        let message = conversation.append(file: ZMVideoMetadata(fileURL: self.fileURL(forResource: "video", extension: "mp4"), thumbnail: self.verySmallJPEGData())) as! ZMAssetClientMessage
        let assets = message.assets
        XCTAssertEqual(assets.count, 2)
        
        // when
        sut.objectsDidChange(Set(arrayLiteral: message))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        for asset in assets {
            XCTAssertTrue(asset.hasEncrypted)
            
            if asset.needsPreprocessing {
                XCTAssertTrue(asset.hasPreprocessed)
            }
        }
    }
    
    func testThatItMarksTheTransferStateAsModifiedAfterItsDoneProcessing() {
        // given
        let message = conversation.append(imageFromData: verySmallJPEGData()) as! ZMAssetClientMessage
        
        // when
        sut.objectsDidChange(Set(arrayLiteral: message))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(message.modifiedKeys!.contains(#keyPath(ZMAssetClientMessage.transferState)))
    }
    
}
