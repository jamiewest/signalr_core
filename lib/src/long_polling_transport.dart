import 'package:http/http.dart';
import 'package:signalr/signalr.dart';

class LongPollingTransport implements Transport {
  BaseClient _client;
  AccessTokenFactory _accessTokenFactory;
  Logging _log;
  bool _logMessageContent;
  bool _withCredentials;

  String _url;
  bool _running;
  Future<void> _receiving;
  Exception _closeError;

  OnReceive _onreceive;
  OnClose _onclose;

  LongPollingTransport({
    BaseClient client, 
    AccessTokenFactory accessTokenFactory,
    Logging log,
    bool logMessageContent,
    bool withCredentials
  }) : 
    _client = client,
    _accessTokenFactory = accessTokenFactory,
    _log = log,
    _logMessageContent = logMessageContent,
    _withCredentials = withCredentials {

    _running = false;
    _onreceive = null;
    _onclose = null;
  }

  @override
  var onClose;

  @override
  var onReceive;

  @override
  Future<void> connect(String url, TransferFormat transferFormat) async {
    _url = url;

    _log(LogLevel.trace, '(LongPolling transport) Connecting.');

    final headers = <String, String>{};
    final userAgentHeader = getUserAgentHeader();
    headers[userAgentHeader.item1] = userAgentHeader.item2;
  
    final token = await _getAccessToken();
    if (token != null) {
      headers['Authorization']  = 'Bearer ${token}';
    }

    // Make initial long polling request
    // Server uses first long polling request to finish initializing connection and it returns without data
    final pollUrl = '${url}&_=${DateTime.now().millisecondsSinceEpoch}';
    _log(LogLevel.trace, '(LongPolling transport) polling: ${pollUrl}.');
    final response = await _client.get(pollUrl, headers: headers);
    if (response.statusCode != 200) {
      _log(LogLevel.error, '(LongPolling transport) Unexpected response code: ${response.statusCode}.');

      // Mark running as false so that the poll immediately ends and runs the close logic
      _closeError = HttpError(statusCode: response.statusCode);
      _running = false;

    } else {
      _running = true;
    }

    _receiving = _poll(_url, headers);
  }

  Future<String> _getAccessToken() async {
    if (_accessTokenFactory != null) {
      return await _accessTokenFactory();
    }

    return null;
  }

  Future<void> _poll(String url, Map<String, String> headers) async {
    try {
      while (_running) {
        // We have to get the access token on each poll, in case it changes
        final token = await _getAccessToken();
        if (token != null) {
          headers['Authorization']  = 'Bearer ${token}';
        }

        final pollUrl = '${url}&_=${DateTime.now().millisecondsSinceEpoch}';
        _log(LogLevel.trace, '(LongPolling transport) polling: ${pollUrl}.');
        final response = await _client.get(pollUrl, headers: headers);

        if (response.statusCode == 204) {
          _log(LogLevel.information, '(LongPolling transport) Poll terminated by server.');

          _running = false;
        } else if (response.statusCode != 200) {
          _log(LogLevel.error, '(LongPolling transport) Unexpected response code: ${response.statusCode}.');

          // Unexpected status code
          _closeError = HttpError(statusCode: response.statusCode);
          _running = false;
        } else {
          // Process the response
          if (response.body != null) {
            _log(LogLevel.trace, '(LongPolling transport) data received. ${getDataDetail(response.body, _logMessageContent)}.');
            if (onReceive != null) {
              onReceive(response.body);
            }
          } else {
            // This is another way timeout manifest.
            _log(LogLevel.trace, '(LongPolling transport) Poll timed out, reissuing.');
          }
        }

      }
    } catch (e) {
      if (!_running) {
        // Log but disregard errors that occur after stopping
        _log(LogLevel.trace, '(LongPolling transport) Poll errored after shutdown: ${e.message}');
      } else {
        if (e is TimeoutError) {
          // Ignore timeouts and reissue the poll.
          _log(LogLevel.trace, '(LongPolling transport) Poll timed out, reissuing.');
        } else {
          // Close the connection with the error as the result.
          _closeError = e;
          _running = false;
        }
      }
    } finally {
      _log(LogLevel.trace, '(LongPolling transport) Polling complete.');

      // We will reach here with pollAborted==false when the server returned a response causing the transport to stop.
      // If pollAborted==true then client initiated the stop and the stop method will raise the close event after DELETE is sent.
      // if (_pollAborted) {
      //   _raiseOnClose();
      // }
    }
  }

  @override
  Future<void> send(data) async {
    if (!_running) {
      return Future.error(Exception('Cannot send until the transport is connected'));
    }
    return sendMessage(_log, 'LongPolling', _client, _url, _accessTokenFactory, data, _logMessageContent, _withCredentials);
  }

  @override
  Future<void> stop() async {
    _log(LogLevel.trace, '(LongPolling transport) Stopping polling.');

    // Tell receiving loop to stop, abort any current request, and then wait for it to finish
    _running = false;
    //_pollAbort.abort();

    try {
      await _receiving;

      // Send DELETE to clean up long polling on the server
      _log(LogLevel.trace, '(LongPolling transport) sending DELETE request to ${_url}.');

      final headers = <String, String>{};
      final userAgentHeader = getUserAgentHeader();
      headers[userAgentHeader.item1] = userAgentHeader.item2;
    
      final token = await _getAccessToken();
      if (token != null) {
        headers['Authorization']  = 'Bearer ${token}';
      }

      await _client.delete(_url, headers: headers);

      _log(LogLevel.trace, '(LongPolling transport) DELETE request sent.');
    } finally {
      _log(LogLevel.trace, '(LongPolling transport) Stop finished.');

      // Raise close event here instead of in polling
      // It needs to happen after the DELETE request is sent
      _raiseOnClose();
    }
  }

  void _raiseOnClose() {
    if (onClose !=null) {
      var logMessage = '(LongPolling transport) Firing onclose event.';
      if (_closeError != null) {
        logMessage += ' Error: ' + _closeError.toString();
      }
      _log(LogLevel.trace, logMessage);
      onClose(_closeError);
    }
  }
}