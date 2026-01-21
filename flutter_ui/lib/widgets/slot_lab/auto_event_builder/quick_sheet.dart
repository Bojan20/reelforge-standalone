/// Quick Sheet — Inline Drop Popup
///
/// Compact popup that appears at drop position for fast event configuration:
/// - Shows event ID preview
/// - Trigger dropdown
/// - Bus (readonly)
/// - Preset dropdown
/// - Commit / More / Cancel actions
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section 15.7
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../controllers/slot_lab/lower_zone_controller.dart';
import '../../../theme/fluxforge_theme.dart';

/// Show quick sheet popup at drop position
void showQuickSheet({
  required BuildContext context,
  required AudioAsset asset,
  required DropTarget target,
  required Offset position,
  VoidCallback? onCommit,
  VoidCallback? onExpand,
  VoidCallback? onCancel,
}) {
  // Create draft in provider
  final provider = context.read<AutoEventBuilderProvider>();
  final draft = provider.createDraft(asset, target);

  // Show popup menu
  showMenu<void>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 300,
      position.dy + 220,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
      ),
    ),
    color: FluxForgeTheme.bgMid,
    elevation: 16,
    items: [
      PopupMenuItem<void>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _QuickSheetContent(
          draft: draft,
          onCommit: () {
            provider.commitDraft();
            Navigator.of(context).pop();
            onCommit?.call();
          },
          onExpand: () {
            Navigator.of(context).pop();
            // Switch to Command Builder tab
            try {
              context.read<LowerZoneController>().switchTo(LowerZoneTab.commandBuilder);
            } catch (_) {
              // LowerZoneController not available
            }
            onExpand?.call();
          },
          onCancel: () {
            provider.cancelDraft();
            Navigator.of(context).pop();
            onCancel?.call();
          },
        ),
      ),
    ],
  );
}

// =============================================================================
// QUICK SHEET CONTENT
// =============================================================================

class _QuickSheetContent extends StatefulWidget {
  final EventDraft draft;
  final VoidCallback onCommit;
  final VoidCallback onExpand;
  final VoidCallback onCancel;

  const _QuickSheetContent({
    required this.draft,
    required this.onCommit,
    required this.onExpand,
    required this.onCancel,
  });

  @override
  State<_QuickSheetContent> createState() => _QuickSheetContentState();
}

class _QuickSheetContentState extends State<_QuickSheetContent> {
  late String _selectedTrigger;
  late String _selectedPreset;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedTrigger = widget.draft.trigger;
    _selectedPreset = widget.draft.presetId;
    // Auto-focus for keyboard shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Enter = Commit
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onCommit();
      return KeyEventResult.handled;
    }

    // Escape = Cancel
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }

    // Tab = Expand to Command Builder
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      widget.onExpand();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),

            const Divider(height: 16, color: FluxForgeTheme.borderSubtle),

            // Event ID preview
            _buildEventIdPreview(),

            const SizedBox(height: 12),

            // Trigger dropdown
            _buildTriggerDropdown(),

            const SizedBox(height: 8),

            // Bus (readonly)
            _buildBusField(),

            const SizedBox(height: 8),

            // Preset dropdown
            _buildPresetDropdown(),

            const SizedBox(height: 16),

            // Actions
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Asset type icon
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _getAssetTypeColor(widget.draft.asset.assetType).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            _getAssetTypeIcon(widget.draft.asset.assetType),
            size: 16,
            color: _getAssetTypeColor(widget.draft.asset.assetType),
          ),
        ),
        const SizedBox(width: 10),
        // Asset name
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.draft.asset.displayName,
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '→ ${widget.draft.target.displayName}',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventIdPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tag,
            size: 12,
            color: FluxForgeTheme.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.draft.eventId,
              style: TextStyle(
                color: FluxForgeTheme.accentCyan,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggerDropdown() {
    return _FieldRow(
      label: 'Trigger',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedTrigger,
          isDense: true,
          isExpanded: true,
          dropdownColor: FluxForgeTheme.bgMid,
          style: const TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
          ),
          items: widget.draft.availableTriggers.map((trigger) {
            return DropdownMenuItem(
              value: trigger,
              child: Text(trigger),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedTrigger = value);
              context.read<AutoEventBuilderProvider>().updateDraft(trigger: value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildBusField() {
    return _FieldRow(
      label: 'Bus',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              Icons.route,
              size: 12,
              color: FluxForgeTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              widget.draft.bus,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetDropdown() {
    final presets = context.read<AutoEventBuilderProvider>().presets;

    return _FieldRow(
      label: 'Preset',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPreset,
          isDense: true,
          isExpanded: true,
          dropdownColor: FluxForgeTheme.bgMid,
          style: const TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
          ),
          items: presets.map((preset) {
            return DropdownMenuItem(
              value: preset.presetId,
              child: Text(preset.name),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedPreset = value);
              context.read<AutoEventBuilderProvider>().updateDraft(presetId: value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        // More... button
        TextButton(
          onPressed: widget.onExpand,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'More...',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '[Tab]',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // Cancel button
        TextButton(
          onPressed: widget.onCancel,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
          ),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Commit button
        ElevatedButton(
          onPressed: widget.onCommit,
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Commit',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              SizedBox(width: 4),
              Text(
                '[↵]',
                style: TextStyle(fontSize: 9, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper methods
  Color _getAssetTypeColor(AssetType type) {
    switch (type) {
      case AssetType.sfx: return FluxForgeTheme.accentBlue;
      case AssetType.music: return FluxForgeTheme.accentOrange;
      case AssetType.vo: return FluxForgeTheme.accentGreen;
      case AssetType.amb: return FluxForgeTheme.accentCyan;
    }
  }

  IconData _getAssetTypeIcon(AssetType type) {
    switch (type) {
      case AssetType.sfx: return Icons.volume_up;
      case AssetType.music: return Icons.music_note;
      case AssetType.vo: return Icons.mic;
      case AssetType.amb: return Icons.waves;
    }
  }
}

// =============================================================================
// FIELD ROW WIDGET
// =============================================================================

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldRow({
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
