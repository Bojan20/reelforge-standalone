/// Analog EQ Panel
///
/// Professional analog EQ emulations:
/// - Pultec EQP-1A (tube passive)
/// - API 550 (proportional Q)
/// - Neve 1073 (inductor-based)

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Analog EQ model type
enum AnalogEqModel {
  pultec,
  api550,
  neve1073,
}

/// Analog EQ Panel
class AnalogEqPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const AnalogEqPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<AnalogEqPanel> createState() => _AnalogEqPanelState();
}

class _AnalogEqPanelState extends State<AnalogEqPanel> {
  final _ffi = NativeFFI.instance;

  AnalogEqModel _model = AnalogEqModel.pultec;
  bool _bypassed = false;

  // Pultec parameters
  double _pultecLowBoost = 0.0;
  double _pultecLowAtten = 0.0;
  PultecLowFreq _pultecLowFreq = PultecLowFreq.hz100;
  double _pultecHighBoost = 0.0;
  double _pultecHighBandwidth = 0.5;
  PultecHighBoostFreq _pultecHighBoostFreq = PultecHighBoostFreq.k12;
  double _pultecHighAtten = 0.0;
  PultecHighAttenFreq _pultecHighAttenFreq = PultecHighAttenFreq.k10;
  double _pultecDrive = 0.3;

  // API 550 parameters
  double _api550LowGain = 0.0;
  Api550LowFreq _api550LowFreq = Api550LowFreq.hz200;
  double _api550MidGain = 0.0;
  Api550MidFreq _api550MidFreq = Api550MidFreq.k1_5;
  double _api550HighGain = 0.0;
  Api550HighFreq _api550HighFreq = Api550HighFreq.k10;

  // Neve 1073 parameters
  bool _neve1073HpEnabled = false;
  Neve1073HpFreq _neve1073HpFreq = Neve1073HpFreq.hz300;
  double _neve1073LowGain = 0.0;
  Neve1073LowFreq _neve1073LowFreq = Neve1073LowFreq.hz220;
  double _neve1073HighGain = 0.0;
  Neve1073HighFreq _neve1073HighFreq = Neve1073HighFreq.k12;

  @override
  void initState() {
    super.initState();
    _initializeEq();
  }

  @override
  void dispose() {
    _ffi.pultecDestroy(widget.trackId);
    _ffi.api550Destroy(widget.trackId);
    _ffi.neve1073Destroy(widget.trackId);
    super.dispose();
  }

  void _initializeEq() {
    _ffi.pultecCreate(widget.trackId, sampleRate: widget.sampleRate);
    _ffi.api550Create(widget.trackId, sampleRate: widget.sampleRate);
    _ffi.neve1073Create(widget.trackId, sampleRate: widget.sampleRate);
    _syncToEngine();
  }

  void _syncToEngine() {
    // Pultec
    _ffi.pultecSetLowBoost(widget.trackId, _pultecLowBoost);
    _ffi.pultecSetLowAtten(widget.trackId, _pultecLowAtten);
    _ffi.pultecSetLowFreq(widget.trackId, _pultecLowFreq);
    _ffi.pultecSetHighBoost(widget.trackId, _pultecHighBoost);
    _ffi.pultecSetHighBandwidth(widget.trackId, _pultecHighBandwidth);
    _ffi.pultecSetHighBoostFreq(widget.trackId, _pultecHighBoostFreq);
    _ffi.pultecSetHighAtten(widget.trackId, _pultecHighAtten);
    _ffi.pultecSetHighAttenFreq(widget.trackId, _pultecHighAttenFreq);
    _ffi.pultecSetDrive(widget.trackId, _pultecDrive);

    // API 550
    _ffi.api550SetLow(widget.trackId, _api550LowGain, _api550LowFreq);
    _ffi.api550SetMid(widget.trackId, _api550MidGain, _api550MidFreq);
    _ffi.api550SetHigh(widget.trackId, _api550HighGain, _api550HighFreq);

    // Neve 1073
    _ffi.neve1073SetHp(widget.trackId, _neve1073HpEnabled, _neve1073HpFreq);
    _ffi.neve1073SetLow(widget.trackId, _neve1073LowGain, _neve1073LowFreq);
    _ffi.neve1073SetHigh(widget.trackId, _neve1073HighGain, _neve1073HighFreq);

    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgVoid,
        border: Border.all(color: ReelForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          _buildModelSelector(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          Expanded(child: _buildModelContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq, color: ReelForgeTheme.accentOrange, size: 20),
          const SizedBox(width: 8),
          const Text(
            'ANALOG EQ',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            _modelName(_model),
            style: const TextStyle(
              color: ReelForgeTheme.accentOrange,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          _buildBypassButton(),
        ],
      ),
    );
  }

  Widget _buildBypassButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _bypassed = !_bypassed);
        // Bypass resets all - future: add proper bypass FFI
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _bypassed
              ? ReelForgeTheme.accentRed.withValues(alpha:0.3)
              : ReelForgeTheme.accentGreen.withValues(alpha:0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _bypassed ? ReelForgeTheme.accentRed : ReelForgeTheme.accentGreen,
          ),
        ),
        child: Text(
          _bypassed ? 'BYPASS' : 'ACTIVE',
          style: TextStyle(
            color: _bypassed ? ReelForgeTheme.accentRed : ReelForgeTheme.accentGreen,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _modelName(AnalogEqModel model) {
    switch (model) {
      case AnalogEqModel.pultec: return 'PULTEC EQP-1A';
      case AnalogEqModel.api550: return 'API 550';
      case AnalogEqModel.neve1073: return 'NEVE 1073';
    }
  }

  Widget _buildModelSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: AnalogEqModel.values.map((model) {
          final isSelected = model == _model;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => setState(() => _model = model),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? ReelForgeTheme.accentOrange : ReelForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? ReelForgeTheme.accentOrange : ReelForgeTheme.borderMedium,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _modelShortName(model),
                      style: TextStyle(
                        color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _modelShortName(AnalogEqModel model) {
    switch (model) {
      case AnalogEqModel.pultec: return 'PULTEC';
      case AnalogEqModel.api550: return 'API 550';
      case AnalogEqModel.neve1073: return 'NEVE';
    }
  }

  Widget _buildModelContent() {
    switch (_model) {
      case AnalogEqModel.pultec: return _buildPultecContent();
      case AnalogEqModel.api550: return _buildApi550Content();
      case AnalogEqModel.neve1073: return _buildNeve1073Content();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PULTEC EQP-1A
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPultecContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Low frequency section
          _buildSectionHeader('LOW FREQUENCY'),
          const SizedBox(height: 12),
          _buildFreqSelector<PultecLowFreq>(
            'FREQ',
            _pultecLowFreq,
            PultecLowFreq.values,
            _pultecLowFreqLabel,
            (f) {
              setState(() => _pultecLowFreq = f);
              _ffi.pultecSetLowFreq(widget.trackId, f);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 12),
          _buildKnobRow([
            _KnobData('BOOST', _pultecLowBoost, 0, 10, '', (v) {
              setState(() => _pultecLowBoost = v);
              _ffi.pultecSetLowBoost(widget.trackId, v);
              widget.onSettingsChanged?.call();
            }),
            _KnobData('ATTEN', _pultecLowAtten, 0, 10, '', (v) {
              setState(() => _pultecLowAtten = v);
              _ffi.pultecSetLowAtten(widget.trackId, v);
              widget.onSettingsChanged?.call();
            }),
          ]),

          const SizedBox(height: 24),

          // High frequency section
          _buildSectionHeader('HIGH FREQUENCY'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFreqSelector<PultecHighBoostFreq>(
                  'BOOST',
                  _pultecHighBoostFreq,
                  PultecHighBoostFreq.values,
                  _pultecHighBoostFreqLabel,
                  (f) {
                    setState(() => _pultecHighBoostFreq = f);
                    _ffi.pultecSetHighBoostFreq(widget.trackId, f);
                    widget.onSettingsChanged?.call();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildFreqSelector<PultecHighAttenFreq>(
                  'ATTEN',
                  _pultecHighAttenFreq,
                  PultecHighAttenFreq.values,
                  _pultecHighAttenFreqLabel,
                  (f) {
                    setState(() => _pultecHighAttenFreq = f);
                    _ffi.pultecSetHighAttenFreq(widget.trackId, f);
                    widget.onSettingsChanged?.call();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildKnobRow([
            _KnobData('BOOST', _pultecHighBoost, 0, 10, '', (v) {
              setState(() => _pultecHighBoost = v);
              _ffi.pultecSetHighBoost(widget.trackId, v);
              widget.onSettingsChanged?.call();
            }),
            _KnobData('BW', _pultecHighBandwidth * 10, 0, 10, '', (v) {
              setState(() => _pultecHighBandwidth = v / 10);
              _ffi.pultecSetHighBandwidth(widget.trackId, v / 10);
              widget.onSettingsChanged?.call();
            }),
            _KnobData('ATTEN', _pultecHighAtten, 0, 10, '', (v) {
              setState(() => _pultecHighAtten = v);
              _ffi.pultecSetHighAtten(widget.trackId, v);
              widget.onSettingsChanged?.call();
            }),
          ]),

          const SizedBox(height: 24),

          // Tube drive
          _buildSectionHeader('TUBE STAGE'),
          const SizedBox(height: 12),
          _buildSlider('DRIVE', _pultecDrive * 100, 0, 100, '%', (v) {
            setState(() => _pultecDrive = v / 100);
            _ffi.pultecSetDrive(widget.trackId, v / 100);
            widget.onSettingsChanged?.call();
          }),
        ],
      ),
    );
  }

  String _pultecLowFreqLabel(PultecLowFreq f) {
    switch (f) {
      case PultecLowFreq.hz20: return '20';
      case PultecLowFreq.hz30: return '30';
      case PultecLowFreq.hz60: return '60';
      case PultecLowFreq.hz100: return '100';
    }
  }

  String _pultecHighBoostFreqLabel(PultecHighBoostFreq f) {
    switch (f) {
      case PultecHighBoostFreq.k3: return '3k';
      case PultecHighBoostFreq.k4: return '4k';
      case PultecHighBoostFreq.k5: return '5k';
      case PultecHighBoostFreq.k8: return '8k';
      case PultecHighBoostFreq.k10: return '10k';
      case PultecHighBoostFreq.k12: return '12k';
      case PultecHighBoostFreq.k16: return '16k';
    }
  }

  String _pultecHighAttenFreqLabel(PultecHighAttenFreq f) {
    switch (f) {
      case PultecHighAttenFreq.k5: return '5k';
      case PultecHighAttenFreq.k10: return '10k';
      case PultecHighAttenFreq.k20: return '20k';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // API 550
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildApi550Content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Low band
          _buildSectionHeader('LOW'),
          const SizedBox(height: 12),
          _buildFreqSelector<Api550LowFreq>(
            'FREQ',
            _api550LowFreq,
            Api550LowFreq.values,
            _api550LowFreqLabel,
            (f) {
              setState(() => _api550LowFreq = f);
              _ffi.api550SetLow(widget.trackId, _api550LowGain, f);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 8),
          _buildSlider('GAIN', _api550LowGain, -12, 12, 'dB', (v) {
            setState(() => _api550LowGain = v);
            _ffi.api550SetLow(widget.trackId, v, _api550LowFreq);
            widget.onSettingsChanged?.call();
          }),

          const SizedBox(height: 24),

          // Mid band
          _buildSectionHeader('MID'),
          const SizedBox(height: 12),
          _buildFreqSelector<Api550MidFreq>(
            'FREQ',
            _api550MidFreq,
            Api550MidFreq.values,
            _api550MidFreqLabel,
            (f) {
              setState(() => _api550MidFreq = f);
              _ffi.api550SetMid(widget.trackId, _api550MidGain, f);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 8),
          _buildSlider('GAIN', _api550MidGain, -12, 12, 'dB', (v) {
            setState(() => _api550MidGain = v);
            _ffi.api550SetMid(widget.trackId, v, _api550MidFreq);
            widget.onSettingsChanged?.call();
          }),

          const SizedBox(height: 24),

          // High band
          _buildSectionHeader('HIGH'),
          const SizedBox(height: 12),
          _buildFreqSelector<Api550HighFreq>(
            'FREQ',
            _api550HighFreq,
            Api550HighFreq.values,
            _api550HighFreqLabel,
            (f) {
              setState(() => _api550HighFreq = f);
              _ffi.api550SetHigh(widget.trackId, _api550HighGain, f);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 8),
          _buildSlider('GAIN', _api550HighGain, -12, 12, 'dB', (v) {
            setState(() => _api550HighGain = v);
            _ffi.api550SetHigh(widget.trackId, v, _api550HighFreq);
            widget.onSettingsChanged?.call();
          }),

          const SizedBox(height: 16),
          const Text(
            'Proportional Q: narrower at higher gain settings',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _api550LowFreqLabel(Api550LowFreq f) {
    switch (f) {
      case Api550LowFreq.hz50: return '50';
      case Api550LowFreq.hz100: return '100';
      case Api550LowFreq.hz200: return '200';
      case Api550LowFreq.hz300: return '300';
      case Api550LowFreq.hz400: return '400';
    }
  }

  String _api550MidFreqLabel(Api550MidFreq f) {
    switch (f) {
      case Api550MidFreq.hz200: return '200';
      case Api550MidFreq.hz400: return '400';
      case Api550MidFreq.hz800: return '800';
      case Api550MidFreq.k1_5: return '1.5k';
      case Api550MidFreq.k3: return '3k';
    }
  }

  String _api550HighFreqLabel(Api550HighFreq f) {
    switch (f) {
      case Api550HighFreq.k2_5: return '2.5k';
      case Api550HighFreq.k5: return '5k';
      case Api550HighFreq.k7_5: return '7.5k';
      case Api550HighFreq.k10: return '10k';
      case Api550HighFreq.k12_5: return '12.5k';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEVE 1073
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNeve1073Content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // High-pass filter
          _buildSectionHeader('HIGH-PASS FILTER'),
          const SizedBox(height: 12),
          Row(
            children: [
              // Enable switch
              GestureDetector(
                onTap: () {
                  setState(() => _neve1073HpEnabled = !_neve1073HpEnabled);
                  _ffi.neve1073SetHp(widget.trackId, _neve1073HpEnabled, _neve1073HpFreq);
                  widget.onSettingsChanged?.call();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _neve1073HpEnabled
                        ? ReelForgeTheme.accentOrange.withValues(alpha:0.3)
                        : ReelForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _neve1073HpEnabled
                          ? ReelForgeTheme.accentOrange
                          : ReelForgeTheme.borderMedium,
                    ),
                  ),
                  child: Text(
                    _neve1073HpEnabled ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: _neve1073HpEnabled
                          ? ReelForgeTheme.accentOrange
                          : ReelForgeTheme.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildFreqSelector<Neve1073HpFreq>(
                  'FREQ',
                  _neve1073HpFreq,
                  Neve1073HpFreq.values,
                  _neve1073HpFreqLabel,
                  (f) {
                    setState(() => _neve1073HpFreq = f);
                    _ffi.neve1073SetHp(widget.trackId, _neve1073HpEnabled, f);
                    widget.onSettingsChanged?.call();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Low shelf
          _buildSectionHeader('LOW SHELF'),
          const SizedBox(height: 12),
          _buildFreqSelector<Neve1073LowFreq>(
            'FREQ',
            _neve1073LowFreq,
            Neve1073LowFreq.values,
            _neve1073LowFreqLabel,
            (f) {
              setState(() => _neve1073LowFreq = f);
              _ffi.neve1073SetLow(widget.trackId, _neve1073LowGain, f);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 8),
          _buildSlider('GAIN', _neve1073LowGain, -16, 16, 'dB', (v) {
            setState(() => _neve1073LowGain = v);
            _ffi.neve1073SetLow(widget.trackId, v, _neve1073LowFreq);
            widget.onSettingsChanged?.call();
          }),

          const SizedBox(height: 24),

          // High shelf
          _buildSectionHeader('HIGH SHELF'),
          const SizedBox(height: 12),
          _buildFreqSelector<Neve1073HighFreq>(
            'FREQ',
            _neve1073HighFreq,
            Neve1073HighFreq.values,
            _neve1073HighFreqLabel,
            (f) {
              setState(() => _neve1073HighFreq = f);
              _ffi.neve1073SetHigh(widget.trackId, _neve1073HighGain, f);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(height: 8),
          _buildSlider('GAIN', _neve1073HighGain, -16, 16, 'dB', (v) {
            setState(() => _neve1073HighGain = v);
            _ffi.neve1073SetHigh(widget.trackId, v, _neve1073HighFreq);
            widget.onSettingsChanged?.call();
          }),

          const SizedBox(height: 16),
          const Text(
            'Inductor-based EQ with transformer coloration',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _neve1073HpFreqLabel(Neve1073HpFreq f) {
    switch (f) {
      case Neve1073HpFreq.hz50: return '50';
      case Neve1073HpFreq.hz80: return '80';
      case Neve1073HpFreq.hz160: return '160';
      case Neve1073HpFreq.hz300: return '300';
    }
  }

  String _neve1073LowFreqLabel(Neve1073LowFreq f) {
    switch (f) {
      case Neve1073LowFreq.hz35: return '35';
      case Neve1073LowFreq.hz60: return '60';
      case Neve1073LowFreq.hz110: return '110';
      case Neve1073LowFreq.hz220: return '220';
    }
  }

  String _neve1073HighFreqLabel(Neve1073HighFreq f) {
    switch (f) {
      case Neve1073HighFreq.k12: return '12k';
      case Neve1073HighFreq.k10: return '10k';
      case Neve1073HighFreq.k7_5: return '7.5k';
      case Neve1073HighFreq.k5: return '5k';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: ReelForgeTheme.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildFreqSelector<T>(
    String label,
    T current,
    List<T> values,
    String Function(T) formatter,
    void Function(T) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: ReelForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: values.map((v) {
            final isSelected = v == current;
            return GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? ReelForgeTheme.accentOrange
                      : ReelForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isSelected
                        ? ReelForgeTheme.accentOrange
                        : ReelForgeTheme.borderMedium,
                  ),
                ),
                child: Text(
                  formatter(v),
                  style: TextStyle(
                    color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    void Function(double) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: ReelForgeTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(
                color: ReelForgeTheme.accentOrange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: ReelForgeTheme.accentOrange,
            inactiveTrackColor: ReelForgeTheme.borderSubtle,
            thumbColor: ReelForgeTheme.accentOrange,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayColor: ReelForgeTheme.accentOrange.withValues(alpha:0.2),
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

  Widget _buildKnobRow(List<_KnobData> knobs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: knobs.map((k) => _buildKnob(k)).toList(),
    );
  }

  Widget _buildKnob(_KnobData knob) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ReelForgeTheme.bgMid,
            border: Border.all(color: ReelForgeTheme.borderMedium, width: 2),
            boxShadow: [
              BoxShadow(
                color: ReelForgeTheme.accentOrange.withValues(alpha:0.1),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Knob indicator
              Transform.rotate(
                angle: (knob.value - knob.min) / (knob.max - knob.min) * 2.8 - 1.4,
                child: Container(
                  width: 4,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: ReelForgeTheme.accentOrange,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
                  ),
                ),
              ),
              // Value text
              Text(
                knob.value.toStringAsFixed(1),
                style: const TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          knob.label,
          style: const TextStyle(
            color: ReelForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Hidden slider for interaction
        SizedBox(
          width: 70,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: ReelForgeTheme.borderMedium,
              inactiveTrackColor: ReelForgeTheme.borderSubtle,
              thumbColor: ReelForgeTheme.accentOrange,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayColor: Colors.transparent,
            ),
            child: Slider(
              value: knob.value.clamp(knob.min, knob.max),
              min: knob.min,
              max: knob.max,
              onChanged: knob.onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _KnobData {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final void Function(double) onChanged;

  _KnobData(this.label, this.value, this.min, this.max, this.unit, this.onChanged);
}
