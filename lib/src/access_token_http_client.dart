import 'dart:async';

import 'package:http/http.dart' as http;
import 'header_names.dart';

class AccessTokenHttpClient extends http.BaseClient {
  final http.Client _innerClient;
  String? _accessToken;
  final FutureOr<String> Function()? _accessTokenFactory;

  AccessTokenHttpClient(
      http.Client httpClient, FutureOr<String> Function()? accessTokenFactory)
      : _innerClient = httpClient,
        _accessTokenFactory = accessTokenFactory;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var allowRetry = true;

    if (_accessTokenFactory != null &&
        (_accessToken == null ||
            request.url.toString().indexOf("/negotiate?") > 0)) {
      allowRetry = false;
      _accessToken = await _accessTokenFactory.call();
    }
    _setAuthorizationHeader(request);
    final response = await _innerClient.send(request);

    if (allowRetry &&
        response.statusCode == 401 &&
        _accessTokenFactory != null) {
      _accessToken = await _accessTokenFactory.call();
      _setAuthorizationHeader(request);
      return await _innerClient.send(request);
    }
    return response;
  }

  void _setAuthorizationHeader(http.BaseRequest request) {
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    } else if (_accessTokenFactory != null) {
      if (request.headers.containsKey(HeaderNames.authorization)) {
        request.headers.remove(HeaderNames.authorization);
      }
    }
  }

  String getCookieString(String url) {
    return '';
  }
}
