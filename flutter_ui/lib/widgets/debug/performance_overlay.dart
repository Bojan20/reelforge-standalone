/// Performance Overlay Widget (P4.13)
///
/// Comprehensive performance monitoring overlay displaying:
/// - FPS counter with histogram
/// - Memory usage (Dart heap)
/// - Audio engine stats (voices, CPU, latency)
/// - GPU/rendering info
///
/// Toggle with Ctrl+Shift+P or from debug menu.
///
/// Created: 2026-01-30

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';
import 'fps_counter.dart';

/// Performance metrics snapshot
class PerformanceMetrics {
  final double fps;
  final double frameTimeMs;
  final double jankPercent;
  final int dartHeapMB;
  final int activeVoices;
  final int maxVoices;
  final double audioLatencyMs;
  final double dspLoadPercent;
  final DateTime timestamp;

  const PerformanceMetrics({
    required this.fps,
    required this.frameTimeMs,
    required this.jankPercent,
    required this.dartHeapMB,
    required this.activeVoices,
    required this.maxVoices,
    required this.audioLatencyMs,
    required this.dspLoadPercent,
    required this.timestamp,
  });

  factory PerformanceMetrics.empty() => PerformanceMetrics(
        fps: 0,
        frameTimeMs: 0,
        jankPercent: 0,
        dartHeapMB: 0,
        activeVoices: 0,
        maxVoices: 48,
        audioLatencyMs: 0,
        dspLoadPercent: 0,
        timestamp: DateTime.now(),
      );
}

/// Performance monitor that collects all metrics
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._();
  static PerformanceMonitor get instance => _instance;

  PerformanceMonitor._();

  Timer? _timer;
  final _controller = StreamController<PerformanceMetrics>.broadcast();
  bool _isRunning = false;

  Stream<PerformanceMetrics> get stream => _controller.stream;
  bool get isRunning => _isRunning;

  void start() {
    if (_isRunning) return;
    _isRunning = true;

    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _collectMetrics();
    });
  }

  void _collectMetrics() {
    try {
      final fpsStats = FpsMonitor.instance.stats;

      // Get audio engine stats via FFI
      int activeVoices = 0;
      int maxVoices = 48;
      double dspLoad = 0;
      double latency = 0;

      try {
        final voiceStats = NativeFFI.instance.getVoicePoolStats();
        activeVoices = voiceStats.activeCount;
        maxVoices = voiceStats.maxVoices;
      } catch (_) { /* ignored */ }

      try {
        dspLoad = NativeFFI.instance.profilerGetCurrentLoad();
      } catch (_) { /* ignored */ }

      try {
        // Use mastering latency as approximate audio latency (in samples)
        final latencySamples = NativeFFI.instance.masteringGetLatency();
        // Convert to ms assuming 48kHz sample rate
        latency = (latencySamples / 48000.0) * 1000.0;
      } catch (_) { /* ignored */ }

      // Get Dart heap usage (approximate)
      final dartHeapMB = _estimateDartHeap();

      final metrics = PerformanceMetrics(
        fps: fpsStats.currentFps,
        frameTimeMs: fpsStats.avgFrameTimeMs,
        jankPercent: fpsStats.jankPercent,
        dartHeapMB: dartHeapMB,
        activeVoices: activeVoices,
        maxVoices: maxVoices,
        audioLatencyMs: latency,
        dspLoadPercent: dspLoad,
        timestamp: DateTime.now(),
      );

      _controller.add(metrics);
    } catch (e) {
      // Ignore errors in metric collection
    }
  }

  int _estimateDartHeap() {
    // Note: Actual heap size requires VM service extensions
    // This is a placeholder that returns 0
    return 0;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Performance Overlay Widget
class PerformanceOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final Alignment alignment;
  final bool showFps;
  final bool showMemory;
  final bool showAudio;
  final bool showHistogram;

  const PerformanceOverlay({
    super.key,
    this.onClose,
    this.alignment = Alignment.topRight,
    this.showFps = true,
    this.showMemory = true,
    this.showAudio = true,
    this.showHistogram = true,
  });

  @override
  State<PerformanceOverlay> createState() => _PerformanceOverlayState();
}

class _PerformanceOverlayState extends State<PerformanceOverlay>
    with SingleTickerProviderStateMixin {
  late StreamSubscription<PerformanceMetrics> _subscription;
  PerformanceMetrics _metrics = PerformanceMetrics.empty();
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    FpsMonitor.instance.start(this);
    PerformanceMonitor.instance.start();
    _subscription = PerformanceMonitor.instance.stream.listen((metrics) {
      if (mounted) {
        setState(() => _metrics = metrics);
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    PerformanceMonitor.instance.stop();
    FpsMonitor.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: _expanded ? 220 : 80,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep.withAlpha(230),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: FluxForgeTheme.borderSubtle,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(60),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                if (_expanded) ...[
                  const Divider(height: 1, color: Color(0xFF2A2A35)),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        if (widget.showFps) _buildFpsSection(),
                        if (widget.showHistogram) ...[
                          const SizedBox(height: 8),
                          _buildHistogram(),
                        ],
                        if (widget.showAudio) ...[
                          const SizedBox(height: 8),
                          _buildAudioSection(),
                        ],
                        if (widget.showMemory) ...[
                          const SizedBox(height: 8),
                          _buildMemorySection(),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.speed,
                  size: 14,
                  color: _getFpsColor(_metrics.fps),
                ),
                const SizedBox(width: 6),
                Text(
                  _expanded ? 'Performance' : '${_metrics.fps.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                if (!_expanded)
                  Text(
                    'fps',
                    style: TextStyle(
                      fontSize: 9,
                      color: FluxForgeTheme.textSecondary,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: FluxForgeTheme.textSecondary,
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFpsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('FRAME RATE'),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildMetricBig(
              _metrics.fps.toStringAsFixed(1),
              'FPS',
              _getFpsColor(_metrics.fps),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildMetricSmall(
                  '${_metrics.frameTimeMs.toStringAsFixed(2)} ms',
                  'frame',
                ),
                _buildMetricSmall(
                  '${_metrics.jankPercent.toStringAsFixed(1)}%',
                  'jank',
                  color: _metrics.jankPercent > 5
                      ? FluxForgeTheme.accentOrange
                      : null,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHistogram() {
    final histogram = FpsMonitor.instance.stats.histogram;
    if (histogram.isEmpty) {
      return const SizedBox(height: 30);
    }

    return SizedBox(
      height: 30,
      child: CustomPaint(
        size: const Size(double.infinity, 30),
        painter: FrameHistogramPainter(
          values: histogram,
          targetMs: 16.67,
        ),
      ),
    );
  }

  Widget _buildAudioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('AUDIO ENGINE'),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildMetricSmall(
              '${_metrics.activeVoices}/${_metrics.maxVoices}',
              'voices',
              color: _metrics.activeVoices > _metrics.maxVoices * 0.8
                  ? FluxForgeTheme.accentOrange
                  : null,
            ),
            _buildMetricSmall(
              '${_metrics.dspLoadPercent.toStringAsFixed(1)}%',
              'DSP',
              color: _metrics.dspLoadPercent > 80
                  ? FluxForgeTheme.accentOrange
                  : null,
            ),
            _buildMetricSmall(
              '${_metrics.audioLatencyMs.toStringAsFixed(1)} ms',
              'latency',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMemorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('MEMORY'),
        const SizedBox(height: 4),
        _buildMetricSmall(
          _metrics.dartHeapMB > 0 ? '${_metrics.dartHeapMB} MB' : 'N/A',
          'heap',
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: FluxForgeTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMetricBig(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'monospace',
            height: 1,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricSmall(String value, String label, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color ?? FluxForgeTheme.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Color _getFpsColor(double fps) {
    if (fps >= 55) return FluxForgeTheme.accentGreen;
    if (fps >= 30) return FluxForgeTheme.accentOrange;
    return const Color(0xFFFF4060);
  }
}

/// Compact performance badge for status bars
class PerformanceBadge extends StatefulWidget {
  final VoidCallback? onTap;

  const PerformanceBadge({super.key, this.onTap});

  @override
  State<PerformanceBadge> createState() => _PerformanceBadgeState();
}

class _PerformanceBadgeState extends State<PerformanceBadge>
    with SingleTickerProviderStateMixin {
  late StreamSubscription<PerformanceMetrics> _subscription;
  PerformanceMetrics _metrics = PerformanceMetrics.empty();

  @override
  void initState() {
    super.initState();
    FpsMonitor.instance.start(this);
    PerformanceMonitor.instance.start();
    _subscription = PerformanceMonitor.instance.stream.listen((metrics) {
      if (mounted) {
        setState(() => _metrics = metrics);
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fpsColor = _metrics.fps >= 55
        ? FluxForgeTheme.accentGreen
        : _metrics.fps >= 30
            ? FluxForgeTheme.accentOrange
            : const Color(0xFFFF4060);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, size: 12, color: fpsColor),
            const SizedBox(width: 4),
            Text(
              '${_metrics.fps.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: fpsColor,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.graphic_eq,
              size: 12,
              color: _metrics.activeVoices > _metrics.maxVoices * 0.8
                  ? FluxForgeTheme.accentOrange
                  : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 2),
            Text(
              '${_metrics.activeVoices}',
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
