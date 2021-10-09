//
//

import Foundation

open class OTREntityTranscoder<Entity : OTREntity & Hashable> : NSObject, EntityTranscoder {
    
    let context : NSManagedObjectContext
    let clientRegistrationDelegate : ClientRegistrationDelegate
    
    public init(context: NSManagedObjectContext, clientRegistrationDelegate : ClientRegistrationDelegate) {
        self.context = context
        self.clientRegistrationDelegate = clientRegistrationDelegate
    }
    
    open func request(forEntity entity: Entity) -> ZMTransportRequest? {
        return nil
    }
    
    /// If you override this method in your subclass you must call super.
    open func request(forEntity entity: Entity, didCompleteWithResponse response: ZMTransportResponse) {
         _ = entity.parseUploadResponse(response, clientRegistrationDelegate: self.clientRegistrationDelegate)
    }
    
    /// If you override this method in your subclass you must call super.
    open func shouldTryToResend(entity: Entity, afterFailureWithResponse response: ZMTransportResponse) -> Bool {
        return entity.parseUploadResponse(response, clientRegistrationDelegate: self.clientRegistrationDelegate).contains(.missing)
    }
    
}
