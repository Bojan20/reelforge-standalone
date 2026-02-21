/// Send Slot Widget — Pro Tools style send slot for mixer strip
///
/// Compact row: destination label + level knob + pre/post indicator + mute button
/// Uses existing send FFI for level, destination, pre/post fader.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'ultimate_mixer.dart' show SendData, SendTapPoint;

// ═══════════════════════════════════════════════════════════════════════════
// SEND SLOT WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Compact send slot row for mixer strip.
/// Shows: destination label + level indicator + pre/post badge + mute dot.
class SendSlotWidget extends StatelessWidget {
  final SendData send;
  final bool isNarrow; // 56px vs 90px strip
  final String slotLabel; // "A", "B", etc.
  final ValueChanged<double>? onLevelChanged;
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
    this.onDestinationChanged,
    this.onMuteToggle,
    this.onPrePostToggle,
    this.onTapPointChanged,
    this.availableDestinations = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (send.isEmpty) {
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
          if (availableDestinations.isNotEmpty) {
            onDestinationChanged?.call(availableDestinations.first);
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
                slotLabel,
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
    final levelDb = _linearToDb(send.level);
    final levelText = levelDb <= -60 ? '-∞' : '${levelDb.toStringAsFixed(0)}';

    return SizedBox(
      height: 18,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: send.muted
              ? const Color(0xFF1A1215)
              : const Color(0xFF14141A),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: send.muted
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
                  isNarrow ? _abbreviate(send.destination ?? '') : (send.destination ?? ''),
                  style: TextStyle(
                    color: send.muted
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
            // Level indicator
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                // Drag to adjust send level
                final delta = details.primaryDelta ?? 0;
                final newLevel = (send.level + delta * 0.005).clamp(0.0, 2.0);
                onLevelChanged?.call(newLevel);
              },
              child: Container(
                width: 22,
                alignment: Alignment.center,
                child: Text(
                  levelText,
                  style: TextStyle(
                    color: send.level > 1.0
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
              onTap: onMuteToggle,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: send.muted
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

  Widget _buildPrePostBadge() {
    final isPreFader = send.tapPoint == SendTapPoint.preFader ||
                       send.tapPoint == SendTapPoint.preMute;
    return GestureDetector(
      onTap: onPrePostToggle,
      child: Container(
        width: 12,
        height: 12,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isPreFader
              ? const Color(0xFF1A3020)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isPreFader
                ? const Color(0xFF40FF90)
                : const Color(0xFF444455),
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
