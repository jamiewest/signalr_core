import 'dart:convert';
import 'dart:typed_data';

import 'package:signalr_core/src/text_message_format.dart';

class HandshakeRequestMessage {
  HandshakeRequestMessage({
    this.protocol,
    this.version,
  });

  final String? protocol;
  final int? version;
}

class HandshakeResponseMessage {
  HandshakeResponseMessage({
    this.error,
    this.minorVersion,
  });

  final String? error;
  final int? minorVersion;
}

extension on HandshakeRequestMessage {
  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'version': version,
      };
}

extension HandshakeResponseMessageExtensions on HandshakeResponseMessage {
  static HandshakeResponseMessage fromJson(Map<String, dynamic> json) {
    return HandshakeResponseMessage(
      error: json['error'] as String?,
      minorVersion: json['minorVersion'] as int?,
    );
  }
}

class HandshakeProtocol {
  String writeHandshakeRequest(HandshakeRequestMessage handshakeRequest) {
    return TextMessageFormat.write(json.encode(handshakeRequest.toJson()));
  }

  (dynamic, HandshakeResponseMessage) parseHandshakeResponse(dynamic data) {
    HandshakeResponseMessage responseMessage;
    String messageData;
    dynamic remainingData;

    if (data is Uint8List) {
      // Format is binary but still need to read JSON text from handshake
      // response
      var separatorIndex = data.indexOf(TextMessageFormat.RecordSeparatorCode);
      if (separatorIndex == -1) {
        throw Exception('Message is incomplete.');
      }

      // content before separator is handshake response
      // optional content after is additional messages
      final responseLength = separatorIndex + 1;
      messageData = utf8.decode(data.sublist(0, responseLength));
      remainingData = (data.length > responseLength)
          ? data.sublist(responseLength, data.length)
          : null;
    } else {
      final textData = data as String;
      final separatorIndex =
          textData.indexOf(TextMessageFormat.recordSeparator);
      if (separatorIndex == -1) {
        throw Exception('Message is incomplete.');
      }

      // content before separator is handshake response
      // optional content after is additional messages
      final responseLength = separatorIndex + 1;
      messageData = textData.substring(0, responseLength);
      remainingData = (textData.length > responseLength)
          ? textData.substring(responseLength)
          : null;
    }

    // At this point we should have just the single handshake message
    final messages = TextMessageFormat.parse(messageData);
    final response = HandshakeResponseMessageExtensions.fromJson(
        json.decode(messages[0]) as Map<String, dynamic>);

    // if (response.type) {
    //   throw new Error("Expected a handshake response from the server.");
    // }

    responseMessage = response;

    return (
      remainingData,
      responseMessage,
    );
  }
}
