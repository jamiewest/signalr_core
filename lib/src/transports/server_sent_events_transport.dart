import 'dart:async';

import 'package:http/http.dart';
import 'package:signalr_core/src/logger.dart';
import 'package:signalr_core/src/transport.dart';
import 'package:signalr_core/src/utils.dart';

import 'package:sse_client/sse_client.dart';

class ServerSentEventsTransport implements Transport {
  final BaseClient _client;
  final AccessTokenFactory _accessTokenFactory;
  final Logging _log;
  final bool _logMessageContent;
  final bool _withCredentials;
  String _url;
  SseClient _sseClient;

  ServerSentEventsTransport({
    BaseClient client,
    AccessTokenFactory accessTokenFactory,
    Logging logging,
    bool logMessageContent,
    bool withCredentials,
  })  : _client = client,
        _accessTokenFactory = accessTokenFactory,
        _log = logging,
        _logMessageContent = logMessageContent,
        _withCredentials = withCredentials {
    onclose = null;
    onreceive = null;
  }

  @override
  OnClose onclose;

  @override
  OnReceive onreceive;

  @override
  Future<void> connect(String url, TransferFormat transferFormat) async {
    _log(LogLevel.trace, '(SSE transport) Connecting.');

    // set url before accessTokenFactory because this.url is only for send and we set the auth header instead of the query string for send
    _url = url;

    if (_accessTokenFactory != null) {
      final token = await _accessTokenFactory();
      if (token != null) {
        _url += (!url.contains('?') ? '?' : '&') +
            'access_token=${Uri.encodeComponent(token)}';
      }
    }

    var completer = Completer<void>();

    var opened = false;
    if (transferFormat != TransferFormat.text) {
      return completer.completeError(
        Exception(
            'The Server-Sent Events transport only supports the \'Text\' transfer format'),
      );
    }

    SseClient client;
    try {
      client = SseClient.connect(Uri.parse(url));
      _log(LogLevel.information, 'SSE connected to $_url');
      opened = true;
      _sseClient = client;
      completer.complete();
    } catch (e) {
      return completer.completeError(e);
    }

    _sseClient.stream.listen((data) {
      _log(LogLevel.trace,
          '(SSE transport) data received. ${getDataDetail(data, _logMessageContent)}');
      onreceive(data);
    }, onError: (e) {
      if (opened) {
        _close(exception: e as Exception);
      } else {
        completer.completeError(e);
      }
    });

    return completer.future;
  }

  @override
  Future<void> send(data) async {
    if (_sseClient == null) {
      return Future.error(
          Exception('Cannot send until the transport is connected'));
    }
    return sendMessage(
      _log,
      'SSE',
      _client,
      _url,
      _accessTokenFactory,
      data,
      _logMessageContent,
      _withCredentials,
    );
  }

  @override
  Future<void> stop() {
    _close();
    return Future.value(null);
  }

  void _close({Exception exception}) {
    if (_sseClient != null) {
      _sseClient = null;

      if (onclose != null) {
        onclose(exception);
      }
    }
  }
}
