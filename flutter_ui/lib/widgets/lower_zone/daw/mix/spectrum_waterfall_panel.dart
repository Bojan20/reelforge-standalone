/// Spectrum Waterfall Panel (P3.3) — Scrolling waterfall/spectrogram display
///
/// Shows frequency spectrum over time with configurable:
/// - Waterfall vs Spectrogram view modes
/// - History length (1-10 seconds)
/// - Color gradients (heat, ice, rainbow, etc.)
/// - Frequency range and resolution
///
/// Created: 2026-01-29
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../theme/fluxforge_theme.dart';
import '../../../spectrum/spectrum_analyzer.dart';

/// History length presets (in seconds)
enum WaterfallHistoryLength {
  sec1(1, '1s', 60),    // 60 frames @ 60fps
  sec2(2, '2s', 120),
  sec3(3, '3s', 180),
  sec5(5, '5s', 300),
  sec10(10, '10s', 600);

  final int seconds;
  final String label;
  final int frames;
  const WaterfallHistoryLength(this.seconds, this.label, this.frames);
}

/// Waterfall display mode
enum WaterfallDisplayMode {
  waterfall('Waterfall', Icons.water_drop),
  spectrogram('Spectrogram', Icons.equalizer);

  final String label;
  final IconData icon;
  const WaterfallDisplayMode(this.label, this.icon);
}

/// Color gradient presets for waterfall
enum WaterfallColorGradient {
  heat('Heat', [Color(0xFF000020), Color(0xFF0040FF), Color(0xFF00FF80), Color(0xFFFFFF00), Color(0xFFFF4040)]),
  ice('Ice', [Color(0xFF000020), Color(0xFF2040FF), Color(0xFF40D0FF), Color(0xFFFFFFFF)]),
  magma('Magma', [Color(0xFF000000), Color(0xFF600000), Color(0xFFFF2000), Color(0xFFFFFF00)]),
  viridis('Viridis', [Color(0xFF440154), Color(0xFF3B528B), Color(0xFF21918C), Color(0xFF5DC863), Color(0xFFFDE725)]),
  mono('Mono', [Color(0xFF000000), Color(0xFF40C8FF), Color(0xFFFFFFFF)]);

  final String label;
  final List<Color> colors;
  const WaterfallColorGradient(this.label, this.colors);
}

/// Compact spectrum waterfall panel for DAW Lower Zone MIX tab
class SpectrumWaterfallPanel extends StatefulWidget {
  final double? width;
  final double? height;

  const SpectrumWaterfallPanel({
    super.key,
    this.width,
    this.height,
  });

  @override
  State<SpectrumWaterfallPanel> createState() => _SpectrumWaterfallPanelState();
}

class _SpectrumWaterfallPanelState extends State<SpectrumWaterfallPanel>
    with SingleTickerProviderStateMixin {
  // Configuration
  WaterfallDisplayMode _displayMode = WaterfallDisplayMode.waterfall;
  WaterfallHistoryLength _historyLength = WaterfallHistoryLength.sec3;
  WaterfallColorGradient _colorGradient = WaterfallColorGradient.heat;
  SpectrumColorScheme _spectrumColorScheme = SpectrumColorScheme.heat;

  // Display options
  bool _showFreqLabels = true;
  bool _showDbScale = true;
  bool _showGrid = false;
  bool _isPaused = false;

  // FFT configuration
  FftSizeOption _fftSize = FftSizeOption.fft4096;
  double _minFreq = 20.0;
  double _maxFreq = 20000.0;
  double _minDb = -90.0;
  double _maxDb = 6.0;

  // Animation
  late AnimationController _controller;
  Timer? _demoTimer;

  // Demo data (until FFI is connected)
  Float64List? _spectrumData;
  final math.Random _random = math.Random();

  // Waterfall history
  final List<Float64List> _history = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    _controller.repeat();

    // Demo mode: generate test data until FFI is connected
    // TODO: Replace with real FFI data from PLAYBACK_ENGINE
    _startDemoMode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _demoTimer?.cancel();
    super.dispose();
  }

  void _startDemoMode() {
    // Generate initial spectrum with realistic shape
    _spectrumData = Float64List(256);
    _generateDemoSpectrum();

    // Update demo data at ~30fps
    _demoTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_isPaused) {
        _generateDemoSpectrum();
      }
    });
  }

  void _generateDemoSpectrum() {
    if (_spectrumData == null) return;

    final data = _spectrumData!;
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;

    for (int i = 0; i < data.length; i++) {
      // Base level drops off at high frequencies
      final freq = _binToFreq(i, data.length);
      final rolloff = -12.0 * math.log(freq / 100 + 1) / math.ln10;

      // Add some harmonic content
      double level = rolloff;

      // Bass bump
      if (freq < 100) {
        level += 6.0 * math.sin(time * 2);
      }

      // Mid presence
      if (freq > 300 && freq < 3000) {
        level += 3.0 * math.sin(time * 3 + i * 0.1);
      }

      // Add noise
      level += (_random.nextDouble() - 0.5) * 6;

      // Clamp to valid dB range
      data[i] = level.clamp(_minDb, _maxDb);
    }

    setState(() {});
  }

  double _binToFreq(int bin, int binCount) {
    final t = bin / (binCount - 1);
    return _minFreq * math.pow(_maxFreq / _minFreq, t);
  }

  void _onTick() {
    if (_isPaused || _spectrumData == null) return;

    // Add current spectrum to history
    _history.insert(0, Float64List.fromList(_spectrumData!));

    // Limit history based on selected duration
    final maxHistory = _historyLength.frames;
    while (_history.length > maxHistory) {
      _history.removeLast();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Controls bar
          _buildControlsBar(),

          // Waterfall display
          Expanded(
            child: _buildWaterfallDisplay(),
          ),

          // Info bar
          _buildInfoBar(),
        ],
      ),
    );
  }

  Widget _buildControlsBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Display mode toggle
          _buildModeToggle(),

          const SizedBox(width: 8),

          // History length
          _buildDropdown<WaterfallHistoryLength>(
            value: _historyLength,
            items: WaterfallHistoryLength.values,
            labelBuilder: (h) => h.label,
            tooltip: 'History Length',
            onChanged: (v) => setState(() => _historyLength = v),
          ),

          const SizedBox(width: 8),

          // Color gradient
          _buildDropdown<WaterfallColorGradient>(
            value: _colorGradient,
            items: WaterfallColorGradient.values,
            labelBuilder: (c) => c.label,
            tooltip: 'Color Gradient',
            onChanged: (v) {
              setState(() {
                _colorGradient = v;
                // Map to spectrum color scheme
                _spectrumColorScheme = _mapGradientToScheme(v);
              });
            },
          ),

          const Spacer(),

          // Toggle buttons
          _buildToggleButton(
            icon: Icons.grid_on,
            isActive: _showGrid,
            tooltip: 'Show Grid',
            onTap: () => setState(() => _showGrid = !_showGrid),
          ),
          _buildToggleButton(
            icon: Icons.straighten,
            isActive: _showFreqLabels,
            tooltip: 'Frequency Labels',
            onTap: () => setState(() => _showFreqLabels = !_showFreqLabels),
          ),
          _buildToggleButton(
            icon: Icons.format_list_numbered,
            isActive: _showDbScale,
            tooltip: 'dB Scale',
            onTap: () => setState(() => _showDbScale = !_showDbScale),
          ),
          _buildToggleButton(
            icon: _isPaused ? Icons.play_arrow : Icons.pause,
            isActive: _isPaused,
            tooltip: _isPaused ? 'Resume' : 'Pause',
            onTap: () => setState(() => _isPaused = !_isPaused),
          ),

          const SizedBox(width: 8),

          // FFT size
          _buildDropdown<FftSizeOption>(
            value: _fftSize,
            items: FftSizeOption.values,
            labelBuilder: (f) => '${f.size}',
            tooltip: 'FFT Size',
            onChanged: (v) => setState(() => _fftSize = v),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: WaterfallDisplayMode.values.map((mode) {
          final isSelected = mode == _displayMode;
          return InkWell(
            onTap: () => setState(() => _displayMode = mode),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? FluxForgeTheme.accentBlue.withAlpha(77) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    mode.icon,
                    size: 12,
                    color: isSelected ? FluxForgeTheme.accentBlue : Colors.white54,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? FluxForgeTheme.accentBlue : Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required String tooltip,
    required ValueChanged<T> onChanged,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            dropdownColor: FluxForgeTheme.bgMid,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
            items: items.map((e) => DropdownMenuItem(
              value: e,
              child: Text(labelBuilder(e)),
            )).toList(),
            onChanged: (v) => onChanged(v as T),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive ? FluxForgeTheme.accentBlue.withAlpha(77) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 14,
            color: isActive ? FluxForgeTheme.accentBlue : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _buildWaterfallDisplay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        if (_history.isEmpty) {
          return Center(
            child: Text(
              'Awaiting spectrum data...',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          );
        }

        return CustomPaint(
          size: Size(width, height),
          painter: _WaterfallDisplayPainter(
            history: _history,
            displayMode: _displayMode,
            colorGradient: _colorGradient,
            minDb: _minDb,
            maxDb: _maxDb,
            minFreq: _minFreq,
            maxFreq: _maxFreq,
            showGrid: _showGrid,
            showFreqLabels: _showFreqLabels,
            showDbScale: _showDbScale,
          ),
        );
      },
    );
  }

  Widget _buildInfoBar() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            '${_history.length} frames',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),

          const SizedBox(width: 12),

          Text(
            '${_minFreq.toInt()} Hz - ${(_maxFreq / 1000).toStringAsFixed(0)} kHz',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),

          const Spacer(),

          if (_isPaused)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(51),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text(
                'PAUSED',
                style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold),
              ),
            ),

          const SizedBox(width: 8),

          // Demo mode indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.cyan.withAlpha(51),
              borderRadius: BorderRadius.circular(2),
            ),
            child: const Text(
              'DEMO',
              style: TextStyle(color: Colors.cyan, fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  SpectrumColorScheme _mapGradientToScheme(WaterfallColorGradient gradient) {
    switch (gradient) {
      case WaterfallColorGradient.heat:
        return SpectrumColorScheme.heat;
      case WaterfallColorGradient.ice:
        return SpectrumColorScheme.ice;
      case WaterfallColorGradient.magma:
        return SpectrumColorScheme.heat;
      case WaterfallColorGradient.viridis:
        return SpectrumColorScheme.rainbow;
      case WaterfallColorGradient.mono:
        return SpectrumColorScheme.cyan;
    }
  }
}

/// Custom painter for waterfall/spectrogram display
class _WaterfallDisplayPainter extends CustomPainter {
  final List<Float64List> history;
  final WaterfallDisplayMode displayMode;
  final WaterfallColorGradient colorGradient;
  final double minDb;
  final double maxDb;
  final double minFreq;
  final double maxFreq;
  final bool showGrid;
  final bool showFreqLabels;
  final bool showDbScale;

  _WaterfallDisplayPainter({
    required this.history,
    required this.displayMode,
    required this.colorGradient,
    required this.minDb,
    required this.maxDb,
    required this.minFreq,
    required this.maxFreq,
    required this.showGrid,
    required this.showFreqLabels,
    required this.showDbScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    // Calculate margins
    final leftMargin = showDbScale ? 35.0 : 8.0;
    final bottomMargin = showFreqLabels ? 20.0 : 8.0;
    final topMargin = 8.0;
    final rightMargin = 8.0;

    final plotRect = Rect.fromLTRB(
      leftMargin,
      topMargin,
      size.width - rightMargin,
      size.height - bottomMargin,
    );

    // Background
    canvas.drawRect(
      plotRect,
      Paint()..color = const Color(0xFF0A0A10),
    );

    // Draw grid
    if (showGrid) {
      _drawGrid(canvas, plotRect);
    }

    // Draw waterfall/spectrogram
    canvas.save();
    canvas.clipRect(plotRect);

    if (displayMode == WaterfallDisplayMode.waterfall) {
      _drawWaterfall(canvas, plotRect);
    } else {
      _drawSpectrogram(canvas, plotRect);
    }

    canvas.restore();

    // Draw labels
    if (showDbScale) {
      _drawDbScale(canvas, plotRect);
    }
    if (showFreqLabels) {
      _drawFreqLabels(canvas, plotRect);
    }
  }

  void _drawGrid(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(20)
      ..strokeWidth = 1;

    // Horizontal lines (dB)
    final dbRange = maxDb - minDb;
    final dbStep = dbRange > 40 ? 12.0 : 6.0;
    for (double db = minDb; db <= maxDb; db += dbStep) {
      final y = _dbToY(db, rect);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }

    // Vertical lines (frequency for spectrogram, time for waterfall)
    if (displayMode == WaterfallDisplayMode.spectrogram) {
      // Time markers
      final steps = 5;
      for (int i = 0; i <= steps; i++) {
        final x = rect.left + (i / steps) * rect.width;
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
      }
    } else {
      // Frequency markers
      final freqs = [100.0, 1000.0, 10000.0];
      for (final freq in freqs) {
        if (freq >= minFreq && freq <= maxFreq) {
          final x = _freqToX(freq, rect);
          canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
        }
      }
    }
  }

  void _drawWaterfall(Canvas canvas, Rect rect) {
    // Waterfall: newest at bottom, scrolling up
    // Y-axis = time, X-axis = frequency
    final rowHeight = rect.height / history.length;

    for (int row = 0; row < history.length; row++) {
      final data = history[row];
      final y = rect.bottom - (row + 1) * rowHeight;

      for (int bin = 0; bin < data.length - 1; bin++) {
        final t1 = bin / (data.length - 1);
        final t2 = (bin + 1) / (data.length - 1);
        final x1 = rect.left + t1 * rect.width;
        final x2 = rect.left + t2 * rect.width;

        final level = ((data[bin] - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
        final color = _levelToColor(level);

        canvas.drawRect(
          Rect.fromLTRB(x1, y, x2 + 1, y + rowHeight + 1),
          Paint()..color = color,
        );
      }
    }
  }

  void _drawSpectrogram(Canvas canvas, Rect rect) {
    // Spectrogram: time on X-axis, frequency on Y-axis
    // Newest on right
    final colWidth = rect.width / history.length;

    for (int col = 0; col < history.length; col++) {
      final data = history[history.length - 1 - col];
      final x = rect.left + col * colWidth;

      for (int bin = 0; bin < data.length; bin++) {
        final t = bin / (data.length - 1);
        // Low freq at bottom, high at top
        final y = rect.bottom - t * rect.height;
        final binHeight = rect.height / data.length;

        final level = ((data[bin] - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
        final color = _levelToColor(level);

        canvas.drawRect(
          Rect.fromLTWH(x, y - binHeight, colWidth + 1, binHeight + 1),
          Paint()..color = color,
        );
      }
    }
  }

  Color _levelToColor(double level) {
    final colors = colorGradient.colors;
    if (colors.length < 2) return colors.first;

    // Interpolate through color gradient
    final scaledLevel = level * (colors.length - 1);
    final lowerIndex = scaledLevel.floor().clamp(0, colors.length - 2);
    final t = scaledLevel - lowerIndex;

    return Color.lerp(colors[lowerIndex], colors[lowerIndex + 1], t)!;
  }

  void _drawDbScale(Canvas canvas, Rect rect) {
    final textStyle = TextStyle(
      color: Colors.white54,
      fontSize: 9,
    );

    final dbRange = maxDb - minDb;
    final dbStep = dbRange > 40 ? 12.0 : 6.0;

    for (double db = minDb; db <= maxDb; db += dbStep) {
      final y = _dbToY(db, rect);
      final tp = TextPainter(
        text: TextSpan(text: '${db.toInt()}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left - tp.width - 4, y - tp.height / 2));
    }
  }

  void _drawFreqLabels(Canvas canvas, Rect rect) {
    final textStyle = TextStyle(
      color: Colors.white54,
      fontSize: 9,
    );

    if (displayMode == WaterfallDisplayMode.spectrogram) {
      // Time labels for spectrogram
      final tp = TextPainter(
        text: TextSpan(text: 'Time →', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.right - tp.width, rect.bottom + 4));
    } else {
      // Frequency labels for waterfall
      final freqs = [100.0, 1000.0, 10000.0];
      for (final freq in freqs) {
        if (freq >= minFreq && freq <= maxFreq) {
          final x = _freqToX(freq, rect);
          final label = freq >= 1000 ? '${(freq / 1000).toInt()}k' : '${freq.toInt()}';
          final tp = TextPainter(
            text: TextSpan(text: label, style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x - tp.width / 2, rect.bottom + 4));
        }
      }
    }
  }

  double _dbToY(double db, Rect rect) {
    final normalized = (db - minDb) / (maxDb - minDb);
    return rect.bottom - normalized.clamp(0, 1) * rect.height;
  }

  double _freqToX(double freq, Rect rect) {
    final normalized = math.log(freq / minFreq) / math.log(maxFreq / minFreq);
    return rect.left + normalized.clamp(0, 1) * rect.width;
  }

  @override
  bool shouldRepaint(covariant _WaterfallDisplayPainter oldDelegate) {
    return history != oldDelegate.history ||
        displayMode != oldDelegate.displayMode ||
        colorGradient != oldDelegate.colorGradient ||
        showGrid != oldDelegate.showGrid;
  }
}
