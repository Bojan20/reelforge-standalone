/// Linear Phase EQ Panel
///
/// FIR-based linear phase EQ with:
/// - Zero phase distortion
/// - 8 filter types
/// - Latency display
/// - Visual EQ curve

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// EQ Band data
class LinearPhaseBand {
  int index;
  LinearPhaseFilterType type;
  double freq;
  double gain;
  double q;
  bool enabled;

  LinearPhaseBand({
    required this.index,
    this.type = LinearPhaseFilterType.bell,
    this.freq = 1000.0,
    this.gain = 0.0,
    this.q = 1.0,
    this.enabled = true,
  });
}

/// Linear Phase EQ Panel Widget
class LinearPhaseEqPanel extends StatefulWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const LinearPhaseEqPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  State<LinearPhaseEqPanel> createState() => _LinearPhaseEqPanelState();
}

class _LinearPhaseEqPanelState extends State<LinearPhaseEqPanel> {
  final _ffi = NativeFFI.instance;
  // ignore: unused_field
  bool _initialized = false;
  bool _bypassed = false;

  final List<LinearPhaseBand> _bands = [];
  int? _selectedBandIndex;
  int _latencySamples = 0;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _ffi.linearPhaseEqRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final dsp = DspChainProvider.instance;
    final chain = dsp.getChain(widget.trackId);

    // Only connect to existing EQ node — do NOT auto-add
    for (final n in chain.nodes) {
      if (n.type == DspNodeType.eq) {
        setState(() {
          _initialized = true;
          _latencySamples = _ffi.linearPhaseEqGetLatency(widget.trackId);
        });
        return;
      }
    }
  }

  void _addBand(LinearPhaseFilterType type, double freq) {
    if (_bands.length >= 16) return;

    final bandIndex = _ffi.linearPhaseEqAddBand(
      widget.trackId,
      type,
      freq,
      0.0,
      1.0,
    );

    if (bandIndex >= 0) {
      setState(() {
        _bands.add(LinearPhaseBand(
          index: bandIndex,
          type: type,
          freq: freq,
        ));
        _selectedBandIndex = _bands.length - 1;
        _latencySamples = _ffi.linearPhaseEqGetLatency(widget.trackId);
      });
      widget.onSettingsChanged?.call();
    }
  }

  void _updateBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.linearPhaseEqUpdateBand(
      widget.trackId,
      band.index,
      band.type,
      band.freq,
      band.gain,
      band.q,
    );
    setState(() {
      _latencySamples = _ffi.linearPhaseEqGetLatency(widget.trackId);
    });
    widget.onSettingsChanged?.call();
  }

  void _removeBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.linearPhaseEqRemoveBand(widget.trackId, band.index);
    setState(() {
      _bands.removeAt(listIndex);
      if (_selectedBandIndex == listIndex) {
        _selectedBandIndex = _bands.isEmpty ? null : 0;
      } else if (_selectedBandIndex != null && _selectedBandIndex! > listIndex) {
        _selectedBandIndex = _selectedBandIndex! - 1;
      }
      _latencySamples = _ffi.linearPhaseEqGetLatency(widget.trackId);
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
                Expanded(
                  flex: 2,
                  child: _buildEqGraph(),
                ),
                const Divider(height: 1, color: Color(0xFF2A2A30)),
                _buildBandList(),
                if (_selectedBandIndex != null) _buildBandEditor(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final latencyMs = (_latencySamples / 48000 * 1000).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq, color: Color(0xFF40FF90), size: 20),
          const SizedBox(width: 8),
          const Text(
            'LINEAR PHASE EQ',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'LATENCY: $latencyMs ms',
              style: const TextStyle(
                color: Color(0xFFFFFF40),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          _buildBypassButton(),
        ],
      ),
    );
  }

  Widget _buildBypassButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _bypassed = !_bypassed);
        _ffi.linearPhaseEqSetBypass(widget.trackId, _bypassed);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _bypassed
              ? FluxForgeTheme.accentRed.withValues(alpha: 0.3)
              : FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _bypassed ? FluxForgeTheme.accentRed : FluxForgeTheme.accentGreen,
          ),
        ),
        child: Text(
          _bypassed ? 'BYPASS' : 'ACTIVE',
          style: TextStyle(
            color: _bypassed ? FluxForgeTheme.accentRed : FluxForgeTheme.accentGreen,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEqGraph() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _LinearPhaseEqCurvePainter(
          bands: _bands,
          selectedIndex: _selectedBandIndex,
          bypassed: _bypassed,
        ),
        child: GestureDetector(
          onTapDown: (details) {
            _handleGraphTap(details.localPosition, context);
          },
        ),
      ),
    );
  }

  void _handleGraphTap(Offset position, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final size = box.size;
    final freq = _posToFreq(position.dx / size.width);

    // Show add band dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: Text(
          'Add Band at ${freq.toInt()} Hz',
          style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 16),
        ),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: LinearPhaseFilterType.values.map((type) {
            return ActionChip(
              label: Text(_filterTypeName(type)),
              backgroundColor: FluxForgeTheme.borderSubtle,
              labelStyle: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
              onPressed: () {
                Navigator.pop(ctx);
                _addBand(type, freq);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  double _posToFreq(double normalized) {
    const minLog = 1.301; // log10(20)
    const maxLog = 4.301; // log10(20000)
    final logFreq = minLog + normalized * (maxLog - minLog);
    return math.pow(10, logFreq).toDouble().clamp(20.0, 20000.0);
  }

  String _filterTypeName(LinearPhaseFilterType type) {
    return switch (type) {
      LinearPhaseFilterType.bell => 'Bell',
      LinearPhaseFilterType.lowShelf => 'Low Shelf',
      LinearPhaseFilterType.highShelf => 'High Shelf',
      LinearPhaseFilterType.lowCut => 'Low Cut',
      LinearPhaseFilterType.highCut => 'High Cut',
      LinearPhaseFilterType.notch => 'Notch',
      LinearPhaseFilterType.bandpass => 'Bandpass',
      LinearPhaseFilterType.tilt => 'Tilt',
    };
  }

  Widget _buildBandList() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text(
            'BANDS:',
            style: TextStyle(
              color: Color(0xFF606070),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _bands.length,
              itemBuilder: (context, index) => _buildBandChip(index),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF40FF90), size: 20),
            onPressed: () => _addBand(LinearPhaseFilterType.bell, 1000.0),
            tooltip: 'Add Band',
          ),
        ],
      ),
    );
  }

  Widget _buildBandChip(int index) {
    final band = _bands[index];
    final isSelected = index == _selectedBandIndex;
    final color = _getBandColor(band.type);

    return GestureDetector(
      onTap: () => setState(() => _selectedBandIndex = index),
      onLongPress: () => _removeBand(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${band.freq.toInt()} Hz',
              style: TextStyle(
                color: isSelected ? FluxForgeTheme.textPrimary : color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)}',
              style: TextStyle(
                color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBandColor(LinearPhaseFilterType type) {
    return switch (type) {
      LinearPhaseFilterType.bell => FluxForgeTheme.accentCyan,
      LinearPhaseFilterType.lowShelf => FluxForgeTheme.accentOrange,
      LinearPhaseFilterType.highShelf => FluxForgeTheme.accentYellow,
      LinearPhaseFilterType.lowCut => FluxForgeTheme.accentRed,
      LinearPhaseFilterType.highCut => FluxForgeTheme.accentRed,
      LinearPhaseFilterType.notch => FluxForgeTheme.accentPink,
      LinearPhaseFilterType.bandpass => FluxForgeTheme.accentGreen,
      LinearPhaseFilterType.tilt => FluxForgeTheme.accentCyan,
    };
  }

  Widget _buildBandEditor() {
    if (_selectedBandIndex == null || _selectedBandIndex! >= _bands.length) {
      return const SizedBox();
    }

    final band = _bands[_selectedBandIndex!];
    final color = _getBandColor(band.type);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(top: BorderSide(color: Color(0xFF2A2A30))),
      ),
      child: Column(
        children: [
          // Filter type selector
          Row(
            children: [
              const Text('TYPE:', style: TextStyle(color: Color(0xFF606070), fontSize: 10)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: LinearPhaseFilterType.values.map((type) {
                      final isSelected = type == band.type;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => band.type = type);
                            _updateBand(_selectedBandIndex!);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? _getBandColor(type) : FluxForgeTheme.bgMid,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _getBandColor(type)),
                            ),
                            child: Text(
                              _filterTypeName(type),
                              style: TextStyle(
                                color: isSelected ? FluxForgeTheme.textPrimary : _getBandColor(type),
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
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Freq/Gain/Q sliders
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildParameterSlider(
                  'FREQ',
                  band.freq,
                  20,
                  20000,
                  '${band.freq.toInt()} Hz',
                  color,
                  true,
                  (v) {
                    setState(() => band.freq = v);
                    _updateBand(_selectedBandIndex!);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildParameterSlider(
                  'GAIN',
                  band.gain,
                  -24,
                  24,
                  '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB',
                  color,
                  false,
                  (v) {
                    setState(() => band.gain = v);
                    _updateBand(_selectedBandIndex!);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildParameterSlider(
                  'Q',
                  band.q,
                  0.1,
                  18,
                  band.q.toStringAsFixed(2),
                  color,
                  true,
                  (v) {
                    setState(() => band.q = v);
                    _updateBand(_selectedBandIndex!);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParameterSlider(
    String label,
    double value,
    double min,
    double max,
    String display,
    Color color,
    bool logarithmic,
    void Function(double) onChanged,
  ) {
    double sliderValue;
    if (logarithmic && min > 0) {
      sliderValue = (math.log(value) - math.log(min)) / (math.log(max) - math.log(min));
    } else {
      sliderValue = (value - min) / (max - min);
    }

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
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: color,
            inactiveTrackColor: FluxForgeTheme.borderSubtle,
            thumbColor: color,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayColor: color.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: sliderValue.clamp(0.0, 1.0),
            onChanged: (v) {
              double newValue;
              if (logarithmic && min > 0) {
                newValue = math.exp(math.log(min) + v * (math.log(max) - math.log(min)));
              } else {
                newValue = min + v * (max - min);
              }
              onChanged(newValue.clamp(min, max));
            },
          ),
        ),
      ],
    );
  }
}

class _LinearPhaseEqCurvePainter extends CustomPainter {
  final List<LinearPhaseBand> bands;
  final int? selectedIndex;
  final bool bypassed;

  _LinearPhaseEqCurvePainter({
    required this.bands,
    required this.selectedIndex,
    required this.bypassed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw frequency grid
    _drawGrid(canvas, size);

    if (bands.isEmpty || bypassed) return;

    // Draw combined EQ curve
    final curvePath = Path();
    final centerY = size.height / 2;

    for (int i = 0; i <= size.width.toInt(); i++) {
      final x = i.toDouble();
      final freq = _xToFreq(x, size.width);
      double totalGain = 0.0;

      for (final band in bands) {
        if (band.enabled) {
          totalGain += _calculateBandResponse(freq, band);
        }
      }

      final y = centerY - (totalGain / 24) * (size.height / 2);

      if (i == 0) {
        curvePath.moveTo(x, y.clamp(0, size.height));
      } else {
        curvePath.lineTo(x, y.clamp(0, size.height));
      }
    }

    // Fill under curve
    final fillPath = Path.from(curvePath)
      ..lineTo(size.width, centerY)
      ..lineTo(0, centerY)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
          FluxForgeTheme.accentGreen.withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw curve line
    final curvePaint = Paint()
      ..color = FluxForgeTheme.accentGreen
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(curvePath, curvePaint);

    // Draw band markers
    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      final x = _freqToX(band.freq, size.width);
      final y = centerY - (band.gain / 24) * (size.height / 2);

      final isSelected = i == selectedIndex;
      final color = _getBandColor(band.type);

      // Marker circle
      final markerPaint = Paint()..color = color;
      canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), isSelected ? 8 : 6, markerPaint);

      // Selection ring
      if (isSelected) {
        final ringPaint = Paint()
          ..color = FluxForgeTheme.textPrimary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), 10, ringPaint);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..strokeWidth = 1;

    // Frequency lines
    for (final freq in [100.0, 1000.0, 10000.0]) {
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // dB lines
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), gridPaint..color = FluxForgeTheme.borderMedium);

    for (final db in [-12.0, 12.0]) {
      final y = centerY - (db / 24) * (size.height / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint..color = FluxForgeTheme.borderSubtle);
    }
  }

  double _freqToX(double freq, double width) {
    const minLog = 1.301;
    const maxLog = 4.301;
    final logFreq = math.log(freq.clamp(20, 20000)) / math.ln10;
    return ((logFreq - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.301;
    const maxLog = 4.301;
    final logFreq = minLog + (x / width) * (maxLog - minLog);
    return math.pow(10, logFreq).toDouble();
  }

  double _calculateBandResponse(double freq, LinearPhaseBand band) {
    final ratio = freq / band.freq;
    final logRatio = math.log(ratio) / math.ln2;

    return switch (band.type) {
      LinearPhaseFilterType.bell =>
        band.gain * math.exp(-math.pow(logRatio * band.q, 2)),
      LinearPhaseFilterType.lowShelf =>
        band.gain * (1 - 1 / (1 + math.exp(-logRatio * 4))) * 2,
      LinearPhaseFilterType.highShelf =>
        band.gain * (1 / (1 + math.exp(-logRatio * 4))) * 2,
      LinearPhaseFilterType.lowCut =>
        ratio < 1 ? -24 * (1 - ratio) * band.q : 0,
      LinearPhaseFilterType.highCut =>
        ratio > 1 ? -24 * (ratio - 1) * band.q : 0,
      LinearPhaseFilterType.notch =>
        -math.min(24.0, 24 * math.exp(-math.pow(logRatio * band.q * 2, 2))),
      LinearPhaseFilterType.bandpass =>
        math.exp(-math.pow(logRatio * band.q, 2)) * 12 - 6,
      LinearPhaseFilterType.tilt =>
        band.gain * logRatio.clamp(-2.0, 2.0) / 2,
    };
  }

  Color _getBandColor(LinearPhaseFilterType type) {
    return switch (type) {
      LinearPhaseFilterType.bell => FluxForgeTheme.accentCyan,
      LinearPhaseFilterType.lowShelf => FluxForgeTheme.accentOrange,
      LinearPhaseFilterType.highShelf => FluxForgeTheme.accentYellow,
      LinearPhaseFilterType.lowCut => FluxForgeTheme.accentRed,
      LinearPhaseFilterType.highCut => FluxForgeTheme.accentRed,
      LinearPhaseFilterType.notch => FluxForgeTheme.accentPink,
      LinearPhaseFilterType.bandpass => FluxForgeTheme.accentGreen,
      LinearPhaseFilterType.tilt => FluxForgeTheme.accentCyan,
    };
  }

  @override
  bool shouldRepaint(covariant _LinearPhaseEqCurvePainter oldDelegate) {
    return bands != oldDelegate.bands ||
           selectedIndex != oldDelegate.selectedIndex ||
           bypassed != oldDelegate.bypassed;
  }
}
