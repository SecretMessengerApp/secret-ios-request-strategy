// 


#import <WireRequestStrategy/ZMDownstreamObjectSyncWithWhitelist.h>
#import <WireRequestStrategy/ZMDownStreamObjectSync.h>

@interface ZMDownstreamObjectSyncWithWhitelist (Internal)

@property (nonatomic, copy) NSMutableSet *whitelist;
@property (nonatomic, readonly) ZMDownstreamObjectSync *innerDownstreamSync;

@end
