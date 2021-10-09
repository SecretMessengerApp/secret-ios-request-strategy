//

import Foundation
import WireTesting
import XCTest
import WireRequestStrategy

class DependentObjectsTests: ZMTBaseTest {
    
    var testSession: ZMTestSession!
    var sut: DependentObjects<ZMManagedObject, ZMConversation>!
    var conversation1: ZMConversation!
    var conversation2: ZMConversation!
    var messageA: ZMClientMessage!
    var messageB: ZMClientMessage!
    var messageC: ZMClientMessage!
    
    override func setUp() {
        super.setUp()
        self.sut = DependentObjects()
        self.testSession = ZMTestSession(dispatchGroup: self.dispatchGroup)
        self.testSession.prepare(forTestNamed: self.name)
        self.conversation1 = ZMConversation.insertNewObject(in: self.testSession.uiMOC)
        self.conversation2 = ZMConversation.insertNewObject(in: self.testSession.uiMOC)
        self.messageA = ZMClientMessage(nonce: UUID(), managedObjectContext: self.testSession.uiMOC)
        self.messageB = ZMClientMessage(nonce: UUID(), managedObjectContext: self.testSession.uiMOC)
        self.messageC = ZMClientMessage(nonce: UUID(), managedObjectContext: self.testSession.uiMOC)
    }
    
    override func tearDown() {
        self.sut = nil
        self.testSession.tearDown()
        self.testSession = nil
        super.tearDown()
    }

    
    func testThatItEnumeratesAllObjectsInTheOrderTheyWereAdded() {
        // GIVEN
        let messages = [self.messageA, self.messageB, self.messageC].compactMap { $0 }
        messages.forEach {
            self.sut.add(dependency: self.conversation1!, for: $0)
        }
    
        // WHEN
        var result = [ZMClientMessage]()
        self.sut.enumerateAndRemoveObjects(for: self.conversation1!) { (mo) -> Bool in
            result.append(mo as! ZMClientMessage)
            return true
        }
        
        // THEN
        XCTAssertEqual(Set(messages), Set(result))
    }

    func testThatItOnlyReturnsAnObjectOnceWhenItIsAddedMultipleTimes() {
        // GIVEN
        let messages = [self.messageA!, self.messageA!, self.messageA!]
        messages.forEach {
            self.sut.add(dependency: self.conversation1!, for: $0)
        }
        
        // WHEN
        var result = [ZMClientMessage]()
        self.sut.enumerateAndRemoveObjects(for: self.conversation1!) { (mo) -> Bool in
            result.append(mo as! ZMClientMessage)
            return true
        }
        
        // THEN
        XCTAssertEqual(result, [self.messageA])
    }

    func testThatItEnumeratesAllObjectsAgainIfTheyWereNotToBeRemoved() {
        // GIVEN
        let messages = [self.messageA!, self.messageB!, self.messageC!]
        messages.forEach {
            self.sut.add(dependency: self.conversation1!, for: $0)
        }

        
        // WHEN
        self.sut.enumerateAndRemoveObjects(for: self.conversation1!) { _ in
            return false
        }
        
        // THEN
        var result = [ZMClientMessage]()
        self.sut.enumerateAndRemoveObjects(for: self.conversation1!) { (mo) -> Bool in
            result.append(mo as! ZMClientMessage)
            return true
        }
        XCTAssertEqual(Set(messages), Set(result))
    }
    
    func testThatItRemovesObjects() {
        
        // GIVEN
        let messages = [self.messageA!, self.messageB!, self.messageC!]
        messages.forEach {
            self.sut.add(dependency: self.conversation1!, for: $0)
        }
        
        // WHEN
        self.sut.enumerateAndRemoveObjects(for: self.conversation1!) {
            $0 == self.messageA!
        }
        
        // THEN
        var result = [ZMClientMessage]()
        self.sut.enumerateAndRemoveObjects(for: self.conversation1!) { (mo) -> Bool in
            result.append(mo as! ZMClientMessage)
            return true
        }
        XCTAssertEqual(Set([self.messageB!, self.messageC!]), Set(result))
    }
    
    func testThatItEnumeratesObjectsForTheCorrectDependency() {
        // GIVEN
        self.sut.add(dependency: self.conversation2!, for: self.messageA!)
        self.sut.add(dependency: self.conversation1!, for: self.messageB!)
        self.sut.add(dependency: self.conversation2!, for: self.messageC!)
        
        // WHEN
        var result1 = [ZMClientMessage]()
        self.sut.enumerateAndRemoveObjects(for: self.conversation1!) { (mo) -> Bool in
            result1.append(mo as! ZMClientMessage)
            return true
        }
        
        var result2 = [ZMClientMessage]()
        self.sut.enumerateAndRemoveObjects(for: self.conversation2!) { (mo) -> Bool in
            result2.append(mo as! ZMClientMessage)
            return true
        }
        // THEN
        XCTAssertEqual([self.messageB!], result1)
        XCTAssertEqual(Set([self.messageA!, self.messageC!]), Set(result2))

    }
    
    func testThatItReturnsAllDependenciesForAnObject() {
        // GIVEN
        self.sut.add(dependency: self.conversation2!, for: self.messageA!)
        self.sut.add(dependency: self.conversation1!, for: self.messageB!)
        self.sut.add(dependency: self.conversation2!, for: self.messageB!)
        
        // WHEN
        let dependenciesB = self.sut.dependencies(for: self.messageB!)
        let dependenciesA = self.sut.dependencies(for: self.messageA!)
        
        // THEN
        XCTAssertEqual(Set([self.conversation1!, self.conversation2!]), dependenciesB)
        XCTAssertEqual(Set([self.conversation2!]), dependenciesA)
    }
    
    func testThatItReturnsAllDependentsOnADependency() {
        // GIVEN
        self.sut.add(dependency: self.conversation2!, for: self.messageA!)
        self.sut.add(dependency: self.conversation1!, for: self.messageB!)
        self.sut.add(dependency: self.conversation2!, for: self.messageB!)
        
        // WHEN
        let dependents = self.sut.dependents(on: self.conversation1!)
        
        // THEN
        XCTAssertEqual(Set([self.messageB!]), dependents)
    }
    
    func testThatItDoesNotEnumerateWhenNoObjectsAreAdded() {
        self.sut.enumerateAndRemoveObjects(for: self.conversation1!) { (mo) -> Bool in
            XCTFail()
            return true
        }
    }
    
    func testThatItRemovesDependencies() {
        
        // GIVEN
        self.sut.add(dependency: self.conversation2!, for: self.messageA!)
        self.sut.add(dependency: self.conversation1!, for: self.messageB!)
        self.sut.add(dependency: self.conversation2!, for: self.messageB!)
        
        // WHEN
        self.sut.remove(dependency: self.conversation1!, for: self.messageB!)
        
        // THEN
        XCTAssertTrue(self.sut.dependents(on: self.conversation1!).isEmpty)
        XCTAssertEqual(self.sut.dependencies(for: self.messageB!), Set([self.conversation2!]))
    }
    
    func testThatItReturnsNoObjectForDepedency() {
        XCTAssertNil(self.sut.anyDependency(for: self.conversation1!))
    }
    
    func testThatItReturnsOneObjectForDependency() {
        
        // GIVEN
        self.sut.add(dependency: self.conversation2!, for: self.messageA!)
        self.sut.add(dependency: self.conversation1!, for: self.messageB)
        
        // WHEN
        let result = self.sut.anyDependency(for: self.messageB!)
        
        // THEN
        XCTAssertEqual(result, self.conversation1!)
        
    }
}

