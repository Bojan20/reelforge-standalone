/// Panel Undo Toolbar — Compact undo/redo controls for panels
///
/// P2.2: UI component for panel-local undo system.
///
/// Usage:
/// ```dart
/// PanelUndoToolbar(
///   manager: undoManager,
///   compact: true, // Small buttons only
/// )
/// ```

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../providers/panel_undo_manager.dart';

/// Compact toolbar for panel undo/redo
class PanelUndoToolbar extends StatelessWidget {
  final PanelUndoManager manager;
  final bool compact;
  final bool showHistory;
  final Color? accentColor;

  const PanelUndoToolbar({
    super.key,
    required this.manager,
    this.compact = true,
    this.showHistory = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        if (compact) {
          return _buildCompactToolbar(color);
        }
        return _buildFullToolbar(color);
      },
    );
  }

  Widget _buildCompactToolbar(Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Undo button
        Tooltip(
          message: manager.canUndo ? 'Undo: ${manager.undoDescription}' : 'Nothing to undo',
          child: InkWell(
            onTap: manager.canUndo ? manager.undo : null,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.undo,
                size: 14,
                color: manager.canUndo ? color : color.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        // Redo button
        Tooltip(
          message: manager.canRedo ? 'Redo: ${manager.redoDescription}' : 'Nothing to redo',
          child: InkWell(
            onTap: manager.canRedo ? manager.redo : null,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.redo,
                size: 14,
                color: manager.canRedo ? color : color.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        if (showHistory && (manager.canUndo || manager.canRedo)) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${manager.undoStackSize}',
              style: TextStyle(fontSize: 9, color: color),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFullToolbar(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Undo button with label
          _buildButton(
            icon: Icons.undo,
            label: 'Undo',
            tooltip: manager.undoDescription,
            enabled: manager.canUndo,
            onTap: manager.undo,
            color: color,
          ),
          const SizedBox(width: 8),
          // Redo button with label
          _buildButton(
            icon: Icons.redo,
            label: 'Redo',
            tooltip: manager.redoDescription,
            enabled: manager.canRedo,
            onTap: manager.redo,
            color: color,
          ),
          if (manager.undoStackSize > 0) ...[
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 16,
              color: color.withValues(alpha: 0.2),
            ),
            const SizedBox(width: 8),
            // History count
            Text(
              '${manager.undoStackSize} actions',
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 4),
            // Clear button
            Tooltip(
              message: 'Clear history',
              child: InkWell(
                onTap: manager.clear,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline,
                    size: 14,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    String? tooltip,
    required bool enabled,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: enabled ? color : color.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: enabled ? color : color.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel undo history dropdown
class PanelUndoHistoryDropdown extends StatelessWidget {
  final PanelUndoManager manager;
  final Color? accentColor;
  final double maxHeight;

  const PanelUndoHistoryDropdown({
    super.key,
    required this.manager,
    this.accentColor,
    this.maxHeight = 200,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final history = manager.undoHistory;

        if (history.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No undo history',
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.5),
              ),
            ),
          );
        }

        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(4),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final action = history[index];
              return _buildHistoryItem(context, index, action, color);
            },
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(BuildContext context, int index, PanelUndoAction action, Color color) {
    final isRecent = index == 0;

    return InkWell(
      onTap: () => manager.undoTo(index),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isRecent ? color.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              _getIconForAction(action),
              size: 12,
              color: isRecent ? color : color.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                action.description,
                style: TextStyle(
                  fontSize: 10,
                  color: isRecent ? color : color.withValues(alpha: 0.7),
                  fontWeight: isRecent ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            Text(
              _formatTimestamp(action.timestamp),
              style: TextStyle(
                fontSize: 8,
                color: color.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForAction(PanelUndoAction action) {
    if (action is ParameterChangeAction) return Icons.tune;
    if (action is BatchParameterChangeAction) return Icons.layers;
    if (action is EqBandAction) return Icons.equalizer;
    if (action is PresetChangeAction) return Icons.bookmark;
    if (action is ABSwitchAction) return Icons.compare;
    return Icons.history;
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Focus node wrapper that handles Cmd+Z within panel
class PanelUndoFocusWrapper extends StatefulWidget {
  final PanelUndoManager manager;
  final Widget child;
  final bool captureUndo;

  const PanelUndoFocusWrapper({
    super.key,
    required this.manager,
    required this.child,
    this.captureUndo = true,
  });

  @override
  State<PanelUndoFocusWrapper> createState() => _PanelUndoFocusWrapperState();
}

class _PanelUndoFocusWrapperState extends State<PanelUndoFocusWrapper> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'PanelUndoFocus');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.captureUndo) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Cmd+Z (Mac) or Ctrl+Z (Win/Linux)
    if ((isMeta || isCtrl) && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        // Redo
        if (widget.manager.redo()) {
          return KeyEventResult.handled;
        }
      } else {
        // Undo
        if (widget.manager.undo()) {
          return KeyEventResult.handled;
        }
      }
    }

    // Cmd+Y (Win/Linux redo)
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      if (widget.manager.redo()) {
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
