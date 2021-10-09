// 


@import Foundation;
@import WireImages;

#import "ZMContextChangeTracker.h"
#import "ZMOutstandingItems.h"

@protocol ZMAssetsPreprocessor;
@class ZMImageMessage;


@interface ZMImagePreprocessingTracker : NSObject <ZMContextChangeTracker, ZMOutstandingItems, ZMAssetsPreprocessorDelegate, TearDownCapable>

/// The @c preprocessor will only be called on the @c groupQueue
- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                        imageProcessingQueue:(NSOperationQueue *)imageProcessingQueue
                              fetchPredicate:(NSPredicate *)fetchPredicate
                    needsProcessingPredicate:(NSPredicate *)needsProcessingPredicate
                                 entityClass:(Class)entityClass;

- (void)tearDown;

@end
