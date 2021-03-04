import 'package:http/http.dart';
import 'package:signalr_core/src/transport.dart';
import 'package:signalr_core/src/utils.dart';

/// Options provided to the 'withUrl' factory constructor on [HubConnection] to configure options for the HTTP-based transports.
class HttpConnectionOptions {
  HttpConnectionOptions({
    this.client,
    this.transport,
    this.logging,
    this.accessTokenFactory,
    this.logMessageContent = false,
    this.skipNegotiation = false,
    this.withCredentials = true,
  });

  /// An [BaseClient] that will be used to make HTTP requests.
  final BaseClient? client;

  /// An [HttpTransportType] or [Transport] value specifying the transport to use for the connection.
  final dynamic transport;

  /// Configures the logger used for logging.
  ///
  /// Provide an [Logger] instance, and log messages will be logged via that instance.
  final Logging? logging;

  /// A function that provides an access token required for HTTP Bearer authentication.
  ///
  /// A string containing the access token, or a Future that resolves to a string containing the access token.
  final AccessTokenFactory? accessTokenFactory;

  /// A boolean indicating if message content should be logged.
  ///
  /// Message content can contain sensitive user data, so this is disabled by default.
  final bool logMessageContent;

  /// A boolean indicating if negotiation should be skipped.
  ///
  /// Negotiation can only be skipped when the [transport] property is set to 'HttpTransportType.WebSockets'.
  final bool skipNegotiation;

  /// This controls whether credentials such as cookies are sent in cross-site requests.
  ///
  /// Cookies are used by many load-balancers for sticky sessions which is required when your app is deployed with multiple servers.
  final bool withCredentials;
}
