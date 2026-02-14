// SlotLab Bus Mixer — Vertical fader mixer for SlotLab Lower Zone
//
// Professional mixer with vertical faders, peak meters, mute/solo,
// and pan knobs for all SlotLab audio buses.
// Connected to MixerDSPProvider → FFI → Rust engine.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/mixer_dsp_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Bus colors for visual identification
const Map<String, Color> _busColors = {
  'master': Color(0xFFE0E0E0),
  'music': Color(0xFF4A9EFF),
  'sfx': Color(0xFFFF9040),
  'voice': Color(0xFF40FF90),
  'ambience': Color(0xFF40C8FF),
  'ui': Color(0xFFCCCCCC),
  'reels': Color(0xFFFFD700),
  'wins': Color(0xFFFF4060),
};

/// Vertical fader mixer for SlotLab Lower Zone.
/// Displays all buses as vertical channel strips with faders, meters, M/S, pan.
class SlotLabBusMixer extends StatelessWidget {
  const SlotLabBusMixer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerDSPProvider>(
      builder: (context, provider, _) {
        final buses = provider.buses;
        final hasSolo = buses.any((b) => b.solo);

        return Container(
          color: FluxForgeTheme.bgDeepest,
          child: Row(
            children: [
              // Bus strips — horizontally scrollable
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(width: 2),
                      // Non-master buses first
                      ...buses.where((b) => b.id != 'master').map((bus) =>
                        _BusStrip(
                          key: ValueKey('bus_${bus.id}'),
                          bus: bus,
                          color: _busColors[bus.id] ?? const Color(0xFF808080),
                          hasSoloActive: hasSolo,
                          onVolumeChange: (v) => provider.setBusVolume(bus.id, v),
                          onPanChange: (p) => provider.setBusPan(bus.id, p),
                          onMuteToggle: () => provider.toggleMute(bus.id),
                          onSoloToggle: () => provider.toggleSolo(bus.id),
                        ),
                      ),
                      // Divider before master
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: FluxForgeTheme.textPrimary.withOpacity(0.15),
                      ),
                      // Master bus (wider)
                      ...buses.where((b) => b.id == 'master').map((bus) =>
                        _BusStrip(
                          key: const ValueKey('bus_master'),
                          bus: bus,
                          color: _busColors['master']!,
                          hasSoloActive: false,
                          isMaster: true,
                          onVolumeChange: (v) => provider.setBusVolume(bus.id, v),
                          onPanChange: (p) => provider.setBusPan(bus.id, p),
                          onMuteToggle: () => provider.toggleMute(bus.id),
                          onSoloToggle: () => provider.toggleSolo(bus.id),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Single bus channel strip with vertical fader
class _BusStrip extends StatefulWidget {
  final MixerBus bus;
  final Color color;
  final bool hasSoloActive;
  final bool isMaster;
  final ValueChanged<double> onVolumeChange;
  final ValueChanged<double> onPanChange;
  final VoidCallback onMuteToggle;
  final VoidCallback onSoloToggle;

  const _BusStrip({
    super.key,
    required this.bus,
    required this.color,
    required this.hasSoloActive,
    this.isMaster = false,
    required this.onVolumeChange,
    required this.onPanChange,
    required this.onMuteToggle,
    required this.onSoloToggle,
  });

  @override
  State<_BusStrip> createState() => _BusStripState();
}

class _BusStripState extends State<_BusStrip> {
  bool _isDraggingFader = false;

  String _volumeToDb(double volume) {
    if (volume <= 0.001) return '-inf';
    final db = 20 * math.log(volume) / math.ln10;
    if (db >= 0) return '+${db.toStringAsFixed(1)}';
    return db.toStringAsFixed(1);
  }

  String _panToString(double pan) {
    if (pan.abs() < 0.02) return 'C';
    final pct = (pan.abs() * 100).round();
    return pan < 0 ? '${pct}L' : '${pct}R';
  }

  @override
  Widget build(BuildContext context) {
    final bus = widget.bus;
    final isDimmed = widget.hasSoloActive && !bus.solo;
    final stripWidth = widget.isMaster ? 72.0 : 58.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: isDimmed ? 0.35 : 1.0,
      child: Container(
        width: stripWidth,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: FluxForgeTheme.textPrimary.withOpacity(0.06),
          ),
        ),
        child: Column(
          children: [
            // Color bar
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ),
            // Pan knob
            _buildPanControl(),
            // Fader + meter (fills remaining space)
            Expanded(child: _buildFaderWithMeter()),
            // dB readout
            _buildDbReadout(),
            // M / S buttons
            _buildMuteSolo(),
            // Bus name
            _buildNameLabel(),
          ],
        ),
      ),
    );
  }

  Widget _buildPanControl() {
    final pan = widget.bus.pan;
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final newPan = (pan + details.delta.dx / 50).clamp(-1.0, 1.0);
        widget.onPanChange(newPan);
      },
      onDoubleTap: () => widget.onPanChange(0.0),
      child: Container(
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.textPrimary.withOpacity(0.08)),
        ),
        child: Stack(
          children: [
            // Center tick
            Center(child: Container(width: 1, height: 8, color: FluxForgeTheme.textPrimary.withOpacity(0.15))),
            // Pan indicator
            Center(
              child: Transform.translate(
                offset: Offset(pan * (widget.isMaster ? 26 : 20), 0),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: pan.abs() < 0.02 ? FluxForgeTheme.textSecondary : widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            // L/R labels
            Positioned(
              left: 3, top: 2,
              child: Text('L', style: TextStyle(fontSize: 7, color: FluxForgeTheme.textPrimary.withOpacity(0.25))),
            ),
            Positioned(
              right: 3, top: 2,
              child: Text('R', style: TextStyle(fontSize: 7, color: FluxForgeTheme.textPrimary.withOpacity(0.25))),
            ),
            // Pan value
            Positioned(
              bottom: 1, left: 0, right: 0,
              child: Text(
                _panToString(pan),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 7, color: FluxForgeTheme.textPrimary.withOpacity(0.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaderWithMeter() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final faderHeight = constraints.maxHeight;
        final volume = widget.bus.volume;
        // Map volume 0-1 to fader position (bottom=0, top=1)
        final faderPos = volume.clamp(0.0, 1.0);

        return GestureDetector(
          onVerticalDragStart: (_) => setState(() => _isDraggingFader = true),
          onVerticalDragEnd: (_) => setState(() => _isDraggingFader = false),
          onVerticalDragUpdate: (details) {
            // Drag up = increase volume
            final delta = -details.delta.dy / faderHeight;
            final newVolume = (volume + delta).clamp(0.0, 1.0);
            widget.onVolumeChange(newVolume);
          },
          onDoubleTap: () => widget.onVolumeChange(0.85), // Reset to default
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: CustomPaint(
              painter: _FaderPainter(
                volume: faderPos,
                color: widget.color,
                muted: widget.bus.muted,
                isDragging: _isDraggingFader,
                isMaster: widget.isMaster,
              ),
              size: Size(constraints.maxWidth - 8, faderHeight),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDbReadout() {
    return Container(
      height: 16,
      alignment: Alignment.center,
      child: Text(
        _volumeToDb(widget.bus.volume),
        style: TextStyle(
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: widget.bus.volume > 0.95
              ? const Color(0xFFFF6B6B)
              : FluxForgeTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildMuteSolo() {
    return Container(
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        children: [
          // Mute
          Expanded(
            child: GestureDetector(
              onTap: widget.onMuteToggle,
              child: Container(
                margin: const EdgeInsets.only(right: 1),
                decoration: BoxDecoration(
                  color: widget.bus.muted
                      ? const Color(0xFFFF4060)
                      : FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: widget.bus.muted
                        ? const Color(0xFFFF4060)
                        : FluxForgeTheme.textPrimary.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'M',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: widget.bus.muted
                        ? Colors.white
                        : FluxForgeTheme.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          // Solo
          Expanded(
            child: GestureDetector(
              onTap: widget.onSoloToggle,
              child: Container(
                margin: const EdgeInsets.only(left: 1),
                decoration: BoxDecoration(
                  color: widget.bus.solo
                      ? const Color(0xFFFFD700)
                      : FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: widget.bus.solo
                        ? const Color(0xFFFFD700)
                        : FluxForgeTheme.textPrimary.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'S',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: widget.bus.solo
                        ? const Color(0xFF1a1a20)
                        : FluxForgeTheme.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameLabel() {
    return Container(
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.12),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
      ),
      child: Text(
        widget.bus.name.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: widget.color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Custom painter for the vertical fader track with meter-style fill
class _FaderPainter extends CustomPainter {
  final double volume;
  final Color color;
  final bool muted;
  final bool isDragging;
  final bool isMaster;

  _FaderPainter({
    required this.volume,
    required this.color,
    required this.muted,
    required this.isDragging,
    required this.isMaster,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackWidth = isMaster ? 10.0 : 6.0;
    final trackX = (size.width - trackWidth) / 2;
    final trackTop = 6.0;
    final trackBottom = size.height - 6;
    final trackHeight = trackBottom - trackTop;

    // Fader track background
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(trackX, trackTop, trackWidth, trackHeight),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      trackRect,
      Paint()..color = const Color(0xFF0a0a0c),
    );

    // Track border
    canvas.drawRRect(
      trackRect,
      Paint()
        ..color = const Color(0xFF2a2a35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // dB scale ticks
    final tickPaint = Paint()
      ..color = const Color(0xFF3a3a45)
      ..strokeWidth = 0.5;
    // 0dB, -6, -12, -24, -48 marks
    final dbMarks = [1.0, 0.5012, 0.2512, 0.0631, 0.004]; // linear values
    for (final mark in dbMarks) {
      final y = trackBottom - (mark * trackHeight);
      canvas.drawLine(
        Offset(trackX - 3, y),
        Offset(trackX, y),
        tickPaint,
      );
      canvas.drawLine(
        Offset(trackX + trackWidth, y),
        Offset(trackX + trackWidth + 3, y),
        tickPaint,
      );
    }

    // Unity gain (0dB) mark — brighter
    final unityY = trackBottom - (0.85 * trackHeight); // 0.85 ≈ -1.4dB, close to unity
    canvas.drawLine(
      Offset(trackX - 4, unityY),
      Offset(trackX + trackWidth + 4, unityY),
      Paint()
        ..color = const Color(0xFF555565)
        ..strokeWidth = 0.5,
    );

    // Meter fill (from bottom up to volume level)
    if (volume > 0.001 && !muted) {
      final fillHeight = volume * trackHeight;
      final fillTop = trackBottom - fillHeight;

      // Gradient fill: green → yellow → red
      final fillRect = Rect.fromLTWH(trackX + 1, fillTop, trackWidth - 2, fillHeight);
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: const [
          Color(0xFF40FF90), // Green (low)
          Color(0xFF40FF90), // Green
          Color(0xFFFFFF40), // Yellow (mid)
          Color(0xFFFF9040), // Orange (high)
          Color(0xFFFF4040), // Red (clip)
        ],
        stops: const [0.0, 0.5, 0.7, 0.85, 1.0],
      );
      canvas.drawRect(
        fillRect,
        Paint()..shader = gradient.createShader(
          Rect.fromLTWH(trackX + 1, trackTop, trackWidth - 2, trackHeight),
        ),
      );
    }

    // Fader cap / thumb
    final thumbY = trackBottom - (volume * trackHeight);
    final thumbWidth = trackWidth + 10;
    final thumbHeight = isDragging ? 10.0 : 8.0;
    final thumbX = trackX - 5;

    // Thumb shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(trackX + trackWidth / 2, thumbY + 1),
          width: thumbWidth,
          height: thumbHeight,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.black.withOpacity(0.4),
    );

    // Thumb body
    final thumbColor = muted
        ? const Color(0xFF555555)
        : isDragging
            ? color
            : const Color(0xFFBBBBCC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(trackX + trackWidth / 2, thumbY),
          width: thumbWidth,
          height: thumbHeight,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = thumbColor,
    );

    // Thumb center line
    canvas.drawLine(
      Offset(trackX + trackWidth / 2 - 3, thumbY),
      Offset(trackX + trackWidth / 2 + 3, thumbY),
      Paint()
        ..color = const Color(0xFF333333)
        ..strokeWidth = 0.5,
    );

    // Muted overlay
    if (muted) {
      canvas.drawRRect(
        trackRect,
        Paint()..color = const Color(0x44FF4060),
      );
    }
  }

  @override
  bool shouldRepaint(_FaderPainter oldDelegate) {
    return volume != oldDelegate.volume ||
        muted != oldDelegate.muted ||
        isDragging != oldDelegate.isDragging;
  }
}
