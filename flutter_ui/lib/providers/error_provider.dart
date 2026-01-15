// Error Provider
//
// Manages error state from Rust engine and provides:
// - Error polling from FFI
// - Error queue for displaying multiple errors
// - Error dialog presentation
// - Action handling (retry, dismiss, settings, browse)

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../src/rust/engine_api.dart';

/// Error provider for managing Rust engine errors in Flutter UI
class ErrorProvider extends ChangeNotifier {
  /// Queue of pending errors to display
  final List<AppError> _errorQueue = [];

  /// Currently displayed error (if any)
  AppError? _currentError;

  /// Timer for polling errors from engine
  Timer? _pollTimer;

  /// Is error dialog currently showing
  bool _isDialogShowing = false;

  // Getters
  List<AppError> get errorQueue => List.unmodifiable(_errorQueue);
  AppError? get currentError => _currentError;
  bool get hasErrors => _errorQueue.isNotEmpty || _currentError != null;
  bool get isDialogShowing => _isDialogShowing;

  /// Start polling for errors from Rust engine
  void startPolling({Duration interval = const Duration(milliseconds: 100)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _checkForErrors());
  }

  /// Stop polling
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Check for new errors from engine
  void _checkForErrors() {
    if (hasError()) {
      final error = getLastAppError();
      if (error != null) {
        _enqueueError(error);
        clearError(); // Clear from Rust side
      }
    }
  }

  /// Add error to queue
  void _enqueueError(AppError error) {
    // Avoid duplicates (same code within 1 second)
    final isDuplicate = _errorQueue.any((e) =>
      e.code == error.code &&
      (error.timestamp - e.timestamp).abs() < 1000
    );

    if (!isDuplicate) {
      _errorQueue.add(error);
      notifyListeners();
    }
  }

  /// Add error manually (for Flutter-side errors)
  void addError(AppError error) {
    _enqueueError(error);
  }

  /// Show next error from queue
  AppError? showNextError() {
    if (_errorQueue.isEmpty) {
      _currentError = null;
      _isDialogShowing = false;
      notifyListeners();
      return null;
    }

    _currentError = _errorQueue.removeAt(0);
    _isDialogShowing = true;
    notifyListeners();
    return _currentError;
  }

  /// Dismiss current error
  void dismissCurrentError() {
    _currentError = null;
    _isDialogShowing = false;
    notifyListeners();
  }

  /// Handle error action
  void handleAction(ErrorAction action) {
    switch (action.actionType) {
      case ErrorActionType.retry:
        // Caller should implement retry logic
        break;
      case ErrorActionType.dismiss:
        dismissCurrentError();
        break;
      case ErrorActionType.openSettings:
        // Navigation handled by caller
        break;
      case ErrorActionType.browse:
        // File picker handled by caller
        break;
      case ErrorActionType.custom:
        // Custom handling by caller
        break;
    }
  }

  /// Clear all errors
  void clearAllErrors() {
    _errorQueue.clear();
    _currentError = null;
    _isDialogShowing = false;
    clearError(); // Clear Rust side too
    notifyListeners();
  }

  /// Get error count by severity
  int countBySeverity(ErrorSeverity severity) {
    int count = _errorQueue.where((e) => e.severity == severity).length;
    if (_currentError?.severity == severity) count++;
    return count;
  }

  /// Check if there are critical or fatal errors
  bool get hasCriticalErrors {
    return _errorQueue.any((e) =>
      e.severity == ErrorSeverity.critical ||
      e.severity == ErrorSeverity.fatal
    ) ||
    (_currentError?.severity == ErrorSeverity.critical) ||
    (_currentError?.severity == ErrorSeverity.fatal);
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

/// Create a Flutter-side AppError
AppError createAppError({
  required String code,
  required String title,
  required String message,
  String? details,
  ErrorSeverity severity = ErrorSeverity.error,
  ErrorCategory category = ErrorCategory.system,
  List<ErrorAction> actions = const [],
  bool recoverable = true,
}) {
  return AppError(
    code: code,
    title: title,
    message: message,
    details: details,
    severity: severity,
    category: category,
    actions: actions,
    recoverable: recoverable,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Create common error types
class AppErrors {
  static AppError fileNotFound(String path) => createAppError(
    code: 'FILE_NOT_FOUND',
    title: 'File Not Found',
    message: 'Cannot find file: $path',
    category: ErrorCategory.file,
    actions: [
      ErrorAction(id: 'browse', label: 'Locate File', actionType: ErrorActionType.browse),
    ],
  );

  static AppError audioDeviceError(String message) => createAppError(
    code: 'AUDIO_DEVICE_ERROR',
    title: 'Audio Device Error',
    message: message,
    category: ErrorCategory.audio,
    actions: [
      ErrorAction(id: 'retry', label: 'Retry', actionType: ErrorActionType.retry),
      ErrorAction(id: 'settings', label: 'Audio Settings', actionType: ErrorActionType.openSettings),
    ],
  );

  static AppError pluginLoadError(String pluginName, String error) => createAppError(
    code: 'PLUGIN_LOAD_ERROR',
    title: 'Plugin Load Failed',
    message: 'Cannot load plugin "$pluginName": $error',
    category: ErrorCategory.plugin,
    severity: ErrorSeverity.warning,
    details: error,
    actions: [
      ErrorAction(id: 'skip', label: 'Skip Plugin', actionType: ErrorActionType.custom),
      ErrorAction(id: 'rescan', label: 'Rescan Plugins', actionType: ErrorActionType.custom),
    ],
  );

  static AppError projectCorrupted(String name) => createAppError(
    code: 'PROJECT_CORRUPTED',
    title: 'Project File Corrupted',
    message: 'Project "$name" appears to be corrupted.',
    category: ErrorCategory.project,
    severity: ErrorSeverity.critical,
    recoverable: false,
    actions: [
      ErrorAction(id: 'recover', label: 'Recover from Backup', actionType: ErrorActionType.custom),
    ],
  );

  static AppError outOfMemory() => createAppError(
    code: 'OUT_OF_MEMORY',
    title: 'Out of Memory',
    message: 'The application has run out of memory. Try closing some plugins or projects.',
    category: ErrorCategory.system,
    severity: ErrorSeverity.critical,
    recoverable: false,
  );
}
