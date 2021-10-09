//

import XCTest
import WireTesting
import WireCryptobox
import WireDataModel

extension MessagingTestBase {
    
    /// Encrypts a message from the given client to the self user. 
    /// It will create a session between the two if needed
    @objc(encryptedMessageToSelfWithMessage:fromSender:)
    public func encryptedMessageToSelf(message: ZMGenericMessage, from sender: UserClient) -> Data {
        
        let selfClient = ZMUser.selfUser(in: self.syncMOC).selfClient()!
        if selfClient.user!.remoteIdentifier == nil {
            selfClient.user!.remoteIdentifier = UUID()
        }
        if selfClient.remoteIdentifier == nil {
            selfClient.remoteIdentifier = UUID.create().transportString()
        }
        
        var cypherText: Data?
        self.encryptionContext(for: sender).perform { (session) in
            if !session.hasSession(for: selfClient.sessionIdentifier!) {
                guard let lastPrekey = try? selfClient.keysStore.lastPreKey() else {
                    fatalError("Can't get prekey for self user")
                }
                try! session.createClientSession(selfClient.sessionIdentifier!, base64PreKeyString: lastPrekey)
            }
            
            do {
                cypherText = try session.encrypt(message.data(), for: selfClient.sessionIdentifier!)
            } catch {
                fatalError("Error in encrypting: \(error)")
            }
        }
        return cypherText!
    }
    
    /// Creates a session between the self client to the given user, if it does not 
    /// exists already
    @objc(establishSessionFromSelfToClient:)
    public func establishSessionFromSelf(to client: UserClient) {
        
        // this makes sure the client has remote identifier
        _ = self.encryptionContext(for: client)
        
        if client.hasSessionWithSelfClient {
            // done!
            return
        }
        
        let selfClient = ZMUser.selfUser(in: self.syncMOC).selfClient()!
        var prekey: String?
        self.encryptionContext(for: client).perform { (session) in
            prekey = try! session.generateLastPrekey()
        }
        
        selfClient.keysStore.encryptionContext.perform { (session) in
            try! session.createClientSession(client.sessionIdentifier!, base64PreKeyString: prekey!)
        }
    }
    
    /// Decrypts a message that was sent from self to a given user
    public func decryptMessageFromSelf(cypherText: Data, to client: UserClient) -> Data? {
        
        let selfClient = ZMUser.selfUser(in: self.syncMOC).selfClient()!
        var plainText: Data?
        self.encryptionContext(for: client).perform { (session) in
            if session.hasSession(for: selfClient.sessionIdentifier!) {
                do {
                    plainText = try session.decrypt(cypherText, from: selfClient.sessionIdentifier!)
                } catch {
                    XCTFail("Decryption error: \(error)")
                }
            } else {
                do {
                    plainText = try session.createClientSessionAndReturnPlaintext(for: selfClient.sessionIdentifier!, prekeyMessage: cypherText)
                } catch {
                    XCTFail("Decryption error: \(error)")
                }
            }
        }
        return plainText
    }
}


extension MessagingTestBase {

    /// Delete all other clients encryption contexts
    func deleteAllOtherEncryptionContexts() {
        try? FileManager.default.removeItem(at: self.otherClientsEncryptionContextsURL)
    }
    
    /// Returns the folder where the encryption contexts for other test clients are stored
    var otherClientsEncryptionContextsURL: URL {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("OtherClients")
    }
    
    /// Returns the encryption context to use for a given client. There are extra cryptobox sessions
    /// that simulate a remote client able to decrypt/encrypt data with its own cryptobox instance.
    /// If the client has no remote identifier, it will create one
    fileprivate func encryptionContext(for client: UserClient) -> EncryptionContext {
        if client.remoteIdentifier == nil {
            client.remoteIdentifier = UUID.create().transportString()
        }
        let url =  self.otherClientsEncryptionContextsURL.appendingPathComponent("client-\(client.remoteIdentifier!)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [:])
        let encryptionContext = EncryptionContext(path: url)
        return encryptionContext
    }
}
