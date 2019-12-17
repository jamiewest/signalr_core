import 'dart:convert';
import 'dart:typed_data';

import 'package:signalr_core/src/text_message_format.dart';
import 'package:tuple/tuple.dart';

class HandshakeRequestMessage {
  HandshakeRequestMessage({
    this.protocol, 
    this.version
  });

  final String protocol;

  final int version;
}

class HandshakeResponseMessage {
  HandshakeResponseMessage({
    this.error,
    this.minorVersion
  });

  final String error;

  final int minorVersion;
}

extension on HandshakeRequestMessage {
  Map<String, dynamic> toJson() => {
    'protocol': this.protocol,
    'version': this.version
  };
}

extension HandshakeResponseMessageExtensions on HandshakeResponseMessage {
  static HandshakeResponseMessage fromJson(Map<String, dynamic> json) {
    return HandshakeResponseMessage(
      error: json['error'],
      minorVersion: json['minorVersion']
    );
  }
}

class HandshakeProtocol {
  String writeHandshakeRequest(HandshakeRequestMessage handshakeRequest) {
    return TextMessageFormat.write(json.encode(handshakeRequest.toJson()));
  }

  Tuple2<dynamic, HandshakeResponseMessage> parseHandshakeResponse(dynamic data) {
    HandshakeResponseMessage _responseMessage;
    String _messageData;
    dynamic _remainingData;

    if (data is Uint8List) {
      // Format is binary but still need to read JSON text from handshake response
      int separatorIndex = data.indexOf(TextMessageFormat.RecordSeparatorCode);
      if (separatorIndex == -1) {
        throw Exception("Message is incomplete.");
      }

      // content before separator is handshake response
      // optional content after is additional messages
      final responseLength = separatorIndex + 1;
      _messageData = utf8.decode(data.sublist(0, responseLength));
      _remainingData = (data.length > responseLength)
          ? data.sublist(responseLength, data.length)
          : null;

    } else {
      final String textData = data;
      final separatorIndex =
          textData.indexOf(TextMessageFormat.recordSeparator);
      if (separatorIndex == -1) {
        throw Exception('Message is incomplete.');
      }

      // content before separator is handshake response
      // optional content after is additional messages
      final responseLength = separatorIndex + 1;
      _messageData = textData.substring(0, responseLength);
      _remainingData = (textData.length > responseLength)
          ? textData.substring(responseLength)
          : null;

    }

    // At this point we should have just the single handshake message
    final messages = TextMessageFormat.parse(_messageData);
    final response = HandshakeResponseMessageExtensions.fromJson(json.decode(messages[0]));

    // if (response.type) {
    //   throw new Error("Expected a handshake response from the server.");
    // }

    _responseMessage = response;

    return Tuple2<dynamic, HandshakeResponseMessage>(_remainingData, _responseMessage);
  }
}