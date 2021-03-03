import 'package:signalr_core/signalr_core.dart';

/// A builder for configuring [HubConnection] instances.
class HubConnectionBuilder {
  HubProtocol _protocol;
  HttpConnectionOptions _httpConnectionOptions;
  HttpTransportType _httpTransportType;
  String _url;
  RetryPolicy reconnectPolicy;

  /// Configures the [HubConnection] to use HTTP-based transports to connect to the specified URL.
  // ignore: avoid_returning_this
  HubConnectionBuilder withUrl(String url, [dynamic transportTypeOrOptions]) {
    _url = url;

    if (transportTypeOrOptions != null) {
      if (transportTypeOrOptions is HttpConnectionOptions) {
        _httpConnectionOptions = transportTypeOrOptions;
      } else if (transportTypeOrOptions is HttpTransportType) {
        _httpTransportType = transportTypeOrOptions;
      }
    }

    return this;
  }

  /// Configures the [HubConnection] to use the specified Hub Protocol.
  // ignore: avoid_returning_this
  HubConnectionBuilder withHubProtocol(HubProtocol protocol) {
    _protocol = protocol;
    return this;
  }

  /// Configures the [HubConnection] to automatically attempt to reconnect if the connection is lost.
  // ignore: avoid_returning_this
  HubConnectionBuilder withAutomaticReconnect(
      [dynamic retryDelaysOrReconnectPolicy]) {
    if (reconnectPolicy != null) {
      throw Exception('A reconnectPolicy has already been set.');
    }

    if (retryDelaysOrReconnectPolicy == null) {
      reconnectPolicy = DefaultReconnectPolicy();
    } else if (retryDelaysOrReconnectPolicy is List) {
      reconnectPolicy = DefaultReconnectPolicy(
        retryDelays: retryDelaysOrReconnectPolicy as List<int>,
      );
    } else if (retryDelaysOrReconnectPolicy is RetryPolicy) {
      reconnectPolicy = retryDelaysOrReconnectPolicy;
    }

    return this;
  }

  /// Creates a [HubConnection] from the configuration options specified in this builder.
  HubConnection build() {
    // Now create the connection
    if (_url == null) {
      throw Exception(
          'The \'HubConnectionBuilder.withUrl\' method must be called before building the connection.');
    }

    _httpConnectionOptions ??=
        HttpConnectionOptions(transport: _httpTransportType);

    final connection =
        HttpConnection(url: _url, options: _httpConnectionOptions);

    return HubConnection(
      connection: connection,
      logging: (_httpConnectionOptions.logging != null)
          ? _httpConnectionOptions.logging
          : (l, m) => {},
      protocol: (_protocol == null) ? JsonHubProtocol() : _protocol,
      reconnectPolicy: reconnectPolicy,
    );
  }
}
