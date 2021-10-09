//
//

@import Foundation;
@import WireTransport;
#import "ZMSingleRequestSync.h"
#import "ZMRequestGenerator.h"

@protocol ZMSimpleListRequestPaginatorSync;


@interface ZMSimpleListRequestPaginator : NSObject <ZMRequestGenerator>

/// YES if more requests should be made before to fetch the full list
@property (nonatomic, readonly) BOOL hasMoreToFetch;

/// Status of the underlying singleRequestTranscoder
@property (nonatomic, readonly) ZMSingleRequestProgress status;

@property (nonatomic, readonly) BOOL inProgress;

/// Date of last call to `resetFetching`
@property (nonatomic, readonly) NSDate *lastResetFetchDate;


- (instancetype)initWithBasePath:(NSString *)basePath
                        startKey:(NSString *)startKey
                        pageSize:(NSUInteger)pageSize
            managedObjectContext:(NSManagedObjectContext *)moc
                 includeClientID:(BOOL)includeClientID
                      transcoder:(id<ZMSimpleListRequestPaginatorSync>)transcoder;

- (ZMTransportRequest *)nextRequest;

/// this will cause the fetch to restart at the nextPaginatedRequest
- (void)resetFetching;

@end



@protocol ZMSimpleListRequestPaginatorSync <NSObject>

/// returns the next UUID to be used as the starting point for the next request
- (NSUUID *)nextUUIDFromResponse:(ZMTransportResponse *)response forListPaginator:(ZMSimpleListRequestPaginator *)paginator;


/// Returns an NSUUID to start with after calling resetFetching
@optional
- (NSUUID *)startUUID;

/// Returns YES, if the error response for a specific statusCode should be parsed (e.g. if the payload contains content that needs to be processed)
@optional
- (BOOL)shouldParseErrorForResponse:(ZMTransportResponse*)response;

@end

