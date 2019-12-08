class HttpError implements Exception {
  HttpError({
    this.statusCode,
    this.errorMessage
  });

  /// The HTTP status code represented by this error.
  final int statusCode;

  /// A descriptive error message.
  final String errorMessage;
}

class TimeoutError implements Exception {
  TimeoutError({
    this.errorMessage = 'A timeout occured.'
  });

  final String errorMessage;
}

class AbortException implements Exception {
  AbortException({
    this.errorMessage = 'An abort occured.'
  });

  final String errorMessage;
}