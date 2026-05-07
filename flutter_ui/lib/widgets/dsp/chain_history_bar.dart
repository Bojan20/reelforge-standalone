/// ChainHistoryBar — Undo / Redo + A/B Snapshot toolbar
///
/// Drop-in compact bar for the FX Chain Panel header.
///
/// ```dart
/// ChainHistoryBar(trackId: selectedTrackId)
/// ```
///
/// Layout (all inline):
///   ← Undo (depth badge) | Redo (depth badge) →  [A] [B]  ⇄
///
/// Keyboard shortcuts handled externally via FocusNode — this widget
/// only provides the visual controls.
library;

import 'package:flutter/material.dart';
import '../../services/chain_history_service.dart';

// ─── Colors ──────────────────────────────────────────────────────────────

const _kAccent = Color(0xFF7B5EA7); // purple-ish, consistent with DAW process tabs
const _kDim = Color(0xFF4A4A5A);
const _kA = Color(0xFF40A0FF); // blue = slot A
const _kB = Color(0xFFFF8040); // orange = slot B
const _kBg = Color(0xFF1A1A22);

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ChainHistoryBar extends StatelessWidget {
  final int trackId;

  const ChainHistoryBar({super.key, required this.trackId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChainHistoryService.instance,
      builder: (context, _) {
        final svc = ChainHistoryService.instance;
        // Refresh status on first render
        WidgetsBinding.instance.addPostFrameCallback((_) {
          svc.refresh(trackId);
        });
        final status = svc.statusFor(trackId);

        return Container(
          height: 28,
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 6),

              // ─── Undo ────────────────────────────────────────────────
              _HistoryButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                depth: status.undoDepth,
                tooltip: status.undoLabel != null
                    ? 'Undo: ${status.undoLabel}'
                    : status.canUndo
                        ? 'Undo (${status.undoDepth})'
                        : 'Nothing to undo',
                enabled: status.canUndo,
                onTap: () => svc.undo(trackId),
              ),

              const SizedBox(width: 2),

              // ─── Redo ────────────────────────────────────────────────
              _HistoryButton(
                icon: Icons.redo_rounded,
                label: 'Redo',
                depth: status.redoDepth,
                tooltip: status.redoLabel != null
                    ? 'Redo: ${status.redoLabel}'
                    : status.canRedo
                        ? 'Redo (${status.redoDepth})'
                        : 'Nothing to redo',
                enabled: status.canRedo,
                onTap: () => svc.redo(trackId),
              ),

              const _Divider(),

              // ─── A/B Buttons ─────────────────────────────────────────
              _AbButton(
                label: 'A',
                color: _kA,
                isSet: status.aSet,
                setLabel: status.aLabel,
                onCapture: () => svc.saveA(trackId),
                onRestore: () => svc.restoreA(trackId),
              ),

              const SizedBox(width: 2),

              _AbButton(
                label: 'B',
                color: _kB,
                isSet: status.bSet,
                setLabel: status.bLabel,
                onCapture: () => svc.saveB(trackId),
                onRestore: () => svc.restoreB(trackId),
              ),

              // ─── Swap ────────────────────────────────────────────────
              if (status.aSet || status.bSet) ...[
                const SizedBox(width: 2),
                _IconBtn(
                  icon: Icons.swap_horiz_rounded,
                  tooltip: 'Swap A↔B',
                  onTap: () => svc.swapAB(trackId),
                ),
              ],

              const SizedBox(width: 6),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final int depth;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _HistoryButton({
    required this.icon,
    required this.label,
    required this.depth,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white.withValues(alpha: 0.85) : _kDim;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              if (enabled && depth > 1) ...[
                const SizedBox(width: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '$depth',
                    style: TextStyle(
                      fontSize: 9,
                      color: _kAccent,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AbButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSet;
  final String? setLabel;
  final VoidCallback onCapture;
  final VoidCallback onRestore;

  const _AbButton({
    required this.label,
    required this.color,
    required this.isSet,
    this.setLabel,
    required this.onCapture,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    // Left-click = restore (if set) or capture; right-click = capture
    // Long-press tooltip explains this
    final effectiveColor = isSet ? color : _kDim;
    final tooltip = isSet
        ? (setLabel != null
            ? 'Restore $label: $setLabel\nRight-click to overwrite'
            : 'Restore chain $label\nRight-click to capture')
        : 'Capture current chain as $label';

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: isSet ? onRestore : onCapture,
        onSecondaryTap: onCapture, // right-click → always capture
        child: Container(
          width: 24,
          height: 20,
          decoration: BoxDecoration(
            color: isSet ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSet ? color.withValues(alpha: 0.6) : _kDim.withValues(alpha: 0.4),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: effectiveColor,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.1),
    );
  }
}
