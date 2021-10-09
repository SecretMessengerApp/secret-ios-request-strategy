//
//

typedef NS_OPTIONS(NSUInteger, ZMStrategyConfigurationOption) {
    ZMStrategyConfigurationOptionDoesNotAllowRequests = 0,
    ZMStrategyConfigurationOptionAllowsRequestsWhileUnauthenticated = 1 << 0,
    ZMStrategyConfigurationOptionAllowsRequestsWhileInBackground = 1 << 1,
    ZMStrategyConfigurationOptionAllowsRequestsDuringSync = 1 << 2,
    ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing = 1 << 3,
    ZMStrategyConfigurationOptionAllowsRequestsDuringNotificationStreamFetch = 1 << 4
};
