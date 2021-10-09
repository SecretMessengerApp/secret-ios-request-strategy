//
//

@import Foundation;

#import "ZMStrategyConfigurationOption.h"
#import "RequestStrategy.h"

@class ZMTransportRequest;
@class NSManagedObjectContext;
@protocol ZMApplicationStatus;

@interface ZMAbstractRequestStrategy : NSObject <RequestStrategy>

@property (nonatomic, readonly, nonnull) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, readonly) ZMStrategyConfigurationOption configuration;
@property (nonatomic, readonly, nonnull) id<ZMApplicationStatus> applicationStatus;

- (instancetype _Nonnull)initWithManagedObjectContext:(nonnull NSManagedObjectContext *)managedObjectContext applicationStatus:(_Nullable id<ZMApplicationStatus>)applicationStatus;

- (ZMTransportRequest * _Nullable)nextRequestIfAllowed;

@end
