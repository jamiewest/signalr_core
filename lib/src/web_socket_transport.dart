import 'dart:async';

import 'package:signalr/src/logger.dart';
import 'package:signalr/src/transport.dart';
import 'package:signalr/src/utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketTransport implements Transport {
  StreamSubscription<dynamic> _streamSubscription;
  WebSocketChannel _channel;

  WebSocketTransport({
    this.accessTokenFactory,
    this.logging,
    this.logMessageContent
  });

  final AccessTokenFactory accessTokenFactory;

  final Logging logging; 

  final bool logMessageContent;
  
  @override
  Future<void> connect(String url, TransferFormat transferFormat) async {
    assert(url != null);
    assert(transferFormat != null);

    logging(LogLevel.trace, "(WebSockets transport) Connecting."); 

    if (accessTokenFactory != null) {
      final token = await accessTokenFactory();
      if (token.isNotEmpty) {
        final encodedToken = Uri.encodeComponent(token);
        url += (url.contains('?') ? '?' : '&') + "access_token=$encodedToken";
      }
    }

    url = url.replaceFirst(RegExp(r'^http'), 'ws');
    _channel = WebSocketChannel.connect(Uri.parse(url));

    _streamSubscription = _channel.stream.listen((data) {
      var dataDetail = getDataDetail(data, this.logMessageContent);
      logging(LogLevel.trace, '(WebSockets transport) data received. $dataDetail');
      if (onreceive != null) {
        try {
          onreceive(data);
        } catch (e1) {
          _close(e1);
          return;
        }
      }
    }, onError: (e) {
      print(e.toString());
    }, onDone: () {
      print('done');
    }, cancelOnError: false);

    logging(LogLevel.information, 'WebSocket connected to $url.');

    return Future.value(null);
  }

  @override
  Future<void> send(dynamic data) {
    if (_channel != null) {
      var dataDetail = getDataDetail(data, this.logMessageContent);
      logging(LogLevel.trace, '(WebSockets transport) sending data. $dataDetail.');
      _channel.sink.add(data);
      return Future.value(null);
    }

    return Future.error(Exception('WebSocket is not in the OPEN state'));
  }

  @override
  Future<void> stop() async {
    await _streamSubscription.cancel();

    return Future.value(null);
  }

    @override
  var onclose;

  @override
  var onreceive;

  void _close(Exception error) {
    logging(LogLevel.trace, '(WebSockets transport) socket closed.');
    if (onclose != null) {
      if (error != null) {
        onclose(error);
      } else {
        onclose(null);
      }
    }
  }
}