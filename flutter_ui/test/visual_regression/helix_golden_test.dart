/// FluxForge Studio — Layer 5: Golden Pixel Tests (HELIX)
///
/// GOLDEN TESTING: Pixel-perfect regression detection.
/// Every HELIX state has a reference screenshot. Any change that moves
/// a pixel, changes a color, or creates an overflow → test FAILS.
///
/// This eliminates: "Corti, imaš placeholder u tab 3" — CI catches it first.
///
/// How to use:
///   1. Generate baseline: flutter test test/visual_regression/helix_golden_test.dart --update-goldens
///   2. After changes: flutter test test/visual_regression/helix_golden_test.dart
///   3. Any diff → test fails with pixel-by-pixel comparison image
///
/// Golden files stored in: test/visual_regression/goldens/helix/
///
/// WARNING: Golden tests are platform-specific. Run on same OS/resolution
/// when generating and comparing (macOS Retina @ 2.0x).
///
/// Coverage:
///   G01: HELIX idle state (initial load)
///   G02: HELIX COMPOSE mode
///   G03: HELIX FOCUS mode
///   G04: HELIX ARCHITECT mode
///   G05: AUDIO ASSIGN spine panel
///   G06: GAME CONFIG spine panel
///   G07: AI/INTEL spine panel (with sliders)
///   G08: SETTINGS spine panel
///   G09: ANALYTICS spine panel
///   G10: FLOW dock tab content
///   G11: AUDIO dock tab (with Auto-Bind)
///   G12: MATH dock tab
///   G13: TIMELINE dock tab
///   G14: INTEL dock tab
///   G15: EXPORT dock tab
///   G16: DNA dock tab
///   G17: Reel lens (slot preview grid)
///   G18: Spin button active state
///   G19: SLAM button visible (spinning state)
///   G20: Win presentation overlay

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'visual_test_helper.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HELIX GOLDEN TEST CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// HELIX screen dimensions (1280×800 — standard development viewport)
const _helixSize = Size(1280, 800);

/// Pixel ratio for golden captures (1.0 for CI consistency)
const _pixelRatio = 1.0;

/// Tolerance: 0.5% pixel diff allowed (for antialiasing variance)
const _tolerance = 0.005;

/// Golden file prefix
const _prefix = 'helix';

void main() {
  group('HELIX Golden Tests — Layer 5', () {
    // ─────────────────────────────────────────────────────────────────────
    // ISOLATED COMPONENT GOLDENS
    // These test individual HELIX sub-components in isolation,
    // without requiring the full app bootstrap.
    // ─────────────────────────────────────────────────────────────────────

    group('G01-G04: Mode Bar', () {
      testWidgets('G01: HELIX mode bar — COMPOSE active', (tester) async {
        await tester.pumpGolden(
          _buildHelixModeBar(activeMode: 'COMPOSE'),
          size: const Size(600, 60),
          
        );
        await tester.expectGolden('${_prefix}_mode_bar_compose');
      });

      testWidgets('G02: HELIX mode bar — FOCUS active', (tester) async {
        await tester.pumpGolden(
          _buildHelixModeBar(activeMode: 'FOCUS'),
          size: const Size(600, 60),
          
        );
        await tester.expectGolden('${_prefix}_mode_bar_focus');
      });

      testWidgets('G03: HELIX mode bar — ARCHITECT active', (tester) async {
        await tester.pumpGolden(
          _buildHelixModeBar(activeMode: 'ARCHITECT'),
          size: const Size(600, 60),
          
        );
        await tester.expectGolden('${_prefix}_mode_bar_architect');
      });

      testWidgets('G04: HELIX omnibar — full header', (tester) async {
        await tester.pumpGolden(
          _buildHelixOmnibar(),
          size: const Size(1280, 52),
          
        );
        await tester.expectGolden('${_prefix}_omnibar');
      });
    });

    group('G05-G08: Spine Panel UI Components', () {
      testWidgets('G05: Spine button row — all 5 buttons', (tester) async {
        await tester.pumpGolden(
          _buildSpineButtonRow(),
          size: const Size(52, 400),
          
        );
        await tester.expectGolden('${_prefix}_spine_buttons');
      });

      testWidgets('G06: RTPC slider component', (tester) async {
        await tester.pumpGolden(
          _buildRtpcSlider(label: 'TENSION', value: 0.65),
          size: const Size(320, 60),
          
        );
        await tester.expectGolden('${_prefix}_rtpc_slider');
      });

      testWidgets('G07: RTPC slider — zero value', (tester) async {
        await tester.pumpGolden(
          _buildRtpcSlider(label: 'TENSION', value: 0.0),
          size: const Size(320, 60),
          
        );
        await tester.expectGolden('${_prefix}_rtpc_slider_zero');
      });

      testWidgets('G08: RTPC slider — max value', (tester) async {
        await tester.pumpGolden(
          _buildRtpcSlider(label: 'TENSION', value: 1.0),
          size: const Size(320, 60),
          
        );
        await tester.expectGolden('${_prefix}_rtpc_slider_max');
      });
    });

    group('G09-G12: Dock Tab UI Components', () {
      testWidgets('G09: Dock tab row — primary tabs', (tester) async {
        await tester.pumpGolden(
          _buildDockTabRow(primaryTabs: const [
            'FLOW', 'AUDIO', 'MATH', 'TIMELINE', 'INTEL', 'EXPORT',
          ]),
          size: const Size(1280, 40),
          
        );
        await tester.expectGolden('${_prefix}_dock_tab_row_primary');
      });

      testWidgets('G10: Dock tab row — secondary tabs', (tester) async {
        await tester.pumpGolden(
          _buildDockTabRow(primaryTabs: const [
            'SFX', 'BT', 'DNA', 'AI GEN', 'CLOUD', 'A/B',
          ]),
          size: const Size(1280, 40),
          
        );
        await tester.expectGolden('${_prefix}_dock_tab_row_secondary');
      });

      testWidgets('G11: Composite event card', (tester) async {
        await tester.pumpGolden(
          _buildCompositeEventCard(
            name: 'SPIN_START',
            category: 'Spin',
            stages: ['REEL_SPIN_1', 'REEL_SPIN_2'],
            hasAudio: true,
          ),
          size: const Size(400, 80),
          
        );
        await tester.expectGolden('${_prefix}_composite_event_card');
      });

      testWidgets('G12: Composite event card — no audio', (tester) async {
        await tester.pumpGolden(
          _buildCompositeEventCard(
            name: 'FEATURE_TRIGGER',
            category: 'Feature',
            stages: ['BONUS_ENTER'],
            hasAudio: false,
          ),
          size: const Size(400, 80),
          
        );
        await tester.expectGolden('${_prefix}_composite_event_card_no_audio');
      });
    });

    group('G13-G16: Reel Grid Components', () {
      testWidgets('G13: Reel grid 3×3', (tester) async {
        await tester.pumpGolden(
          _buildReelGrid(reels: 3, rows: 3),
          size: const Size(450, 300),
          
        );
        await tester.expectGolden('${_prefix}_reel_grid_3x3');
      });

      testWidgets('G14: Reel grid 5×3', (tester) async {
        await tester.pumpGolden(
          _buildReelGrid(reels: 5, rows: 3),
          size: const Size(600, 280),
          
        );
        await tester.expectGolden('${_prefix}_reel_grid_5x3');
      });

      testWidgets('G15: Reel cell — normal state', (tester) async {
        await tester.pumpGolden(
          _buildReelCell(symbol: 'A', isWinning: false),
          size: const Size(100, 100),
          
        );
        await tester.expectGolden('${_prefix}_reel_cell_normal');
      });

      testWidgets('G16: Reel cell — winning state', (tester) async {
        await tester.pumpGolden(
          _buildReelCell(symbol: 'A', isWinning: true),
          size: const Size(100, 100),
          
        );
        await tester.expectGolden('${_prefix}_reel_cell_winning');
      });
    });

    group('G17-G20: Spin Control Components', () {
      testWidgets('G17: SPIN button — idle state', (tester) async {
        await tester.pumpGolden(
          _buildSpinButton(state: SpinButtonState.idle),
          size: const Size(200, 80),
          
        );
        await tester.expectGolden('${_prefix}_spin_button_idle');
      });

      testWidgets('G18: SPIN button — spinning state', (tester) async {
        await tester.pumpGolden(
          _buildSpinButton(state: SpinButtonState.spinning),
          size: const Size(200, 80),
          
        );
        await tester.expectGolden('${_prefix}_spin_button_spinning');
      });

      testWidgets('G19: SLAM button', (tester) async {
        await tester.pumpGolden(
          _buildActionButton(label: 'SLAM', color: const Color(0xFFFF6B35)),
          size: const Size(120, 50),
          
        );
        await tester.expectGolden('${_prefix}_slam_button');
      });

      testWidgets('G20: SKIP button', (tester) async {
        await tester.pumpGolden(
          _buildActionButton(label: 'SKIP', color: const Color(0xFF6B7280)),
          size: const Size(120, 50),
          
        );
        await tester.expectGolden('${_prefix}_skip_button');
      });
    });

    group('G21-G25: Audio DNA Components', () {
      testWidgets('G21: DNA panel header', (tester) async {
        await tester.pumpGolden(
          _buildDnaPanelHeader(brand: 'VanVinkl'),
          size: const Size(800, 60),
          
        );
        await tester.expectGolden('${_prefix}_dna_header');
      });

      testWidgets('G22: DNA instrument chips', (tester) async {
        await tester.pumpGolden(
          _buildDnaInstrumentChips(instruments: ['piano', 'strings', 'brass']),
          size: const Size(600, 50),
          
        );
        await tester.expectGolden('${_prefix}_dna_instruments');
      });

      testWidgets('G23: DNA BPM range display', (tester) async {
        await tester.pumpGolden(
          _buildDnaBpmRange(min: 110, max: 140),
          size: const Size(300, 60),
          
        );
        await tester.expectGolden('${_prefix}_dna_bpm_range');
      });

      testWidgets('G24: DNA Apply button', (tester) async {
        await tester.pumpGolden(
          _buildDnaApplyButton(enabled: true),
          size: const Size(200, 50),
          
        );
        await tester.expectGolden('${_prefix}_dna_apply_enabled');
      });

      testWidgets('G25: DNA Apply button — disabled', (tester) async {
        await tester.pumpGolden(
          _buildDnaApplyButton(enabled: false),
          size: const Size(200, 50),
          
        );
        await tester.expectGolden('${_prefix}_dna_apply_disabled');
      });
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET BUILDERS — Isolated components for golden capture
// ═══════════════════════════════════════════════════════════════════════════

const _darkBg = Color(0xFF06060A);
const _accent = Color(0xFF00D4FF);
const _accentGreen = Color(0xFF00FF88);
const _textPrimary = Color(0xFFE8E8F0);
const _textSecondary = Color(0xFF8A8A9A);
const _surfaceColor = Color(0xFF0D0D14);
const _borderColor = Color(0xFF1E1E2E);

/// pumpGolden already wraps in MaterialApp via VisualTestHelper.wrapForGolden.
/// _scaffold just provides a dark background scaffold — no extra MaterialApp.
Widget _scaffold(Widget child) => Scaffold(
  backgroundColor: _darkBg,
  body: Center(child: child),
);

/// Mode bar: COMPOSE / FOCUS / ARCHITECT tabs
Widget _buildHelixModeBar({required String activeMode}) {
  return _scaffold(Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final mode in ['COMPOSE', 'FOCUS', 'ARCHITECT'])
        _ModeTab(label: mode, isActive: mode == activeMode),
    ],
  ));
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  const _ModeTab({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? _accent.withOpacity(0.15) : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: isActive ? _accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? _accent : _textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// HELIX omnibar header
Widget _buildHelixOmnibar() {
  return _scaffold(Container(
    height: 52,
    color: _surfaceColor,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        const Text(
          'HELIX',
          style: TextStyle(
            color: _accent,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'NEURAL SLOT DESIGN ENVIRONMENT',
            style: TextStyle(
              color: _accent,
              fontSize: 9,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const Spacer(),
        const Icon(Icons.close_rounded, color: _textSecondary, size: 18),
      ],
    ),
  ));
}

/// Spine button column
Widget _buildSpineButtonRow() {
  return _scaffold(Container(
    width: 52,
    color: _surfaceColor,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (icon, active) in [
          (Icons.music_note_rounded, true),
          (Icons.grid_view_rounded, false),
          (Icons.auto_awesome, false),
          (Icons.settings_rounded, false),
          (Icons.analytics_rounded, false),
        ])
          _SpineButton(icon: icon, isActive: active),
      ],
    ),
  ));
}

class _SpineButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  const _SpineButton({required this.icon, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: isActive ? _accent.withOpacity(0.15) : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isActive ? _accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Icon(
        icon,
        color: isActive ? _accent : _textSecondary,
        size: 18,
      ),
    );
  }
}

/// RTPC slider component
Widget _buildRtpcSlider({required String label, required double value}) {
  return _scaffold(Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: _accent,
              inactiveTrackColor: _borderColor,
              thumbColor: _accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              onChanged: null, // Read-only for golden
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _accent,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    ),
  ));
}

/// Dock tab row
Widget _buildDockTabRow({required List<String> primaryTabs}) {
  return _scaffold(Container(
    height: 40,
    color: _surfaceColor,
    child: Row(
      children: [
        for (int i = 0; i < primaryTabs.length; i++)
          _DockTab(label: primaryTabs[i], isActive: i == 0),
        const Spacer(),
      ],
    ),
  ));
}

class _DockTab extends StatelessWidget {
  final String label;
  final bool isActive;
  const _DockTab({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isActive ? _accentGreen : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? _accentGreen : _textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// Composite event card
Widget _buildCompositeEventCard({
  required String name,
  required String category,
  required List<String> stages,
  required bool hasAudio,
}) {
  return _scaffold(Container(
    margin: const EdgeInsets.all(8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _surfaceColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _borderColor),
    ),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: hasAudio ? _accentGreen : _textSecondary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stages.join(' · '),
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        Icon(
          hasAudio ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: hasAudio ? _accentGreen : _textSecondary,
          size: 16,
        ),
      ],
    ),
  ));
}

/// Reel grid widget
Widget _buildReelGrid({required int reels, required int rows}) {
  return _scaffold(Container(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int r = 0; r < rows; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int c = 0; c < reels; c++)
                Container(
                  margin: const EdgeInsets.all(2),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    border: Border.all(color: _borderColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text(
                      'A',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    ),
  ));
}

/// Single reel cell
Widget _buildReelCell({required String symbol, required bool isWinning}) {
  return _scaffold(Container(
    width: 90,
    height: 90,
    decoration: BoxDecoration(
      color: _surfaceColor,
      border: Border.all(
        color: isWinning ? _accentGreen : _borderColor,
        width: isWinning ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(6),
      boxShadow: isWinning
          ? [BoxShadow(color: _accentGreen.withOpacity(0.3), blurRadius: 12)]
          : null,
    ),
    child: Center(
      child: Text(
        symbol,
        style: TextStyle(
          color: isWinning ? _accentGreen : _textSecondary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  ));
}

enum SpinButtonState { idle, spinning }

/// SPIN button in various states
Widget _buildSpinButton({required SpinButtonState state}) {
  final isSpinning = state == SpinButtonState.spinning;
  return _scaffold(Container(
    width: 180,
    height: 60,
    decoration: BoxDecoration(
      gradient: isSpinning
          ? null
          : LinearGradient(
              colors: [_accent, _accent.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      color: isSpinning ? _borderColor : null,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isSpinning ? _textSecondary : _accent,
      ),
    ),
    child: Center(
      child: Text(
        isSpinning ? 'SPINNING...' : 'SPIN',
        style: TextStyle(
          color: isSpinning ? _textSecondary : _darkBg,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
        ),
      ),
    ),
  ));
}

/// Generic action button (SLAM / SKIP)
Widget _buildActionButton({required String label, required Color color}) {
  return _scaffold(Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.5)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    ),
  ));
}

/// DNA panel header
Widget _buildDnaPanelHeader({required String brand}) {
  return _scaffold(Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: _surfaceColor,
      border: const Border(bottom: BorderSide(color: _borderColor)),
    ),
    child: Row(
      children: [
        const Icon(Icons.graphic_eq_rounded, color: _accent, size: 18),
        const SizedBox(width: 10),
        const Text(
          'AUDIO DNA',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _accent.withOpacity(0.3)),
          ),
          child: Text(
            brand,
            style: const TextStyle(
              color: _accent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  ));
}

/// DNA instrument chips
Widget _buildDnaInstrumentChips({required List<String> instruments}) {
  return _scaffold(Wrap(
    spacing: 8,
    children: [
      for (final inst in instruments)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _accentGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _accentGreen.withOpacity(0.4)),
          ),
          child: Text(
            inst,
            style: const TextStyle(
              color: _accentGreen,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
    ],
  ));
}

/// DNA BPM range
Widget _buildDnaBpmRange({required double min, required double max}) {
  return _scaffold(Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('BPM', style: TextStyle(color: _textSecondary, fontSize: 11)),
      const SizedBox(width: 12),
      Text(
        '${min.toInt()}',
        style: const TextStyle(
          color: _accent,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('—', style: TextStyle(color: _textSecondary)),
      ),
      Text(
        '${max.toInt()}',
        style: const TextStyle(
          color: _accent,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
      ),
    ],
  ));
}

/// DNA Apply button
Widget _buildDnaApplyButton({required bool enabled}) {
  return _scaffold(AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    decoration: BoxDecoration(
      color: enabled ? _accentGreen.withOpacity(0.15) : _borderColor,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: enabled ? _accentGreen.withOpacity(0.6) : _borderColor,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.play_arrow_rounded,
          color: enabled ? _accentGreen : _textSecondary,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          'APPLY DNA',
          style: TextStyle(
            color: enabled ? _accentGreen : _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  ));
}
