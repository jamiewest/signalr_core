/// Log Levels are ordered in increasing severity. So `Debug` is more severe than `Trace`, etc.
enum LogLevel {
  /// Log level for very low severity diagnostic messages.
  trace,

  /// Log level for low severity diagnostic messages.
  debug,

  /// Log level for informational diagnostic messages.
  information,

  /// Log level for diagnostic messages that indicate a non-fatal problem.
  warning,

  /// Log level for diagnostic messages that indicate a failure in the current operation.
  error,

  /// Log level for diagnostic messages that indicate a failure that will terminate the entire application.
  critical,

  /// The highest possible log level. Used when configuring logging to indicate that no log messages should be emitted.
  none,
}
