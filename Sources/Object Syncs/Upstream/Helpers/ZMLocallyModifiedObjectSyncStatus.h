// 


@import Foundation;

@class ZMManagedObject;
@class ZMLocallyModifiedObjectSyncStatusToken;



@interface ZMLocallyModifiedObjectSyncStatus : NSObject

@property (nonatomic, readonly) ZMManagedObject *object;
@property (nonatomic, readonly) NSSet *keysToSynchronize;
@property (nonatomic, readonly) BOOL isDone;

- (instancetype)initWithObject:(ZMManagedObject *)object trackedKeys:(NSSet *)trackedKeys;

- (ZMLocallyModifiedObjectSyncStatusToken *)startSynchronizingKeys:(NSSet *)keys;

/// Returns the keys that did change since the token was created
- (NSSet *)returnChangedKeysAndFinishTokenSync:(ZMLocallyModifiedObjectSyncStatusToken *)token;

- (void)resetLocallyModifiedKeysForToken:(ZMLocallyModifiedObjectSyncStatusToken *)token;

@end
