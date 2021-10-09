// 




@protocol ZMOutstandingItems <NSObject>

/// Returns YES if there are any objects still to be sync'ed, processed or otherwise 'in progress' of being sync'ed.
@property (nonatomic, readonly) BOOL hasOutstandingItems;

@end
