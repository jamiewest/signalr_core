import 'package:signalr/src/retry_policy.dart';

const DefaultRetryDelaysInMilliseconds = [0, 2000, 10000, 30000, null];

class DefaultReconnectPolicy implements RetryPolicy {

  DefaultReconnectPolicy({
    this.retryDelays = DefaultRetryDelaysInMilliseconds
  });

  final List<int> retryDelays;

  @override
  int nextRetryDelayInMilliseconds({RetryContext retryContext}) {
    return retryDelays[retryContext.previousRetryCount];
  }
}