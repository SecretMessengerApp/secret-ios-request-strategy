//
//


@class NSFetchRequest;


NS_ASSUME_NONNULL_BEGIN
@protocol ZMContextChangeTracker <NSObject>

- (void)objectsDidChange:(NSSet<NSManagedObject *> *)object;

/// Returns the fetch request to retrieve the initial set of objects.
///
/// During app launch this fetch request is executed and the resulting objects are passed to -addTrackedObjects:
- (nullable NSFetchRequest *)fetchRequestForTrackedObjects;
/// Adds tracked objects -- which have been retrieved by using the fetch request returned by -fetchRequestForTrackedObjects
- (void)addTrackedObjects:(NSSet<NSManagedObject *> *)objects;

@end



@protocol ZMContextChangeTrackerSource <NSObject>

@property (nonatomic, readonly) NSArray< id<ZMContextChangeTracker> > *contextChangeTrackers; /// Array of ZMContextChangeTracker

@end
NS_ASSUME_NONNULL_END
