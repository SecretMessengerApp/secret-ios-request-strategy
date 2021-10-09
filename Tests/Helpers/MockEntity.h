// 


@import WireDataModel;

@interface MockEntity : ZMManagedObject

@property (nonatomic) NSUUID *remoteIdentifier;
@property (nonatomic) NSSet *modifiedKeys;

@property (nonatomic) NSUUID *testUUID;
@property (nonatomic) int16_t field;
@property (nonatomic) NSString *field2;
@property (nonatomic) NSString *field3;

@property (nonatomic) NSMutableSet *mockEntities;

@property (class, nonatomic) NSPredicate *predicateForObjectsThatNeedToBeUpdatedUpstream;

@end

