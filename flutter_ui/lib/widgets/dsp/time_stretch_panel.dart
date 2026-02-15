/// RF-Elastic Pro Time Stretch Panel
///
/// Professional time-stretching and pitch-shifting controls
/// with STN decomposition visualization.

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Quality preset enum
enum StretchQuality {
  preview,   // 0
  standard,  // 1
  high,      // 2
  ultra,     // 3
}

/// Algorithm mode enum
enum StretchMode {
  auto,       // 0
  polyphonic, // 1
  monophonic, // 2
  rhythmic,   // 3
  speech,     // 4
  creative,   // 5
}

/// Time Stretch Panel Widget
class TimeStretchPanel extends StatefulWidget {
  /// Clip ID to process
  final int clipId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const TimeStretchPanel({
    super.key,
    required this.clipId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<TimeStretchPanel> createState() => _TimeStretchPanelState();
}

class _TimeStretchPanelState extends State<TimeStretchPanel> {
  // Stretch parameters
  double _stretchRatio = 1.0;
  double _pitchShift = 0.0;
  StretchQuality _quality = StretchQuality.standard;
  StretchMode _mode = StretchMode.auto;

  // Advanced options
  bool _useStn = true;
  bool _preserveTransients = true;
  bool _preserveFormants = false;
  double _tonalThreshold = 0.5;
  double _transientThreshold = 0.5;

  // State
  bool _initialized = false;
  bool _showAdvanced = false;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    NativeFFI.instance.elasticRemove(widget.clipId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = NativeFFI.instance.elasticCreate(widget.clipId, widget.sampleRate);
    if (success) {
      setState(() => _initialized = true);
      _applyAllSettings();
    }
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    NativeFFI.instance.elasticSetRatio(widget.clipId, _stretchRatio);
    NativeFFI.instance.elasticSetPitch(widget.clipId, _pitchShift);
    NativeFFI.instance.elasticSetQuality(widget.clipId, _quality.index);
    NativeFFI.instance.elasticSetMode(widget.clipId, _mode.index);
    NativeFFI.instance.elasticSetStnEnabled(widget.clipId, _useStn);
    NativeFFI.instance.elasticSetPreserveTransients(widget.clipId, _preserveTransients);
    NativeFFI.instance.elasticSetPreserveFormants(widget.clipId, _preserveFormants);
    NativeFFI.instance.elasticSetTonalThreshold(widget.clipId, _tonalThreshold);
    NativeFFI.instance.elasticSetTransientThreshold(widget.clipId, _transientThreshold);

    widget.onSettingsChanged?.call();
  }

  void _applyStretch() {
    if (!_initialized || _processing) return;

    setState(() => _processing = true);

    // Ensure all params are synced before processing
    _applyAllSettings();

    // Apply stretch to clip audio in engine
    final success = NativeFFI.instance.elasticApplyToClip(widget.clipId);

    setState(() => _processing = false);

    if (success) {
      widget.onSettingsChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),

          // Main controls
          _buildMainControls(),
          const SizedBox(height: 16),

          // Mode and Quality
          _buildModeQualityRow(),
          const SizedBox(height: 16),

          // Advanced options toggle
          _buildAdvancedToggle(),

          // Advanced options (collapsible)
          if (_showAdvanced) ...[
            const SizedBox(height: 16),
            _buildAdvancedOptions(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.speed, color: FluxForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'RF-Elastic Pro',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        // Apply button
        GestureDetector(
          onTap: _applyStretch,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _processing
                  ? Colors.orange.withOpacity(0.3)
                  : FluxForgeTheme.accentBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _processing
                    ? Colors.orange.withOpacity(0.5)
                    : FluxForgeTheme.accentBlue.withOpacity(0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_processing)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orange),
                  )
                else
                  Icon(Icons.check, size: 12, color: FluxForgeTheme.accentBlue),
                const SizedBox(width: 4),
                Text(
                  _processing ? 'Processing...' : 'Apply',
                  style: TextStyle(
                    color: _processing ? Colors.orange : FluxForgeTheme.accentBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Status indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _initialized ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _initialized ? 'Ready' : 'Init...',
            style: TextStyle(
              color: _initialized ? Colors.green : Colors.red,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainControls() {
    return Column(
      children: [
        // Stretch Ratio
        _buildParameterRow(
          label: 'Time Stretch',
          value: '${(_stretchRatio * 100).toStringAsFixed(0)}%',
          child: SliderTheme(
            data: _sliderTheme,
            child: Slider(
              value: _stretchRatio,
              min: 0.25,
              max: 4.0,
              onChanged: (v) {
                setState(() => _stretchRatio = v);
                NativeFFI.instance.elasticSetRatio(widget.clipId, v);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Pitch Shift
        _buildParameterRow(
          label: 'Pitch Shift',
          value: '${_pitchShift >= 0 ? '+' : ''}${_pitchShift.toStringAsFixed(1)} st',
          child: SliderTheme(
            data: _sliderTheme,
            child: Slider(
              value: _pitchShift,
              min: -12.0,
              max: 12.0,
              onChanged: (v) {
                setState(() => _pitchShift = v);
                NativeFFI.instance.elasticSetPitch(widget.clipId, v);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
        ),

        // Quick presets
        const SizedBox(height: 8),
        _buildQuickPresets(),
      ],
    );
  }

  Widget _buildParameterRow({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 60,
          child: Text(
            value,
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickPresets() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildPresetButton('50%', 0.5, 0),
        _buildPresetButton('75%', 0.75, 0),
        _buildPresetButton('100%', 1.0, 0),
        _buildPresetButton('150%', 1.5, 0),
        _buildPresetButton('200%', 2.0, 0),
        _buildPresetButton('+12st', 1.0, 12),
        _buildPresetButton('-12st', 1.0, -12),
      ],
    );
  }

  Widget _buildPresetButton(String label, double ratio, double pitch) {
    final isActive = (_stretchRatio - ratio).abs() < 0.01 && (_pitchShift - pitch).abs() < 0.01;

    return GestureDetector(
      onTap: () {
        setState(() {
          _stretchRatio = ratio;
          _pitchShift = pitch;
        });
        NativeFFI.instance.elasticSetRatio(widget.clipId, ratio);
        NativeFFI.instance.elasticSetPitch(widget.clipId, pitch);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? FluxForgeTheme.accentBlue.withOpacity(0.3) : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildModeQualityRow() {
    return Row(
      children: [
        // Mode dropdown
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mode', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FluxForgeTheme.border),
                ),
                child: DropdownButton<StretchMode>(
                  value: _mode,
                  isExpanded: true,
                  dropdownColor: FluxForgeTheme.surfaceDark,
                  underline: const SizedBox(),
                  style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                  items: StretchMode.values.map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(_getModeLabel(m)),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _mode = v);
                      NativeFFI.instance.elasticSetMode(widget.clipId, v.index);
                      widget.onSettingsChanged?.call();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Quality dropdown
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quality', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FluxForgeTheme.border),
                ),
                child: DropdownButton<StretchQuality>(
                  value: _quality,
                  isExpanded: true,
                  dropdownColor: FluxForgeTheme.surfaceDark,
                  underline: const SizedBox(),
                  style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                  items: StretchQuality.values.map((q) => DropdownMenuItem(
                    value: q,
                    child: Text(_getQualityLabel(q)),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _quality = v);
                      NativeFFI.instance.elasticSetQuality(widget.clipId, v.index);
                      widget.onSettingsChanged?.call();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
      child: Row(
        children: [
          Icon(
            _showAdvanced ? Icons.expand_less : Icons.expand_more,
            color: FluxForgeTheme.textSecondary,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            'Advanced Options',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedOptions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Toggles row
          Row(
            children: [
              _buildToggle('STN', _useStn, (v) {
                setState(() => _useStn = v);
                NativeFFI.instance.elasticSetStnEnabled(widget.clipId, v);
                widget.onSettingsChanged?.call();
              }),
              const SizedBox(width: 16),
              _buildToggle('Transients', _preserveTransients, (v) {
                setState(() => _preserveTransients = v);
                NativeFFI.instance.elasticSetPreserveTransients(widget.clipId, v);
                widget.onSettingsChanged?.call();
              }),
              const SizedBox(width: 16),
              _buildToggle('Formants', _preserveFormants, (v) {
                setState(() => _preserveFormants = v);
                NativeFFI.instance.elasticSetPreserveFormants(widget.clipId, v);
                widget.onSettingsChanged?.call();
              }),
            ],
          ),
          const SizedBox(height: 12),

          // Threshold sliders
          _buildParameterRow(
            label: 'Tonal',
            value: '${(_tonalThreshold * 100).toStringAsFixed(0)}%',
            child: SliderTheme(
              data: _sliderTheme,
              child: Slider(
                value: _tonalThreshold,
                min: 0.0,
                max: 1.0,
                onChanged: (v) {
                  setState(() => _tonalThreshold = v);
                  NativeFFI.instance.elasticSetTonalThreshold(widget.clipId, v);
                  widget.onSettingsChanged?.call();
                },
              ),
            ),
          ),
          _buildParameterRow(
            label: 'Transient',
            value: '${(_transientThreshold * 100).toStringAsFixed(0)}%',
            child: SliderTheme(
              data: _sliderTheme,
              child: Slider(
                value: _transientThreshold,
                min: 0.0,
                max: 1.0,
                onChanged: (v) {
                  setState(() => _transientThreshold = v);
                  NativeFFI.instance.elasticSetTransientThreshold(widget.clipId, v);
                  widget.onSettingsChanged?.call();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: FluxForgeTheme.accentBlue,
            side: BorderSide(color: FluxForgeTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  String _getModeLabel(StretchMode mode) {
    switch (mode) {
      case StretchMode.auto: return 'Auto';
      case StretchMode.polyphonic: return 'Polyphonic';
      case StretchMode.monophonic: return 'Monophonic';
      case StretchMode.rhythmic: return 'Rhythmic';
      case StretchMode.speech: return 'Speech';
      case StretchMode.creative: return 'Creative';
    }
  }

  String _getQualityLabel(StretchQuality quality) {
    switch (quality) {
      case StretchQuality.preview: return 'Preview';
      case StretchQuality.standard: return 'Standard';
      case StretchQuality.high: return 'High';
      case StretchQuality.ultra: return 'Ultra';
    }
  }

  SliderThemeData get _sliderTheme => SliderThemeData(
    trackHeight: 4,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
    activeTrackColor: FluxForgeTheme.accentBlue,
    inactiveTrackColor: FluxForgeTheme.surface,
    thumbColor: FluxForgeTheme.accentBlue,
    overlayColor: FluxForgeTheme.accentBlue.withOpacity(0.2),
  );
}
