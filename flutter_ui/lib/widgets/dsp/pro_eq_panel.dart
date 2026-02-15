/// Pro-EQ 64 Panel
///
/// Professional 64-band parametric EQ with:
/// - 10 filter types (Bell, Shelves, Cuts, Notch, Bandpass, Tilt, Allpass, Brickwall)
/// - Per-band stereo placement (Stereo/L/R/Mid/Side)
/// - Per-band slope (6-96 dB/oct + Brickwall)
/// - Dynamic EQ per band
/// - A/B comparison
/// - Real-time spectrum analyzer
/// - EQ matching
/// - Auto-gain

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Pro EQ Band data
class ProEqBand {
  int index;
  double freq;
  double gain;
  double q;
  ProEqFilterShape shape;
  ProEqPlacement placement;
  ProEqSlope slope;
  bool enabled;
  // Dynamic EQ
  bool dynamicEnabled;
  double dynamicThreshold;
  double dynamicRatio;
  double dynamicAttack;
  double dynamicRelease;

  ProEqBand({
    required this.index,
    this.freq = 1000.0,
    this.gain = 0.0,
    this.q = 1.0,
    this.shape = ProEqFilterShape.bell,
    this.placement = ProEqPlacement.stereo,
    this.slope = ProEqSlope.db12,
    this.enabled = true,
    this.dynamicEnabled = false,
    this.dynamicThreshold = -20.0,
    this.dynamicRatio = 2.0,
    this.dynamicAttack = 10.0,
    this.dynamicRelease = 100.0,
  });
}

/// Pro-EQ 64 Panel Widget
class ProEqPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ProEqPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<ProEqPanel> createState() => _ProEqPanelState();
}

class _ProEqPanelState extends State<ProEqPanel> {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  final List<ProEqBand> _bands = [];
  int? _selectedBandIndex;

  // Settings
  double _outputGain = 0.0;
  ProEqAnalyzerMode _analyzerMode = ProEqAnalyzerMode.postEq;
  bool _autoGain = false;
  bool _matchEnabled = false;
  // ignore: unused_field
  bool _showDynamicPanel = false;

  // Spectrum data
  List<double> _spectrum = [];
  List<(double, double)> _eqCurve = [];
  Timer? _spectrumTimer;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _spectrumTimer?.cancel();
    _ffi.proEqDestroy(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    // Only connect to existing EQ node — do NOT auto-add
    for (final n in chain.nodes) {
      if (n.type == DspNodeType.eq) {
        setState(() => _initialized = true);
        _startSpectrumUpdate();
        return;
      }
    }
  }

  void _startSpectrumUpdate() {
    _spectrumTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _initialized && _analyzerMode != ProEqAnalyzerMode.off) {
        final spectrum = _ffi.proEqGetSpectrum(widget.trackId);
        final curve = _ffi.proEqGetFrequencyResponse(widget.trackId);
        if (spectrum != null || curve != null) {
          setState(() {
            if (spectrum != null) _spectrum = spectrum.toList().cast<double>();
            if (curve != null) _eqCurve = curve;
          });
        }
      }
    });
  }

  void _addBand(double freq, ProEqFilterShape shape) {
    if (_bands.length >= 64) return;

    final bandIndex = _bands.length;
    final band = ProEqBand(index: bandIndex, freq: freq, shape: shape);

    _ffi.proEqSetBand(widget.trackId, bandIndex,
      freq: freq,
      gainDb: 0.0,
      q: 1.0,
      shape: shape,
    );
    _ffi.proEqSetBandEnabled(widget.trackId, bandIndex, true);

    setState(() {
      _bands.add(band);
      _selectedBandIndex = _bands.length - 1;
    });
    widget.onSettingsChanged?.call();
  }

  void _updateBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.proEqSetBand(widget.trackId, band.index,
      freq: band.freq,
      gainDb: band.gain,
      q: band.q,
      shape: band.shape,
    );
    _ffi.proEqSetBandPlacement(widget.trackId, band.index, band.placement);
    _ffi.proEqSetBandSlope(widget.trackId, band.index, band.slope);
    _ffi.proEqSetBandEnabled(widget.trackId, band.index, band.enabled);

    if (band.dynamicEnabled) {
      _ffi.proEqSetBandDynamic(widget.trackId, band.index,
        enabled: true,
        thresholdDb: band.dynamicThreshold,
        ratio: band.dynamicRatio,
        attackMs: band.dynamicAttack,
        releaseMs: band.dynamicRelease,
      );
    }

    widget.onSettingsChanged?.call();
  }

  void _removeBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.proEqSetBandEnabled(widget.trackId, band.index, false);
    setState(() {
      _bands.removeAt(listIndex);
      _selectedBandIndex = _bands.isEmpty ? null : math.max(0, listIndex - 1);
    });
    widget.onSettingsChanged?.call();
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
            child: Column(
              children: [
                Expanded(flex: 3, child: _buildEqGraph()),
                const Divider(height: 1, color: Color(0xFF2A2A30)),
                _buildToolbar(),
                const Divider(height: 1, color: Color(0xFF2A2A30)),
                _buildBandList(),
                if (_selectedBandIndex != null) ...[
                  const Divider(height: 1, color: Color(0xFF2A2A30)),
                  _buildBandEditor(),
                ],
              ],
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
          const Icon(Icons.equalizer, color: Color(0xFF4A9EFF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'PRO-EQ 64',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_bands.where((b) => b.enabled).length}/64 BANDS',
              style: const TextStyle(
                color: Color(0xFF808090),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          _buildAbCompare(),
          const SizedBox(width: 12),
          _buildOutputGain(),
        ],
      ),
    );
  }

  Widget _buildAbCompare() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAbButton('A', () {
          _ffi.proEqRecallStateA(widget.trackId);
          widget.onSettingsChanged?.call();
        }, () => _ffi.proEqStoreStateA(widget.trackId)),
        const SizedBox(width: 4),
        _buildAbButton('B', () {
          _ffi.proEqRecallStateB(widget.trackId);
          widget.onSettingsChanged?.call();
        }, () => _ffi.proEqStoreStateB(widget.trackId)),
      ],
    );
  }

  Widget _buildAbButton(String label, VoidCallback onTap, VoidCallback onLongPress) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderMedium),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF4A9EFF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutputGain() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('OUT', style: TextStyle(color: Color(0xFF606070), fontSize: 10)),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 4,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: _outputGain,
              min: -24,
              max: 24,
              activeColor: FluxForgeTheme.accentBlue,
              inactiveColor: FluxForgeTheme.borderSubtle,
              onChanged: (v) {
                setState(() => _outputGain = v);
                _ffi.proEqSetOutputGain(widget.trackId, v);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            '${_outputGain >= 0 ? '+' : ''}${_outputGain.toStringAsFixed(1)}',
            style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Analyzer mode
          _buildDropdown<ProEqAnalyzerMode>(
            'Analyzer',
            _analyzerMode,
            ProEqAnalyzerMode.values,
            (m) => m.name.toUpperCase(),
            (v) {
              setState(() => _analyzerMode = v);
              _ffi.proEqSetAnalyzerMode(widget.trackId, v);
            },
          ),
          const SizedBox(width: 16),
          // Auto-gain toggle
          _buildToggle('Auto-Gain', _autoGain, (v) {
            setState(() => _autoGain = v);
            _ffi.proEqSetAutoGain(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(width: 16),
          // Match toggle
          _buildToggle('Match', _matchEnabled, (v) {
            setState(() => _matchEnabled = v);
            _ffi.proEqSetMatchEnabled(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const Spacer(),
          // Reset button
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF606070), size: 18),
            onPressed: () {
              _ffi.proEqReset(widget.trackId);
              setState(() {
                _bands.clear();
                _selectedBandIndex = null;
              });
              widget.onSettingsChanged?.call();
            },
            tooltip: 'Reset EQ',
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>(String label, T value, List<T> items, String Function(T) labelFn, void Function(T) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 10)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderMedium),
          ),
          child: DropdownButton<T>(
            value: value,
            dropdownColor: FluxForgeTheme.bgMid,
            style: const TextStyle(color: Color(0xFF808090), fontSize: 10),
            underline: const SizedBox(),
            isDense: true,
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(labelFn(e)))).toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? FluxForgeTheme.accentBlue.withValues(alpha: 0.3) : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderMedium),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEqGraph() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            painter: _ProEqGraphPainter(
              bands: _bands,
              selectedIndex: _selectedBandIndex,
              spectrum: _spectrum,
              eqCurve: _eqCurve,
              analyzerMode: _analyzerMode,
            ),
            child: GestureDetector(
              onTapDown: (d) => _handleGraphTap(d.localPosition, constraints.biggest),
              onPanStart: _selectedBandIndex != null
                  ? (d) => _handleGraphDrag(d.localPosition, constraints.biggest)
                  : null,
              onPanUpdate: _selectedBandIndex != null
                  ? (d) => _handleGraphDrag(d.localPosition, constraints.biggest)
                  : null,
            ),
          );
        },
      ),
    );
  }

  void _handleGraphTap(Offset position, Size size) {
    // Check if clicking on existing band
    for (int i = 0; i < _bands.length; i++) {
      final band = _bands[i];
      if (!band.enabled) continue;
      final x = _freqToX(band.freq, size.width);
      final y = size.height / 2 - (band.gain / 30) * (size.height / 2);
      if ((Offset(x, y) - position).distance < 15) {
        setState(() => _selectedBandIndex = i);
        return;
      }
    }

    // Add new band
    final freq = _xToFreq(position.dx, size.width);
    _showAddBandDialog(freq);
  }

  void _showAddBandDialog(double freq) {
    showModalBottomSheet(
      context: context,
      backgroundColor: FluxForgeTheme.bgMid,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Band at ${freq.toInt()} Hz',
              style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ProEqFilterShape.values.map((shape) {
                return ActionChip(
                  label: Text(_shapeName(shape)),
                  backgroundColor: _getShapeColor(shape).withValues(alpha: 0.3),
                  labelStyle: TextStyle(color: _getShapeColor(shape), fontSize: 11),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addBand(freq, shape);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _handleGraphDrag(Offset position, Size size) {
    if (_selectedBandIndex == null) return;

    final band = _bands[_selectedBandIndex!];
    final newFreq = _xToFreq(position.dx, size.width).clamp(10.0, 30000.0);
    final newGain = ((size.height / 2 - position.dy) / (size.height / 2) * 30).clamp(-30.0, 30.0);

    setState(() {
      band.freq = newFreq;
      band.gain = newGain;
    });
    _updateBand(_selectedBandIndex!);
  }

  double _freqToX(double freq, double width) {
    const minLog = 1.0; // log10(10)
    const maxLog = 4.477; // log10(30000)
    return ((math.log(freq.clamp(10, 30000)) / math.ln10 - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.0;
    const maxLog = 4.477;
    return math.pow(10, minLog + (x / width) * (maxLog - minLog)).toDouble();
  }

  String _shapeName(ProEqFilterShape shape) {
    return switch (shape) {
      ProEqFilterShape.bell => 'Bell',
      ProEqFilterShape.lowShelf => 'Low Shelf',
      ProEqFilterShape.highShelf => 'High Shelf',
      ProEqFilterShape.lowCut => 'Low Cut',
      ProEqFilterShape.highCut => 'High Cut',
      ProEqFilterShape.notch => 'Notch',
      ProEqFilterShape.bandPass => 'Bandpass',
      ProEqFilterShape.tiltShelf => 'Tilt',
      ProEqFilterShape.allPass => 'Allpass',
      ProEqFilterShape.brickwall => 'Brickwall',
    };
  }

  Color _getShapeColor(ProEqFilterShape shape) {
    return switch (shape) {
      ProEqFilterShape.bell => FluxForgeTheme.accentBlue,
      ProEqFilterShape.lowShelf => FluxForgeTheme.accentOrange,
      ProEqFilterShape.highShelf => FluxForgeTheme.accentYellow,
      ProEqFilterShape.lowCut => FluxForgeTheme.accentRed,
      ProEqFilterShape.highCut => FluxForgeTheme.accentRed,
      ProEqFilterShape.notch => FluxForgeTheme.accentPink,
      ProEqFilterShape.bandPass => FluxForgeTheme.accentGreen,
      ProEqFilterShape.tiltShelf => FluxForgeTheme.accentCyan,
      ProEqFilterShape.allPass => FluxForgeTheme.textTertiary,
      ProEqFilterShape.brickwall => FluxForgeTheme.accentRed,
    };
  }

  Widget _buildBandList() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text('BANDS:', style: TextStyle(color: Color(0xFF606070), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _bands.length,
              itemBuilder: (context, index) => _buildBandChip(index),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF4A9EFF), size: 20),
            onPressed: () => _showAddBandDialog(1000.0),
          ),
        ],
      ),
    );
  }

  Widget _buildBandChip(int index) {
    final band = _bands[index];
    final isSelected = index == _selectedBandIndex;
    final color = _getShapeColor(band.shape);

    return GestureDetector(
      onTap: () => setState(() => _selectedBandIndex = index),
      onLongPress: () => _removeBand(index),
      child: Opacity(
        opacity: band.enabled ? 1.0 : 0.5,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? color : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color, width: isSelected ? 2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (band.dynamicEnabled)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.flash_on, size: 10, color: FluxForgeTheme.textPrimary),
                ),
              Text(
                '${band.freq.toInt()} Hz',
                style: TextStyle(
                  color: isSelected ? FluxForgeTheme.textPrimary : color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBandEditor() {
    if (_selectedBandIndex == null || _selectedBandIndex! >= _bands.length) return const SizedBox();

    final band = _bands[_selectedBandIndex!];
    final color = _getShapeColor(band.shape);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(top: BorderSide(color: Color(0xFF2A2A30))),
      ),
      child: Column(
        children: [
          // Row 1: Shape, Placement, Slope, Enable
          Row(
            children: [
              // Shape
              Expanded(
                child: _buildEnumSelector<ProEqFilterShape>(
                  'Shape',
                  band.shape,
                  ProEqFilterShape.values,
                  _shapeName,
                  _getShapeColor,
                  (v) {
                    setState(() => band.shape = v);
                    _updateBand(_selectedBandIndex!);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Placement
              Expanded(
                child: _buildEnumSelector<ProEqPlacement>(
                  'Channel',
                  band.placement,
                  ProEqPlacement.values,
                  (p) => p.name.toUpperCase(),
                  (_) => FluxForgeTheme.accentBlue,
                  (v) {
                    setState(() => band.placement = v);
                    _updateBand(_selectedBandIndex!);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Slope (for cut filters)
              if (band.shape == ProEqFilterShape.lowCut || band.shape == ProEqFilterShape.highCut)
                Expanded(
                  child: _buildEnumSelector<ProEqSlope>(
                    'Slope',
                    band.slope,
                    ProEqSlope.values,
                    (s) => s.name.replaceFirst('db', '').replaceFirst('brickwall', 'BW'),
                    (_) => FluxForgeTheme.accentOrange,
                    (v) {
                      setState(() => band.slope = v);
                      _updateBand(_selectedBandIndex!);
                    },
                  ),
                ),
              const SizedBox(width: 8),
              // Enable toggle
              _buildToggle(band.enabled ? 'ON' : 'OFF', band.enabled, (v) {
                setState(() => band.enabled = v);
                _updateBand(_selectedBandIndex!);
              }),
              const SizedBox(width: 8),
              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFFF4040), size: 18),
                onPressed: () => _removeBand(_selectedBandIndex!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: Freq, Gain, Q
          Row(
            children: [
              Expanded(flex: 2, child: _buildSlider('FREQ', band.freq, 10, 30000, '${band.freq.toInt()} Hz', color, true, (v) {
                setState(() => band.freq = v);
                _updateBand(_selectedBandIndex!);
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildSlider('GAIN', band.gain, -30, 30, '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB', color, false, (v) {
                setState(() => band.gain = v);
                _updateBand(_selectedBandIndex!);
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildSlider('Q', band.q, 0.1, 30, band.q.toStringAsFixed(2), color, true, (v) {
                setState(() => band.q = v);
                _updateBand(_selectedBandIndex!);
              })),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3: Dynamic EQ toggle
          Row(
            children: [
              _buildToggle('Dynamic EQ', band.dynamicEnabled, (v) {
                setState(() {
                  band.dynamicEnabled = v;
                  _showDynamicPanel = v;
                });
                _updateBand(_selectedBandIndex!);
              }),
            ],
          ),
          // Row 4: Dynamic EQ params (if enabled)
          if (band.dynamicEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildSlider('Thresh', band.dynamicThreshold, -60, 0, '${band.dynamicThreshold.toStringAsFixed(1)} dB', FluxForgeTheme.accentYellow, false, (v) {
                  setState(() => band.dynamicThreshold = v);
                  _updateBand(_selectedBandIndex!);
                })),
                const SizedBox(width: 8),
                Expanded(child: _buildSlider('Ratio', band.dynamicRatio, 1, 20, '${band.dynamicRatio.toStringAsFixed(1)}:1', FluxForgeTheme.accentYellow, false, (v) {
                  setState(() => band.dynamicRatio = v);
                  _updateBand(_selectedBandIndex!);
                })),
                const SizedBox(width: 8),
                Expanded(child: _buildSlider('Attack', band.dynamicAttack, 0.1, 500, '${band.dynamicAttack.toStringAsFixed(1)} ms', FluxForgeTheme.accentYellow, true, (v) {
                  setState(() => band.dynamicAttack = v);
                  _updateBand(_selectedBandIndex!);
                })),
                const SizedBox(width: 8),
                Expanded(child: _buildSlider('Release', band.dynamicRelease, 1, 5000, '${band.dynamicRelease.toInt()} ms', FluxForgeTheme.accentYellow, true, (v) {
                  setState(() => band.dynamicRelease = v);
                  _updateBand(_selectedBandIndex!);
                })),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnumSelector<T>(String label, T value, List<T> items, String Function(T) labelFn, Color Function(T) colorFn, void Function(T) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: items.map((item) {
              final isSelected = item == value;
              final color = colorFn(item);
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => onChanged(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? color : FluxForgeTheme.bgMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: isSelected ? color : FluxForgeTheme.borderMedium),
                    ),
                    child: Text(
                      labelFn(item),
                      style: TextStyle(
                        color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, String display, Color color, bool log, void Function(double) onChanged) {
    double sliderVal = log && min > 0
        ? (math.log(value) - math.log(min)) / (math.log(max) - math.log(min))
        : (value - min) / (max - min);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 9, fontWeight: FontWeight.bold)),
            Text(display, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: color,
            inactiveTrackColor: FluxForgeTheme.borderSubtle,
            thumbColor: color,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: sliderVal.clamp(0.0, 1.0),
            onChanged: (v) {
              double newVal = log && min > 0
                  ? math.exp(math.log(min) + v * (math.log(max) - math.log(min)))
                  : min + v * (max - min);
              onChanged(newVal.clamp(min, max));
            },
          ),
        ),
      ],
    );
  }
}

class _ProEqGraphPainter extends CustomPainter {
  final List<ProEqBand> bands;
  final int? selectedIndex;
  final List<double> spectrum;
  final List<(double, double)> eqCurve;
  final ProEqAnalyzerMode analyzerMode;

  _ProEqGraphPainter({
    required this.bands,
    required this.selectedIndex,
    required this.spectrum,
    required this.eqCurve,
    required this.analyzerMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    if (analyzerMode != ProEqAnalyzerMode.off && spectrum.isNotEmpty) {
      _drawSpectrum(canvas, size);
    }

    if (eqCurve.isNotEmpty) {
      _drawEqCurve(canvas, size);
    } else {
      _drawCalculatedCurve(canvas, size);
    }

    _drawBandMarkers(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()..color = FluxForgeTheme.borderSubtle..strokeWidth = 1;

    // Frequency lines
    for (final freq in [100.0, 1000.0, 10000.0]) {
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // dB lines
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint..color = FluxForgeTheme.borderMedium);
    for (final db in [-12.0, 12.0]) {
      final y = centerY - (db / 30) * (size.height / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint..color = FluxForgeTheme.borderSubtle);
    }
  }

  void _drawSpectrum(Canvas canvas, Size size) {
    if (spectrum.isEmpty) return;

    final path = Path();
    final spectrumPaint = Paint()
      ..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    path.moveTo(0, size.height);
    for (int i = 0; i < spectrum.length; i++) {
      final x = (i / (spectrum.length - 1)) * size.width;
      final db = spectrum[i].clamp(-60.0, 0.0);
      final y = size.height - ((db + 60) / 60) * size.height;
      if (i == 0) {
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, spectrumPaint);
  }

  void _drawEqCurve(Canvas canvas, Size size) {
    if (eqCurve.isEmpty) return;

    final path = Path();
    final centerY = size.height / 2;

    for (int i = 0; i < eqCurve.length; i++) {
      final (freq, db) = eqCurve[i];
      final x = _freqToX(freq, size.width);
      final y = centerY - (db / 30) * (size.height / 2);

      if (i == 0) {
        path.moveTo(x, y.clamp(0, size.height));
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(size.width, centerY)
      ..lineTo(0, centerY)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.1));

    // Stroke
    canvas.drawPath(path, Paint()
      ..color = FluxForgeTheme.accentBlue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);
  }

  void _drawCalculatedCurve(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final path = Path();
    final centerY = size.height / 2;

    for (int i = 0; i <= size.width.toInt(); i++) {
      final x = i.toDouble();
      final freq = _xToFreq(x, size.width);
      double totalDb = 0;

      for (final band in bands) {
        if (!band.enabled) continue;
        totalDb += _calculateBandResponse(freq, band);
      }

      final y = centerY - (totalDb / 30) * (size.height / 2);
      if (i == 0) {
        path.moveTo(x, y.clamp(0, size.height));
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }

    canvas.drawPath(path, Paint()
      ..color = FluxForgeTheme.accentBlue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);
  }

  double _calculateBandResponse(double freq, ProEqBand band) {
    final ratio = freq / band.freq;
    final logRatio = math.log(ratio) / math.ln2;

    return switch (band.shape) {
      ProEqFilterShape.bell => band.gain * math.exp(-math.pow(logRatio * band.q, 2)),
      ProEqFilterShape.lowShelf => band.gain * (1 - 1 / (1 + math.exp(-logRatio * 4))),
      ProEqFilterShape.highShelf => band.gain * (1 / (1 + math.exp(-logRatio * 4))),
      ProEqFilterShape.lowCut => ratio < 1 ? -30 * (1 - ratio) : 0,
      ProEqFilterShape.highCut => ratio > 1 ? -30 * (ratio - 1) : 0,
      ProEqFilterShape.notch => -math.min(30.0, 30 * math.exp(-math.pow(logRatio * band.q * 2, 2))),
      ProEqFilterShape.bandPass => math.exp(-math.pow(logRatio * band.q, 2)) * 12 - 6,
      ProEqFilterShape.tiltShelf => band.gain * logRatio.clamp(-2.0, 2.0) / 2,
      _ => 0,
    };
  }

  void _drawBandMarkers(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      if (!band.enabled) continue;

      final x = _freqToX(band.freq, size.width);
      final y = centerY - (band.gain / 30) * (size.height / 2);
      final color = _getShapeColor(band.shape);

      // Main dot
      canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), i == selectedIndex ? 10 : 7, Paint()..color = color);

      // Selection ring
      if (i == selectedIndex) {
        canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), 13, Paint()
          ..color = FluxForgeTheme.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }

      // Dynamic indicator
      if (band.dynamicEnabled) {
        canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8) - 14), 3, Paint()..color = FluxForgeTheme.accentYellow);
      }
    }
  }

  double _freqToX(double freq, double width) {
    const minLog = 1.0;
    const maxLog = 4.477;
    return ((math.log(freq.clamp(10, 30000)) / math.ln10 - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.0;
    const maxLog = 4.477;
    return math.pow(10, minLog + (x / width) * (maxLog - minLog)).toDouble();
  }

  Color _getShapeColor(ProEqFilterShape shape) {
    return switch (shape) {
      ProEqFilterShape.bell => FluxForgeTheme.accentBlue,
      ProEqFilterShape.lowShelf => FluxForgeTheme.accentOrange,
      ProEqFilterShape.highShelf => FluxForgeTheme.accentYellow,
      ProEqFilterShape.lowCut => FluxForgeTheme.accentRed,
      ProEqFilterShape.highCut => FluxForgeTheme.accentRed,
      ProEqFilterShape.notch => FluxForgeTheme.accentPink,
      ProEqFilterShape.bandPass => FluxForgeTheme.accentGreen,
      ProEqFilterShape.tiltShelf => FluxForgeTheme.accentCyan,
      ProEqFilterShape.allPass => FluxForgeTheme.textTertiary,
      ProEqFilterShape.brickwall => FluxForgeTheme.accentRed,
    };
  }

  @override
  bool shouldRepaint(covariant _ProEqGraphPainter old) {
    if (bands.length != old.bands.length) return true;
    if (selectedIndex != old.selectedIndex) return true;
    if (analyzerMode != old.analyzerMode) return true;
    if (spectrum != old.spectrum) return true;
    if (eqCurve != old.eqCurve) return true;
    for (int i = 0; i < bands.length; i++) {
      final b = bands[i], o = old.bands[i];
      if (b.freq != o.freq || b.gain != o.gain || b.q != o.q ||
          b.shape != o.shape || b.enabled != o.enabled) {
        return true;
      }
    }
    return false;
  }
}
