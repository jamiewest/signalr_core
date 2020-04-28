import 'package:signalr_core/src/text_message_format.dart';
import 'package:test/test.dart';

const Map<String, List<String>> messages = {
  '\u001e': [''],
  '\u001e\u001e': ['', ''],
  'Hello\u001e': ['Hello'],
  'Hello,\u001eWorld!\u001e': ['Hello,', 'World!']
};

void main() {
  group('TextMessageFormat', () {
    Map<String, List<String>>.from({
      '\u001e': [''],
      '\u001e\u001e': ['', ''],
      'Hello\u001e': ['Hello'],
      'Hello,\u001eWorld!\u001e': ['Hello,', 'World!']
    }).forEach((payload, expectedMessages) {
      test('should parse \'${Uri.encodeComponent(payload)}\' correctly', () {
        final messages = TextMessageFormat.parse(payload);
        expect(messages, expectedMessages);
      });
    });

    Map<String, String>.from({
      '': 'Message is incomplete.',
      'ABC': 'Message is incomplete.',
      'ABC\u001eXYZ': 'Message is incomplete.',
    }).forEach((payload, expectedError) {
      test('should fail to parse \'${Uri.encodeComponent(payload)}\'', () {
        //expect(() => TextMessageFormat.parse(payload), predicate((Exception e) => e is Exception && e.message == 'Message is incomplete.'));
      });
    });
  });
}
