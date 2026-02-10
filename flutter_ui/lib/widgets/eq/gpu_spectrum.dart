import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:typed_data';

/// GPU-accelerated spectrum analyzer using Flutter fragment shaders
class GpuSpectrum extends StatefulWidget {
  final List<double>? spectrumData;  // 512 bins, -90 to 0 dB
  final double width;
  final double height;
  final double dbRange;  // e.g., 60 for -60 to 0 dB display
  final double glow;     // 0.0 to 1.0

  const GpuSpectrum({
    super.key,
    this.spectrumData,
    required this.width,
    required this.height,
    this.dbRange = 60.0,
    this.glow = 0.5,
  });

  @override
  State<GpuSpectrum> createState() => _GpuSpectrumState();
}

class _GpuSpectrumState extends State<GpuSpectrum> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  ui.Image? _spectrumTexture;
  bool _shaderLoaded = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/spectrum.frag');
      _shader = _program!.fragmentShader();
      setState(() {
        _shaderLoaded = true;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
      });
    }
  }

  @override
  void didUpdateWidget(GpuSpectrum oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spectrumData != oldWidget.spectrumData) {
      _updateSpectrumTexture();
    }
  }

  /// Convert spectrum data to 1D texture
  Future<void> _updateSpectrumTexture() async {
    if (widget.spectrumData == null || widget.spectrumData!.isEmpty) return;

    final data = widget.spectrumData!;
    final width = data.length;

    // Create RGBA pixel data (using R channel for spectrum value)
    final pixels = Uint8List(width * 4);

    for (int i = 0; i < width; i++) {
      // Normalize dB value to 0-1 range
      // Input is dB (-90 to 0), output is 0-1
      final db = data[i].clamp(-widget.dbRange, 0.0);
      final normalized = (db + widget.dbRange) / widget.dbRange;
      final value = (normalized * 255).round().clamp(0, 255);

      final offset = i * 4;
      pixels[offset] = value;     // R - spectrum value
      pixels[offset + 1] = value; // G
      pixels[offset + 2] = value; // B
      pixels[offset + 3] = 255;   // A
    }

    // Create image from pixels
    final completer = ui.ImmutableBuffer.fromUint8List(pixels);
    final buffer = await completer;

    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
    );

    final image = await descriptor.instantiateCodec();
    final frame = await image.getNextFrame();

    if (mounted) {
      setState(() {
        _spectrumTexture = frame.image;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fallback to CPU rendering if shader not available
    if (!_shaderLoaded || _shader == null) {
      if (_loadError != null) {
        // Show error but still render CPU fallback
        return _buildCpuFallback();
      }
      return const SizedBox(); // Loading
    }

    // Update texture if needed
    if (widget.spectrumData != null && _spectrumTexture == null) {
      _updateSpectrumTexture();
      return _buildCpuFallback(); // Show CPU while texture loads
    }

    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _GpuSpectrumPainter(
        shader: _shader!,
        spectrumTexture: _spectrumTexture,
        dbRange: widget.dbRange,
        glow: widget.glow,
      ),
    );
  }

  Widget _buildCpuFallback() {
    // Simple CPU-based spectrum for fallback
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _CpuSpectrumPainter(
        spectrum: widget.spectrumData,
        dbRange: widget.dbRange,
      ),
    );
  }

  @override
  void dispose() {
    _spectrumTexture?.dispose();
    super.dispose();
  }
}

/// GPU-accelerated spectrum painter using fragment shader
class _GpuSpectrumPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image? spectrumTexture;
  final double dbRange;
  final double glow;

  _GpuSpectrumPainter({
    required this.shader,
    this.spectrumTexture,
    required this.dbRange,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrumTexture == null) return;

    // Set uniforms
    shader.setFloat(0, size.width);   // uResolution.x
    shader.setFloat(1, size.height);  // uResolution.y
    shader.setFloat(2, dbRange);      // uRange
    shader.setFloat(3, glow);         // uGlow
    shader.setImageSampler(0, spectrumTexture!); // uSpectrum

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GpuSpectrumPainter oldDelegate) {
    return spectrumTexture != oldDelegate.spectrumTexture ||
           dbRange != oldDelegate.dbRange ||
           glow != oldDelegate.glow;
  }
}

/// CPU fallback spectrum painter
class _CpuSpectrumPainter extends CustomPainter {
  final List<double>? spectrum;
  final double dbRange;

  _CpuSpectrumPainter({
    this.spectrum,
    required this.dbRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (spectrum == null || spectrum!.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final n = spectrum!.length;

    // Colors
    const fillColor = Color(0x804a9eff);
    const lineColor = Color(0xCC4ac8ff);

    // Build path
    final fillPath = Path();
    final linePath = Path();

    fillPath.moveTo(0, h);
    linePath.moveTo(0, h);

    for (int i = 0; i < n; i++) {
      final x = i / (n - 1) * w;
      final db = spectrum![i].clamp(-dbRange, 0.0);
      final normalized = (db + dbRange) / dbRange;
      final y = h * (1 - normalized);

      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(w, h);
    fillPath.close();

    // Draw fill
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // Draw line
    canvas.drawPath(linePath, Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _CpuSpectrumPainter oldDelegate) {
    return spectrum != oldDelegate.spectrum;
  }
}
