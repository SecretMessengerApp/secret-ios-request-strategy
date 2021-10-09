// 



#import "ZMObjectSyncStrategy.h"
@import CoreData;

@interface ZMObjectSyncStrategy ()

@property (nonatomic, weak) NSManagedObjectContext *managedObjectContext;
@property (nonatomic) BOOL tornDown;

@end

@implementation ZMObjectSyncStrategy

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc;
{
    self = [super init];
    if (self != nil) {
        self.managedObjectContext = moc;
    }
    return self;
}

- (void)tearDown;
{
    self.tornDown = YES;
}

#if DEBUG
- (void)dealloc
{
    RequireString(self.tornDown, "Did not call -tearDown on %p", (__bridge  void *) self);
}
#endif

@end
