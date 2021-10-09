//
//


public extension Array where Element == ZMRequestGenerator {

    func nextRequest() -> ZMTransportRequest? {
        return (self as NSArray).nextRequest()
    }

}
