//
//

import Foundation
import WireRequestStrategy
import XCTest
import WireDataModel


extension ZMContextChangeTrackerSource {
    func notifyChangeTrackers(_ client : UserClient) {
        contextChangeTrackers.forEach{$0.objectsDidChange(Set(arrayLiteral:client))}
    }
}

