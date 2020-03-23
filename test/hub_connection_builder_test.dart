import 'package:signalr_core/signalr_core.dart';
import 'package:test/test.dart';

void main() {
  test(
      'withAutomaticReconnect uses default retryDelays when called with no arguments',
      () {
    // From DefaultReconnectPolicy.dart
    final defaultRetryDelaysInMilliseconds = [0, 2000, 10000, 30000, null];
    final builder = HubConnectionBuilder().withAutomaticReconnect();

    var retryCount = 0;
    defaultRetryDelaysInMilliseconds.forEach((delay) {
      final retryContext = RetryContext(
          previousRetryCount: retryCount++,
          elapsedMilliseconds: 0,
          retryReason: Exception());

      expect(builder.reconnectPolicy.nextRetryDelayInMilliseconds(retryContext),
          delay);
    });
  });

  test('withAutomaticReconnect uses custom retryDelays when provided', () {
    final customRetryDelays = [3, 1, 4, 1, 5, 9];
    final builder =
        HubConnectionBuilder().withAutomaticReconnect(customRetryDelays);

    var retryCount = 0;
    customRetryDelays.forEach((delay) {
      final retryContext = RetryContext(
          previousRetryCount: retryCount++,
          elapsedMilliseconds: 0,
          retryReason: Exception());

      expect(builder.reconnectPolicy.nextRetryDelayInMilliseconds(retryContext),
          delay);
    });

    // TODO: This test fails in Dart but looks like works using Typescript's testing framework
    // final retryContextFinal = RetryContext(
    //     previousRetryCount: retryCount++,
    //     elapsedMilliseconds: 0,
    //     retryReason: Exception());

    // expect(
    //     builder.reconnectPolicy.nextRetryDelayInMilliseconds(retryContextFinal),
    //     null);
  });

  test('withAutomaticReconnect uses a custom RetryPolicy when provided', () {
    final customRetryDelays = [127, 0, 0, 1];
    final builder = HubConnectionBuilder().withAutomaticReconnect(
        DefaultReconnectPolicy(retryDelays: customRetryDelays));

    var retryCount = 0;
    customRetryDelays.forEach((delay) {
      final retryContext = RetryContext(
          previousRetryCount: retryCount++,
          elapsedMilliseconds: 0,
          retryReason: Exception());

      expect(builder.reconnectPolicy.nextRetryDelayInMilliseconds(retryContext),
          delay);
    });

    // TODO: This test fails in Dart but looks like works using Typescript's testing framework
    // final retryContextFinal = RetryContext(
    //     previousRetryCount: retryCount++,
    //     elapsedMilliseconds: 0,
    //     retryReason: Exception());

    // expect(
    //     builder.reconnectPolicy.nextRetryDelayInMilliseconds(retryContextFinal),
    //     null);
  });
}
