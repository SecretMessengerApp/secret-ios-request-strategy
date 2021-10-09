//
//

#import <Foundation/Foundation.h>
#import <WireRequestStrategy/WireRequestStrategy-Swift.h>
#import "ZMAbstractRequestStrategy.h"

static NSString* ZMLogTag ZM_UNUSED = @"Request Configuration";

@implementation ZMAbstractRequestStrategy

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext applicationStatus:(id<ZMApplicationStatus>)applicationStatus
{
    self = [super init];
    
    if (self != nil) {
        _managedObjectContext = managedObjectContext;
        _applicationStatus = applicationStatus;
    }
    
    return self;
}

/// Subclasses should override this method
- (ZMTransportRequest *)nextRequestIfAllowed
{
    [NSException raise:NSInvalidArgumentException format:@"You must subclass nextRequestIfAllowed"];
    return nil;
}

- (ZMTransportRequest *)nextRequest
{
    if ([self configuration:self.configuration isSubsetOfPrerequisites:[AbstractRequestStrategy prerequisitesForApplicationStatus:self.applicationStatus]]) {
        return [self nextRequestIfAllowed];
    }
    
    return nil;
}

- (BOOL)configuration:(ZMStrategyConfigurationOption)configuration isSubsetOfPrerequisites:(ZMStrategyConfigurationOption)prerequisites
{
    ZMStrategyConfigurationOption option = 0;
    
    for (NSUInteger index = 0; option <= ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing; index++) {
        option = 1 << index;
        
        if ((prerequisites & option) == option && (configuration & option) != option) {
            ZMLogDebug(@"Not performing requests since option: %lu is not configured for (%@)", (unsigned long)option, NSStringFromClass(self.class));
            return NO;
        }
    }
    
    return YES;
}

@end
