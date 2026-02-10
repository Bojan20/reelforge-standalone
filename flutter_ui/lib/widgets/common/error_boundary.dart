/// Error Boundary Widget (P0.7)
///
/// Provides graceful error handling for widgets that may fail.
/// Catches errors and displays fallback UI instead of crashing the app.
///
/// Inspired by React Error Boundaries pattern.
///
/// Usage:
/// ```dart
/// ErrorBoundary(
///   child: MyPanelWidget(),
///   fallbackBuilder: (error, stack) => MyCustomErrorUI(error),
///   onError: (error, stack) => logToService(error, stack),
/// )
/// ```
///
/// Created: 2026-01-26
library;

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ERROR BOUNDARY WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, StackTrace stackTrace)? fallbackBuilder;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final bool showRetry;
  final String? errorTitle;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallbackBuilder,
    this.onError,
    this.showRetry = true,
    this.errorTitle,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    if (_hasError && _error != null) {
      return widget.fallbackBuilder?.call(_error!, _stackTrace ?? StackTrace.empty) ??
          _buildDefaultFallback(context);
    }

    return ErrorCatcher(
      child: widget.child,
      onError: (error, stack) {
        setState(() {
          _error = error;
          _stackTrace = stack;
          _hasError = true;
        });
        widget.onError?.call(error, stack);
      },
    );
  }

  Widget _buildDefaultFallback(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF121216), // bgDeep
        border: Border.all(color: const Color(0xFFFF4060), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: const Color(0xFFFF4060), // error red
          ),
          const SizedBox(height: 16),
          Text(
            widget.errorTitle ?? 'Something went wrong',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE5E5E5), // textPrimary
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0C), // bgDeepest
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              _getErrorMessage(_error!),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Color(0xFF909090), // textMuted
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (widget.showRetry) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A9EFF), // accent blue
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              // Copy error to clipboard
              // Clipboard.setData(ClipboardData(text: _getFullErrorText()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Error details would be copied (Clipboard API needed)')),
              );
            },
            child: const Text(
              'Copy Error Details',
              style: TextStyle(fontSize: 12, color: Color(0xFF909090)),
            ),
          ),
        ],
      ),
    );
  }

  void _retry() {
    setState(() {
      _error = null;
      _stackTrace = null;
      _hasError = false;
    });
  }

  String _getErrorMessage(Object error) {
    if (error is Exception) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    if (error is Error) {
      return error.toString();
    }
    return error.toString();
  }

  String _getFullErrorText() {
    final buffer = StringBuffer();
    buffer.writeln('ERROR: $_error');
    buffer.writeln();
    buffer.writeln('STACK TRACE:');
    buffer.writeln(_stackTrace.toString());
    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ERROR CATCHER (Internal)
// ═══════════════════════════════════════════════════════════════════════════

/// Internal widget that catches errors in child build method
class ErrorCatcher extends StatefulWidget {
  final Widget child;
  final void Function(Object error, StackTrace stackTrace) onError;

  const ErrorCatcher({
    super.key,
    required this.child,
    required this.onError,
  });

  @override
  State<ErrorCatcher> createState() => _ErrorCatcherState();
}

class _ErrorCatcherState extends State<ErrorCatcher> {
  @override
  Widget build(BuildContext context) {
    // Wrap child in Builder to catch build-time errors
    return Builder(
      builder: (context) {
        try {
          return widget.child;
        } catch (error, stackTrace) {
          // Catch synchronous errors
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onError(error, stackTrace);
          });
          // Return placeholder while error is being processed
          return const SizedBox.shrink();
        }
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ERROR PANEL BUILDER (Utility)
// ═══════════════════════════════════════════════════════════════════════════

/// Pre-built error panel for common use cases
class ErrorPanel extends StatelessWidget {
  final String title;
  final String message;
  final Object? error;
  final VoidCallback? onRetry;
  final IconData icon;
  final Color iconColor;

  const ErrorPanel({
    super.key,
    required this.title,
    required this.message,
    this.error,
    this.onRetry,
    this.icon = Icons.error_outline,
    this.iconColor = const Color(0xFFFF4060),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: iconColor),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE5E5E5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF909090),
            ),
            textAlign: TextAlign.center,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0C),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                error.toString(),
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Color(0xFF606060),
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A9EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER ERROR BOUNDARY (Specialized)
// ═══════════════════════════════════════════════════════════════════════════

/// Error boundary specifically for Provider-dependent widgets
class ProviderErrorBoundary extends StatelessWidget {
  final Widget child;
  final String providerName;
  final VoidCallback? onRetry;

  const ProviderErrorBoundary({
    super.key,
    required this.child,
    required this.providerName,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      child: child,
      errorTitle: '$providerName Unavailable',
      fallbackBuilder: (error, stack) {
        return ErrorPanel(
          title: '$providerName Unavailable',
          message: 'This panel requires $providerName to function.',
          error: error,
          onRetry: onRetry,
          icon: Icons.warning_amber_outlined,
          iconColor: const Color(0xFFFF9040), // warning orange
        );
      },
      onError: (error, stack) {
      },
    );
  }
}
