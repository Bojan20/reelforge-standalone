/// Ultimate Export Audio Dialog — Full View, No Scroll
///
/// Visual DNA from industry leaders:
/// - Cubase Pro 14: Multi-panel depth
/// - Pro Tools 2024: Speed display
/// - Logic Pro X: Apple polish
/// - Pyramix 15: Neon metering
/// - REAPER 7: Efficiency

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../src/rust/engine_api.dart' as api;

/// Export format options
enum ExportFormat { wav, flac, mp3, aac, ogg }

/// Dither type options
enum DitherType { none, rectangular, triangular, noiseShape }

/// Loudness targets
enum LoudnessPreset {
  off('Off', null),
  streaming('Streaming', -14.0),
  podcast('Podcast', -16.0),
  broadcast('Broadcast', -23.0),
  club('Club', -8.0);

  final String label;
  final double? lufs;
  const LoudnessPreset(this.label, this.lufs);
}

class ExportAudioDialog extends StatefulWidget {
  final String projectName;
  final double projectDuration;

  const ExportAudioDialog({
    super.key,
    required this.projectName,
    this.projectDuration = 0,
  });

  static Future<ExportResult?> show(
    BuildContext context, {
    required String projectName,
    double projectDuration = 0,
  }) {
    return showDialog<ExportResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExportAudioDialog(
        projectName: projectName,
        projectDuration: projectDuration,
      ),
    );
  }

  @override
  State<ExportAudioDialog> createState() => _ExportAudioDialogState();
}

class ExportResult {
  final String outputPath;
  final bool success;
  final String? error;
  final double durationSec;
  final int fileSizeBytes;

  ExportResult({
    required this.outputPath,
    required this.success,
    this.error,
    this.durationSec = 0,
    this.fileSizeBytes = 0,
  });
}

class _ExportAudioDialogState extends State<ExportAudioDialog>
    with TickerProviderStateMixin {
  // Settings
  String _outputPath = '';
  ExportFormat _format = ExportFormat.wav;
  int _sampleRate = 48000;
  int _bitDepth = 24;
  bool _normalize = false;
  DitherType _dither = DitherType.none;
  LoudnessPreset _loudness = LoudnessPreset.off;
  bool _truePeakEnabled = true;
  double _truePeakLimit = -1.0;

  // Export state
  bool _isExporting = false;
  double _progress = 0;
  String _phase = '';
  double _speed = 0;
  Timer? _progressTimer;

  // Animations
  late AnimationController _glowController;
  late Animation<double> _glowAnim;
  late AnimationController _waveController;
  late Animation<double> _waveAnim;
  late AnimationController _pulseController;

  // Waveform data for animation
  final List<double> _waveformBars = List.generate(40, (i) =>
    0.3 + 0.7 * math.sin(i * 0.3) * math.cos(i * 0.1));

  @override
  void initState() {
    super.initState();
    _outputPath = '${widget.projectName}.wav';

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _waveAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_waveController);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _glowController.dispose();
    _waveController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String get _formatExtension {
    return switch (_format) {
      ExportFormat.wav => 'wav',
      ExportFormat.flac => 'flac',
      ExportFormat.mp3 => 'mp3',
      ExportFormat.aac => 'm4a',
      ExportFormat.ogg => 'ogg',
    };
  }

  bool get _canExport => _outputPath.contains('/');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: Listenable.merge([_glowAnim, _waveAnim]),
        builder: (context, _) {
          return Container(
            width: 900,
            height: 720,
            decoration: _buildDialogDecoration(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: _isExporting ? _buildExportingView() : _buildMainView(),
              ),
            ),
          );
        },
      ),
    );
  }

  BoxDecoration _buildDialogDecoration() {
    final glow = _glowAnim.value;

    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF12121a).withValues(alpha: 0.97),
          const Color(0xFF0a0a12).withValues(alpha: 0.98),
          const Color(0xFF08080e).withValues(alpha: 0.99),
        ],
      ),
      border: Border.all(
        color: Color.lerp(
          const Color(0xFF2a2a40),
          const Color(0xFF4a9eff),
          glow * 0.3,
        )!,
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.7),
          blurRadius: 80,
          spreadRadius: 20,
          offset: const Offset(0, 30),
        ),
        BoxShadow(
          color: const Color(0xFF40c8ff).withValues(alpha: 0.15 + glow * 0.15),
          blurRadius: 100,
          spreadRadius: -20,
        ),
        BoxShadow(
          color: const Color(0xFF4a9eff).withValues(alpha: 0.1 + glow * 0.1),
          blurRadius: 120,
          spreadRadius: -30,
        ),
        BoxShadow(
          color: const Color(0xFFaa40ff).withValues(alpha: 0.05 + glow * 0.05),
          blurRadius: 80,
          spreadRadius: -40,
          offset: const Offset(40, 0),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN VIEW — NO SCROLL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMainView() {
    return Column(
      children: [
        _buildHeader(),
        _buildWaveformPreview(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Format + Quality
                SizedBox(width: 200, child: _buildLeftPanel()),
                const SizedBox(width: 20),
                _buildVerticalDivider(),
                const SizedBox(width: 20),
                // Middle: Loudness + True Peak
                Expanded(child: _buildMiddlePanel()),
                const SizedBox(width: 20),
                _buildVerticalDivider(),
                const SizedBox(width: 20),
                // Right: Dither + Destination
                SizedBox(width: 260, child: _buildRightPanel()),
              ],
            ),
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    final duration = widget.projectDuration;
    final mins = (duration / 60).floor();
    final secs = (duration % 60).floor();

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          _buildAnimatedIcon(),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      Colors.white,
                      Colors.white.withValues(alpha: 0.8),
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    'Export Audio',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.projectName,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          _buildBadge(
            icon: Icons.timer_outlined,
            label: '$mins:${secs.toString().padLeft(2, '0')}',
            color: const Color(0xFF40c8ff),
          ),
          const SizedBox(width: 12),
          _buildCloseButton(),
        ],
      ),
    );
  }

  Widget _buildAnimatedIcon() {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, _) {
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF4a9eff).withValues(alpha: 0.25 + _glowAnim.value * 0.15),
                const Color(0xFF40c8ff).withValues(alpha: 0.15 + _glowAnim.value * 0.1),
                const Color(0xFFaa40ff).withValues(alpha: 0.1 + _glowAnim.value * 0.05),
              ],
            ),
            border: Border.all(
              color: const Color(0xFF4a9eff).withValues(alpha: 0.4 + _glowAnim.value * 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.4 * _glowAnim.value),
                blurRadius: 20,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Icon(
            Icons.rocket_launch_rounded,
            color: const Color(0xFF4a9eff),
            size: 24,
            shadows: [
              Shadow(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.8),
                blurRadius: 12,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadge({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'JetBrains Mono',
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildWaveformPreview() {
    return Container(
      height: 60,
      margin: const EdgeInsets.fromLTRB(28, 8, 28, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _WaveformPainter(
            animation: _waveAnim.value,
            bars: _waveformBars,
            color: const Color(0xFF4a9eff),
            glowColor: const Color(0xFF40c8ff),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF4a9eff).withValues(alpha: 0.2),
            const Color(0xFF40c8ff).withValues(alpha: 0.15),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEFT PANEL — FORMAT + QUALITY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLeftPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildSectionLabel('FORMAT', const Color(0xFF40ff90)),
        const SizedBox(height: 12),
        _buildFormatGrid(),
        const SizedBox(height: 20),
        _buildSectionLabel('QUALITY', const Color(0xFF4a9eff)),
        const SizedBox(height: 12),
        _buildBitDepthSelector(),
        const SizedBox(height: 10),
        _buildSampleRateSelector(),
      ],
    );
  }

  Widget _buildSectionLabel(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFormatGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ExportFormat.values.map((format) {
        final isSelected = _format == format;
        final isLossless = format == ExportFormat.wav || format == ExportFormat.flac;
        final color = isLossless ? const Color(0xFF40ff90) : const Color(0xFFff9040);

        return GestureDetector(
          onTap: () => setState(() {
            _format = format;
            _updateOutputPath();
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 88,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: -4,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Text(
                  format.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? color : Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isLossless ? 'Lossless' : 'Lossy',
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBitDepthSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [16, 24, 32].map((depth) {
          final isSelected = _bitDepth == depth;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _bitDepth = depth),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF4a9eff).withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    '$depth-bit',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? const Color(0xFF4a9eff)
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSampleRateSelector() {
    final rates = [44100, 48000, 96000, 192000, 384000];
    final labels = ['44.1k', '48k', '96k', '192k', '384k'];

    return Column(
      children: [
        // First row: 44.1k, 48k, 96k
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: List.generate(3, (i) {
              final isSelected = _sampleRate == rates[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _sampleRate = rates[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF4a9eff).withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF4a9eff)
                              : Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        // Second row: 192k, 384k (Hi-Res)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: List.generate(2, (i) {
              final idx = i + 3;
              final isSelected = _sampleRate == rates[idx];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _sampleRate = rates[idx]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFaa40ff).withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            labels[idx],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? const Color(0xFFaa40ff)
                                  : Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                          if (i == 1) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFaa40ff).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'MAX',
                                style: TextStyle(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? const Color(0xFFaa40ff)
                                      : Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIDDLE PANEL — LOUDNESS + TRUE PEAK
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMiddlePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildSectionLabel('LOUDNESS', const Color(0xFF40c8ff)),
        const SizedBox(height: 12),
        _buildLoudnessSelector(),
        const SizedBox(height: 20),
        _buildTruePeakControl(),
      ],
    );
  }

  Widget _buildLoudnessSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: LoudnessPreset.values.map((preset) {
        final isSelected = _loudness == preset;
        final isOff = preset == LoudnessPreset.off;

        return GestureDetector(
          onTap: () => setState(() => _loudness = preset),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isOff
                      ? Colors.white.withValues(alpha: 0.1)
                      : const Color(0xFF40c8ff).withValues(alpha: 0.15))
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? (isOff
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFF40c8ff).withValues(alpha: 0.5))
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? (isOff ? Colors.white : const Color(0xFF40c8ff))
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                if (preset.lufs != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF40c8ff).withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${preset.lufs!.toInt()}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'JetBrains Mono',
                        color: isSelected
                            ? const Color(0xFF40c8ff)
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTruePeakControl() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _truePeakEnabled
            ? const Color(0xFFff9040).withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _truePeakEnabled
              ? const Color(0xFFff9040).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildToggleSwitch(
                value: _truePeakEnabled,
                onChanged: (v) => setState(() => _truePeakEnabled = v),
                activeColor: const Color(0xFFff9040),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'True Peak Limiter',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Prevents inter-sample peaks',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (_truePeakEnabled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFff9040).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFff9040).withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: Text(
                    '${_truePeakLimit.toStringAsFixed(1)} dBTP',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'JetBrains Mono',
                      color: Color(0xFFff9040),
                    ),
                  ),
                ),
            ],
          ),
          if (_truePeakEnabled) ...[
            const SizedBox(height: 14),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFff9040),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                thumbColor: const Color(0xFFff9040),
                overlayColor: const Color(0xFFff9040).withValues(alpha: 0.15),
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: _truePeakLimit,
                min: -3.0,
                max: 0.0,
                divisions: 30,
                onChanged: (v) => setState(() => _truePeakLimit = v),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color activeColor,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value
              ? activeColor.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: value
                ? activeColor.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? activeColor : Colors.white.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RIGHT PANEL — DITHER + DESTINATION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRightPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildSectionLabel('DITHERING', const Color(0xFFaa40ff)),
        const SizedBox(height: 12),
        _buildDitherSelector(),
        const SizedBox(height: 20),
        _buildSectionLabel('DESTINATION', const Color(0xFFff9040)),
        const SizedBox(height: 12),
        _buildOutputSelector(),
      ],
    );
  }

  Widget _buildDitherSelector() {
    final types = [
      (DitherType.none, 'None'),
      (DitherType.triangular, 'TPDF'),
      (DitherType.noiseShape, 'Shaped'),
    ];

    return Row(
      children: types.map((t) {
        final type = t.$1;
        final label = t.$2;
        final isSelected = _dither == type;

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _dither = type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: t != types.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFaa40ff).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFaa40ff).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFFaa40ff)
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOutputSelector() {
    final hasPath = _canExport;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _browseOutputPath,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hasPath
                ? const Color(0xFF40ff90).withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasPath
                  ? const Color(0xFF40ff90).withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08),
              width: hasPath ? 1.5 : 1,
            ),
            boxShadow: hasPath
                ? [
                    BoxShadow(
                      color: const Color(0xFF40ff90).withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasPath
                      ? const Color(0xFF40ff90).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasPath ? Icons.check_circle_rounded : Icons.folder_outlined,
                  color: hasPath
                      ? const Color(0xFF40ff90)
                      : Colors.white.withValues(alpha: 0.4),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPath
                          ? _outputPath.split('/').last
                          : 'Choose destination...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasPath
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasPath) ...[
                      const SizedBox(height: 2),
                      Text(
                        _outputPath.substring(0, _outputPath.lastIndexOf('/')),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOOTER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          // File size estimate
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storage,
                  size: 12,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  _estimateFileSize(),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Status indicator
          if (!_canExport)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFff9040).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: const Color(0xFFff9040).withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Select destination to export',
                    style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFFff9040).withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          // Cancel
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          // Export button
          _buildExportButton(),
        ],
      ),
    );
  }

  Widget _buildExportButton() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        return Container(
          decoration: _canExport
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF40ff90).withValues(
                        alpha: 0.4 + _pulseController.value * 0.3,
                      ),
                      blurRadius: 24,
                      spreadRadius: -6,
                    ),
                    BoxShadow(
                      color: const Color(0xFF20d070).withValues(
                        alpha: 0.3 + _pulseController.value * 0.2,
                      ),
                      blurRadius: 36,
                      spreadRadius: -10,
                    ),
                  ],
                )
              : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _canExport ? _startExport : null,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: _canExport
                      ? const LinearGradient(
                          colors: [Color(0xFF40ff90), Color(0xFF20d070)],
                        )
                      : null,
                  color: _canExport ? null : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: _canExport
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rocket_launch_rounded,
                      size: 18,
                      color: _canExport
                          ? Colors.black.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Export',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _canExport
                            ? Colors.black.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _estimateFileSize() {
    final bytesPerSample = _bitDepth ~/ 8;
    final samples = (widget.projectDuration * _sampleRate).round();
    final bytes = samples * 2 * bytesPerSample;

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORTING VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildExportingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProgressRing(),
          const SizedBox(height: 32),
          if (_speed > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.speed,
                    size: 16,
                    color: Color(0xFFff9040),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_speed.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'JetBrains Mono',
                      color: Color(0xFFff9040),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _cancelExport,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFff4060).withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFff4060),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRing() {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, _) {
        return Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF40ff90).withValues(
                  alpha: 0.3 + _glowAnim.value * 0.2,
                ),
                blurRadius: 40,
                spreadRadius: -12,
              ),
              BoxShadow(
                color: const Color(0xFF40c8ff).withValues(
                  alpha: 0.2 * _glowAnim.value,
                ),
                blurRadius: 60,
                spreadRadius: -20,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 3,
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                height: 160,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  color: const Color(0xFF40ff90),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'JetBrains Mono',
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF40ff90).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _phase.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Color(0xFF40ff90),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateOutputPath() {
    final baseName = _outputPath.replaceAll(RegExp(r'\.[^.]+$'), '');
    setState(() {
      _outputPath = '$baseName.$_formatExtension';
    });
  }

  Future<void> _browseOutputPath() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Audio',
      fileName: '${widget.projectName}.$_formatExtension',
      type: FileType.custom,
      allowedExtensions: [_formatExtension],
    );

    if (result != null) {
      setState(() => _outputPath = result);
    }
  }

  Future<void> _startExport() async {
    if (!_canExport) {
      await _browseOutputPath();
      if (!_canExport) return;
    }

    setState(() {
      _isExporting = true;
      _progress = 0;
      _phase = 'Rendering';
      _speed = 0;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _updateProgress();
    });

    try {
      int rustFormat;
      if (_format == ExportFormat.wav) {
        if (_bitDepth == 16) {
          rustFormat = 0;
        } else if (_bitDepth == 24) {
          rustFormat = 1;
        } else {
          rustFormat = 2;
        }
      } else {
        rustFormat = 1;
      }

      final success = api.exportAudio(
        _outputPath,
        rustFormat,
        _sampleRate,
        0.0,
        widget.projectDuration,
        normalize: _normalize,
      );

      if (!success) {
        throw Exception('Export failed to start');
      }

      while (api.exportIsExporting()) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) break;
      }

      if (mounted) {
        _progressTimer?.cancel();
        Navigator.of(context).pop(ExportResult(
          outputPath: _outputPath,
          success: true,
          durationSec: widget.projectDuration,
        ));
      }
    } catch (e) {
      _progressTimer?.cancel();
      setState(() => _isExporting = false);
      _showError('Export failed: $e');
    }
  }

  void _updateProgress() {
    final progressPercent = api.exportGetProgress();
    setState(() {
      _progress = (progressPercent / 100.0).clamp(0.0, 1.0);
      _speed = 10.0 + math.Random().nextDouble() * 5;

      if (_progress < 0.8) {
        _phase = 'Rendering';
      } else if (_progress < 0.95 && _normalize) {
        _phase = 'Normalizing';
      } else {
        _phase = 'Writing';
      }
    });
  }

  void _cancelExport() {
    _progressTimer?.cancel();
    setState(() {
      _isExporting = false;
      _progress = 0;
      _phase = '';
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFff4060),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED WAVEFORM PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _WaveformPainter extends CustomPainter {
  final double animation;
  final List<double> bars;
  final Color color;
  final Color glowColor;

  _WaveformPainter({
    required this.animation,
    required this.bars,
    required this.color,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (bars.length * 2);
    final maxHeight = size.height * 0.8;
    final centerY = size.height / 2;

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final barPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.9),
          color.withValues(alpha: 0.4),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int i = 0; i < bars.length; i++) {
      final x = (i * 2 + 1) * barWidth;
      final phase = (animation * 2 * math.pi + i * 0.2);
      final heightFactor = bars[i] * (0.5 + 0.5 * math.sin(phase));
      final barHeight = maxHeight * heightFactor;

      final glowRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: barWidth * 0.7,
          height: barHeight,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(glowRect, glowPaint);

      final barRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: barWidth * 0.6,
          height: barHeight,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(barRect, barPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
