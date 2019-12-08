import 'dart:convert';

import 'package:signalr/src/hub_protocol.dart';
import 'package:signalr/src/logger.dart';
import 'package:signalr/src/text_message_format.dart';
import 'package:signalr/src/transport.dart';
import 'package:signalr/src/utils.dart';

const String jsonHubProtocolName = "json";

class JsonHubProtocol implements HubProtocol {
  @override
  String get name => jsonHubProtocolName;

  @override
  int get version => 1;

  @override
  TransferFormat get transferFormat => TransferFormat.text;

  @override
  List<HubMessage> parseMessages(dynamic input, Logging logging) {
    // Only JsonContent is allowed.
    if (!(input is String)) {
      throw Exception(
          "Invalid input for JSON hub protocol. Expected a string.");
    }

    final jsonInput = input as String;
    final hubMessages = List<HubMessage>();

    if (input == null) {
      return hubMessages;
    }

    // Parse the messages
    final messages = TextMessageFormat.parse(jsonInput);
    for (var message in messages) {
      final jsonData = json.decode(message);
      final messageType = _getMessageTypeFromJson(jsonData);
      HubMessage parsedMessage;

      switch (messageType) {
        case MessageType.invocation:
          parsedMessage = InvocationMessageExtensions.fromJson(jsonData);
          _isInvocationMessage(parsedMessage);
          break;
        case MessageType.streamItem:
          parsedMessage = StreamItemMessageExtensions.fromJson(jsonData);
          _isStreamItemMessage(parsedMessage);
          break;
        case MessageType.completion:
          parsedMessage = CompletionMessageExtensions.fromJson(jsonData);
          _isCompletionMessage(parsedMessage);
          break;
        case MessageType.ping:
          parsedMessage = PingMessageExtensions.fromJson(jsonData);
          // Single value, no need to validate
          break;
        case MessageType.close:
          parsedMessage = CloseMessageExtensions.fromJson(jsonData);
          // All optional values, no need to validate
          break;
        default:
          // Future protocol changes can add message types, old clients can ignore them
          logging(LogLevel.information, "Unknown message type '" + parsedMessage.type.toString() + "' ignored.");
          continue;
      }
      hubMessages.add(parsedMessage);
    }

    return hubMessages;
  }

  @override
  String writeMessage(HubMessage message) {
    switch (message.type) {
      case MessageType.undefined:
        break;
      case MessageType.invocation:
        return TextMessageFormat.write(json.encode((message as InvocationMessage).toJson()));
        break;
      case MessageType.streamItem:
        return TextMessageFormat.write(json.encode((message as StreamItemMessage).toJson()));
        break;
      case MessageType.completion:
        return TextMessageFormat.write(json.encode((message as CompletionMessage).toJson()));
        break;
      case MessageType.streamInvocation:
        break;
      case MessageType.cancelInvocation:
        break;
      case MessageType.ping:
        return TextMessageFormat.write(json.encode((message as PingMessage).toJson()));
        break;
      case MessageType.close:
        return TextMessageFormat.write(json.encode((message as CloseMessage).toJson()));
        break;
      default:
        break;
    }
    return null;
  }

  static MessageType _getMessageTypeFromJson(Map<String, dynamic> json) {
    switch (json['type']) {
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
    _assertNotEmptyString(message.target, 'Invalid payload for Invocation message.');

    if (message.invocationId != null) {
      _assertNotEmptyString(message.target, 'Invalid payload for Invocation message.');
    }
  }

  void _isStreamItemMessage(StreamItemMessage message) {
    _assertNotEmptyString(message.invocationId, 'Invalid payload for StreamItem message.');

    if (message.item == null) {
      throw Exception('Invalid payload for StreamItem message.');
    }
  }

  void _isCompletionMessage(CompletionMessage message) {
    if ((message.result != null) && message.error.isNotEmpty) {
      throw Exception('Invalid payload for Completion message.');
    }

    if ((message.result == null) && (message.error != null)) {
      _assertNotEmptyString(message.error, 'Invalid payload for Completion message.');
    }

    _assertNotEmptyString(message.invocationId, 'Invalid payload for Completion message.');
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
      target: json['target'],
      arguments: (json['arguments'] as List)?.map((item) => item as Object)?.toList(),
      headers: json['headers'],
      invocationId: json['invocationId']
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': this.type.value,
      'invocationId': this.invocationId,
      'target': this.target,
      'arguments': this.arguments
    };
  }
}

extension StreamItemMessageExtensions on StreamItemMessage {
  static StreamItemMessage fromJson(Map<String, dynamic> json) {
    return StreamItemMessage(
      item: json['item'],
      headers: json['headers'],
      invocationId: json['invocationId']
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': this.type.value,
      'invocationType': this.invocationId,
      'item': this.item,
    };
  }
}

extension CompletionMessageExtensions on CompletionMessage {
  static CompletionMessage fromJson(Map<String, dynamic> json) {
    return CompletionMessage(
      result: json['result'],
      error: json['error'],
      headers: json['headers'],
      invocationId: json['invocationId']
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': this.type.value,
      'invocationType': this.invocationId,
      'result': this.result,
      'error': this.error,
    };
  }
}

extension PingMessageExtensions on PingMessage {
  static PingMessage fromJson(Map<String, dynamic> json) {
    return PingMessage( );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': this.type.value
    };
  }
}

extension CloseMessageExtensions on CloseMessage {
  static CloseMessage fromJson(Map<String, dynamic> json) {
    return CloseMessage(
      error: json['error']
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': this.type.value,
      'error': this.error
    };
  }
}