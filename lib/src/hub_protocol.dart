import 'package:signalr_core/src/transport.dart';
import 'package:signalr_core/src/utils.dart';

/// Defines the type of a Hub Message.
enum MessageType {
  /// MessageType is not defined.
  undefined, // = 0,
  /// Indicates the message is an Invocation message and implements the [InvocationMessage] interface.
  invocation, // = 1,
  /// Indicates the message is a StreamItem message and implements the [StreamItemMessage] interface.
  streamItem, // = 2,
  /// Indicates the message is a Completion message and implements the [CompletionMessage] interface.
  completion, // = 3,
  /// Indicates the message is a Stream Invocation message and implements the [StreamInvocationMessage] interface.
  streamInvocation, // = 4,
  /// Indicates the message is a Cancel Invocation message and implements the [CancelInvocationMessage] interface.
  cancelInvocation, // = 5,
  /// Indicates the message is a Ping message and implements the [PingMessage] interface.
  ping, // = 6,
  /// Indicates the message is a Close message and implements the [CloseMessage] interface.
  close, // = 7,
}

extension MessageTypeExtensions on MessageType {
  int get value {
    switch (this) {
      case MessageType.undefined:
        return 0;
      case MessageType.invocation:
        return 1;
      case MessageType.streamItem:
        return 2;
      case MessageType.completion:
        return 3;
      case MessageType.streamInvocation:
        return 4;
      case MessageType.cancelInvocation:
        return 5;
      case MessageType.ping:
        return 6;
      case MessageType.close:
        return 7;
      default:
        return 0;
    }
  }

  String get name {
    switch (this) {
      case MessageType.undefined:
        return '0';
      case MessageType.invocation:
        return 'invocation';
      case MessageType.streamItem:
        return 'streamItem';
      case MessageType.completion:
        return 'completion';
      case MessageType.streamInvocation:
        return 'streamInvocation';
      case MessageType.cancelInvocation:
        return 'cancelInvocation';
      case MessageType.ping:
        return 'ping';
      case MessageType.close:
        return 'close';
      default:
        return '';
    }
  }
}

/// Defines properties common to all Hub messages.
abstract class HubMessage {
  const HubMessage({this.type});

  /// A [MessageType] value indicating the type of this message.
  final MessageType type;
}

/// Defines properties common to all Hub messages relating to a specific invocation.
abstract class HubInvocationMessage extends HubMessage {
  HubInvocationMessage({MessageType type, this.headers, this.invocationId})
      : super(type: type);

  /// A [MessageHeaders] dictionary containing headers attached to the message.
  final Map<String, String> headers;

  ///The ID of the invocation relating to this message.
  ///
  ///This is expected to be present for StreamInvocationMessage and CompletionMessage. It may
  ///be 'undefined' for an InvocationMessage if the sender does not expect a response.
  final String invocationId;
}

/// A hub message representing a non-streaming invocation.
class InvocationMessage extends HubInvocationMessage {
  InvocationMessage(
      {this.target,
      this.arguments,
      this.streamIds,
      Map<String, String> headers,
      String invocationId})
      : super(
            type: MessageType.invocation,
            headers: headers,
            invocationId: invocationId);

  /// The target method name.
  final String target;

  /// The target method arguments.
  final List<dynamic> arguments;

  /// The target method stream IDs.
  final List<String> streamIds;
}

/// A hub message representing a streaming invocation.
class StreamInvocationMessage extends HubInvocationMessage {
  StreamInvocationMessage(
      {this.target,
      this.arguments,
      this.streamIds,
      Map<String, String> headers,
      String invocationId})
      : super(
            type: MessageType.streamInvocation,
            headers: headers,
            invocationId: invocationId);

  /// The target method name.
  final String target;

  /// The target method arguments.
  final List<dynamic> arguments;

  /// The target method stream IDs.
  final List<String> streamIds;
}

/// A hub message representing a single item produced as part of a result stream.
class StreamItemMessage extends HubInvocationMessage {
  StreamItemMessage(
      {this.item, Map<String, String> headers, String invocationId})
      : super(
            type: MessageType.streamItem,
            headers: headers,
            invocationId: invocationId);

  /// The item produced by the server.
  final dynamic item;
}

/// A hub message representing the result of an invocation.
class CompletionMessage extends HubInvocationMessage {
  CompletionMessage(
      {this.error,
      this.result,
      Map<String, String> headers,
      String invocationId})
      : super(
            type: MessageType.completion,
            headers: headers,
            invocationId: invocationId);

  /// The error produced by the invocation, if any.
  ///
  /// Either CompletionMessage.error CompletionMessage.result must be defined, but not both.
  final String error;

  /// The result produced by the invocation, if any.
  ///
  /// Either {@link @aspnet/signalr.CompletionMessage.error} or {@link @aspnet/signalr.CompletionMessage.result} must be defined, but not both.
  final dynamic result;
}

/// A hub message indicating that the sender is still active.
class PingMessage extends HubMessage {
  PingMessage() : super(type: MessageType.ping);
}

/// A hub message indicating that the sender is closing the connection.
///
/// If {@link @aspnet/signalr.CloseMessage.error} is defined, the sender is closing the connection due to an error.
///
class CloseMessage extends HubMessage {
  CloseMessage({this.error, this.allowReconnect})
      : super(type: MessageType.close);

  /// The error that triggered the close, if any.
  ///
  /// If this property is undefined, the connection was closed normally and without error.
  final String error;

  /// If true, clients with automatic reconnects enabled should attempt to reconnect after receiving the CloseMessage.
  /// Otherwise, they should not.
  final bool allowReconnect;
}

/// A hub message sent to request that a streaming invocation be canceled.
class CancelInvocationMessage extends HubInvocationMessage {
  CancelInvocationMessage({Map<String, String> headers, String invocationId})
      : super(
            type: MessageType.cancelInvocation,
            headers: headers,
            invocationId: invocationId);
}

/// A protocol abstraction for communicating with SignalR Hubs.
abstract class HubProtocol {
  HubProtocol({this.name, this.version, this.transferFormat});

  /// The name of the protocol. This is used by SignalR to resolve the protocol between the client and server.
  final String name;

  /// The version of the protocol.
  final int version;

  /// The TransferFormat of the protocol. */
  final TransferFormat transferFormat;

  /// Creates an array of [HubMessage] objects from the specified serialized representation.
  ///
  /// If transferFormat is 'Text', the `input` parameter must be a string, otherwise it must be an ArrayBuffer.
  ///
  /// [input] A string (json), or Uint8List (binary) containing the serialized representation.
  /// [Logger] logger A logger that will be used to log messages that occur during parsing.

  List<HubMessage> parseMessages(Object input, Logging logging);

  /// Writes the specified HubMessage to a string or ArrayBuffer and returns it.
  ///
  /// If transferFormat is 'Text', the result of this method will be a string, otherwise it will be an ArrayBuffer.
  ///
  /// [message] The message to write.
  /// returns  A string or ArrayBuffer containing the serialized representation of the message.

  dynamic writeMessage(HubMessage message);
}
