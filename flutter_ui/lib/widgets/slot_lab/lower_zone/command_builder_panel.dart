/// Command Builder Panel — Auto Event Builder Full Editor
///
/// Full parameter editor panel for Auto Event Builder.
/// Shows current draft or event list when no draft is active.
///
/// Features:
/// - Draft parameters: event ID, trigger, bus, preset
/// - Advanced params: volume, pitch, pan, filters
/// - Voice settings: polyphony, steal policy, cooldown
/// - Undo/redo controls
/// - Commit/cancel actions
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../theme/fluxforge_theme.dart';

class CommandBuilderPanel extends StatefulWidget {
  const CommandBuilderPanel({super.key});

  @override
  State<CommandBuilderPanel> createState() => _CommandBuilderPanelState();
}

class _CommandBuilderPanelState extends State<CommandBuilderPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, child) {
        if (provider.hasDraft) {
          return _DraftEditor(draft: provider.currentDraft!);
        } else {
          return _EmptyState(provider: provider);
        }
      },
    );
  }
}

// =============================================================================
// DRAFT EDITOR
// =============================================================================

class _DraftEditor extends StatelessWidget {
  final EventDraft draft;

  const _DraftEditor({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Asset info
          SizedBox(
            width: 200,
            child: _AssetInfo(draft: draft),
          ),

          const SizedBox(width: 16),
          Container(width: 1, height: double.infinity, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 16),

          // Center: Main parameters
          Expanded(
            flex: 2,
            child: _MainParameters(draft: draft),
          ),

          const SizedBox(width: 16),
          Container(width: 1, height: double.infinity, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 16),

          // Right: Actions
          SizedBox(
            width: 160,
            child: _ActionsPanel(draft: draft),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ASSET INFO
// =============================================================================

class _AssetInfo extends StatelessWidget {
  final EventDraft draft;

  const _AssetInfo({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _getAssetColor(draft.asset.assetType).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                _getAssetIcon(draft.asset.assetType),
                size: 16,
                color: _getAssetColor(draft.asset.assetType),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.asset.displayName,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    draft.asset.assetType.displayName,
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Target info
        _InfoRow(label: 'Target', value: draft.target.displayName),
        const SizedBox(height: 8),
        _InfoRow(label: 'Type', value: draft.target.targetType.displayName),
        const SizedBox(height: 8),
        _InfoRow(label: 'Context', value: draft.stageContext.displayName),

        const SizedBox(height: 16),

        // Tags
        if (draft.asset.tags.isNotEmpty) ...[
          Text(
            'Tags',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: draft.asset.tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 9,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  IconData _getAssetIcon(AssetType type) {
    switch (type) {
      case AssetType.sfx: return Icons.surround_sound;
      case AssetType.music: return Icons.music_note;
      case AssetType.vo: return Icons.mic;
      case AssetType.amb: return Icons.waves;
    }
  }

  Color _getAssetColor(AssetType type) {
    switch (type) {
      case AssetType.sfx: return FluxForgeTheme.accentBlue;
      case AssetType.music: return FluxForgeTheme.accentOrange;
      case AssetType.vo: return FluxForgeTheme.accentGreen;
      case AssetType.amb: return FluxForgeTheme.accentCyan;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

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
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// MAIN PARAMETERS
// =============================================================================

class _MainParameters extends StatelessWidget {
  final EventDraft draft;

  const _MainParameters({required this.draft});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event ID
          _ParameterField(
            label: 'Event ID',
            child: _EventIdField(draft: draft),
          ),

          const SizedBox(height: 12),

          // Row 1: Trigger + Bus
          Row(
            children: [
              Expanded(
                child: _ParameterField(
                  label: 'Trigger',
                  child: _TriggerDropdown(draft: draft),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ParameterField(
                  label: 'Bus',
                  child: _BusField(draft: draft),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Row 2: Preset + Variation
          Row(
            children: [
              Expanded(
                child: _ParameterField(
                  label: 'Preset',
                  child: _PresetDropdown(draft: draft),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ParameterField(
                  label: 'Variation',
                  child: _VariationDropdown(draft: draft),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Advanced section
          _AdvancedSection(draft: draft),
        ],
      ),
    );
  }
}

class _ParameterField extends StatelessWidget {
  final String label;
  final Widget child;

  const _ParameterField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _EventIdField extends StatefulWidget {
  final EventDraft draft;

  const _EventIdField({required this.draft});

  @override
  State<_EventIdField> createState() => _EventIdFieldState();
}

class _EventIdFieldState extends State<_EventIdField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draft.eventId);
  }

  @override
  void didUpdateWidget(_EventIdField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.eventId != widget.draft.eventId) {
      _controller.text = widget.draft.eventId;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: TextField(
        controller: _controller,
        style: TextStyle(
          color: FluxForgeTheme.textPrimary,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: InputBorder.none,
          hintText: 'event.id',
          hintStyle: TextStyle(color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
        ),
        onChanged: (value) {
          widget.draft.eventId = value;
          widget.draft.markModified();
        },
      ),
    );
  }
}

class _TriggerDropdown extends StatelessWidget {
  final EventDraft draft;

  const _TriggerDropdown({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: draft.trigger,
          isExpanded: true,
          dropdownColor: FluxForgeTheme.bgMid,
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
          ),
          icon: Icon(Icons.expand_more, size: 16, color: FluxForgeTheme.textMuted),
          items: draft.availableTriggers.map((t) {
            return DropdownMenuItem(
              value: t,
              child: Text(t),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              context.read<AutoEventBuilderProvider>().updateDraft(trigger: value);
            }
          },
        ),
      ),
    );
  }
}

class _BusField extends StatelessWidget {
  final EventDraft draft;

  const _BusField({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(
            Icons.route,
            size: 12,
            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Text(
            draft.bus,
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetDropdown extends StatelessWidget {
  final EventDraft draft;

  const _PresetDropdown({required this.draft});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AutoEventBuilderProvider>();

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: draft.presetId,
          isExpanded: true,
          dropdownColor: FluxForgeTheme.bgMid,
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
          ),
          icon: Icon(Icons.expand_more, size: 16, color: FluxForgeTheme.textMuted),
          items: provider.presets.map((p) {
            return DropdownMenuItem(
              value: p.presetId,
              child: Text(p.name),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              provider.updateDraft(presetId: value);
            }
          },
        ),
      ),
    );
  }
}

class _VariationDropdown extends StatelessWidget {
  final EventDraft draft;

  const _VariationDropdown({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<VariationPolicy>(
          value: draft.variationPolicy,
          isExpanded: true,
          dropdownColor: FluxForgeTheme.bgMid,
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
          ),
          icon: Icon(Icons.expand_more, size: 16, color: FluxForgeTheme.textMuted),
          items: VariationPolicy.values.map((v) {
            return DropdownMenuItem(
              value: v,
              child: Text(v.displayName),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              context.read<AutoEventBuilderProvider>().updateDraft(variationPolicy: value);
            }
          },
        ),
      ),
    );
  }
}

// =============================================================================
// ADVANCED SECTION
// =============================================================================

class _AdvancedSection extends StatefulWidget {
  final EventDraft draft;

  const _AdvancedSection({required this.draft});

  @override
  State<_AdvancedSection> createState() => _AdvancedSectionState();
}

class _AdvancedSectionState extends State<_AdvancedSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle header
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Advanced Parameters',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded content
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          _AdvancedParams(draft: widget.draft),
        ],
      ],
    );
  }
}

class _AdvancedParams extends StatelessWidget {
  final EventDraft draft;

  const _AdvancedParams({required this.draft});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AutoEventBuilderProvider>();
    final preset = provider.presets.firstWhere(
      (p) => p.presetId == draft.presetId,
      orElse: () => StandardPresets.uiClickSecondary,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Row 1: Volume, Pitch, Pan
          Row(
            children: [
              Expanded(child: _ParamDisplay(label: 'Volume', value: '${preset.volume.toStringAsFixed(1)} dB')),
              Expanded(child: _ParamDisplay(label: 'Pitch', value: '${preset.pitch.toStringAsFixed(2)}x')),
              Expanded(child: _ParamDisplay(label: 'Pan', value: preset.pan.toStringAsFixed(2))),
            ],
          ),

          const SizedBox(height: 8),

          // Row 2: Timing
          Row(
            children: [
              Expanded(child: _ParamDisplay(label: 'Delay', value: '${preset.delayMs}ms')),
              Expanded(child: _ParamDisplay(label: 'Fade In', value: '${preset.fadeInMs}ms')),
              Expanded(child: _ParamDisplay(label: 'Fade Out', value: '${preset.fadeOutMs}ms')),
            ],
          ),

          const SizedBox(height: 8),

          // Row 3: Voice
          Row(
            children: [
              Expanded(child: _ParamDisplay(label: 'Polyphony', value: '${preset.polyphony}')),
              Expanded(child: _ParamDisplay(label: 'Cooldown', value: '${preset.cooldownMs}ms')),
              Expanded(child: _ParamDisplay(label: 'Priority', value: '${preset.priority}')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParamDisplay extends StatelessWidget {
  final String label;
  final String value;

  const _ParamDisplay({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 9,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// ACTIONS PANEL
// =============================================================================

class _ActionsPanel extends StatelessWidget {
  final EventDraft draft;

  const _ActionsPanel({required this.draft});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AutoEventBuilderProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Commit button
        _ActionButton(
          label: 'Commit Event',
          icon: Icons.check_circle,
          color: FluxForgeTheme.accentGreen,
          onPressed: () {
            final event = provider.commitDraft();
            if (event != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Created event: ${event.eventId}'),
                  backgroundColor: FluxForgeTheme.bgMid,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),

        const SizedBox(height: 8),

        // Cancel button
        _ActionButton(
          label: 'Cancel',
          icon: Icons.close,
          color: FluxForgeTheme.textMuted,
          onPressed: provider.cancelDraft,
        ),

        const Spacer(),

        // Undo/Redo
        Row(
          children: [
            Expanded(
              child: _SmallActionButton(
                icon: Icons.undo,
                enabled: provider.canUndo,
                onPressed: provider.undo,
                tooltip: 'Undo (Cmd+Z)',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallActionButton(
                icon: Icons.redo,
                enabled: provider.canRedo,
                onPressed: provider.redo,
                tooltip: 'Redo (Cmd+Shift+Z)',
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Stats
        Consumer<AutoEventBuilderProvider>(
          builder: (context, p, _) {
            return Text(
              '${p.events.length} events\n${p.bindings.length} bindings',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            );
          },
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final String tooltip;

  const _SmallActionButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    required this.tooltip,
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
            height: 28,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: Icon(
              icon,
              size: 14,
              color: enabled ? FluxForgeTheme.textSecondary : FluxForgeTheme.textMuted.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// EMPTY STATE
// =============================================================================

class _EmptyState extends StatelessWidget {
  final AutoEventBuilderProvider provider;

  const _EmptyState({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // Left: Instructions
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon + Title
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.build_outlined,
                        size: 22,
                        color: FluxForgeTheme.accentOrange.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto Event Builder',
                          style: TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Drop audio to create events',
                          style: TextStyle(
                            color: FluxForgeTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Instructions
                _InstructionItem(number: '1', text: 'Drag audio from Browser'),
                const SizedBox(height: 6),
                _InstructionItem(number: '2', text: 'Drop onto Slot UI element'),
                const SizedBox(height: 6),
                _InstructionItem(number: '3', text: 'Configure and commit'),
              ],
            ),
          ),

          // Right: Stats
          Expanded(
            flex: 3,
            child: _EventsList(provider: provider),
          ),
        ],
      ),
    );
  }
}

class _InstructionItem extends StatelessWidget {
  final String number;
  final String text;

  const _InstructionItem({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: FluxForgeTheme.accentBlue,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _EventsList extends StatelessWidget {
  final AutoEventBuilderProvider provider;

  const _EventsList({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 32,
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'No events yet',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  'Recent Events',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${provider.events.length} total',
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: provider.events.length.clamp(0, 5),
              itemBuilder: (context, index) {
                final event = provider.events[provider.events.length - 1 - index];
                return _EventItem(event: event, provider: provider);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EventItem extends StatelessWidget {
  final CommittedEvent event;
  final AutoEventBuilderProvider provider;

  const _EventItem({required this.event, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.eventId,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  event.bus,
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 14, color: FluxForgeTheme.textMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => provider.deleteEvent(event.eventId),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}
