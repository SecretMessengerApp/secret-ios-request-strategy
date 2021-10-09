// 


@import WireUtilities;
@import WireDataModel;

#import "ZMChangeTrackerBootstrap+Testing.h"
#import "ZMContextChangeTracker.h"

@interface ZMChangeTrackerBootstrap ()

@property (nonatomic) NSManagedObjectContext *managedObjectContext;
@property (nonatomic) NSArray *changeTrackers;
@property (nonatomic) NSMapTable *entityToRequestMap;
@property (nonatomic, readonly, copy) NSDictionary *entitiesByName;

@end



@implementation ZMChangeTrackerBootstrap

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)context changeTrackers:(NSArray *)changeTrackers
{
    self = [super init];
    if (self) {
        self.managedObjectContext = context;
        _entitiesByName = [self.managedObjectContext.persistentStoreCoordinator.managedObjectModel.entitiesByName copy];
        self.changeTrackers = changeTrackers;
    }
    return self;
}


- (NSEntityDescription *)entityForEntityName:(NSString *)name;
{
    Require(name != nil);
    NSEntityDescription *entity = self.entitiesByName[name];
    RequireString(entity != nil, "Entity not found.");
    return entity;
}

- (void)fetchObjectsForChangeTrackers
{
    NSArray *fetchRequests = [self.changeTrackers mapWithBlock:^id(id tracker) {
        return [tracker fetchRequestForTrackedObjects];
    }];
    
    NSMapTable *entityToRequestMap = [self sortFetchRequestsByEntity:fetchRequests];
    NSMapTable *entityToResultsMap = [self executeMappedFetchRequests:entityToRequestMap];
    
    for (id <ZMContextChangeTracker> tracker in self.changeTrackers) {
        NSFetchRequest *request = [tracker fetchRequestForTrackedObjects];
        if (request == nil) {
            continue;
        }
        NSEntityDescription *entity = [self entityForEntityName:request.entityName];
        NSArray *results = [entityToResultsMap objectForKey:entity];
        
        NSMutableSet *objectsToUpdate = [NSMutableSet set];
        for (NSManagedObject *object in results) {
            if ([request.predicate evaluateWithObject:object]){
                [objectsToUpdate addObject:object];
            }
        }
        if (objectsToUpdate.count > 0) {
            [tracker addTrackedObjects:objectsToUpdate];
        }
    }
}

- (NSMapTable *)sortFetchRequestsByEntity:(NSArray *)fetchRequests;
{
    NSMapTable *requestsMap = [NSMapTable strongToStrongObjectsMapTable];
    
    for (NSFetchRequest *request in fetchRequests){
        if (request.predicate == nil) {
            continue;
        }
        NSEntityDescription *entity = [self entityForEntityName:request.entityName];
        NSSet *predicates = [requestsMap objectForKey:entity];
        if ( predicates == nil) {
            [requestsMap setObject:[NSSet setWithObject:request.predicate] forKey:entity];
        } else {
            [requestsMap setObject:[predicates setByAddingObject:request.predicate] forKey:entity];
        }
    }
    return requestsMap;
}


- (NSMapTable *)executeMappedFetchRequests:(NSMapTable *)entityToRequestsMap;
{
    Require(entityToRequestsMap != nil);
    
    NSMapTable *resultsMap = [NSMapTable strongToStrongObjectsMapTable];

    for (NSEntityDescription *entity in entityToRequestsMap) {
        NSDate *date = [NSDate new];
        NSSet *predicates = [entityToRequestsMap objectForKey:entity];
        if ([entity.name isEqualToString:@"ClientMessage"] ||
            [entity.name isEqualToString:@"Message"] ||
            [entity.name isEqualToString:@"AssetClientMessage"]) {
            continue;
        } else {
            NSFetchRequest *fetchRequest = [self compoundRequestForEntity:entity predicates:predicates];
            NSArray *result = [self.managedObjectContext executeFetchRequestOrAssert:fetchRequest];
            double time = -[date timeIntervalSinceNow];
            NSLog(@"[Change-Tracker] EntityName: %@, fetchRequestTime: %f, count:%lu, predicate:%@", entity.name, time, (unsigned long)result.count, fetchRequest.predicate);
            if (result.count > 0){
                [resultsMap setObject:result forKey:entity];
            }
        }
        
    }
    
    return resultsMap;
}

- (NSFetchRequest *)compoundRequestForEntity:(NSEntityDescription *)entity predicates:(NSSet *)predicates
{
    NSCompoundPredicate *compoundPredicate = [NSCompoundPredicate orPredicateWithSubpredicates:[predicates allObjects]];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = entity;
    fetchRequest.predicate = compoundPredicate;
    [fetchRequest configureRelationshipPrefetching];
    fetchRequest.returnsObjectsAsFaults = NO;
    return fetchRequest;
}

- (NSFetchRequest *)compoundRequestForEntity:(NSEntityDescription *)entity predicate:(NSPredicate *)predicate
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = entity;
    fetchRequest.predicate = predicate;
    [fetchRequest configureRelationshipPrefetching];
    fetchRequest.returnsObjectsAsFaults = NO;
    return fetchRequest;
}

@end

@implementation ZMChangeTrackerBootstrap (Testing)

+ (void)bootStrapChangeTrackers:(NSArray *)changeTrackers onContext:(NSManagedObjectContext *)context;
{
    ZMChangeTrackerBootstrap *changeTrackerBootStrap = [[ZMChangeTrackerBootstrap alloc] initWithManagedObjectContext:context
                                                                                                       changeTrackers:changeTrackers];
    [changeTrackerBootStrap fetchObjectsForChangeTrackers];
}

@end



@interface ZMMessageChangeTrackerBootstrap ()

@property (nonatomic) NSManagedObjectContext *managedObjectContext;
@property (nonatomic) NSArray *changeTrackers;
@property (nonatomic) NSMapTable *entityToRequestMap;
@property (nonatomic, readonly, copy) NSDictionary *entitiesByName;

@end



@implementation ZMMessageChangeTrackerBootstrap

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)context changeTrackers:(NSArray *)changeTrackers
{
    self = [super init];
    if (self) {
        self.managedObjectContext = context;
        _entitiesByName = [self.managedObjectContext.persistentStoreCoordinator.managedObjectModel.entitiesByName copy];
        self.changeTrackers = changeTrackers;
    }
    return self;
}


- (NSEntityDescription *)entityForEntityName:(NSString *)name;
{
    Require(name != nil);
    NSEntityDescription *entity = self.entitiesByName[name];
    RequireString(entity != nil, "Entity not found.");
    return entity;
}

- (void)fetchObjectsForChangeTrackers
{
    NSArray *fetchRequests = [self.changeTrackers mapWithBlock:^id(id tracker) {
        return [tracker fetchRequestForTrackedObjects];
    }];
    
    NSMapTable *entityToRequestMap = [self sortFetchRequestsByEntity:fetchRequests];
    NSMapTable *entityToResultsMap = [self executeMappedFetchRequests:entityToRequestMap];
    
    for (id <ZMContextChangeTracker> tracker in self.changeTrackers) {
        NSFetchRequest *request = [tracker fetchRequestForTrackedObjects];
        if (request == nil) {
            continue;
        }
        NSEntityDescription *entity = [self entityForEntityName:request.entityName];
        NSArray *results = [entityToResultsMap objectForKey:entity];
        
        NSMutableSet *objectsToUpdate = [NSMutableSet set];
        for (NSManagedObject *object in results) {
            if ([request.predicate evaluateWithObject:object]){
                [objectsToUpdate addObject:object];
            }
        }
        if (objectsToUpdate.count > 0) {
            [tracker addTrackedObjects:objectsToUpdate];
        }
    }
}

- (NSMapTable *)sortFetchRequestsByEntity:(NSArray *)fetchRequests;
{
    NSMapTable *requestsMap = [NSMapTable strongToStrongObjectsMapTable];
    
    for (NSFetchRequest *request in fetchRequests){
        if (request.predicate == nil) {
            continue;
        }
        NSEntityDescription *entity = [self entityForEntityName:request.entityName];
        NSSet *predicates = [requestsMap objectForKey:entity];
        if ( predicates == nil) {
            [requestsMap setObject:[NSSet setWithObject:request.predicate] forKey:entity];
        } else {
            [requestsMap setObject:[predicates setByAddingObject:request.predicate] forKey:entity];
        }
    }
    return requestsMap;
}


- (NSMapTable *)executeMappedFetchRequests:(NSMapTable *)entityToRequestsMap;
{
    Require(entityToRequestsMap != nil);
    
    NSMapTable *resultsMap = [NSMapTable strongToStrongObjectsMapTable];

    for (NSEntityDescription *entity in entityToRequestsMap) {
        NSDate *date = [NSDate new];
        NSSet *predicates = [entityToRequestsMap objectForKey:entity];
        if ([entity.name isEqualToString:@"ClientMessage"] || [entity.name isEqualToString:@"Message"]) {
            NSMutableArray *allResult = [NSMutableArray array];
            for (NSPredicate *predicate in predicates) {
                NSDate *date1 = [NSDate new];
                NSFetchRequest *fetchRequest = [self compoundRequestForEntity:entity predicate:predicate];
                NSArray *result = [self.managedObjectContext executeFetchRequestOrAssert:fetchRequest];
                [allResult addObjectsFromArray:result];
                double time = -[date1 timeIntervalSinceNow];
                NSLog(@"[Change-Tracker] EntityName: %@, fetchRequestTime: %f, count:%lu, predicate:%@", entity.name, time, (unsigned long)result.count, predicate);
            }
            if (allResult.count > 0){
                [resultsMap setObject:allResult forKey:entity];
            }
        } else {
            NSFetchRequest *fetchRequest = [self compoundRequestForEntity:entity predicates:predicates];
            NSArray *result = [self.managedObjectContext executeFetchRequestOrAssert:fetchRequest];
            double time = -[date timeIntervalSinceNow];
            NSLog(@"[Change-Tracker] EntityName: %@, fetchRequestTime: %f, count:%lu, predicate:%@", entity.name, time, (unsigned long)result.count, fetchRequest.predicate);
            if (result.count > 0){
                [resultsMap setObject:result forKey:entity];
            }
        }
        
    }
    
    return resultsMap;
}

- (NSFetchRequest *)compoundRequestForEntity:(NSEntityDescription *)entity predicates:(NSSet *)predicates
{
    NSCompoundPredicate *compoundPredicate = [NSCompoundPredicate orPredicateWithSubpredicates:[predicates allObjects]];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = entity;
    fetchRequest.predicate = compoundPredicate;
    [fetchRequest configureRelationshipPrefetching];
    fetchRequest.returnsObjectsAsFaults = NO;
    return fetchRequest;
}

- (NSFetchRequest *)compoundRequestForEntity:(NSEntityDescription *)entity predicate:(NSPredicate *)predicate
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    fetchRequest.entity = entity;
    fetchRequest.predicate = predicate;
    [fetchRequest configureRelationshipPrefetching];
    fetchRequest.returnsObjectsAsFaults = NO;
    return fetchRequest;
}

@end

