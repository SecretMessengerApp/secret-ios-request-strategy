// 


#import <Foundation/Foundation.h>
#import "ZMRequestGenerator.h"


@class ZMRemoteIdentifierObjectSync;
@class ZMTransportRequest;
@class ZMTransportResponse;



@protocol ZMRemoteIdentifierObjectTranscoder <NSObject>

- (NSUInteger)maximumRemoteIdentifiersPerRequestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync;
- (ZMTransportRequest *)requestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync remoteIdentifiers:(NSSet<NSUUID *> *)identifiers;
- (void)didReceiveResponse:(ZMTransportResponse *)response remoteIdentifierObjectSync:(ZMRemoteIdentifierObjectSync *)sync forRemoteIdentifiers:(NSSet<NSUUID *> *)remoteIdentifiers;

@end



@interface ZMRemoteIdentifierObjectSync : NSObject <ZMRequestGenerator>

- (instancetype)initWithTranscoder:(id<ZMRemoteIdentifierObjectTranscoder>)transcoder managedObjectContext:(NSManagedObjectContext *)moc;

- (ZMTransportRequest *)nextRequest;

- (void)setRemoteIdentifiersAsNeedingDownload:(NSSet<NSUUID *> *)remoteIdentifiers;
- (void)addRemoteIdentifiersThatNeedDownload:(NSSet<NSUUID *> *)remoteIdentifiers;

- (NSSet *)remoteIdentifiersThatWillBeDownloaded;

@property (nonatomic, readonly) BOOL isDone;

@end
