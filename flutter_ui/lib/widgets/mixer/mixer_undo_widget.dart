/// Mixer Undo Widget (P10.0.4)
///
/// Compact undo/redo controls for the mixer:
/// - Undo/Redo buttons with visual feedback
/// - Keyboard shortcuts (Cmd+Z, Cmd+Shift+Z)
/// - History dropdown showing last 10 actions
/// - Toast notifications for undo actions
///
/// Usage: Add to mixer toolbar or channel strip header
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/undo_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MIXER UNDO TOOLBAR
// ═══════════════════════════════════════════════════════════════════════════

/// Compact undo/redo toolbar for the mixer
class MixerUndoToolbar extends StatefulWidget {
  /// Show history dropdown button
  final bool showHistory;

  /// Show keyboard shortcut hints
  final bool showShortcuts;

  /// Compact mode (icons only)
  final bool compact;

  /// Callback when undo is performed
  final VoidCallback? onUndo;

  /// Callback when redo is performed
  final VoidCallback? onRedo;

  const MixerUndoToolbar({
    super.key,
    this.showHistory = true,
    this.showShortcuts = true,
    this.compact = false,
    this.onUndo,
    this.onRedo,
  });

  @override
  State<MixerUndoToolbar> createState() => _MixerUndoToolbarState();
}

class _MixerUndoToolbarState extends State<MixerUndoToolbar> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleUndo() {
    final undoManager = UiUndoManager.instance;
    if (undoManager.canUndo) {
      final description = undoManager.undoDescription;
      undoManager.undo();
      widget.onUndo?.call();
      _showUndoToast(context, 'Undid: $description');
    }
  }

  void _handleRedo() {
    final undoManager = UiUndoManager.instance;
    if (undoManager.canRedo) {
      final description = undoManager.redoDescription;
      undoManager.redo();
      widget.onRedo?.call();
      _showUndoToast(context, 'Redid: $description');
    }
  }

  void _showUndoToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.history, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final modKey = isMac ? '⌘' : 'Ctrl+';

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final isCmd = isMac
              ? HardwareKeyboard.instance.isMetaPressed
              : HardwareKeyboard.instance.isControlPressed;
          final isShift = HardwareKeyboard.instance.isShiftPressed;

          if (isCmd && event.logicalKey == LogicalKeyboardKey.keyZ) {
            if (isShift) {
              _handleRedo();
            } else {
              _handleUndo();
            }
          }
        }
      },
      child: Consumer<UiUndoManager>(
        builder: (context, undoManager, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Undo button
              _UndoButton(
                icon: Icons.undo,
                label: widget.compact ? null : 'Undo',
                tooltip: widget.showShortcuts ? 'Undo (${modKey}Z)' : 'Undo',
                enabled: undoManager.canUndo,
                onPressed: _handleUndo,
              ),

              const SizedBox(width: 4),

              // Redo button
              _UndoButton(
                icon: Icons.redo,
                label: widget.compact ? null : 'Redo',
                tooltip: widget.showShortcuts
                    ? 'Redo (${modKey}Shift+Z)'
                    : 'Redo',
                enabled: undoManager.canRedo,
                onPressed: _handleRedo,
              ),

              // History dropdown
              if (widget.showHistory) ...[
                const SizedBox(width: 4),
                _HistoryDropdown(
                  undoManager: undoManager,
                  onUndoTo: (index) {
                    undoManager.undoTo(index);
                    _showUndoToast(context, 'Jumped to previous state');
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNDO BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _UndoButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _UndoButton({
    required this.icon,
    this.label,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: label != null ? 8 : 6,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: enabled
                  ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: enabled
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
                    : FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: enabled
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textMuted.withValues(alpha: 0.4),
                ),
                if (label != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    label!,
                    style: TextStyle(
                      color: enabled
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textMuted.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY DROPDOWN
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryDropdown extends StatelessWidget {
  final UiUndoManager undoManager;
  final void Function(int index) onUndoTo;

  const _HistoryDropdown({
    required this.undoManager,
    required this.onUndoTo,
  });

  @override
  Widget build(BuildContext context) {
    final history = undoManager.undoHistory.take(10).toList();
    final isEmpty = history.isEmpty;

    return PopupMenuButton<int>(
      enabled: !isEmpty,
      tooltip: 'Undo History',
      offset: const Offset(0, 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: FluxForgeTheme.bgMid,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isEmpty
              ? Colors.transparent
              : FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isEmpty
                ? FluxForgeTheme.borderSubtle.withValues(alpha: 0.2)
                : FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 14,
              color: isEmpty
                  ? FluxForgeTheme.textMuted.withValues(alpha: 0.4)
                  : FluxForgeTheme.textMuted,
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: isEmpty
                  ? FluxForgeTheme.textMuted.withValues(alpha: 0.4)
                  : FluxForgeTheme.textMuted,
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        if (history.isEmpty) {
          return [
            const PopupMenuItem<int>(
              enabled: false,
              child: Text(
                'No history',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ];
        }

        return [
          // Header
          PopupMenuItem<int>(
            enabled: false,
            height: 28,
            child: Text(
              'UNDO HISTORY (${history.length})',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const PopupMenuDivider(height: 1),
          // History items
          ...history.asMap().entries.map((entry) {
            final index = entry.key;
            final action = entry.value;
            return PopupMenuItem<int>(
              value: index,
              height: 32,
              child: Row(
                children: [
                  Container(
                    width: 20,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _getActionIcon(action.description),
                    size: 14,
                    color: FluxForgeTheme.accentBlue,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      action.description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: FluxForgeTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
        ];
      },
      onSelected: onUndoTo,
    );
  }

  IconData _getActionIcon(String description) {
    final lower = description.toLowerCase();
    if (lower.contains('volume')) return Icons.volume_up;
    if (lower.contains('pan')) return Icons.swap_horiz;
    if (lower.contains('mute')) return Icons.volume_off;
    if (lower.contains('solo')) return Icons.headphones;
    if (lower.contains('send')) return Icons.call_split;
    if (lower.contains('route')) return Icons.alt_route;
    if (lower.contains('insert') || lower.contains('remove')) {
      return Icons.extension;
    }
    if (lower.contains('bypass')) return Icons.power_off;
    if (lower.contains('gain')) return Icons.tune;
    return Icons.edit;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STANDALONE UNDO BUTTONS
// ═══════════════════════════════════════════════════════════════════════════

/// Simple undo button that can be placed anywhere
class MixerUndoButton extends StatelessWidget {
  final bool compact;
  final VoidCallback? onUndo;

  const MixerUndoButton({
    super.key,
    this.compact = false,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<UiUndoManager>(
      builder: (context, undoManager, _) {
        return _UndoButton(
          icon: Icons.undo,
          label: compact ? null : 'Undo',
          tooltip: 'Undo (Cmd+Z)',
          enabled: undoManager.canUndo,
          onPressed: () {
            if (undoManager.canUndo) {
              undoManager.undo();
              onUndo?.call();
            }
          },
        );
      },
    );
  }
}

/// Simple redo button that can be placed anywhere
class MixerRedoButton extends StatelessWidget {
  final bool compact;
  final VoidCallback? onRedo;

  const MixerRedoButton({
    super.key,
    this.compact = false,
    this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<UiUndoManager>(
      builder: (context, undoManager, _) {
        return _UndoButton(
          icon: Icons.redo,
          label: compact ? null : 'Redo',
          tooltip: 'Redo (Cmd+Shift+Z)',
          enabled: undoManager.canRedo,
          onPressed: () {
            if (undoManager.canRedo) {
              undoManager.redo();
              onRedo?.call();
            }
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXER UNDO STATUS INDICATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Shows current undo/redo stack status
class MixerUndoStatus extends StatelessWidget {
  const MixerUndoStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UiUndoManager>(
      builder: (context, undoManager, _) {
        final undoCount = undoManager.undoStackSize;
        final redoCount = undoManager.redoStackSize;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history,
                size: 12,
                color: FluxForgeTheme.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'U:$undoCount R:$redoCount',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
