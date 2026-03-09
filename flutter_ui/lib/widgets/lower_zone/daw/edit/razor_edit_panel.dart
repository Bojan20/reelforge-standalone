/// Razor Edit Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #34: Cubase-style razor editing — Alt+drag range selection with actions.
///
/// Features:
/// - Toggle razor mode on/off
/// - Show razor selection state (idle/selecting/selected)
/// - Action buttons for all 14 RazorActions
/// - Show selected regions count, duration, track count
/// - Snap-to-grid toggle
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/razor_edit_provider.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class RazorEditPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const RazorEditPanel({super.key, this.onAction});

  @override
  State<RazorEditPanel> createState() => _RazorEditPanelState();
}

class _RazorEditPanelState extends State<RazorEditPanel> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RazorEditProvider>();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 220, child: _buildStatusPanel(provider)),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 2, child: _buildActionsGrid(provider)),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 200, child: _buildSettingsPanel(provider)),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Status Panel
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildStatusPanel(RazorEditProvider provider) {
    final stateLabel = switch (provider.state) {
      RazorState.idle => 'IDLE',
      RazorState.selecting => 'SELECTING...',
      RazorState.selected => 'SELECTED',
    };
    final stateColor = switch (provider.state) {
      RazorState.idle => FabFilterColors.textTertiary,
      RazorState.selecting => FabFilterColors.orange,
      RazorState.selected => FabFilterColors.green,
    };

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('RAZOR EDIT'),
          const SizedBox(height: 8),

          // Enable toggle
          _buildToggleRow(
            'Razor Mode',
            provider.enabled,
            Icons.carpenter,
            FabFilterColors.orange,
            () {
              provider.setEnabled(!provider.enabled);
              widget.onAction?.call('razorToggle', {
                'enabled': !provider.enabled,
              });
            },
          ),
          const SizedBox(height: 12),

          // State indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: stateColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stateColor,
                    boxShadow: provider.state != RazorState.idle
                        ? [BoxShadow(color: stateColor.withValues(alpha: 0.5), blurRadius: 4)]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(stateLabel, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: stateColor,
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Selection info
          if (provider.hasSelection) ...[
            _infoRow('Regions', '${provider.selection.regions.length}'),
            _infoRow('Tracks', '${provider.selection.trackCount}'),
            _infoRow('Start', '${provider.selection.startTime.toStringAsFixed(3)}s'),
            _infoRow('End', '${provider.selection.endTime.toStringAsFixed(3)}s'),
            _infoRow('Duration', '${provider.selection.duration.toStringAsFixed(3)}s'),
            const SizedBox(height: 8),
            if (provider.selection.isSingleTrack)
              _chipLabel('Single Track', FabFilterColors.cyan)
            else
              _chipLabel('Multi-Track', FabFilterColors.purple),
          ] else ...[
            Text(
              provider.enabled
                  ? 'Alt+Drag on timeline\nto create selection'
                  : 'Enable razor mode\nto start editing',
              style: TextStyle(
                color: FabFilterColors.textTertiary, fontSize: 11, height: 1.4,
              ),
            ),
          ],

          const Spacer(),
          if (provider.hasSelection)
            _actionButton(Icons.clear, 'Clear Selection', FabFilterColors.red,
                () => provider.clearSelection()),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Actions Grid
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildActionsGrid(RazorEditProvider provider) {
    final hasSelection = provider.hasSelection;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('ACTIONS'),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 2.8,
              children: [
                _gridAction(Icons.delete_outline, 'Delete', RazorAction.delete,
                    hasSelection, provider),
                _gridAction(Icons.call_split, 'Split', RazorAction.split,
                    hasSelection, provider),
                _gridAction(Icons.content_cut, 'Cut', RazorAction.cut,
                    hasSelection, provider),
                _gridAction(Icons.copy, 'Copy', RazorAction.copy,
                    hasSelection, provider),
                _gridAction(Icons.paste, 'Paste', RazorAction.paste,
                    true, provider),
                _gridAction(Icons.volume_off, 'Mute', RazorAction.mute,
                    hasSelection, provider),
                _gridAction(Icons.auto_fix_high, 'Process', RazorAction.process,
                    hasSelection, provider),
                _gridAction(Icons.layers, 'Bounce', RazorAction.bounce,
                    hasSelection, provider),
                _gridAction(Icons.add_box_outlined, 'Create Clip', RazorAction.createClip,
                    hasSelection, provider),
                _gridAction(Icons.merge, 'Join', RazorAction.join,
                    hasSelection, provider),
                _gridAction(Icons.gradient, 'Fade Both', RazorAction.fadeBoth,
                    hasSelection, provider),
                _gridAction(Icons.healing, 'Heal Sep.', RazorAction.healSeparation,
                    hasSelection, provider),
                _gridAction(Icons.space_bar, 'Ins. Silence', RazorAction.insertSilence,
                    hasSelection, provider),
                _gridAction(Icons.content_cut_outlined, 'Strip Silence', RazorAction.stripSilence,
                    hasSelection, provider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridAction(IconData icon, String label, RazorAction action,
      bool enabled, RazorEditProvider provider) {
    final color = enabled ? FabFilterColors.textSecondary : FabFilterColors.textDisabled;

    return InkWell(
      onTap: enabled
          ? () {
              provider.executeAction(action);
              widget.onAction?.call('razorAction', {
                'action': action.name,
              });
            }
          : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: enabled ? FabFilterColors.bgMid : FabFilterColors.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FabFilterColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 10, color: color),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Settings Panel
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSettingsPanel(RazorEditProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('SETTINGS'),
          const SizedBox(height: 8),

          _buildToggleRow(
            'Snap to Grid',
            provider.snapToGrid,
            Icons.grid_on,
            FabFilterColors.cyan,
            () => provider.setSnapToGrid(!provider.snapToGrid),
          ),
          const SizedBox(height: 12),

          // Keyboard shortcuts
          FabSectionLabel('SHORTCUTS'),
          const SizedBox(height: 4),
          _shortcutRow('Alt+Drag', 'Select range'),
          _shortcutRow('Delete', 'Delete selection'),
          _shortcutRow('Escape', 'Clear selection'),
          _shortcutRow('Cmd+X', 'Cut'),
          _shortcutRow('Cmd+C', 'Copy'),
          _shortcutRow('Cmd+V', 'Paste'),

          const Spacer(),
          const Divider(color: FabFilterColors.border, height: 16),
          Text(
            provider.enabled ? 'Razor mode active' : 'Razor mode off',
            style: TextStyle(
              fontSize: 10,
              color: provider.enabled ? FabFilterColors.orange : FabFilterColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildToggleRow(String label, bool active, IconData icon,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.5) : FabFilterColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: active ? color : FabFilterColors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: TextStyle(
                fontSize: 11,
                color: active ? color : FabFilterColors.textSecondary,
              )),
            ),
            Container(
              width: 28, height: 14,
              decoration: BoxDecoration(
                color: active ? color : FabFilterColors.bgDeep,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: active ? color : FabFilterColors.border,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: active ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 10, height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Colors.white : FabFilterColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(
              fontSize: 10, color: FabFilterColors.textTertiary,
            )),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(
              fontSize: 10, color: FabFilterColors.textPrimary,
              fontWeight: FontWeight.w500,
            )),
          ),
        ],
      ),
    );
  }

  Widget _chipLabel(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.w600, color: color,
      )),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color,
      VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 28,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcutRow(String shortcut, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: FabFilterColors.bgMid,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: FabFilterColors.border),
            ),
            child: Text(shortcut, style: const TextStyle(
              fontSize: 9, color: FabFilterColors.textSecondary,
              fontFamily: 'monospace',
            )),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(description, style: const TextStyle(
              fontSize: 9, color: FabFilterColors.textTertiary,
            )),
          ),
        ],
      ),
    );
  }
}
