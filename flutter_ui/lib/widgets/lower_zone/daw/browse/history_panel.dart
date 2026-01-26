/// DAW Undo History Panel (P0.1 Extracted)
///
/// Displays undo/redo history with:
/// - Action list (up to 100 items)
/// - Undo/Redo buttons
/// - Clear history button
/// - Click-to-undo-to-point functionality
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1228-1406 (~178 LOC)
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/undo_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY PANEL
// ═══════════════════════════════════════════════════════════════════════════

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UiUndoManager.instance,
      builder: (context, _) {
        final undoManager = UiUndoManager.instance;
        final history = undoManager.undoHistory;
        final canUndo = undoManager.canUndo;
        final canRedo = undoManager.canRedo;

        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildBrowserHeader('UNDO HISTORY', Icons.history),
                  const SizedBox(width: 8),
                  Text(
                    '${undoManager.undoStackSize} actions',
                    style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                  ),
                  const Spacer(),
                  // Undo button
                  GestureDetector(
                    onTap: canUndo ? () => undoManager.undo() : null,
                    child: _buildUndoRedoChip(Icons.undo, 'Undo', canUndo),
                  ),
                  const SizedBox(width: 4),
                  // Redo button
                  GestureDetector(
                    onTap: canRedo ? () => undoManager.redo() : null,
                    child: _buildUndoRedoChip(Icons.redo, 'Redo', canRedo),
                  ),
                  const SizedBox(width: 8),
                  // Clear button
                  GestureDetector(
                    onTap: history.isNotEmpty ? () => undoManager.clear() : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: history.isNotEmpty
                            ? Colors.red.withValues(alpha: 0.1)
                            : LowerZoneColors.bgSurface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: history.isNotEmpty ? Colors.red.withValues(alpha: 0.3) : LowerZoneColors.border,
                        ),
                      ),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 9,
                          color: history.isNotEmpty ? Colors.red : LowerZoneColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgDeepest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  child: history.isEmpty
                      ? const Center(
                          child: Text(
                            'No undo history',
                            style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(4),
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            final action = history[index];
                            return GestureDetector(
                              onTap: () => undoManager.undoTo(index),
                              child: _buildHistoryItem(
                                action.description,
                                index == 0, // Most recent is current
                                index,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  Widget _buildBrowserHeader(String title, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildUndoRedoChip(IconData icon, String label, bool isEnabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isEnabled
            ? LowerZoneColors.dawAccent.withValues(alpha: 0.1)
            : LowerZoneColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isEnabled ? LowerZoneColors.dawAccent.withValues(alpha: 0.3) : LowerZoneColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isEnabled ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: isEnabled ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String action, bool isCurrent, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isCurrent ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : null,
        border: Border(
          left: BorderSide(
            color: isCurrent ? LowerZoneColors.dawAccent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCurrent ? Icons.arrow_right : Icons.circle,
            size: isCurrent ? 16 : 6,
            color: isCurrent ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              action,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent ? LowerZoneColors.dawAccent : LowerZoneColors.textPrimary,
              ),
            ),
          ),
          // Index indicator (for undo-to-this-point)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '#${index + 1}',
              style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
