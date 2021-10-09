// 


@import Foundation;



/// This class will combine all fetch requests from all change trackers' -fetchRequestForTrackedObjects and pass the result to their -addTrackedObjects:
/// This allows us to do fewer fetch requests during app launch.
@interface ZMChangeTrackerBootstrap : NSObject

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)context changeTrackers:(NSArray *)changeTrackers;

- (void)fetchObjectsForChangeTrackers;

@end


@interface ZMMessageChangeTrackerBootstrap : NSObject

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)context changeTrackers:(NSArray *)changeTrackers;

- (void)fetchObjectsForChangeTrackers;

@end
