/// Preset Editor Panel — Custom Event Preset Creation
///
/// UI for creating and editing custom EventPresets:
/// - Audio parameters (volume, pitch, pan, filters)
/// - Timing parameters (delay, fades, cooldown)
/// - Voice settings (polyphony, stealing, priority)
/// - Preset management (save, duplicate, delete)
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section 8
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../theme/fluxforge_theme.dart';

class PresetEditorPanel extends StatefulWidget {
  final EventPreset? initialPreset;
  final VoidCallback? onClose;

  const PresetEditorPanel({
    super.key,
    this.initialPreset,
    this.onClose,
  });

  @override
  State<PresetEditorPanel> createState() => _PresetEditorPanelState();
}

class _PresetEditorPanelState extends State<PresetEditorPanel> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  // Audio params
  double _volume = 0.0;
  double _pitch = 1.0;
  double _pan = 0.0;
  double _lpf = 20000.0;
  double _hpf = 20.0;

  // Timing params
  int _delayMs = 0;
  int _fadeInMs = 0;
  int _fadeOutMs = 0;
  int _cooldownMs = 0;

  // Voice params
  int _polyphony = 1;
  String _voiceLimitGroup = 'default';
  VoiceStealPolicy _voiceStealPolicy = VoiceStealPolicy.oldest;
  int _voiceStealFadeMs = 10;
  int _priority = 50;
  PreloadPolicy _preloadPolicy = PreloadPolicy.onStageEnter;

  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();

    if (widget.initialPreset != null) {
      _loadPreset(widget.initialPreset!);
      _isEditing = true;
    }
  }

  void _loadPreset(EventPreset preset) {
    _nameController.text = preset.name;
    _descriptionController.text = preset.description ?? '';
    _volume = preset.volume;
    _pitch = preset.pitch;
    _pan = preset.pan;
    _lpf = preset.lpf;
    _hpf = preset.hpf;
    _delayMs = preset.delayMs;
    _fadeInMs = preset.fadeInMs;
    _fadeOutMs = preset.fadeOutMs;
    _cooldownMs = preset.cooldownMs;
    _polyphony = preset.polyphony;
    _voiceLimitGroup = preset.voiceLimitGroup;
    _voiceStealPolicy = preset.voiceStealPolicy;
    _voiceStealFadeMs = preset.voiceStealFadeMs;
    _priority = preset.priority;
    _preloadPolicy = preset.preloadPolicy;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  EventPreset _buildPreset() {
    final name = _nameController.text.trim();
    final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

    return EventPreset(
      presetId: widget.initialPreset?.presetId ?? 'custom_$id',
      name: name.isEmpty ? 'Custom Preset' : name,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      volume: _volume,
      pitch: _pitch,
      pan: _pan,
      lpf: _lpf,
      hpf: _hpf,
      delayMs: _delayMs,
      fadeInMs: _fadeInMs,
      fadeOutMs: _fadeOutMs,
      cooldownMs: _cooldownMs,
      polyphony: _polyphony,
      voiceLimitGroup: _voiceLimitGroup,
      voiceStealPolicy: _voiceStealPolicy,
      voiceStealFadeMs: _voiceStealFadeMs,
      priority: _priority,
      preloadPolicy: _preloadPolicy,
    );
  }

  void _savePreset() {
    final provider = context.read<AutoEventBuilderProvider>();
    final preset = _buildPreset();

    if (_isEditing && widget.initialPreset != null) {
      provider.removePreset(widget.initialPreset!.presetId);
    }
    provider.addPreset(preset);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Preset "${preset.name}" saved'),
        backgroundColor: FluxForgeTheme.bgMid,
        duration: const Duration(seconds: 2),
      ),
    );

    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _Header(
            isEditing: _isEditing,
            onClose: widget.onClose,
            onSave: _savePreset,
          ),

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name & Description
                  _SectionHeader(title: 'General'),
                  const SizedBox(height: 8),
                  _TextField(
                    label: 'Name',
                    controller: _nameController,
                    hint: 'My Custom Preset',
                  ),
                  const SizedBox(height: 8),
                  _TextField(
                    label: 'Description',
                    controller: _descriptionController,
                    hint: 'Optional description...',
                    maxLines: 2,
                  ),

                  const SizedBox(height: 20),

                  // Audio Parameters
                  _SectionHeader(title: 'Audio'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SliderField(
                          label: 'Volume',
                          value: _volume,
                          min: -60,
                          max: 12,
                          suffix: 'dB',
                          onChanged: (v) => setState(() => _volume = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SliderField(
                          label: 'Pitch',
                          value: _pitch,
                          min: 0.5,
                          max: 2.0,
                          suffix: 'x',
                          decimals: 2,
                          onChanged: (v) => setState(() => _pitch = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SliderField(
                          label: 'Pan',
                          value: _pan,
                          min: -1.0,
                          max: 1.0,
                          decimals: 2,
                          onChanged: (v) => setState(() => _pan = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SliderField(
                          label: 'LPF',
                          value: _lpf,
                          min: 100,
                          max: 20000,
                          suffix: 'Hz',
                          decimals: 0,
                          onChanged: (v) => setState(() => _lpf = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SliderField(
                    label: 'HPF',
                    value: _hpf,
                    min: 20,
                    max: 5000,
                    suffix: 'Hz',
                    decimals: 0,
                    onChanged: (v) => setState(() => _hpf = v),
                  ),

                  const SizedBox(height: 20),

                  // Timing Parameters
                  _SectionHeader(title: 'Timing'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _IntField(
                          label: 'Delay',
                          value: _delayMs,
                          suffix: 'ms',
                          onChanged: (v) => setState(() => _delayMs = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _IntField(
                          label: 'Cooldown',
                          value: _cooldownMs,
                          suffix: 'ms',
                          onChanged: (v) => setState(() => _cooldownMs = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _IntField(
                          label: 'Fade In',
                          value: _fadeInMs,
                          suffix: 'ms',
                          onChanged: (v) => setState(() => _fadeInMs = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _IntField(
                          label: 'Fade Out',
                          value: _fadeOutMs,
                          suffix: 'ms',
                          onChanged: (v) => setState(() => _fadeOutMs = v),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Voice Parameters
                  _SectionHeader(title: 'Voice Management'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _IntField(
                          label: 'Polyphony',
                          value: _polyphony,
                          min: 1,
                          max: 32,
                          onChanged: (v) => setState(() => _polyphony = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _IntField(
                          label: 'Priority',
                          value: _priority,
                          min: 0,
                          max: 100,
                          onChanged: (v) => setState(() => _priority = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DropdownField<VoiceStealPolicy>(
                          label: 'Voice Steal',
                          value: _voiceStealPolicy,
                          items: VoiceStealPolicy.values,
                          itemLabel: (v) => v.displayName,
                          onChanged: (v) => setState(() => _voiceStealPolicy = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DropdownField<PreloadPolicy>(
                          label: 'Preload',
                          value: _preloadPolicy,
                          items: PreloadPolicy.values,
                          itemLabel: (v) => v.displayName,
                          onChanged: (v) => setState(() => _preloadPolicy = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _TextField(
                    label: 'Voice Limit Group',
                    controller: TextEditingController(text: _voiceLimitGroup),
                    hint: 'default',
                    onChanged: (v) => _voiceLimitGroup = v,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// HEADER
// =============================================================================

class _Header extends StatelessWidget {
  final bool isEditing;
  final VoidCallback? onClose;
  final VoidCallback onSave;

  const _Header({
    required this.isEditing,
    this.onClose,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.tune,
          size: 18,
          color: FluxForgeTheme.accentOrange,
        ),
        const SizedBox(width: 8),
        Text(
          isEditing ? 'Edit Preset' : 'New Preset',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (onClose != null)
          IconButton(
            icon: Icon(Icons.close, size: 18, color: FluxForgeTheme.textMuted),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SECTION HEADER
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// FORM FIELDS
// =============================================================================

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _TextField({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SliderField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String? suffix;
  final int decimals;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.suffix,
    this.decimals = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${value.toStringAsFixed(decimals)}${suffix ?? ''}',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: FluxForgeTheme.accentBlue,
            inactiveTrackColor: FluxForgeTheme.bgMid,
            thumbColor: FluxForgeTheme.accentBlue,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _IntField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String? suffix;
  final ValueChanged<int> onChanged;

  const _IntField({
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 10000,
    this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            children: [
              // Decrement
              InkWell(
                onTap: value > min ? () => onChanged(value - 1) : null,
                child: Container(
                  width: 28,
                  height: 32,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.remove,
                    size: 14,
                    color: value > min ? FluxForgeTheme.textSecondary : FluxForgeTheme.textMuted.withValues(alpha: 0.3),
                  ),
                ),
              ),

              // Value
              Expanded(
                child: Center(
                  child: Text(
                    '$value${suffix ?? ''}',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),

              // Increment
              InkWell(
                onTap: value < max ? () => onChanged(value + 1) : null,
                child: Container(
                  width: 28,
                  height: 32,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    size: 14,
                    color: value < max ? FluxForgeTheme.textSecondary : FluxForgeTheme.textMuted.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: FluxForgeTheme.bgMid,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 12,
              ),
              icon: Icon(Icons.expand_more, size: 16, color: FluxForgeTheme.textMuted),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(itemLabel(item)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
