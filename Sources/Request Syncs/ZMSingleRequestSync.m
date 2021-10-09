// 


@import WireSystem;
@import WireTransport;

#import "ZMSingleRequestSync.h"

@interface ZMSingleRequestSync ()

@property (nonatomic, weak) id<ZMSingleRequestTranscoder> transcoder;
@property (nonatomic) ZMSingleRequestProgress status;
@property (nonatomic) ZMTransportRequest *currentRequest;
@property (nonatomic) int requestUniqueCounter;
@end


@implementation ZMSingleRequestSync

-(void)dealloc {
    NSLog(@"ZMSingleRequestSync deinit");
}

- (instancetype)initWithSingleRequestTranscoder:(id<ZMSingleRequestTranscoder>)transcoder groupQueue:(id<ZMSGroupQueue>)groupQueue
{
    self = [super init];
    if(self) {
        self.transcoder = transcoder;
        _groupQueue = groupQueue;
    }
    return self;
}

+ (instancetype)syncWithSingleRequestTranscoder:(id<ZMSingleRequestTranscoder>)transcoder groupQueue:(id<ZMSGroupQueue>)groupQueue
{
    return [[self alloc] initWithSingleRequestTranscoder:transcoder groupQueue:groupQueue];
}

- (NSString *)description
{
    id<ZMSingleRequestTranscoder> transcoder = self.transcoder;
    return [NSString stringWithFormat:@"<%@: %p> transcoder: <%@: %p>",
            self.class, self,
            transcoder.class, transcoder];
}

- (void)readyForNextRequest
{
    ++self.requestUniqueCounter;
    self.currentRequest = nil;
    self.status = ZMSingleRequestReady;
}

- (void)readyForNextRequestIfNotBusy
{
    if(self.currentRequest == nil) {
        [self readyForNextRequest];
    }
}

- (ZMTransportRequest *)nextRequest
{
    id<ZMSingleRequestTranscoder> transcoder = self.transcoder;
    if(self.currentRequest == nil && self.status == ZMSingleRequestReady) {
        ZMTransportRequest *request = [transcoder requestForSingleRequestSync:self];
        [request setDebugInformationTranscoder:transcoder];

        self.currentRequest = request;
        if(request == nil) {
            self.status = ZMSingleRequestCompleted;
        } else {
            self.status = ZMSingleRequestInProgress;
        }
        const int currentCounter = self.requestUniqueCounter;
        ZM_WEAK(self);
        [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.groupQueue block:^(ZMTransportResponse * response) {
            ZM_STRONG(self);
            [self processResponse:response forRequest:self.currentRequest counterValueAtStart:currentCounter];
        }]];
        return request;
    }
    return nil;
}

- (void)processResponse:(ZMTransportResponse *)response forRequest:(ZMTransportRequest * __unused)request counterValueAtStart:(int)counterValue
{
    const BOOL isRequestStillValid = counterValue == self.requestUniqueCounter;
    if(!isRequestStillValid) {
        return;
    };
    
    self.currentRequest = nil;
    
    switch (response.result) {
        case ZMTransportResponseStatusSuccess:
        case ZMTransportResponseStatusPermanentError:
        case ZMTransportResponseStatusExpired: // TODO Offline
        {
            self.status = ZMSingleRequestCompleted;
            [self.transcoder didReceiveResponse:response forSingleRequest:self];
            break;
        }
        case ZMTransportResponseStatusTryAgainLater: {
            [self readyForNextRequest];
            break;
        }
        case ZMTransportResponseStatusTemporaryError: {
            self.status = ZMSingleRequestReady;
            break;
        }
    }
}

- (void)resetCompletionState
{
    if(self.status == ZMSingleRequestCompleted) {
        self.status = ZMSingleRequestIdle;
    }
}

@end
