/// FluxForge Async FFI Service — Non-Blocking FFI Wrapper
///
/// Wraps synchronous FFI calls in async operations to prevent UI blocking:
/// - Runs FFI calls in background isolates
/// - Provides progress callbacks for long operations
/// - Caches results for repeated calls
/// - Implements retry logic for transient failures
///
/// CRITICAL: All heavy FFI calls (JSON parsing, file I/O, engine spin)
/// MUST go through this service to maintain 60fps UI performance.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';
import '../utils/ffi_error_handler.dart';

/// Configuration for async FFI operations
class AsyncFFIConfig {
  /// Timeout for FFI operations (default: 5 seconds)
  final Duration timeout;

  /// Number of retry attempts for transient failures
  final int retryAttempts;

  /// Delay between retries (exponential backoff)
  final Duration retryDelay;

  /// Enable result caching
  final bool enableCaching;

  /// Cache TTL (time-to-live)
  final Duration cacheTtl;

  const AsyncFFIConfig({
    this.timeout = const Duration(seconds: 5),
    this.retryAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 100),
    this.enableCaching = true,
    this.cacheTtl = const Duration(minutes: 5),
  });

  /// Fast config for quick operations (< 100ms)
  static const AsyncFFIConfig fast = AsyncFFIConfig(
    timeout: Duration(milliseconds: 500),
    retryAttempts: 1,
    enableCaching: false,
  );

  /// Standard config for most operations
  static const AsyncFFIConfig standard = AsyncFFIConfig();

  /// Slow config for heavy operations (JSON parsing, file I/O)
  static const AsyncFFIConfig slow = AsyncFFIConfig(
    timeout: Duration(seconds: 30),
    retryAttempts: 5,
    retryDelay: Duration(milliseconds: 500),
  );
}

/// Result of async FFI operation
class AsyncFFIResult<T> {
  final T? value;
  final FFIError? error;
  final Duration elapsed;
  final bool fromCache;

  const AsyncFFIResult({
    this.value,
    this.error,
    required this.elapsed,
    this.fromCache = false,
  });

  bool get isSuccess => error == null && value != null;
  bool get isError => error != null;

  /// Throw exception if error occurred
  void throwIfError() {
    if (error != null) {
      throw FFIException(error!);
    }
  }

  /// Get value or throw exception
  T unwrap() {
    if (error != null) {
      throw FFIException(error!);
    }
    if (value == null) {
      throw StateError('AsyncFFIResult has no value and no error');
    }
    return value!;
  }

  /// Get value or default
  T orElse(T defaultValue) {
    return value ?? defaultValue;
  }
}

/// Cache entry for FFI results
class _CacheEntry<T> {
  final T value;
  final DateTime timestamp;

  _CacheEntry(this.value) : timestamp = DateTime.now();

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(timestamp) > ttl;
  }
}

/// Async FFI service — singleton
class AsyncFFIService {
  static final AsyncFFIService instance = AsyncFFIService._();
  AsyncFFIService._();

  /// Result cache (keyed by operation signature)
  final Map<String, _CacheEntry<dynamic>> _cache = {};

  /// Active operations (for duplicate call prevention)
  final Map<String, Future<dynamic>> _activeOperations = {};

  // =============================================================================
  // CORE ASYNC WRAPPERS
  // =============================================================================

  /// Run FFI operation asynchronously in background isolate
  ///
  /// [operation] - FFI function to call
  /// [config] - Configuration for timeout, retry, caching
  /// [cacheKey] - Optional cache key (if null, caching disabled for this call)
  ///
  /// Returns AsyncFFIResult with value or error
  Future<AsyncFFIResult<T>> run<T>({
    required T Function() operation,
    AsyncFFIConfig config = AsyncFFIConfig.standard,
    String? cacheKey,
    void Function(double progress)? onProgress,
  }) async {
    final startTime = DateTime.now();

    // Check cache first (if caching enabled and key provided)
    if (config.enableCaching && cacheKey != null) {
      final cached = _cache[cacheKey] as _CacheEntry<T>?;
      if (cached != null && !cached.isExpired(config.cacheTtl)) {
        return AsyncFFIResult<T>(
          value: cached.value,
          elapsed: DateTime.now().difference(startTime),
          fromCache: true,
        );
      }
    }

    // Check for duplicate in-flight operation
    if (cacheKey != null && _activeOperations.containsKey(cacheKey)) {
      try {
        final result = await _activeOperations[cacheKey] as T;
        return AsyncFFIResult<T>(
          value: result,
          elapsed: DateTime.now().difference(startTime),
        );
      } catch (e) {
        return AsyncFFIResult<T>(
          error: FFIError(
            category: FFIErrorCategory.unknown,
            code: 0,
            message: 'Duplicate operation failed: $e',
          ),
          elapsed: DateTime.now().difference(startTime),
        );
      }
    }

    // Create future for this operation
    final operationFuture = _runWithRetry<T>(
      operation: operation,
      config: config,
      onProgress: onProgress,
    );

    // Track active operation
    if (cacheKey != null) {
      _activeOperations[cacheKey] = operationFuture;
    }

    try {
      // Run with timeout
      final value = await operationFuture.timeout(
        config.timeout,
        onTimeout: () {
          throw TimeoutException(
            'FFI operation timed out after ${config.timeout.inMilliseconds}ms',
          );
        },
      );

      final elapsed = DateTime.now().difference(startTime);

      // Cache result if successful
      if (config.enableCaching && cacheKey != null) {
        _cache[cacheKey] = _CacheEntry<T>(value);
      }

      return AsyncFFIResult<T>(
        value: value,
        elapsed: elapsed,
      );
    } catch (e) {
      final elapsed = DateTime.now().difference(startTime);

      FFIError error;
      if (e is FFIException) {
        error = e.error;
      } else if (e is TimeoutException) {
        error = FFIError(
          category: FFIErrorCategory.syncError,
          code: 900,
          message: e.message ?? 'Operation timed out',
          suggestion: 'Try reducing operation complexity or increasing timeout',
        );
      } else {
        error = FFIError(
          category: FFIErrorCategory.unknown,
          code: 0,
          message: e.toString(),
        );
      }

      return AsyncFFIResult<T>(
        error: error,
        elapsed: elapsed,
      );
    } finally {
      // Remove from active operations
      if (cacheKey != null) {
        _activeOperations.remove(cacheKey);
      }
    }
  }

  /// Run operation with retry logic
  Future<T> _runWithRetry<T>({
    required T Function() operation,
    required AsyncFFIConfig config,
    void Function(double progress)? onProgress,
  }) async {
    int attempt = 0;
    Exception? lastException;

    while (attempt < config.retryAttempts) {
      try {
        // Report progress
        if (onProgress != null && config.retryAttempts > 1) {
          onProgress(attempt / config.retryAttempts);
        }

        // Run in compute isolate for CPU-intensive operations
        // For simple FFI calls, this might be overkill, but prevents UI jank
        final result = await compute(
          _isolateRunner<T>,
          _IsolateParams<T>(operation),
        );

        // Success
        if (onProgress != null) {
          onProgress(1.0);
        }

        return result;
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        attempt++;

        // If not last attempt, wait before retry (exponential backoff)
        if (attempt < config.retryAttempts) {
          final delay = config.retryDelay * (1 << attempt); // 2^attempt multiplier
          await Future.delayed(delay);
        }
      }
    }

    // All retries failed
    throw lastException ?? Exception('All retry attempts failed');
  }

  // =============================================================================
  // CACHE MANAGEMENT
  // =============================================================================

  /// Clear all cached results
  void clearCache() {
    _cache.clear();
  }

  /// Clear expired cache entries
  void clearExpiredCache(Duration ttl) {
    final now = DateTime.now();
    _cache.removeWhere((key, entry) {
      return now.difference(entry.timestamp) > ttl;
    });
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'entries': _cache.length,
      'active_operations': _activeOperations.length,
    };
  }

  // =============================================================================
  // SLOTLAB-SPECIFIC WRAPPERS (Examples)
  // =============================================================================
  // NOTE: These are example wrappers. Actual usage depends on specific FFI methods.
  // Uncomment and adapt as needed for your use case.

  /// Example: Async wrapper for waveform generation (heavy DSP operation)
  Future<AsyncFFIResult<String?>> generateWaveformAsync(
    String audioPath, {
    AsyncFFIConfig config = AsyncFFIConfig.slow,
    String? cacheKey,
  }) async {
    return run<String?>(
      operation: () {
        final ffi = NativeFFI.instance;
        return ffi.generateWaveformFromFile(audioPath, cacheKey ?? audioPath);
      },
      config: config,
      cacheKey: cacheKey,
    );
  }
}

// =============================================================================
// ISOLATE RUNNER (Internal)
// =============================================================================

/// Parameters for isolate runner
class _IsolateParams<T> {
  final T Function() operation;

  _IsolateParams(this.operation);
}

/// Run operation in isolate (prevents main thread blocking)
T _isolateRunner<T>(_IsolateParams<T> params) {
  return params.operation();
}
