import 'package:signalr_core/src/retry_policy.dart';

const defaultRetryDelaysInMilliseconds = [0, 2000, 10000, 30000, null];

class DefaultReconnectPolicy implements RetryPolicy {
  DefaultReconnectPolicy({
    this.retryDelays = defaultRetryDelaysInMilliseconds,
  });

  final List<int?> retryDelays;

  @override
  int? nextRetryDelayInMilliseconds(RetryContext retryContext) {
    return retryDelays[retryContext.previousRetryCount!];
  }
}
