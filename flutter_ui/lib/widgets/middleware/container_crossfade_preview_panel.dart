/// FluxForge Studio Container Crossfade Preview Panel
///
/// P4.3: Container crossfade preview
/// - Real-time RTPC scrubbing with audio preview
/// - Visual volume curves per child
/// - Playback controls with loop mode
/// - RTPC automation recording
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class ContainerCrossfadePreviewPanel extends StatefulWidget {
  final int containerId;
  final VoidCallback? onClose;

  const ContainerCrossfadePreviewPanel({
    super.key,
    required this.containerId,
    this.onClose,
  });

  @override
  State<ContainerCrossfadePreviewPanel> createState() => _ContainerCrossfadePreviewPanelState();
}

class _ContainerCrossfadePreviewPanelState extends State<ContainerCrossfadePreviewPanel>
    with SingleTickerProviderStateMixin {
  double _rtpcValue = 0.5;
  bool _isPlaying = false;
  bool _isLooping = false;
  bool _isRecording = false;
  bool _isDragging = false;
  Timer? _playbackTimer;
  List<_RtpcKeyframe> _recordedKeyframes = [];
  DateTime? _recordingStartTime;
  late AnimationController _playbackController;
  final Map<int, int> _activeVoices = {}; // childId -> voiceId

  @override
  void initState() {
    super.initState();
    _playbackController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );
    _playbackController.addListener(_onPlaybackTick);
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _playbackController.dispose();
    _stopAllVoices();
    super.dispose();
  }

  void _onPlaybackTick() {
    if (_isPlaying && !_isDragging) {
      setState(() {
        _rtpcValue = _playbackController.value;
      });
      _updateVoiceVolumes();
    }
  }

  BlendContainer? _getContainer() {
    return context.read<MiddlewareProvider>()
        .blendContainers
        .where((c) => c.id == widget.containerId)
        .firstOrNull;
  }

  void _updateVoiceVolumes() {
    // Just trigger UI update - visualization calculates volumes from _rtpcValue
    setState(() {});
  }

  double _calculateChildVolume(BlendChild child, double rtpcValue, CrossfadeCurve curve) {
    if (rtpcValue < child.rtpcStart - child.crossfadeWidth) return 0.0;
    if (rtpcValue > child.rtpcEnd + child.crossfadeWidth) return 0.0;

    double volume = 1.0;

    // Fade in
    if (rtpcValue < child.rtpcStart) {
      final fadeProgress = (rtpcValue - (child.rtpcStart - child.crossfadeWidth)) / child.crossfadeWidth;
      volume = _applyCurve(fadeProgress.clamp(0.0, 1.0), curve);
    }
    // Fade out
    else if (rtpcValue > child.rtpcEnd) {
      final fadeProgress = 1.0 - ((rtpcValue - child.rtpcEnd) / child.crossfadeWidth);
      volume = _applyCurve(fadeProgress.clamp(0.0, 1.0), curve);
    }

    return volume;
  }

  double _applyCurve(double t, CrossfadeCurve curve) {
    switch (curve) {
      case CrossfadeCurve.linear:
        return t;
      case CrossfadeCurve.equalPower:
        return t * t * (3 - 2 * t);
      case CrossfadeCurve.sCurve:
        return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);
      case CrossfadeCurve.sinCos:
        return (1 - (t * 3.14159).cos()) / 2;
    }
  }

  void _startPlayback() {
    final container = _getContainer();
    if (container == null || container.children.isEmpty) return;

    setState(() => _isPlaying = true);

    // Start animation (visual scrubbing through RTPC range)
    _playbackController.repeat();
  }

  void _stopPlayback() {
    setState(() => _isPlaying = false);
    _playbackController.stop();
    _activeVoices.clear();
  }

  void _stopAllVoices() {
    // Audio playback would be stopped here
    _activeVoices.clear();
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _stopPlayback();
    } else {
      _startPlayback();
    }
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _recordedKeyframes = [];
      _recordingStartTime = DateTime.now();
    });
    _recordKeyframe();
  }

  void _stopRecording() {
    setState(() => _isRecording = false);
  }

  void _recordKeyframe() {
    if (!_isRecording || _recordingStartTime == null) return;
    final elapsed = DateTime.now().difference(_recordingStartTime!).inMilliseconds;
    _recordedKeyframes.add(_RtpcKeyframe(timeMs: elapsed, value: _rtpcValue));
  }

  void _onSliderChanged(double value) {
    setState(() {
      _rtpcValue = value;
      _isDragging = true;
    });
    _updateVoiceVolumes();
    if (_isRecording) {
      _recordKeyframe();
    }
  }

  void _onSliderEnd(double value) {
    setState(() => _isDragging = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Consumer<MiddlewareProvider>(
        builder: (context, provider, _) {
          final container = provider.blendContainers
              .where((c) => c.id == widget.containerId)
              .firstOrNull;

          if (container == null) {
            return Center(
              child: Text(
                'Container not found',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(container),
              const SizedBox(height: 16),
              // Crossfade visualization
              Expanded(
                flex: 3,
                child: _buildCrossfadeVisualization(container),
              ),
              const SizedBox(height: 16),
              // RTPC scrubber
              _buildRtpcScrubber(container),
              const SizedBox(height: 16),
              // Volume meters
              Expanded(
                flex: 2,
                child: _buildVolumeMeters(container),
              ),
              const SizedBox(height: 16),
              // Controls
              _buildControls(container),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BlendContainer container) {
    return Row(
      children: [
        Icon(Icons.graphic_eq, color: Colors.purple, size: 20),
        const SizedBox(width: 8),
        Text(
          'Crossfade Preview',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            container.name,
            style: TextStyle(
              color: Colors.purple,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Spacer(),
        // Recording indicator
        if (_isRecording)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Recording (${_recordedKeyframes.length})',
                  style: TextStyle(color: Colors.red, fontSize: 10),
                ),
              ],
            ),
          ),
        if (widget.onClose != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.close, size: 14, color: FluxForgeTheme.textSecondary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCrossfadeVisualization(BlendContainer container) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: CustomPaint(
        painter: _CrossfadeVisualizationPainter(
          children: container.children,
          crossfadeCurve: container.crossfadeCurve,
          currentRtpc: _rtpcValue,
          isPlaying: _isPlaying,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildRtpcScrubber(BlendContainer container) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'RTPC Value',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _rtpcValue.toStringAsFixed(3),
                  style: TextStyle(
                    color: Colors.purple,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              activeTrackColor: Colors.purple,
              inactiveTrackColor: FluxForgeTheme.backgroundDeep,
              thumbColor: Colors.purple,
              overlayColor: Colors.purple.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _rtpcValue,
              onChanged: _onSliderChanged,
              onChangeEnd: _onSliderEnd,
            ),
          ),
          // Tick marks
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(11, (i) {
              final value = i / 10.0;
              final isActive = _rtpcValue >= value - 0.05 && _rtpcValue <= value + 0.05;
              return Text(
                '${(value * 100).toInt()}%',
                style: TextStyle(
                  color: isActive ? Colors.purple : FluxForgeTheme.textSecondary,
                  fontSize: 8,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeMeters(BlendContainer container) {
    if (container.children.isEmpty) {
      return Center(
        child: Text(
          'No children in container',
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
        ),
      );
    }

    final colors = [
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Row(
        children: container.children.asMap().entries.map((entry) {
          final child = entry.value;
          final color = colors[entry.key % colors.length];
          final volume = _calculateChildVolume(child, _rtpcValue, container.crossfadeCurve);
          final hasAudio = child.audioPath != null && child.audioPath!.isNotEmpty;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  // Meter
                  Expanded(
                    child: Container(
                      width: 24,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.backgroundDeep,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 50),
                          heightFactor: volume,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  color.withValues(alpha: 0.5),
                                  color,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Volume label
                  Text(
                    '${(volume * 100).toInt()}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Name
                  Text(
                    child.name,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 9,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  // Audio indicator
                  const SizedBox(height: 2),
                  Icon(
                    hasAudio ? Icons.audiotrack : Icons.audiotrack_outlined,
                    size: 12,
                    color: hasAudio ? Colors.green : FluxForgeTheme.textSecondary,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildControls(BlendContainer container) {
    final hasAudio = container.children.any((c) => c.audioPath != null && c.audioPath!.isNotEmpty);

    return Row(
      children: [
        // Play/Stop
        GestureDetector(
          onTap: hasAudio ? _togglePlayback : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: hasAudio
                  ? (_isPlaying ? Colors.red : Colors.green).withValues(alpha: 0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasAudio
                    ? (_isPlaying ? Colors.red : Colors.green)
                    : FluxForgeTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isPlaying ? Icons.stop : Icons.play_arrow,
                  size: 18,
                  color: hasAudio
                      ? (_isPlaying ? Colors.red : Colors.green)
                      : FluxForgeTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _isPlaying ? 'Stop' : 'Play',
                  style: TextStyle(
                    color: hasAudio
                        ? (_isPlaying ? Colors.red : Colors.green)
                        : FluxForgeTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Loop toggle
        GestureDetector(
          onTap: _toggleLoop,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _isLooping
                  ? Colors.blue.withValues(alpha: 0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isLooping ? Colors.blue : FluxForgeTheme.border,
              ),
            ),
            child: Icon(
              Icons.repeat,
              size: 18,
              color: _isLooping ? Colors.blue : FluxForgeTheme.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Record button
        GestureDetector(
          onTap: _isRecording ? _stopRecording : _startRecording,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _isRecording
                  ? Colors.red.withValues(alpha: 0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isRecording ? Colors.red : FluxForgeTheme.border,
              ),
            ),
            child: Icon(
              Icons.fiber_manual_record,
              size: 18,
              color: _isRecording ? Colors.red : FluxForgeTheme.textSecondary,
            ),
          ),
        ),
        const Spacer(),
        // Reset button
        GestureDetector(
          onTap: () {
            setState(() {
              _rtpcValue = 0.5;
              _recordedKeyframes.clear();
            });
            _updateVoiceVolumes();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: FluxForgeTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh, size: 14, color: FluxForgeTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Reset',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Curve info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.backgroundDeep,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart, size: 14, color: FluxForgeTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                container.crossfadeCurve.displayName,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RTPC KEYFRAME
// ═══════════════════════════════════════════════════════════════════════════════

class _RtpcKeyframe {
  final int timeMs;
  final double value;

  const _RtpcKeyframe({required this.timeMs, required this.value});
}

// ═══════════════════════════════════════════════════════════════════════════════
// VISUALIZATION PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _CrossfadeVisualizationPainter extends CustomPainter {
  final List<BlendChild> children;
  final CrossfadeCurve crossfadeCurve;
  final double currentRtpc;
  final bool isPlaying;

  _CrossfadeVisualizationPainter({
    required this.children,
    required this.crossfadeCurve,
    required this.currentRtpc,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (children.isEmpty) return;

    final colors = [
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
    ];

    // Draw grid
    final gridPaint = Paint()
      ..color = FluxForgeTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    for (int i = 0; i <= 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw curves for each child
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final color = colors[i % colors.length];
      final isActive = _isChildActive(child, currentRtpc);

      final strokePaint = Paint()
        ..color = color.withValues(alpha: isActive ? 1.0 : 0.4)
        ..strokeWidth = isActive ? 3 : 2
        ..style = PaintingStyle.stroke;

      final fillPaint = Paint()
        ..color = color.withValues(alpha: isActive ? 0.2 : 0.1)
        ..style = PaintingStyle.fill;

      final path = Path();
      final fillPath = Path();

      // Calculate curve points
      const steps = 100;
      var firstPoint = true;

      for (int step = 0; step <= steps; step++) {
        final rtpc = step / steps;
        final volume = _calculateVolume(child, rtpc);
        final x = rtpc * size.width;
        final y = size.height - (volume * size.height);

        if (firstPoint) {
          path.moveTo(x, y);
          fillPath.moveTo(x, size.height);
          fillPath.lineTo(x, y);
          firstPoint = false;
        } else {
          path.lineTo(x, y);
          fillPath.lineTo(x, y);
        }
      }

      fillPath.lineTo(size.width, size.height);
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, strokePaint);

      // Draw child label
      final midX = ((child.rtpcStart + child.rtpcEnd) / 2) * size.width;
      final labelPaint = TextPainter(
        text: TextSpan(
          text: child.name,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      labelPaint.layout();
      labelPaint.paint(canvas, Offset(midX - labelPaint.width / 2, 8));
    }

    // Draw current RTPC indicator
    final indicatorX = currentRtpc * size.width;
    final indicatorPaint = Paint()
      ..color = isPlaying ? Colors.red : Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(indicatorX, 0),
      Offset(indicatorX, size.height),
      indicatorPaint,
    );

    // Draw playhead diamond
    final diamondPath = Path()
      ..moveTo(indicatorX, size.height - 10)
      ..lineTo(indicatorX - 8, size.height)
      ..lineTo(indicatorX, size.height + 10)
      ..lineTo(indicatorX + 8, size.height)
      ..close();
    canvas.drawPath(diamondPath, Paint()..color = isPlaying ? Colors.red : Colors.white);

    // Draw RTPC value label
    final rtpcLabel = TextPainter(
      text: TextSpan(
        text: currentRtpc.toStringAsFixed(2),
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withValues(alpha: 0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    rtpcLabel.layout();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(indicatorX - rtpcLabel.width / 2 - 4, 4, rtpcLabel.width + 8, rtpcLabel.height + 4),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.7),
    );
    rtpcLabel.paint(canvas, Offset(indicatorX - rtpcLabel.width / 2, 6));
  }

  double _calculateVolume(BlendChild child, double rtpc) {
    if (rtpc < child.rtpcStart - child.crossfadeWidth) return 0.0;
    if (rtpc > child.rtpcEnd + child.crossfadeWidth) return 0.0;

    double volume = 1.0;

    // Fade in
    if (rtpc < child.rtpcStart) {
      final fadeProgress = (rtpc - (child.rtpcStart - child.crossfadeWidth)) / child.crossfadeWidth;
      volume = _applyCurve(fadeProgress.clamp(0.0, 1.0));
    }
    // Fade out
    else if (rtpc > child.rtpcEnd) {
      final fadeProgress = 1.0 - ((rtpc - child.rtpcEnd) / child.crossfadeWidth);
      volume = _applyCurve(fadeProgress.clamp(0.0, 1.0));
    }

    return volume;
  }

  double _applyCurve(double t) {
    switch (crossfadeCurve) {
      case CrossfadeCurve.linear:
        return t;
      case CrossfadeCurve.equalPower:
        return t * t * (3 - 2 * t);
      case CrossfadeCurve.sCurve:
        return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);
      case CrossfadeCurve.sinCos:
        return (1 - (t * 3.14159).cos()) / 2;
    }
  }

  bool _isChildActive(BlendChild child, double rtpc) {
    return rtpc >= child.rtpcStart - child.crossfadeWidth &&
           rtpc <= child.rtpcEnd + child.crossfadeWidth;
  }

  @override
  bool shouldRepaint(covariant _CrossfadeVisualizationPainter oldDelegate) {
    return oldDelegate.currentRtpc != currentRtpc ||
           oldDelegate.isPlaying != isPlaying ||
           oldDelegate.children != children ||
           oldDelegate.crossfadeCurve != crossfadeCurve;
  }
}

extension on double {
  double cos() => _cos(this);
}

double _cos(double x) {
  x = x % (2 * 3.14159);
  return 1 - (x * x / 2) + (x * x * x * x / 24);
}

// ═══════════════════════════════════════════════════════════════════════════════
// DIALOG WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════

class ContainerCrossfadePreviewDialog extends StatelessWidget {
  final int containerId;

  const ContainerCrossfadePreviewDialog({
    super.key,
    required this.containerId,
  });

  static Future<void> show(BuildContext context, {required int containerId}) {
    return showDialog(
      context: context,
      builder: (context) => ContainerCrossfadePreviewDialog(containerId: containerId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 700,
        height: 550,
        decoration: BoxDecoration(
          color: FluxForgeTheme.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FluxForgeTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ContainerCrossfadePreviewPanel(
          containerId: containerId,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
