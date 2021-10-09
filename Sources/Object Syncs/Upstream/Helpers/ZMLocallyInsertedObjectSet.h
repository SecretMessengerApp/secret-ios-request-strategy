// 


@import Foundation;

@class ZMManagedObject;



@interface ZMLocallyInsertedObjectSet : NSObject

- (void)addObjectToSynchronize:(ZMManagedObject *)object;
- (void)removeObjectToSynchronize:(ZMManagedObject *)object;

- (ZMManagedObject *)anyObjectToSynchronize;

- (void)didFailSynchronizingObject:(ZMManagedObject *)object;
- (void)didStartSynchronizingObject:(ZMManagedObject *)object;
- (void)didFinishSynchronizingObject:(ZMManagedObject *)object;

- (BOOL)isSynchronizingObject:(ZMManagedObject *)object;

@property (nonatomic, readonly) NSUInteger count;

@end
