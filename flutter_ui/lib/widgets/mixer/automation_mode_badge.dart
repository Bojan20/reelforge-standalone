/// Automation Mode Badge — Pro Tools style automation mode indicator
///
/// PopupMenuButton showing current automation mode with color coding.
/// Modes: Off, Read, Touch, Write, Latch, Touch/Latch, Trim
/// NOTE: UI-only state in Phase 2 — FFI wiring in Phase 4.

import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION MODE
// ═══════════════════════════════════════════════════════════════════════════

enum AutomationMode {
  off,
  read,
  touch,
  write,
  latch,
  touchLatch,
  trim;

  String get label => switch (this) {
    AutomationMode.off => 'off',
    AutomationMode.read => 'read',
    AutomationMode.touch => 'tch',
    AutomationMode.write => 'wrt',
    AutomationMode.latch => 'ltch',
    AutomationMode.touchLatch => 't/l',
    AutomationMode.trim => 'trim',
  };

  String get fullLabel => switch (this) {
    AutomationMode.off => 'Off',
    AutomationMode.read => 'Read',
    AutomationMode.touch => 'Touch',
    AutomationMode.write => 'Write',
    AutomationMode.latch => 'Latch',
    AutomationMode.touchLatch => 'Touch/Latch',
    AutomationMode.trim => 'Trim',
  };

  Color get color => switch (this) {
    AutomationMode.off => const Color(0xFF666680),
    AutomationMode.read => const Color(0xFF40FF90),
    AutomationMode.touch => const Color(0xFF4A9EFF),
    AutomationMode.write => const Color(0xFFFF4060),
    AutomationMode.latch => const Color(0xFFFFD740),
    AutomationMode.touchLatch => const Color(0xFF40C8FF),
    AutomationMode.trim => const Color(0xFFFF9040),
  };

  Color get bgColor => switch (this) {
    AutomationMode.off => const Color(0xFF1A1A20),
    AutomationMode.read => const Color(0xFF0D2D1A),
    AutomationMode.touch => const Color(0xFF0D1A2D),
    AutomationMode.write => const Color(0xFF2D0D15),
    AutomationMode.latch => const Color(0xFF2D2D0D),
    AutomationMode.touchLatch => const Color(0xFF0D2030),
    AutomationMode.trim => const Color(0xFF2D1A0D),
  };

  /// Whether this mode writes automation data
  bool get isWriteMode => switch (this) {
    AutomationMode.write || AutomationMode.latch ||
    AutomationMode.touch || AutomationMode.touchLatch ||
    AutomationMode.trim => true,
    _ => false,
  };

  /// Short description for tooltips
  String get description => switch (this) {
    AutomationMode.off => 'No automation playback or writing',
    AutomationMode.read => 'Plays back existing automation',
    AutomationMode.touch => 'Writes while touching, returns on release',
    AutomationMode.write => 'Overwrites all automation data',
    AutomationMode.latch => 'Writes from first touch, holds value',
    AutomationMode.touchLatch => 'Touch to start, latches on release',
    AutomationMode.trim => 'Offsets existing data by delta amount',
  };

  static AutomationMode fromString(String s) => switch (s) {
    'off' => AutomationMode.off,
    'read' => AutomationMode.read,
    'tch' || 'touch' => AutomationMode.touch,
    'wrt' || 'write' => AutomationMode.write,
    'ltch' || 'latch' => AutomationMode.latch,
    't/l' || 'touchlatch' || 'touch/latch' => AutomationMode.touchLatch,
    'trim' => AutomationMode.trim,
    _ => AutomationMode.read,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION MODE BADGE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Color-coded automation mode badge with popup selector.
/// When in Trim mode, shows the current trim offset (delta dB).
class AutomationModeBadge extends StatelessWidget {
  final AutomationMode mode;
  final ValueChanged<AutomationMode>? onModeChanged;
  final bool isNarrow; // 56px strip mode
  final double trimDeltaDb; // Trim offset in dB (only shown in trim mode)

  const AutomationModeBadge({
    super.key,
    required this.mode,
    this.onModeChanged,
    this.isNarrow = false,
    this.trimDeltaDb = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: PopupMenuButton<AutomationMode>(
        padding: EdgeInsets.zero,
        tooltip: 'Automation: ${mode.fullLabel}',
        onSelected: onModeChanged,
        offset: const Offset(0, 16),
        color: const Color(0xFF1E1E24),
        constraints: const BoxConstraints(minWidth: 130),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: mode.color.withValues(alpha: 0.3)),
        ),
        itemBuilder: (_) => AutomationMode.values.map((m) {
          final isSelected = m == mode;
          return PopupMenuItem<AutomationMode>(
            value: m,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // Color dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: m.color,
                  ),
                ),
                const SizedBox(width: 8),
                // Label
                Text(
                  m.fullLabel,
                  style: TextStyle(
                    color: isSelected ? m.color : const Color(0xFFCCCCDD),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                // Check mark
                if (isSelected)
                  Icon(Icons.check, size: 12, color: m.color),
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: mode.bgColor,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: mode.color.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          child: Center(
            child: mode == AutomationMode.trim && !isNarrow && trimDeltaDb != 0.0
                ? Text(
                    '${trimDeltaDb >= 0 ? '+' : ''}${trimDeltaDb.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: mode.color,
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : Text(
                    isNarrow ? mode.label.substring(0, (mode.label.length).clamp(0, 2)) : mode.label,
                    style: TextStyle(
                      color: mode.color,
                      fontSize: isNarrow ? 7 : 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
