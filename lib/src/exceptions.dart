/// Exception thrown when an HTTP request fails.
class HttpException implements Exception {
  HttpException({
    required this.statusCode,
    required this.message,
  });

  /// The HTTP status code represented by this error.
  final int statusCode;

  final String message;

  @override
  String toString() => '$message: Status code \'$statusCode\'';
}

/// Exception thrown when a timeout elapses.
class TimeoutException implements Exception {
  TimeoutException({
    this.message = 'A timeout occurred.',
  });

  final String? message;

  @override
  String toString() => message!;
}

/// Exception thrown when a timeout elapses.
class AbortException implements Exception {
  AbortException({
    this.message = 'A abort occurred.',
  });

  final String? message;

  @override
  String toString() => message!;
}

/// Exception thrown when the selected transport is unsupported by the browser.
class UnsupportedTransportException implements Exception {
  UnsupportedTransportException({
    required this.transport,
    required this.message,
  });

  final int transport;

  final String message;

  @override
  String toString() => message;
}

/// Exception thrown when the selected transport is disabled by the browser.
class DisabledTransportException implements Exception {
  DisabledTransportException({
    required this.transport,
    required this.message,
  });

  final int transport;

  final String message;

  @override
  String toString() => message;
}

/// Exception thrown when the selected transport is disabled by the browser.
class FailedToStartTransportException implements Exception {
  FailedToStartTransportException({
    required this.transport,
    required this.message,
  });

  final int transport;

  final String message;

  @override
  String toString() => message;
}

/// Exception thrown when the negotiation with the server failed to complete.
class FailedToNegotiateWithServerException implements Exception {
  FailedToNegotiateWithServerException({
    required this.message,
  });

  final String message;

  @override
  String toString() => message;
}

/// Exception thrown when multiple errors have occurred.
class AggregateExceptions implements Exception {
  AggregateExceptions({
    required this.innerExceptions,
    required this.message,
  });

  final List<Exception> innerExceptions;

  final String message;

  @override
  String toString() => message;
}
