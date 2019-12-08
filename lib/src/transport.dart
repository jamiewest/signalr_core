import 'package:signalr/signalr.dart';

/// Specifies a specific HTTP transport type.
///
/// This will be treated as a bit flag in the future, so we keep it using power-of-two values.
enum HttpTransportType {
  /// Specifies no transport preference.
  none, // 0
  /// Specifies the WebSockets transport.
  webSockets, // 1
  /// Specifies the Server-Sent Events transport.
  serverSentEvents, // 2
  /// Specifies the Long Polling transport.
  longPolling // 4
}

extension HttpTransportTypeExtensions on HttpTransportType {
  static HttpTransportType fromName(String name) {
    switch (name) {
      case 'none': {
        return HttpTransportType.none;
      }
      case 'WebSockets': {
        return HttpTransportType.webSockets;
      }
      case 'ServerSentEvents': {
        return HttpTransportType.serverSentEvents;
      }
      case 'LongPolling': {
        return HttpTransportType.longPolling;
      }
      default:
        return HttpTransportType.none;
    }
  }
}

/// Specifies the transfer format for a connection.
enum TransferFormat {
  /// Specifies that only text data will be transmitted over the connection.
  text, // = 1,
  /// Specifies that binary data will be transmitted over the connection.
  binary, // = 2,
}

extension TransferFormatExtensions on TransferFormat {
  static TransferFormat fromName(String name) {
    switch (name) {
      case 'Text': {
        return TransferFormat.text;
      }
      case 'Binary': {
        return TransferFormat.binary;
      }
      default:
        return TransferFormat.binary;
    }
  }
}

/// An abstraction over the behavior of transports. 
/// 
/// This is designed to support the framework and not intended for use by applications.
abstract class Transport {
  Future<void> connect(String url, TransferFormat transferFormat);
  Future<void> send(dynamic data);
  Future<void> stop();
  OnReceive onReceive;
  OnClose onClose;
}