//
//

import Foundation

private let zmLog = ZMSLog(tag: "Request Configuration")

@objcMembers open class AbstractRequestStrategy : NSObject, RequestStrategy {
    
    weak public var applicationStatus : ApplicationStatus?
    
    public let managedObjectContext : NSManagedObjectContext
    public var configuration : ZMStrategyConfigurationOption =
        [.allowsRequestsDuringSync,
         .allowsRequestsDuringEventProcessing,.allowsRequestsDuringNotificationStreamFetch]
    
    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus?) {
        self.managedObjectContext = managedObjectContext
        self.applicationStatus = applicationStatus
        
        super.init()
    }
    
    /// Subclasses should override this method. 
    open func nextRequestIfAllowed() -> ZMTransportRequest? {
        fatal("you must override this method")
    }
    
    open func nextRequest() -> ZMTransportRequest? {
        guard let applicationStatus = self.applicationStatus else {
            zmLog.error("applicationStatus is missing")
            return nil
        }
        
        let prerequisites = AbstractRequestStrategy.prerequisites(forApplicationStatus: applicationStatus)
        
        if prerequisites.isSubset(of: configuration) {
            return nextRequestIfAllowed()
        } else {
            zmLog.debug("Not performing requests since option: \(prerequisites.subtracting(configuration)) is not configured for (\(String(describing: type(of: self))))")
        }
        
        return nil
    }
    
    public class func prerequisites(forApplicationStatus applicationStatus: ApplicationStatus) -> ZMStrategyConfigurationOption {
        var prerequisites : ZMStrategyConfigurationOption = []
        
        if applicationStatus.synchronizationState == .unauthenticated {
            prerequisites.insert(.allowsRequestsWhileUnauthenticated)
        }
        
        if applicationStatus.synchronizationState == .synchronizing {
            prerequisites.insert(.allowsRequestsDuringSync)
        }
        
        if applicationStatus.synchronizationState == .eventProcessing {
            prerequisites.insert(.allowsRequestsDuringEventProcessing)
        }
        
        if applicationStatus.operationState == .background {
            prerequisites.insert(.allowsRequestsWhileInBackground)
        }

        if applicationStatus.notificationFetchStatus == .inProgress {
            // Don't create requests while we are still fetching the notification stream in the background.
            // Otherwise we risk already sending out OTR messages when we have to fetch
            // multiple pages of the stream (in case we have been offline for a while).
            prerequisites.insert(.allowsRequestsDuringNotificationStreamFetch)
        }

        return prerequisites
    }

}
