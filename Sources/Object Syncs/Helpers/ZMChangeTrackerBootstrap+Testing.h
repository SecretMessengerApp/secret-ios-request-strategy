// 


#import "ZMChangeTrackerBootstrap.h"
@protocol ZMContextChangeTracker;

@interface ZMChangeTrackerBootstrap ()

- (NSMapTable *)sortFetchRequestsByEntity:(NSArray *)fetchRequests;
- (NSMapTable *)executeMappedFetchRequests:(NSMapTable *)entityToRequestsMap;
- (NSEntityDescription *)entityForEntityName:(NSString *)name;

@end

@interface ZMChangeTrackerBootstrap (Testing)

+ (void)bootStrapChangeTrackers:(NSArray *)changeTrackers onContext:(NSManagedObjectContext *)context;

@end
