class AbortController implements AbortSignal {
  bool _isAborted = false;
  void abort() {
    if (!_isAborted) {
      _isAborted = true;
      if (onAbort != null) {
        onAbort?.call();
      }
    }
  }

  AbortSignal get signal => this;

  @override
  bool get aborted => _isAborted;

  @override
  void Function()? onAbort;
}

/// Represents a signal that can be monitored to determine if a request
/// has been aborted.
abstract class AbortSignal {
  /// Indicates if the request has been aborted.
  bool get aborted;

  /// Set this to a handler that will be invoked when the request is aborted.
  void Function()? onAbort;
}
