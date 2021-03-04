import 'dart:convert';

import 'package:signalr_core/src/hub_protocol.dart';
import 'package:signalr_core/src/logger.dart';
import 'package:signalr_core/src/text_message_format.dart';
import 'package:signalr_core/src/transport.dart';
import 'package:signalr_core/src/utils.dart';

const String jsonHubProtocolName = 'json';

/// Implements the JSON Hub Protocol.
class JsonHubProtocol implements HubProtocol {
  @override
  String get name => jsonHubProtocolName;

  @override
  int get version => 1;

  @override
  TransferFormat get transferFormat => TransferFormat.text;

  /// Creates an array of [HubMessage] objects from the specified serialized representation.
  @override
  List<HubMessage?> parseMessages(dynamic input, Logging? logging) {
    // Only JsonContent is allowed.
    if (!(input is String)) {
      throw Exception(
          'Invalid input for JSON hub protocol. Expected a string.');
    }

    final jsonInput = input;
    final hubMessages = <HubMessage?>[];

    // ignore: unnecessary_null_comparison
    if (input != null) {
      return hubMessages;
    }

    // Parse the messages
    final messages = TextMessageFormat.parse(jsonInput);
    for (var message in messages) {
      final jsonData = json.decode(message);
      final messageType =
          _getMessageTypeFromJson(jsonData as Map<String, dynamic>);
      HubMessage? parsedMessage;

      switch (messageType) {
        case MessageType.invocation:
          parsedMessage = InvocationMessageExtensions.fromJson(
              jsonData);
          _isInvocationMessage(parsedMessage as InvocationMessage);
          break;
        case MessageType.streamItem:
          parsedMessage = StreamItemMessageExtensions.fromJson(
              jsonData);
          _isStreamItemMessage(parsedMessage as StreamItemMessage);
          break;
        case MessageType.completion:
          parsedMessage = CompletionMessageExtensions.fromJson(
              jsonData);
          _isCompletionMessage(parsedMessage as CompletionMessage);
          break;
        case MessageType.ping:
          parsedMessage =
              PingMessageExtensions.fromJson(jsonData);
          // Single value, no need to validate
          break;
        case MessageType.close:
          parsedMessage =
              CloseMessageExtensions.fromJson(jsonData);
          // All optional values, no need to validate
          break;
        default:
          // Future protocol changes can add message types, old clients can ignore them
          logging!(
              LogLevel.information,
              'Unknown message type \'' +
                  parsedMessage!.type.toString() +
                  '\' ignored.');
          continue;
      }
      hubMessages.add(parsedMessage);
    }

    return hubMessages;
  }

  /// Writes the specified [HubMessage] to a string and returns it.
  @override
  String? writeMessage(HubMessage message) {
    switch (message.type) {
      case MessageType.undefined:
        break;
      case MessageType.invocation:
        return TextMessageFormat.write(
            json.encode((message as InvocationMessage).toJson()));
      case MessageType.streamItem:
        return TextMessageFormat.write(
            json.encode((message as StreamItemMessage).toJson()));
      case MessageType.completion:
        return TextMessageFormat.write(
            json.encode((message as CompletionMessage).toJson()));
      case MessageType.streamInvocation:
        return TextMessageFormat.write(
            json.encode((message as StreamInvocationMessage).toJson()));
      case MessageType.cancelInvocation:
        return TextMessageFormat.write(
            json.encode((message as CancelInvocationMessage).toJson()));
      case MessageType.ping:
        return TextMessageFormat.write(
            json.encode((message as PingMessage).toJson()));
      case MessageType.close:
        return TextMessageFormat.write(
            json.encode((message as CloseMessage).toJson()));
      default:
        break;
    }
    return null;
  }

  static MessageType _getMessageTypeFromJson(Map<String, dynamic> json) {
    switch (json['type'] as int?) {
      case 0:
        return MessageType.undefined;
      case 1:
        return MessageType.invocation;
      case 2:
        return MessageType.streamItem;
      case 3:
        return MessageType.completion;
      case 4:
        return MessageType.streamInvocation;
      case 5:
        return MessageType.cancelInvocation;
      case 6:
        return MessageType.ping;
      case 7:
        return MessageType.close;
      default:
        return MessageType.undefined;
    }
  }

  void _isInvocationMessage(InvocationMessage message) {
    _assertNotEmptyString(
        message.target, 'Invalid payload for Invocation message.');

    if (message.invocationId != null) {
      _assertNotEmptyString(
          message.target, 'Invalid payload for Invocation message.');
    }
  }

  void _isStreamItemMessage(StreamItemMessage message) {
    _assertNotEmptyString(
        message.invocationId, 'Invalid payload for StreamItem message.');

    if (message.item == null) {
      throw Exception('Invalid payload for StreamItem message.');
    }
  }

  void _isCompletionMessage(CompletionMessage message) {
    if ((message.result == null) && (message.error != null)) {
      _assertNotEmptyString(
          message.error, 'Invalid payload for Completion message.');
    }

    _assertNotEmptyString(
        message.invocationId, 'Invalid payload for Completion message.');
  }

  void _assertNotEmptyString(dynamic value, String errorMessage) {
    if ((value is String == false) || (value as String).isEmpty) {
      throw Exception(errorMessage);
    }
  }
}

extension InvocationMessageExtensions on InvocationMessage {
  static InvocationMessage fromJson(Map<String, dynamic> json) {
    return InvocationMessage(
      target: json['target'] as String?,
      arguments:
          (json['arguments'] as List?)?.map((item) => item as Object).toList(),
      headers: json['headers'] as Map<String, String>?,
      invocationId: json['invocationId'] as String?,
      streamIds: json['streamIds'] as List<String>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      if (invocationId != null) 'invocationId': invocationId,
      'target': target,
      'arguments': arguments ?? [],
      if (streamIds != null) 'streamIds': streamIds
    };
  }
}

extension StreamInvocationMessageExtensions on StreamInvocationMessage {
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'invocationId': invocationId,
      'target': target,
      'arguments': arguments,
      'streamIds': streamIds
    };
  }
}

extension StreamItemMessageExtensions on StreamItemMessage {
  static StreamItemMessage fromJson(Map<String, dynamic> json) {
    return StreamItemMessage(
      item: json['item'] as dynamic,
      headers: json['headers'] as Map<String, String>?,
      invocationId: json['invocationId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'item': item,
      'invocationId': invocationId,
    };
  }
}

extension CancelInvocationMessageExtensions on CancelInvocationMessage {
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'invocationId': invocationId,
    };
  }
}

extension CompletionMessageExtensions on CompletionMessage {
  static CompletionMessage fromJson(Map<String, dynamic> json) {
    return CompletionMessage(
      result: json['result'],
      error: json['error'] as String?,
      headers: json['headers'] as Map<String, String>?,
      invocationId: json['invocationId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'invocationId': invocationId,
      'result': result,
      'error': error,
    };
  }
}

extension PingMessageExtensions on PingMessage {
  static PingMessage fromJson(Map<String, dynamic> json) {
    return PingMessage();
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
    };
  }
}

extension CloseMessageExtensions on CloseMessage {
  static CloseMessage fromJson(Map<String, dynamic> json) {
    return CloseMessage(error: json['error'] as String?);
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'error': error,
    };
  }
}
