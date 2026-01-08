/// Minimum Phase EQ Panel
///
/// Zero-latency EQ using Hilbert transform with:
/// - Up to 32 bands
/// - Magnitude and group delay display
/// - 6 filter types

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';

/// Min Phase Band data
class MinPhaseBand {
  int index;
  MinPhaseFilterType type;
  double freq;
  double gain;
  double q;
  bool enabled;

  MinPhaseBand({
    required this.index,
    this.type = MinPhaseFilterType.bell,
    this.freq = 1000.0,
    this.gain = 0.0,
    this.q = 1.0,
    this.enabled = true,
  });
}

/// Minimum Phase EQ Panel Widget
class MinPhaseEqPanel extends StatefulWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const MinPhaseEqPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  State<MinPhaseEqPanel> createState() => _MinPhaseEqPanelState();
}

class _MinPhaseEqPanelState extends State<MinPhaseEqPanel> {
  final _ffi = NativeFFI.instance;
  // ignore: unused_field
  bool _initialized = false;

  final List<MinPhaseBand> _bands = [];
  int? _selectedBandIndex;
  bool _showGroupDelay = false;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _ffi.minPhaseEqRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = _ffi.minPhaseEqCreate(widget.trackId);
    if (success) {
      setState(() => _initialized = true);
    }
  }

  void _addBand(MinPhaseFilterType type, double freq) {
    if (_bands.length >= 32) return;

    final bandIndex = _ffi.minPhaseEqAddBand(widget.trackId, type, freq, 0.0, 1.0);
    if (bandIndex >= 0) {
      setState(() {
        _bands.add(MinPhaseBand(index: bandIndex, type: type, freq: freq));
        _selectedBandIndex = _bands.length - 1;
      });
      widget.onSettingsChanged?.call();
    }
  }

  void _updateBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.minPhaseEqSetBand(widget.trackId, band.index, band.type, band.freq, band.gain, band.q);
    widget.onSettingsChanged?.call();
  }

  void _removeBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.minPhaseEqRemoveBand(widget.trackId, band.index);
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
        color: const Color(0xFF0A0A0C),
        border: Border.all(color: const Color(0xFF2A2A30)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A30)),
          Expanded(
            child: Column(
              children: [
                Expanded(flex: 2, child: _buildEqGraph()),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.show_chart, color: Color(0xFF40C8FF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'MINIMUM PHASE EQ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'ZERO LATENCY',
              style: TextStyle(
                color: Color(0xFF40FF90),
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          _buildViewToggle(),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showGroupDelay = !_showGroupDelay),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _showGroupDelay
              ? const Color(0xFFFFFF40).withValues(alpha: 0.3)
              : const Color(0xFF1A1A20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _showGroupDelay ? const Color(0xFFFFFF40) : const Color(0xFF3A3A40),
          ),
        ),
        child: Text(
          _showGroupDelay ? 'GROUP DELAY' : 'MAGNITUDE',
          style: TextStyle(
            color: _showGroupDelay ? const Color(0xFFFFFF40) : const Color(0xFF808090),
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
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A30)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            painter: _MinPhaseEqPainter(
              bands: _bands,
              selectedIndex: _selectedBandIndex,
              showGroupDelay: _showGroupDelay,
              ffi: _ffi,
              trackId: widget.trackId,
            ),
            child: GestureDetector(
              onTapDown: (details) => _handleTap(details.localPosition, constraints.biggest),
              onPanStart: _selectedBandIndex != null
                  ? (details) => _handleDrag(details.localPosition, constraints.biggest)
                  : null,
              onPanUpdate: _selectedBandIndex != null
                  ? (details) => _handleDrag(details.localPosition, constraints.biggest)
                  : null,
            ),
          );
        },
      ),
    );
  }

  void _handleTap(Offset position, Size size) {
    // Check if tapping on existing band
    for (int i = 0; i < _bands.length; i++) {
      final band = _bands[i];
      final x = _freqToX(band.freq, size.width);
      final y = size.height / 2 - (band.gain / 24) * (size.height / 2);
      if ((Offset(x, y) - position).distance < 15) {
        setState(() => _selectedBandIndex = i);
        return;
      }
    }

    // Add new band
    final freq = _xToFreq(position.dx, size.width);
    _addBand(MinPhaseFilterType.bell, freq);
  }

  void _handleDrag(Offset position, Size size) {
    if (_selectedBandIndex == null) return;

    final band = _bands[_selectedBandIndex!];
    final newFreq = _xToFreq(position.dx, size.width).clamp(20.0, 20000.0);
    final newGain = ((size.height / 2 - position.dy) / (size.height / 2) * 24).clamp(-24.0, 24.0);

    setState(() {
      band.freq = newFreq;
      band.gain = newGain;
    });
    _updateBand(_selectedBandIndex!);
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

  Widget _buildBandList() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            'BANDS: ${_bands.length}/32',
            style: const TextStyle(
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
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF40C8FF), size: 20),
            onPressed: () => _addBand(MinPhaseFilterType.bell, 1000.0),
          ),
        ],
      ),
    );
  }

  Widget _buildBandChip(int index) {
    final band = _bands[index];
    final isSelected = index == _selectedBandIndex;
    final color = _getFilterColor(band.type);

    return GestureDetector(
      onTap: () => setState(() => _selectedBandIndex = index),
      onLongPress: () => _removeBand(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color : const Color(0xFF1A1A20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color),
        ),
        child: Text(
          '${band.freq.toInt()} Hz',
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _getFilterColor(MinPhaseFilterType type) {
    return switch (type) {
      MinPhaseFilterType.bell => const Color(0xFF40C8FF),
      MinPhaseFilterType.lowShelf => const Color(0xFFFF9040),
      MinPhaseFilterType.highShelf => const Color(0xFFFFFF40),
      MinPhaseFilterType.lowCut => const Color(0xFFFF4040),
      MinPhaseFilterType.highCut => const Color(0xFFFF4040),
      MinPhaseFilterType.notch => const Color(0xFFFF40FF),
    };
  }

  String _filterName(MinPhaseFilterType type) {
    return switch (type) {
      MinPhaseFilterType.bell => 'Bell',
      MinPhaseFilterType.lowShelf => 'Low Shelf',
      MinPhaseFilterType.highShelf => 'High Shelf',
      MinPhaseFilterType.lowCut => 'Low Cut',
      MinPhaseFilterType.highCut => 'High Cut',
      MinPhaseFilterType.notch => 'Notch',
    };
  }

  Widget _buildBandEditor() {
    if (_selectedBandIndex == null || _selectedBandIndex! >= _bands.length) {
      return const SizedBox();
    }

    final band = _bands[_selectedBandIndex!];
    final color = _getFilterColor(band.type);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(top: BorderSide(color: Color(0xFF2A2A30))),
      ),
      child: Column(
        children: [
          // Type selector
          Row(
            children: [
              const Text('TYPE:', style: TextStyle(color: Color(0xFF606070), fontSize: 10)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: MinPhaseFilterType.values.map((type) {
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
                              color: isSelected ? _getFilterColor(type) : const Color(0xFF1A1A20),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _getFilterColor(type)),
                            ),
                            child: Text(
                              _filterName(type),
                              style: TextStyle(
                                color: isSelected ? Colors.white : _getFilterColor(type),
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
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFFF4040), size: 18),
                onPressed: () => _removeBand(_selectedBandIndex!),
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
                child: _buildSlider('GAIN', band.gain, -24, 24, '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB', color, false, (v) {
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
          const SizedBox(height: 8),
          // Enable toggle
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => band.enabled = !band.enabled);
                  _ffi.minPhaseEqSetBandEnabled(widget.trackId, band.index, band.enabled);
                  widget.onSettingsChanged?.call();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: band.enabled
                        ? const Color(0xFF40FF90).withValues(alpha: 0.3)
                        : const Color(0xFF1A1A20),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: band.enabled ? const Color(0xFF40FF90) : const Color(0xFF3A3A40),
                    ),
                  ),
                  child: Text(
                    band.enabled ? 'ENABLED' : 'DISABLED',
                    style: TextStyle(
                      color: band.enabled ? const Color(0xFF40FF90) : const Color(0xFF606070),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
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
            Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 9, fontWeight: FontWeight.bold)),
            Text(display, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: color,
            inactiveTrackColor: const Color(0xFF2A2A30),
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

class _MinPhaseEqPainter extends CustomPainter {
  final List<MinPhaseBand> bands;
  final int? selectedIndex;
  final bool showGroupDelay;
  final NativeFFI ffi;
  final int trackId;

  _MinPhaseEqPainter({
    required this.bands,
    required this.selectedIndex,
    required this.showGroupDelay,
    required this.ffi,
    required this.trackId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    if (bands.isEmpty) return;

    final centerY = size.height / 2;
    final path = Path();

    for (int i = 0; i <= size.width.toInt(); i++) {
      final x = i.toDouble();
      final freq = _xToFreq(x, size.width);

      double value;
      if (showGroupDelay) {
        value = ffi.minPhaseEqGetGroupDelayAt(trackId, freq);
        value = (value / 10).clamp(-1.0, 1.0); // Scale group delay
      } else {
        value = ffi.minPhaseEqGetMagnitudeAt(trackId, freq);
        value = value / 24; // Scale magnitude
      }

      final y = centerY - value * (size.height / 2);

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

    final fillColor = showGroupDelay ? const Color(0xFFFFFF40) : const Color(0xFF40C8FF);
    canvas.drawPath(fillPath, Paint()..color = fillColor.withValues(alpha: 0.1));
    canvas.drawPath(path, Paint()
      ..color = fillColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);

    // Band markers
    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      if (!band.enabled) continue;

      final x = _freqToX(band.freq, size.width);
      final y = centerY - (band.gain / 24) * (size.height / 2);
      final color = _getFilterColor(band.type);

      canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), i == selectedIndex ? 10 : 7, Paint()..color = color);
      if (i == selectedIndex) {
        canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), 12, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2A2A30)..strokeWidth = 1;
    for (final freq in [100.0, 1000.0, 10000.0]) {
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint..color = const Color(0xFF3A3A40));
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

  Color _getFilterColor(MinPhaseFilterType type) {
    return switch (type) {
      MinPhaseFilterType.bell => const Color(0xFF40C8FF),
      MinPhaseFilterType.lowShelf => const Color(0xFFFF9040),
      MinPhaseFilterType.highShelf => const Color(0xFFFFFF40),
      MinPhaseFilterType.lowCut => const Color(0xFFFF4040),
      MinPhaseFilterType.highCut => const Color(0xFFFF4040),
      MinPhaseFilterType.notch => const Color(0xFFFF40FF),
    };
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
