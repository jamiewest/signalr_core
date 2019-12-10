import 'package:signalr/signalr.dart';

/// A builder for configuring [HubConnection] instances.
class HubConnectionBuilder {
  HubProtocol _protocol;
  HttpConnectionOptions _httpConnectionOptions;
  HttpTransportType _httpTransportType;
  String _url;
  RetryPolicy _reconnectPolicy;

  /// Configures the [HubConnection] to use HTTP-based transports to connect to the specified URL.
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
  HubConnectionBuilder withHubProtocol(HubProtocol protocol) {
    _protocol = protocol;
    return this;
  }

  /// Configures the [HubConnection] to automatically attempt to reconnect if the connection is lost.
   HubConnectionBuilder withAutomaticReconnect([dynamic retryDelaysOrReconnectPolicy]) {
    if (_reconnectPolicy != null) {
      throw Exception('A reconnectPolicy has already been set.');
    }

    if (retryDelaysOrReconnectPolicy == null) {
      _reconnectPolicy = DefaultReconnectPolicy();
    } else if (retryDelaysOrReconnectPolicy is List) {
      _reconnectPolicy = DefaultReconnectPolicy(retryDelays: retryDelaysOrReconnectPolicy);
    } else if (retryDelaysOrReconnectPolicy is RetryPolicy) {
      _reconnectPolicy = retryDelaysOrReconnectPolicy;
    }

    return this;
  }

  /// Creates a [HubConnection] from the configuration options specified in this builder.
  HubConnection build() {
    // Now create the connection
    if (_url == null) {
      throw Exception('The \'HubConnectionBuilder.withUrl\' method must be called before building the connection.');
    }
    final connection = HttpConnection(url: _url, options: _httpConnectionOptions);

    return HubConnection(
      connection: connection,
      logging: _httpConnectionOptions.logging,
      protocol: (_protocol == null) ? JsonHubProtocol() : _protocol,
      reconnectPolicy: _reconnectPolicy
    );
  }
}