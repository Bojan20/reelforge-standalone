/// FluxForge Studio RTPC Macro Editor Panel
///
/// P4.5: RTPC Macro System UI
/// - Create/edit macros that control multiple RTPC bindings
/// - Visual knob control for macro value
/// - Binding list with curve visualization
/// - Enable/disable per-binding
/// - Preset factory macros
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/subsystems/rtpc_system_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RTPC MACRO EDITOR PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class RtpcMacroEditorPanel extends StatefulWidget {
  final double height;

  const RtpcMacroEditorPanel({
    super.key,
    this.height = 400,
  });

  @override
  State<RtpcMacroEditorPanel> createState() => _RtpcMacroEditorPanelState();
}

class _RtpcMacroEditorPanelState extends State<RtpcMacroEditorPanel>
    with SingleTickerProviderStateMixin {
  int? _selectedMacroId;
  bool _isAddingBinding = false;
  RtpcTargetParameter _newBindingTarget = RtpcTargetParameter.volume;

  @override
  Widget build(BuildContext context) {
    return Consumer<RtpcSystemProvider>(
      builder: (context, provider, _) {
        final macros = provider.rtpcMacros;

        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            border: Border(
              top: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(context, provider, macros.length),
              // Content
              Expanded(
                child: Row(
                  children: [
                    // Macro list (left)
                    SizedBox(
                      width: 240,
                      child: _buildMacroList(provider, macros),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                    ),
                    // Macro editor (right)
                    Expanded(
                      child: _selectedMacroId != null
                          ? _buildMacroEditor(provider, provider.getMacro(_selectedMacroId!))
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
          bottom: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 16, color: FluxForgeTheme.accent),
          const SizedBox(width: 8),
          Text(
            'RTPC Macros',
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
              color: FluxForgeTheme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: FluxForgeTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          // Factory presets
          PopupMenuButton<String>(
            icon: Icon(Icons.auto_awesome, size: 16, color: FluxForgeTheme.textMuted),
            tooltip: 'Factory Presets',
            onSelected: (preset) => _createFromPreset(provider, preset),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'tension_master', child: Text('Tension Master')),
              const PopupMenuItem(value: 'win_intensity', child: Text('Win Intensity')),
              const PopupMenuItem(value: 'feature_drama', child: Text('Feature Drama')),
              const PopupMenuItem(value: 'ambient_control', child: Text('Ambient Control')),
              const PopupMenuItem(value: 'cascade_power', child: Text('Cascade Power')),
            ],
          ),
          const SizedBox(width: 4),
          // Add macro
          IconButton(
            icon: Icon(Icons.add_circle_outline, size: 18, color: FluxForgeTheme.accent),
            tooltip: 'Create Macro',
            onPressed: () => _createNewMacro(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroList(RtpcSystemProvider provider, List<RtpcMacro> macros) {
    if (macros.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_outlined, size: 48, color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'No Macros',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a macro to control\nmultiple parameters at once',
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
      itemCount: macros.length,
      itemBuilder: (context, index) {
        final macro = macros[index];
        final isSelected = macro.id == _selectedMacroId;

        return _MacroListTile(
          macro: macro,
          isSelected: isSelected,
          onTap: () => setState(() => _selectedMacroId = macro.id),
          onDelete: () => _deleteMacro(provider, macro.id),
          onValueChanged: (value) => provider.setMacroValue(macro.id, value),
        );
      },
    );
  }

  Widget _buildMacroEditor(RtpcSystemProvider provider, RtpcMacro? macro) {
    if (macro == null) return _buildEmptyState();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Macro info header
          _buildMacroInfoHeader(provider, macro),
          const SizedBox(height: 16),

          // Value knob and bindings
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Large knob
              _buildMacroKnob(provider, macro),
              const SizedBox(width: 24),
              // Bindings list
              Expanded(
                child: _buildBindingsList(provider, macro),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroInfoHeader(RtpcSystemProvider provider, RtpcMacro macro) {
    return Row(
      children: [
        // Color indicator
        GestureDetector(
          onTap: () => _showColorPicker(provider, macro),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: macro.color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Name (editable)
        Expanded(
          child: InkWell(
            onTap: () => _editMacroName(provider, macro),
            child: Text(
              macro.name,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Enable toggle
        Switch(
          value: macro.enabled,
          onChanged: (v) => provider.setMacroEnabled(macro.id, v),
          activeColor: FluxForgeTheme.accent,
        ),
        // Reset button
        IconButton(
          icon: Icon(Icons.refresh, size: 18, color: FluxForgeTheme.textMuted),
          tooltip: 'Reset to default',
          onPressed: () => provider.resetMacro(macro.id),
        ),
      ],
    );
  }

  Widget _buildMacroKnob(RtpcSystemProvider provider, RtpcMacro macro) {
    final normalized = (macro.currentValue - macro.min) / (macro.max - macro.min);

    return Column(
      children: [
        // Knob
        GestureDetector(
          onPanUpdate: (details) {
            final delta = -details.delta.dy * 0.005;
            final newNormalized = (normalized + delta).clamp(0.0, 1.0);
            final newValue = macro.min + newNormalized * (macro.max - macro.min);
            provider.setMacroValue(macro.id, newValue);
          },
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: FluxForgeTheme.bgDeep,
              border: Border.all(color: macro.color.withValues(alpha: 0.5), width: 2),
              boxShadow: [
                BoxShadow(
                  color: macro.color.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _KnobPainter(
                value: normalized,
                color: macro.color,
                enabled: macro.enabled,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Value display
        Text(
          macro.currentValue.toStringAsFixed(2),
          style: TextStyle(
            color: macro.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
        // Range
        Text(
          '${macro.min.toStringAsFixed(1)} - ${macro.max.toStringAsFixed(1)}',
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildBindingsList(RtpcSystemProvider provider, RtpcMacro macro) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bindings header
        Row(
          children: [
            Text(
              'Bindings',
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
                '${macro.bindings.length}',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.add, size: 18, color: FluxForgeTheme.accent),
              tooltip: 'Add Binding',
              onPressed: () => setState(() => _isAddingBinding = true),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Add binding form
        if (_isAddingBinding) _buildAddBindingForm(provider, macro),

        // Bindings
        if (macro.bindings.isEmpty && !_isAddingBinding)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No bindings. Add parameters to control.',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ...macro.bindings.map((binding) => _BindingTile(
                binding: binding,
                macroValue: macro.currentValue,
                macroMin: macro.min,
                macroMax: macro.max,
                onRemove: () => provider.removeMacroBinding(macro.id, binding.id),
                onToggle: (enabled) {
                  provider.updateMacroBinding(
                    macro.id,
                    binding.id,
                    binding.copyWith(enabled: enabled),
                  );
                },
                onInvert: (inverted) {
                  provider.updateMacroBinding(
                    macro.id,
                    binding.id,
                    binding.copyWith(inverted: inverted),
                  );
                },
              )),
      ],
    );
  }

  Widget _buildAddBindingForm(RtpcSystemProvider provider, RtpcMacro macro) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Binding',
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
                  value: _newBindingTarget,
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
                      setState(() => _newBindingTarget = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Add button
              ElevatedButton(
                onPressed: () => _addBinding(provider, macro),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: const Text('Add'),
              ),
              const SizedBox(width: 4),
              // Cancel
              TextButton(
                onPressed: () => setState(() => _isAddingBinding = false),
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
            'Select a macro to edit',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════════

  void _createNewMacro(RtpcSystemProvider provider) {
    final macro = provider.createMacro(
      name: 'New Macro',
      min: 0.0,
      max: 1.0,
      color: _getRandomColor(),
    );
    setState(() => _selectedMacroId = macro.id);
  }

  void _createFromPreset(RtpcSystemProvider provider, String presetId) {
    final presets = _getFactoryPresets();
    final preset = presets[presetId];
    if (preset == null) return;

    final macro = provider.createMacroFromPreset(preset);
    setState(() => _selectedMacroId = macro.id);
  }

  void _deleteMacro(RtpcSystemProvider provider, int macroId) {
    if (_selectedMacroId == macroId) {
      setState(() => _selectedMacroId = null);
    }
    provider.deleteMacro(macroId);
  }

  void _addBinding(RtpcSystemProvider provider, RtpcMacro macro) {
    final range = _newBindingTarget.defaultRange;
    final binding = RtpcMacroBinding(
      id: DateTime.now().millisecondsSinceEpoch,
      target: _newBindingTarget,
      curve: RtpcCurve.linear(0.0, 1.0, range.$1, range.$2),
    );
    provider.addMacroBinding(macro.id, binding);
    setState(() => _isAddingBinding = false);
  }

  void _editMacroName(RtpcSystemProvider provider, RtpcMacro macro) {
    final controller = TextEditingController(text: macro.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surface,
        title: Text('Rename Macro', style: TextStyle(color: FluxForgeTheme.textPrimary)),
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
              provider.updateMacro(macro.id, name: controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(RtpcSystemProvider provider, RtpcMacro macro) {
    final colors = [
      const Color(0xFF4A9EFF), // Blue
      const Color(0xFFFF9040), // Orange
      const Color(0xFF40FF90), // Green
      const Color(0xFFFF4060), // Red
      const Color(0xFF40C8FF), // Cyan
      const Color(0xFFFF40FF), // Magenta
      const Color(0xFFFFFF40), // Yellow
      const Color(0xFF9040FF), // Purple
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surface,
        title: Text('Macro Color', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () {
                provider.updateMacro(macro.id, color: color);
                Navigator.pop(context);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: macro.color == color ? Colors.white : Colors.transparent,
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
      const Color(0xFF4A9EFF),
      const Color(0xFFFF9040),
      const Color(0xFF40FF90),
      const Color(0xFFFF4060),
      const Color(0xFF40C8FF),
      const Color(0xFFFF40FF),
      const Color(0xFFFFFF40),
      const Color(0xFF9040FF),
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  Map<String, Map<String, dynamic>> _getFactoryPresets() {
    // Helper to create curve points JSON
    List<Map<String, dynamic>> linearCurve(double x0, double y0, double x1, double y1) {
      return [
        {'x': x0, 'y': y0, 'shape': 0},
        {'x': x1, 'y': y1, 'shape': 0},
      ];
    }

    return {
      'tension_master': {
        'name': 'Tension Master',
        'description': 'Controls tension buildup across multiple parameters',
        'min': 0.0,
        'max': 1.0,
        'color': 0xFFFF4060,
        'bindings': [
          {
            'id': 1,
            'target': RtpcTargetParameter.volume.index,
            'curve': {'points': linearCurve(0.0, 0.7, 1.0, 1.0)},
          },
          {
            'id': 2,
            'target': RtpcTargetParameter.lowPassFilter.index,
            'inverted': true,
            'curve': {'points': linearCurve(0.0, 2000.0, 1.0, 20000.0)},
          },
          {
            'id': 3,
            'target': RtpcTargetParameter.pitch.index,
            'curve': {'points': linearCurve(0.0, 0.0, 1.0, 0.5)},
          },
        ],
      },
      'win_intensity': {
        'name': 'Win Intensity',
        'description': 'Scales audio for different win tiers',
        'min': 0.0,
        'max': 5.0,
        'color': 0xFFFFFF40,
        'bindings': [
          {
            'id': 1,
            'target': RtpcTargetParameter.volume.index,
            'curve': {'points': linearCurve(0.0, 0.5, 5.0, 1.0)},
          },
          {
            'id': 2,
            'target': RtpcTargetParameter.reverbSend.index,
            'curve': {'points': linearCurve(0.0, 0.1, 5.0, 0.6)},
          },
        ],
      },
      'feature_drama': {
        'name': 'Feature Drama',
        'description': 'Builds drama during bonus features',
        'min': 0.0,
        'max': 1.0,
        'color': 0xFF9040FF,
        'bindings': [
          {
            'id': 1,
            'target': RtpcTargetParameter.volume.index,
            'curve': {'points': linearCurve(0.0, 0.6, 1.0, 1.0)},
          },
          {
            'id': 2,
            'target': RtpcTargetParameter.highPassFilter.index,
            'curve': {'points': linearCurve(0.0, 20.0, 1.0, 200.0)},
          },
        ],
      },
      'ambient_control': {
        'name': 'Ambient Control',
        'description': 'Fades ambient layers based on game state',
        'min': 0.0,
        'max': 1.0,
        'color': 0xFF40C8FF,
        'bindings': [
          {
            'id': 1,
            'target': RtpcTargetParameter.volume.index,
            'curve': {'points': linearCurve(0.0, 0.0, 1.0, 0.4)},
          },
          {
            'id': 2,
            'target': RtpcTargetParameter.lowPassFilter.index,
            'curve': {'points': linearCurve(0.0, 500.0, 1.0, 8000.0)},
          },
        ],
      },
      'cascade_power': {
        'name': 'Cascade Power',
        'description': 'Escalates audio with cascade depth',
        'min': 0.0,
        'max': 10.0,
        'color': 0xFFFF9040,
        'bindings': [
          {
            'id': 1,
            'target': RtpcTargetParameter.volume.index,
            'curve': {'points': linearCurve(0.0, 0.7, 10.0, 1.0)},
          },
          {
            'id': 2,
            'target': RtpcTargetParameter.pitch.index,
            'curve': {'points': linearCurve(0.0, 0.0, 10.0, 2.0)},
          },
          {
            'id': 3,
            'target': RtpcTargetParameter.delaySend.index,
            'curve': {'points': linearCurve(0.0, 0.0, 10.0, 0.4)},
          },
        ],
      },
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MACRO LIST TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _MacroListTile extends StatelessWidget {
  final RtpcMacro macro;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<double> onValueChanged;

  const _MacroListTile({
    required this.macro,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = (macro.currentValue - macro.min) / (macro.max - macro.min);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: macro.color.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          children: [
            // Mini knob
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FluxForgeTheme.bgDeep,
                border: Border.all(color: macro.color.withValues(alpha: 0.5)),
              ),
              child: CustomPaint(
                painter: _KnobPainter(
                  value: normalized,
                  color: macro.color,
                  enabled: macro.enabled,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Name and value
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    macro.name,
                    style: TextStyle(
                      color: macro.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${macro.bindings.length} binding${macro.bindings.length != 1 ? "s" : ""}',
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            // Delete
            if (isSelected)
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: FluxForgeTheme.errorRed),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BINDING TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _BindingTile extends StatelessWidget {
  final RtpcMacroBinding binding;
  final double macroValue;
  final double macroMin;
  final double macroMax;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggle;
  final ValueChanged<bool> onInvert;

  const _BindingTile({
    required this.binding,
    required this.macroValue,
    required this.macroMin,
    required this.macroMax,
    required this.onRemove,
    required this.onToggle,
    required this.onInvert,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedMacro = (macroValue - macroMin) / (macroMax - macroMin);
    final outputValue = binding.evaluate(normalizedMacro);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: binding.enabled
              ? FluxForgeTheme.border.withValues(alpha: 0.3)
              : FluxForgeTheme.border.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          // Enable toggle
          Switch(
            value: binding.enabled,
            onChanged: onToggle,
            activeColor: FluxForgeTheme.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 8),
          // Target parameter
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  binding.target.displayName,
                  style: TextStyle(
                    color: binding.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                // Output value
                Text(
                  'Output: ${outputValue.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Invert toggle
          Tooltip(
            message: 'Invert curve',
            child: IconButton(
              icon: Icon(
                Icons.swap_vert,
                size: 18,
                color: binding.inverted ? FluxForgeTheme.accent : FluxForgeTheme.textMuted,
              ),
              onPressed: () => onInvert(!binding.inverted),
            ),
          ),
          // Mini curve preview
          Container(
            width: 50,
            height: 30,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: CustomPaint(
              painter: _MiniCurvePainter(
                curve: binding.curve,
                inverted: binding.inverted,
                currentValue: normalizedMacro,
                enabled: binding.enabled,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Remove
          IconButton(
            icon: Icon(Icons.close, size: 16, color: FluxForgeTheme.textMuted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _KnobPainter extends CustomPainter {
  final double value;
  final Color color;
  final bool enabled;

  _KnobPainter({
    required this.value,
    required this.color,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;

    // Arc background
    final bgPaint = Paint()
      ..color = FluxForgeTheme.border.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const startAngle = 0.75 * math.pi;
    const sweepAngle = 1.5 * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Arc value
    final valuePaint = Paint()
      ..color = enabled ? color : FluxForgeTheme.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * value,
      false,
      valuePaint,
    );

    // Indicator dot
    final angle = startAngle + sweepAngle * value;
    final dotCenter = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );

    final dotPaint = Paint()
      ..color = enabled ? color : FluxForgeTheme.textMuted
      ..style = PaintingStyle.fill;

    canvas.drawCircle(dotCenter, 4, dotPaint);
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) =>
      value != oldDelegate.value ||
      color != oldDelegate.color ||
      enabled != oldDelegate.enabled;
}

class _MiniCurvePainter extends CustomPainter {
  final RtpcCurve curve;
  final bool inverted;
  final double currentValue;
  final bool enabled;

  _MiniCurvePainter({
    required this.curve,
    required this.inverted,
    required this.currentValue,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Get output range from curve points
    double outputMin = 0.0;
    double outputMax = 1.0;
    if (curve.points.isNotEmpty) {
      outputMin = curve.points.map((p) => p.y).reduce(math.min);
      outputMax = curve.points.map((p) => p.y).reduce(math.max);
    }
    final outputRange = outputMax - outputMin;
    if (outputRange == 0) return;

    final path = Path();

    // Draw curve
    for (int i = 0; i <= 50; i++) {
      final x = i / 50.0;
      final input = inverted ? (1.0 - x) : x;

      // Normalize output to 0-1 range for display
      final rawOutput = curve.evaluate(input);
      final normalizedOutput = (rawOutput - outputMin) / outputRange;

      final px = x * size.width;
      final py = size.height - normalizedOutput * size.height;

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    final paint = Paint()
      ..color = enabled ? FluxForgeTheme.accent : FluxForgeTheme.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawPath(path, paint);

    // Current value indicator
    final cx = currentValue * size.width;
    final input = inverted ? (1.0 - currentValue) : currentValue;
    final rawOutput = curve.evaluate(input);
    final normalizedOutput = (rawOutput - outputMin) / outputRange;
    final cy = size.height - normalizedOutput * size.height;

    final dotPaint = Paint()
      ..color = enabled ? FluxForgeTheme.accent : FluxForgeTheme.textMuted
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx, cy), 3, dotPaint);
  }

  @override
  bool shouldRepaint(_MiniCurvePainter oldDelegate) =>
      curve != oldDelegate.curve ||
      inverted != oldDelegate.inverted ||
      currentValue != oldDelegate.currentValue ||
      enabled != oldDelegate.enabled;
}
