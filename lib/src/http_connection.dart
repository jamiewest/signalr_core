import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:signalr/src/connection.dart';
import 'package:signalr/src/http_connection_options.dart';
import 'package:signalr/src/logger.dart';
import 'package:signalr/src/long_polling_transport.dart';
import 'package:signalr/src/transport.dart';
import 'package:meta/meta.dart';
import 'package:signalr/src/utils.dart';
import 'package:signalr/src/web_socket_transport.dart';

enum ConnectionState {
  connecting,
  connected,
  disconnected,
  disconnecting
}

class NegotiateResponse {
  NegotiateResponse({
    this.connectionId,
    this.connectionToken,
    this.negotiateVersion,
    this.availableTransports,
    this.url,
    this.accessToken,
    this.error
  });

  final String connectionId;

  String connectionToken;

  final int negotiateVersion;

  final List<AvailableTransport> availableTransports;

  final String url;

  final String accessToken;

  final String error;
}

extension on NegotiateResponse {
  Map<String, dynamic> toJson() => {
    'connectionId': this.connectionId,
    'connectionToken': this.connectionToken,
    'negotiateVersion': this.negotiateVersion,
    'availableTransports': this.availableTransports,
    'url': this.url,
    'accessToken': this.accessToken,
    'error': this.error
  };
}

extension NegotiateResponseExtensions on NegotiateResponse {
  static NegotiateResponse fromJson(Map<String, dynamic> json) {
    return NegotiateResponse(
      connectionId: json['connectionId'],
      connectionToken: json['connectionToken'],
      negotiateVersion: json['negotiateVersion'],
      availableTransports: AvailableTransportExtensions.listFromJson(json['availableTransports']),
      url: json['url'],
      accessToken: json['accessToekn'],
      error: json['error']
    );
  }
}

class AvailableTransport {
  AvailableTransport({ 
    this.transport,
    this.transferFormats
  });

  final HttpTransportType transport;
  
  final List<TransferFormat> transferFormats;  
}

extension AvailableTransportExtensions on AvailableTransport {
  static AvailableTransport fromJson(Map<String, dynamic> json) {
    return AvailableTransport(
      transport: HttpTransportTypeExtensions.fromName(json['transport']),
      transferFormats: List<dynamic>.from(json['transferFormats']).map((value) => TransferFormatExtensions.fromName(value))?.toList()
    );
  }

  static List<AvailableTransport> listFromJson(List<dynamic> json) {
    return json == null
        ? List<AvailableTransport>()
        : json.map((value) => AvailableTransportExtensions.fromJson(value)).toList();
  }
}

const maxRedirects = 100;
typedef StopFutureResolver = void Function(Future<void> value);

class HttpConnection implements Connection {
  ConnectionState _connectionState;
  bool _connectionStarted;
  final http.BaseClient _client;
  final Logging _logging;
  final HttpConnectionOptions _options;
  Transport _transport;
  Future<void> _startInternalFuture;
  Future<void> _stopFuture;
  StopFutureResolver _stopFutureResolver;
  Exception _stopException;
  AccessTokenFactory _accessTokenFactory;
  TransportSendQueue _sendQueue;

  final dynamic features = {};
  String baseUrl;
  String connectionId;
  OnReceive onReceive;
  OnClose onClose;

  final int negotiateVersion = 1;

  HttpConnection(
    this._client, 
    this._logging, 
    this._options,
    String url) {
      baseUrl = url;
  }

  factory HttpConnection.withUrl(String url, HttpConnectionOptions options) {
    return HttpConnection(
      http.Client(),
      options.logging,
      options,
      url
    );
  }


  Future<void> start({TransferFormat transferFormat = TransferFormat.binary}) async {
    _logging(LogLevel.debug, 'Starting connection with transfer format \'${transferFormat.toString()}\'.');

    if (_connectionState == ConnectionState.disconnected) {
      return Future.error(Exception('Cannot start an HttpConnection that is not in the \'Disconnected\' state.'));
    }

    _connectionState = ConnectionState.connecting;

    _startInternalFuture = _startInternal(transferFormat: transferFormat);
    await _startInternalFuture;

    if (_connectionState == ConnectionState.disconnecting) {
        // stop() was called and transitioned the client into the Disconnecting state.
        const message = 'Failed to start the HttpConnection before stop() was called.';
        _logging(LogLevel.error, message);

        // We cannot await stopPromise inside startInternal since stopInternal awaits the startInternalPromise.
        await _stopFuture;

        return Future.error(Exception(message));
    } else if (_connectionState as dynamic != ConnectionState.connected) {
        // stop() was called and transitioned the client into the Disconnecting state.
        const message = 'HttpConnection.startInternal completed gracefully but didn\'t enter the connection into the connected state!';
        _logging(LogLevel.error, message);
        return Future.error(Exception(message));
    }

    _connectionStarted = true;
  }

  Future<void> send(dynamic data) async {
    if (_connectionState != ConnectionState.connected) {
      return Future.error(Exception('Cannot send data if the connection is not in the \'Connected\' State.'));
    }

    // if (_sendQueue == null) {
    //   _sendQueue = TransportSendQueue(transport: _transport);
    // }

    // Transport will not be null if state is connected
    //return _sendQueue.send(data);

    return await _transport.send(data);
  }

  Future<void> stop({Exception exception}) async {
    if (_connectionState == ConnectionState.disconnected) {
      _logging(LogLevel.debug, 'Call to HttpConnection.stop(${exception.toString()}) ignored because the connection is already in the disconnected state.');
      return Future.value(null);
    }

    if (_connectionState == ConnectionState.disconnecting) {
      _logging(LogLevel.debug, 'Call to HttpConnection.stop(${exception.toString()}) ignored because the connection is already in the disconnecting state.');
      return Future.value(null);
    }

    _connectionState = ConnectionState.disconnecting;

    _stopFuture = Future.value((resolve) {
      _stopFutureResolver = resolve;
    });

    await _stopInternal(exception: exception);
    await _stopFuture;
  }

  Future<void> _stopInternal({Exception exception}) async {
    // Set exception as soon as possible otherwise there is a race between
    // the transport closing and providing an exception and the exception from a close message
    // We would prefer the close message exception.
    _stopException = exception;

    try {
        await _startInternalFuture;
    } catch (e) {
        // This exception is returned to the user as a rejected Future from the start method.
    }

    if (_sendQueue != null) {
      try {
        await _sendQueue.stop();
      } catch (e) {
        _logging(LogLevel.error, 'TransportSendQueue.stop() threw error \'${e.toString()}\'.');
      }
      _sendQueue = null;
    }

    // The transport's onclose will trigger stopConnection which will run our onclose event.
    // The transport should always be set if currently connected. If it wasn't set, it's likely because
    // stop was called during start() and start() failed.
    if (_transport != null) {
      try {
        await _transport.stop();
      } catch (e) {
        _logging(LogLevel.error, 'HttpConnection.transport.stop() threw error \'${e.toString()}\'.');
        _stopConnection();
      }

      _transport = null;
    } else {
      _logging(LogLevel.debug, 'HttpConnection.transport is undefined in HttpConnection.stop() because start() failed.');
      _stopConnection();
    }
  }

  void _stopConnection({Exception exception}) {
    _logging(LogLevel.debug, 'HttpConnection.stopConnection(${exception.toString()}) called while in state ${_connectionState.toString()}.');

    _transport = null;

    // If we have a stopError, it takes precedence over the error from the transport
    var _exception = (_stopException == null) ? exception : _stopException;
    _stopException = null;

    if (_connectionState == ConnectionState.disconnected) {
      _logging(LogLevel.debug, 'Call to HttpConnection.stopConnection(${_exception.toString()}) was ignored because the connection is already in the disconnected state.');
      return;
    }

    if (_connectionState == ConnectionState.connecting) {
      _logging(LogLevel.warning, 'Call to HttpConnection.stopConnection(${_exception.toString()}) was ignored because the connection is still in the connecting state.');
        throw Exception('HttpConnection.stopConnection(${_exception.toString()}) was called while the connection is still in the connecting state.');
    }

    if (_connectionState == ConnectionState.disconnecting) {
        // A call to stop() induced this call to stopConnection and needs to be completed.
        // Any stop() awaiters will be scheduled to continue after the onclose callback fires.
        //_stopPromiseResolver();
    }

    if (exception != null) {
        _logging(LogLevel.error, 'Connection disconnected with error \'${_exception.toString()}\'.');
    } else {
      _logging(LogLevel.information, 'Connection disconnected.');
    }

    connectionId = null;
    _connectionState = ConnectionState.disconnected;

    if (onClose != null && _connectionStarted) {
      _connectionStarted = false;

      try {
          onClose(exception);
      } catch (e) {
        _logging(LogLevel.error, 'HttpConnection.onclose(${_exception.toString()}) threw error \'${e}\'.');
      }
    }
  }

  Future<void> _startInternal({@required TransferFormat transferFormat}) async {
    // Store the original base url and the access token factory since they may change
    // as part of negotiating
    var url = baseUrl;
    _accessTokenFactory = _options.accessTokenFactory;

    try {
      if (_options.skipNegotiation) {
        if (_options.transport == HttpTransportType.webSockets) {
          // No need to add a connection ID in this case
          _transport = _constructTransport(HttpTransportType.webSockets);
          // We should just call connect directly in this case.
          // No fallback or negotiate in this case.
          await _startTransport(url: url, transferFormat: transferFormat);
        } else {
          throw Exception('Negotiation can only be skipped when using the WebSocket transport directly.');
        }
      } else {
        NegotiateResponse negotiateResponse;
        int redirects = 0;

        do {
          negotiateResponse = await _getNegotiationResponse(url);
          // the user tries to stop the connection when it is being started
          if (_connectionState == ConnectionState.disconnecting || _connectionState == ConnectionState.disconnected) {
            throw Exception('The connection was stopped during negotiation.');
          }

          if (negotiateResponse.error != null) {
            throw Exception(negotiateResponse.error);
          }

          // if ((negotiateResponse as dynamic).protocolVersion) {
          //   throw Exception('Detected a connection attempt to an ASP.NET SignalR Server. This client only supports connecting to an ASP.NET Core SignalR Server. See https://aka.ms/signalr-core-differences for details.');
          // }

          if (negotiateResponse.url != null) {
            url = negotiateResponse.url;
          }

          if (negotiateResponse.accessToken != null) {
            // Replace the current access token factory with one that uses
            // the returned access token
            final accessToken = negotiateResponse.accessToken;
            _accessTokenFactory = () async => accessToken;
          }

          redirects++;
        }
        while ((negotiateResponse.url != null) && redirects < maxRedirects);

        if ((redirects == maxRedirects) && (negotiateResponse.url != null)) {
          throw Exception('Negotiate redirection limit exceeded.');
        }

        await _createTransport(url, _options.transport, negotiateResponse, transferFormat);
      }

      // if (_transport is LongPollingTransport) {
      //   features.inherentKeepAlive = true;
      // }

      if (_connectionState == ConnectionState.connecting) {
          // Ensure the connection transitions to the connected state prior to completing this.startInternalPromise.
          // start() will handle the case when stop was called and startInternal exits still in the disconnecting state.
          _logging(LogLevel.debug, 'The HttpConnection connected successfully.');
          _connectionState = ConnectionState.connected;
      }

      // stop() is waiting on us via this.startInternalPromise so keep this.transport around so it can clean up.
      // This is the only case startInternal can exit in neither the connected nor disconnected state because stopConnection()
      // will transition to the disconnected state. start() will wait for the transition using the stopPromise.
    } catch (e) {
      _logging(LogLevel.error, 'Failed to start the connection: ' + e.toString());
      _connectionState = ConnectionState.disconnected;
      _transport = null;
      return Future.error(e);
    }
  }

  Future<NegotiateResponse> _getNegotiationResponse(String url) async {
    final headers = {};

    if (_accessTokenFactory != null) {
      final token = await _accessTokenFactory();
      if (token != null) {
        headers['Authorization'] = 'Bearer ${token}';
      }
    }

    final negotiateUrl = _resolveNegotiateUrl(url);
    _logging(LogLevel.debug, 'Sending negotiation request: ${negotiateUrl}.');

    //headers['X-SignalR-User-Agent'] = 'Microsoft SignalR/';
    headers['Content-Type'] = 'text/plain;charset=UTF-8';
    //headers['X-Requested-With'] = 'boop';

    try {
      final response = await _client.post(negotiateUrl,
        headers: Map<String, String>.from(headers));

      if (response.statusCode != 200) {
        return Future.error(Exception('Unexpected status code returned from negotiate \'${response.statusCode}\''));
      }

      final negotiateResponse = NegotiateResponseExtensions.fromJson(json.decode(response.body));

      // TODO: Clean up the next couple of if statements.
      if ((negotiateResponse.negotiateVersion != null)) {
        if(negotiateResponse.negotiateVersion < 1) {
          // Negotiate version 0 doesn't use connectionToken
          // So we set it equal to connectionId so all our logic can use connectionToken without being aware of the negotiate version
          negotiateResponse.connectionToken = negotiateResponse.connectionId;
        }
      }

      if (negotiateResponse.negotiateVersion == null) {
        negotiateResponse.connectionToken = negotiateResponse.connectionId;
      }

      return negotiateResponse;
    } catch (e) {
      _logging(LogLevel.error, 'Failed to complete negotiation with the server: ' + e.toString());
      return Future.error(e);
    }
  }

  static String _resolveNegotiateUrl(String url) {
    final index = url.indexOf("?");
    var negotiateUrl = url.substring(0, index == -1 ? url.length : index);
    if (negotiateUrl[negotiateUrl.length - 1] != "/") {
      negotiateUrl += "/";
    }
    negotiateUrl += "negotiate";
    negotiateUrl += index == -1 ? "" : url.substring(index);
    return negotiateUrl;
  }

  Future<void> _startTransport({String url, TransferFormat transferFormat}) {
    _transport.onReceive = onReceive;
    _transport.onClose = (e) => _stopConnection(exception: e);
    return _transport.connect(url, transferFormat);
  }

  static String _createConnectUrl(String url, String connectionToken) {
    if (connectionToken == null) {
      return url;
    }
    return url + '?' + 'id=$connectionToken';
    //return url + (url.contains('?') ? '?' : '&') + 'id=$connectionToken';
  }

  Future<void> _createTransport(
      String url,
      Object requestedTransport,
      NegotiateResponse negotiateResponse,
      TransferFormat requestedTransferFormat) async {

    var connectUrl = _createConnectUrl(url, negotiateResponse.connectionToken);
    if (requestedTransport is Transport) {

      _logging(LogLevel.debug, 'Connection was provided an instance of Transport, using that directly.');
      _transport = requestedTransport;
      await _startTransport(url: connectUrl, transferFormat: requestedTransferFormat);

      connectionId = negotiateResponse.connectionId;
      return Future.value(null);
    }

    final transportExceptions = [];
    final transports = negotiateResponse.availableTransports;
    var negotiate = negotiateResponse;

    for (var endpoint in transports) {
      _connectionState = ConnectionState.connecting;
      final transportOrError  = _resolveTransportOrError(endpoint, requestedTransport, requestedTransferFormat);

      if (transportOrError is Exception) {
        transportExceptions.add(transportOrError);
      } else {
        if (transportOrError is Transport) {
          _transport = transportOrError;
          if (negotiate == null) {
            try {
              negotiate = await _getNegotiationResponse(url);
            } catch (ex) {
              return Future.error(ex);
            }
            connectUrl = _createConnectUrl(url, negotiate.connectionToken);
          }
        }

        try {
          await _startTransport(url: connectUrl, transferFormat: requestedTransferFormat);
          connectionId = negotiate.connectionId;
          return Future.value(null);
        } catch (e) {
          _logging(LogLevel.error, 'Failed to start the transport \'${endpoint.transport}\': ${e.toString()}');
          negotiate = null;
          transportExceptions.add(Exception('${endpoint.transport} failed: ${e.toString()}'));

          if (_connectionState != ConnectionState.connecting) {
            const message = 'Failed to select transport before stop() was called.';
            _logging(LogLevel.debug, message);
            return Future.error(Exception(message));
          }
        }
      }
    }
  }

  dynamic _resolveTransportOrError(AvailableTransport endpoint, HttpTransportType requestedTransport, TransferFormat requestedTransferFormat) {
    final transport = endpoint.transport;
    if (transport == null) {
      _logging(LogLevel.debug, 'Skipping transport \'${endpoint.transport.toString()}\' because it is not supported by this client.');
      return Exception('Skipping transport \'${endpoint.transport.toString()}\' because it is not supported by this client.');
    } else {
      if (_transportMatches(requestedTransport, transport)) {
        final transferFormats = endpoint.transferFormats;
        if (transferFormats.contains(requestedTransferFormat)) {
          _logging(LogLevel.debug, 'Selecting transport \'${transport.toString()}\'.');
          try {
            return _constructTransport(transport);
          } catch (e) {
            return e;
          }
        } else {
          _logging(LogLevel.debug, 'Skipping transport \'${transport.toString()}\' because it does not support the requested transfer format \'${requestedTransferFormat.toString()}\'.');
          return Exception('\'${transport.toString()}\' does not support ${requestedTransferFormat.toString()}');
        }
      } else {
        _logging(LogLevel.debug, 'Skipping transport \'${transport.toString()}\' because it was disabled by the client.');
        return Exception('\'${transport.toString()}\' is disabled by the client.');
      }
    }
  }

  bool _transportMatches(HttpTransportType requestedTransport, HttpTransportType actualTransport) {
    if (requestedTransport == null) {
      return false;
    } else {
      return (requestedTransport.index == actualTransport.index);
    }
  }

  Transport _constructTransport(HttpTransportType transport) {
    switch(transport) {
      case HttpTransportType.none:
        // TODO: Handle this case.
        break;
      case HttpTransportType.webSockets:
        return WebSocketTransport(
          accessTokenFactory: _accessTokenFactory, 
          logging: _logging, 
          logMessageContent: _options.logMessageContent
        );
        break;
      case HttpTransportType.serverSentEvents:
        // TODO: Handle this case.
        break;
      case HttpTransportType.longPolling:
        return LongPollingTransport(
          accessTokenFactory: _accessTokenFactory,
          logMessageContent: _options.logMessageContent,
          log: _logging,
          client: _client
        );
        break;
    }
    return null;
  }
}

class TransportSendQueue {
  List _buffer = [];
  Future<void> _sendBufferedData;
  bool _executing = true;
  Future<void> _transportResult;
  Future<void> _sendLoopPromise;

  final Transport transport;

  TransportSendQueue({this.transport}) {
    //_sendBufferedData = FutureSource();
    //_transportResult = FutureSource();

    _sendLoopPromise = sendLoop();
  }

  Future<void> send (dynamic data) {
    _bufferData(data);
        if (_transportResult == null) {
            //_transportResult = FutureSource();
        }
        //return _transportResult.future;
  }

  Future<void> stop() {
    _executing = false;
    //_sendBufferedData.resolve();
    return _sendLoopPromise;
  }

  void _bufferData(dynamic data) {
    if (_buffer.isNotEmpty) {
      throw Exception('Expected data to be of type ${_buffer.toString()} but was of type ${data.toString()}');
    }

    _buffer.add(data);
    //_sendBufferedData.resolve();
  }

  Future<void> sendLoop() async {
    while (true) {
            //await _sendBufferedData.future;

            if (!_executing) {
                if (_transportResult != null) {
                    //_transportResult.reject(Exception('Connection stopped.'));
                }

                break;
            }

            //_sendBufferedData = FutureSource();

            //final transportResult = _transportResult;
            //_transportResult = null;

            var data;
            if (_buffer.isNotEmpty) {
              data = (_buffer[0] is String) 
                ? _buffer.join('') 
                : TransportSendQueue._concatBuffers(_buffer);
              
              _buffer.clear();

              try {
                await transport.send(data);
                //transportResult.resolve();
            } catch (error) {
                //transportResult.reject(error);
            }
            }
        }

  }

  static ByteBuffer _concatBuffers(List<ByteBuffer> byteBuffers) {
    final totalLength = byteBuffers.map((b) => b.lengthInBytes).reduce((a, b) => a + b);
    final result = Uint8List(totalLength);
    
    var offset = 0;
    for (final item in byteBuffers) {
      result.setAll(offset, item.asUint8List());
      offset += item.lengthInBytes;
    }

    return result.buffer;
  }
}

// typedef Resolver = void Function();
// typedef Rejector = void Function(dynamic reason);

// class FutureSource {
//   Resolver _resolver;
//   Rejector _rejector;
//   Future<void> future;

//   FutureSource() {
//     future = Future.value((resolve, reject) {
//       _resolver = resolve;
//       _rejector = reject;
//     });
//   }

//   void resolve() {
//       _resolver();
//     }

//     void reject(dynamic reason) {
//       _rejector(reason);
//     }
// }