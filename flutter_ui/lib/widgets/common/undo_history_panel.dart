/// Undo History Visualization Panel
///
/// Interactive panel showing undo/redo stack:
/// - Visual timeline of all actions
/// - Click to jump to specific undo state
/// - Shows current position in history
/// - Displays action descriptions
/// - Search/filter capabilities
///
/// Usage: Add to DAW/SlotLab lower zone or debug panel
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/undo_manager.dart';

/// Undo History Panel widget
class UndoHistoryPanel extends StatefulWidget {
  final double maxHeight;

  const UndoHistoryPanel({
    super.key,
    this.maxHeight = 400,
  });

  @override
  State<UndoHistoryPanel> createState() => _UndoHistoryPanelState();
}

class _UndoHistoryPanelState extends State<UndoHistoryPanel> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UiUndoManager>(
      builder: (context, undoManager, _) {
        final undoHistory = undoManager.undoHistory;
        final redoHistory = undoManager.redoHistory;

        // Filter actions by search query
        final filteredUndoHistory = _searchQuery.isEmpty
            ? undoHistory
            : undoHistory
                .where((action) => action.description.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

        final filteredRedoHistory = _searchQuery.isEmpty
            ? redoHistory
            : redoHistory
                .where((action) => action.description.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

        return Container(
          height: widget.maxHeight,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: FluxForgeTheme.borderSubtle,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // Header with stats and search
              _buildHeader(undoManager, undoHistory.length, redoHistory.length),

              const Divider(height: 1, color: FluxForgeTheme.borderSubtle),

              // Action list
              Expanded(
                child: _buildActionList(
                  undoManager,
                  filteredUndoHistory,
                  filteredRedoHistory,
                ),
              ),

              // Footer with quick actions
              _buildFooter(undoManager),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(UiUndoManager undoManager, int undoCount, int redoCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and stats
          Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: FluxForgeTheme.accentBlue,
              ),
              const SizedBox(width: 8),
              Text(
                'Undo History',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildStatChip('Undo', undoCount, FluxForgeTheme.accentBlue),
              const SizedBox(width: 8),
              _buildStatChip('Redo', redoCount, FluxForgeTheme.accentOrange),
            ],
          ),

          const SizedBox(height: 8),

          // Search bar
          TextField(
            controller: _searchController,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: 'Search actions...',
              hintStyle: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 16,
                color: FluxForgeTheme.textMuted,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        size: 16,
                        color: FluxForgeTheme.textMuted,
                      ),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionList(
    UiUndoManager undoManager,
    List<UndoableAction> undoHistory,
    List<UndoableAction> redoHistory,
  ) {
    if (undoHistory.isEmpty && redoHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_toggle_off,
              size: 48,
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No actions yet',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: [
        // Redo history (newest first, grayed out)
        if (redoHistory.isNotEmpty) ...[
          _buildSectionHeader('Future Actions (Redo)', redoHistory.length),
          const SizedBox(height: 4),
          for (int i = redoHistory.length - 1; i >= 0; i--)
            _buildActionItem(
              action: redoHistory[i],
              index: i,
              isFuture: true,
              onTap: () {
                // Redo to this point
                for (int j = 0; j <= i; j++) {
                  undoManager.redo();
                }
              },
            ),
          const SizedBox(height: 16),
        ],

        // Current position indicator
        _buildCurrentPositionIndicator(),
        const SizedBox(height: 16),

        // Undo history (newest first)
        if (undoHistory.isNotEmpty) ...[
          _buildSectionHeader('Past Actions (Undo)', undoHistory.length),
          const SizedBox(height: 4),
          for (int i = 0; i < undoHistory.length; i++)
            _buildActionItem(
              action: undoHistory[i],
              index: i,
              isFuture: false,
              onTap: () {
                // Undo to this point
                undoManager.undoTo(i);
              },
            ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPositionIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.radio_button_checked,
            size: 14,
            color: FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          Text(
            'CURRENT STATE',
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({
    required UndoableAction action,
    required int index,
    required bool isFuture,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isFuture
                  ? FluxForgeTheme.bgDeep.withValues(alpha: 0.3)
                  : FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isFuture
                    ? FluxForgeTheme.borderSubtle.withValues(alpha: 0.2)
                    : FluxForgeTheme.borderSubtle.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Index
                Container(
                  width: 28,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '#${index + 1}',
                    style: TextStyle(
                      color: isFuture
                          ? FluxForgeTheme.textMuted.withValues(alpha: 0.5)
                          : FluxForgeTheme.textMuted,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Icon
                Icon(
                  _getActionIcon(action),
                  size: 16,
                  color: isFuture
                      ? FluxForgeTheme.textMuted.withValues(alpha: 0.5)
                      : FluxForgeTheme.accentBlue,
                ),

                const SizedBox(width: 8),

                // Description
                Expanded(
                  child: Text(
                    action.description,
                    style: TextStyle(
                      color: isFuture
                          ? FluxForgeTheme.textMuted.withValues(alpha: 0.6)
                          : FluxForgeTheme.textPrimary,
                      fontSize: 12,
                      decoration: isFuture ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),

                // Jump button
                if (!isFuture)
                  Icon(
                    Icons.play_arrow,
                    size: 14,
                    color: FluxForgeTheme.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getActionIcon(UndoableAction action) {
    if (action is ClipMoveAction) return Icons.open_with;
    if (action is TrackAddAction) return Icons.add_box;
    if (action is TrackDeleteAction) return Icons.delete;
    if (action is RegionMoveAction) return Icons.swap_horiz;
    if (action is RegionAddAction) return Icons.add_circle;
    if (action is RegionDeleteAction) return Icons.remove_circle;
    if (action is BatchUndoAction) return Icons.layers;
    return Icons.edit;
  }

  Widget _buildFooter(UiUndoManager undoManager) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Undo button
          _FooterButton(
            label: 'Undo',
            icon: Icons.undo,
            color: FluxForgeTheme.accentBlue,
            enabled: undoManager.canUndo,
            onTap: undoManager.canUndo ? undoManager.undo : null,
          ),

          const SizedBox(width: 8),

          // Redo button
          _FooterButton(
            label: 'Redo',
            icon: Icons.redo,
            color: FluxForgeTheme.accentOrange,
            enabled: undoManager.canRedo,
            onTap: undoManager.canRedo ? undoManager.redo : null,
          ),

          const Spacer(),

          // Clear button
          _FooterButton(
            label: 'Clear All',
            icon: Icons.clear_all,
            color: FluxForgeTheme.errorAccent,
            enabled: undoManager.undoStackSize > 0 || undoManager.redoStackSize > 0,
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear History?'),
                  content: const Text('This will clear all undo/redo history. This cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        undoManager.clear();
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: FluxForgeTheme.errorAccent,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;

  const _FooterButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: enabled ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: enabled ? color.withValues(alpha: 0.3) : FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: enabled ? color : FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? color : FluxForgeTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
