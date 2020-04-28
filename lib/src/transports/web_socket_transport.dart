import 'dart:async';

import 'package:http/http.dart';

import 'web_socket_channel_api.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) 'web_socket_channel_html.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) 'web_socket_channel_io.dart' as platform;

import 'package:signalr_core/src/logger.dart';
import 'package:signalr_core/src/transport.dart';
import 'package:signalr_core/src/utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class WebSocketTransport implements Transport {
  final Logging _logging;
  final AccessTokenFactory _accessTokenFactory;
  final bool _logMessageContent;
  final BaseClient _client;

  StreamSubscription<dynamic> _streamSubscription;
  WebSocketChannel _channel;

  WebSocketTransport({
    BaseClient client,
    AccessTokenFactory accessTokenFactory,
    Logging logging,
    bool logMessageContent,
  })  : _logging = logging,
        _accessTokenFactory = accessTokenFactory,
        _logMessageContent = logMessageContent,
        _client = client {
    onreceive = null;
    onreceive = null;
  }

  @override
  var onclose;

  @override
  var onreceive;

  @override
  Future<void> connect(String url, TransferFormat transferFormat) async {
    assert(url != null);
    assert(transferFormat != null);

    _logging(LogLevel.trace, '(WebSockets transport) Connecting.');

    if (_accessTokenFactory != null) {
      final token = await _accessTokenFactory();
      if (token.isNotEmpty) {
        final encodedToken = Uri.encodeComponent(token);
        url += (url.contains('?') ? '&' : '?') + "access_token=$encodedToken";
      }
    }

    final connectFuture = Completer<void>();
    bool opened = false;

    url = url.replaceFirst(RegExp(r'^http'), 'ws');

    try {
      _channel = await platform.connect(Uri.parse(url), client: _client);

      _logging(LogLevel.information, 'WebSocket connected to $url.');
      opened = true;

      _streamSubscription = _channel.stream.listen((data) {
        var dataDetail = getDataDetail(data, _logMessageContent);
        _logging(LogLevel.trace,
            '(WebSockets transport) data received. $dataDetail');
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
    if ((_channel == null) && (_channel?.closeCode != null)) {
      return Future.error(Exception('WebSocket is not in the OPEN state'));
    }

    _logging(LogLevel.trace,
        '(WebSockets transport) sending data. ${getDataDetail(data, _logMessageContent)}.');
    _channel.sink.add(data);
    return Future.value();
  }

  @override
  Future<void> stop() {
    if (_channel != null) {
      _close(null);
    }
    return Future.value();
  }

  void _close(Exception error) {
    var closeCode = 0;
    var closeReason;
    if (_channel != null) {
      closeCode = _channel.closeCode ?? 0;
      closeReason = _channel.closeReason;
      _streamSubscription.cancel();
      _streamSubscription = null;
      _channel.sink.close();
      _channel = null;
    }

    _logging(LogLevel.trace, '(WebSockets transport) socket closed.');
    if (onclose != null) {
      if (error != null) {
        onclose(error);
      } else {
        if (closeCode != 0 && closeCode != 1000) {
          onclose(Exception(
              'WebSocket closed with status code: $closeCode ($closeReason).'));
        }
        onclose(null);
      }
    }
  }
}
