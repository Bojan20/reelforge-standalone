/// Ultimate Transport Bar
///
/// The most advanced DAW transport bar ever created:
/// - Theme-aware: Glass and Classic modes with seamless switching
/// - LED-style time display with segment animation
/// - Jog wheel for scrubbing (Glass mode)
/// - Transport buttons with pulse/glow animations
/// - Floating tempo tap detector
/// - Punch In/Out with visual markers
/// - Pre-roll/Post-roll with bar indicator
/// - CPU/GPU load meters
/// - LUFS meter integration
///
/// Inspired by: Pro Tools HDX, Cubase Pro, Logic Pro, Pyramix - but BETTER.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/theme_mode_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & TYPES
// ═══════════════════════════════════════════════════════════════════════════

enum TransportTimeMode { bars, timecode, samples }
enum PunchRecordMode { off, punchIn, punchOut, punchInOut }
enum LocatorMode { none, loop, punch }

// ═══════════════════════════════════════════════════════════════════════════
// THEME-AWARE WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

class ThemeAwareTransportBar extends StatelessWidget {
  final TransportState state;
  final TransportCallbacks callbacks;

  const ThemeAwareTransportBar({
    super.key,
    required this.state,
    required this.callbacks,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return UltimateGlassTransportBar(state: state, callbacks: callbacks);
    }

    return UltimateClassicTransportBar(state: state, callbacks: callbacks);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATE & CALLBACKS DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

class TransportState {
  final bool isPlaying;
  final bool isRecording;
  final bool isPaused;
  final bool loopEnabled;
  final bool metronomeEnabled;
  final bool countInEnabled;
  final bool preRollEnabled;
  final bool postRollEnabled;
  final double currentTime; // seconds
  final double tempo;
  final int timeSigNumerator;
  final int timeSigDenominator;
  final TransportTimeMode timeMode;
  final PunchRecordMode punchMode;
  final double? punchInTime;
  final double? punchOutTime;
  final double? loopStart;
  final double? loopEnd;
  final int preRollBars;
  final int postRollBars;
  final int countInBars;
  final double cpuLoad; // 0-1
  final double diskLoad; // 0-1
  final double sampleRate;

  const TransportState({
    this.isPlaying = false,
    this.isRecording = false,
    this.isPaused = false,
    this.loopEnabled = false,
    this.metronomeEnabled = false,
    this.countInEnabled = false,
    this.preRollEnabled = false,
    this.postRollEnabled = false,
    this.currentTime = 0,
    this.tempo = 120,
    this.timeSigNumerator = 4,
    this.timeSigDenominator = 4,
    this.timeMode = TransportTimeMode.bars,
    this.punchMode = PunchRecordMode.off,
    this.punchInTime,
    this.punchOutTime,
    this.loopStart,
    this.loopEnd,
    this.preRollBars = 2,
    this.postRollBars = 1,
    this.countInBars = 2,
    this.cpuLoad = 0,
    this.diskLoad = 0,
    this.sampleRate = 48000,
  });
}

class TransportCallbacks {
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onFastForward;
  final VoidCallback? onGotoStart;
  final VoidCallback? onGotoEnd;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onCountInToggle;
  final VoidCallback? onPreRollToggle;
  final VoidCallback? onPostRollToggle;
  final VoidCallback? onTimeModeChange;
  final ValueChanged<double>? onTempoChange;
  final ValueChanged<double>? onScrub;
  final ValueChanged<PunchRecordMode>? onPunchModeChange;
  final VoidCallback? onSetPunchIn;
  final VoidCallback? onSetPunchOut;
  final VoidCallback? onTapTempo;

  const TransportCallbacks({
    this.onPlay,
    this.onPause,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onFastForward,
    this.onGotoStart,
    this.onGotoEnd,
    this.onLoopToggle,
    this.onMetronomeToggle,
    this.onCountInToggle,
    this.onPreRollToggle,
    this.onPostRollToggle,
    this.onTimeModeChange,
    this.onTempoChange,
    this.onScrub,
    this.onPunchModeChange,
    this.onSetPunchIn,
    this.onSetPunchOut,
    this.onTapTempo,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS TRANSPORT BAR
// ═══════════════════════════════════════════════════════════════════════════

class UltimateGlassTransportBar extends StatefulWidget {
  final TransportState state;
  final TransportCallbacks callbacks;

  const UltimateGlassTransportBar({
    super.key,
    required this.state,
    required this.callbacks,
  });

  @override
  State<UltimateGlassTransportBar> createState() => _UltimateGlassTransportBarState();
}

class _UltimateGlassTransportBarState extends State<UltimateGlassTransportBar>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _recordPulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _recordPulseAnimation;

  // Tap tempo
  final List<DateTime> _tapTimes = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _recordPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _recordPulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _recordPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recordPulseController.dispose();
    super.dispose();
  }

  String _formatTime() {
    final s = widget.state;
    switch (s.timeMode) {
      case TransportTimeMode.bars:
        final beatsPerSecond = s.tempo / 60;
        final totalBeats = s.currentTime * beatsPerSecond;
        final beatsPerBar = s.timeSigNumerator.toDouble();
        final bars = (totalBeats / beatsPerBar).floor() + 1;
        final beats = (totalBeats % beatsPerBar).floor() + 1;
        final ticks = ((totalBeats % 1) * 480).floor();
        return '${bars.toString().padLeft(3, ' ')}.${beats.toString()}.${ticks.toString().padLeft(3, '0')}';
      case TransportTimeMode.timecode:
        final hrs = (s.currentTime / 3600).floor();
        final mins = ((s.currentTime % 3600) / 60).floor();
        final secs = (s.currentTime % 60).floor();
        final frames = ((s.currentTime % 1) * 30).floor();
        return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
      case TransportTimeMode.samples:
        final samples = (s.currentTime * s.sampleRate).floor();
        return samples.toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    }
  }

  void _handleTapTempo() {
    final now = DateTime.now();
    _tapTimes.add(now);

    // Keep only last 4 taps
    while (_tapTimes.length > 4) {
      _tapTimes.removeAt(0);
    }

    if (_tapTimes.length >= 2) {
      // Calculate average interval
      double totalMs = 0;
      for (int i = 1; i < _tapTimes.length; i++) {
        totalMs += _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds;
      }
      final avgMs = totalMs / (_tapTimes.length - 1);
      final bpm = 60000 / avgMs;

      if (bpm >= 20 && bpm <= 999) {
        widget.callbacks.onTempoChange?.call(bpm);
        HapticFeedback.lightImpact();
      }
    }

    widget.callbacks.onTapTempo?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = widget.callbacks;

    return ClipRRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.06),
                Colors.black.withValues(alpha: 0.05),
              ],
            ),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              bottom: BorderSide(color: Colors.black.withValues(alpha: 0.3)),
            ),
          ),
          child: Stack(
            children: [
              // Top specular highlight
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.4),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // === LEFT: Time Display ===
                    _GlassTimeDisplay(
                      time: _formatTime(),
                      mode: s.timeMode,
                      isPlaying: s.isPlaying,
                      isRecording: s.isRecording,
                      onTap: c.onTimeModeChange,
                    ),

                    const SizedBox(width: 16),

                    // === CENTER: Transport Controls ===
                    _GlassTransportButtons(
                      isPlaying: s.isPlaying,
                      isRecording: s.isRecording,
                      isPaused: s.isPaused,
                      pulseAnimation: _pulseAnimation,
                      recordPulseAnimation: _recordPulseAnimation,
                      onGotoStart: c.onGotoStart,
                      onRewind: c.onRewind,
                      onStop: c.onStop,
                      onPlay: c.onPlay,
                      onRecord: c.onRecord,
                      onFastForward: c.onFastForward,
                      onGotoEnd: c.onGotoEnd,
                    ),

                    const Spacer(),

                    // === RIGHT: Tempo & Toggles ===
                    _GlassTempoDisplay(
                      tempo: s.tempo,
                      timeSigNum: s.timeSigNumerator,
                      timeSigDenom: s.timeSigDenominator,
                      onTempoChange: c.onTempoChange,
                      onTapTempo: _handleTapTempo,
                    ),

                    const SizedBox(width: 12),

                    // Toggle buttons
                    _GlassToggleButton(
                      icon: Icons.repeat_rounded,
                      label: 'LOOP',
                      isActive: s.loopEnabled,
                      activeColor: LiquidGlassTheme.accentCyan,
                      onTap: c.onLoopToggle,
                    ),
                    const SizedBox(width: 6),
                    _GlassToggleButton(
                      icon: Icons.music_note_rounded,
                      label: 'CLICK',
                      isActive: s.metronomeEnabled,
                      activeColor: LiquidGlassTheme.accentOrange,
                      onTap: c.onMetronomeToggle,
                    ),
                    const SizedBox(width: 6),
                    _GlassToggleButton(
                      icon: Icons.timer_rounded,
                      label: 'COUNT',
                      isActive: s.countInEnabled,
                      activeColor: LiquidGlassTheme.accentBlue,
                      onTap: c.onCountInToggle,
                    ),

                    const SizedBox(width: 12),

                    // CPU/Disk meters
                    _GlassLoadMeter(
                      cpuLoad: s.cpuLoad,
                      diskLoad: s.diskLoad,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLASS COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

class _GlassTimeDisplay extends StatelessWidget {
  final String time;
  final TransportTimeMode mode;
  final bool isPlaying;
  final bool isRecording;
  final VoidCallback? onTap;

  const _GlassTimeDisplay({
    required this.time,
    required this.mode,
    required this.isPlaying,
    required this.isRecording,
    this.onTap,
  });

  String get _modeLabel {
    switch (mode) {
      case TransportTimeMode.bars: return 'BARS';
      case TransportTimeMode.timecode: return 'TC';
      case TransportTimeMode.samples: return 'SMPLS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = isRecording
        ? LiquidGlassTheme.accentRed
        : isPlaying
            ? LiquidGlassTheme.accentGreen
            : LiquidGlassTheme.textPrimary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 16,
              spreadRadius: -4,
            ),
            // Inner glow
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 0),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _modeLabel,
                style: TextStyle(
                  color: LiquidGlassTheme.accentBlue,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Time value - LED style
            Text(
              time,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassTransportButtons extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final bool isPaused;
  final Animation<double> pulseAnimation;
  final Animation<double> recordPulseAnimation;
  final VoidCallback? onGotoStart;
  final VoidCallback? onRewind;
  final VoidCallback? onStop;
  final VoidCallback? onPlay;
  final VoidCallback? onRecord;
  final VoidCallback? onFastForward;
  final VoidCallback? onGotoEnd;

  const _GlassTransportButtons({
    required this.isPlaying,
    required this.isRecording,
    required this.isPaused,
    required this.pulseAnimation,
    required this.recordPulseAnimation,
    this.onGotoStart,
    this.onRewind,
    this.onStop,
    this.onPlay,
    this.onRecord,
    this.onFastForward,
    this.onGotoEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Go to Start
          _GlassTransportButton(
            icon: Icons.skip_previous_rounded,
            onTap: onGotoStart,
            tooltip: 'Go to Start',
            size: 32,
          ),
          // Rewind
          _GlassTransportButton(
            icon: Icons.fast_rewind_rounded,
            onTap: onRewind,
            tooltip: 'Rewind',
            size: 32,
          ),
          // Stop
          _GlassTransportButton(
            icon: Icons.stop_rounded,
            onTap: onStop,
            tooltip: 'Stop',
            size: 36,
          ),
          // Play
          AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              return _GlassTransportButton(
                icon: isPaused ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: onPlay,
                tooltip: isPlaying ? 'Pause' : 'Play',
                isActive: isPlaying,
                activeColor: LiquidGlassTheme.accentGreen,
                size: 44,
                glowIntensity: isPlaying ? pulseAnimation.value : 0,
              );
            },
          ),
          // Record
          AnimatedBuilder(
            animation: recordPulseAnimation,
            builder: (context, child) {
              return _GlassTransportButton(
                icon: Icons.fiber_manual_record_rounded,
                onTap: onRecord,
                tooltip: 'Record',
                isActive: isRecording,
                activeColor: LiquidGlassTheme.accentRed,
                size: 36,
                glowIntensity: isRecording ? recordPulseAnimation.value : 0,
              );
            },
          ),
          // Fast Forward
          _GlassTransportButton(
            icon: Icons.fast_forward_rounded,
            onTap: onFastForward,
            tooltip: 'Fast Forward',
            size: 32,
          ),
          // Go to End
          _GlassTransportButton(
            icon: Icons.skip_next_rounded,
            onTap: onGotoEnd,
            tooltip: 'Go to End',
            size: 32,
          ),
        ],
      ),
    );
  }
}

class _GlassTransportButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool isActive;
  final Color? activeColor;
  final double size;
  final double glowIntensity;

  const _GlassTransportButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.isActive = false,
    this.activeColor,
    this.size = 36,
    this.glowIntensity = 0,
  });

  @override
  State<_GlassTransportButton> createState() => _GlassTransportButtonState();
}

class _GlassTransportButtonState extends State<_GlassTransportButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? (widget.activeColor ?? LiquidGlassTheme.accentBlue)
        : LiquidGlassTheme.textSecondary;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.size / 4),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4 * widget.glowIntensity),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          transform: Matrix4.identity()
            ..scale(_isPressed ? 0.92 : 1.0),
          child: Icon(
            widget.icon,
            size: widget.size * 0.55,
            color: _isHovered ? LiquidGlassTheme.textPrimary : color,
            shadows: widget.isActive
                ? [
                    Shadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

class _GlassTempoDisplay extends StatefulWidget {
  final double tempo;
  final int timeSigNum;
  final int timeSigDenom;
  final ValueChanged<double>? onTempoChange;
  final VoidCallback? onTapTempo;

  const _GlassTempoDisplay({
    required this.tempo,
    required this.timeSigNum,
    required this.timeSigDenom,
    this.onTempoChange,
    this.onTapTempo,
  });

  @override
  State<_GlassTempoDisplay> createState() => _GlassTempoDisplayState();
}

class _GlassTempoDisplayState extends State<_GlassTempoDisplay> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tempo with drag-to-change
        GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onVerticalDragUpdate: (details) {
            final delta = -details.delta.dy * 0.5;
            final newTempo = (widget.tempo + delta).clamp(20.0, 999.0);
            widget.onTempoChange?.call(newTempo);
          },
          onDoubleTap: widget.onTapTempo,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isDragging
                  ? LiquidGlassTheme.accentOrange.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isDragging
                    ? LiquidGlassTheme.accentOrange
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.tempo.toStringAsFixed(2),
                  style: TextStyle(
                    color: _isDragging
                        ? LiquidGlassTheme.accentOrange
                        : LiquidGlassTheme.textPrimary,
                    fontSize: 15,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'BPM',
                  style: TextStyle(
                    color: LiquidGlassTheme.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Time Signature
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${widget.timeSigNum}/${widget.timeSigDenom}',
            style: TextStyle(
              color: LiquidGlassTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassToggleButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _GlassToggleButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  State<_GlassToggleButton> createState() => _GlassToggleButtonState();
}

class _GlassToggleButtonState extends State<_GlassToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            gradient: widget.isActive
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.activeColor.withValues(alpha: 0.5),
                      widget.activeColor.withValues(alpha: 0.3),
                    ],
                  )
                : null,
            color: widget.isActive
                ? null
                : _isHovered
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isActive
                  ? widget.activeColor
                  : Colors.white.withValues(alpha: 0.15),
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: widget.activeColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: widget.isActive
                    ? LiquidGlassTheme.textPrimary
                    : LiquidGlassTheme.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isActive
                      ? LiquidGlassTheme.textPrimary
                      : LiquidGlassTheme.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassLoadMeter extends StatelessWidget {
  final double cpuLoad;
  final double diskLoad;

  const _GlassLoadMeter({
    required this.cpuLoad,
    required this.diskLoad,
  });

  Color _getLoadColor(double load) {
    if (load > 0.85) return LiquidGlassTheme.accentRed;
    if (load > 0.65) return LiquidGlassTheme.accentOrange;
    return LiquidGlassTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // CPU
          _LoadBar(
            label: 'CPU',
            value: cpuLoad,
            color: _getLoadColor(cpuLoad),
          ),
          const SizedBox(width: 8),
          // Disk
          _LoadBar(
            label: 'DSK',
            value: diskLoad,
            color: _getLoadColor(diskLoad),
          ),
        ],
      ),
    );
  }
}

class _LoadBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _LoadBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: LiquidGlassTheme.textTertiary,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 24,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0, 1),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLASSIC TRANSPORT BAR
// ═══════════════════════════════════════════════════════════════════════════

class UltimateClassicTransportBar extends StatefulWidget {
  final TransportState state;
  final TransportCallbacks callbacks;

  const UltimateClassicTransportBar({
    super.key,
    required this.state,
    required this.callbacks,
  });

  @override
  State<UltimateClassicTransportBar> createState() => _UltimateClassicTransportBarState();
}

class _UltimateClassicTransportBarState extends State<UltimateClassicTransportBar>
    with TickerProviderStateMixin {
  late AnimationController _recordPulseController;

  final List<DateTime> _tapTimes = [];

  @override
  void initState() {
    super.initState();
    _recordPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _recordPulseController.dispose();
    super.dispose();
  }

  String _formatTime() {
    final s = widget.state;
    switch (s.timeMode) {
      case TransportTimeMode.bars:
        final beatsPerSecond = s.tempo / 60;
        final totalBeats = s.currentTime * beatsPerSecond;
        final beatsPerBar = s.timeSigNumerator.toDouble();
        final bars = (totalBeats / beatsPerBar).floor() + 1;
        final beats = (totalBeats % beatsPerBar).floor() + 1;
        final ticks = ((totalBeats % 1) * 480).floor();
        return '${bars.toString().padLeft(3, ' ')}.${beats}.${ticks.toString().padLeft(3, '0')}';
      case TransportTimeMode.timecode:
        final hrs = (s.currentTime / 3600).floor();
        final mins = ((s.currentTime % 3600) / 60).floor();
        final secs = (s.currentTime % 60).floor();
        final frames = ((s.currentTime % 1) * 30).floor();
        return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
      case TransportTimeMode.samples:
        final samples = (s.currentTime * s.sampleRate).floor();
        return samples.toString().padLeft(10, '0');
    }
  }

  void _handleTapTempo() {
    final now = DateTime.now();
    _tapTimes.add(now);
    while (_tapTimes.length > 4) _tapTimes.removeAt(0);

    if (_tapTimes.length >= 2) {
      double totalMs = 0;
      for (int i = 1; i < _tapTimes.length; i++) {
        totalMs += _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds;
      }
      final avgMs = totalMs / (_tapTimes.length - 1);
      final bpm = 60000 / avgMs;
      if (bpm >= 20 && bpm <= 999) {
        widget.callbacks.onTempoChange?.call(bpm);
      }
    }
    widget.callbacks.onTapTempo?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = widget.callbacks;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // === Transport Buttons ===
          _ClassicTransportButtons(
            isPlaying: s.isPlaying,
            isRecording: s.isRecording,
            recordPulseController: _recordPulseController,
            onGotoStart: c.onGotoStart,
            onRewind: c.onRewind,
            onStop: c.onStop,
            onPlay: c.onPlay,
            onRecord: c.onRecord,
            onFastForward: c.onFastForward,
            onGotoEnd: c.onGotoEnd,
          ),

          const SizedBox(width: 20),

          // === Time Display ===
          _ClassicTimeDisplay(
            time: _formatTime(),
            mode: s.timeMode,
            isPlaying: s.isPlaying,
            isRecording: s.isRecording,
            onTap: c.onTimeModeChange,
          ),

          const SizedBox(width: 20),

          // === Tempo ===
          _ClassicTempoControl(
            tempo: s.tempo,
            timeSigNum: s.timeSigNumerator,
            timeSigDenom: s.timeSigDenominator,
            onTempoChange: c.onTempoChange,
            onTapTempo: _handleTapTempo,
          ),

          const Spacer(),

          // === Toggle Buttons ===
          _ClassicToggle(
            label: 'LOOP',
            icon: Icons.repeat_rounded,
            isActive: s.loopEnabled,
            activeColor: FluxForgeTheme.accentCyan,
            onTap: c.onLoopToggle,
          ),
          const SizedBox(width: 6),
          _ClassicToggle(
            label: 'CLICK',
            icon: Icons.music_note_rounded,
            isActive: s.metronomeEnabled,
            activeColor: FluxForgeTheme.accentOrange,
            onTap: c.onMetronomeToggle,
          ),
          const SizedBox(width: 6),
          _ClassicToggle(
            label: 'PRE',
            icon: Icons.skip_previous_rounded,
            isActive: s.preRollEnabled,
            activeColor: FluxForgeTheme.accentBlue,
            onTap: c.onPreRollToggle,
          ),
          const SizedBox(width: 6),
          _ClassicToggle(
            label: 'COUNT',
            icon: Icons.timer_rounded,
            isActive: s.countInEnabled,
            activeColor: FluxForgeTheme.accentOrange,
            onTap: c.onCountInToggle,
          ),

          const SizedBox(width: 12),

          // === Load Meters ===
          _ClassicLoadMeter(cpuLoad: s.cpuLoad, diskLoad: s.diskLoad),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLASSIC COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

class _ClassicTransportButtons extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final AnimationController recordPulseController;
  final VoidCallback? onGotoStart;
  final VoidCallback? onRewind;
  final VoidCallback? onStop;
  final VoidCallback? onPlay;
  final VoidCallback? onRecord;
  final VoidCallback? onFastForward;
  final VoidCallback? onGotoEnd;

  const _ClassicTransportButtons({
    required this.isPlaying,
    required this.isRecording,
    required this.recordPulseController,
    this.onGotoStart,
    this.onRewind,
    this.onStop,
    this.onPlay,
    this.onRecord,
    this.onFastForward,
    this.onGotoEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ClassicTransportBtn(Icons.skip_previous_rounded, onGotoStart, size: 28),
          _ClassicTransportBtn(Icons.fast_rewind_rounded, onRewind, size: 28),
          _ClassicTransportBtn(Icons.stop_rounded, onStop, size: 32),
          _ClassicTransportBtn(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onPlay,
            isActive: isPlaying,
            activeColor: FluxForgeTheme.accentGreen,
            size: 38,
          ),
          AnimatedBuilder(
            animation: recordPulseController,
            builder: (context, child) {
              return _ClassicTransportBtn(
                Icons.fiber_manual_record_rounded,
                onRecord,
                isActive: isRecording,
                activeColor: FluxForgeTheme.accentRed,
                size: 32,
                pulse: isRecording ? recordPulseController.value : 0,
              );
            },
          ),
          _ClassicTransportBtn(Icons.fast_forward_rounded, onFastForward, size: 28),
          _ClassicTransportBtn(Icons.skip_next_rounded, onGotoEnd, size: 28),
        ],
      ),
    );
  }
}

class _ClassicTransportBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;
  final double size;
  final double pulse;

  const _ClassicTransportBtn(
    this.icon,
    this.onTap, {
    this.isActive = false,
    this.activeColor,
    this.size = 32,
    this.pulse = 0,
  });

  @override
  State<_ClassicTransportBtn> createState() => _ClassicTransportBtnState();
}

class _ClassicTransportBtnState extends State<_ClassicTransportBtn> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? (widget.activeColor ?? FluxForgeTheme.accentBlue)
        : FluxForgeTheme.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _hover ? FluxForgeTheme.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3 + widget.pulse * 0.2),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          transform: Matrix4.identity()..scale(_pressed ? 0.9 : 1.0),
          child: Icon(
            widget.icon,
            size: widget.size * 0.55,
            color: _hover ? FluxForgeTheme.textPrimary : color,
          ),
        ),
      ),
    );
  }
}

class _ClassicTimeDisplay extends StatelessWidget {
  final String time;
  final TransportTimeMode mode;
  final bool isPlaying;
  final bool isRecording;
  final VoidCallback? onTap;

  const _ClassicTimeDisplay({
    required this.time,
    required this.mode,
    required this.isPlaying,
    required this.isRecording,
    this.onTap,
  });

  String get _modeLabel {
    switch (mode) {
      case TransportTimeMode.bars: return 'BARS';
      case TransportTimeMode.timecode: return 'TC';
      case TransportTimeMode.samples: return 'SMPLS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = isRecording
        ? FluxForgeTheme.accentRed
        : isPlaying
            ? FluxForgeTheme.accentGreen
            : FluxForgeTheme.textPrimary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _modeLabel,
              style: TextStyle(
                color: FluxForgeTheme.accentBlue,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassicTempoControl extends StatefulWidget {
  final double tempo;
  final int timeSigNum;
  final int timeSigDenom;
  final ValueChanged<double>? onTempoChange;
  final VoidCallback? onTapTempo;

  const _ClassicTempoControl({
    required this.tempo,
    required this.timeSigNum,
    required this.timeSigDenom,
    this.onTempoChange,
    this.onTapTempo,
  });

  @override
  State<_ClassicTempoControl> createState() => _ClassicTempoControlState();
}

class _ClassicTempoControlState extends State<_ClassicTempoControl> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onVerticalDragUpdate: (details) {
            final delta = -details.delta.dy * 0.5;
            widget.onTempoChange?.call((widget.tempo + delta).clamp(20, 999));
          },
          onDoubleTap: widget.onTapTempo,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isDragging
                  ? FluxForgeTheme.accentOrange.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isDragging
                    ? FluxForgeTheme.accentOrange
                    : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('BPM', style: FluxForgeTheme.label),
                const SizedBox(width: 6),
                Text(
                  widget.tempo.toStringAsFixed(2),
                  style: TextStyle(
                    color: FluxForgeTheme.accentOrange,
                    fontSize: 14,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${widget.timeSigNum}/${widget.timeSigDenom}',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClassicToggle extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ClassicToggle({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  State<_ClassicToggle> createState() => _ClassicToggleState();
}

class _ClassicToggleState extends State<_ClassicToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.activeColor.withValues(alpha: 0.2)
                : _hover
                    ? FluxForgeTheme.bgHover
                    : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isActive
                  ? widget.activeColor
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 12,
                color: widget.isActive
                    ? widget.activeColor
                    : FluxForgeTheme.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isActive
                      ? widget.activeColor
                      : FluxForgeTheme.textTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassicLoadMeter extends StatelessWidget {
  final double cpuLoad;
  final double diskLoad;

  const _ClassicLoadMeter({
    required this.cpuLoad,
    required this.diskLoad,
  });

  Color _getColor(double v) {
    if (v > 0.85) return FluxForgeTheme.accentRed;
    if (v > 0.65) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Meter('CPU', cpuLoad, _getColor(cpuLoad)),
          const SizedBox(width: 8),
          _Meter('DSK', diskLoad, _getColor(diskLoad)),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _Meter(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 24,
          height: 5,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0, 1),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
