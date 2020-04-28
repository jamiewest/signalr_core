import 'dart:async';

import 'package:signalr_core/signalr_core.dart';
import 'package:signalr_core/src/connection.dart';
import 'package:signalr_core/src/handshake_protocol.dart';
import 'package:signalr_core/src/hub_protocol.dart';
import 'package:signalr_core/src/logger.dart';
import 'package:signalr_core/src/retry_policy.dart';
import 'package:tuple/tuple.dart';

typedef InvocationEventCallback = void Function(
    HubMessage invocationEvent, Exception exception);
typedef MethodInvacationFunc = void Function(List<dynamic> arguments);
typedef ClosedCallback = void Function(Exception exception);
typedef ReconnectingCallback = void Function(Exception exception);
typedef ReconnectedCallback = void Function(String connectionId);

const int DEFAULT_TIMEOUT_IN_MS = 30 * 1000;
const int DEFAULT_PING_INTERVAL_IN_MS = 15 * 1000;

/// Describes the current state of the [HubConnection] to the server.
enum HubConnectionState {
  /// The hub connection is disconnected.
  disconnected,

  /// The hub connection is connecting.
  connecting,

  /// The hub connection is connected.
  connected,

  /// The hub connection is disconnecting.
  disconnecting,

  /// The hub connection is reconnecting.
  reconnecting
}

/// Represents a connection to a SignalR Hub.
class HubConnection {
  final dynamic _cachedPingMessage;
  final Connection _connection;
  final Logging _logger;
  final RetryPolicy _reconnectPolicy;
  HubProtocol _protocol;
  HandshakeProtocol _handshakeProtocol;
  Map<String, InvocationEventCallback> _callbacks;
  Map<String, List<MethodInvacationFunc>> _methods;
  int _invocationId;

  List<ClosedCallback> _closedCallbacks;
  List<ReconnectingCallback> _reconnectingCallbacks;
  List<ReconnectedCallback> _reconnectedCallbacks;

  bool _receivedHandshakeResponse;
  Completer _handshakeCompleter;
  Exception _stopDuringStartError;

  HubConnectionState _connectionState;
  bool _connectionStarted;
  Future<void> _startFuture;
  Future<void> _stopFuture;

  Timer _reconnectDelayHandle;
  Timer _timeoutHandle;
  Timer _pingServerHandle;

  HubConnection(
      {Connection connection,
      Logging logging,
      HubProtocol protocol,
      RetryPolicy reconnectPolicy})
      : _cachedPingMessage = protocol.writeMessage(PingMessage()),
        _connection = connection,
        _logger = logging,
        _protocol = protocol,
        _reconnectPolicy = reconnectPolicy {
    serverTimeoutInMilliseconds = DEFAULT_TIMEOUT_IN_MS;
    keepAliveIntervalInMilliseconds = DEFAULT_PING_INTERVAL_IN_MS;

    _handshakeProtocol = HandshakeProtocol();
    _connection.onreceive = (dynamic data) => _processIncomingData(data);
    _connection.onclose =
        (Exception exception) => _connectionClosed(exception: exception);

    _callbacks = {};
    _methods = {};
    _closedCallbacks = [];
    _reconnectingCallbacks = [];
    _reconnectedCallbacks = [];
    _invocationId = 0;
    _receivedHandshakeResponse = false;
    _connectionState = HubConnectionState.disconnected;
    _connectionStarted = false;
  }

  /// The server timeout in milliseconds.
  ///
  /// If this timeout elapses without receiving any messages from the server, the connection will be terminated with an error.
  /// The default timeout value is 30,000 milliseconds (30 seconds).
  int serverTimeoutInMilliseconds;

  /// Default interval at which to ping the server.
  ///
  /// The default value is 15,000 milliseconds (15 seconds).
  /// Allows the server to detect hard disconnects (like when a client unplugs their computer).
  int keepAliveIntervalInMilliseconds;

  /// Indicates the state of the {@link HubConnection} to the server.
  HubConnectionState get state => _connectionState;

  /// Represents the connection id of the [HubConnection] on the server. The connection id will be null when the connection is either
  /// in the disconnected state or if the negotiation step was skipped.
  String get connectionId => _connection.connectionId;

  /// Indicates the url of the {@link HubConnection} to the server.
  String get baseUrl => _connection.baseUrl;

  /// Sets a new url for the HubConnection. Note that the url can only be changed when the connection is in either the Disconnected or
  /// Reconnecting states.
  set baseUrl(String url) {
    if ((_connectionState != HubConnectionState.disconnected) &&
        (_connectionState != HubConnectionState.reconnecting)) {
      throw Exception(
          'The HubConnection must be in the Disconnected or Reconnecting state to change the url.');
    }

    if (url.isEmpty) {
      throw Exception('The HubConnection url must be a valid url.');
    }

    _connection.baseUrl = url;
  }

  /// Starts the connection.
  Future<void> start() {
    _startFuture = _startWithStateTransitions();
    return _startFuture;
  }

  Future<void> _startWithStateTransitions() async {
    if (_connectionState != HubConnectionState.disconnected) {
      return Future.error(Exception(
          'Cannot start a HubConnection that is not in the \'Disconnected\' state.'));
    }

    _connectionState == HubConnectionState.connecting;
    _logger(LogLevel.debug, 'Starting HubConnection.');

    try {
      await _startInternal();

      _connectionState = HubConnectionState.connected;
      _connectionStarted = true;
      _logger(LogLevel.debug, 'HubConnection connected successfully.');
    } catch (e) {
      _connectionState = HubConnectionState.disconnected;
      _logger(LogLevel.debug,
          'HubConnection failed to start successfully because of error \'{$e.toString}\'.');
      return Future.error(e);
    }
  }

  Future<void> _startInternal() async {
    _stopDuringStartError = null;
    _receivedHandshakeResponse = false;

    _handshakeCompleter = Completer();
    final handshakeFuture = _handshakeCompleter.future;

    // Set up the promise before any connection is (re)started otherwise it could race with received messages
    // final handshakeFuture = Future.value((resolve, reject) async => {
    //   _handshakeResolver = resolve,
    //   _handshakeRejector = reject
    // });

    await _connection.start(transferFormat: _protocol.transferFormat);

    try {
      final handshakeRequest = HandshakeRequestMessage(
          protocol: _protocol.name, version: _protocol.version);

      _logger(LogLevel.debug, 'Sending handshake request.');

      await _sendMessage(
          _handshakeProtocol.writeHandshakeRequest(handshakeRequest));

      _logger(LogLevel.information, 'Using HubProtocol \'${_protocol.name}\'.');

      // defensively cleanup timeout in case we receive a message from the server before we finish start
      _cleanupTimeout();
      _resetTimeoutPeriod();
      _resetKeepAliveInterval();

      await handshakeFuture;

      // It's important to check the stopDuringStartError instead of just relying on the handshakePromise
      // being rejected on close, because this continuation can run after both the handshake completed successfully
      // and the connection was closed.
      if (_stopDuringStartError != null) {
        // It's important to throw instead of returning a rejected promise, because we don't want to allow any state
        // transitions to occur between now and the calling code observing the exceptions. Returning a rejected promise
        // will cause the calling continuation to get scheduled to run later.
        throw _stopDuringStartError;
      }
    } catch (e) {
      _logger(LogLevel.debug,
          'Hub handshake failed with error \'${e.toString()}\' during start(). Stopping HubConnection.');

      _cleanupTimeout();
      _cleanupPingTimer();

      // HttpConnection.stop() should not complete until after the onclose callback is invoked.
      // This will transition the HubConnection to the disconnected state before HttpConnection.stop() completes.
      await _connection.stop(exception: e);
      rethrow;
    }
  }

  /// Stops the connection.
  Future<void> stop() async {
    // Capture the start future before the connection might be restarted in an onclose callback.
    final startFuture = _startFuture;

    _stopFuture = _stopInternal();
    await _stopFuture;

    try {
      // Awaiting undefined continues immediately
      await startFuture;
    } catch (e) {
      // This exception is returned to the user as a rejected Future from the start method.
    }
  }

  Future<void> _stopInternal({Exception exception}) async {
    if (_connectionState == HubConnectionState.disconnected) {
      _logger(LogLevel.debug,
          'Call to HubConnection.stop(${exception.toString()}) ignored because it is already in the disconnected state.');
      return Future.value(null);
    }

    if (_connectionState == HubConnectionState.disconnecting) {
      _logger(LogLevel.debug,
          'Call to HttpConnection.stop(${exception.toString()}) ignored because the connection is already in the disconnecting state.');
      return _stopFuture;
    }

    _connectionState = HubConnectionState.disconnecting;

    _logger(LogLevel.debug, 'Stopping HubConnection');

    if (_reconnectDelayHandle != null) {
      // We're in a reconnect delay which means the underlying connection is currently already stopped.
      // Just clear the handle to stop the reconnect loop (which no one is waiting on thankfully) and
      // fire the onclose callbacks.
      _logger(LogLevel.debug,
          "Connection stopped during reconnect delay. Done reconnecting.");

      _clearTimeout(_reconnectDelayHandle);
      _reconnectDelayHandle = null;

      _completeClose();
      return Future.value(null);
    }

    _cleanupTimeout();
    _cleanupPingTimer();
    _stopDuringStartError = (exception != null)
        ? exception
        : Exception(
            'The connection was stopped before the hub handshake could complete.');

    // HttpConnection.stop() should not complete until after either HttpConnection.start() fails
    // or the onclose callback is invoked. The onclose callback will transition the HubConnection
    // to the disconnected state if need be before HttpConnection.stop() completes.
    return _connection.stop(exception: exception);
  }

  /// Invokes a hub method on the server using the specified name and arguments. Does not wait for a response from the receiver.
  ///
  /// The Promise returned by this method resolves when the client has sent the invocation to the server. The server may still
  /// be processing the invocation.
  Future<void> send({String methodName, List<dynamic> args}) {
    final Tuple2<Map<int, Stream<dynamic>>, List<String>> streamParameters =
        _replaceStreamParameters(args);
    final sendPromise = _sendWithProtocol(_createInvocation(
        methodName: methodName,
        args: args,
        nonblocking: true,
        streamIds: streamParameters.item2));

    _launchStreams(streamParameters.item1, sendPromise);

    return sendPromise;
  }

  Future<void> _sendMessage(dynamic message) {
    _resetKeepAliveInterval();
    return _connection.send(message);
  }

  Future<void> _sendWithProtocol(dynamic message) {
    return _sendMessage(_protocol.writeMessage(message));
  }

  void _resetKeepAliveInterval() {
    // if (_connection.features.inherentKeepAlive) {
    //   return;
    // }

    _cleanupPingTimer();
    _pingServerHandle =
        Timer.periodic(Duration(milliseconds: keepAliveIntervalInMilliseconds),
            (Timer timer) async {
      if (_connectionState == HubConnectionState.connected) {
        try {
          await _sendMessage(_cachedPingMessage);
        } catch (e) {
          //We don't care about the error. It should be seen elsewhere in the client.
          // The connection is probably in a bad or closed state now, cleanup the timer so it stops triggering
          _cleanupPingTimer();
        }
      }
    });
  }

  void _resetTimeoutPeriod() {
    if ((_connection.features != null) ||
        (!_connection.features.inherentKeepAlive)) {
      // Set the timeout timer
      _timeoutHandle = Timer.periodic(
          Duration(milliseconds: serverTimeoutInMilliseconds), (Timer timer) {
        _serverTimeout();
        timer.cancel();
      });
    }
  }

  void _serverTimeout() {
    // The server hasn't talked to us in a while. It doesn't like us anymore ... :(
    // Terminate the connection, but we don't need to wait on the promise. This could trigger reconnecting.
    // tslint:disable-next-line:no-floating-promises
    _connection.stop(
        exception: Exception(
            'Server timeout elapsed without receiving a message from the server.'));
  }

  void _completeClose({Exception exception}) {
    if (_connectionStarted) {
      _connectionState = HubConnectionState.disconnected;
      _connectionStarted = false;

      try {
        _closedCallbacks.forEach((c) => c(exception));
      } catch (e) {
        _logger(LogLevel.error,
            'An onclose callback called with error \'${exception.toString()}\' threw error \'${e.toString()}\'.');
      }
    }
  }

  Future<void> _reconnect({Exception exception}) async {
    final reconnectStartTime = Stopwatch()..start();
    //final reconnectStartTime = DateTime.now();
    int previousReconnectAttempts = 0;
    Exception retryError = (exception != null)
        ? exception
        : Exception('Attempting to reconnect due to a unknown error.');

    var nextRetryDelay = _getNextRetryDelay(
        previousRetryCount: previousReconnectAttempts++,
        elapsedMilliseconds: 0,
        retryReason: retryError);

    if (nextRetryDelay == null) {
      _logger(LogLevel.debug,
          'Connection not reconnecting because the RetryPolicy returned null on the first reconnect attempt.');
      _completeClose(exception: exception);
      return;
    }

    _connectionState = HubConnectionState.reconnecting;

    if (exception != null) {
      _logger(LogLevel.information,
          'Connection reconnecting because of error \'${exception}\'.');
    } else {
      _logger(LogLevel.information, 'Connection reconnecting.');
    }

    if (onreconnecting != null) {
      try {
        _reconnectingCallbacks.forEach((c) => c(exception));
      } catch (e) {
        _logger(LogLevel.error,
            'An onreconnecting callback called with error \'${exception}\' threw error \'${e}\'.');
      }

      // Exit early if an onreconnecting callback called connection.stop().
      if (_connectionState != HubConnectionState.reconnecting) {
        _logger(LogLevel.debug,
            'Connection left the reconnecting state in onreconnecting callback. Done reconnecting.');
        return;
      }
    }

    while (nextRetryDelay != null) {
      _logger(LogLevel.information,
          'Reconnect attempt number ${previousReconnectAttempts} will start in ${nextRetryDelay} ms.');

      await Future.value((resolve) async {
        _reconnectDelayHandle =
            Timer.periodic(Duration(milliseconds: nextRetryDelay), resolve);
      });
      _reconnectDelayHandle = null;

      if (_connectionState != HubConnectionState.reconnecting) {
        _logger(LogLevel.debug,
            'Connection left the reconnecting state during reconnect delay. Done reconnecting.');
        return;
      }

      try {
        await _startInternal();

        _connectionState = HubConnectionState.connected;
        _logger(
            LogLevel.information, 'HubConnection reconnected successfully.');

        if (onreconnected != null) {
          try {
            _reconnectedCallbacks.forEach((c) => c(_connection.connectionId));
          } catch (e) {
            _logger(LogLevel.error,
                'An onreconnected callback called with connectionId \'${_connection.connectionId}; threw error \'${e.toString()}\'.');
          }
        }

        return;
      } catch (e) {
        _logger(LogLevel.information,
            'Reconnect attempt failed because of error \'${e.toString()}\'.');

        if (_connectionState != HubConnectionState.reconnecting) {
          _logger(LogLevel.debug,
              'Connection left the reconnecting state during reconnect attempt. Done reconnecting.');
          return;
        }

        retryError = (e is Exception) ? e : Exception(e.toString());
        nextRetryDelay = _getNextRetryDelay(
            previousRetryCount: previousReconnectAttempts++,
            elapsedMilliseconds: reconnectStartTime.elapsedMilliseconds,
            retryReason: retryError);
      }
    }

    _logger(LogLevel.information,
        'Reconnect retries have been exhausted after ${reconnectStartTime.elapsedMilliseconds} ms and ${previousReconnectAttempts} failed attempts. Connection disconnecting.');

    _completeClose();
  }

  int _getNextRetryDelay(
      {int previousRetryCount,
      int elapsedMilliseconds,
      Exception retryReason}) {
    try {
      return _reconnectPolicy.nextRetryDelayInMilliseconds(RetryContext(
          elapsedMilliseconds: elapsedMilliseconds,
          previousRetryCount: previousRetryCount,
          retryReason: retryReason));
    } catch (e) {
      _logger(LogLevel.error,
          'RetryPolicy.nextRetryDelayInMilliseconds(${previousRetryCount}, ${elapsedMilliseconds}) threw error \'${e.toString()}\'.');
      return null;
    }
  }

  /// Invokes a streaming hub method on the server using the specified name and arguments.
  Stream<T> stream<T>(String methodName, {List<dynamic> args}) {
    final Tuple2<Map<int, Stream<dynamic>>, List<String>> streamParameters =
        _replaceStreamParameters(args);
    final invocationDescriptor = _createStreamInvocation(
        methodName: methodName, args: args, streamIds: streamParameters.item2);

    Future<void> futureQueue;
    final controller = StreamController<T>();
    controller.onCancel = () {
      final cancelInvocation =
          _createCancelInvocation(id: invocationDescriptor.invocationId);

      _callbacks.remove(invocationDescriptor.invocationId);

      futureQueue.then((value) {
        return _sendWithProtocol(cancelInvocation);
      });
    };

    _callbacks[invocationDescriptor.invocationId] =
        (HubMessage invocationEvent, Exception error) {
      if (error != null) {
        controller.addError(error);
        return;
      } else if (invocationEvent != null) {
        if (invocationEvent.type == MessageType.completion) {
          if (invocationEvent is CompletionMessage) {
            if (invocationEvent.error != null) {
              if (invocationEvent.error.isNotEmpty) {
                controller.addError(Exception(error));
              } else {
                controller.close();
              }
            } else {
              controller.close();
            }
          }
        } else {
          if (invocationEvent is StreamItemMessage) {
            controller.add((invocationEvent.item) as T);
          }
        }
      }
    };

    futureQueue = _sendWithProtocol(invocationDescriptor).catchError((e) {
      controller.addError(e);
      _callbacks.remove(invocationDescriptor.invocationId);
    });

    _launchStreams(streamParameters.item1, futureQueue);

    return controller.stream;
  }

  /// Invokes a hub method on the server using the specified name and arguments.
  ///
  /// The Future returned by this method resolves when the server indicates it has finished invoking the method. When the future
  /// resolves, the server has finished invoking the method. If the server method returns a result, it is produced as the result of
  /// resolving the Future.
  Future<dynamic> invoke(String methodName, {List<dynamic> args}) {
    final Tuple2<Map<int, Stream<dynamic>>, List<String>> streamParameters =
        _replaceStreamParameters(args);
    final invocationDescriptor = _createInvocation(
        methodName: methodName,
        args: args,
        nonblocking: false,
        streamIds: streamParameters.item2);

    final p = Completer<dynamic>();

    _callbacks[invocationDescriptor.invocationId] =
        (HubMessage invocationEvent, Exception error) {
      if (error != null) {
        p.completeError(error);
      } else if (invocationEvent != null) {
        // invocationEvent will not be null when an error is not passed to the callback
        if (invocationEvent.type == MessageType.completion) {
          if (invocationEvent is CompletionMessage) {
            if (invocationEvent.error != null) {
              p.completeError(Exception(invocationEvent.error));
            } else {
              p.complete(invocationEvent.result);
            }
          } else {
            p.completeError(
                Exception('Unexpected message type: ${invocationEvent.type}'));
          }
        }
      }
    };

    final futureQueue = _sendWithProtocol(invocationDescriptor).catchError((e) {
      p.completeError(e);
      _callbacks.remove(invocationDescriptor.invocationId);
    });

    _launchStreams(streamParameters.item1, futureQueue);

    return p.future;
  }

  Tuple2<Map<int, Stream<dynamic>>, List<String>> _replaceStreamParameters(
      List<dynamic> args) {
    final Map<int, Stream<dynamic>> streams = {};
    final List<String> streamIds = [];

    for (var i = 0; i < args.length; i++) {
      final argument = args[i];
      if (argument is Stream) {
        final streamId = _invocationId;
        _invocationId++;
        // Store the stream for later use
        streams[streamId] = argument;
        streamIds.add(streamId.toString());

        // remove stream from args
        args.removeAt(i);
      }
    }

    return Tuple2<Map<int, Stream<dynamic>>, List<String>>(streams, streamIds);
  }

  /// Registers a handler that will be invoked when the hub method with the specified method name is invoked.
  void on(String methodName, MethodInvacationFunc newMethod) {
    if (methodName.isEmpty || newMethod == null) {
      return;
    }

    methodName = methodName.toLowerCase();
    if (_methods[methodName] == null) {
      _methods[methodName] = [];
    }

    // Preventing adding the same handler multiple times.
    if (_methods[methodName].contains(newMethod)) {
      return;
    }

    _methods[methodName].add(newMethod);
  }

  /// Removes all handlers for the specified hub method.
  void off(String methodName, {MethodInvacationFunc method}) {
    if (methodName.isEmpty) {
      return;
    }

    methodName = methodName.toLowerCase();
    final handlers = _methods[methodName];
    if (handlers == null) {
      return;
    }

    if (method != null) {
      final removeIdx = handlers.indexOf(method);
      if (removeIdx != -1) {
        handlers.removeAt(removeIdx);
        if (handlers.isEmpty) {
          _methods.remove(methodName);
        }
      }
    } else {
      _methods.remove(methodName);
    }
  }

  void _processIncomingData(dynamic data) {
    _cleanupTimeout();

    if (_receivedHandshakeResponse == false) {
      data = _processHandshakeResponse(data);
      _receivedHandshakeResponse = true;
    }

    // Data may have all been read when processing handshake response
    if (data != null) {
      // Parse the messages
      final messages = _protocol.parseMessages(data, _logger);

      for (final message in messages) {
        switch (message.type) {
          case MessageType.undefined:
            break;
          case MessageType.invocation:
            _invokeClientMethod(message);
            break;
          case MessageType.streamItem:
          case MessageType.completion:
            var invovationMessage = message as HubInvocationMessage;
            final callback = _callbacks[invovationMessage.invocationId];

            if (callback != null) {
              if (message.type == MessageType.completion) {
                _callbacks.remove(invovationMessage.invocationId);
              }
              callback(message, null);
            }

            break;
          case MessageType.streamInvocation:
            break;
          case MessageType.cancelInvocation:
            break;
          case MessageType.ping:
            break;
          case MessageType.close:
            final closeMessage = message as CloseMessage;
            _logger(
                LogLevel.information, 'Close message received from server.');

            final exception = (closeMessage.error != null)
                ? Exception(
                    'Server returned an error on close: ' + closeMessage.error)
                : null;

            if (closeMessage.allowReconnect == true) {
              // It feels wrong not to await connection.stop() here, but processIncomingData is called as part of an onreceive callback which is not async,
              // this is already the behavior for serverTimeout(), and HttpConnection.Stop() should catch and log all possible exceptions.

              _connection.stop(exception: exception);
            } else {
              // We cannot await stopInternal() here, but subsequent calls to stop() will await this if stopInternal() is still ongoing.
              _stopFuture = _stopInternal(exception: exception);
            }
            break;
          default:
            _logger(LogLevel.warning, 'Invalid message type: ${message.type}.');
            break;
        }
      }
    }

    _resetTimeoutPeriod();
  }

  dynamic _processHandshakeResponse(dynamic data) {
    HandshakeResponseMessage responseMessage;
    dynamic remainingData;

    try {
      var response = _handshakeProtocol.parseHandshakeResponse(data);
      remainingData = response.item1;
      responseMessage = response.item2;
    } catch (e) {
      final message = 'Error parsing handshake response: ' + e.toString();
      _logger(LogLevel.error, message);

      final exception = Exception(message);
      _handshakeCompleter.completeError(exception);
      throw exception;
    }

    if (responseMessage.error != null) {
      final message =
          'Server returned handshake error: ' + responseMessage.error;
      _logger(LogLevel.error, message);

      final exception = Exception(message);
      _handshakeCompleter.completeError(exception);
      throw exception;
    } else {
      _logger(LogLevel.debug, 'Server handshake complete.');
    }

    _handshakeCompleter.complete();
    return remainingData;
  }

  void _connectionClosed({Exception exception}) {
    _logger(LogLevel.debug,
        'HubConnection.connectionClosed(${exception.toString()}) called while in state ${_connectionState.toString()}.');

    // Triggering this.handshakeRejecter is insufficient because it could already be resolved without the continuation having run yet.
    if (_stopDuringStartError == null) {
      _stopDuringStartError = (exception != null)
          ? exception
          : Exception(
              'The underlying connection was closed before the hub handshake could complete.');
    }

    // If the handshake is in progress, start will be waiting for the handshake future, so we complete it.
    // If it has already completed, this should just noop.
    if (!_handshakeCompleter.isCompleted) {
      _handshakeCompleter.complete();
    }

    _cancelCallbacksWithError((exception != null)
        ? exception
        : Exception(
            'Invocation canceled due to the underlying connection being closed.'));

    _cleanupTimeout();
    _cleanupPingTimer();

    if (_connectionState == HubConnectionState.disconnecting) {
      _completeClose(exception: exception);
    } else if ((_connectionState == HubConnectionState.connected) &&
        _reconnectPolicy != null) {
      _reconnect(exception: exception);
    } else if (_connectionState == HubConnectionState.connected) {
      _completeClose(exception: exception);
    }

    // If none of the above if conditions were true were called the HubConnection must be in either:
    // 1. The Connecting state in which case the handshakeResolver will complete it and stopDuringStartError will fail it.
    // 2. The Reconnecting state in which case the handshakeResolver will complete it and stopDuringStartError will fail the current reconnect attempt
    //    and potentially continue the reconnect() loop.
    // 3. The Disconnected state in which case we're already done.
  }

  void _cancelCallbacksWithError(Exception exception) {
    final callbacks = _callbacks;
    _callbacks = {};

    callbacks.forEach((key, value) {
      value(null, exception);
    });
  }

  InvocationMessage _createInvocation(
      {String methodName,
      List<dynamic> args,
      bool nonblocking,
      List<String> streamIds}) {
    if (nonblocking) {
      if (streamIds.isNotEmpty) {
        return InvocationMessage(
            arguments: args, streamIds: streamIds, target: methodName);
      } else {
        return InvocationMessage(arguments: args, target: methodName);
      }
    } else {
      final invocationId = _invocationId;
      _invocationId++;

      if (streamIds.isNotEmpty) {
        return InvocationMessage(
            arguments: args,
            invocationId: invocationId.toString(),
            streamIds: streamIds,
            target: methodName);
      } else {
        return InvocationMessage(
            arguments: args,
            invocationId: invocationId.toString(),
            target: methodName);
      }
    }
  }

  StreamInvocationMessage _createStreamInvocation(
      {String methodName, List<dynamic> args, List<String> streamIds}) {
    final invocationId = _invocationId;
    _invocationId++;

    if (streamIds.isNotEmpty) {
      return StreamInvocationMessage(
          arguments: args,
          invocationId: invocationId.toString(),
          streamIds: streamIds,
          target: methodName);
    } else {
      return StreamInvocationMessage(
          arguments: args,
          invocationId: invocationId.toString(),
          target: methodName);
    }
  }

  CancelInvocationMessage _createCancelInvocation({String id}) {
    return CancelInvocationMessage(invocationId: id);
  }

  StreamItemMessage _createStreamItemMessage({String id, dynamic item}) {
    return StreamItemMessage(invocationId: id, item: item);
  }

  CompletionMessage _createCompletionMessage(
      {String id, Exception exception, dynamic result}) {
    if (exception != null) {
      return CompletionMessage(
        error: exception.toString(),
        invocationId: id,
      );
    }

    return CompletionMessage(invocationId: id, result: result);
  }

  void _launchStreams(Map<int, Stream> streams, Future<void> futureQueue) {
    if (streams.isEmpty) {
      return;
    }

    if (futureQueue == null) {
      futureQueue = Completer<void>().future;
    }

    streams.forEach((streamId, stream) {
      stream.listen((data) {
        futureQueue = futureQueue.then((_) => _sendWithProtocol(
            _createStreamItemMessage(id: streamId.toString(), item: data)));
      }, onDone: () {
        futureQueue = futureQueue.then((_) => _sendWithProtocol(
            _createCompletionMessage(id: streamId.toString())));
      }, onError: (e) {
        futureQueue = futureQueue.then((_) => _sendWithProtocol(
            _createCompletionMessage(id: streamId.toString(), exception: e)));
      });
    });
  }

  /// Registers a handler that will be invoked when the connection is closed.
  void onclose(ClosedCallback callback) {
    if (callback != null) {
      _closedCallbacks.add(callback);
    }
  }

  /// Registers a handler that will be invoked when the connection starts reconnecting.
  void onreconnecting(ReconnectingCallback callback) {
    if (callback != null) {
      _reconnectingCallbacks.add(callback);
    }
  }

  /// Registers a handler that will be invoked when the connection successfully reconnects.
  void onreconnected(ReconnectedCallback callback) {
    if (callback != null) {
      _reconnectedCallbacks.add(callback);
    }
  }

  void _cleanupPingTimer() {
    if (_pingServerHandle != null) {
      _clearTimeout(_pingServerHandle);
    }
  }

  void _cleanupTimeout() {
    if (_timeoutHandle != null) {
      _clearTimeout(_timeoutHandle);
    }
  }

  void _clearTimeout(Timer timer) {
    timer?.cancel();
    timer = null;
  }

  void _invokeClientMethod(InvocationMessage invocationMessage) {
    final methods = _methods[invocationMessage.target.toLowerCase()];

    if (methods != null) {
      try {
        methods.forEach((method) => method(invocationMessage.arguments));
      } catch (e) {
        _logger(LogLevel.error,
            'A callback for the method ${invocationMessage.target.toLowerCase()} threw error \'${e.toString()}\'.');
      }

      if (invocationMessage.invocationId != null) {
        // This is not supported in v1. So we return an error to avoid blocking the server waiting for the response.
        final message =
            'Server requested a response, which is not supported in this version of the client.';
        _logger(LogLevel.error, message);

        // We don't want to wait on the stop itself.
        _stopFuture = _stopInternal(exception: Exception(message));
      }
    } else {
      _logger(LogLevel.warning,
          'No client method with the name \'${invocationMessage.target}\' found.');
    }
  }
}
