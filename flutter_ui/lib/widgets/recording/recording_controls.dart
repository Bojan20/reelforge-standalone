/// Recording Controls Widget
///
/// Provides:
/// - Record arm/disarm button
/// - Record start/stop button
/// - Input level meters
/// - Recording time display
/// - Recording status indicator

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

// Mock types until flutter_rust_bridge generates them
class RecordingStatus {
  final bool isRecording;
  final bool isArmed;
  final double durationSecs;
  final int samplesRecorded;
  final double peakLevel;
  final int clipsDetected;
  final String? outputPath;

  RecordingStatus({
    required this.isRecording,
    required this.isArmed,
    required this.durationSecs,
    required this.samplesRecorded,
    required this.peakLevel,
    required this.clipsDetected,
    this.outputPath,
  });
}

class RecordingControls extends StatefulWidget {
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onArmToggle;
  final bool showInputMeters;

  const RecordingControls({
    super.key,
    this.onRecordStart,
    this.onRecordStop,
    this.onArmToggle,
    this.showInputMeters = true,
  });

  @override
  State<RecordingControls> createState() => _RecordingControlsState();
}

class _RecordingControlsState extends State<RecordingControls>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isArmed = false;
  double _duration = 0.0;
  double _inputLevelL = 0.0;
  double _inputLevelR = 0.0;
  Timer? _updateTimer;
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Poll recording status
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  void _updateStatus() {
    // TODO: Call Rust API
    // final status = api.recordingGetStatus();
    // final (levelL, levelR) = api.recordingGetInputLevels();

    // Mock data for now
    if (_isRecording) {
      setState(() {
        _duration += 0.1;
        _inputLevelL = 0.3 + (DateTime.now().millisecondsSinceEpoch % 100) / 200;
        _inputLevelR = 0.25 + (DateTime.now().millisecondsSinceEpoch % 100) / 250;
      });
    }

    // Blink when armed
    if (_isArmed && !_isRecording) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      _blinkController.stop();
      _blinkController.value = 1.0;
    }
  }

  void _toggleArm() {
    setState(() => _isArmed = !_isArmed);
    widget.onArmToggle?.call();
  }

  void _toggleRecording() {
    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _isArmed = false;
      });
      widget.onRecordStop?.call();
    } else {
      setState(() {
        _isRecording = true;
        _duration = 0.0;
      });
      widget.onRecordStart?.call();
    }
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 100).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Input meters
          if (widget.showInputMeters) ...[
            _buildInputMeters(),
            const SizedBox(height: 12),
          ],

          // Recording time
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatDuration(_duration),
              style: TextStyle(
                fontFamily: FluxForgeTheme.monoFontFamily,
                fontSize: 24,
                color: _isRecording
                    ? FluxForgeTheme.accentRed
                    : FluxForgeTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Arm button
              AnimatedBuilder(
                animation: _blinkController,
                builder: (context, child) {
                  return _buildControlButton(
                    icon: Icons.fiber_manual_record,
                    color: _isArmed
                        ? FluxForgeTheme.accentRed.withValues(
                            alpha: 0.5 + _blinkController.value * 0.5,
                          )
                        : FluxForgeTheme.textTertiary,
                    onTap: _toggleArm,
                    tooltip: _isArmed ? 'Disarm' : 'Arm Recording',
                    size: 36,
                  );
                },
              ),
              const SizedBox(width: 16),

              // Record button
              _buildRecordButton(),

              const SizedBox(width: 16),

              // Stop button
              _buildControlButton(
                icon: Icons.stop,
                color: _isRecording
                    ? FluxForgeTheme.textPrimary
                    : FluxForgeTheme.textTertiary,
                onTap: _isRecording ? _toggleRecording : null,
                tooltip: 'Stop Recording',
                size: 36,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Status text
          Text(
            _isRecording
                ? 'Recording...'
                : _isArmed
                    ? 'Armed - Press Record to start'
                    : 'Ready',
            style: TextStyle(
              color: _isRecording
                  ? FluxForgeTheme.accentRed
                  : FluxForgeTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputMeters() {
    return Row(
      children: [
        Text('L', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
        const SizedBox(width: 4),
        Expanded(child: _buildMeter(_inputLevelL)),
        const SizedBox(width: 8),
        Text('R', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
        const SizedBox(width: 4),
        Expanded(child: _buildMeter(_inputLevelR)),
      ],
    );
  }

  Widget _buildMeter(double level) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth * level.clamp(0.0, 1.0);
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: width,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    FluxForgeTheme.accentGreen,
                    level > 0.7 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen,
                    level > 0.9 ? FluxForgeTheme.accentRed : FluxForgeTheme.accentOrange,
                  ],
                  stops: const [0.0, 0.7, 0.9],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: _toggleRecording,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording
              ? FluxForgeTheme.accentRed
              : FluxForgeTheme.bgSurface,
          border: Border.all(
            color: _isRecording
                ? FluxForgeTheme.accentRed
                : FluxForgeTheme.borderSubtle,
            width: 3,
          ),
          boxShadow: _isRecording
              ? [
                  BoxShadow(
                    color: FluxForgeTheme.accentRed.withValues(alpha: 0.5),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: _isRecording ? 20 : 24,
            height: _isRecording ? 20 : 24,
            decoration: BoxDecoration(
              color: _isRecording ? Colors.white : FluxForgeTheme.accentRed,
              borderRadius: BorderRadius.circular(_isRecording ? 4 : 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    String? tooltip,
    double size = 32,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: FluxForgeTheme.bgSurface,
          ),
          child: Icon(icon, color: color, size: size * 0.6),
        ),
      ),
    );
  }
}
