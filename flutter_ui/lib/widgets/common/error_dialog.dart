// Error Dialog Widget
//
// Professional error dialog for FluxForge Studio.
// Displays rich error information with:
// - Severity-based styling (info, warning, error, critical, fatal)
// - Category icons
// - Action buttons
// - Expandable technical details

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/error_provider.dart';
import '../../src/rust/engine_api.dart';
import '../../theme/fluxforge_theme.dart';

/// Show error dialog for AppError
Future<String?> showErrorDialog(BuildContext context, AppError error) {
  return showDialog<String>(
    context: context,
    barrierDismissible: error.recoverable,
    builder: (context) => ErrorDialog(error: error),
  );
}

/// Error dialog widget
class ErrorDialog extends StatefulWidget {
  final AppError error;

  const ErrorDialog({super.key, required this.error});

  @override
  State<ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<ErrorDialog> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _getSeverityColors(widget.error.severity);

    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border, width: 1),
      ),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.all(16),
      title: _buildHeader(colors),
      content: _buildContent(colors),
      actions: _buildActions(colors),
    );
  }

  Widget _buildHeader(_SeverityColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          Icon(
            _getCategoryIcon(widget.error.category),
            color: colors.icon,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.error.title,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _getSeverityLabel(widget.error.severity),
                  style: TextStyle(
                    color: colors.text.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.icon.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.error.code,
              style: TextStyle(
                color: colors.icon,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(_SeverityColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.error.message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        if (widget.error.details != null) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _showDetails = !_showDetails),
            child: Row(
              children: [
                Icon(
                  _showDetails
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: FluxForgeTheme.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  _showDetails ? 'Hide Details' : 'Show Details',
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_showDetails)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                widget.error.details!,
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(_SeverityColors colors) {
    final actions = <Widget>[];

    // Add dismiss button if recoverable
    if (widget.error.recoverable) {
      actions.add(
        TextButton(
          onPressed: () => Navigator.of(context).pop('dismiss'),
          child: const Text(
            'Dismiss',
            style: TextStyle(color: FluxForgeTheme.textSecondary),
          ),
        ),
      );
    }

    // Add error-specific actions
    for (final action in widget.error.actions) {
      final isPrimary = action.actionType == ErrorActionType.retry ||
          widget.error.actions.indexOf(action) == 0;

      actions.add(
        isPrimary
            ? ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.icon,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(action.id),
                child: Text(action.label),
              )
            : TextButton(
                onPressed: () => Navigator.of(context).pop(action.id),
                child: Text(
                  action.label,
                  style: TextStyle(color: colors.icon),
                ),
              ),
      );
    }

    // If no actions, add OK button
    if (widget.error.actions.isEmpty && !widget.error.recoverable) {
      actions.add(
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.icon,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop('ok'),
          child: const Text('OK'),
        ),
      );
    }

    return actions;
  }

  IconData _getCategoryIcon(ErrorCategory category) {
    switch (category) {
      case ErrorCategory.audio:
        return Icons.graphic_eq;
      case ErrorCategory.file:
        return Icons.folder_off;
      case ErrorCategory.project:
        return Icons.assignment_late;
      case ErrorCategory.plugin:
        return Icons.extension_off;
      case ErrorCategory.hardware:
        return Icons.memory;
      case ErrorCategory.network:
        return Icons.wifi_off;
      case ErrorCategory.user:
        return Icons.person_off;
      case ErrorCategory.system:
        return Icons.warning_amber;
    }
  }

  String _getSeverityLabel(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return 'Information';
      case ErrorSeverity.warning:
        return 'Warning';
      case ErrorSeverity.error:
        return 'Error';
      case ErrorSeverity.critical:
        return 'Critical Error';
      case ErrorSeverity.fatal:
        return 'Fatal Error';
    }
  }

  _SeverityColors _getSeverityColors(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return _SeverityColors(
          background: FluxForgeTheme.accentBlue.withOpacity(0.1),
          border: FluxForgeTheme.accentBlue.withOpacity(0.3),
          icon: FluxForgeTheme.accentBlue,
          text: Colors.white,
        );
      case ErrorSeverity.warning:
        return _SeverityColors(
          background: FluxForgeTheme.accentOrange.withOpacity(0.1),
          border: FluxForgeTheme.accentOrange.withOpacity(0.3),
          icon: FluxForgeTheme.accentOrange,
          text: Colors.white,
        );
      case ErrorSeverity.error:
        return _SeverityColors(
          background: FluxForgeTheme.accentRed.withOpacity(0.1),
          border: FluxForgeTheme.accentRed.withOpacity(0.3),
          icon: FluxForgeTheme.accentRed,
          text: Colors.white,
        );
      case ErrorSeverity.critical:
        return _SeverityColors(
          background: const Color(0xFF8B0000).withOpacity(0.2),
          border: const Color(0xFF8B0000).withOpacity(0.5),
          icon: const Color(0xFFFF4040),
          text: Colors.white,
        );
      case ErrorSeverity.fatal:
        return _SeverityColors(
          background: const Color(0xFF8B0000).withOpacity(0.3),
          border: const Color(0xFFFF0000).withOpacity(0.6),
          icon: const Color(0xFFFF0000),
          text: Colors.white,
        );
    }
  }
}

class _SeverityColors {
  final Color background;
  final Color border;
  final Color icon;
  final Color text;

  _SeverityColors({
    required this.background,
    required this.border,
    required this.icon,
    required this.text,
  });
}

/// Error snackbar for less severe errors
void showErrorSnackbar(BuildContext context, AppError error) {
  final colors = _getSnackbarColors(error.severity);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: colors.background,
      behavior: SnackBarBehavior.floating,
      duration: error.severity == ErrorSeverity.info
          ? const Duration(seconds: 3)
          : const Duration(seconds: 5),
      content: Row(
        children: [
          Icon(
            error.severity == ErrorSeverity.warning
                ? Icons.warning_amber
                : Icons.error_outline,
            color: colors.icon,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.title,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  error.message,
                  style: TextStyle(
                    color: colors.text.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      action: error.actions.isNotEmpty
          ? SnackBarAction(
              label: error.actions.first.label,
              textColor: colors.icon,
              onPressed: () {
                // Handle action through provider
                context.read<ErrorProvider>().handleAction(error.actions.first);
              },
            )
          : null,
    ),
  );
}

_SeverityColors _getSnackbarColors(ErrorSeverity severity) {
  switch (severity) {
    case ErrorSeverity.info:
      return _SeverityColors(
        background: FluxForgeTheme.bgSurface,
        border: FluxForgeTheme.accentBlue,
        icon: FluxForgeTheme.accentBlue,
        text: Colors.white,
      );
    case ErrorSeverity.warning:
      return _SeverityColors(
        background: FluxForgeTheme.bgSurface,
        border: FluxForgeTheme.accentOrange,
        icon: FluxForgeTheme.accentOrange,
        text: Colors.white,
      );
    default:
      return _SeverityColors(
        background: FluxForgeTheme.bgSurface,
        border: FluxForgeTheme.accentRed,
        icon: FluxForgeTheme.accentRed,
        text: Colors.white,
      );
  }
}

/// Error listener widget that shows dialogs automatically
class ErrorListener extends StatefulWidget {
  final Widget child;

  const ErrorListener({super.key, required this.child});

  @override
  State<ErrorListener> createState() => _ErrorListenerState();
}

class _ErrorListenerState extends State<ErrorListener> {
  @override
  void initState() {
    super.initState();
    // Start polling when widget mounts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ErrorProvider>().startPolling();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ErrorProvider>(
      builder: (context, provider, child) {
        // Check for new errors to display
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkForErrors(provider);
        });
        return child!;
      },
      child: widget.child,
    );
  }

  void _checkForErrors(ErrorProvider provider) async {
    if (!provider.isDialogShowing && provider.errorQueue.isNotEmpty) {
      final error = provider.showNextError();
      if (error != null && mounted) {
        // Show dialog for errors, snackbar for warnings/info
        if (error.severity == ErrorSeverity.error ||
            error.severity == ErrorSeverity.critical ||
            error.severity == ErrorSeverity.fatal) {
          final actionId = await showErrorDialog(context, error);
          if (actionId != null) {
            _handleAction(provider, error, actionId);
          }
          provider.dismissCurrentError();
        } else {
          showErrorSnackbar(context, error);
          provider.dismissCurrentError();
        }
      }
    }
  }

  void _handleAction(ErrorProvider provider, AppError error, String actionId) {
    final action = error.actions.firstWhere(
      (a) => a.id == actionId,
      orElse: () => ErrorAction(
        id: actionId,
        label: actionId,
        actionType: ErrorActionType.custom,
      ),
    );
    provider.handleAction(action);
  }
}
