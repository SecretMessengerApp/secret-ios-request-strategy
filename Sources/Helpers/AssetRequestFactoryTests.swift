//
//

import WireTesting
@testable import WireRequestStrategy

class AssetRequestFactoryTests: ZMTBaseTest {
    
    var testSession: ZMTestSession!
    
    override func setUp() {
        super.setUp()
        self.testSession = ZMTestSession(dispatchGroup: self.dispatchGroup)
        self.testSession.prepare(forTestNamed: self.name)
    }
    
    override func tearDown() {
        XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        self.testSession.tearDown()
        self.testSession = nil
        super.tearDown()
    }
 
    func testThatItReturnsExpiringForRegularConversation() {
        // given
        let conversation = ZMConversation.insertNewObject(in: testSession.uiMOC)
        
        // when & then
        XCTAssertEqual(AssetRequestFactory.Retention(conversation: conversation), .expiring)
    }
    
    func testThatItReturnsEternalInfrequentAccessForTeamUserConversation() {
        guard let moc = testSession.syncMOC else { return XCTFail() }
        moc.performGroupedBlock {
            // given
            let conversation = ZMConversation.insertNewObject(in: moc)
            let team = Team.insertNewObject(in: moc)
            team.remoteIdentifier = .init()
            
            // when
            let selfUser = ZMUser.selfUser(in: moc)
            let membership = Member.getOrCreateMember(for: selfUser, in: team, context: moc)
            XCTAssertNotNil(membership.team)
            XCTAssertTrue(selfUser.hasTeam)
            
            // then
            XCTAssertEqual(AssetRequestFactory.Retention(conversation: conversation), .eternalInfrequentAccess)
        }
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }
    
    func testThatItReturnsEternalInfrequentAccessForConversationWithTeam() {
        guard let moc = testSession.syncMOC else { return XCTFail() }
        moc.performGroupedBlock {
            // given
            let conversation = ZMConversation.insertNewObject(in: moc)
            
            // when
            conversation.team = .insertNewObject(in: moc)
            conversation.team?.remoteIdentifier = .init()
        
            // then
            XCTAssert(conversation.hasTeam)
            XCTAssertEqual(AssetRequestFactory.Retention(conversation: conversation), .eternalInfrequentAccess)
        }
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }
    
    func testThatItReturnsEternalInfrequentAccessForAConversationWithAParticipantsWithTeam() {
        guard let moc = testSession.syncMOC else { return XCTFail() }
        moc.performGroupedBlock {
            // given
            let user = ZMUser.insertNewObject(in: moc)
            user.remoteIdentifier = UUID()
            user.teamIdentifier = .init()
            
            // when
            guard let conversation = ZMConversation.insertGroupConversation(into: moc, withParticipants: [user]) else { return XCTFail("no conversation") }
            
            // then
            XCTAssert(conversation.containsTeamUser)
            XCTAssertEqual(AssetRequestFactory.Retention(conversation: conversation), .eternalInfrequentAccess)
        }
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }
}
