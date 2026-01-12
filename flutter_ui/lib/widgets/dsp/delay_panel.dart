/// FluxForge Studio Professional Delay Panel
///
/// Multi-mode delay with Simple, Ping-Pong, Multi-Tap, and Modulated (Chorus/Flanger)
/// processing options with tempo sync support.

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Professional Delay Panel Widget
class DelayPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Project BPM for tempo sync
  final double bpm;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const DelayPanel({
    super.key,
    required this.trackId,
    this.bpm = 120.0,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<DelayPanel> createState() => _DelayPanelState();
}

class _DelayPanelState extends State<DelayPanel> {
  // Mode selection
  DelayType _delayType = DelayType.simple;

  // Common parameters
  double _delayTimeMs = 500.0;
  double _feedback = 0.5;
  double _dryWet = 0.5;
  bool _tempoSync = false;
  int _syncDivision = 2; // 0=1/1, 1=1/2, 2=1/4, 3=1/8, 4=1/16

  // Simple delay specific
  double _highpassFreq = 80.0;
  double _lowpassFreq = 8000.0;
  bool _filterEnabled = true;

  // Ping-pong specific
  double _pingPongAmount = 1.0;

  // Multi-tap specific
  int _numTaps = 4;
  List<TapSettings> _taps = [];

  // Modulated delay specific
  ModulatedDelayPreset _modPreset = ModulatedDelayPreset.chorus;
  double _modDepthMs = 3.0;
  double _modRateHz = 0.8;

  // State
  bool _initialized = false;
  bool _bypassed = false;

  @override
  void initState() {
    super.initState();
    _initializeTaps();
    _initializeProcessor();
  }

  void _initializeTaps() {
    _taps = List.generate(8, (i) => TapSettings(
      delayMs: (i + 1) * 125.0,
      level: 1.0 / (i + 1),
      pan: i.isEven ? -0.3 : 0.3,
    ));
  }

  @override
  void dispose() {
    _removeCurrentDelay();
    super.dispose();
  }

  void _removeCurrentDelay() {
    NativeFFI.instance.simpleDelayRemove(widget.trackId);
    NativeFFI.instance.pingPongDelayRemove(widget.trackId);
    NativeFFI.instance.multiTapDelayRemove(widget.trackId);
    NativeFFI.instance.modulatedDelayRemove(widget.trackId);
  }

  void _initializeProcessor() {
    _removeCurrentDelay();

    bool success = false;
    switch (_delayType) {
      case DelayType.simple:
        success = NativeFFI.instance.simpleDelayCreate(widget.trackId, sampleRate: widget.sampleRate);
        break;
      case DelayType.pingPong:
        success = NativeFFI.instance.pingPongDelayCreate(widget.trackId, sampleRate: widget.sampleRate);
        break;
      case DelayType.multiTap:
        success = NativeFFI.instance.multiTapDelayCreate(widget.trackId, sampleRate: widget.sampleRate, numTaps: _numTaps);
        break;
      case DelayType.modulated:
        success = NativeFFI.instance.modulatedDelayCreate(widget.trackId, sampleRate: widget.sampleRate, preset: _modPreset);
        break;
    }

    if (success) {
      setState(() => _initialized = true);
      _applyAllSettings();
    }
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    final time = _tempoSync ? _getTempoSyncTime() : _delayTimeMs;

    switch (_delayType) {
      case DelayType.simple:
        NativeFFI.instance.simpleDelaySetTime(widget.trackId, time);
        NativeFFI.instance.simpleDelaySetFeedback(widget.trackId, _feedback);
        NativeFFI.instance.simpleDelaySetDryWet(widget.trackId, _dryWet);
        NativeFFI.instance.simpleDelaySetHighpass(widget.trackId, _highpassFreq);
        NativeFFI.instance.simpleDelaySetLowpass(widget.trackId, _lowpassFreq);
        NativeFFI.instance.simpleDelaySetFilterEnabled(widget.trackId, _filterEnabled);
        break;
      case DelayType.pingPong:
        NativeFFI.instance.pingPongDelaySetTime(widget.trackId, time);
        NativeFFI.instance.pingPongDelaySetFeedback(widget.trackId, _feedback);
        NativeFFI.instance.pingPongDelaySetDryWet(widget.trackId, _dryWet);
        NativeFFI.instance.pingPongDelaySetPingPong(widget.trackId, _pingPongAmount);
        break;
      case DelayType.multiTap:
        for (int i = 0; i < _taps.length && i < _numTaps; i++) {
          NativeFFI.instance.multiTapDelaySetTap(
            widget.trackId,
            i,
            _taps[i].delayMs,
            _taps[i].level,
            _taps[i].pan,
          );
        }
        NativeFFI.instance.multiTapDelaySetFeedback(widget.trackId, _feedback);
        NativeFFI.instance.multiTapDelaySetDryWet(widget.trackId, _dryWet);
        break;
      case DelayType.modulated:
        NativeFFI.instance.modulatedDelaySetTime(widget.trackId, time);
        NativeFFI.instance.modulatedDelaySetModDepth(widget.trackId, _modDepthMs);
        NativeFFI.instance.modulatedDelaySetModRate(widget.trackId, _modRateHz);
        NativeFFI.instance.modulatedDelaySetFeedback(widget.trackId, _feedback);
        NativeFFI.instance.modulatedDelaySetDryWet(widget.trackId, _dryWet);
        break;
    }

    widget.onSettingsChanged?.call();
  }

  double _getTempoSyncTime() {
    final beatDuration = 60000.0 / widget.bpm; // ms per beat
    final multipliers = [4.0, 2.0, 1.0, 0.5, 0.25]; // 1/1, 1/2, 1/4, 1/8, 1/16
    return beatDuration * multipliers[_syncDivision];
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
          _buildHeader(),
          const SizedBox(height: 16),
          _buildTypeSelector(),
          const SizedBox(height: 16),
          _buildCommonControls(),
          const SizedBox(height: 16),
          _buildTypeSpecificControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.timer, color: FluxForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Delay',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        // Bypass
        _buildBypassButton(),
        const SizedBox(width: 8),
        _buildStatusIndicator(),
      ],
    );
  }

  Widget _buildBypassButton() {
    return GestureDetector(
      onTap: () => setState(() => _bypassed = !_bypassed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _bypassed ? Colors.orange.withOpacity(0.3) : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _bypassed ? Colors.orange : FluxForgeTheme.border),
        ),
        child: Text(
          'BYPASS',
          style: TextStyle(
            color: _bypassed ? Colors.orange : FluxForgeTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
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
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: DelayType.values.map((type) => Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() => _delayType = type);
            _initializeProcessor();
          },
          child: Container(
            margin: EdgeInsets.only(right: type != DelayType.modulated ? 4 : 0),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: _delayType == type
                  ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _delayType == type ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
              ),
            ),
            child: Text(
              _getTypeName(type),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _delayType == type ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontWeight: _delayType == type ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      )).toList(),
    );
  }

  String _getTypeName(DelayType type) {
    switch (type) {
      case DelayType.simple: return 'Simple';
      case DelayType.pingPong: return 'Ping-Pong';
      case DelayType.multiTap: return 'Multi-Tap';
      case DelayType.modulated: return 'Modulated';
    }
  }

  Widget _buildCommonControls() {
    return Column(
      children: [
        // Tempo sync row
        if (_delayType != DelayType.multiTap) ...[
          _buildTempoSyncRow(),
          const SizedBox(height: 12),
        ],

        // Delay time
        if (_delayType != DelayType.multiTap)
          _buildParameterRow(
            label: 'Time',
            value: _tempoSync
                ? _getSyncDivisionName()
                : '${_delayTimeMs.toStringAsFixed(0)} ms',
            child: _tempoSync
                ? _buildSyncDivisionSlider()
                : _buildSlider(
                    value: _delayTimeMs / 2000.0,
                    onChanged: (v) {
                      setState(() => _delayTimeMs = v * 2000.0);
                      _applyAllSettings();
                    },
                  ),
          ),
        if (_delayType != DelayType.multiTap) const SizedBox(height: 8),

        // Feedback
        _buildParameterRow(
          label: 'Feedback',
          value: '${(_feedback * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _feedback / 0.99,
            onChanged: (v) {
              setState(() => _feedback = v * 0.99);
              _applyAllSettings();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Dry/Wet
        _buildParameterRow(
          label: 'Dry/Wet',
          value: '${(_dryWet * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _dryWet,
            onChanged: (v) {
              setState(() => _dryWet = v);
              _applyAllSettings();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTempoSyncRow() {
    return Row(
      children: [
        Text(
          'Tempo Sync',
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            setState(() => _tempoSync = !_tempoSync);
            _applyAllSettings();
          },
          child: Container(
            width: 40,
            height: 22,
            decoration: BoxDecoration(
              color: _tempoSync ? FluxForgeTheme.accentBlue : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _tempoSync ? FluxForgeTheme.accentBlue : FluxForgeTheme.border),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: _tempoSync ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: _tempoSync ? Colors.white : FluxForgeTheme.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        if (_tempoSync) ...[
          const SizedBox(width: 12),
          Text(
            '${widget.bpm.toStringAsFixed(0)} BPM',
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSyncDivisionSlider() {
    return SliderTheme(
      data: _sliderTheme,
      child: Slider(
        value: _syncDivision.toDouble(),
        min: 0,
        max: 4,
        divisions: 4,
        onChanged: (v) {
          setState(() => _syncDivision = v.round());
          _applyAllSettings();
        },
      ),
    );
  }

  String _getSyncDivisionName() {
    const names = ['1/1', '1/2', '1/4', '1/8', '1/16'];
    return names[_syncDivision];
  }

  Widget _buildTypeSpecificControls() {
    switch (_delayType) {
      case DelayType.simple:
        return _buildSimpleControls();
      case DelayType.pingPong:
        return _buildPingPongControls();
      case DelayType.multiTap:
        return _buildMultiTapControls();
      case DelayType.modulated:
        return _buildModulatedControls();
    }
  }

  Widget _buildSimpleControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filter', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() => _filterEnabled = !_filterEnabled);
                  _applyAllSettings();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _filterEnabled ? FluxForgeTheme.accentBlue.withOpacity(0.2) : FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _filterEnabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.border),
                  ),
                  child: Text(
                    _filterEnabled ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: _filterEnabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildParameterRow(
            label: 'HP',
            value: '${_highpassFreq.toStringAsFixed(0)} Hz',
            child: _buildSlider(
              value: _highpassFreq / 500.0,
              onChanged: (v) {
                setState(() => _highpassFreq = v * 500.0);
                _applyAllSettings();
              },
            ),
          ),
          const SizedBox(height: 8),
          _buildParameterRow(
            label: 'LP',
            value: '${(_lowpassFreq / 1000).toStringAsFixed(1)} kHz',
            child: _buildSlider(
              value: _lowpassFreq / 20000.0,
              onChanged: (v) {
                setState(() => _lowpassFreq = v * 20000.0);
                _applyAllSettings();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPingPongControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: _buildParameterRow(
        label: 'Ping-Pong',
        value: '${(_pingPongAmount * 100).toStringAsFixed(0)}%',
        child: _buildSlider(
          value: _pingPongAmount,
          onChanged: (v) {
            setState(() => _pingPongAmount = v);
            _applyAllSettings();
          },
        ),
      ),
    );
  }

  Widget _buildMultiTapControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tap Configuration', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
          const SizedBox(height: 12),
          ...List.generate(_numTaps.clamp(1, 4), (i) => Padding(
            padding: EdgeInsets.only(bottom: i < _numTaps - 1 ? 8 : 0),
            child: _buildTapRow(i),
          )),
        ],
      ),
    );
  }

  Widget _buildTapRow(int index) {
    final tap = _taps[index];
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            '${index + 1}',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
        ),
        Expanded(
          flex: 2,
          child: _buildMiniSlider(
            value: tap.delayMs / 2000.0,
            onChanged: (v) {
              setState(() => _taps[index] = tap.copyWith(delayMs: v * 2000.0));
              _applyAllSettings();
            },
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            '${tap.delayMs.toStringAsFixed(0)}ms',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildModulatedControls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Preset selector
          Row(
            children: [
              Text('Preset', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
              const Spacer(),
              ...ModulatedDelayPreset.values.map((preset) => Padding(
                padding: EdgeInsets.only(left: preset != ModulatedDelayPreset.custom ? 8 : 0),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _modPreset = preset);
                    _initializeProcessor();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _modPreset == preset
                          ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                          : FluxForgeTheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _modPreset == preset ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
                      ),
                    ),
                    child: Text(
                      _getPresetName(preset),
                      style: TextStyle(
                        color: _modPreset == preset ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              )),
            ],
          ),
          const SizedBox(height: 12),

          // Mod depth
          _buildParameterRow(
            label: 'Depth',
            value: '${_modDepthMs.toStringAsFixed(1)} ms',
            child: _buildSlider(
              value: _modDepthMs / 10.0,
              onChanged: (v) {
                setState(() => _modDepthMs = v * 10.0);
                _applyAllSettings();
              },
            ),
          ),
          const SizedBox(height: 8),

          // Mod rate
          _buildParameterRow(
            label: 'Rate',
            value: '${_modRateHz.toStringAsFixed(2)} Hz',
            child: _buildSlider(
              value: _modRateHz / 10.0,
              onChanged: (v) {
                setState(() => _modRateHz = v * 10.0);
                _applyAllSettings();
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getPresetName(ModulatedDelayPreset preset) {
    switch (preset) {
      case ModulatedDelayPreset.custom: return 'Custom';
      case ModulatedDelayPreset.chorus: return 'Chorus';
      case ModulatedDelayPreset.flanger: return 'Flanger';
    }
  }

  Widget _buildParameterRow({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 70,
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

  Widget _buildSlider({
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return SliderTheme(
      data: _sliderTheme,
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildMiniSlider({
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
        activeTrackColor: FluxForgeTheme.accentBlue,
        inactiveTrackColor: FluxForgeTheme.surface,
        thumbColor: FluxForgeTheme.accentBlue,
        overlayColor: FluxForgeTheme.accentBlue.withOpacity(0.2),
      ),
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChanged: onChanged,
      ),
    );
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

/// Settings for a single tap in multi-tap delay
class TapSettings {
  final double delayMs;
  final double level;
  final double pan;

  const TapSettings({
    required this.delayMs,
    required this.level,
    required this.pan,
  });

  TapSettings copyWith({
    double? delayMs,
    double? level,
    double? pan,
  }) {
    return TapSettings(
      delayMs: delayMs ?? this.delayMs,
      level: level ?? this.level,
      pan: pan ?? this.pan,
    );
  }
}
