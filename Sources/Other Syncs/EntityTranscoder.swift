//
//

import Foundation

public protocol EntityTranscoder : class {
    associatedtype Entity: Hashable
    
    func request(forEntity entity: Entity) -> ZMTransportRequest?
    
    func request(forEntity entity: Entity, didCompleteWithResponse response: ZMTransportResponse)
    
    func shouldTryToResend(entity: Entity, afterFailureWithResponse response: ZMTransportResponse) -> Bool
    
}
