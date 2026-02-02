/// RTPC DSP Binding Editor Panel (P11.1.2)
///
/// Visual editor for creating and managing RTPC → DSP parameter bindings:
/// - Select source RTPC
/// - Select target DSP processor and parameter
/// - Configure curve shape with visual preview
/// - Live RTPC slider for testing
/// - Range control for modulation amount
///
/// Enables game-driven DSP control like Wwise/FMOD:
/// - winTier RTPC → filter cutoff (more excitement at higher wins)
/// - momentum RTPC → reverb decay (longer reverb in tense moments)
/// - cascadeDepth RTPC → compressor ratio (heavier compression in cascades)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../providers/subsystems/rtpc_system_provider.dart';
import '../../services/dsp_rtpc_modulator.dart';
import '../../theme/fluxforge_theme.dart';

// Alias colors for cleaner code
const _orange = FluxForgeTheme.accentOrange;
const _green = FluxForgeTheme.accentGreen;
const _red = FluxForgeTheme.accentRed;
const _cyan = FluxForgeTheme.accentCyan;

// ═══════════════════════════════════════════════════════════════════════════════
// RTPC DSP BINDING EDITOR PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class RtpcDspBindingEditorPanel extends StatefulWidget {
  final double height;

  const RtpcDspBindingEditorPanel({
    super.key,
    this.height = 450,
  });

  @override
  State<RtpcDspBindingEditorPanel> createState() => _RtpcDspBindingEditorPanelState();
}

class _RtpcDspBindingEditorPanelState extends State<RtpcDspBindingEditorPanel> {
  int? _selectedBindingId;
  bool _isCreatingNew = false;

  // New binding form state
  int? _newRtpcId;
  int _newTrackId = 0;
  int _newSlotIndex = 0;
  RtpcTargetParameter _newTarget = RtpcTargetParameter.filterCutoff;
  String _newCurvePreset = 'linear';

  // Live preview state
  double _previewRtpcValue = 0.5;

  @override
  Widget build(BuildContext context) {
    return Consumer<RtpcSystemProvider>(
      builder: (context, provider, _) {
        final bindings = provider.dspBindingsList;

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
              _buildHeader(context, provider, bindings.length),
              // Content
              Expanded(
                child: Row(
                  children: [
                    // Binding list (left)
                    SizedBox(
                      width: 280,
                      child: _buildBindingList(provider, bindings),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.2),
                    ),
                    // Editor panel (right)
                    Expanded(
                      child: _isCreatingNew
                          ? _buildNewBindingForm(provider)
                          : _selectedBindingId != null
                              ? _buildBindingEditor(provider, provider.getDspBinding(_selectedBindingId!))
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
          Icon(Icons.settings_input_component, size: 16, color: _orange),
          const SizedBox(width: 8),
          Text(
            'RTPC → DSP Bindings',
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
              color: _orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: _orange,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          // Quick templates
          PopupMenuButton<String>(
            icon: Icon(Icons.flash_on, size: 16, color: FluxForgeTheme.textMuted),
            tooltip: 'Quick Templates',
            onSelected: (template) => _createFromTemplate(provider, template),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'win_filter', child: Text('Win → Filter Sweep')),
              const PopupMenuItem(value: 'momentum_reverb', child: Text('Momentum → Reverb')),
              const PopupMenuItem(value: 'cascade_comp', child: Text('Cascade → Compressor')),
              const PopupMenuItem(value: 'tension_delay', child: Text('Tension → Delay')),
            ],
          ),
          const SizedBox(width: 4),
          // Add binding
          IconButton(
            icon: Icon(Icons.add_circle_outline, size: 18, color: _orange),
            tooltip: 'Create Binding',
            onPressed: () => setState(() {
              _isCreatingNew = true;
              _selectedBindingId = null;
              _newRtpcId = provider.rtpcDefinitions.isNotEmpty ? provider.rtpcDefinitions.first.id : null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBindingList(RtpcSystemProvider provider, List<RtpcDspBinding> bindings) {
    if (bindings.isEmpty && !_isCreatingNew) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, size: 48, color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'No DSP Bindings',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a binding to route\nRTPC to DSP parameters',
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
      itemCount: bindings.length,
      itemBuilder: (context, index) {
        final binding = bindings[index];
        final isSelected = binding.id == _selectedBindingId;
        final rtpc = provider.getRtpc(binding.rtpcId);

        return _DspBindingListTile(
          binding: binding,
          rtpcName: rtpc?.name ?? 'Unknown',
          isSelected: isSelected,
          onTap: () => setState(() {
            _selectedBindingId = binding.id;
            _isCreatingNew = false;
          }),
          onToggle: (enabled) => provider.setDspBindingEnabled(binding.id, enabled),
          onDelete: () => _deleteBinding(provider, binding.id),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, size: 48, color: FluxForgeTheme.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'Select a binding or create new',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNewBindingForm(RtpcSystemProvider provider) {
    final rtpcs = provider.rtpcDefinitions;
    final dspParams = RtpcTargetParameterExtension.dspParameters;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Form header
          Row(
            children: [
              Icon(Icons.add_circle, size: 20, color: _green),
              const SizedBox(width: 8),
              Text(
                'Create DSP Binding',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _isCreatingNew = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Source RTPC
          _buildFormSection('Source RTPC', Icons.tune, [
            if (rtpcs.isEmpty)
              _buildWarning('No RTPCs defined. Create an RTPC first.')
            else
              DropdownButtonFormField<int>(
                value: _newRtpcId,
                decoration: _inputDecoration('Select RTPC'),
                items: rtpcs.map((r) => DropdownMenuItem(
                  value: r.id,
                  child: Text(r.name),
                )).toList(),
                onChanged: (v) => setState(() => _newRtpcId = v),
              ),
          ]),
          const SizedBox(height: 16),

          // Target DSP Parameter
          _buildFormSection('Target DSP Parameter', Icons.equalizer, [
            DropdownButtonFormField<RtpcTargetParameter>(
              value: _newTarget,
              decoration: _inputDecoration('Parameter'),
              items: dspParams.map((p) => DropdownMenuItem(
                value: p,
                child: Text(p.displayName),
              )).toList(),
              onChanged: (v) => setState(() => _newTarget = v ?? RtpcTargetParameter.filterCutoff),
            ),
            const SizedBox(height: 8),
            // Show processor type hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Processor: ${DspRtpcModulator.getProcessorForParameter(_newTarget)?.fullName ?? "Any"}',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Target Track & Slot
          _buildFormSection('Target Location', Icons.audio_file, [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _newTrackId.toString(),
                    decoration: _inputDecoration('Track ID'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _newTrackId = int.tryParse(v) ?? 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _newSlotIndex.toString(),
                    decoration: _inputDecoration('Slot Index'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _newSlotIndex = int.tryParse(v) ?? 0,
                  ),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 16),

          // Curve Preset
          _buildFormSection('Mapping Curve', Icons.show_chart, [
            DropdownButtonFormField<String>(
              value: _newCurvePreset,
              decoration: _inputDecoration('Curve Shape'),
              items: DspRtpcModulator.instance.presetCurveNames.map((name) => DropdownMenuItem(
                value: name,
                child: Text(_formatCurveName(name)),
              )).toList(),
              onChanged: (v) => setState(() => _newCurvePreset = v ?? 'linear'),
            ),
            const SizedBox(height: 8),
            // Curve preview
            SizedBox(
              height: 80,
              child: _CurvePreview(
                curve: DspRtpcModulator.instance.getPresetCurve(_newCurvePreset, _newTarget),
                color: _orange,
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // Create button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create Binding'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _newRtpcId != null
                  ? () => _createBinding(provider)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBindingEditor(RtpcSystemProvider provider, RtpcDspBinding? binding) {
    if (binding == null) return _buildEmptyState();

    final rtpc = provider.getRtpc(binding.rtpcId);
    final range = DspRtpcModulator.instance.getParameterRange(binding.target);

    // Calculate current output value based on preview RTPC value
    final outputValue = binding.evaluate(_previewRtpcValue);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with enable toggle
          Row(
            children: [
              Icon(Icons.link, size: 20, color: binding.enabled ? _orange : FluxForgeTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  binding.label ?? 'DSP Binding',
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Switch(
                value: binding.enabled,
                onChanged: (v) => provider.setDspBindingEnabled(binding.id, v),
                activeColor: _orange,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Binding info cards
          Row(
            children: [
              Expanded(
                child: _InfoCard(
                  label: 'Source RTPC',
                  value: rtpc?.name ?? 'Unknown',
                  icon: Icons.tune,
                  color: FluxForgeTheme.accent,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 20, color: Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoCard(
                  label: 'Target',
                  value: binding.target.displayName,
                  icon: Icons.equalizer,
                  color: _orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoCard(
                  label: 'Track',
                  value: binding.trackId == 0 ? 'Master' : 'Track ${binding.trackId}',
                  icon: Icons.audio_file,
                  color: _green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoCard(
                  label: 'Slot',
                  value: 'Slot ${binding.slotIndex}',
                  icon: Icons.layers,
                  color: _cyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Live preview section
          _buildFormSection('Live Preview', Icons.play_circle_outline, [
            // RTPC slider
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    'RTPC Input:',
                    style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _previewRtpcValue,
                    onChanged: (v) {
                      setState(() => _previewRtpcValue = v);
                      // Live apply if binding is enabled
                      if (binding.enabled) {
                        final outValue = binding.evaluate(v);
                        provider.applyDspBinding(binding.id);
                        // Also notify about RTPC value change for UI feedback
                        final rtpcDef = provider.getRtpc(binding.rtpcId);
                        if (rtpcDef != null) {
                          final denormalized = rtpcDef.min + (v * (rtpcDef.max - rtpcDef.min));
                          provider.setRtpc(binding.rtpcId, denormalized);
                        }
                      }
                    },
                    activeColor: FluxForgeTheme.accent,
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${(_previewRtpcValue * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Output value display
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    'Output:',
                    style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _orange.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      DspRtpcModulator.instance.formatParameterValue(binding.target, outputValue),
                      style: TextStyle(
                        color: _orange,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Output range display
            if (range != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Range: ${DspRtpcModulator.instance.formatParameterValue(binding.target, range.min)}',
                    style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
                  ),
                  Text(
                    '→ ${DspRtpcModulator.instance.formatParameterValue(binding.target, range.max)}',
                    style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
          ]),
          const SizedBox(height: 16),

          // Curve visualization
          _buildFormSection('Mapping Curve', Icons.show_chart, [
            SizedBox(
              height: 120,
              child: _CurvePreview(
                curve: binding.curve,
                color: _orange,
                inputMarker: _previewRtpcValue,
                outputMarker: binding.curve.evaluate(_previewRtpcValue),
              ),
            ),
            const SizedBox(height: 8),
            // Curve preset selector
            DropdownButtonFormField<String>(
              value: null,
              decoration: _inputDecoration('Change Curve'),
              hint: const Text('Select preset curve'),
              items: DspRtpcModulator.instance.presetCurveNames.map((name) => DropdownMenuItem(
                value: name,
                child: Text(_formatCurveName(name)),
              )).toList(),
              onChanged: (v) {
                if (v != null) {
                  final newCurve = DspRtpcModulator.instance.getPresetCurve(v, binding.target);
                  provider.updateDspBindingCurve(binding.id, newCurve);
                }
              },
            ),
          ]),
          const SizedBox(height: 24),

          // Delete button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(Icons.delete_outline, color: _red),
              label: Text('Delete Binding', style: TextStyle(color: _red)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _red.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _deleteBinding(provider, binding.id),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFormSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: FluxForgeTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildWarning(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 18, color: _orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: _orange, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: FluxForgeTheme.textMuted),
      filled: true,
      fillColor: FluxForgeTheme.bgMid,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: FluxForgeTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _orange),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  String _formatCurveName(String name) {
    return name.split('_').map((s) => s[0].toUpperCase() + s.substring(1)).join(' ');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _createBinding(RtpcSystemProvider provider) {
    if (_newRtpcId == null) return;

    final processorType = DspRtpcModulator.getProcessorForParameter(_newTarget);

    provider.createDspBindingWithPreset(
      rtpcId: _newRtpcId!,
      target: _newTarget,
      trackId: _newTrackId,
      slotIndex: _newSlotIndex,
      processorType: processorType ?? DspNodeType.eq,
      curvePreset: _newCurvePreset,
    );

    setState(() {
      _isCreatingNew = false;
      _selectedBindingId = provider.dspBindingsList.last.id;
    });
  }

  void _createFromTemplate(RtpcSystemProvider provider, String template) {
    final rtpcs = provider.rtpcDefinitions;
    if (rtpcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an RTPC first')),
      );
      return;
    }

    // Find or create appropriate RTPC
    int rtpcId = rtpcs.first.id;

    // Try to find matching RTPC by name
    switch (template) {
      case 'win_filter':
        final winRtpc = provider.getRtpcByName('winTier') ?? provider.getRtpcByName('Win');
        if (winRtpc != null) rtpcId = winRtpc.id;
        provider.createDspBindingWithPreset(
          rtpcId: rtpcId,
          target: RtpcTargetParameter.filterCutoff,
          trackId: 0,
          slotIndex: 0,
          processorType: DspNodeType.eq,
          curvePreset: 'logarithmic',
          label: 'Win → Filter Sweep',
        );

      case 'momentum_reverb':
        final momentumRtpc = provider.getRtpcByName('momentum') ?? provider.getRtpcByName('Tension');
        if (momentumRtpc != null) rtpcId = momentumRtpc.id;
        provider.createDspBindingWithPreset(
          rtpcId: rtpcId,
          target: RtpcTargetParameter.reverbDecay,
          trackId: 0,
          slotIndex: 0,
          processorType: DspNodeType.reverb,
          curvePreset: 's_curve',
          label: 'Momentum → Reverb Decay',
        );

      case 'cascade_comp':
        final cascadeRtpc = provider.getRtpcByName('cascadeDepth') ?? provider.getRtpcByName('Cascade');
        if (cascadeRtpc != null) rtpcId = cascadeRtpc.id;
        provider.createDspBindingWithPreset(
          rtpcId: rtpcId,
          target: RtpcTargetParameter.compressorRatio,
          trackId: 0,
          slotIndex: 0,
          processorType: DspNodeType.compressor,
          curvePreset: 'exponential',
          label: 'Cascade → Comp Ratio',
        );

      case 'tension_delay':
        final tensionRtpc = provider.getRtpcByName('tension') ?? provider.getRtpcByName('Anticipation');
        if (tensionRtpc != null) rtpcId = tensionRtpc.id;
        provider.createDspBindingWithPreset(
          rtpcId: rtpcId,
          target: RtpcTargetParameter.delayFeedback,
          trackId: 0,
          slotIndex: 0,
          processorType: DspNodeType.delay,
          curvePreset: 'linear',
          label: 'Tension → Delay Feedback',
        );
    }

    setState(() {
      _selectedBindingId = provider.dspBindingsList.last.id;
    });
  }

  void _deleteBinding(RtpcSystemProvider provider, int bindingId) {
    provider.deleteDspBinding(bindingId);
    if (_selectedBindingId == bindingId) {
      setState(() => _selectedBindingId = null);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUPPORT WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// List tile for DSP binding
class _DspBindingListTile extends StatelessWidget {
  final RtpcDspBinding binding;
  final String rtpcName;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _DspBindingListTile({
    required this.binding,
    required this.rtpcName,
    required this.isSelected,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? _orange.withValues(alpha: 0.15) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected ? _orange : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            children: [
              // Enable toggle
              GestureDetector(
                onTap: () => onToggle(!binding.enabled),
                child: Icon(
                  binding.enabled ? Icons.link : Icons.link_off,
                  size: 16,
                  color: binding.enabled ? _orange : FluxForgeTheme.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              // Binding info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$rtpcName → ${binding.target.displayName}',
                      style: TextStyle(
                        color: binding.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Track ${binding.trackId}, Slot ${binding.slotIndex}',
                      style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              // Delete
              IconButton(
                icon: Icon(Icons.close, size: 14, color: FluxForgeTheme.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Info card widget
class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Curve preview visualization
class _CurvePreview extends StatelessWidget {
  final RtpcCurve curve;
  final Color color;
  final double? inputMarker;
  final double? outputMarker;

  const _CurvePreview({
    required this.curve,
    required this.color,
    this.inputMarker,
    this.outputMarker,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _CurvePainter(
            curve: curve,
            color: color,
            inputMarker: inputMarker,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final RtpcCurve curve;
  final Color color;
  final double? inputMarker;

  _CurvePainter({
    required this.curve,
    required this.color,
    this.inputMarker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw grid
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw curve
    final path = Path();
    const steps = 100;

    for (int i = 0; i <= steps; i++) {
      final x = i / steps;
      final y = curve.evaluate(x);

      final px = x * size.width;
      // Invert Y and normalize to visible range (assume 0-1 output for now)
      final py = size.height - (y.clamp(0.0, 1.0) * size.height);

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    canvas.drawPath(path, paint);

    // Draw input marker
    if (inputMarker != null) {
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      final mx = inputMarker! * size.width;
      final my = size.height - (curve.evaluate(inputMarker!).clamp(0.0, 1.0) * size.height);

      // Vertical line
      canvas.drawLine(
        Offset(mx, 0),
        Offset(mx, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..strokeWidth = 1,
      );

      // Dot
      canvas.drawCircle(Offset(mx, my), 5, markerPaint);
      canvas.drawCircle(Offset(mx, my), 5, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter oldDelegate) =>
      curve != oldDelegate.curve ||
      color != oldDelegate.color ||
      inputMarker != oldDelegate.inputMarker;
}
