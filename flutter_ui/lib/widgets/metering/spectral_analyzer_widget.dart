/// Spectral Analyzer Widget — Pro Tools-Level FFT Display
///
/// Real-time FFT spectrum analyzer with:
/// - 256-bin FFT display (20Hz-20kHz, log scale)
/// - Peak hold per bin with configurable decay
/// - dB scale (-100 to 0)
/// - Multiple display modes (bars, line, fill)
/// - Color gradient (blue → green → yellow → red)
/// - Freeze mode for analysis
/// - GPU-accelerated CustomPainter rendering
///
/// Target: 60fps smooth rendering with < 1ms paint time

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Spectrum display style
enum SpectralDisplayStyle {
  /// Filled bars (default, best for analysis)
  bars,

  /// Line graph (Pro Tools style)
  line,

  /// Filled area under curve
  fill,

  /// LED segment style
  segments,
}

/// Spectral analyzer configuration
@immutable
class SpectralAnalyzerConfig {
  /// Minimum dB value for display
  final double minDb;

  /// Maximum dB value for display
  final double maxDb;

  /// Peak hold time in milliseconds (0 = no hold)
  final int peakHoldMs;

  /// Peak decay rate in dB/second
  final double peakDecayDbPerSec;

  /// Show frequency scale
  final bool showFrequencyScale;

  /// Show dB scale
  final bool showDbScale;

  /// Show grid lines
  final bool showGrid;

  /// Display style
  final SpectralDisplayStyle style;

  /// Smoothing factor (0.0 = none, 1.0 = max)
  final double smoothing;

  const SpectralAnalyzerConfig({
    this.minDb = -90,
    this.maxDb = 0,
    this.peakHoldMs = 1500,
    this.peakDecayDbPerSec = 30,
    this.showFrequencyScale = true,
    this.showDbScale = true,
    this.showGrid = true,
    this.style = SpectralDisplayStyle.bars,
    this.smoothing = 0.7,
  });

  /// Pro Tools style configuration
  static const proTools = SpectralAnalyzerConfig(
    minDb: -90,
    maxDb: 0,
    peakHoldMs: 2000,
    peakDecayDbPerSec: 20,
    showFrequencyScale: true,
    showDbScale: true,
    showGrid: true,
    style: SpectralDisplayStyle.line,
    smoothing: 0.8,
  );

  /// RTA (Real-Time Analyzer) configuration
  static const rta = SpectralAnalyzerConfig(
    minDb: -60,
    maxDb: 0,
    peakHoldMs: 0,
    peakDecayDbPerSec: 0,
    showFrequencyScale: true,
    showDbScale: true,
    showGrid: true,
    style: SpectralDisplayStyle.bars,
    smoothing: 0.5,
  );

  /// Compact display configuration
  static const compact = SpectralAnalyzerConfig(
    minDb: -60,
    maxDb: 0,
    peakHoldMs: 1000,
    peakDecayDbPerSec: 40,
    showFrequencyScale: false,
    showDbScale: false,
    showGrid: false,
    style: SpectralDisplayStyle.fill,
    smoothing: 0.6,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Professional FFT spectrum analyzer widget
class SpectralAnalyzer extends StatefulWidget {
  /// Spectrum magnitude data (256 bins, normalized 0-1 or in dB)
  final Float32List? spectrumData;

  /// Whether input data is in dB (true) or linear (false)
  final bool dataInDb;

  /// Widget width
  final double width;

  /// Widget height
  final double height;

  /// Configuration
  final SpectralAnalyzerConfig config;

  /// Freeze display (for analysis)
  final bool frozen;

  /// Callback when tapped (e.g., toggle freeze)
  final VoidCallback? onTap;

  /// Sample rate for frequency labels (default 44100)
  final double sampleRate;

  const SpectralAnalyzer({
    super.key,
    this.spectrumData,
    this.dataInDb = false,
    this.width = 400,
    this.height = 200,
    this.config = const SpectralAnalyzerConfig(),
    this.frozen = false,
    this.onTap,
    this.sampleRate = 44100,
  });

  @override
  State<SpectralAnalyzer> createState() => _SpectralAnalyzerState();
}

class _SpectralAnalyzerState extends State<SpectralAnalyzer>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  // Smoothed spectrum data
  late Float32List _smoothedSpectrum;
  late Float32List _peakHoldSpectrum;
  late List<DateTime> _peakHoldTimes;

  // Last frame time
  Duration _lastFrameTime = Duration.zero;

  // Number of FFT bins
  static const int _binCount = 256;

  // Standard frequency markers (log scale)
  static const List<double> _frequencyMarkers = [
    20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000,
  ];

  // Standard dB markers
  static const List<double> _dbMarkers = [0, -6, -12, -24, -36, -48, -60, -90];

  @override
  void initState() {
    super.initState();
    _initializeBuffers();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _initializeBuffers() {
    _smoothedSpectrum = Float32List(_binCount);
    _peakHoldSpectrum = Float32List(_binCount);
    _peakHoldTimes = List.filled(_binCount, DateTime.now());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (widget.frozen) return;

    final deltaMs = (elapsed - _lastFrameTime).inMicroseconds / 1000.0;
    _lastFrameTime = elapsed;

    if (deltaMs < 1 || deltaMs > 100) return;

    _updateSpectrum(deltaMs);
    _updatePeakHold(deltaMs);

    if (mounted) setState(() {});
  }

  void _updateSpectrum(double deltaMs) {
    final inputData = widget.spectrumData;
    if (inputData == null || inputData.isEmpty) return;

    final smoothingFactor = widget.config.smoothing;
    final attackCoef = 1.0 - math.exp(-deltaMs / 5.0); // Fast attack
    final releaseCoef = 1.0 - math.exp(-deltaMs / (50.0 / (1.0 - smoothingFactor + 0.1)));

    for (int i = 0; i < _binCount; i++) {
      // Get input value
      double inputDb;
      if (i < inputData.length) {
        if (widget.dataInDb) {
          inputDb = inputData[i];
        } else {
          // Convert linear to dB
          final linear = inputData[i].clamp(0.0, 10.0);
          inputDb = linear > 1e-10 ? 20.0 * math.log(linear) / math.ln10 : -100;
        }
      } else {
        inputDb = -100;
      }

      // Clamp to valid range
      inputDb = inputDb.clamp(widget.config.minDb, widget.config.maxDb);

      // Apply smoothing (attack/release)
      if (inputDb > _smoothedSpectrum[i]) {
        _smoothedSpectrum[i] += (inputDb - _smoothedSpectrum[i]) * attackCoef;
      } else {
        _smoothedSpectrum[i] += (inputDb - _smoothedSpectrum[i]) * releaseCoef;
      }
    }
  }

  void _updatePeakHold(double deltaMs) {
    if (widget.config.peakHoldMs <= 0) return;

    final now = DateTime.now();
    final decayDb = widget.config.peakDecayDbPerSec * deltaMs / 1000.0;

    for (int i = 0; i < _binCount; i++) {
      final current = _smoothedSpectrum[i];

      if (current > _peakHoldSpectrum[i]) {
        _peakHoldSpectrum[i] = current;
        _peakHoldTimes[i] = now;
      } else {
        final holdElapsed = now.difference(_peakHoldTimes[i]).inMilliseconds;
        if (holdElapsed > widget.config.peakHoldMs) {
          _peakHoldSpectrum[i] = math.max(
            widget.config.minDb,
            _peakHoldSpectrum[i] - decayDb,
          );
        }
      }
    }
  }

  double _frequencyToBin(double freq) {
    // Log-scale mapping: 20Hz-20kHz to 0-255
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    final logMin = math.log(minFreq);
    final logMax = math.log(maxFreq);
    final logFreq = math.log(freq.clamp(minFreq, maxFreq));
    return ((logFreq - logMin) / (logMax - logMin) * (_binCount - 1));
  }

  double _binToFrequency(int bin) {
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    final logMin = math.log(minFreq);
    final logMax = math.log(maxFreq);
    final normalized = bin / (_binCount - 1);
    return math.exp(logMin + normalized * (logMax - logMin));
  }

  String _formatFrequency(double freq) {
    if (freq >= 1000) {
      return '${(freq / 1000).toStringAsFixed(freq >= 10000 ? 0 : 1)}k';
    }
    return freq.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Stack(
          children: [
            // Main spectrum display
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  left: widget.config.showDbScale ? 28 : 4,
                  right: 4,
                  top: 4,
                  bottom: widget.config.showFrequencyScale ? 16 : 4,
                ),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SpectralAnalyzerPainter(
                      spectrum: _smoothedSpectrum,
                      peakHold: _peakHoldSpectrum,
                      config: widget.config,
                    ),
                    willChange: !widget.frozen,
                    isComplex: true,
                  ),
                ),
              ),
            ),

            // dB scale (left)
            if (widget.config.showDbScale)
              Positioned(
                left: 0,
                top: 4,
                bottom: widget.config.showFrequencyScale ? 16 : 4,
                width: 26,
                child: _buildDbScale(),
              ),

            // Frequency scale (bottom)
            if (widget.config.showFrequencyScale)
              Positioned(
                left: widget.config.showDbScale ? 28 : 4,
                right: 4,
                bottom: 0,
                height: 14,
                child: _buildFrequencyScale(),
              ),

            // Frozen indicator
            if (widget.frozen)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentOrange.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    'FROZEN',
                    style: FluxForgeTheme.labelTiny.copyWith(
                      color: FluxForgeTheme.accentOrange,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDbScale() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final range = widget.config.maxDb - widget.config.minDb;

        return Stack(
          children: [
            for (final db in _dbMarkers)
              if (db >= widget.config.minDb && db <= widget.config.maxDb)
                Positioned(
                  top: (widget.config.maxDb - db) / range * constraints.maxHeight - 5,
                  left: 0,
                  right: 2,
                  child: Text(
                    db.toInt().toString(),
                    textAlign: TextAlign.right,
                    style: FluxForgeTheme.labelTiny.copyWith(
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildFrequencyScale() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (final freq in _frequencyMarkers)
              Builder(
                builder: (context) {
                  final binPos = _frequencyToBin(freq);
                  final x = (binPos / (_binCount - 1)) * constraints.maxWidth;

                  return Positioned(
                    left: x - 12,
                    width: 24,
                    child: Text(
                      _formatFrequency(freq),
                      textAlign: TextAlign.center,
                      style: FluxForgeTheme.labelTiny.copyWith(
                        color: FluxForgeTheme.textTertiary,
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — GPU Optimized
// ═══════════════════════════════════════════════════════════════════════════

class _SpectralAnalyzerPainter extends CustomPainter {
  final Float32List spectrum;
  final Float32List peakHold;
  final SpectralAnalyzerConfig config;

  // Cached gradient
  static LinearGradient? _cachedGradient;

  _SpectralAnalyzerPainter({
    required this.spectrum,
    required this.peakHold,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRect(rect, Paint()..color = FluxForgeTheme.bgVoid);

    // Grid
    if (config.showGrid) {
      _drawGrid(canvas, size);
    }

    // Spectrum display based on style
    switch (config.style) {
      case SpectralDisplayStyle.bars:
        _drawBars(canvas, size);
        break;
      case SpectralDisplayStyle.line:
        _drawLine(canvas, size);
        break;
      case SpectralDisplayStyle.fill:
        _drawFill(canvas, size);
        break;
      case SpectralDisplayStyle.segments:
        _drawSegments(canvas, size);
        break;
    }

    // Peak hold
    if (config.peakHoldMs > 0) {
      _drawPeakHold(canvas, size);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.textTertiary.withValues(alpha: 0.1)
      ..strokeWidth = 0.5;

    final majorGridPaint = Paint()
      ..color = FluxForgeTheme.textTertiary.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;

    // Horizontal grid lines (dB)
    final dbRange = config.maxDb - config.minDb;
    for (final db in [0, -6, -12, -24, -36, -48, -60, -90]) {
      if (db < config.minDb || db > config.maxDb) continue;
      final y = (config.maxDb - db) / dbRange * size.height;
      final paint = db % 12 == 0 ? majorGridPaint : gridPaint;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical grid lines (frequency) - log scale
    const freqMarkers = [100.0, 1000.0, 10000.0];
    for (final freq in freqMarkers) {
      final x = _frequencyToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorGridPaint);
    }
  }

  void _drawBars(Canvas canvas, Size size) {
    final gradient = _getGradient();
    final barWidth = size.width / spectrum.length;
    final dbRange = config.maxDb - config.minDb;

    for (int i = 0; i < spectrum.length; i++) {
      final db = spectrum[i];
      if (db <= config.minDb) continue;

      final normalized = (db - config.minDb) / dbRange;
      final barHeight = normalized * size.height;

      final x = i * barWidth;
      final barRect = Rect.fromLTWH(
        x,
        size.height - barHeight,
        barWidth - 1,
        barHeight,
      );

      canvas.drawRect(
        barRect,
        Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
  }

  void _drawLine(Canvas canvas, Size size) {
    final path = Path();
    final dbRange = config.maxDb - config.minDb;
    bool started = false;

    for (int i = 0; i < spectrum.length; i++) {
      final db = spectrum[i];
      final normalized = ((db - config.minDb) / dbRange).clamp(0.0, 1.0);
      final x = (i / (spectrum.length - 1)) * size.width;
      final y = size.height * (1 - normalized);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    if (started) {
      // Glow layer
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // Main line
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = _getGradient().createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
  }

  void _drawFill(Canvas canvas, Size size) {
    final path = Path();
    final dbRange = config.maxDb - config.minDb;
    bool started = false;

    path.moveTo(0, size.height);

    for (int i = 0; i < spectrum.length; i++) {
      final db = spectrum[i];
      final normalized = ((db - config.minDb) / dbRange).clamp(0.0, 1.0);
      final x = (i / (spectrum.length - 1)) * size.width;
      final y = size.height * (1 - normalized);

      if (!started) {
        path.lineTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    path.lineTo(size.width, size.height);
    path.close();

    // Fill gradient
    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        FluxForgeTheme.accentCyan.withValues(alpha: 0.6),
        FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
      ],
    );

    canvas.drawPath(
      path,
      Paint()..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Top edge line
    _drawLine(canvas, size);
  }

  void _drawSegments(Canvas canvas, Size size) {
    const segmentsPerBand = 24;
    final bandWidth = size.width / spectrum.length;
    final segmentHeight = size.height / segmentsPerBand;
    final dbRange = config.maxDb - config.minDb;

    for (int i = 0; i < spectrum.length; i++) {
      final db = spectrum[i];
      final normalized = ((db - config.minDb) / dbRange).clamp(0.0, 1.0);
      final activeSegments = (normalized * segmentsPerBand).ceil();

      for (int s = 0; s < segmentsPerBand; s++) {
        final isActive = s < activeSegments;
        final segmentLevel = s / segmentsPerBand;
        final color = _getColorForLevel(segmentLevel);

        final segmentRect = Rect.fromLTWH(
          i * bandWidth + 1,
          size.height - (s + 1) * segmentHeight + 1,
          bandWidth - 2,
          segmentHeight - 2,
        );

        canvas.drawRect(
          segmentRect,
          Paint()..color = isActive ? color : color.withValues(alpha: 0.1),
        );
      }
    }
  }

  void _drawPeakHold(Canvas canvas, Size size) {
    final dbRange = config.maxDb - config.minDb;
    final peakPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < peakHold.length; i++) {
      final db = peakHold[i];
      if (db <= config.minDb) continue;

      final normalized = ((db - config.minDb) / dbRange).clamp(0.0, 1.0);
      final x = (i / (peakHold.length - 1)) * size.width;
      final y = size.height * (1 - normalized);

      canvas.drawCircle(Offset(x, y), 1.5, peakPaint);
    }
  }

  double _frequencyToX(double freq, double width) {
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    final logMin = math.log(minFreq);
    final logMax = math.log(maxFreq);
    final logFreq = math.log(freq.clamp(minFreq, maxFreq));
    return ((logFreq - logMin) / (logMax - logMin)) * width;
  }

  LinearGradient _getGradient() {
    _cachedGradient ??= const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Color(0xFF40C8FF), // Cyan (low)
        Color(0xFF40FF90), // Green
        Color(0xFFFFFF40), // Yellow
        Color(0xFFFF9040), // Orange
        Color(0xFFFF4040), // Red (high)
      ],
      stops: [0.0, 0.35, 0.6, 0.8, 1.0],
    );
    return _cachedGradient!;
  }

  Color _getColorForLevel(double normalized) {
    if (normalized < 0.35) {
      return Color.lerp(
        const Color(0xFF40C8FF),
        const Color(0xFF40FF90),
        normalized / 0.35,
      )!;
    } else if (normalized < 0.6) {
      return Color.lerp(
        const Color(0xFF40FF90),
        const Color(0xFFFFFF40),
        (normalized - 0.35) / 0.25,
      )!;
    } else if (normalized < 0.8) {
      return Color.lerp(
        const Color(0xFFFFFF40),
        const Color(0xFFFF9040),
        (normalized - 0.6) / 0.2,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFFFF9040),
        const Color(0xFFFF4040),
        (normalized - 0.8) / 0.2,
      )!;
    }
  }

  @override
  bool shouldRepaint(_SpectralAnalyzerPainter oldDelegate) {
    return true; // Always repaint for smooth animation
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Convert linear magnitude to dB
double linearToDb(double linear) {
  if (linear <= 0) return -100;
  return 20.0 * math.log(linear) / math.ln10;
}

/// Convert dB to linear magnitude
double dbToLinear(double db) {
  return math.pow(10.0, db / 20.0).toDouble();
}

/// Generate mock spectrum data for testing
Float32List generateMockSpectrum({
  int binCount = 256,
  double noiseFloor = -60,
  double signalLevel = -12,
  double centerFreq = 1000,
  double bandwidth = 2000,
}) {
  final spectrum = Float32List(binCount);
  final random = math.Random();

  for (int i = 0; i < binCount; i++) {
    // Log-scale frequency for this bin
    final freq = 20.0 * math.pow(1000, i / (binCount - 1));

    // Base noise floor
    double level = noiseFloor + random.nextDouble() * 6;

    // Add signal peak around center frequency
    final distance = (freq - centerFreq).abs();
    if (distance < bandwidth) {
      final peakGain = (1.0 - distance / bandwidth) * (signalLevel - noiseFloor);
      level += peakGain;
    }

    spectrum[i] = level.clamp(-100.0, 0.0);
  }

  return spectrum;
}
