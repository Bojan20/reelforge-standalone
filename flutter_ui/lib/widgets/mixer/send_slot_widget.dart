/// Send Slot Widget — Pro Tools style send slot for mixer strip
///
/// Compact row: destination label + level knob + pan slider + pre/post indicator + mute button
/// Uses existing send FFI for level, destination, pre/post fader, and pan.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'ultimate_mixer.dart' show SendData, SendTapPoint;

// ═══════════════════════════════════════════════════════════════════════════
// SEND SLOT WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Compact send slot row for mixer strip.
/// Shows: destination label + level indicator + pan slider + pre/post badge + mute dot.
class SendSlotWidget extends StatefulWidget {
  final SendData send;
  final bool isNarrow; // 56px vs 90px strip
  final String slotLabel; // "A", "B", etc.
  final ValueChanged<double>? onLevelChanged;
  final ValueChanged<double>? onPanChanged;
  final ValueChanged<String>? onDestinationChanged;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onPrePostToggle;
  final VoidCallback? onTapPointChanged;
  final List<String> availableDestinations;

  const SendSlotWidget({
    super.key,
    required this.send,
    this.isNarrow = false,
    this.slotLabel = '',
    this.onLevelChanged,
    this.onPanChanged,
    this.onDestinationChanged,
    this.onMuteToggle,
    this.onPrePostToggle,
    this.onTapPointChanged,
    this.availableDestinations = const [],
  });

  @override
  State<SendSlotWidget> createState() => _SendSlotWidgetState();
}

class _SendSlotWidgetState extends State<SendSlotWidget> {
  /// Local optimistic pan value while dragging, null when not dragging.
  double? _draggingPan;

  @override
  Widget build(BuildContext context) {
    if (widget.send.isEmpty) {
      return _buildEmptySlot();
    }
    return _buildActiveSlot();
  }

  Widget _buildEmptySlot() {
    return SizedBox(
      height: 18,
      child: GestureDetector(
        onTap: () {
          // Empty slot click → open destination picker
          if (widget.availableDestinations.isNotEmpty) {
            widget.onDestinationChanged?.call(widget.availableDestinations.first);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF111117),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: const Color(0xFF2A2A35),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Slot label
              Text(
                widget.slotLabel,
                style: const TextStyle(
                  color: Color(0xFF555566),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Empty indicator
              const Text(
                '—',
                style: TextStyle(
                  color: Color(0xFF444455),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSlot() {
    final levelDb = _linearToDb(widget.send.level);
    final levelText = levelDb <= -60 ? '-∞' : '${levelDb.toStringAsFixed(0)}';
    final pan = _draggingPan ?? widget.send.pan;

    return SizedBox(
      height: 18,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: widget.send.muted
              ? const Color(0xFF1A1215)
              : const Color(0xFF14141A),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: widget.send.muted
                ? const Color(0xFF4A2020)
                : const Color(0xFF333340),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            // Pre/Post badge
            _buildPrePostBadge(),
            const SizedBox(width: 2),
            // Destination name
            Expanded(
              child: GestureDetector(
                onTap: () => _showDestinationPicker(),
                child: Text(
                  widget.isNarrow
                      ? _abbreviate(widget.send.destination ?? '')
                      : (widget.send.destination ?? ''),
                  style: TextStyle(
                    color: widget.send.muted
                        ? const Color(0xFF666680)
                        : const Color(0xFFCCCCDD),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
            // Pan slider — drag left/right to pan -1.0..1.0, double-tap to center
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                final delta = details.primaryDelta ?? 0;
                // 30px full-width drag covers the 2.0 range (-1 to +1)
                final newPan = (pan + delta * (2.0 / 30.0)).clamp(-1.0, 1.0);
                setState(() => _draggingPan = newPan);
                widget.onPanChanged?.call(newPan);
              },
              onHorizontalDragEnd: (_) {
                setState(() => _draggingPan = null);
              },
              onDoubleTap: () {
                setState(() => _draggingPan = null);
                widget.onPanChanged?.call(0.0);
              },
              child: _buildPanBar(pan),
            ),
            const SizedBox(width: 2),
            // Level indicator
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                // Drag to adjust send level
                final delta = details.primaryDelta ?? 0;
                final newLevel =
                    (widget.send.level + delta * 0.005).clamp(0.0, 2.0);
                widget.onLevelChanged?.call(newLevel);
              },
              child: Container(
                width: 22,
                alignment: Alignment.center,
                child: Text(
                  levelText,
                  style: TextStyle(
                    color: widget.send.level > 1.0
                        ? const Color(0xFFFF9040)
                        : const Color(0xFF9999AA),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            // Mute dot
            GestureDetector(
              onTap: widget.onMuteToggle,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.send.muted
                      ? const Color(0xFFFF4060)
                      : const Color(0xFF333340),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small pan bar: 28px wide, filled left or right of center based on pan value.
  Widget _buildPanBar(double pan) {
    // pan: -1.0 (L) to 0.0 (C) to 1.0 (R)
    final isCentered = pan.abs() < 0.03;
    final panColor = isCentered
        ? const Color(0xFF444455)
        : const Color(0xFF4A9EFF);

    return Tooltip(
      message: isCentered
          ? 'Pan: C (drag to adjust, double-tap to center)'
          : 'Pan: ${_panLabel(pan)} (drag to adjust, double-tap to center)',
      waitDuration: const Duration(milliseconds: 600),
      child: SizedBox(
        width: 28,
        height: 10,
        child: CustomPaint(
          painter: _PanBarPainter(pan: pan, color: panColor),
        ),
      ),
    );
  }

  String _panLabel(double pan) {
    if (pan.abs() < 0.03) return 'C';
    final side = pan < 0 ? 'L' : 'R';
    final pct = (pan.abs() * 100).round();
    return '$side$pct';
  }

  Widget _buildPrePostBadge() {
    final isPreFader = widget.send.tapPoint == SendTapPoint.preFader ||
        widget.send.tapPoint == SendTapPoint.preMute;
    return GestureDetector(
      onTap: widget.onPrePostToggle,
      child: Container(
        width: 12,
        height: 12,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isPreFader ? const Color(0xFF1A3020) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color:
                isPreFader ? const Color(0xFF40FF90) : const Color(0xFF444455),
            width: 0.5,
          ),
        ),
        child: Text(
          isPreFader ? 'P' : '',
          style: TextStyle(
            color: isPreFader
                ? const Color(0xFF40FF90)
                : const Color(0xFF555566),
            fontSize: 7,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _showDestinationPicker() {
    // Destination change is handled via callback
    // Parent should show a proper popup with availableDestinations
  }

  String _abbreviate(String name) {
    if (name.length <= 3) return name;
    if (name.startsWith('Bus ')) return 'B${name.substring(4)}';
    if (name.startsWith('Aux ')) return 'A${name.substring(4)}';
    if (name == 'Reverb A') return 'RvA';
    if (name == 'Reverb B') return 'RvB';
    if (name == 'Delay') return 'Dly';
    return name.substring(0, 3);
  }

  static double _linearToDb(double linear) {
    if (linear <= 0.001) return -60.0;
    return 20.0 * math.log(linear) / math.ln10;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAN BAR PAINTER
// ═══════════════════════════════════════════════════════════════════════════

/// Draws a compact pan bar: center line + filled region indicating pan position.
class _PanBarPainter extends CustomPainter {
  final double pan; // -1.0 to 1.0
  final Color color;

  const _PanBarPainter({required this.pan, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = const Color(0xFF2A2A35)
      ..style = PaintingStyle.fill;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final centerPaint = Paint()
      ..color = const Color(0xFF555566)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final trackRect =
        Rect.fromLTWH(0, size.height * 0.3, size.width, size.height * 0.4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, const Radius.circular(1)),
      trackPaint,
    );

    final centerX = size.width / 2.0;
    final fillX = centerX + pan * (size.width / 2.0);

    final left = math.min(centerX, fillX);
    final right = math.max(centerX, fillX);
    if ((right - left) > 0.5) {
      final fillRect =
          Rect.fromLTWH(left, size.height * 0.3, right - left, size.height * 0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(1)),
        fillPaint,
      );
    }

    // Center tick
    canvas.drawLine(
      Offset(centerX, size.height * 0.1),
      Offset(centerX, size.height * 0.9),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(_PanBarPainter old) => old.pan != pan || old.color != color;
}
