// Lower Zone Action Strip — Context-aware action buttons
//
// Bottom bar with actions that change based on current tab context.

import 'package:flutter/material.dart';

import 'lower_zone_types.dart';

/// Action definition for Action Strip
class LowerZoneAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isDestructive;

  const LowerZoneAction({
    required this.label,
    required this.icon,
    this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
  });
}

/// Generic action strip for Lower Zone
class LowerZoneActionStrip extends StatelessWidget {
  /// List of actions to display
  final List<LowerZoneAction> actions;

  /// Section accent color
  final Color accentColor;

  /// Status text to display on the right
  final String? statusText;

  /// Optional left-side content (e.g., slot context dropdowns)
  final Widget? leftContent;

  /// Minimum height for action strip (default: 36px)
  final double minHeight;

  const LowerZoneActionStrip({
    super.key,
    required this.actions,
    required this.accentColor,
    this.statusText,
    this.leftContent,
    this.minHeight = kActionStripHeight,
  });

  @override
  Widget build(BuildContext context) {
    // P2-10: Flexible height — wraps actions if needed
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: LowerZoneColors.bgMid,
        border: Border(
          top: BorderSide(color: LowerZoneColors.borderSubtle),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Left content (optional)
          if (leftContent != null) ...[
            leftContent!,
            Container(width: 1, height: 20, color: LowerZoneColors.border),
          ],
          // Actions
          ...actions.map(_buildActionButton),
          // Spacer replaced with flexible gap
          if (statusText != null) ...[
            const SizedBox(width: 16), // Gap before status
            // Status text
            Text(
              statusText!,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeBadge,
                color: LowerZoneColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(LowerZoneAction action) {
    final isEnabled = action.onTap != null;
    final Color buttonColor;
    if (action.isDestructive) {
      buttonColor = LowerZoneColors.error;
    } else if (action.isPrimary) {
      buttonColor = accentColor;
    } else {
      buttonColor = LowerZoneColors.textSecondary;
    }

    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: action.isPrimary
              ? accentColor.withValues(alpha: 0.15)
              : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: action.isPrimary
                ? accentColor.withValues(alpha: 0.4)
                : LowerZoneColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              action.icon,
              size: 12,
              color: isEnabled ? buttonColor : LowerZoneColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              action.label,
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                fontWeight: action.isPrimary ? FontWeight.w600 : FontWeight.normal,
                color: isEnabled ? buttonColor : LowerZoneColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRE-DEFINED ACTION SETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Common actions for DAW section
class DawActions {
  static List<LowerZoneAction> forBrowse({
    VoidCallback? onImport,
    VoidCallback? onDelete,
    VoidCallback? onPreview,
    VoidCallback? onAddToProject,
  }) => [
    LowerZoneAction(label: 'Import', icon: Icons.add, onTap: onImport, isPrimary: true),
    LowerZoneAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true),
    LowerZoneAction(label: 'Preview', icon: Icons.play_arrow, onTap: onPreview),
    LowerZoneAction(label: 'Add', icon: Icons.playlist_add, onTap: onAddToProject),
  ];

  static List<LowerZoneAction> forEdit({
    VoidCallback? onAddTrack,
    VoidCallback? onSplit,
    VoidCallback? onDuplicate,
    VoidCallback? onDelete,
  }) => [
    LowerZoneAction(label: 'Add Track', icon: Icons.add, onTap: onAddTrack, isPrimary: true),
    LowerZoneAction(label: 'Split', icon: Icons.content_cut, onTap: onSplit),
    LowerZoneAction(label: 'Duplicate', icon: Icons.copy, onTap: onDuplicate),
    LowerZoneAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true),
  ];

  static List<LowerZoneAction> forMix({
    VoidCallback? onAddBus,
    VoidCallback? onMuteAll,
    VoidCallback? onSolo,
    VoidCallback? onReset,
  }) => [
    LowerZoneAction(label: 'Add Bus', icon: Icons.add, onTap: onAddBus, isPrimary: true),
    LowerZoneAction(label: 'Mute All', icon: Icons.volume_off, onTap: onMuteAll),
    LowerZoneAction(label: 'Solo', icon: Icons.headphones, onTap: onSolo),
    LowerZoneAction(label: 'Reset', icon: Icons.refresh, onTap: onReset),
  ];

  static List<LowerZoneAction> forProcess({
    VoidCallback? onAddBand,
    VoidCallback? onRemove,
    VoidCallback? onCopy,
    VoidCallback? onBypass,
  }) => [
    LowerZoneAction(label: 'Add Band', icon: Icons.add, onTap: onAddBand, isPrimary: true),
    LowerZoneAction(label: 'Remove', icon: Icons.remove, onTap: onRemove),
    LowerZoneAction(label: 'Copy', icon: Icons.copy, onTap: onCopy),
    LowerZoneAction(label: 'Bypass', icon: Icons.do_not_disturb, onTap: onBypass),
  ];

  static List<LowerZoneAction> forDeliver({
    VoidCallback? onQuickExport,
    VoidCallback? onBrowse,
    VoidCallback? onExport,
  }) => [
    LowerZoneAction(label: 'Quick Export', icon: Icons.flash_on, onTap: onQuickExport, isPrimary: true),
    LowerZoneAction(label: 'Browse', icon: Icons.folder_open, onTap: onBrowse),
    LowerZoneAction(label: 'Export', icon: Icons.upload, onTap: onExport),
  ];
}

/// Common actions for Middleware section
class MiddlewareActions {
  static List<LowerZoneAction> forEvents({
    VoidCallback? onNewEvent,
    VoidCallback? onDelete,
    VoidCallback? onDuplicate,
    VoidCallback? onTest,
  }) => [
    LowerZoneAction(label: 'New Event', icon: Icons.add, onTap: onNewEvent, isPrimary: true),
    LowerZoneAction(label: 'Delete', icon: Icons.delete_outline, onTap: onDelete, isDestructive: true),
    LowerZoneAction(label: 'Duplicate', icon: Icons.copy, onTap: onDuplicate),
    LowerZoneAction(label: 'Test', icon: Icons.play_arrow, onTap: onTest),
  ];

  static List<LowerZoneAction> forContainers({
    VoidCallback? onAddSound,
    VoidCallback? onBalance,
    VoidCallback? onShuffle,
    VoidCallback? onTest,
  }) => [
    LowerZoneAction(label: 'Add Sound', icon: Icons.add, onTap: onAddSound, isPrimary: true),
    LowerZoneAction(label: 'Balance', icon: Icons.balance, onTap: onBalance),
    LowerZoneAction(label: 'Shuffle', icon: Icons.shuffle, onTap: onShuffle),
    LowerZoneAction(label: 'Test', icon: Icons.play_arrow, onTap: onTest),
  ];

  static List<LowerZoneAction> forRouting({
    VoidCallback? onAddRule,
    VoidCallback? onRemove,
    VoidCallback? onCopy,
    VoidCallback? onTest,
  }) => [
    LowerZoneAction(label: 'Add Rule', icon: Icons.add, onTap: onAddRule, isPrimary: true),
    LowerZoneAction(label: 'Remove', icon: Icons.remove, onTap: onRemove),
    LowerZoneAction(label: 'Copy', icon: Icons.copy, onTap: onCopy),
    LowerZoneAction(label: 'Test', icon: Icons.play_arrow, onTap: onTest),
  ];

  static List<LowerZoneAction> forRtpc({
    VoidCallback? onAddPoint,
    VoidCallback? onRemove,
    VoidCallback? onReset,
    VoidCallback? onPreview,
  }) => [
    LowerZoneAction(label: 'Add Point', icon: Icons.add, onTap: onAddPoint, isPrimary: true),
    LowerZoneAction(label: 'Remove', icon: Icons.remove, onTap: onRemove),
    LowerZoneAction(label: 'Reset', icon: Icons.refresh, onTap: onReset),
    LowerZoneAction(label: 'Preview', icon: Icons.play_arrow, onTap: onPreview),
  ];

  static List<LowerZoneAction> forDeliver({
    VoidCallback? onValidate,
    VoidCallback? onBake,
    VoidCallback? onPackage,
  }) => [
    LowerZoneAction(label: 'Validate', icon: Icons.check_circle_outline, onTap: onValidate),
    LowerZoneAction(label: 'Bake', icon: Icons.local_fire_department, onTap: onBake, isPrimary: true),
    LowerZoneAction(label: 'Package', icon: Icons.inventory_2, onTap: onPackage),
  ];
}

/// Common actions for SlotLab section
class SlotLabActions {
  static List<LowerZoneAction> forStages({
    VoidCallback? onRecord,
    VoidCallback? onStop,
    VoidCallback? onClear,
    VoidCallback? onExport,
  }) => [
    LowerZoneAction(label: 'Record', icon: Icons.fiber_manual_record, onTap: onRecord, isPrimary: true),
    LowerZoneAction(label: 'Stop', icon: Icons.stop, onTap: onStop),
    LowerZoneAction(label: 'Clear', icon: Icons.clear_all, onTap: onClear),
    LowerZoneAction(label: 'Export', icon: Icons.upload, onTap: onExport),
  ];

  static List<LowerZoneAction> forEvents({
    VoidCallback? onAddLayer,
    VoidCallback? onRemove,
    VoidCallback? onDuplicate,
    VoidCallback? onPreview,
  }) => [
    LowerZoneAction(label: 'Add Layer', icon: Icons.add, onTap: onAddLayer, isPrimary: true),
    LowerZoneAction(label: 'Remove', icon: Icons.remove, onTap: onRemove),
    LowerZoneAction(label: 'Duplicate', icon: Icons.copy, onTap: onDuplicate),
    LowerZoneAction(label: 'Preview', icon: Icons.play_arrow, onTap: onPreview),
  ];

  static List<LowerZoneAction> forMix({
    VoidCallback? onMute,
    VoidCallback? onSolo,
    VoidCallback? onReset,
    VoidCallback? onMeters,
  }) => [
    LowerZoneAction(label: 'Mute', icon: Icons.volume_off, onTap: onMute),
    LowerZoneAction(label: 'Solo', icon: Icons.headphones, onTap: onSolo),
    LowerZoneAction(label: 'Reset', icon: Icons.refresh, onTap: onReset),
    LowerZoneAction(label: 'Meters', icon: Icons.bar_chart, onTap: onMeters, isPrimary: true),
  ];

  static List<LowerZoneAction> forDsp({
    VoidCallback? onInsert,
    VoidCallback? onRemove,
    VoidCallback? onReorder,
    VoidCallback? onCopyChain,
  }) => [
    LowerZoneAction(label: 'Insert', icon: Icons.add, onTap: onInsert, isPrimary: true),
    LowerZoneAction(label: 'Remove', icon: Icons.remove, onTap: onRemove),
    LowerZoneAction(label: 'Reorder', icon: Icons.swap_vert, onTap: onReorder),
    LowerZoneAction(label: 'Copy Chain', icon: Icons.copy, onTap: onCopyChain),
  ];

  static List<LowerZoneAction> forBake({
    VoidCallback? onValidate,
    VoidCallback? onBakeAll,
    VoidCallback? onPackage,
  }) => [
    LowerZoneAction(label: 'Validate', icon: Icons.check_circle_outline, onTap: onValidate),
    LowerZoneAction(label: 'Bake All', icon: Icons.local_fire_department, onTap: onBakeAll, isPrimary: true),
    LowerZoneAction(label: 'Package', icon: Icons.inventory_2, onTap: onPackage),
  ];
}
