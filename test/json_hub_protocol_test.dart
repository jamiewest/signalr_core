import 'package:signalr/src/hub_protocol.dart';
import 'package:signalr/src/json_hub_protocol.dart';
import 'package:signalr/src/text_message_format.dart';
import 'package:test/test.dart';

void main() {
  test('can read ping message', () {
    final payload = '{"type":6}${TextMessageFormat.recordSeparator}';
    final messages = JsonHubProtocol().parseMessages(payload, (level, message) => print(message));
    expect(messages, equals([
      PingMessage()
    ]));
  });
}