/// FluxForge Studio Preset Morph Editor Panel
///
/// P4.6: Preset Morphing UI
/// - Create/edit morphs between presets
/// - Visual morph slider with preview
/// - Parameter list with per-parameter curves
/// - Factory templates
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/subsystems/rtpc_system_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PRESET MORPH EDITOR PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class PresetMorphEditorPanel extends StatefulWidget {
  final double height;

  const PresetMorphEditorPanel({
    super.key,
    this.height = 400,
  });

  @override
  State<PresetMorphEditorPanel> createState() => _PresetMorphEditorPanelState();
}

class _PresetMorphEditorPanelState extends State<PresetMorphEditorPanel> {
  int? _selectedMorphId;
  bool _isAddingParameter = false;
  RtpcTargetParameter _newParamTarget = RtpcTargetParameter.volume;

  @override
  Widget build(BuildContext context) {
    return Consumer<RtpcSystemProvider>(
      builder: (context, provider, _) {
        final morphs = provider.presetMorphs;

        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            border: Border(
              top: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
            ),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(context, provider, morphs.length),
              // Content
              Expanded(
                child: Row(
                  children: [
                    // Morph list (left)
                    SizedBox(
                      width: 260,
                      child: _buildMorphList(provider, morphs),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                    ),
                    // Morph editor (right)
                    Expanded(
                      child: _selectedMorphId != null
                          ? _buildMorphEditor(provider, provider.getMorph(_selectedMorphId!))
                          : _buildEmptyState(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, RtpcSystemProvider provider, int count) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, size: 16, color: FluxForgeTheme.accentPurple),
          const SizedBox(width: 8),
          Text(
            'Preset Morphs',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: FluxForgeTheme.accentPurple,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          // Templates
          PopupMenuButton<String>(
            icon: Icon(Icons.auto_awesome, size: 16, color: FluxForgeTheme.textMuted),
            tooltip: 'Templates',
            onSelected: (template) => _createFromTemplate(provider, template),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'volume_crossfade', child: Text('Volume Crossfade')),
              const PopupMenuItem(value: 'filter_sweep', child: Text('Filter Sweep')),
              const PopupMenuItem(value: 'tension_builder', child: Text('Tension Builder')),
              const PopupMenuItem(value: 'intensity_shift', child: Text('Intensity Shift')),
              const PopupMenuItem(value: 'spatial_drift', child: Text('Spatial Drift')),
            ],
          ),
          const SizedBox(width: 4),
          // Add morph
          IconButton(
            icon: Icon(Icons.add_circle_outline, size: 18, color: FluxForgeTheme.accentPurple),
            tooltip: 'Create Morph',
            onPressed: () => _createNewMorph(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildMorphList(RtpcSystemProvider provider, List<PresetMorph> morphs) {
    if (morphs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.compare_arrows, size: 48, color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'No Morphs',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a morph to smoothly\nblend between presets',
                textAlign: TextAlign.center,
                style: TextStyle(color: FluxForgeTheme.textMuted.withValues(alpha: 0.7), fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: morphs.length,
      itemBuilder: (context, index) {
        final morph = morphs[index];
        final isSelected = morph.id == _selectedMorphId;

        return _MorphListTile(
          morph: morph,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedMorphId = morph.id),
          onDelete: () => _deleteMorph(provider, morph.id),
          onPositionChanged: (pos) => provider.setMorphPosition(morph.id, pos),
        );
      },
    );
  }

  Widget _buildMorphEditor(RtpcSystemProvider provider, PresetMorph? morph) {
    if (morph == null) return _buildEmptyState();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Morph info header
          _buildMorphInfoHeader(provider, morph),
          const SizedBox(height: 20),

          // Big morph slider
          _buildMorphSlider(provider, morph),
          const SizedBox(height: 24),

          // Parameters list
          _buildParametersList(provider, morph),
        ],
      ),
    );
  }

  Widget _buildMorphInfoHeader(RtpcSystemProvider provider, PresetMorph morph) {
    return Row(
      children: [
        // Color indicator
        GestureDetector(
          onTap: () => _showColorPicker(provider, morph),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: morph.color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Name (editable)
        Expanded(
          child: InkWell(
            onTap: () => _editMorphName(provider, morph),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  morph.name,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (morph.description.isNotEmpty)
                  Text(
                    morph.description,
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Enable toggle
        Switch(
          value: morph.enabled,
          onChanged: (v) => provider.setMorphEnabled(morph.id, v),
          activeColor: FluxForgeTheme.accentPurple,
        ),
        // Global curve selector
        PopupMenuButton<MorphCurve>(
          initialValue: morph.globalCurve,
          tooltip: 'Global Curve',
          onSelected: (curve) => provider.updateMorph(morph.id, globalCurve: curve),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timeline, size: 14, color: FluxForgeTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  morph.globalCurve.displayName,
                  style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          itemBuilder: (context) => MorphCurve.values.map((curve) {
            return PopupMenuItem(
              value: curve,
              child: Text(curve.displayName),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMorphSlider(RtpcSystemProvider provider, PresetMorph morph) {
    return Column(
      children: [
        // Preset labels
        Row(
          children: [
            // Preset A
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: morph.position < 0.5
                        ? FluxForgeTheme.accentPurple.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'A',
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      morph.presetA.isEmpty ? 'Preset A' : morph.presetA,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Position indicator
            Text(
              '${(morph.position * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: FluxForgeTheme.accentPurple,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 16),
            // Preset B
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: morph.position >= 0.5
                        ? FluxForgeTheme.accentPurple.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'B',
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      morph.presetB.isEmpty ? 'Preset B' : morph.presetB,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Large slider
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Stack(
            children: [
              // Curve visualization background
              CustomPaint(
                size: const Size(double.infinity, 60),
                painter: _CurveBackgroundPainter(
                  curve: morph.globalCurve,
                  color: FluxForgeTheme.accentPurple.withValues(alpha: 0.2),
                ),
              ),
              // Slider
              Positioned.fill(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: FluxForgeTheme.accentPurple,
                    inactiveTrackColor: FluxForgeTheme.surface,
                    thumbColor: FluxForgeTheme.accentPurple,
                    overlayColor: FluxForgeTheme.accentPurple.withValues(alpha: 0.2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                  ),
                  child: Slider(
                    value: morph.position,
                    onChanged: morph.enabled
                        ? (value) => provider.setMorphPosition(morph.id, value)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Quick buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: morph.enabled ? () => provider.setMorphPosition(morph.id, 0.0) : null,
              child: const Text('A'),
            ),
            TextButton(
              onPressed: morph.enabled ? () => provider.setMorphPosition(morph.id, 0.25) : null,
              child: const Text('25%'),
            ),
            TextButton(
              onPressed: morph.enabled ? () => provider.setMorphPosition(morph.id, 0.5) : null,
              child: const Text('50%'),
            ),
            TextButton(
              onPressed: morph.enabled ? () => provider.setMorphPosition(morph.id, 0.75) : null,
              child: const Text('75%'),
            ),
            TextButton(
              onPressed: morph.enabled ? () => provider.setMorphPosition(morph.id, 1.0) : null,
              child: const Text('B'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildParametersList(RtpcSystemProvider provider, PresetMorph morph) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Parameters header
        Row(
          children: [
            Text(
              'Parameters',
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${morph.parameters.length}',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.add, size: 18, color: FluxForgeTheme.accentPurple),
              tooltip: 'Add Parameter',
              onPressed: () => setState(() => _isAddingParameter = true),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Add parameter form
        if (_isAddingParameter) _buildAddParameterForm(provider, morph),

        // Parameters
        if (morph.parameters.isEmpty && !_isAddingParameter)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No parameters. Add parameters to morph between values.',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ...morph.parameters.map((param) => _ParameterTile(
                parameter: param,
                morphPosition: morph.position,
                onRemove: () => provider.removeMorphParameter(morph.id, param.name),
                onToggle: (enabled) {
                  provider.updateMorphParameter(
                    morph.id,
                    param.name,
                    param.copyWith(enabled: enabled),
                  );
                },
                onCurveChanged: (curve) {
                  provider.updateMorphParameter(
                    morph.id,
                    param.name,
                    param.copyWith(curve: curve),
                  );
                },
              )),
      ],
    );
  }

  Widget _buildAddParameterForm(RtpcSystemProvider provider, PresetMorph morph) {
    final range = _newParamTarget.defaultRange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Parameter',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Target parameter
              Expanded(
                child: DropdownButtonFormField<RtpcTargetParameter>(
                  value: _newParamTarget,
                  decoration: InputDecoration(
                    labelText: 'Target',
                    labelStyle: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  dropdownColor: FluxForgeTheme.surface,
                  style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                  items: RtpcTargetParameter.values.map((param) {
                    return DropdownMenuItem(
                      value: param,
                      child: Text(param.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _newParamTarget = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Add button
              ElevatedButton(
                onPressed: () => _addParameter(provider, morph, range),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accentPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: const Text('Add'),
              ),
              const SizedBox(width: 4),
              // Cancel
              TextButton(
                onPressed: () => setState(() => _isAddingParameter = false),
                child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textMuted)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back, size: 32, color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'Select a morph to edit',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════════

  void _createNewMorph(RtpcSystemProvider provider) {
    final morph = provider.createMorph(
      name: 'New Morph',
      presetA: 'Preset A',
      presetB: 'Preset B',
      color: _getRandomColor(),
    );
    setState(() => _selectedMorphId = morph.id);
  }

  void _createFromTemplate(RtpcSystemProvider provider, String template) {
    final morph = provider.createMorphFromTemplate(
      template,
      _getTemplateName(template),
    );
    setState(() => _selectedMorphId = morph.id);
  }

  String _getTemplateName(String template) {
    switch (template) {
      case 'volume_crossfade': return 'Volume Crossfade';
      case 'filter_sweep': return 'Filter Sweep';
      case 'tension_builder': return 'Tension Builder';
      case 'intensity_shift': return 'Intensity Shift';
      case 'spatial_drift': return 'Spatial Drift';
      default: return 'New Morph';
    }
  }

  void _deleteMorph(RtpcSystemProvider provider, int morphId) {
    if (_selectedMorphId == morphId) {
      setState(() => _selectedMorphId = null);
    }
    provider.deleteMorph(morphId);
  }

  void _addParameter(RtpcSystemProvider provider, PresetMorph morph, (double, double) range) {
    final parameter = MorphParameter(
      name: '${_newParamTarget.displayName} ${morph.parameters.length + 1}',
      target: _newParamTarget,
      startValue: range.$1,
      endValue: range.$2,
    );
    provider.addMorphParameter(morph.id, parameter);
    setState(() => _isAddingParameter = false);
  }

  void _editMorphName(RtpcSystemProvider provider, PresetMorph morph) {
    final controller = TextEditingController(text: morph.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surface,
        title: Text('Rename Morph', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              provider.updateMorph(morph.id, name: controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(RtpcSystemProvider provider, PresetMorph morph) {
    final colors = [
      const Color(0xFF9C27B0), // Purple
      const Color(0xFF4A9EFF), // Blue
      const Color(0xFFFF9040), // Orange
      const Color(0xFF40FF90), // Green
      const Color(0xFFFF4060), // Red
      const Color(0xFF40C8FF), // Cyan
      const Color(0xFFFF40FF), // Magenta
      const Color(0xFFFFFF40), // Yellow
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surface,
        title: Text('Morph Color', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () {
                provider.updateMorph(morph.id, color: color);
                Navigator.pop(context);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: morph.color == color ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _getRandomColor() {
    final colors = [
      const Color(0xFF9C27B0),
      const Color(0xFF4A9EFF),
      const Color(0xFFFF9040),
      const Color(0xFF40FF90),
      const Color(0xFFFF4060),
      const Color(0xFF40C8FF),
    ];
    return colors[math.Random().nextInt(colors.length)];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MORPH LIST TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _MorphListTile extends StatelessWidget {
  final PresetMorph morph;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<double> onPositionChanged;

  const _MorphListTile({
    required this.morph,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onPositionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: morph.color.withValues(alpha: 0.5))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Color indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: morph.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                // Name
                Expanded(
                  child: Text(
                    morph.name,
                    style: TextStyle(
                      color: morph.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Delete
                if (isSelected)
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 16, color: FluxForgeTheme.errorRed),
                    onPressed: onDelete,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Mini slider
            Row(
              children: [
                Text(
                  'A',
                  style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 9),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      activeTrackColor: morph.color,
                      inactiveTrackColor: FluxForgeTheme.surface,
                      thumbColor: morph.color,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: morph.position,
                      onChanged: morph.enabled ? onPositionChanged : null,
                    ),
                  ),
                ),
                Text(
                  'B',
                  style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 9),
                ),
              ],
            ),
            // Info
            Text(
              '${morph.parameters.length} param${morph.parameters.length != 1 ? "s" : ""}',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PARAMETER TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _ParameterTile extends StatelessWidget {
  final MorphParameter parameter;
  final double morphPosition;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggle;
  final ValueChanged<MorphCurve> onCurveChanged;

  const _ParameterTile({
    required this.parameter,
    required this.morphPosition,
    required this.onRemove,
    required this.onToggle,
    required this.onCurveChanged,
  });

  @override
  Widget build(BuildContext context) {
    final currentValue = parameter.valueAt(morphPosition);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: parameter.enabled
              ? FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
              : FluxForgeTheme.borderSubtle.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          // Enable toggle
          Switch(
            value: parameter.enabled,
            onChanged: onToggle,
            activeColor: FluxForgeTheme.accentPurple,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 8),
          // Parameter info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parameter.target.displayName,
                  style: TextStyle(
                    color: parameter.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                // Range and current value
                Row(
                  children: [
                    Text(
                      '${parameter.startValue.toStringAsFixed(1)} → ${parameter.endValue.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentPurple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        currentValue.toStringAsFixed(2),
                        style: TextStyle(
                          color: FluxForgeTheme.accentPurple,
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Curve selector
          PopupMenuButton<MorphCurve>(
            initialValue: parameter.curve,
            tooltip: 'Curve',
            onSelected: onCurveChanged,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mini curve preview
                  Container(
                    width: 24,
                    height: 16,
                    child: CustomPaint(
                      painter: _MiniMorphCurvePainter(
                        curve: parameter.curve,
                        enabled: parameter.enabled,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 14, color: FluxForgeTheme.textMuted),
                ],
              ),
            ),
            itemBuilder: (context) => MorphCurve.values.map((curve) {
              return PopupMenuItem(
                value: curve,
                child: Text(curve.displayName),
              );
            }).toList(),
          ),
          const SizedBox(width: 8),
          // Remove
          IconButton(
            icon: Icon(Icons.close, size: 16, color: FluxForgeTheme.textMuted),
            onPressed: onRemove,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _CurveBackgroundPainter extends CustomPainter {
  final MorphCurve curve;
  final Color color;

  _CurveBackgroundPainter({
    required this.curve,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(0, size.height);

    for (int i = 0; i <= 50; i++) {
      final x = i / 50.0;
      final y = curve.apply(x);

      final px = x * size.width;
      final py = size.height - y * size.height;

      if (i == 0) {
        path.lineTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    path.lineTo(size.width, size.height);
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CurveBackgroundPainter oldDelegate) =>
      curve != oldDelegate.curve || color != oldDelegate.color;
}

class _MiniMorphCurvePainter extends CustomPainter {
  final MorphCurve curve;
  final bool enabled;

  _MiniMorphCurvePainter({
    required this.curve,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    for (int i = 0; i <= 20; i++) {
      final x = i / 20.0;
      final y = curve.apply(x);

      final px = x * size.width;
      final py = size.height - y * size.height;

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    final paint = Paint()
      ..color = enabled ? FluxForgeTheme.accentPurple : FluxForgeTheme.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MiniMorphCurvePainter oldDelegate) =>
      curve != oldDelegate.curve || enabled != oldDelegate.enabled;
}
