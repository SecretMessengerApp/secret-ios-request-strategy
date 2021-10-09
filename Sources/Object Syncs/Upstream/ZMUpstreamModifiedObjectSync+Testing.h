// 


#import <WireRequestStrategy/ZMUpstreamModifiedObjectSync.h>
@class ZMLocallyModifiedObjectSet;

@interface ZMUpstreamModifiedObjectSync (Testing)

@property (nonatomic, readonly) ZMLocallyModifiedObjectSet *updatedObjects;

- (instancetype)initWithTranscoder:(id<ZMUpstreamTranscoder>)transcoder
                        entityName:(NSString *)entityName
                   updatePredicate:(NSPredicate *)updatePredicate
                            filter:(NSPredicate *)filter
                        keysToSync:(NSArray<NSString *> *)keysToSync
              managedObjectContext:(NSManagedObjectContext *)context
          locallyModifiedObjectSet:(ZMLocallyModifiedObjectSet *)objectSet;

@end
