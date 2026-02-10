/// P2.2: GPU Spectrum Widget — 60fps at 4K resolution
///
/// Uses fragment shader for hardware-accelerated spectrum rendering.
/// Supports fill, line, bars, and combined modes.

import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// GPU rendering modes
enum GpuSpectrumMode {
  fill,  // 0: Filled area
  line,  // 1: Line only
  bars,  // 2: Bar graph
  both,  // 3: Fill + line
}

/// GPU Spectrum configuration
class GpuSpectrumConfig {
  final GpuSpectrumMode mode;
  final double minDb;
  final double maxDb;
  final double minFreq;
  final double maxFreq;
  final double glow;
  final double barWidth;
  final bool showPeaks;
  final double peakHoldTime;
  final double peakDecayRate;
  final double smoothing;

  const GpuSpectrumConfig({
    this.mode = GpuSpectrumMode.both,
    this.minDb = -60.0,
    this.maxDb = 0.0,
    this.minFreq = 20.0,
    this.maxFreq = 20000.0,
    this.glow = 0.5,
    this.barWidth = 0.8,
    this.showPeaks = true,
    this.peakHoldTime = 1000.0,
    this.peakDecayRate = 0.02,
    this.smoothing = 0.7,
  });

  GpuSpectrumConfig copyWith({
    GpuSpectrumMode? mode,
    double? minDb,
    double? maxDb,
    double? minFreq,
    double? maxFreq,
    double? glow,
    double? barWidth,
    bool? showPeaks,
    double? peakHoldTime,
    double? peakDecayRate,
    double? smoothing,
  }) {
    return GpuSpectrumConfig(
      mode: mode ?? this.mode,
      minDb: minDb ?? this.minDb,
      maxDb: maxDb ?? this.maxDb,
      minFreq: minFreq ?? this.minFreq,
      maxFreq: maxFreq ?? this.maxFreq,
      glow: glow ?? this.glow,
      barWidth: barWidth ?? this.barWidth,
      showPeaks: showPeaks ?? this.showPeaks,
      peakHoldTime: peakHoldTime ?? this.peakHoldTime,
      peakDecayRate: peakDecayRate ?? this.peakDecayRate,
      smoothing: smoothing ?? this.smoothing,
    );
  }
}

/// GPU-accelerated spectrum analyzer widget
class GpuSpectrumWidget extends StatefulWidget {
  /// Spectrum data (FFT magnitudes in dB, typically 128-512 bins)
  final Float32List? data;

  /// Sample rate for frequency calculation
  final double sampleRate;

  /// Configuration
  final GpuSpectrumConfig config;

  /// Called when config changes
  final ValueChanged<GpuSpectrumConfig>? onConfigChanged;

  /// Show controls bar
  final bool showControls;

  const GpuSpectrumWidget({
    super.key,
    this.data,
    this.sampleRate = 44100.0,
    this.config = const GpuSpectrumConfig(),
    this.onConfigChanged,
    this.showControls = true,
  });

  @override
  State<GpuSpectrumWidget> createState() => _GpuSpectrumWidgetState();
}

class _GpuSpectrumWidgetState extends State<GpuSpectrumWidget>
    with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  bool _shaderLoaded = false;
  bool _shaderFailed = false;

  late Ticker _ticker;
  double _time = 0.0;

  // Smoothed values for display
  List<double> _smoothedValues = [];
  List<double> _peakValues = [];
  List<int> _peakTimers = [];

  // Texture for passing data to shader
  ui.Image? _spectrumTexture;

  @override
  void initState() {
    super.initState();
    _loadShader();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _spectrumTexture?.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/spectrum.frag');
      _shader = _program!.fragmentShader();
      if (mounted) {
        setState(() {
          _shaderLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _shaderFailed = true;
        });
      }
    }
  }

  void _onTick(Duration elapsed) {
    _time = elapsed.inMicroseconds / 1000000.0;
    _updateSpectrum();
  }

  void _updateSpectrum() {
    if (widget.data == null || widget.data!.isEmpty) return;

    final inputData = widget.data!;
    final binCount = inputData.length;

    // Initialize arrays if needed
    if (_smoothedValues.length != binCount) {
      _smoothedValues = List.filled(binCount, widget.config.minDb);
      _peakValues = List.filled(binCount, widget.config.minDb);
      _peakTimers = List.filled(binCount, 0);
    }

    // Process each bin
    for (int i = 0; i < binCount; i++) {
      double value = inputData[i];

      // Apply smoothing
      final smoothing = widget.config.smoothing;
      _smoothedValues[i] =
          _smoothedValues[i] * smoothing + value * (1 - smoothing);

      // Update peak hold
      if (_smoothedValues[i] > _peakValues[i]) {
        _peakValues[i] = _smoothedValues[i];
        _peakTimers[i] = (widget.config.peakHoldTime / 16).round();
      } else if (_peakTimers[i] > 0) {
        _peakTimers[i]--;
      } else {
        _peakValues[i] -= widget.config.peakDecayRate *
            (widget.config.maxDb - widget.config.minDb);
        if (_peakValues[i] < widget.config.minDb) {
          _peakValues[i] = widget.config.minDb;
        }
      }
    }

    // Create texture with spectrum and peak data
    _createSpectrumTexture();

    if (mounted) setState(() {});
  }

  void _createSpectrumTexture() {
    if (_smoothedValues.isEmpty) return;

    final width = _smoothedValues.length;
    final pixels = Uint8List(width * 4); // RGBA

    final dbRange = widget.config.maxDb - widget.config.minDb;

    for (int i = 0; i < width; i++) {
      // Normalize values to 0-255 range
      final specNorm = ((_smoothedValues[i] - widget.config.minDb) / dbRange)
          .clamp(0.0, 1.0);
      final peakNorm = ((_peakValues[i] - widget.config.minDb) / dbRange)
          .clamp(0.0, 1.0);

      final offset = i * 4;
      pixels[offset] = (specNorm * 255).round(); // R = spectrum
      pixels[offset + 1] = (peakNorm * 255).round(); // G = peak
      pixels[offset + 2] = 0; // B = unused
      pixels[offset + 3] = 255; // A = full
    }

    // Create image from pixel data
    ui.decodeImageFromPixels(
      pixels,
      width,
      1,
      ui.PixelFormat.rgba8888,
      (image) {
        _spectrumTexture?.dispose();
        _spectrumTexture = image;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          if (widget.showControls) _buildControlsBar(),
          Expanded(
            child: _shaderLoaded && !_shaderFailed
                ? CustomPaint(
                    painter: _GpuSpectrumPainter(
                      shader: _shader!,
                      texture: _spectrumTexture,
                      time: _time,
                      config: widget.config,
                    ),
                    child: Container(),
                  )
                : _shaderFailed
                    ? _buildFallbackRenderer()
                    : const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A35)),
        ),
      ),
      child: Row(
        children: [
          // Mode selector
          _buildModeButton(GpuSpectrumMode.fill, 'Fill', Icons.area_chart),
          _buildModeButton(GpuSpectrumMode.line, 'Line', Icons.show_chart),
          _buildModeButton(GpuSpectrumMode.bars, 'Bars', Icons.bar_chart),
          _buildModeButton(GpuSpectrumMode.both, 'Both', Icons.stacked_line_chart),
          const SizedBox(width: 16),
          // Peak toggle
          _buildToggle(
            'Peaks',
            widget.config.showPeaks,
            (v) => _updateConfig(widget.config.copyWith(showPeaks: v)),
          ),
          const SizedBox(width: 8),
          // Glow slider
          const Text('Glow', style: TextStyle(color: Color(0xFF808090), fontSize: 11)),
          const SizedBox(width: 4),
          SizedBox(
            width: 80,
            child: Slider(
              value: widget.config.glow,
              min: 0,
              max: 1,
              onChanged: (v) => _updateConfig(widget.config.copyWith(glow: v)),
            ),
          ),
          const Spacer(),
          // GPU indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _shaderLoaded ? const Color(0xFF40FF90).withOpacity(0.2) : const Color(0xFFFF4060).withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _shaderLoaded ? 'GPU' : 'CPU',
              style: TextStyle(
                color: _shaderLoaded ? const Color(0xFF40FF90) : const Color(0xFFFF4060),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(GpuSpectrumMode mode, String label, IconData icon) {
    final isSelected = widget.config.mode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => _updateConfig(widget.config.copyWith(mode: mode)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4A9EFF).withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF4A9EFF).withOpacity(0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: isSelected ? const Color(0xFF4A9EFF) : const Color(0xFF808090)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? const Color(0xFF4A9EFF) : const Color(0xFF808090),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: value ? const Color(0xFF4A9EFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: value ? const Color(0xFF4A9EFF) : const Color(0xFF606070)),
            ),
            child: value
                ? const Icon(Icons.check, size: 10, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Color(0xFF808090), fontSize: 11)),
        ],
      ),
    );
  }

  void _updateConfig(GpuSpectrumConfig config) {
    widget.onConfigChanged?.call(config);
    setState(() {});
  }

  Widget _buildFallbackRenderer() {
    // Simple CPU fallback if shader fails
    return CustomPaint(
      painter: _CpuFallbackPainter(
        values: _smoothedValues,
        peaks: _peakValues,
        config: widget.config,
      ),
      child: Container(),
    );
  }
}

/// GPU Spectrum Painter using fragment shader
class _GpuSpectrumPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image? texture;
  final double time;
  final GpuSpectrumConfig config;

  _GpuSpectrumPainter({
    required this.shader,
    required this.texture,
    required this.time,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == null) return;

    // Set uniforms
    shader.setFloat(0, size.width);   // uResolution.x
    shader.setFloat(1, size.height);  // uResolution.y
    shader.setFloat(2, time);         // uTime
    shader.setFloat(3, config.maxDb - config.minDb); // uRange
    shader.setFloat(4, config.minFreq); // uMinFreq
    shader.setFloat(5, config.maxFreq); // uMaxFreq
    shader.setFloat(6, config.glow);    // uGlow
    shader.setFloat(7, config.mode.index.toDouble()); // uMode
    shader.setFloat(8, config.barWidth); // uBarWidth
    shader.setFloat(9, config.showPeaks ? 1.0 : 0.0); // uShowPeaks
    shader.setImageSampler(0, texture!); // uSpectrum

    // Draw with shader
    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GpuSpectrumPainter oldDelegate) {
    return true; // Always repaint for animation
  }
}

/// CPU fallback painter (simplified)
class _CpuFallbackPainter extends CustomPainter {
  final List<double> values;
  final List<double> peaks;
  final GpuSpectrumConfig config;

  _CpuFallbackPainter({
    required this.values,
    required this.peaks,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final dbRange = config.maxDb - config.minDb;
    final barWidth = size.width / values.length;

    // Draw spectrum
    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i * barWidth;
      final normalized = ((values[i] - config.minDb) / dbRange).clamp(0.0, 1.0);
      final y = size.height * (1.0 - normalized);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height),
          Offset(0, 0),
          [const Color(0xFF40FF90), const Color(0xFF4A9EFF)],
        )
        ..style = PaintingStyle.fill,
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4AC8FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(_CpuFallbackPainter oldDelegate) {
    return true;
  }
}
