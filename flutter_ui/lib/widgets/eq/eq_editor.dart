/// EQ Editor Widget
///
/// Professional parametric EQ editor with:
/// - Interactive frequency response curve
/// - Drag-to-edit band nodes
/// - Filter type selection
/// - Frequency/Gain/Q controls per band
/// - GPU-accelerated curve rendering

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../theme/reelforge_theme.dart';

// ============ Types ============

/// EQ filter types matching Rust backend
enum EqFilterType {
  bell,
  lowShelf,
  highShelf,
  lowCut,
  highCut,
  notch,
  bandpass,
  tiltShelf,
  allpass,
}

/// Filter slope for cut filters
enum FilterSlope {
  db6,
  db12,
  db18,
  db24,
  db36,
  db48,
  db72,
  db96,
}

/// Single EQ band state
class EqBandState {
  final int id;
  final bool enabled;
  final EqFilterType filterType;
  final double frequency; // Hz (20-20000)
  final double gain; // dB (-30 to +30)
  final double q; // 0.1 to 30
  final FilterSlope slope;
  final Color color;

  const EqBandState({
    required this.id,
    this.enabled = true,
    this.filterType = EqFilterType.bell,
    this.frequency = 1000,
    this.gain = 0,
    this.q = 1.0,
    this.slope = FilterSlope.db12,
    this.color = ReelForgeTheme.accentBlue,
  });

  EqBandState copyWith({
    int? id,
    bool? enabled,
    EqFilterType? filterType,
    double? frequency,
    double? gain,
    double? q,
    FilterSlope? slope,
    Color? color,
  }) {
    return EqBandState(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      filterType: filterType ?? this.filterType,
      frequency: frequency ?? this.frequency,
      gain: gain ?? this.gain,
      q: q ?? this.q,
      slope: slope ?? this.slope,
      color: color ?? this.color,
    );
  }

  /// Calculate biquad response at frequency
  double responseAt(double freq, double sampleRate) {
    if (!enabled) return 0.0;

    // ignore: unused_local_variable
    final omega = 2.0 * math.pi * frequency / sampleRate;
    // ignore: unused_local_variable
    final targetOmega = 2.0 * math.pi * freq / sampleRate;

    switch (filterType) {
      case EqFilterType.bell:
        return _bellResponse(freq, sampleRate);
      case EqFilterType.lowShelf:
        return _shelfResponse(freq, sampleRate, isLow: true);
      case EqFilterType.highShelf:
        return _shelfResponse(freq, sampleRate, isLow: false);
      case EqFilterType.lowCut:
        return _cutResponse(freq, sampleRate, isLow: true);
      case EqFilterType.highCut:
        return _cutResponse(freq, sampleRate, isLow: false);
      case EqFilterType.notch:
        return _notchResponse(freq, sampleRate);
      default:
        return 0.0;
    }
  }

  double _bellResponse(double freq, double sampleRate) {
    // Simplified bell response approximation
    final ratio = math.log(freq / frequency) / math.log(2);
    final bandwidth = 1.0 / q;
    final x = ratio / bandwidth;
    return gain * math.exp(-x * x * 2);
  }

  double _shelfResponse(double freq, double sampleRate, {required bool isLow}) {
    final ratio = freq / frequency;
    if (isLow) {
      if (ratio < 0.5) return gain;
      if (ratio > 2.0) return 0;
      return gain * (1.0 - (ratio - 0.5) / 1.5);
    } else {
      if (ratio > 2.0) return gain;
      if (ratio < 0.5) return 0;
      return gain * ((ratio - 0.5) / 1.5);
    }
  }

  double _cutResponse(double freq, double sampleRate, {required bool isLow}) {
    final ratio = freq / frequency;
    final slopeDb = _slopeToDb(slope);
    if (isLow) {
      if (ratio >= 1) return 0;
      return -slopeDb * math.log(1 / ratio) / math.log(2);
    } else {
      if (ratio <= 1) return 0;
      return -slopeDb * math.log(ratio) / math.log(2);
    }
  }

  double _notchResponse(double freq, double sampleRate) {
    final ratio = math.log(freq / frequency) / math.log(2);
    final bandwidth = 0.5 / q;
    final x = ratio / bandwidth;
    return -30 * math.exp(-x * x * 4);
  }

  double _slopeToDb(FilterSlope s) {
    switch (s) {
      case FilterSlope.db6: return 6;
      case FilterSlope.db12: return 12;
      case FilterSlope.db18: return 18;
      case FilterSlope.db24: return 24;
      case FilterSlope.db36: return 36;
      case FilterSlope.db48: return 48;
      case FilterSlope.db72: return 72;
      case FilterSlope.db96: return 96;
    }
  }
}

// ============ EQ Editor Widget ============

class EqEditor extends StatefulWidget {
  final List<EqBandState> bands;
  final ValueChanged<List<EqBandState>>? onBandsChanged;
  final int? selectedBandId;
  final ValueChanged<int?>? onBandSelected;
  final double sampleRate;
  final List<double>? spectrumData; // Optional spectrum overlay

  const EqEditor({
    super.key,
    required this.bands,
    this.onBandsChanged,
    this.selectedBandId,
    this.onBandSelected,
    this.sampleRate = 48000,
    this.spectrumData,
  });

  @override
  State<EqEditor> createState() => _EqEditorState();
}

class _EqEditorState extends State<EqEditor> {
  int? _hoveredBandId;
  int? _draggingBandId;
  // ignore: unused_field
  Offset? _dragStart;
  EqBandState? _dragStartState;

  // Grid constants
  static const double minFreq = 20;
  static const double maxFreq = 20000;
  static const double minGain = -30;
  static const double maxGain = 30;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) => _handleHover(event, constraints),
          onExit: (_) => setState(() => _hoveredBandId = null),
          child: GestureDetector(
            onTapDown: (details) => _handleTap(details, constraints),
            onPanStart: (details) => _handleDragStart(details, constraints),
            onPanUpdate: (details) => _handleDragUpdate(details, constraints),
            onPanEnd: (_) => _handleDragEnd(),
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _EqCurvePainter(
                bands: widget.bands,
                selectedBandId: widget.selectedBandId,
                hoveredBandId: _hoveredBandId,
                sampleRate: widget.sampleRate,
                spectrumData: widget.spectrumData,
              ),
            ),
          ),
        );
      },
    );
  }

  double _xToFreq(double x, double width) {
    final t = x / width;
    return minFreq * math.pow(maxFreq / minFreq, t);
  }

  double _freqToX(double freq, double width) {
    return width * math.log(freq / minFreq) / math.log(maxFreq / minFreq);
  }

  double _yToGain(double y, double height) {
    return maxGain - (y / height) * (maxGain - minGain);
  }

  double _gainToY(double gain, double height) {
    return height * (maxGain - gain) / (maxGain - minGain);
  }

  void _handleHover(PointerHoverEvent event, BoxConstraints constraints) {
    final pos = event.localPosition;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;

    // Find band near cursor
    int? nearestId;
    double nearestDist = 20; // 20px threshold

    for (final band in widget.bands) {
      if (!band.enabled) continue;
      final bx = _freqToX(band.frequency, width);
      final by = _gainToY(band.gain, height);
      final dist = math.sqrt(math.pow(pos.dx - bx, 2) + math.pow(pos.dy - by, 2));
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestId = band.id;
      }
    }

    if (nearestId != _hoveredBandId) {
      setState(() => _hoveredBandId = nearestId);
    }
  }

  void _handleTap(TapDownDetails details, BoxConstraints constraints) {
    final pos = details.localPosition;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;

    // Check if tapped on a band
    for (final band in widget.bands) {
      if (!band.enabled) continue;
      final bx = _freqToX(band.frequency, width);
      final by = _gainToY(band.gain, height);
      final dist = math.sqrt(math.pow(pos.dx - bx, 2) + math.pow(pos.dy - by, 2));
      if (dist < 15) {
        widget.onBandSelected?.call(band.id);
        return;
      }
    }

    // Deselect if tapped on empty area
    widget.onBandSelected?.call(null);
  }

  void _handleDragStart(DragStartDetails details, BoxConstraints constraints) {
    if (_hoveredBandId == null) return;

    _draggingBandId = _hoveredBandId;
    _dragStart = details.localPosition;
    _dragStartState = widget.bands.firstWhere((b) => b.id == _draggingBandId);
    widget.onBandSelected?.call(_draggingBandId);
  }

  void _handleDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_draggingBandId == null || _dragStartState == null) return;

    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final pos = details.localPosition;

    // Calculate new frequency and gain
    final newFreq = _xToFreq(pos.dx, width).clamp(minFreq, maxFreq);
    final newGain = _yToGain(pos.dy, height).clamp(minGain, maxGain);

    // Update band
    final newBands = widget.bands.map((band) {
      if (band.id == _draggingBandId) {
        return band.copyWith(frequency: newFreq, gain: newGain);
      }
      return band;
    }).toList();

    widget.onBandsChanged?.call(newBands);
  }

  void _handleDragEnd() {
    _draggingBandId = null;
    _dragStart = null;
    _dragStartState = null;
  }
}

// ============ EQ Curve Painter ============

class _EqCurvePainter extends CustomPainter {
  final List<EqBandState> bands;
  final int? selectedBandId;
  final int? hoveredBandId;
  final double sampleRate;
  final List<double>? spectrumData;

  static const double minFreq = 20;
  static const double maxFreq = 20000;
  static const double minGain = -30;
  static const double maxGain = 30;

  _EqCurvePainter({
    required this.bands,
    this.selectedBandId,
    this.hoveredBandId,
    required this.sampleRate,
    this.spectrumData,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGrid(canvas, size);
    if (spectrumData != null) {
      _drawSpectrum(canvas, size);
    }
    _drawCombinedCurve(canvas, size);
    _drawBandCurves(canvas, size);
    _drawBandNodes(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ReelForgeTheme.bgDeepest
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle.withOpacity(0.3)
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: ReelForgeTheme.textSecondary,
      fontSize: 10,
    );

    // Frequency grid lines (logarithmic)
    final freqs = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
    for (final freq in freqs) {
      final x = _freqToX(freq.toDouble(), size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

      // Label
      final label = freq >= 1000 ? '${freq ~/ 1000}k' : '$freq';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height - 2));
    }

    // Gain grid lines
    final gains = [-24, -18, -12, -6, 0, 6, 12, 18, 24];
    for (final gain in gains) {
      final y = _gainToY(gain.toDouble(), size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

      // 0dB line is brighter
      if (gain == 0) {
        final zeroPaint = Paint()
          ..color = ReelForgeTheme.borderSubtle.withOpacity(0.6)
          ..strokeWidth = 1;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), zeroPaint);
      }

      // Label
      final tp = TextPainter(
        text: TextSpan(text: '${gain}dB', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }
  }

  void _drawSpectrum(Canvas canvas, Size size) {
    if (spectrumData == null || spectrumData!.isEmpty) return;

    final path = Path();
    final paint = Paint()
      ..color = ReelForgeTheme.accentCyan.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    path.moveTo(0, size.height);

    for (int i = 0; i < spectrumData!.length; i++) {
      final x = size.width * i / (spectrumData!.length - 1);
      final db = spectrumData![i];
      final y = _gainToY(db.clamp(minGain, maxGain), size.height);
      if (i == 0) {
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawCombinedCurve(Canvas canvas, Size size) {
    final path = Path();
    final paint = Paint()
      ..color = ReelForgeTheme.textPrimary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const steps = 200;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final freq = minFreq * math.pow(maxFreq / minFreq, t);

      // Sum response from all bands
      double totalGain = 0;
      for (final band in bands) {
        if (band.enabled) {
          totalGain += band.responseAt(freq, sampleRate);
        }
      }

      final x = size.width * t;
      final y = _gainToY(totalGain.clamp(minGain, maxGain), size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Fill under curve
    final fillPath = Path.from(path);
    final zeroY = _gainToY(0, size.height);
    fillPath.lineTo(size.width, zeroY);
    fillPath.lineTo(0, zeroY);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ReelForgeTheme.accentOrange.withOpacity(0.2),
          ReelForgeTheme.accentCyan.withOpacity(0.2),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  }

  void _drawBandCurves(Canvas canvas, Size size) {
    for (final band in bands) {
      if (!band.enabled) continue;
      if (band.id != selectedBandId && band.id != hoveredBandId) continue;

      final path = Path();
      final paint = Paint()
        ..color = band.color.withOpacity(0.5)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      const steps = 100;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final freq = minFreq * math.pow(maxFreq / minFreq, t);
        final gain = band.responseAt(freq, sampleRate);

        final x = size.width * t;
        final y = _gainToY(gain.clamp(minGain, maxGain), size.height);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, paint);
    }
  }

  void _drawBandNodes(Canvas canvas, Size size) {
    for (final band in bands) {
      if (!band.enabled) continue;

      final x = _freqToX(band.frequency, size.width);
      final y = _gainToY(band.gain, size.height);
      final isSelected = band.id == selectedBandId;
      final isHovered = band.id == hoveredBandId;

      // Node size
      final radius = isSelected ? 10.0 : (isHovered ? 8.0 : 6.0);

      // Outer glow for selected
      if (isSelected) {
        final glowPaint = Paint()
          ..color = band.color.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(Offset(x, y), radius + 4, glowPaint);
      }

      // Node fill
      final fillPaint = Paint()
        ..color = band.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), radius, fillPaint);

      // Node border
      final borderPaint = Paint()
        ..color = isSelected ? Colors.white : Colors.white.withOpacity(0.7)
        ..strokeWidth = isSelected ? 2 : 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(x, y), radius, borderPaint);

      // Band number
      if (isSelected || isHovered) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${band.id + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
      }
    }
  }

  double _freqToX(double freq, double width) {
    return width * math.log(freq / minFreq) / math.log(maxFreq / minFreq);
  }

  double _gainToY(double gain, double height) {
    return height * (maxGain - gain) / (maxGain - minGain);
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    return bands != oldDelegate.bands ||
        selectedBandId != oldDelegate.selectedBandId ||
        hoveredBandId != oldDelegate.hoveredBandId ||
        spectrumData != oldDelegate.spectrumData;
  }
}

// ============ EQ Controls Panel ============

class EqControlsPanel extends StatelessWidget {
  final EqBandState? selectedBand;
  final ValueChanged<EqBandState>? onBandChanged;
  final VoidCallback? onAddBand;
  final VoidCallback? onRemoveBand;

  const EqControlsPanel({
    super.key,
    this.selectedBand,
    this.onBandChanged,
    this.onAddBand,
    this.onRemoveBand,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedBand == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Select a band to edit',
            style: TextStyle(color: ReelForgeTheme.textSecondary),
          ),
        ),
      );
    }

    final band = selectedBand!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(top: BorderSide(color: ReelForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Enable toggle
          _buildToggle(
            'ON',
            band.enabled,
            (v) => onBandChanged?.call(band.copyWith(enabled: v)),
          ),
          const SizedBox(width: 16),

          // Filter type
          _buildDropdown<EqFilterType>(
            'Type',
            band.filterType,
            EqFilterType.values,
            (v) => onBandChanged?.call(band.copyWith(filterType: v)),
            (v) => _filterTypeName(v),
          ),
          const SizedBox(width: 16),

          // Frequency
          Expanded(
            child: _buildSlider(
              'Freq',
              band.frequency,
              20,
              20000,
              (v) => onBandChanged?.call(band.copyWith(frequency: v)),
              isLog: true,
              suffix: 'Hz',
            ),
          ),
          const SizedBox(width: 16),

          // Gain
          Expanded(
            child: _buildSlider(
              'Gain',
              band.gain,
              -30,
              30,
              (v) => onBandChanged?.call(band.copyWith(gain: v)),
              suffix: 'dB',
            ),
          ),
          const SizedBox(width: 16),

          // Q
          Expanded(
            child: _buildSlider(
              'Q',
              band.q,
              0.1,
              30,
              (v) => onBandChanged?.call(band.copyWith(q: v)),
              isLog: true,
            ),
          ),
          const SizedBox(width: 16),

          // Remove button
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: ReelForgeTheme.errorRed,
            onPressed: onRemoveBand,
            tooltip: 'Remove band',
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 10)),
        const SizedBox(height: 4),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: ReelForgeTheme.accentBlue,
        ),
      ],
    );
  }

  Widget _buildDropdown<T>(
    String label,
    T value,
    List<T> items,
    ValueChanged<T> onChanged,
    String Function(T) labelBuilder,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 10)),
        const SizedBox(height: 4),
        DropdownButton<T>(
          value: value,
          items: items.map((t) => DropdownMenuItem(
            value: t,
            child: Text(labelBuilder(t), style: const TextStyle(fontSize: 12)),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
          dropdownColor: ReelForgeTheme.bgMid,
          style: TextStyle(color: ReelForgeTheme.textPrimary),
          underline: const SizedBox(),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    bool isLog = false,
    String suffix = '',
  }) {
    final displayValue = isLog
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 10)),
            Text('$displayValue$suffix', style: TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 10)),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: ReelForgeTheme.accentBlue,
            inactiveTrackColor: ReelForgeTheme.borderSubtle,
            thumbColor: ReelForgeTheme.textPrimary,
            overlayColor: ReelForgeTheme.accentBlue.withOpacity(0.2),
            trackHeight: 3,
          ),
          child: Slider(
            value: isLog ? math.log(value) : value,
            min: isLog ? math.log(min) : min,
            max: isLog ? math.log(max) : max,
            onChanged: (v) => onChanged(isLog ? math.exp(v) : v),
          ),
        ),
      ],
    );
  }

  String _filterTypeName(EqFilterType type) {
    switch (type) {
      case EqFilterType.bell: return 'Bell';
      case EqFilterType.lowShelf: return 'Low Shelf';
      case EqFilterType.highShelf: return 'High Shelf';
      case EqFilterType.lowCut: return 'Low Cut';
      case EqFilterType.highCut: return 'High Cut';
      case EqFilterType.notch: return 'Notch';
      case EqFilterType.bandpass: return 'Bandpass';
      case EqFilterType.tiltShelf: return 'Tilt';
      case EqFilterType.allpass: return 'Allpass';
    }
  }
}

// ============ Full EQ Plugin Widget ============

class EqPlugin extends StatefulWidget {
  final String busId;
  final String insertId;

  const EqPlugin({
    super.key,
    required this.busId,
    required this.insertId,
  });

  @override
  State<EqPlugin> createState() => _EqPluginState();
}

class _EqPluginState extends State<EqPlugin> {
  List<EqBandState> _bands = [];
  int? _selectedBandId;
  int _nextBandId = 0;

  // Default band colors
  static const _bandColors = [
    Color(0xFFFF6B6B), // Red
    Color(0xFFFFE66D), // Yellow
    Color(0xFF4ECDC4), // Teal
    Color(0xFF45B7D1), // Blue
    Color(0xFFDDA0DD), // Plum
    Color(0xFF98D8C8), // Mint
    Color(0xFFF7DC6F), // Gold
    Color(0xFFBB8FCE), // Purple
  ];

  @override
  void initState() {
    super.initState();
    // Add some default bands
    _addBand(frequency: 80, filterType: EqFilterType.lowShelf);
    _addBand(frequency: 250);
    _addBand(frequency: 1000);
    _addBand(frequency: 4000);
    _addBand(frequency: 12000, filterType: EqFilterType.highShelf);
  }

  void _addBand({
    double frequency = 1000,
    double gain = 0,
    double q = 1.0,
    EqFilterType filterType = EqFilterType.bell,
  }) {
    final color = _bandColors[_nextBandId % _bandColors.length];
    setState(() {
      _bands.add(EqBandState(
        id: _nextBandId++,
        frequency: frequency,
        gain: gain,
        q: q,
        filterType: filterType,
        color: color,
      ));
    });
  }

  void _removeBand(int id) {
    setState(() {
      _bands.removeWhere((b) => b.id == id);
      if (_selectedBandId == id) {
        _selectedBandId = null;
      }
    });
  }

  void _updateBand(EqBandState band) {
    setState(() {
      _bands = _bands.map((b) => b.id == band.id ? band : b).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgMid,
            border: Border(bottom: BorderSide(color: ReelForgeTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              Text(
                'ReelForge EQ',
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addBand(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Band'),
                style: TextButton.styleFrom(
                  foregroundColor: ReelForgeTheme.accentBlue,
                ),
              ),
            ],
          ),
        ),

        // EQ Editor
        Expanded(
          child: EqEditor(
            bands: _bands,
            onBandsChanged: (bands) => setState(() => _bands = bands),
            selectedBandId: _selectedBandId,
            onBandSelected: (id) => setState(() => _selectedBandId = id),
          ),
        ),

        // Controls Panel
        EqControlsPanel(
          selectedBand: _selectedBandId != null
              ? _bands.firstWhere((b) => b.id == _selectedBandId, orElse: () => _bands.first)
              : null,
          onBandChanged: _updateBand,
          onAddBand: () => _addBand(),
          onRemoveBand: _selectedBandId != null
              ? () => _removeBand(_selectedBandId!)
              : null,
        ),
      ],
    );
  }
}
