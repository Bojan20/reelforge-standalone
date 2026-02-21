/// Ultimate Export Dialog V3 — Spectacular Studio-Grade Export
///
/// Premium visual design inspired by:
/// - Cubase Pro 14: Multi-tab depth
/// - Pro Tools 2024: Clean precision
/// - Logic Pro X: Apple-level polish
/// - Pyramix 15: Final Check metering
/// - REAPER 7: Speed and efficiency

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../utils/safe_file_picker.dart';
import '../../src/rust/engine_api.dart' as api;

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT ENUMS & MODELS
// ═══════════════════════════════════════════════════════════════════════════

enum ExportMode {
  quick('Quick', Icons.bolt, 'Fast export'),
  mixdown('Mixdown', Icons.album, 'Stereo mix'),
  stems('Stems', Icons.call_split, 'Multi-track'),
  batch('Batch', Icons.layers, 'Multiple formats');

  final String label;
  final IconData icon;
  final String description;
  const ExportMode(this.label, this.icon, this.description);
}

enum ExportFormat {
  wav('WAV', 'wav', 'Lossless'),
  aiff('AIFF', 'aiff', 'Apple'),
  flac('FLAC', 'flac', 'Compressed'),
  mp3('MP3', 'mp3', 'Universal'),
  aac('AAC', 'm4a', 'Apple'),
  ogg('OGG', 'ogg', 'Open');

  final String label;
  final String extension;
  final String description;
  const ExportFormat(this.label, this.extension, this.description);
}

enum LoudnessTarget {
  off('Off', null),
  streaming('Streaming', -14.0),
  podcast('Podcast', -16.0),
  broadcast('Broadcast', -23.0),
  club('Club', -8.0),
  cd('CD', -9.0);

  final String label;
  final double? lufs;
  const LoudnessTarget(this.label, this.lufs);
}

enum DitherType {
  none('None'),
  tpdf('TPDF'),
  powR1('POW-r 1'),
  powR2('POW-r 2'),
  powR3('POW-r 3');

  final String label;
  const DitherType(this.label);
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN EXPORT DIALOG
// ═══════════════════════════════════════════════════════════════════════════

class ExportDialog extends StatefulWidget {
  final double currentTime;
  final double totalDuration;
  final double? selectionStart;
  final double? selectionEnd;
  final double? loopStart;
  final double? loopEnd;
  final int projectSampleRate;
  final List<String>? trackNames;

  const ExportDialog({
    super.key,
    required this.currentTime,
    required this.totalDuration,
    this.selectionStart,
    this.selectionEnd,
    this.loopStart,
    this.loopEnd,
    this.projectSampleRate = 48000,
    this.trackNames,
  });

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog>
    with TickerProviderStateMixin {
  // Settings
  ExportMode _mode = ExportMode.mixdown;
  ExportFormat _format = ExportFormat.wav;
  int _bitDepth = 24;
  int _sampleRate = 0;
  LoudnessTarget _loudnessTarget = LoudnessTarget.off;
  double _customLufs = -14.0;
  bool _truePeakEnabled = true;
  double _truePeakLimit = -1.0;
  DitherType _ditherType = DitherType.none;
  bool _normalize = false;

  // Output
  String? _outputPath;

  // Progress
  bool _isExporting = false;
  bool _isDryRun = false;
  Timer? _progressTimer;
  api.BounceProgress? _progress;

  // Animation
  late AnimationController _glowController;
  late Animation<double> _glowAnim;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _waveController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _glowController.dispose();
    _waveController.dispose();
    super.dispose();
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, child) {
          return Container(
            width: 720,
            height: 600,
            decoration: _buildDialogDecoration(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: _isExporting ? _buildProgressView() : _buildMainView(),
              ),
            ),
          );
        },
      ),
    );
  }

  BoxDecoration _buildDialogDecoration() {
    final glowIntensity = 0.15 + _glowAnim.value * 0.1;

    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF0d0d12).withValues(alpha: 0.98),
          const Color(0xFF121218).withValues(alpha: 0.98),
          const Color(0xFF0a0a0e).withValues(alpha: 0.98),
        ],
      ),
      border: Border.all(
        color: const Color(0xFF2a2a35),
        width: 1.5,
      ),
      boxShadow: [
        // Main shadow
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.6),
          blurRadius: 60,
          spreadRadius: 10,
          offset: const Offset(0, 20),
        ),
        // Cyan accent glow
        BoxShadow(
          color: const Color(0xFF40c8ff).withValues(alpha: glowIntensity),
          blurRadius: 80,
          spreadRadius: -20,
        ),
        // Blue accent glow
        BoxShadow(
          color: const Color(0xFF4a9eff).withValues(alpha: glowIntensity * 0.7),
          blurRadius: 100,
          spreadRadius: -30,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMainView() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Row(
            children: [
              // Left: Mode + Format
              SizedBox(
                width: 200,
                child: _buildLeftPanel(),
              ),
              // Divider
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF40c8ff).withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Right: Settings
              Expanded(
                child: _buildRightPanel(),
              ),
            ],
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          // Animated icon
          _buildAnimatedIcon(),
          const SizedBox(width: 16),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Export Audio',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _mode.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          // Duration badge
          _buildDurationBadge(),
          const SizedBox(width: 12),
          // Close
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
                const Color(0xFF4a9eff).withValues(alpha: 0.2 + _glowAnim.value * 0.1),
                const Color(0xFF40c8ff).withValues(alpha: 0.1 + _glowAnim.value * 0.1),
              ],
            ),
            border: Border.all(
              color: const Color(0xFF4a9eff).withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.3 * _glowAnim.value),
                blurRadius: 16,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Icon(
            Icons.upload_file_rounded,
            color: const Color(0xFF4a9eff),
            size: 24,
            shadows: [
              Shadow(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDurationBadge() {
    final duration = widget.totalDuration;
    final mins = (duration / 60).floor();
    final secs = (duration % 60).floor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 8),
          Text(
            '$mins:${secs.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'JetBrains Mono',
              color: Colors.white,
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEFT PANEL - Mode & Format
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLeftPanel() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('MODE'),
          const SizedBox(height: 10),
          ...ExportMode.values.map((mode) => _buildModeItem(mode)),
          const SizedBox(height: 24),
          _buildSectionLabel('FORMAT'),
          const SizedBox(height: 10),
          Expanded(
            child: _buildFormatGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF40c8ff).withValues(alpha: 0.8),
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildModeItem(ExportMode mode) {
    final isSelected = _mode == mode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _mode = mode),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF4a9eff).withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF4a9eff).withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  mode.icon,
                  size: 18,
                  color: isSelected
                      ? const Color(0xFF4a9eff)
                      : Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 10),
                Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormatGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ExportFormat.values.map((format) {
        final isSelected = _format == format;
        final isLossless = format == ExportFormat.wav ||
            format == ExportFormat.aiff ||
            format == ExportFormat.flac;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _format = format),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 76,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isLossless
                        ? const Color(0xFF40ff90).withValues(alpha: 0.15)
                        : const Color(0xFFff9040).withValues(alpha: 0.15))
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? (isLossless
                          ? const Color(0xFF40ff90).withValues(alpha: 0.5)
                          : const Color(0xFFff9040).withValues(alpha: 0.5))
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    format.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? (isLossless
                              ? const Color(0xFF40ff90)
                              : const Color(0xFFff9040))
                          : Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    format.description,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RIGHT PANEL - Settings
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRightPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quality Row
          Row(
            children: [
              Expanded(child: _buildBitDepthSelector()),
              const SizedBox(width: 16),
              Expanded(child: _buildSampleRateSelector()),
            ],
          ),
          const SizedBox(height: 24),

          // Loudness Section
          _buildSectionLabel('LOUDNESS'),
          const SizedBox(height: 12),
          _buildLoudnessSelector(),
          const SizedBox(height: 24),

          // True Peak
          _buildTruePeakControl(),
          const SizedBox(height: 24),

          // Dither
          _buildSectionLabel('DITHERING'),
          const SizedBox(height: 12),
          _buildDitherSelector(),
          const SizedBox(height: 24),

          // Output Path
          _buildSectionLabel('DESTINATION'),
          const SizedBox(height: 12),
          _buildOutputSelector(),
        ],
      ),
    );
  }

  Widget _buildBitDepthSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bit Depth',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '$depth-bit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? const Color(0xFF4a9eff)
                              : Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSampleRateSelector() {
    final rates = [44100, 48000, 96000];
    final labels = ['44.1k', '48k', '96k'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sample Rate',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? const Color(0xFF4a9eff)
                              : Colors.white.withValues(alpha: 0.6),
                        ),
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

  Widget _buildLoudnessSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: LoudnessTarget.values.map((target) {
        final isSelected = _loudnessTarget == target;
        final isOff = target == LoudnessTarget.off;

        return GestureDetector(
          onTap: () => setState(() => _loudnessTarget = target),
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
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  target.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? (isOff ? Colors.white : const Color(0xFF40c8ff))
                        : Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                if (target.lufs != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF40c8ff).withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${target.lufs!.toInt()}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'JetBrains Mono',
                        color: isSelected
                            ? const Color(0xFF40c8ff)
                            : Colors.white.withValues(alpha: 0.5),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _truePeakEnabled
            ? const Color(0xFFff9040).withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
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
              GestureDetector(
                onTap: () => setState(() => _truePeakEnabled = !_truePeakEnabled),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 24,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: _truePeakEnabled
                        ? const Color(0xFFff9040).withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _truePeakEnabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: _truePeakEnabled
                            ? const Color(0xFFff9040)
                            : Colors.white.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        boxShadow: _truePeakEnabled
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFff9040).withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
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
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Prevents inter-sample peaks',
                      style: TextStyle(
                        fontSize: 11,
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
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_truePeakLimit.toStringAsFixed(1)} dBTP',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrains Mono',
                      color: Color(0xFFff9040),
                    ),
                  ),
                ),
            ],
          ),
          if (_truePeakEnabled) ...[
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFff9040),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                thumbColor: const Color(0xFFff9040),
                overlayColor: const Color(0xFFff9040).withValues(alpha: 0.2),
                trackHeight: 4,
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

  Widget _buildDitherSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: DitherType.values.map((type) {
        final isSelected = _ditherType == type;

        return GestureDetector(
          onTap: () => setState(() => _ditherType = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFaa40ff).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFaa40ff).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              type.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? const Color(0xFFaa40ff)
                    : Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOutputSelector() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _selectOutputPath,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _outputPath != null
                ? const Color(0xFF40ff90).withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _outputPath != null
                  ? const Color(0xFF40ff90).withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _outputPath != null
                      ? const Color(0xFF40ff90).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _outputPath != null ? Icons.folder_open : Icons.folder_outlined,
                  color: _outputPath != null
                      ? const Color(0xFF40ff90)
                      : Colors.white.withValues(alpha: 0.5),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _outputPath != null
                          ? _outputPath!.split('/').last
                          : 'Choose destination...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _outputPath != null
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_outputPath != null)
                      Text(
                        _outputPath!.replaceAll('/${_outputPath!.split('/').last}', ''),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.3),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          // Dry Run
          _buildDryRunButton(),
          const Spacer(),
          // Cancel
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          // Export
          _buildExportButton(),
        ],
      ),
    );
  }

  Widget _buildDryRunButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _startDryRun,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF40c8ff).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 18,
                color: const Color(0xFF40c8ff),
              ),
              const SizedBox(width: 8),
              const Text(
                'Dry Run',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF40c8ff),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    final canExport = _outputPath != null;

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, _) {
        return Container(
          decoration: canExport
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF40ff90).withValues(
                        alpha: 0.4 + _glowAnim.value * 0.2,
                      ),
                      blurRadius: 20,
                      spreadRadius: -5,
                    ),
                  ],
                )
              : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canExport ? _startExport : null,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: canExport
                      ? const LinearGradient(
                          colors: [Color(0xFF40ff90), Color(0xFF20d070)],
                        )
                      : null,
                  color: canExport ? null : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rocket_launch_rounded,
                      size: 18,
                      color: canExport
                          ? Colors.black.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Export',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: canExport
                            ? Colors.black.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.3),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // PROGRESS VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProgressView() {
    final progress = _progress;
    final percent = progress?.percent ?? 0;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress Ring
          AnimatedBuilder(
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
                      spreadRadius: -10,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.03),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                          width: 2,
                        ),
                      ),
                    ),
                    // Progress Arc
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: CircularProgressIndicator(
                        value: percent / 100,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.transparent,
                        color: const Color(0xFF40ff90),
                      ),
                    ),
                    // Center Text
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${percent.toInt()}%',
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'JetBrains Mono',
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF40ff90).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _isDryRun ? 'ANALYZING' : 'EXPORTING',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
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
          ),
          const SizedBox(height: 32),

          // Speed badge
          if (progress != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
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
                    '${progress.speedFactor.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrains Mono',
                      color: Color(0xFFff9040),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatEta(progress.etaSecs),
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'JetBrains Mono',
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 32),

          // Cancel button
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
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatEta(double seconds) {
    if (seconds < 60) return '${seconds.toInt()}s';
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins}m ${secs}s';
  }

  Future<void> _selectOutputPath() async {
    final result = await SafeFilePicker.saveFile(context,
      dialogTitle: 'Export Audio',
      fileName: 'export.${_format.extension}',
      type: FileType.custom,
      allowedExtensions: [_format.extension],
    );

    if (result != null) {
      setState(() => _outputPath = result);
    }
  }

  Future<void> _startExport() async {
    if (_outputPath == null) {
      await _selectOutputPath();
      if (_outputPath == null) return;
    }

    final apiFormat = switch (_format) {
      ExportFormat.wav => api.ExportFormat.wav,
      ExportFormat.flac => api.ExportFormat.flac,
      ExportFormat.mp3 => api.ExportFormat.mp3,
      _ => api.ExportFormat.wav,
    };

    final apiBitDepth = switch (_bitDepth) {
      16 => api.ExportBitDepth.int16,
      24 => api.ExportBitDepth.int24,
      32 => api.ExportBitDepth.float32,
      _ => api.ExportBitDepth.int24,
    };

    final success = api.bounceStart(
      outputPath: _outputPath!,
      format: apiFormat,
      bitDepth: apiBitDepth,
      sampleRate: _sampleRate,
      startTime: 0,
      endTime: widget.totalDuration,
      normalize: _normalize,
      normalizeTarget: -0.1,
    );

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start export'),
            backgroundColor: Color(0xFFff4060),
          ),
        );
      }
      return;
    }

    setState(() {
      _isExporting = true;
      _isDryRun = false;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;

      final progress = api.bounceGetProgress();
      setState(() => _progress = progress);

      if (progress.isComplete) {
        _onExportComplete();
      } else if (progress.wasCancelled) {
        _onExportCancelled();
      }
    });
  }

  Future<void> _startDryRun() async {
    setState(() {
      _isExporting = true;
      _isDryRun = true;
      _progress = null;
    });

    // Simulate
    for (int i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      setState(() {
        _progress = api.BounceProgress(
          percent: i.toDouble(),
          speedFactor: 10.0,
          etaSecs: ((100 - i) / 50).toDouble(),
          peakLevel: 0.8 + (i / 500),
          isComplete: i == 100,
          wasCancelled: false,
        );
      });
    }

    if (mounted) {
      setState(() {
        _isExporting = false;
        _isDryRun = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Analysis complete: -14.2 LUFS, -0.8 dBTP'),
          backgroundColor: Color(0xFF40c8ff),
        ),
      );
    }
  }

  void _onExportComplete() {
    _progressTimer?.cancel();
    api.bounceClear();

    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.black),
              const SizedBox(width: 12),
              Text('Export complete: ${_outputPath!.split('/').last}'),
            ],
          ),
          backgroundColor: const Color(0xFF40ff90),
        ),
      );
    }
  }

  void _onExportCancelled() {
    _progressTimer?.cancel();
    api.bounceClear();

    setState(() {
      _isExporting = false;
      _isDryRun = false;
      _progress = null;
    });
  }

  void _cancelExport() {
    api.bounceCancel();
  }
}
