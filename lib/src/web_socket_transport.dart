import 'dart:async';

import 'package:signalr_core/src/logger.dart';
import 'package:signalr_core/src/transport.dart';
import 'package:signalr_core/src/utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketTransport implements Transport {
  StreamSubscription<dynamic> _streamSubscription;
  WebSocketChannel _channel;

  WebSocketTransport(
      {this.accessTokenFactory, this.logging, this.logMessageContent});

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

    final connectFuture = Completer<void>();
    bool opened = false;
    url = url.replaceFirst(RegExp(r'^http'), 'ws');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      logging(LogLevel.information, 'WebSocket connected to $url.');
      opened = true;

      _streamSubscription = _channel.stream.listen((data) {
        var dataDetail = getDataDetail(data, this.logMessageContent);
        logging(LogLevel.trace,
            '(WebSockets transport) data received. $dataDetail');
        if (onreceive != null) {
          try {
            onreceive(data);
          } catch (e1) {
            _close(e1);
          }
        }
      }, onError: (e) {
        print(e);
      }, onDone: () {
        if (opened == true) {
          _close(null);
        } else {}
      }, cancelOnError: false);

      return connectFuture.complete();
    } catch (e) {
      return connectFuture.completeError(e);
    }
  }

  @override
  Future<void> send(dynamic data) {
    if ((_channel == null) || (_channel?.closeCode != null)) {
      return Future.error(Exception('WebSocket is not in the OPEN state'));
    }

    logging(LogLevel.trace,
        '(WebSockets transport) sending data. ${getDataDetail(data, this.logMessageContent)}.');
    _channel.sink.add(data);
    return Future.value();
  }

  @override
  Future<void> stop() async {
    await _streamSubscription.cancel();

    return Future.value();
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
