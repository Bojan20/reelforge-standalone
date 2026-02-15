/// Channel Strip Panel
///
/// Complete console channel strip with:
/// - HPF (High Pass Filter)
/// - Gate
/// - Compressor
/// - 4-band Console EQ
/// - Limiter
/// - Pan/Width
/// - I/O Metering

import 'dart:async';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Channel Strip Panel Widget
class ChannelStripPanel extends StatefulWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const ChannelStripPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  State<ChannelStripPanel> createState() => _ChannelStripPanelState();
}

class _ChannelStripPanelState extends State<ChannelStripPanel> {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  // Input/Output
  double _inputGain = 0.0;
  double _outputGain = 0.0;

  // HPF
  bool _hpfEnabled = false;
  double _hpfFreq = 80.0;
  int _hpfSlope = 12;

  // Gate
  bool _gateEnabled = false;
  double _gateThreshold = -40.0;
  double _gateRatio = 10.0;
  double _gateAttack = 0.5;
  double _gateRelease = 100.0;
  double _gateRange = -80.0;

  // Compressor
  bool _compEnabled = false;
  double _compThreshold = -20.0;
  double _compRatio = 4.0;
  double _compAttack = 10.0;
  double _compRelease = 100.0;
  double _compKnee = 6.0;
  double _compMakeup = 0.0;

  // EQ
  bool _eqEnabled = true;
  double _eqLowFreq = 100.0;
  double _eqLowGain = 0.0;
  double _eqLowMidFreq = 500.0;
  double _eqLowMidGain = 0.0;
  double _eqLowMidQ = 1.0;
  double _eqHighMidFreq = 2500.0;
  double _eqHighMidGain = 0.0;
  double _eqHighMidQ = 1.0;
  double _eqHighFreq = 8000.0;
  double _eqHighGain = 0.0;

  // Limiter
  bool _limiterEnabled = false;
  double _limiterThreshold = -1.0;
  double _limiterRelease = 50.0;

  // Pan/Width
  double _pan = 0.0;
  double _width = 1.0;

  // Processing order
  ChannelStripProcessingOrder _processingOrder = ChannelStripProcessingOrder.gateCompEq;

  // Metering
  double _inputLevel = -60.0;
  double _outputLevel = -60.0;
  double _gateGr = 0.0;
  double _compGr = 0.0;
  double _limiterGr = 0.0;

  Timer? _meterTimer;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _ffi.channelStripRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    // Do NOT auto-create channel strip — must be created externally
  }

  void _startMetering() {
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _initialized) {
        setState(() {
          _inputLevel = _ffi.channelStripGetInputLevel(widget.trackId);
          _outputLevel = _ffi.channelStripGetOutputLevel(widget.trackId);
          _gateGr = _ffi.channelStripGetGateGr(widget.trackId);
          _compGr = _ffi.channelStripGetCompGr(widget.trackId);
          _limiterGr = _ffi.channelStripGetLimiterGr(widget.trackId);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A30)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildInputSection(),
                  const SizedBox(height: 12),
                  _buildHpfSection(),
                  const SizedBox(height: 12),
                  _buildGateSection(),
                  const SizedBox(height: 12),
                  _buildCompressorSection(),
                  const SizedBox(height: 12),
                  _buildEqSection(),
                  const SizedBox(height: 12),
                  _buildLimiterSection(),
                  const SizedBox(height: 12),
                  _buildOutputSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.tune, color: Color(0xFF40C8FF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'CHANNEL STRIP',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          _buildProcessingOrderDropdown(),
        ],
      ),
    );
  }

  Widget _buildProcessingOrderDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderMedium),
      ),
      child: DropdownButton<ChannelStripProcessingOrder>(
        value: _processingOrder,
        dropdownColor: FluxForgeTheme.bgMid,
        style: const TextStyle(color: Color(0xFF808090), fontSize: 10),
        underline: const SizedBox(),
        isDense: true,
        items: const [
          DropdownMenuItem(value: ChannelStripProcessingOrder.gateCompEq, child: Text('G→C→E')),
          DropdownMenuItem(value: ChannelStripProcessingOrder.gateEqComp, child: Text('G→E→C')),
          DropdownMenuItem(value: ChannelStripProcessingOrder.eqGateComp, child: Text('E→G→C')),
          DropdownMenuItem(value: ChannelStripProcessingOrder.eqCompGate, child: Text('E→C→G')),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() => _processingOrder = value);
            _ffi.channelStripSetProcessingOrder(widget.trackId, value);
            widget.onSettingsChanged?.call();
          }
        },
      ),
    );
  }

  Widget _buildInputSection() {
    return _buildSection(
      'INPUT',
      FluxForgeTheme.accentCyan,
      true,
      null,
      Column(
        children: [
          _buildSliderRow('Gain', _inputGain, -24, 24, 'dB', (v) {
            setState(() => _inputGain = v);
            _ffi.channelStripSetInputGain(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 8),
          _buildMeterBar('Level', _inputLevel, FluxForgeTheme.accentCyan),
        ],
      ),
    );
  }

  Widget _buildHpfSection() {
    return _buildSection(
      'HIGH PASS',
      FluxForgeTheme.accentOrange,
      _hpfEnabled,
      (v) {
        setState(() => _hpfEnabled = v);
        _ffi.channelStripSetHpfEnabled(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      Column(
        children: [
          _buildSliderRow('Freq', _hpfFreq, 20, 500, 'Hz', (v) {
            setState(() => _hpfFreq = v);
            _ffi.channelStripSetHpfFreq(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Slope:', style: TextStyle(color: Color(0xFF606070), fontSize: 10)),
              const SizedBox(width: 8),
              for (final slope in [12, 24, 48])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _buildSlopeButton(slope),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlopeButton(int slope) {
    final isSelected = _hpfSlope == slope;
    return GestureDetector(
      onTap: () {
        setState(() => _hpfSlope = slope);
        _ffi.channelStripSetHpfSlope(widget.trackId, slope);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.accentOrange : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? FluxForgeTheme.accentOrange : FluxForgeTheme.borderMedium),
        ),
        child: Text(
          '$slope',
          style: TextStyle(
            color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildGateSection() {
    return _buildSection(
      'GATE',
      FluxForgeTheme.accentGreen,
      _gateEnabled,
      (v) {
        setState(() => _gateEnabled = v);
        _ffi.channelStripSetGateEnabled(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      Column(
        children: [
          _buildSliderRow('Thresh', _gateThreshold, -80, 0, 'dB', (v) {
            setState(() => _gateThreshold = v);
            _ffi.channelStripSetGateThreshold(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Ratio', _gateRatio, 1, 100, ':1', (v) {
            setState(() => _gateRatio = v);
            _ffi.channelStripSetGateRatio(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Attack', _gateAttack, 0.01, 100, 'ms', (v) {
            setState(() => _gateAttack = v);
            _ffi.channelStripSetGateAttack(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Release', _gateRelease, 1, 2000, 'ms', (v) {
            setState(() => _gateRelease = v);
            _ffi.channelStripSetGateRelease(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Range', _gateRange, -80, 0, 'dB', (v) {
            setState(() => _gateRange = v);
            _ffi.channelStripSetGateRange(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 8),
          _buildGrMeter('GR', _gateGr, FluxForgeTheme.accentGreen),
        ],
      ),
    );
  }

  Widget _buildCompressorSection() {
    return _buildSection(
      'COMPRESSOR',
      FluxForgeTheme.accentYellow,
      _compEnabled,
      (v) {
        setState(() => _compEnabled = v);
        _ffi.channelStripSetCompEnabled(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      Column(
        children: [
          _buildSliderRow('Thresh', _compThreshold, -60, 0, 'dB', (v) {
            setState(() => _compThreshold = v);
            _ffi.channelStripSetCompThreshold(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Ratio', _compRatio, 1, 100, ':1', (v) {
            setState(() => _compRatio = v);
            _ffi.channelStripSetCompRatio(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Attack', _compAttack, 0.01, 500, 'ms', (v) {
            setState(() => _compAttack = v);
            _ffi.channelStripSetCompAttack(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Release', _compRelease, 1, 5000, 'ms', (v) {
            setState(() => _compRelease = v);
            _ffi.channelStripSetCompRelease(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Knee', _compKnee, 0, 30, 'dB', (v) {
            setState(() => _compKnee = v);
            _ffi.channelStripSetCompKnee(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Makeup', _compMakeup, 0, 30, 'dB', (v) {
            setState(() => _compMakeup = v);
            _ffi.channelStripSetCompMakeup(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 8),
          _buildGrMeter('GR', _compGr, FluxForgeTheme.accentYellow),
        ],
      ),
    );
  }

  Widget _buildEqSection() {
    return _buildSection(
      'CONSOLE EQ',
      FluxForgeTheme.accentCyan,
      _eqEnabled,
      (v) {
        setState(() => _eqEnabled = v);
        _ffi.channelStripSetEqEnabled(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      Column(
        children: [
          _buildEqBand('LOW', _eqLowFreq, _eqLowGain, null, 20, 500, (f, g, q) {
            setState(() {
              _eqLowFreq = f;
              _eqLowGain = g;
            });
            _ffi.channelStripSetEqLowFreq(widget.trackId, f);
            _ffi.channelStripSetEqLowGain(widget.trackId, g);
            widget.onSettingsChanged?.call();
          }),
          _buildEqBand('LOW MID', _eqLowMidFreq, _eqLowMidGain, _eqLowMidQ, 100, 2000, (f, g, q) {
            setState(() {
              _eqLowMidFreq = f;
              _eqLowMidGain = g;
              _eqLowMidQ = q ?? 1.0;
            });
            _ffi.channelStripSetEqLowMidFreq(widget.trackId, f);
            _ffi.channelStripSetEqLowMidGain(widget.trackId, g);
            if (q != null) _ffi.channelStripSetEqLowMidQ(widget.trackId, q);
            widget.onSettingsChanged?.call();
          }),
          _buildEqBand('HIGH MID', _eqHighMidFreq, _eqHighMidGain, _eqHighMidQ, 500, 8000, (f, g, q) {
            setState(() {
              _eqHighMidFreq = f;
              _eqHighMidGain = g;
              _eqHighMidQ = q ?? 1.0;
            });
            _ffi.channelStripSetEqHighMidFreq(widget.trackId, f);
            _ffi.channelStripSetEqHighMidGain(widget.trackId, g);
            if (q != null) _ffi.channelStripSetEqHighMidQ(widget.trackId, q);
            widget.onSettingsChanged?.call();
          }),
          _buildEqBand('HIGH', _eqHighFreq, _eqHighGain, null, 2000, 20000, (f, g, q) {
            setState(() {
              _eqHighFreq = f;
              _eqHighGain = g;
            });
            _ffi.channelStripSetEqHighFreq(widget.trackId, f);
            _ffi.channelStripSetEqHighGain(widget.trackId, g);
            widget.onSettingsChanged?.call();
          }),
        ],
      ),
    );
  }

  Widget _buildEqBand(String label, double freq, double gain, double? q, double minFreq, double maxFreq, void Function(double, double, double?) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${freq.toInt()} Hz', style: const TextStyle(color: Color(0xFF40C8FF), fontSize: 10)),
                    Slider(
                      value: freq,
                      min: minFreq,
                      max: maxFreq,
                      activeColor: FluxForgeTheme.accentCyan,
                      inactiveColor: FluxForgeTheme.borderSubtle,
                      onChanged: (v) => onChanged(v, gain, q),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB', style: const TextStyle(color: Color(0xFFFF9040), fontSize: 10)),
                    Slider(
                      value: gain,
                      min: -18,
                      max: 18,
                      activeColor: FluxForgeTheme.accentOrange,
                      inactiveColor: FluxForgeTheme.borderSubtle,
                      onChanged: (v) => onChanged(freq, v, q),
                    ),
                  ],
                ),
              ),
              if (q != null)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Q ${q.toStringAsFixed(1)}', style: const TextStyle(color: Color(0xFF40FF90), fontSize: 10)),
                      Slider(
                        value: q,
                        min: 0.1,
                        max: 18,
                        activeColor: FluxForgeTheme.accentGreen,
                        inactiveColor: FluxForgeTheme.borderSubtle,
                        onChanged: (v) => onChanged(freq, gain, v),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLimiterSection() {
    return _buildSection(
      'LIMITER',
      FluxForgeTheme.accentRed,
      _limiterEnabled,
      (v) {
        setState(() => _limiterEnabled = v);
        _ffi.channelStripSetLimiterEnabled(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      Column(
        children: [
          _buildSliderRow('Thresh', _limiterThreshold, -24, 0, 'dB', (v) {
            setState(() => _limiterThreshold = v);
            _ffi.channelStripSetLimiterThreshold(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          _buildSliderRow('Release', _limiterRelease, 1, 500, 'ms', (v) {
            setState(() => _limiterRelease = v);
            _ffi.channelStripSetLimiterRelease(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 8),
          _buildGrMeter('GR', _limiterGr, FluxForgeTheme.accentRed),
        ],
      ),
    );
  }

  Widget _buildOutputSection() {
    return _buildSection(
      'OUTPUT',
      FluxForgeTheme.accentGreen,
      true,
      null,
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSliderRow('Pan', _pan, -1, 1, '', (v) {
                  setState(() => _pan = v);
                  _ffi.channelStripSetPan(widget.trackId, v);
                  widget.onSettingsChanged?.call();
                }),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSliderRow('Width', _width, 0, 2, '', (v) {
                  setState(() => _width = v);
                  _ffi.channelStripSetWidth(widget.trackId, v);
                  widget.onSettingsChanged?.call();
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSliderRow('Gain', _outputGain, -24, 24, 'dB', (v) {
            setState(() => _outputGain = v);
            _ffi.channelStripSetOutputGain(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 8),
          _buildMeterBar('Level', _outputLevel, FluxForgeTheme.accentGreen),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Color color, bool enabled, void Function(bool)? onToggle, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: enabled ? color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle != null ? () => onToggle(!enabled) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: enabled ? color.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
              ),
              child: Row(
                children: [
                  if (onToggle != null)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: enabled ? color : FluxForgeTheme.borderMedium,
                      ),
                    ),
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? color : FluxForgeTheme.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.all(12),
              child: child,
            ),
        ],
      ),
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max, String unit, void Function(double) onChanged) {
    final displayValue = unit == ':1' ? '${value.toStringAsFixed(1)}$unit' :
                         unit == 'dB' ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} $unit' :
                         unit == 'Hz' ? '${value.toInt()} $unit' :
                         unit == 'ms' ? '${value.toStringAsFixed(1)} $unit' :
                         value.toStringAsFixed(2);
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF606070), fontSize: 10),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: FluxForgeTheme.accentCyan,
              inactiveColor: FluxForgeTheme.borderSubtle,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            displayValue,
            style: const TextStyle(color: Color(0xFF40C8FF), fontSize: 10),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildMeterBar(String label, double level, Color color) {
    final normalized = ((level + 60) / 60).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 10)),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: normalized,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.6), color],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            '${level.toStringAsFixed(1)} dB',
            style: TextStyle(color: color, fontSize: 10),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildGrMeter(String label, double gr, Color color) {
    final normalized = (gr.abs() / 24).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 10)),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerRight,
              widthFactor: normalized,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            '${gr.toStringAsFixed(1)} dB',
            style: TextStyle(color: color, fontSize: 10),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
