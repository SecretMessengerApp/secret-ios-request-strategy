// 


@import WireUtilities;
@import WireTransport;
@import WireDataModel;

#import "ZMSyncOperationSet.h"

static id valueOrNSNull(id obj) {
    return obj ?: [NSNull null];
}




@interface ZMPartialSyncOperation : NSObject

@property (nonatomic) ZMManagedObject *managedObject;
@property (nonatomic) NSSet *remainingKeys;

@end



@interface ZMSyncOperationSet ()

@property (nonatomic) NSMutableSet *managedObjectsBeingSynchronized;
@property (nonatomic) NSMutableOrderedSet *pendingOperationSet;
@property (nonatomic) NSMutableOrderedSet *managedObjectsWithPartialUpdates;

@end


@implementation ZMSyncOperationSet

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.managedObjectsBeingSynchronized = [NSMutableSet set];
        self.pendingOperationSet = [[NSMutableOrderedSet alloc] init];
        self.managedObjectsWithPartialUpdates = [NSMutableOrderedSet orderedSet];
    }
    return self;
}

-(NSUInteger)count
{
    return self.pendingOperationSet.count + self.managedObjectsWithPartialUpdates.count;
}

- (void)addObjectToBeSynchronized:(ZMManagedObject *)mo;
{
    [self.pendingOperationSet addObject:mo];
    [self removeObjectFromPartialUpdates:mo];
}

- (ZMManagedObject *)nextObjectToSynchronize
{
    return [self nextObjectToSynchronizeNotInOperationSet:nil];
}

- (ZMManagedObject *)nextObjectToSynchronizeNotInOperationSet:(ZMSyncOperationSet *)operationSet;
{
    NSSet *forbiddenSet = self.managedObjectsBeingSynchronized;
    if (operationSet != nil) {
        NSMutableSet *set = [forbiddenSet mutableCopy];
        [set unionSet:operationSet.pendingOperationSet.set];
        forbiddenSet = set;
    }

    NSArray *sds = self.sortDescriptors;
    if (sds != nil) {
        return (ZMManagedObject *)[self.pendingOperationSet firstObjectSortedByDescriptors:sds notInSet:forbiddenSet];
    } else {
        return (ZMManagedObject *)[self.pendingOperationSet firstObjectNotInSet:forbiddenSet];
    }
}

- (ZMSyncToken *)didStartSynchronizingKeys:(NSSet *)keys forObject:(ZMManagedObject *)mo;
{
    [self.managedObjectsBeingSynchronized addObject:mo];
    NSMutableDictionary *originalKeyValues = [NSMutableDictionary dictionary];
    for(NSString* key in keys) {
        originalKeyValues[key] = valueOrNSNull([mo valueForKey:key]);
    }
    return (id) originalKeyValues;
}

- (NSSet *)keysForWhichToApplyResultsAfterFinishedSynchronizingSyncWithToken:(ZMSyncToken *)token forObject:(ZMManagedObject *)mo result:(ZMTransportResponseStatus)status;
{
    NSDictionary *originalKeyValues = (id) token;
    
    [self.managedObjectsBeingSynchronized removeObject:mo];
    
    if ((status == ZMTransportResponseStatusTemporaryError) ||
        (status == ZMTransportResponseStatusTryAgainLater))
    {
        return [NSSet set];
    }
    
    NSMutableSet *synchronizedKeys = [NSMutableSet set];
    if (status == ZMTransportResponseStatusPermanentError) {
        return [NSSet setWithArray:originalKeyValues.allKeys];
    }
    
    for(NSString *key in originalKeyValues.allKeys) {
        id value = valueOrNSNull([mo valueForKey:key]);
        if([value isEqual:originalKeyValues[key]] ) {
            [synchronizedKeys addObject:key];
        }
    }
    
    return synchronizedKeys;
}

- (void)removeUpdatedObject:(ZMManagedObject *)mo syncToken:(ZMSyncToken *)token synchronizedKeys:(NSSet *)synchronizedKeys
{
    NSDictionary *originalKeyValues = (id) token;
    if(synchronizedKeys.count == originalKeyValues.count) {
        [self.pendingOperationSet removeObject:mo];
    }
}

- (NSString *)description;
{
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p> ", self.class, self];
    if (self.pendingOperationSet.count) {
        NSArray *pending = [self.pendingOperationSet.array mapWithBlock:^id(NSManagedObject *mo) {
            if ([mo isKindOfClass:NSManagedObject.class]) {
                return mo.objectID.URIRepresentation;
            } else {
                return mo.description;
            }
        }];
        [description appendString:@"pending: {"];
        [description appendString:[pending componentsJoinedByString:@", "]];
        [description appendString:@"}"];
    } else {
        [description appendString:@"empty"];
    }
    return description;
}

- (void)removeObject:(ZMManagedObject *)mo;
{
    [self.pendingOperationSet removeObject:mo];
    [self removeObjectFromPartialUpdates:mo];
}

- (void)removeObjectFromPartialUpdates:(ZMManagedObject *)mo
{
    NSUInteger idx = [self.managedObjectsWithPartialUpdates indexOfObjectPassingTest:^BOOL(ZMPartialSyncOperation *op, NSUInteger __unused innerIdx, BOOL __unused *stop) {
        return op.managedObject == mo;
    }];
    if (idx != NSNotFound) {
        [self.managedObjectsWithPartialUpdates removeObjectAtIndex:idx];
    }
}

- (BOOL)containsObject:(ZMManagedObject *)mo
{
    return [self.pendingOperationSet containsObject:mo];
}

@end



@implementation ZMSyncOperationSet (PartialUpdates)

- (ZMManagedObject *)nextObjectToSynchronizeWithRemainingKeys:(NSSet **)remainingKeys notInOperationSet:(ZMSyncOperationSet *)operationSet;
{
    ZMPartialSyncOperation *first = [self.managedObjectsWithPartialUpdates firstObject];
    
    if (first == nil) {
        return [self nextObjectToSynchronizeNotInOperationSet:operationSet];
    }
    *remainingKeys = first.remainingKeys;
    return first.managedObject;
}

- (void)setRemainingKeys:(NSSet *)keys forObject:(ZMManagedObject *)mo;
{
    if (keys.count == 0) {
        [self removeObjectFromPartialUpdates:mo];
        return;
    }
    for (ZMPartialSyncOperation *op in self.managedObjectsWithPartialUpdates) {
        if (op.managedObject == mo) {
            op.remainingKeys = [keys copy];
            return;
        }
    }
    ZMPartialSyncOperation *op = [[ZMPartialSyncOperation alloc] init];
    op.managedObject = mo;
    op.remainingKeys = [keys copy];
    [self.managedObjectsWithPartialUpdates addObject:op];
}


@end



@implementation ZMPartialSyncOperation
@end
