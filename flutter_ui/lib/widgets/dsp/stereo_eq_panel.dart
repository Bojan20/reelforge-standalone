/// Stereo EQ Panel
///
/// Per-band L/R/M/S EQ processing with:
/// - Band mode selection (Stereo/L/R/Mid/Side)
/// - Bass Mono feature
/// - Stereo width per band
/// - Visual stereo field display

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Stereo EQ Band data
class StereoBand {
  int index;
  MinPhaseFilterType type;
  double freq;
  double gain;
  double q;
  StereoEqBandMode mode;
  bool enabled;

  StereoBand({
    required this.index,
    this.type = MinPhaseFilterType.bell,
    this.freq = 1000.0,
    this.gain = 0.0,
    this.q = 1.0,
    this.mode = StereoEqBandMode.stereo,
    this.enabled = true,
  });
}

/// Stereo EQ Panel Widget
class StereoEqPanel extends StatefulWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const StereoEqPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  State<StereoEqPanel> createState() => _StereoEqPanelState();
}

class _StereoEqPanelState extends State<StereoEqPanel> {
  final _ffi = NativeFFI.instance;
  // ignore: unused_field
  bool _initialized = false;

  final List<StereoBand> _bands = [];
  int? _selectedBandIndex;

  // Bass Mono
  bool _bassMonoEnabled = false;
  double _bassMonoFreq = 120.0;

  // Global M/S mode
  bool _globalMsMode = false;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _ffi.stereoEqRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = _ffi.stereoEqCreate(widget.trackId);
    if (success) {
      setState(() => _initialized = true);
    }
  }

  void _addBand(MinPhaseFilterType type, double freq, StereoEqBandMode mode) {
    if (_bands.length >= 16) return;

    final bandIndex = _ffi.stereoEqAddBand(
      widget.trackId,
      type,
      freq,
      0.0,
      1.0,
      mode,
    );

    if (bandIndex >= 0) {
      setState(() {
        _bands.add(StereoBand(
          index: bandIndex,
          type: type,
          freq: freq,
          mode: mode,
        ));
        _selectedBandIndex = _bands.length - 1;
      });
      widget.onSettingsChanged?.call();
    }
  }

  void _updateBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.stereoEqSetBand(
      widget.trackId,
      band.index,
      band.type,
      band.freq,
      band.gain,
      band.q,
    );
    _ffi.stereoEqSetBandMode(widget.trackId, band.index, band.mode);
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
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _buildEqGraph()),
                      Container(width: 1, color: FluxForgeTheme.borderSubtle),
                      SizedBox(width: 120, child: _buildStereoField()),
                    ],
                  ),
                ),
                const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
                _buildBassMonoSection(),
                const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq, color: FluxForgeTheme.accentOrange, size: 20),
          const SizedBox(width: 8),
          const Text(
            'STEREO EQ',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          _buildMsToggle(),
        ],
      ),
    );
  }

  Widget _buildMsToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => _globalMsMode = !_globalMsMode);
        _ffi.stereoEqSetGlobalMs(widget.trackId, _globalMsMode);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _globalMsMode
              ? FluxForgeTheme.accentPink.withValues(alpha: 0.3)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _globalMsMode ? FluxForgeTheme.accentPink : FluxForgeTheme.borderMedium,
          ),
        ),
        child: Text(
          _globalMsMode ? 'M/S MODE' : 'L/R MODE',
          style: TextStyle(
            color: _globalMsMode ? FluxForgeTheme.accentPink : FluxForgeTheme.textTertiary,
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
      child: CustomPaint(
        painter: _StereoEqCurvePainter(
          bands: _bands,
          selectedIndex: _selectedBandIndex,
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
            const Text('Mode:', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: StereoEqBandMode.values.map((mode) {
                return ActionChip(
                  label: Text(_modeName(mode)),
                  backgroundColor: _getModeColor(mode).withValues(alpha: 0.3),
                  labelStyle: TextStyle(color: _getModeColor(mode), fontSize: 12),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addBand(MinPhaseFilterType.bell, freq, mode);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  double _posToFreq(double normalized) {
    const minLog = 1.301;
    const maxLog = 4.301;
    final logFreq = minLog + normalized * (maxLog - minLog);
    return math.pow(10, logFreq).toDouble().clamp(20.0, 20000.0);
  }

  String _modeName(StereoEqBandMode mode) {
    return switch (mode) {
      StereoEqBandMode.stereo => 'Stereo',
      StereoEqBandMode.leftOnly => 'Left',
      StereoEqBandMode.rightOnly => 'Right',
      StereoEqBandMode.mid => 'Mid',
      StereoEqBandMode.side => 'Side',
    };
  }

  Color _getModeColor(StereoEqBandMode mode) {
    return switch (mode) {
      StereoEqBandMode.stereo => FluxForgeTheme.accentCyan,
      StereoEqBandMode.leftOnly => FluxForgeTheme.accentRed,
      StereoEqBandMode.rightOnly => FluxForgeTheme.accentGreen,
      StereoEqBandMode.mid => FluxForgeTheme.accentYellow,
      StereoEqBandMode.side => FluxForgeTheme.accentPink,
    };
  }

  Widget _buildStereoField() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _StereoFieldPainter(bands: _bands),
      ),
    );
  }

  Widget _buildBassMonoSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() => _bassMonoEnabled = !_bassMonoEnabled);
              _ffi.stereoEqSetBassMonoEnabled(widget.trackId, _bassMonoEnabled);
              widget.onSettingsChanged?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _bassMonoEnabled
                    ? FluxForgeTheme.accentGreen.withValues(alpha: 0.3)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _bassMonoEnabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.borderMedium,
                ),
              ),
              child: Text(
                'BASS MONO',
                style: TextStyle(
                  color: _bassMonoEnabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Text('Crossover:', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: _bassMonoEnabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.borderMedium,
                inactiveTrackColor: FluxForgeTheme.borderSubtle,
                thumbColor: _bassMonoEnabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: _bassMonoFreq,
                min: 20,
                max: 500,
                onChanged: _bassMonoEnabled ? (v) {
                  setState(() => _bassMonoFreq = v);
                  _ffi.stereoEqSetBassMonoFreq(widget.trackId, v);
                  widget.onSettingsChanged?.call();
                } : null,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${_bassMonoFreq.toInt()} Hz',
              style: TextStyle(
                color: _bassMonoEnabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
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
              color: FluxForgeTheme.textTertiary,
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
            icon: const Icon(Icons.add_circle_outline, color: FluxForgeTheme.accentOrange, size: 20),
            onPressed: () => _addBand(MinPhaseFilterType.bell, 1000.0, StereoEqBandMode.stereo),
            tooltip: 'Add Band',
          ),
        ],
      ),
    );
  }

  Widget _buildBandChip(int index) {
    final band = _bands[index];
    final isSelected = index == _selectedBandIndex;
    final color = _getModeColor(band.mode);

    return GestureDetector(
      onTap: () => setState(() => _selectedBandIndex = index),
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
              _modeName(band.mode)[0],
              style: TextStyle(
                color: isSelected ? FluxForgeTheme.textPrimary : color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${band.freq.toInt()} Hz',
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

  Widget _buildBandEditor() {
    if (_selectedBandIndex == null || _selectedBandIndex! >= _bands.length) {
      return const SizedBox();
    }

    final band = _bands[_selectedBandIndex!];
    final color = _getModeColor(band.mode);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          // Mode selector
          Row(
            children: [
              const Text('MODE:', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
              const SizedBox(width: 8),
              for (final mode in StereoEqBandMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => band.mode = mode);
                      _updateBand(_selectedBandIndex!);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: band.mode == mode ? _getModeColor(mode) : FluxForgeTheme.bgMid,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _getModeColor(mode)),
                      ),
                      child: Text(
                        _modeName(mode)[0],
                        style: TextStyle(
                          color: band.mode == mode ? FluxForgeTheme.textPrimary : _getModeColor(mode),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Parameters
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildSlider('FREQ', band.freq, 20, 20000, '${band.freq.toInt()} Hz', color, true, (v) {
                  setState(() => band.freq = v);
                  _updateBand(_selectedBandIndex!);
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSlider('GAIN', band.gain, -24, 24, '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)}', color, false, (v) {
                  setState(() => band.gain = v);
                  _updateBand(_selectedBandIndex!);
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSlider('Q', band.q, 0.1, 18, band.q.toStringAsFixed(2), color, true, (v) {
                  setState(() => band.q = v);
                  _updateBand(_selectedBandIndex!);
                }),
              ),
            ],
          ),
        ],
      ),
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
            Text(label, style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9, fontWeight: FontWeight.bold)),
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

class _StereoEqCurvePainter extends CustomPainter {
  final List<StereoBand> bands;
  final int? selectedIndex;

  _StereoEqCurvePainter({required this.bands, required this.selectedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    if (bands.isEmpty) return;

    final centerY = size.height / 2;

    // Draw curves for each mode
    for (final mode in StereoEqBandMode.values) {
      final modeBands = bands.where((b) => b.mode == mode && b.enabled).toList();
      if (modeBands.isEmpty) continue;

      final path = Path();
      for (int i = 0; i <= size.width.toInt(); i++) {
        final x = i.toDouble();
        final freq = _xToFreq(x, size.width);
        double totalGain = 0.0;

        for (final band in modeBands) {
          totalGain += _calculateBandResponse(freq, band);
        }

        final y = centerY - (totalGain / 24) * (size.height / 2);
        if (i == 0) {
          path.moveTo(x, y.clamp(0, size.height));
        } else {
          path.lineTo(x, y.clamp(0, size.height));
        }
      }

      final color = _getModeColor(mode);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, paint);
    }

    // Draw markers
    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      final x = _freqToX(band.freq, size.width);
      final y = centerY - (band.gain / 24) * (size.height / 2);
      final color = _getModeColor(band.mode);

      canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), i == selectedIndex ? 8 : 6, Paint()..color = color);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()..color = FluxForgeTheme.borderSubtle..strokeWidth = 1;
    for (final freq in [100.0, 1000.0, 10000.0]) {
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint..color = FluxForgeTheme.borderMedium);
  }

  double _freqToX(double freq, double width) {
    const minLog = 1.301;
    const maxLog = 4.301;
    return ((math.log(freq.clamp(20, 20000)) / math.ln10 - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.301;
    const maxLog = 4.301;
    return math.pow(10, minLog + (x / width) * (maxLog - minLog)).toDouble();
  }

  double _calculateBandResponse(double freq, StereoBand band) {
    final ratio = freq / band.freq;
    final logRatio = math.log(ratio) / math.ln2;
    return band.gain * math.exp(-math.pow(logRatio * band.q, 2));
  }

  Color _getModeColor(StereoEqBandMode mode) {
    return switch (mode) {
      StereoEqBandMode.stereo => FluxForgeTheme.accentCyan,
      StereoEqBandMode.leftOnly => FluxForgeTheme.accentRed,
      StereoEqBandMode.rightOnly => FluxForgeTheme.accentGreen,
      StereoEqBandMode.mid => FluxForgeTheme.accentYellow,
      StereoEqBandMode.side => FluxForgeTheme.accentPink,
    };
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _StereoFieldPainter extends CustomPainter {
  final List<StereoBand> bands;

  _StereoFieldPainter({required this.bands});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Draw background circle
    canvas.drawCircle(center, radius, Paint()..color = FluxForgeTheme.bgMid);
    canvas.drawCircle(center, radius, Paint()..color = FluxForgeTheme.borderMedium..style = PaintingStyle.stroke);

    // Draw L/R labels
    const textStyle = TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.bold);
    final lPainter = TextPainter(text: const TextSpan(text: 'L', style: textStyle), textDirection: TextDirection.ltr)..layout();
    final rPainter = TextPainter(text: const TextSpan(text: 'R', style: textStyle), textDirection: TextDirection.ltr)..layout();
    lPainter.paint(canvas, Offset(4, center.dy - 6));
    rPainter.paint(canvas, Offset(size.width - 12, center.dy - 6));

    // Draw band positions
    for (final band in bands) {
      if (!band.enabled) continue;

      final xPos = switch (band.mode) {
        StereoEqBandMode.leftOnly => -0.7,
        StereoEqBandMode.rightOnly => 0.7,
        StereoEqBandMode.mid => 0.0,
        StereoEqBandMode.side => 0.0,
        StereoEqBandMode.stereo => 0.0,
      };

      final yPos = switch (band.mode) {
        StereoEqBandMode.side => -0.5,
        _ => (math.log(band.freq / 20) / math.log(1000)) - 0.5,
      };

      final offset = Offset(
        center.dx + xPos * radius * 0.8,
        center.dy - yPos * radius * 0.6,
      );

      final color = _getModeColor(band.mode);
      canvas.drawCircle(offset, 6, Paint()..color = color);
    }
  }

  Color _getModeColor(StereoEqBandMode mode) {
    return switch (mode) {
      StereoEqBandMode.stereo => FluxForgeTheme.accentCyan,
      StereoEqBandMode.leftOnly => FluxForgeTheme.accentRed,
      StereoEqBandMode.rightOnly => FluxForgeTheme.accentGreen,
      StereoEqBandMode.mid => FluxForgeTheme.accentYellow,
      StereoEqBandMode.side => FluxForgeTheme.accentPink,
    };
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
