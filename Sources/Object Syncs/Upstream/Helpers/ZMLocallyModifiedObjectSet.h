//
//


@import Foundation;

#import <WireRequestStrategy/ZMOutstandingItems.h>

@class ZMManagedObject;
@class ZMLocallyModifiedObjectSyncStatus;

NS_ASSUME_NONNULL_BEGIN

@interface ZMObjectWithKeys : NSObject

@property (nonatomic, readonly,) ZMManagedObject *object;
@property (nonatomic, readonly,) NSSet *keysToSync;

@end


@class ZMModifiedObjectSyncToken;


@interface ZMLocallyModifiedObjectSet : NSObject <ZMOutstandingItems>

@property (nonatomic, readonly, nullable) NSSet *trackedKeys;

// Init with all keys tracked
- (instancetype)init;
// Init with only some keys tracked
- (instancetype)initWithTrackedKeys:(NSSet *)keys;

// This will check internally if the object really needs to be synced i.e. the locally modified keys are the one we are interested in
- (void)addPossibleObjectToSynchronize:(ZMManagedObject *)object;

// return any of the object that is not currently being synced
- (ZMObjectWithKeys * __nullable)anyObjectToSynchronize;

// Mark the object as started to sync and return a token that should be passed in all the completion callbacks (didFailToSynchronize, ...)
- (ZMModifiedObjectSyncToken *)didStartSynchronizingKeys:(NSSet *)keys forObject:(ZMObjectWithKeys *)object;

// Called when sync failed
- (void)didFailToSynchronizeToken:(ZMModifiedObjectSyncToken *)token;

// Returns list of keys that should be parsed by the transcoder
- (NSSet *)keysToParseAfterSyncingToken:(ZMModifiedObjectSyncToken *)token;

// Called when it is done syncing the keys in the token
- (void)didSynchronizeToken:(ZMModifiedObjectSyncToken *)token;

// Called when it still needs to generate more requests to sync this object
- (void)didNotFinishToSynchronizeToken:(ZMModifiedObjectSyncToken *)token;

@end

NS_ASSUME_NONNULL_END
