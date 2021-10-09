// 


#import "ZMImagePreprocessingTracker.h"

@class ZMAssetsPreprocessor;

@interface ZMImagePreprocessingTracker ()

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                        imageProcessingQueue:(NSOperationQueue *)imageProcessingQueue
                              fetchPredicate:(NSPredicate *)fetchPredicate
                    needsProcessingPredicate:(NSPredicate *)needsProcessingPredicate
                                 entityClass:(Class)entityClass
                                preprocessor:(ZMAssetsPreprocessor *)preprocessor;

@property (nonatomic, readonly) NSMutableOrderedSet *imageOwnersThatNeedPreprocessing;
@property (nonatomic, readonly) NSMutableSet *imageOwnersBeingPreprocessed;

@end

