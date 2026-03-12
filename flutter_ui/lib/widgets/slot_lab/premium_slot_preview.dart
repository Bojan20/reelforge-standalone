/// Premium Fullscreen Slot Preview
///
/// Modern slot machine UI with ALL industry-standard elements:
/// - A. Header Zone (menu, logo, balance, VIP, settings)
/// - B. Jackpot Zone (4-tier progressive tickers)
/// - C. Main Game Zone (reels, paylines, overlays)
/// - D. Win Presenter (rollup, particles, collect/gamble)
/// - E. Feature Indicators (free spins, bonus, multiplier)
/// - F. Control Bar (bet controls, spin, auto, turbo)
/// - G. Info Panels (paytable, symbols, rules, history)
/// - H. Audio/Visual (volume, music, sfx toggles)
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/win_tier_config.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/feature_composer_provider.dart';
import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../services/audio_playback_service.dart';
import '../../services/event_registry.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
import 'forced_outcome_panel.dart';
import 'game_flow_overlay.dart';
import '../../providers/slot_lab/game_flow_provider.dart';
import 'project_dashboard_dialog.dart';
import 'slot_preview_widget.dart';

// =============================================================================
// CONSTANTS & THEME
// =============================================================================

/// Slot-specific theme extension
///
/// Extends FluxForgeTheme with slot-specific colors for casino UI elements.
/// Uses FluxForgeTheme base colors for consistency with the main app,
/// adds slot-specific colors (gold, jackpots, win tiers) for casino feel.
class _SlotTheme {
  // ═══════════════════════════════════════════════════════════════════════════
  // BACKGROUNDS - Aligned with FluxForgeTheme (slightly darker for casino feel)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Deepest background (app base)
  static const bgDeep = Color(0xFF0a0a12);

  /// Dark background (zones, panels)
  static const bgDark = Color(0xFF121218);

  /// Mid-level background (cards, items)
  static const bgMid = Color(0xFF1a1a24);

  /// Surface level (interactive elements)
  static const bgSurface = Color(0xFF242432);

  /// Panel background (overlays, dialogs)
  static const bgPanel = Color(0xFF1e1e2a);

  // ═══════════════════════════════════════════════════════════════════════════
  // CASINO METALS - Gold, Silver, Bronze (slot-specific)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Casino gold (primary high-value color)
  static const gold = Color(0xFFFFD700);

  /// Light gold (highlights, shines)
  static const goldLight = Color(0xFFFFE55C);

  /// Silver (secondary value color)
  static const silver = Color(0xFFC0C0C0);

  /// Bronze (tertiary value color)
  static const bronze = Color(0xFFCD7F32);

  // ═══════════════════════════════════════════════════════════════════════════
  // JACKPOT TIERS - 4-tier progressive system
  // ═══════════════════════════════════════════════════════════════════════════

  /// Grand Jackpot (highest tier) - Gold
  static const jackpotGrand = Color(0xFFFFD700);

  /// Major Jackpot (second tier) - Magenta/Pink
  static const jackpotMajor = Color(0xFFFF4080);

  /// Minor Jackpot (third tier) - Purple
  static const jackpotMinor = Color(0xFF8B5CF6);

  /// Mini Jackpot (fourth tier) - Green
  static const jackpotMini = Color(0xFF4CAF50);

  /// Mystery Jackpot (special) - Cyan
  static const jackpotMystery = Color(0xFF40C8FF);

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN TIERS - 5-tier win celebration colors
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ultra Win (1000x+) - Hot magenta
  static const winUltra = Color(0xFFFF4080);

  /// Epic Win (100x-999x) - Electric purple
  static const winEpic = Color(0xFFE040FB);

  /// Mega Win (25x-99x) - Gold
  static const winMega = Color(0xFFFFD700);

  /// Big Win (10x-24x) - Green
  /// Matches FluxForgeTheme.accentGreen (#40FF90)
  static const winBig = Color(0xFF40FF90);

  /// Small Win (1x-9x) - Cyan
  /// Matches FluxForgeTheme.accentCyan (#40C8FF)
  static const winSmall = Color(0xFF40C8FF);

  // ═══════════════════════════════════════════════════════════════════════════
  // UI ELEMENTS - Borders and text (aligned with FluxForgeTheme)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Default border color
  static const border = Color(0xFF3a3a48);

  /// Light border (hover states)
  static const borderLight = Color(0xFF4a4a58);

  /// Primary text (maximum readability)
  /// Matches FluxForgeTheme.textPrimary (#FFFFFF)
  static const textPrimary = Color(0xFFFFFFFF);

  /// Secondary text (labels, descriptions)
  /// Matches FluxForgeTheme.textSecondary (#B0B0B8)
  static const textSecondary = Color(0xFFB0B0B8);

  /// Muted text (hints, disabled)
  /// Matches FluxForgeTheme.textTertiary (#707080)
  static const textMuted = Color(0xFF707080);

  // ═══════════════════════════════════════════════════════════════════════════
  // BUTTON GRADIENTS - Slot-specific button styles
  // ═══════════════════════════════════════════════════════════════════════════

  /// Spin button gradient (blue)
  static const spinGradient = [Color(0xFF4A9EFF), Color(0xFF2060CC)];

  /// Max Bet button gradient (gold→orange)
  static const maxBetGradient = [Color(0xFFFFD700), Color(0xFFFF9040)];

  /// Auto-spin button gradient (green)
  static const autoSpinGradient = [Color(0xFF40FF90), Color(0xFF20A060)];
}

// =============================================================================
// P6: DEVICE SIMULATION MODE
// =============================================================================

/// Device simulation presets for responsive testing
enum DeviceSimulation {
  desktop,         // Full size (no constraints)
  tablet,          // 1024x768 (iPad)
  mobileLandscape, // 844x390 (iPhone 14 Pro landscape)
  mobilePortrait,  // 390x844 (iPhone 14 Pro portrait)
}

extension DeviceSimulationExtension on DeviceSimulation {
  String get label {
    return switch (this) {
      DeviceSimulation.desktop => 'Desktop',
      DeviceSimulation.tablet => 'Tablet',
      DeviceSimulation.mobileLandscape => 'Mobile (L)',
      DeviceSimulation.mobilePortrait => 'Mobile (P)',
    };
  }

  IconData get icon {
    return switch (this) {
      DeviceSimulation.desktop => Icons.desktop_mac,
      DeviceSimulation.tablet => Icons.tablet_mac,
      DeviceSimulation.mobileLandscape => Icons.phone_android,
      DeviceSimulation.mobilePortrait => Icons.smartphone,
    };
  }

  Size? get size {
    return switch (this) {
      DeviceSimulation.desktop => null, // No constraint
      DeviceSimulation.tablet => const Size(1024, 768),
      DeviceSimulation.mobileLandscape => const Size(844, 390),
      DeviceSimulation.mobilePortrait => const Size(390, 844),
    };
  }
}

// =============================================================================
// P6: SLOT THEME PRESETS
// =============================================================================

/// Visual theme presets for A/B testing
enum SlotThemePreset {
  casino,   // Current dark casino theme (default)
  neon,     // Cyberpunk neon
  royal,    // Gold & purple luxury
  nature,   // Green & wood organic
  retro,    // 80s arcade
  minimal,  // Clean white
}

extension SlotThemePresetExtension on SlotThemePreset {
  String get label {
    return switch (this) {
      SlotThemePreset.casino => 'Casino',
      SlotThemePreset.neon => 'Neon',
      SlotThemePreset.royal => 'Royal',
      SlotThemePreset.nature => 'Nature',
      SlotThemePreset.retro => 'Retro',
      SlotThemePreset.minimal => 'Minimal',
    };
  }

  SlotThemeData get data {
    return switch (this) {
      SlotThemePreset.casino => SlotThemeData.casino,
      SlotThemePreset.neon => SlotThemeData.neon,
      SlotThemePreset.royal => SlotThemeData.royal,
      SlotThemePreset.nature => SlotThemeData.nature,
      SlotThemePreset.retro => SlotThemeData.retro,
      SlotThemePreset.minimal => SlotThemeData.minimal,
    };
  }
}

// =============================================================================
// SPIN BUTTON PHASE SYSTEM — Industry Standard STOP/SKIP
// =============================================================================

/// Spin button phase states for industry-standard button behavior.
///
/// **Industry Standard (NetEnt, Pragmatic Play, IGT, Aristocrat):**
/// - SPIN (blue) → Player can start a spin
/// - STOP (red) → Player can stop spinning reels immediately
/// - SKIP (gold) → Player can skip win presentation (with protection)
///
/// Big Win protection:
/// - Regular wins: No protection (immediate skip)
/// - All Big Win tiers: 2.5 seconds protection, then SKIP → BIG_WIN_END
enum SpinButtonPhase {
  /// Ready to spin - Blue button with "SPIN" label
  spin,

  /// Reels are spinning - Red button with "STOP" label
  stop,

  /// Win presentation active - Gold button with "SKIP" label
  /// May show countdown timer if Big Win protection is active
  skip,

  /// Skip is available but still within protection countdown
  /// Shows "SKIP" with remaining seconds countdown
  skipProtected,
}

/// Big Win protection configuration.
///
/// **Simple rules:**
/// - Regular wins (< threshold): No protection, can skip immediately
/// - All Big Win tiers: 2.5 seconds protection before SKIP available
/// - Each tier presentation: 4 seconds
/// - BIG_WIN_END: 4 seconds
class BigWinProtection {
  /// No protection for regular wins
  static const double regularWin = 0.0;

  /// All Big Win tiers have same protection: 2.5 seconds
  static const double bigWinProtection = 2.5;

  /// Each tier lasts 4 seconds
  static const double tierDuration = 4.0;

  /// BIG_WIN_END lasts 4 seconds
  static const double endDuration = 4.0;

  /// Get protection duration for a win tier
  static double forTier(String tier) {
    final t = tier.toUpperCase();
    // All Big Win tiers get 2.5 seconds protection
    // Industry standard tiers: BIG, SUPER, MEGA, EPIC, ULTRA
    const bigWinTiers = {'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_TIER_4', 'BIG_WIN_TIER_5'};
    if (bigWinTiers.contains(t) || t.startsWith('BIG_WIN')) {
      return bigWinProtection;
    }
    // Regular wins - no protection
    return regularWin;
  }
}

/// Button gradient colors for each phase
class SpinButtonColors {
  /// SPIN button gradient (blue)
  static const spinGradient = [Color(0xFF4A9EFF), Color(0xFF2060CC)];

  /// STOP button gradient (red)
  static const stopGradient = [Color(0xFFFF4040), Color(0xFFCC2040)];

  /// SKIP button gradient (gold) - Industry standard for skip/collect
  static const skipGradient = [Color(0xFFFFD700), Color(0xFFE6B800)];

  /// SKIP protected gradient (gold with darker tint for countdown)
  static const skipProtectedGradient = [Color(0xFFD4AF37), Color(0xFFB8860B)];

  /// Disabled button colors
  static const disabledGradient = [Color(0xFF242432), Color(0xFF1e1e2a)];
}

/// Complete theme data for slot UI
class SlotThemeData {
  final Color bgDeep;
  final Color bgDark;
  final Color bgMid;
  final Color bgSurface;
  final Color bgPanel;
  final Color gold;
  final Color goldLight;
  final Color accent;
  final Color winSmall;
  final Color winBig;
  final Color winMega;
  final Color winEpic;
  final Color winUltra;
  final List<Color> jackpotColors;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  const SlotThemeData({
    required this.bgDeep,
    required this.bgDark,
    required this.bgMid,
    required this.bgSurface,
    this.bgPanel = const Color(0xFF1e1e2a),
    required this.gold,
    this.goldLight = const Color(0xFFFFE55C),
    required this.accent,
    required this.winSmall,
    required this.winBig,
    required this.winMega,
    required this.winEpic,
    required this.winUltra,
    required this.jackpotColors,
    required this.border,
    this.borderLight = const Color(0xFF4a4a58),
    required this.textPrimary,
    required this.textSecondary,
    this.textMuted = const Color(0xFF707080),
  });

  // Helper getters for jackpot colors (backward compatible)
  Color get jackpotGrand => jackpotColors.isNotEmpty ? jackpotColors[0] : const Color(0xFFFFD700);
  Color get jackpotMajor => jackpotColors.length > 1 ? jackpotColors[1] : const Color(0xFFFF4080);
  Color get jackpotMinor => jackpotColors.length > 2 ? jackpotColors[2] : const Color(0xFF8B5CF6);
  Color get jackpotMini => jackpotColors.length > 3 ? jackpotColors[3] : const Color(0xFF4CAF50);
  Color get jackpotMystery => const Color(0xFF40C8FF);

  // Gradient getters for control buttons
  List<Color> get maxBetGradient => [gold, const Color(0xFFFF9040)];
  List<Color> get autoSpinGradient => [accent, accent.withOpacity(0.7)];

  // Casino (default) - Current dark casino theme
  static const casino = SlotThemeData(
    bgDeep: Color(0xFF0a0a12),
    bgDark: Color(0xFF121218),
    bgMid: Color(0xFF1a1a24),
    bgSurface: Color(0xFF242432),
    gold: Color(0xFFFFD700),
    accent: Color(0xFF4A9EFF),
    winSmall: Color(0xFF40C8FF),
    winBig: Color(0xFF40FF90),
    winMega: Color(0xFFFFD700),
    winEpic: Color(0xFFE040FB),
    winUltra: Color(0xFFFF4080),
    jackpotColors: [Color(0xFFFFD700), Color(0xFFFF4080), Color(0xFF8B5CF6), Color(0xFF4CAF50)],
    border: Color(0xFF3a3a48),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB0B0B8),
  );

  // Neon - Cyberpunk neon
  static const neon = SlotThemeData(
    bgDeep: Color(0xFF0a0010),
    bgDark: Color(0xFF140020),
    bgMid: Color(0xFF1e0030),
    bgSurface: Color(0xFF280040),
    gold: Color(0xFF00FFFF),
    accent: Color(0xFFFF00FF),
    winSmall: Color(0xFF00FF00),
    winBig: Color(0xFF00FFFF),
    winMega: Color(0xFFFF00FF),
    winEpic: Color(0xFFFFFF00),
    winUltra: Color(0xFFFF0080),
    jackpotColors: [Color(0xFFFF00FF), Color(0xFF00FFFF), Color(0xFF00FF00), Color(0xFFFFFF00)],
    border: Color(0xFF800080),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFFF80FF),
  );

  // Royal - Gold & purple luxury
  static const royal = SlotThemeData(
    bgDeep: Color(0xFF0a0512),
    bgDark: Color(0xFF150a20),
    bgMid: Color(0xFF201530),
    bgSurface: Color(0xFF2a1f40),
    gold: Color(0xFFFFD700),
    accent: Color(0xFF9B59B6),
    winSmall: Color(0xFFC0C0C0),
    winBig: Color(0xFFFFD700),
    winMega: Color(0xFFE040FB),
    winEpic: Color(0xFF9B59B6),
    winUltra: Color(0xFFFF6B9D),
    jackpotColors: [Color(0xFFFFD700), Color(0xFF9B59B6), Color(0xFFE040FB), Color(0xFFC0C0C0)],
    border: Color(0xFF5a3a68),
    textPrimary: Color(0xFFFFFDF0),
    textSecondary: Color(0xFFD4AF37),
  );

  // Nature - Green & wood organic
  static const nature = SlotThemeData(
    bgDeep: Color(0xFF0a120a),
    bgDark: Color(0xFF141E14),
    bgMid: Color(0xFF1E2A1E),
    bgSurface: Color(0xFF283828),
    gold: Color(0xFFFFE082),
    accent: Color(0xFF4CAF50),
    winSmall: Color(0xFF81C784),
    winBig: Color(0xFF66BB6A),
    winMega: Color(0xFFFFE082),
    winEpic: Color(0xFFFFD54F),
    winUltra: Color(0xFFFF8A65),
    jackpotColors: [Color(0xFFFFE082), Color(0xFF4CAF50), Color(0xFF8BC34A), Color(0xFF795548)],
    border: Color(0xFF3E5A3E),
    textPrimary: Color(0xFFF5F5DC),
    textSecondary: Color(0xFFA5D6A7),
  );

  // Retro - 80s arcade
  static const retro = SlotThemeData(
    bgDeep: Color(0xFF000020),
    bgDark: Color(0xFF101030),
    bgMid: Color(0xFF202050),
    bgSurface: Color(0xFF303070),
    gold: Color(0xFFFFFF00),
    accent: Color(0xFFFF6B00),
    winSmall: Color(0xFF00FF00),
    winBig: Color(0xFFFFFF00),
    winMega: Color(0xFFFF6B00),
    winEpic: Color(0xFFFF0000),
    winUltra: Color(0xFFFF00FF),
    jackpotColors: [Color(0xFFFFFF00), Color(0xFFFF6B00), Color(0xFFFF0000), Color(0xFF00FF00)],
    border: Color(0xFF4040A0),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF00FFFF),
  );

  // Minimal - Clean white
  static const minimal = SlotThemeData(
    bgDeep: Color(0xFFF5F5F5),
    bgDark: Color(0xFFEEEEEE),
    bgMid: Color(0xFFE0E0E0),
    bgSurface: Color(0xFFFFFFFF),
    gold: Color(0xFF1976D2),
    accent: Color(0xFF1976D2),
    winSmall: Color(0xFF4CAF50),
    winBig: Color(0xFF2196F3),
    winMega: Color(0xFF9C27B0),
    winEpic: Color(0xFFE91E63),
    winUltra: Color(0xFFFF5722),
    jackpotColors: [Color(0xFF1976D2), Color(0xFF9C27B0), Color(0xFFE91E63), Color(0xFF4CAF50)],
    border: Color(0xFFBDBDBD),
    textPrimary: Color(0xFF212121),
    textSecondary: Color(0xFF757575),
  );
}

// =============================================================================
// SLOT THEME PROVIDER - InheritedWidget for dynamic theme access
// =============================================================================

/// InheritedWidget that provides theme data to all slot UI widgets.
///
/// Usage in child widgets:
/// ```dart
/// final theme = SlotThemeProvider.of(context);
/// Container(color: theme.bgDark);
/// ```
class SlotThemeProvider extends InheritedWidget {
  final SlotThemeData theme;

  const SlotThemeProvider({
    super.key,
    required this.theme,
    required super.child,
  });

  /// Get theme from context. Returns casino theme as fallback.
  static SlotThemeData of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<SlotThemeProvider>();
    return provider?.theme ?? SlotThemeData.casino;
  }

  /// Get theme without rebuilding on change
  static SlotThemeData read(BuildContext context) {
    final provider = context.getInheritedWidgetOfExactType<SlotThemeProvider>();
    return provider?.theme ?? SlotThemeData.casino;
  }

  @override
  bool updateShouldNotify(SlotThemeProvider oldWidget) {
    return theme != oldWidget.theme;
  }
}

/// Extension for easy theme access from BuildContext
extension SlotThemeContext on BuildContext {
  /// Get current slot theme (shorthand for SlotThemeProvider.of(this))
  SlotThemeData get slotTheme => SlotThemeProvider.of(this);
}

// =============================================================================
// A. HEADER ZONE
// =============================================================================

class _HeaderZone extends StatelessWidget {
  final double balance;
  final bool isMusicOn;
  final bool isSfxOn;
  final VoidCallback onMenuTap;
  final VoidCallback onMusicToggle;
  final VoidCallback onSfxToggle;
  final VoidCallback onSettingsTap;

  // P6: Device simulation
  final DeviceSimulation deviceSimulation;
  final ValueChanged<DeviceSimulation> onDeviceChanged;

  // P6: Theme
  final SlotThemePreset currentTheme;
  final ValueChanged<SlotThemePreset> onThemeChanged;

  // P6: Debug
  final bool showDebugToolbar;
  final VoidCallback onDebugToggle;

  // Reload slot machine (browser-style refresh)
  final VoidCallback? onReload;

  const _HeaderZone({
    required this.balance,
    required this.isMusicOn,
    required this.isSfxOn,
    required this.onMenuTap,
    required this.onMusicToggle,
    required this.onSfxToggle,
    required this.onSettingsTap,
    this.deviceSimulation = DeviceSimulation.desktop,
    required this.onDeviceChanged,
    this.currentTheme = SlotThemePreset.casino,
    required this.onThemeChanged,
    this.showDebugToolbar = false,
    required this.onDebugToggle,
    this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SlotThemeProvider.of(context);
    return Container(
      height: 48, // Reduced from 56
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.bgDark,
            theme.bgDark.withOpacity(0.95),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: theme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Balance display (animated)
          _BalanceDisplay(balance: balance),

          const Spacer(),

          // P6: Device simulation dropdown
          _DeviceSimulationDropdown(
            value: deviceSimulation,
            onChanged: onDeviceChanged,
          ),
          const SizedBox(width: 12),

          // P6: Theme dropdown
          _ThemeDropdown(
            value: currentTheme,
            onChanged: onThemeChanged,
          ),
          const SizedBox(width: 12),

          // Audio controls
          _HeaderIconButton(
            icon: isMusicOn ? Icons.music_note : Icons.music_off,
            tooltip: 'Music ${isMusicOn ? 'On' : 'Off'}',
            isActive: isMusicOn,
            onTap: onMusicToggle,
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(
            icon: isSfxOn ? Icons.volume_up : Icons.volume_off,
            tooltip: 'SFX ${isSfxOn ? 'On' : 'Off'}',
            isActive: isSfxOn,
            onTap: onSfxToggle,
          ),
          const SizedBox(width: 8),

          // Debug / Forced Outcomes
          _HeaderIconButton(
            icon: showDebugToolbar ? Icons.bug_report : Icons.bug_report_outlined,
            tooltip: 'Debug Panel (D)',
            isActive: showDebugToolbar,
            onTap: onDebugToggle,
          ),
          const SizedBox(width: 16),

          // Settings
          _HeaderIconButton(
            icon: Icons.settings,
            tooltip: 'Settings',
            onTap: onSettingsTap,
          ),
          if (onReload != null) ...[
            const SizedBox(width: 8),
            _HeaderIconButton(
              icon: Icons.refresh,
              tooltip: 'Reload',
              onTap: onReload!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogo(SlotThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.accent, theme.gold],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: theme.accent.withOpacity(0.4),
                blurRadius: 8,
              ),
            ],
          ),
          child: const Icon(Icons.casino, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          'FLUXFORGE',
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;
  final bool isDestructive;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.isDestructive = false,
  });

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final color = widget.isDestructive
        ? FluxForgeTheme.accentRed
        : widget.isActive
            ? FluxForgeTheme.accentBlue
            : theme.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isHovered
                  ? color.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isHovered ? color.withOpacity(0.3) : Colors.transparent,
              ),
            ),
            child: Icon(
              widget.icon,
              color: _isHovered ? color : color.withOpacity(0.7),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P6: DEVICE SIMULATION DROPDOWN
// ═══════════════════════════════════════════════════════════════════════════════

class _DeviceSimulationDropdown extends StatelessWidget {
  final DeviceSimulation value;
  final ValueChanged<DeviceSimulation> onChanged;

  const _DeviceSimulationDropdown({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.bgMid.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.border.withOpacity(0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeviceSimulation>(
          value: value,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, color: theme.textSecondary, size: 18),
          dropdownColor: theme.bgDark,
          style: TextStyle(color: theme.textPrimary, fontSize: 12),
          items: DeviceSimulation.values.map((device) {
            return DropdownMenuItem(
              value: device,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(device.icon, size: 16, color: theme.textSecondary),
                  const SizedBox(width: 6),
                  Text(device.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (newValue) {
            if (newValue != null) onChanged(newValue);
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P6: THEME DROPDOWN
// ═══════════════════════════════════════════════════════════════════════════════

class _ThemeDropdown extends StatelessWidget {
  final SlotThemePreset value;
  final ValueChanged<SlotThemePreset> onChanged;

  const _ThemeDropdown({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.bgMid.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.border.withOpacity(0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SlotThemePreset>(
          value: value,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, color: theme.textSecondary, size: 18),
          dropdownColor: theme.bgDark,
          style: TextStyle(color: theme.textPrimary, fontSize: 12),
          items: SlotThemePreset.values.map((preset) {
            return DropdownMenuItem(
              value: preset,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.palette, size: 16, color: preset.data.accent),
                  const SizedBox(width: 6),
                  Text(preset.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (newValue) {
            if (newValue != null) onChanged(newValue);
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// P6: RECORDING BUTTON
// ═══════════════════════════════════════════════════════════════════════════════


// ═══════════════════════════════════════════════════════════════════════════════
// P6: DEBUG TOOLBAR
// ═══════════════════════════════════════════════════════════════════════════════

class _DebugToolbar extends StatelessWidget {
  final int fps;
  final int activeVoices;
  final int memoryMb;
  final bool showStageTrace;
  final VoidCallback onStageTraceToggle;
  final ValueChanged<int> onForceOutcome;

  const _DebugToolbar({
    required this.fps,
    required this.activeVoices,
    required this.memoryMb,
    required this.showStageTrace,
    required this.onStageTraceToggle,
    required this.onForceOutcome,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.bgDark.withOpacity(0.95),
        border: Border(
          bottom: BorderSide(color: theme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Debug label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentOrange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bug_report, size: 14, color: FluxForgeTheme.accentOrange),
                SizedBox(width: 4),
                Text(
                  'DEBUG',
                  style: TextStyle(
                    color: FluxForgeTheme.accentOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Forced outcome buttons (P5 Win Tier System)
          // Uses ForcedOutcomeConfig keyboard shortcuts: 1=Lose, 2=LOW, 3=EQ, 4-9=W1-W6, 0=BIG
          ...ForcedOutcomeConfig.outcomes
              .where((c) => c.keyboardShortcut != null)
              .map((c) => _DebugOutcomeButton(
                    label: c.shortLabel,
                    index: int.tryParse(c.keyboardShortcut!) ?? 0,
                    onTap: onForceOutcome,
                    color: c.gradientColors[0],
                  ))
              ,

          const Spacer(),

          // Stats
          _DebugStat(label: 'FPS', value: '$fps', color: fps >= 55 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed),
          const SizedBox(width: 16),
          _DebugStat(label: 'Voices', value: '$activeVoices/48', color: theme.textSecondary),
          const SizedBox(width: 16),
          _DebugStat(label: 'Mem', value: '${memoryMb}MB', color: theme.textSecondary),
          const SizedBox(width: 16),

          // Stage trace toggle
          GestureDetector(
            onTap: onStageTraceToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: showStageTrace
                    ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: showStageTrace
                      ? FluxForgeTheme.accentBlue.withOpacity(0.5)
                      : theme.border.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timeline,
                    size: 14,
                    color: showStageTrace
                        ? FluxForgeTheme.accentBlue
                        : theme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Stages',
                    style: TextStyle(
                      color: showStageTrace
                          ? FluxForgeTheme.accentBlue
                          : theme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugOutcomeButton extends StatelessWidget {
  final String label;
  final int index;
  final ValueChanged<int> onTap;
  final Color? color;

  const _DebugOutcomeButton({
    required this.label,
    required this.index,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final btnColor = color ?? theme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: btnColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: btnColor.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$index',
                style: TextStyle(
                  color: btnColor.withOpacity(0.6),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: btnColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DebugStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: theme.textSecondary,
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BalanceDisplay extends StatefulWidget {
  final double balance;

  const _BalanceDisplay({required this.balance});

  @override
  State<_BalanceDisplay> createState() => _BalanceDisplayState();
}

class _BalanceDisplayState extends State<_BalanceDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  double _displayedBalance = 0;
  double _previousBalance = 0;

  @override
  void initState() {
    super.initState();
    _displayedBalance = widget.balance;
    _previousBalance = widget.balance;
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void didUpdateWidget(_BalanceDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.balance != widget.balance) {
      _previousBalance = _displayedBalance;
      _animateBalanceChange();
    }
  }

  void _animateBalanceChange() {
    final diff = widget.balance - _previousBalance;
    if (diff != 0) {
      _glowController.forward(from: 0);
    }

    // Animate the number
    const duration = Duration(milliseconds: 500);
    const steps = 20;
    final stepDuration = duration.inMilliseconds ~/ steps;
    final stepAmount = (widget.balance - _previousBalance) / steps;

    for (int i = 1; i <= steps; i++) {
      Future.delayed(Duration(milliseconds: stepDuration * i), () {
        if (mounted) {
          setState(() {
            _displayedBalance = _previousBalance + (stepAmount * i);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final isWin = widget.balance > _previousBalance;
    final glowColor =
        isWin ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed;

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowOpacity = (1 - _glowController.value) * 0.5;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.bgPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _glowController.isAnimating
                  ? glowColor.withOpacity(glowOpacity)
                  : theme.border,
              width: _glowController.isAnimating ? 2 : 1,
            ),
            boxShadow: _glowController.isAnimating
                ? [
                    BoxShadow(
                      color: glowColor.withOpacity(glowOpacity * 0.5),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: theme.gold,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '\$${_displayedBalance.toStringAsFixed(2)}',
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


// =============================================================================
// B. JACKPOT ZONE
// =============================================================================

class _JackpotZone extends StatelessWidget {
  final double miniJackpot;
  final double minorJackpot;
  final double majorJackpot;
  final double grandJackpot;
  final double? mysteryJackpot;
  final double progressiveContribution;

  const _JackpotZone({
    required this.miniJackpot,
    required this.minorJackpot,
    required this.majorJackpot,
    required this.grandJackpot,
    this.mysteryJackpot,
    required this.progressiveContribution,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), // Reduced padding
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.bgDark.withOpacity(0.95),
            theme.bgMid.withOpacity(0.85),
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF2a2a38), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _JackpotTicker(
            label: 'MINI',
            amount: miniJackpot,
            color: theme.jackpotMini,
            size: _JackpotSize.small,
          ),
          const SizedBox(width: 12),
          _JackpotTicker(
            label: 'MINOR',
            amount: minorJackpot,
            color: theme.jackpotMinor,
            size: _JackpotSize.medium,
          ),
          const SizedBox(width: 16),
          _JackpotTicker(
            label: 'MAJOR',
            amount: majorJackpot,
            color: theme.jackpotMajor,
            size: _JackpotSize.large,
          ),
          const SizedBox(width: 16),
          _JackpotTicker(
            label: 'GRAND',
            amount: grandJackpot,
            color: theme.jackpotGrand,
            size: _JackpotSize.grand,
          ),
          if (mysteryJackpot != null) ...[
            const SizedBox(width: 12),
            _JackpotTicker(
              label: 'MYSTERY',
              amount: mysteryJackpot!,
              color: theme.jackpotMystery,
              size: _JackpotSize.medium,
              isMystery: true,
            ),
          ],
          const SizedBox(width: 24),
          // Inline progressive meter
          _ProgressiveMeter(contribution: progressiveContribution),
        ],
      ),
    );
  }
}

enum _JackpotSize { small, medium, large, grand }

class _JackpotTicker extends StatefulWidget {
  final String label;
  final double amount;
  final Color color;
  final _JackpotSize size;
  final bool isMystery;

  const _JackpotTicker({
    required this.label,
    required this.amount,
    required this.color,
    required this.size,
    this.isMystery = false,
  });

  @override
  State<_JackpotTicker> createState() => _JackpotTickerState();
}

class _JackpotTickerState extends State<_JackpotTicker>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  double _displayedAmount = 0;

  @override
  void initState() {
    super.initState();
    _displayedAmount = widget.amount;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_JackpotTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amount != widget.amount) {
      _animateAmount();
    }
  }

  void _animateAmount() {
    final start = _displayedAmount;
    final end = widget.amount;
    const steps = 30;
    final stepAmount = (end - start) / steps;

    for (int i = 1; i <= steps; i++) {
      Future.delayed(Duration(milliseconds: 20 * i), () {
        if (mounted) {
          setState(() => _displayedAmount = start + (stepAmount * i));
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final dimensions = _getDimensions();

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = (0.8 + (_pulseController.value.clamp(0.0, 1.0) * 0.2)).clamp(0.0, 1.0);

        return Container(
          width: dimensions.width,
          padding: EdgeInsets.symmetric(
            horizontal: dimensions.horizontalPadding,
            vertical: dimensions.verticalPadding,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.color.withOpacity(0.2),
                widget.color.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(dimensions.borderRadius),
            border: Border.all(
              color: widget.color.withOpacity((pulse * 0.6).clamp(0.0, 1.0)),
              width: widget.size == _JackpotSize.grand ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity((pulse * 0.3).clamp(0.0, 1.0)),
                blurRadius: dimensions.glowRadius,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Label
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: dimensions.labelSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: dimensions.spacing),
              // Amount
              widget.isMystery
                  ? Text(
                      '???',
                      style: TextStyle(
                        color: widget.color,
                        fontSize: dimensions.amountSize,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Text(
                      '\$${_formatAmount(_displayedAmount)}',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: dimensions.amountSize,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        shadows: [
                          Shadow(
                            color: widget.color.withOpacity(0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  _JackpotDimensions _getDimensions() {
    return switch (widget.size) {
      _JackpotSize.small => const _JackpotDimensions(
          width: 85,
          horizontalPadding: 8,
          verticalPadding: 6,
          borderRadius: 6,
          glowRadius: 6,
          labelSize: 8,
          amountSize: 12,
          spacing: 2,
        ),
      _JackpotSize.medium => const _JackpotDimensions(
          width: 100,
          horizontalPadding: 10,
          verticalPadding: 8,
          borderRadius: 8,
          glowRadius: 10,
          labelSize: 9,
          amountSize: 14,
          spacing: 3,
        ),
      _JackpotSize.large => const _JackpotDimensions(
          width: 115,
          horizontalPadding: 12,
          verticalPadding: 8,
          borderRadius: 10,
          glowRadius: 14,
          labelSize: 10,
          amountSize: 16,
          spacing: 3,
        ),
      _JackpotSize.grand => const _JackpotDimensions(
          width: 140,
          horizontalPadding: 14,
          verticalPadding: 10,
          borderRadius: 12,
          glowRadius: 20,
          labelSize: 11,
          amountSize: 20,
          spacing: 4,
        ),
    };
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(2)}K';
    }
    return amount.toStringAsFixed(2);
  }
}

class _JackpotDimensions {
  final double width;
  final double horizontalPadding;
  final double verticalPadding;
  final double borderRadius;
  final double glowRadius;
  final double labelSize;
  final double amountSize;
  final double spacing;

  const _JackpotDimensions({
    required this.width,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.borderRadius,
    required this.glowRadius,
    required this.labelSize,
    required this.amountSize,
    required this.spacing,
  });
}

class _ProgressiveMeter extends StatelessWidget {
  final double contribution;

  const _ProgressiveMeter({required this.contribution});

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return SizedBox(
      width: 180,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CONTRIBUTION',
                style: TextStyle(
                  color: theme.textMuted,
                  fontSize: 8,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '\$${(contribution * 100).toStringAsFixed(2)}',
                style: TextStyle(
                  color: theme.gold,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: theme.bgSurface,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: contribution.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.jackpotMini, theme.gold],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// C. MAIN GAME ZONE (Reel Frame + Overlays)
// =============================================================================

class _MainGameZone extends StatelessWidget {
  final SlotLabProvider provider;
  final SlotLabProjectProvider? projectProvider;
  final int reels;
  final int rows;
  final String? winTier;
  final List<int>? winningPayline;
  final bool isAnticipation;
  final bool showWildExpansion;
  final bool showScatterWin;
  final bool showCascade;

  const _MainGameZone({
    required this.provider,
    this.projectProvider,
    required this.reels,
    required this.rows,
    this.winTier,
    this.winningPayline,
    this.isAnticipation = false,
    this.showWildExpansion = false,
    this.showScatterWin = false,
    this.showCascade = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background theme layer
        _buildBackgroundLayer(context),

        // Reel frame with effects - fills entire space
        Positioned.fill(
          child: _buildReelFrame(context),
        ),

        // Payline visualizer
        if (winningPayline != null && winningPayline!.isNotEmpty)
          _PaylineVisualizer(
            payline: winningPayline!,
            reels: reels,
            rows: rows,
          ),

        // Win highlight overlay
        if (winTier != null && winTier!.isNotEmpty)
          _WinHighlightOverlay(tier: winTier!),

        // Anticipation frame
        if (isAnticipation) _buildAnticipationFrame(),

        // Wild expansion layer
        if (showWildExpansion) _buildWildExpansion(),

        // Scatter win layer
        if (showScatterWin) _buildScatterWin(),

        // Cascade/tumble layer
        if (showCascade) _buildCascadeLayer(),
      ],
    );
  }

  Widget _buildBackgroundLayer(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.5,
          colors: [
            theme.bgMid,
            theme.bgDeep,
          ],
        ),
      ),
    );
  }

  Widget _buildReelFrame(BuildContext context) {
    final theme = context.slotTheme;
    final glowColor = _getWinColor(winTier, theme);
    final isWinning = winTier != null && winTier!.isNotEmpty;

    // Fill entire available space - no constraints, no aspect ratio limits
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isWinning ? glowColor : theme.gold.withOpacity(0.4),
                width: isWinning ? 5 : 3,
              ),
              boxShadow: [
                // Inner glow
                BoxShadow(
                  color: theme.gold.withOpacity(0.15),
                  blurRadius: 30,
                  spreadRadius: -5,
                ),
                // Main glow
                BoxShadow(
                  color: isWinning
                      ? glowColor.withOpacity(0.6)
                      : FluxForgeTheme.accentBlue.withOpacity(0.25),
                  blurRadius: isWinning ? 50 : 30,
                  spreadRadius: isWinning ? 15 : 5,
                ),
                // Deep shadow
                BoxShadow(
                  color: Colors.black.withOpacity(0.9),
                  blurRadius: 80,
                  spreadRadius: 30,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  // Reel content - ValueKey forces rebuild when dimensions change
                  // Consumer ensures reels are hidden during scene transitions
                  Consumer<GameFlowProvider>(
                    builder: (context, flow, _) => SlotPreviewWidget(
                      key: ValueKey('slot_preview_${reels}x$rows'),
                      provider: provider,
                      projectProvider: projectProvider ?? context.read<SlotLabProjectProvider>(),
                      reels: reels,
                      rows: rows,
                      showWinPresentation: true,
                      isTransitionActive: flow.isInTransition,
                    ),
                  ),
                  // L5 Game Flow Overlay — feature-specific UI (FS counter, H&W grid, etc.)
                  const Positioned.fill(
                    child: GameFlowOverlay(),
                  ),
                  // Unconfigured overlay — shown when no slot machine config exists
                  if (!GetIt.instance<FeatureComposerProvider>().isConfigured)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.casino_outlined, size: 48,
                                color: context.slotTheme.textMuted.withOpacity(0.5)),
                              const SizedBox(height: 12),
                              Text(
                                'NO CONFIGURATION',
                                style: TextStyle(
                                  color: context.slotTheme.textMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Configure your slot machine to start',
                                style: TextStyle(
                                  color: context.slotTheme.textMuted.withOpacity(0.6),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Glossy overlay
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.05),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withOpacity(0.1),
                            ],
                            stops: const [0.0, 0.15, 0.85, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnticipationFrame() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: FluxForgeTheme.accentOrange.withOpacity(0.8),
          width: 4,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: FluxForgeTheme.accentOrange.withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }

  Widget _buildWildExpansion() {
    return const _WildExpansionOverlay();
  }

  Widget _buildScatterWin() {
    return const _ScatterWinOverlay();
  }

  Widget _buildCascadeLayer() {
    return const _CascadeOverlay();
  }

  Color _getWinColor(String? tier, SlotThemeData theme) {
    return switch (tier) {
      'BIG_WIN_TIER_5' => theme.winUltra,
      'BIG_WIN_TIER_4' => theme.winEpic,
      'BIG_WIN_TIER_3' => theme.winMega,
      'BIG_WIN_TIER_2' => theme.winBig,
      'BIG_WIN_TIER_1' => theme.winBig,
      'SMALL' => theme.winSmall,
      _ => theme.accent,
    };
  }
}

class _PaylineVisualizer extends StatelessWidget {
  final List<int> payline;
  final int reels;
  final int rows;

  const _PaylineVisualizer({
    required this.payline,
    required this.reels,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return CustomPaint(
      size: Size.infinite,
      painter: _PaylinePainter(
        payline: payline,
        reels: reels,
        rows: rows,
        goldColor: theme.gold,
      ),
    );
  }
}

class _PaylinePainter extends CustomPainter {
  final List<int> payline;
  final int reels;
  final int rows;
  final Color goldColor;

  _PaylinePainter({
    required this.payline,
    required this.reels,
    required this.rows,
    required this.goldColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (payline.isEmpty) return;

    final paint = Paint()
      ..color = goldColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = goldColor.withOpacity(0.3)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final path = Path();
    final cellWidth = size.width / reels;
    final cellHeight = size.height / rows;

    for (int i = 0; i < payline.length && i < reels; i++) {
      final row = payline[i].clamp(0, rows - 1);
      final x = cellWidth * (i + 0.5);
      final y = cellHeight * (row + 0.5);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PaylinePainter oldDelegate) =>
      oldDelegate.payline != payline;
}

class _WinHighlightOverlay extends StatefulWidget {
  final String tier;

  const _WinHighlightOverlay({required this.tier});

  @override
  State<_WinHighlightOverlay> createState() => _WinHighlightOverlayState();
}

class _WinHighlightOverlayState extends State<_WinHighlightOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final color = _getColor(theme);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withOpacity(0.5 + _controller.value * 0.5),
              width: 6,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
        );
      },
    );
  }

  Color _getColor(SlotThemeData theme) {
    return switch (widget.tier) {
      'BIG_WIN_TIER_5' => theme.winUltra,
      'BIG_WIN_TIER_4' => theme.winEpic,
      'BIG_WIN_TIER_3' => theme.winMega,
      'BIG_WIN_TIER_2' => theme.winBig,
      'BIG_WIN_TIER_1' => theme.winBig,
      _ => theme.winSmall,
    };
  }
}

// =============================================================================
// CASCADE OVERLAY — Tumbling symbols animation
// =============================================================================

class _CascadeOverlay extends StatefulWidget {
  const _CascadeOverlay();

  @override
  State<_CascadeOverlay> createState() => _CascadeOverlayState();
}

class _CascadeOverlayState extends State<_CascadeOverlay>
    with TickerProviderStateMixin {
  late AnimationController _fallController;
  late AnimationController _glowController;
  final List<_CascadeSymbol> _symbols = [];
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _fallController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
    _fallController.addListener(_updateSymbols);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);

    _initSymbols();
  }

  void _initSymbols() {
    for (int i = 0; i < 15; i++) {
      _symbols.add(_CascadeSymbol(
        x: _random.nextDouble(),
        y: -_random.nextDouble() * 0.5,
        size: _random.nextDouble() * 30 + 20,
        speed: _random.nextDouble() * 0.02 + 0.015,
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.1,
        symbolIndex: _random.nextInt(8),
      ));
    }
  }

  void _updateSymbols() {
    if (!mounted) return;
    setState(() {
      for (final s in _symbols) {
        s.y += s.speed;
        s.rotation += s.rotationSpeed;
        if (s.y > 1.2) {
          s.y = -0.2;
          s.x = _random.nextDouble();
        }
      }
    });
  }

  @override
  void dispose() {
    _fallController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                FluxForgeTheme.accentCyan.withOpacity(0.1 + _glowController.value * 0.1),
                Colors.transparent,
                FluxForgeTheme.accentCyan.withOpacity(0.05 + _glowController.value * 0.05),
              ],
            ),
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: _CascadeSymbolPainter(symbols: _symbols),
          ),
        );
      },
    );
  }
}

class _CascadeSymbol {
  double x, y, size, speed, rotation, rotationSpeed;
  int symbolIndex;

  _CascadeSymbol({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.symbolIndex,
  });
}

class _CascadeSymbolPainter extends CustomPainter {
  final List<_CascadeSymbol> symbols;
  // Symbol chars for cascade animation — matches Rust engine order (HP1..HP4, LP1..LP3, WILD)
  static const _symbolChars = ['7', '▬', '🔔', '🍒', '🍋', '🍊', '🍇', '★'];

  _CascadeSymbolPainter({required this.symbols});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in symbols) {
      final x = s.x * size.width;
      final y = s.y * size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(s.rotation);

      // Glow effect
      final glowPaint = Paint()
        ..color = FluxForgeTheme.accentCyan.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset.zero, s.size / 2, glowPaint);

      // Symbol background
      final bgPaint = Paint()
        ..color = const Color(0xFF1a1a24);
      canvas.drawCircle(Offset.zero, s.size / 2.5, bgPaint);

      // Draw symbol text
      final textPainter = TextPainter(
        text: TextSpan(
          text: _symbolChars[s.symbolIndex % _symbolChars.length],
          style: TextStyle(
            fontSize: s.size * 0.5,
            color: FluxForgeTheme.accentCyan,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CascadeSymbolPainter oldDelegate) => true;
}

// =============================================================================
// WILD EXPANSION OVERLAY — Expanding wild symbol animation
// =============================================================================

class _WildExpansionOverlay extends StatefulWidget {
  const _WildExpansionOverlay();

  @override
  State<_WildExpansionOverlay> createState() => _WildExpansionOverlayState();
}

class _WildExpansionOverlayState extends State<_WildExpansionOverlay>
    with TickerProviderStateMixin {
  late AnimationController _expandController;
  late AnimationController _glowController;
  late AnimationController _sparkleController;
  final List<_Sparkle> _sparkles = [];
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);

    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _sparkleController.addListener(_updateSparkles);

    _initSparkles();
  }

  void _initSparkles() {
    for (int i = 0; i < 20; i++) {
      _sparkles.add(_Sparkle(
        x: 0.5 + (_random.nextDouble() - 0.5) * 0.3,
        y: 0.5 + (_random.nextDouble() - 0.5) * 0.3,
        vx: (_random.nextDouble() - 0.5) * 0.01,
        vy: (_random.nextDouble() - 0.5) * 0.01,
        size: _random.nextDouble() * 4 + 2,
        life: _random.nextDouble(),
      ));
    }
  }

  void _updateSparkles() {
    if (!mounted) return;
    setState(() {
      for (final s in _sparkles) {
        s.x += s.vx;
        s.y += s.vy;
        s.life -= 0.02;
        if (s.life <= 0) {
          s.x = 0.5 + (_random.nextDouble() - 0.5) * 0.2;
          s.y = 0.5 + (_random.nextDouble() - 0.5) * 0.2;
          s.vx = (_random.nextDouble() - 0.5) * 0.015;
          s.vy = (_random.nextDouble() - 0.5) * 0.015;
          s.life = 1.0;
        }
      }
    });
  }

  @override
  void dispose() {
    _expandController.dispose();
    _glowController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return AnimatedBuilder(
      animation: Listenable.merge([_expandController, _glowController]),
      builder: (context, _) {
        final scale = 0.8 + _expandController.value * 0.4;
        final glowOpacity = 0.3 + _glowController.value * 0.4;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Radial glow
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    theme.gold.withOpacity(glowOpacity),
                    theme.gold.withOpacity(glowOpacity * 0.3),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),

            // Sparkles
            CustomPaint(
              size: Size.infinite,
              painter: _SparklePainter(sparkles: _sparkles, goldColor: theme.gold),
            ),

            // Main wild icon
            Transform.scale(
              scale: scale,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFFFFD700),
                      Color(0xFFFF9040),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.gold.withOpacity(0.6),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    '★',
                    style: TextStyle(
                      fontSize: 60,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Sparkle {
  double x, y, vx, vy, size, life;

  _Sparkle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
  });
}

class _SparklePainter extends CustomPainter {
  final List<_Sparkle> sparkles;
  final Color goldColor;

  _SparklePainter({required this.sparkles, required this.goldColor});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparkles) {
      if (s.life <= 0) continue;
      final x = s.x * size.width;
      final y = s.y * size.height;
      final opacity = s.life;

      final paint = Paint()
        ..color = goldColor.withOpacity(opacity * 0.8);
      canvas.drawCircle(Offset(x, y), s.size * s.life, paint);

      // Star shape
      final starPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.6)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(x - s.size, y),
        Offset(x + s.size, y),
        starPaint,
      );
      canvas.drawLine(
        Offset(x, y - s.size),
        Offset(x, y + s.size),
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => true;
}

// =============================================================================
// SCATTER WIN OVERLAY — Scatter symbols flying to counter
// =============================================================================

class _ScatterWinOverlay extends StatefulWidget {
  const _ScatterWinOverlay();

  @override
  State<_ScatterWinOverlay> createState() => _ScatterWinOverlayState();
}

class _ScatterWinOverlayState extends State<_ScatterWinOverlay>
    with TickerProviderStateMixin {
  late AnimationController _collectController;
  late AnimationController _glowController;
  final List<_ScatterSymbol> _scatters = [];
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _collectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _collectController.addListener(_updateScatters);

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _initScatters();
  }

  void _initScatters() {
    // Scatter symbols at random positions, flying toward top-center
    for (int i = 0; i < 5; i++) {
      _scatters.add(_ScatterSymbol(
        startX: _random.nextDouble() * 0.6 + 0.2,
        startY: _random.nextDouble() * 0.4 + 0.3,
        progress: _random.nextDouble() * 0.3,
        delay: i * 0.15,
      ));
    }
  }

  void _updateScatters() {
    if (!mounted) return;
    setState(() {
      for (final s in _scatters) {
        if (_collectController.value > s.delay) {
          s.progress = (_collectController.value - s.delay) / (1.0 - s.delay);
          if (s.progress > 1.0) s.progress = s.progress % 1.0;
        }
      }
    });
  }

  @override
  void dispose() {
    _collectController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        return Stack(
          children: [
            // Background glow
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.8),
                  colors: [
                    theme.jackpotMinor.withOpacity(0.3 + _glowController.value * 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),

            // Scatter symbols
            CustomPaint(
              size: Size.infinite,
              painter: _ScatterPainter(scatters: _scatters, scatterColor: theme.jackpotMinor),
            ),

            // Collection target at top
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.jackpotMinor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.jackpotMinor.withOpacity(0.5 + _glowController.value * 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.jackpotMinor.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '◆',
                        style: TextStyle(
                          fontSize: 24,
                          color: theme.jackpotMinor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'SCATTER',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: theme.jackpotMinor,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScatterSymbol {
  double startX, startY, progress, delay;

  _ScatterSymbol({
    required this.startX,
    required this.startY,
    required this.progress,
    required this.delay,
  });

  double get currentX => startX + (0.5 - startX) * progress;
  double get currentY => startY + (0.1 - startY) * progress;
  double get scale => 1.0 - progress * 0.5;
  double get opacity => 1.0 - progress * 0.3;
}

class _ScatterPainter extends CustomPainter {
  final List<_ScatterSymbol> scatters;
  final Color scatterColor;

  _ScatterPainter({required this.scatters, required this.scatterColor});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in scatters) {
      final x = s.currentX * size.width;
      final y = s.currentY * size.height;
      final symbolSize = 40.0 * s.scale;

      // Trail effect
      for (int i = 0; i < 5; i++) {
        final trailProgress = s.progress - i * 0.05;
        if (trailProgress < 0) continue;
        final trailX = s.startX + (0.5 - s.startX) * trailProgress;
        final trailY = s.startY + (0.1 - s.startY) * trailProgress;
        final trailOpacity = (1.0 - i * 0.2) * 0.3;

        final trailPaint = Paint()
          ..color = scatterColor.withOpacity(trailOpacity);
        canvas.drawCircle(
          Offset(trailX * size.width, trailY * size.height),
          symbolSize * 0.3,
          trailPaint,
        );
      }

      // Glow
      final glowPaint = Paint()
        ..color = scatterColor.withOpacity(s.opacity * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(Offset(x, y), symbolSize * 0.8, glowPaint);

      // Symbol background
      final bgPaint = Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: symbolSize));
      canvas.drawCircle(Offset(x, y), symbolSize * 0.6, bgPaint);

      // Diamond symbol
      final textPainter = TextPainter(
        text: TextSpan(
          text: '◆',
          style: TextStyle(
            fontSize: symbolSize * 0.8,
            color: Colors.white.withOpacity(s.opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter oldDelegate) => true;
}

// =============================================================================
// GAMBLE OVERLAY
// =============================================================================

class _GambleOverlay extends StatelessWidget {
  final double stakeAmount;
  final int? cardRevealed; // 0,1=Red, 2,3=Black
  final bool? won;
  final VoidCallback onChooseRed;
  final VoidCallback onChooseBlack;
  final VoidCallback onCollect;

  const _GambleOverlay({
    required this.stakeAmount,
    this.cardRevealed,
    this.won,
    required this.onChooseRed,
    required this.onChooseBlack,
    required this.onCollect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final isRevealed = cardRevealed != null;
    final isRed = cardRevealed != null && cardRevealed! < 2;

    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.bgSurface.withOpacity(0.95),
                theme.bgMid.withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.gold.withOpacity(0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.gold.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [theme.gold, theme.jackpotMajor],
                ).createShader(bounds),
                child: const Text(
                  'GAMBLE',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Double or Nothing!',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),

              // Stake display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.bgDeep,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.gold.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      'STAKE',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${stakeAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: theme.gold,
                      ),
                    ),
                    if (!isRevealed) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Win: \$${(stakeAmount * 2).toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.green[400],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Card display (when revealed)
              if (isRevealed) ...[
                _buildRevealedCard(context, isRed, won ?? false),
                const SizedBox(height: 24),
              ],

              // Choice buttons (when not revealed)
              if (!isRevealed) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildChoiceButton(
                      label: 'RED',
                      color: Colors.red[700]!,
                      icon: Icons.favorite,
                      onTap: onChooseRed,
                    ),
                    const SizedBox(width: 24),
                    _buildChoiceButton(
                      label: 'BLACK',
                      color: Colors.grey[900]!,
                      icon: Icons.spa,
                      onTap: onChooseBlack,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // Result message
              if (isRevealed && won != null) ...[
                Text(
                  won! ? 'YOU WIN!' : 'YOU LOSE',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: won! ? Colors.green[400] : Colors.red[400],
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Collect button (always visible)
              if (!isRevealed || won == true)
                ElevatedButton.icon(
                  onPressed: onCollect,
                  icon: const Icon(Icons.account_balance_wallet, size: 20),
                  label: Text(
                    won == true ? 'COLLECT \$${(stakeAmount).toStringAsFixed(2)}' : 'COLLECT',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 160,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 48),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevealedCard(BuildContext context, bool isRed, bool won) {
    final theme = context.slotTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (_, value, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY((1 - value) * 3.14159),
          child: value > 0.5
              ? Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    color: isRed ? Colors.red[700] : Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: won ? Colors.green[400]! : Colors.red[400]!,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (won ? Colors.green : Colors.red).withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isRed ? Icons.favorite : Icons.spa,
                        color: Colors.white,
                        size: 48,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isRed ? 'RED' : 'BLACK',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.bgMid, theme.bgDeep],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.gold, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '?',
                      style: TextStyle(
                        color: theme.gold,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

// =============================================================================
// D. WIN PRESENTER — REMOVED (Dead code)
// =============================================================================
// SlotPreviewWidget (child widget) already has complete, working win presentation
// No need for duplicate overlay that never executed properly

// =============================================================================
// E. FEATURE INDICATORS
// =============================================================================

class _FeatureIndicators extends StatelessWidget {
  const _FeatureIndicators();

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;

    return Consumer<GameFlowProvider>(
      builder: (context, flow, _) {
        if (!flow.isInFeature) return const SizedBox.shrink();

        final fs = flow.freeSpinsState;
        final cs = flow.cascadeState;
        final collector = flow.getFeatureState('collector');

        // Determine active multiplier from any feature
        double activeMult = 1.0;
        for (final state in flow.activeFeatures.values) {
          if (state.currentMultiplier > activeMult) {
            activeMult = state.currentMultiplier;
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Free spin counter
              if (fs != null) ...[
                _FeatureBadge(
                  icon: Icons.star,
                  label: 'FREE SPINS',
                  value: '${fs.spinsRemaining} / ${fs.totalSpins}',
                  color: theme.jackpotMinor,
                ),
                const SizedBox(width: 16),
              ],

              // Collector meter
              if (collector != null && collector.meterValues.isNotEmpty) ...[
                _FeatureMeter(
                  label: 'COLLECTION',
                  value: collector.progress,
                  color: theme.jackpotMajor,
                ),
                const SizedBox(width: 16),
              ],

              // Feature progress
              if (flow.isInFeature) ...[
                _FeatureMeter(
                  label: flow.currentState.displayName.toUpperCase(),
                  value: _activeProgress(flow),
                  color: FluxForgeTheme.accentCyan,
                ),
                const SizedBox(width: 16),
              ],

              // Multiplier trail
              if (activeMult > 1) ...[
                _FeatureBadge(
                  icon: Icons.close,
                  label: 'MULTIPLIER',
                  value: '${activeMult.toStringAsFixed(1)}x',
                  color: theme.gold,
                ),
                const SizedBox(width: 16),
              ],

              // Cascade counter
              if (cs != null && cs.cascadeDepth > 0) ...[
                _FeatureBadge(
                  icon: Icons.waterfall_chart,
                  label: 'CASCADE',
                  value: '${cs.cascadeDepth}',
                  color: FluxForgeTheme.accentCyan,
                ),
                const SizedBox(width: 16),
              ],

              // Queue indicator
              if (flow.hasQueuedFeatures)
                _FeatureBadge(
                  icon: Icons.queue,
                  label: 'QUEUED',
                  value: '+${flow.featureQueue.length}',
                  color: theme.gold,
                ),
            ],
          ),
        );
      },
    );
  }

  double _activeProgress(GameFlowProvider flow) {
    for (final state in flow.activeFeatures.values) {
      final p = state.progress;
      if (p > 0) return p;
    }
    return 0.0;
  }
}

class _FeatureBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _FeatureBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 8,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureMeter extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _FeatureMeter({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: theme.bgSurface,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${(value * 100).toInt()}%',
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// F. CONTROL BAR
// =============================================================================

/// Modern Control Bar — Total Bet Only (Pragmatic Play / BTG / Hacksaw style)
///
/// Features:
/// - Single TOTAL BET display with +/- buttons
/// - Quick Bet Presets row for one-tap bet selection
/// - Static WAYS info badge (from GDD)
/// - No LINES/COIN/BET LEVEL controls (legacy removed)
class _ControlBar extends StatelessWidget {
  // Modern bet system
  final double totalBet;
  final double minBet;
  final double maxBet;
  final double betStep;
  final List<double> quickBetPresets;
  final int? waysCount; // null = paylines mode, value = ways mode
  final int? paylinesCount; // for paylines slots

  // Spin controls
  final bool isSpinning;
  final bool showStopButton;
  final bool isAutoSpin;
  final int autoSpinCount;
  final bool isTurbo;
  final bool canSpin;
  final bool isConfigured; // Slot machine built — gates ALL controls

  // SKIP button controls (industry-standard win presentation skip)
  final bool isInWinPresentation;
  final String currentWinTier;
  final double bigWinProtectionRemaining;

  // Callbacks
  final ValueChanged<double> onBetChanged;
  final VoidCallback onMaxBet;
  final VoidCallback onSpin;
  final VoidCallback onStop;
  final VoidCallback? onSkip;
  final VoidCallback onAutoSpinToggle;
  final VoidCallback onTurboToggle;
  final VoidCallback? onAfterInteraction;

  const _ControlBar({
    required this.totalBet,
    required this.minBet,
    required this.maxBet,
    required this.betStep,
    required this.quickBetPresets,
    this.waysCount,
    this.paylinesCount,
    required this.isSpinning,
    required this.showStopButton,
    required this.isAutoSpin,
    required this.autoSpinCount,
    required this.isTurbo,
    required this.canSpin,
    this.isConfigured = true,
    required this.isInWinPresentation,
    required this.currentWinTier,
    required this.bigWinProtectionRemaining,
    required this.onBetChanged,
    required this.onMaxBet,
    required this.onSpin,
    required this.onStop,
    this.onSkip,
    required this.onAutoSpinToggle,
    required this.onTurboToggle,
    this.onAfterInteraction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.bgMid.withOpacity(0.95),
            theme.bgDark,
          ],
        ),
        border: Border(
          top: BorderSide(color: theme.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick Bet Presets row
          Opacity(
            opacity: isConfigured ? 1.0 : 0.3,
            child: IgnorePointer(
              ignoring: !isConfigured,
              child: _QuickBetPresetsRow(
                presets: quickBetPresets,
                currentBet: totalBet,
                isDisabled: isSpinning || !isConfigured,
                onPresetSelected: (bet) {
                  onBetChanged(bet);
                  onAfterInteraction?.call();
                },
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Main controls row
          Opacity(
            opacity: isConfigured ? 1.0 : 0.3,
            child: IgnorePointer(
              ignoring: !isConfigured,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // WAYS/PAYLINES info badge (static, from GDD)
                  if (waysCount != null || paylinesCount != null)
                    _InfoBadge(
                      label: waysCount != null ? 'WAYS' : 'LINES',
                      value: waysCount != null
                          ? _formatWays(waysCount!)
                          : '$paylinesCount',
                    ),
                  if (waysCount != null || paylinesCount != null)
                    const SizedBox(width: 16),

                  // Total Bet control with +/- buttons
                  _ModernBetControl(
                    totalBet: totalBet,
                    minBet: minBet,
                    maxBet: maxBet,
                    betStep: betStep,
                    isDisabled: isSpinning || !isConfigured,
                    onDecrease: () {
                      final newBet = (totalBet - betStep).clamp(minBet, maxBet);
                      onBetChanged(newBet);
                      onAfterInteraction?.call();
                    },
                    onIncrease: () {
                      final newBet = (totalBet + betStep).clamp(minBet, maxBet);
                      onBetChanged(newBet);
                      onAfterInteraction?.call();
                    },
                  ),
                  const SizedBox(width: 16),

                  // Max bet button
                  _ControlButton(
                    label: 'MAX\nBET',
                    gradient: theme.maxBetGradient,
                    onTap: (isSpinning || !isConfigured) ? null : () {
                      onMaxBet();
                      onAfterInteraction?.call();
                    },
                    width: 54,
                    height: 54,
                  ),
                  const SizedBox(width: 10),

                  // Auto spin button
                  _ControlButton(
                    label: isAutoSpin ? 'STOP\n$autoSpinCount' : 'AUTO\nSPIN',
                    gradient: isAutoSpin ? theme.autoSpinGradient : null,
                    onTap: !isConfigured ? null : () {
                      onAutoSpinToggle();
                      onAfterInteraction?.call();
                    },
                    width: 54,
                    height: 54,
                    isActive: isAutoSpin,
                  ),
                  const SizedBox(width: 10),

                  // Turbo toggle
                  _ControlButton(
                    icon: Icons.bolt,
                    label: 'TURBO',
                    gradient: isTurbo ? [FluxForgeTheme.accentOrange, const Color(0xFFFF6020)] : null,
                    onTap: !isConfigured ? null : () {
                      onTurboToggle();
                      onAfterInteraction?.call();
                    },
                    width: 54,
                    height: 54,
                    isActive: isTurbo,
                  ),
                  const SizedBox(width: 20),

                  // Main spin/stop/skip button (industry-standard 3-phase)
                  _SpinButton(
                    isSpinning: isSpinning,
                    showStopButton: showStopButton,
                    canSpin: canSpin,
                    isInWinPresentation: isInWinPresentation,
                    currentWinTier: currentWinTier,
                    bigWinProtectionRemaining: bigWinProtectionRemaining,
                    onSpin: onSpin,
                    onStop: onStop,
                    onSkip: onSkip,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Format ways count for display (e.g., 243, 1024, 117649)
  String _formatWays(int ways) {
    if (ways >= 100000) return '${(ways / 1000).toStringAsFixed(0)}K';
    return ways.toString();
  }
}

/// Quick Bet Presets row — one-tap bet selection
class _QuickBetPresetsRow extends StatelessWidget {
  final List<double> presets;
  final double currentBet;
  final bool isDisabled;
  final ValueChanged<double> onPresetSelected;

  const _QuickBetPresetsRow({
    required this.presets,
    required this.currentBet,
    required this.isDisabled,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: presets.map((preset) {
          final isSelected = (preset - currentBet).abs() < 0.01;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _QuickBetChip(
              amount: preset,
              isSelected: isSelected,
              isDisabled: isDisabled,
              onTap: () => onPresetSelected(preset),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Quick Bet chip button
class _QuickBetChip extends StatelessWidget {
  final double amount;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const _QuickBetChip({
    required this.amount,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [theme.gold, theme.gold.withOpacity(0.7)])
              : null,
          color: isSelected ? null : theme.bgPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.gold : theme.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: theme.gold.withOpacity(0.4), blurRadius: 6)]
              : null,
        ),
        child: Text(
          _formatAmount(amount),
          style: TextStyle(
            color: isSelected ? theme.bgDark : theme.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1.0) {
      return '\$${amount.toStringAsFixed(0)}';
    }
    return '\$${amount.toStringAsFixed(2)}';
  }
}

/// Modern Bet Control with +/- buttons and total display
class _ModernBetControl extends StatelessWidget {
  final double totalBet;
  final double minBet;
  final double maxBet;
  final double betStep;
  final bool isDisabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _ModernBetControl({
    required this.totalBet,
    required this.minBet,
    required this.maxBet,
    required this.betStep,
    required this.isDisabled,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final canDecrease = !isDisabled && totalBet > minBet;
    final canIncrease = !isDisabled && totalBet < maxBet;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: theme.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.gold.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrease button
          _BetArrowButton(
            icon: Icons.remove,
            onTap: canDecrease ? onDecrease : null,
          ),
          const SizedBox(width: 8),

          // Total Bet display
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TOTAL BET',
                style: TextStyle(
                  color: theme.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '\$${totalBet.toStringAsFixed(2)}',
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // Increase button
          _BetArrowButton(
            icon: Icons.add,
            onTap: canIncrease ? onIncrease : null,
          ),
        ],
      ),
    );
  }
}

/// Arrow button for bet control (+/-)
class _BetArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _BetArrowButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isEnabled ? theme.gold.withOpacity(0.2) : theme.bgPanel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isEnabled ? theme.gold : theme.border,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isEnabled ? theme.gold : theme.textSecondary.withOpacity(0.5),
        ),
      ),
    );
  }
}

/// Static info badge (WAYS or LINES)
class _InfoBadge extends StatelessWidget {
  final String label;
  final String value;

  const _InfoBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Legacy _BetSelector, _SelectorArrow, _TotalBetDisplay removed
// Now using: _ModernBetControl, _QuickBetPresetsRow, _QuickBetChip, _BetArrowButton, _InfoBadge

class _ControlButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final List<Color>? gradient;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final bool isActive;

  const _ControlButton({
    required this.label,
    this.icon,
    this.gradient,
    this.onTap,
    this.width = 70,
    this.height = 50,
    this.isActive = false,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    final hasGradient = widget.gradient != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Builder(
          builder: (context) {
            final theme = context.slotTheme;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                gradient: hasGradient
                    ? LinearGradient(colors: widget.gradient!)
                    : null,
                color: hasGradient
                    ? null
                    : (_isHovered
                        ? theme.bgSurface
                        : theme.bgPanel),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasGradient
                      ? widget.gradient![0].withOpacity(_isHovered ? 1.0 : 0.6)
                      : theme.border,
                  width: _isHovered ? 2 : 1,
                ),
                boxShadow: hasGradient && _isHovered
                    ? [
                        BoxShadow(
                          color: widget.gradient![0].withOpacity(0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: hasGradient || widget.isActive
                          ? Colors.white
                          : theme.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: hasGradient || widget.isActive
                          ? Colors.white
                          : theme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Industry-Standard Spin Button with SPIN/STOP/SKIP phases.
///
/// **Button Phases (NetEnt, Pragmatic Play, IGT, Aristocrat standard):**
/// - **SPIN** (blue): Ready to start spin
/// - **STOP** (red): Reels spinning, can stop immediately
/// - **SKIP** (gold): Win presentation, can skip to collect
///
/// Big Win tiers have mandatory celebration times (protection) before SKIP activates.
/// Countdown timer shows remaining seconds during protection period.
class _SpinButton extends StatefulWidget {
  final bool isSpinning;
  final bool showStopButton; // True ONLY while reels are visually spinning
  final bool canSpin;
  final VoidCallback onSpin;
  final VoidCallback onStop;

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW: Win Presentation / SKIP Phase Support
  // ═══════════════════════════════════════════════════════════════════════════

  /// True when win presentation is active (rollup, plaque, win lines)
  final bool isInWinPresentation;

  /// Current win tier for Big Win protection timing (e.g., 'BIG_WIN', 'MEGA_WIN')
  final String currentWinTier;

  /// Callback when SKIP is pressed (skips win presentation)
  final VoidCallback? onSkip;

  /// Remaining seconds of Big Win protection countdown (0 = no protection)
  final double bigWinProtectionRemaining;

  const _SpinButton({
    required this.isSpinning,
    required this.showStopButton,
    required this.canSpin,
    required this.onSpin,
    required this.onStop,
    this.isInWinPresentation = false,
    this.currentWinTier = '',
    this.onSkip,
    this.bigWinProtectionRemaining = 0.0,
  });

  @override
  State<_SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<_SpinButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Determine current button phase based on state
  SpinButtonPhase get _currentPhase {
    if (widget.showStopButton) {
      return SpinButtonPhase.stop;
    }
    if (widget.isInWinPresentation) {
      if (widget.bigWinProtectionRemaining > 0) {
        return SpinButtonPhase.skipProtected;
      }
      return SpinButtonPhase.skip;
    }
    return SpinButtonPhase.spin;
  }

  @override
  Widget build(BuildContext context) {
    final phase = _currentPhase;

    // Determine button enabled state
    final isEnabled = switch (phase) {
      SpinButtonPhase.spin => widget.canSpin,
      SpinButtonPhase.stop => true, // Always can stop reels
      SpinButtonPhase.skip => true, // Can skip when no protection
      SpinButtonPhase.skipProtected => false, // Cannot skip during protection
    };

    // Get gradient colors for current phase
    final gradientColors = switch (phase) {
      SpinButtonPhase.spin => isEnabled
          ? SpinButtonColors.spinGradient
          : SpinButtonColors.disabledGradient,
      SpinButtonPhase.stop => SpinButtonColors.stopGradient,
      SpinButtonPhase.skip => SpinButtonColors.skipGradient,
      SpinButtonPhase.skipProtected => SpinButtonColors.skipProtectedGradient,
    };

    // Get border/glow color
    final theme = context.slotTheme;
    final accentColor = switch (phase) {
      SpinButtonPhase.spin => FluxForgeTheme.accentBlue,
      SpinButtonPhase.stop => FluxForgeTheme.accentRed,
      SpinButtonPhase.skip => theme.gold,
      SpinButtonPhase.skipProtected => theme.gold.withOpacity(0.6),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: () {
          // 🔴 DEBUG: Log button tap with all conditions
          switch (phase) {
            case SpinButtonPhase.spin:
              if (widget.canSpin) {
                widget.onSpin();
              }
            case SpinButtonPhase.stop:
              widget.onStop();
            case SpinButtonPhase.skip:
              widget.onSkip?.call();
            case SpinButtonPhase.skipProtected:
              // Ignore tap during protection (visual feedback only)
              break;
          }
        },
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            // Pulse animation for SPIN phase only
            final pulse = phase == SpinButtonPhase.spin && isEnabled
                ? (0.95 + _pulseController.value * 0.1)
                : 1.0;

            return Transform.scale(
              scale: pulse,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  border: Border.all(
                    color: isEnabled ? accentColor : theme.border,
                    width: _isHovered && isEnabled ? 4 : 3,
                  ),
                  boxShadow: [
                    if (isEnabled)
                      BoxShadow(
                        color: accentColor.withOpacity(_isHovered ? 0.6 : 0.4),
                        blurRadius: _isHovered ? 24 : 16,
                        spreadRadius: _isHovered ? 4 : 2,
                      ),
                  ],
                ),
                child: Center(
                  child: _buildButtonContent(phase, isEnabled, theme),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Build button content based on current phase
  Widget _buildButtonContent(SpinButtonPhase phase, bool isEnabled, SlotThemeData theme) {
    switch (phase) {
      case SpinButtonPhase.stop:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stop, color: Colors.white, size: 32),
            SizedBox(height: 4),
            Text(
              'STOP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        );

      case SpinButtonPhase.skip:
        // Gold SKIP button - ready to skip
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.skip_next, color: Color(0xFF1a1a24), size: 32),
            SizedBox(height: 4),
            Text(
              'SKIP',
              style: TextStyle(
                color: Color(0xFF1a1a24), // Dark text on gold
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        );

      case SpinButtonPhase.skipProtected:
        // Gold SKIP button with countdown timer
        final remainingSeconds = widget.bigWinProtectionRemaining.ceil();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Countdown circle
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: 1.0 - (widget.bigWinProtectionRemaining /
                        BigWinProtection.forTier(widget.currentWinTier)),
                    strokeWidth: 3,
                    color: const Color(0xFF1a1a24),
                    backgroundColor: const Color(0xFF1a1a24).withOpacity(0.3),
                  ),
                ),
                Text(
                  '$remainingSeconds',
                  style: const TextStyle(
                    color: Color(0xFF1a1a24),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'SKIP',
              style: TextStyle(
                color: Color(0xFF1a1a24),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        );

      case SpinButtonPhase.spin:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow,
              color: isEnabled ? Colors.white : theme.textMuted,
              size: 36,
            ),
            Text(
              'SPIN',
              style: TextStyle(
                color: isEnabled ? Colors.white : theme.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
          ],
        );
    }
  }
}

// =============================================================================
// G. INFO PANELS — REMOVED
// =============================================================================
// NOTE: All info panels (Paytable, Rules, History, Stats) have been consolidated
// into ProjectDashboardDialog for a unified experience. Access via Menu → Dashboard.
// See: project_dashboard_dialog.dart

// =============================================================================
// G2. MENU PANEL
// =============================================================================

class _MenuPanel extends StatelessWidget {
  final VoidCallback onDashboard;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onClose;

  const _MenuPanel({
    required this.onDashboard,
    required this.onSettings,
    required this.onHelp,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.menu, color: theme.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'MENU',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.close, color: theme.textSecondary, size: 18),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          Divider(color: theme.border, height: 16),

          // Dashboard — Paytable, Rules, History, Stats consolidated
          _MenuItem(
            icon: Icons.dashboard,
            label: 'Dashboard',
            onTap: onDashboard,
            highlight: true,
            subtitle: 'Paytable • Rules • Stats',
          ),
          Divider(color: theme.border, height: 12),
          _MenuItem(icon: Icons.settings, label: 'Settings', onTap: onSettings),
          _MenuItem(icon: Icons.help_outline, label: 'Help', onTap: onHelp),
        ],
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;
  final String? subtitle;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
    this.subtitle,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    final highlightColor = widget.highlight ? theme.gold : FluxForgeTheme.accentBlue;
    final baseColor = widget.highlight ? highlightColor.withOpacity(0.1) : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: _isHovered ? highlightColor.withOpacity(0.2) : baseColor,
            borderRadius: BorderRadius.circular(8),
            border: widget.highlight ? Border.all(
              color: highlightColor.withOpacity(0.3),
              width: 1,
            ) : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: _isHovered || widget.highlight ? highlightColor : theme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: _isHovered || widget.highlight ? highlightColor : theme.textPrimary,
                        fontSize: 13,
                        fontWeight: widget.highlight ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          color: theme.textMuted,
                          fontSize: 10,
                        ),
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
}

// =============================================================================
// H. AUDIO/VISUAL CONTROLS
// =============================================================================

/// P6: Consolidated Settings Panel — combines Audio, Visual, Device, Theme, Recording, Debug
class _AudioVisualPanel extends StatelessWidget {
  final double volume;
  final bool isMusicOn;
  final bool isSfxOn;
  final int quality; // 0=Low, 1=Medium, 2=High
  final bool animationsEnabled;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMusicToggle;
  final VoidCallback onSfxToggle;
  final ValueChanged<int> onQualityChanged;
  final VoidCallback onAnimationsToggle;
  final VoidCallback onClose;

  // P6: Device simulation
  final DeviceSimulation deviceSimulation;
  final ValueChanged<DeviceSimulation> onDeviceChanged;

  // P6: Theme
  final SlotThemePreset currentTheme;
  final SlotThemePreset? comparisonTheme;
  final ValueChanged<SlotThemePreset> onThemeChanged;
  final ValueChanged<SlotThemePreset?> onComparisonThemeChanged;

  // P6: Debug
  final bool showFps;
  final bool showVoices;
  final bool showMemory;
  final bool showStageTrace;
  final VoidCallback onShowFpsToggle;
  final VoidCallback onShowVoicesToggle;
  final VoidCallback onShowMemoryToggle;
  final VoidCallback onShowStageTraceToggle;

  const _AudioVisualPanel({
    required this.volume,
    required this.isMusicOn,
    required this.isSfxOn,
    required this.quality,
    required this.animationsEnabled,
    required this.onVolumeChanged,
    required this.onMusicToggle,
    required this.onSfxToggle,
    required this.onQualityChanged,
    required this.onAnimationsToggle,
    required this.onClose,
    // P6 params
    this.deviceSimulation = DeviceSimulation.desktop,
    required this.onDeviceChanged,
    this.currentTheme = SlotThemePreset.casino,
    this.comparisonTheme,
    required this.onThemeChanged,
    required this.onComparisonThemeChanged,
    this.showFps = true,
    this.showVoices = true,
    this.showMemory = true,
    this.showStageTrace = false,
    required this.onShowFpsToggle,
    required this.onShowVoicesToggle,
    required this.onShowMemoryToggle,
    required this.onShowStageTraceToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.settings, color: theme.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'SETTINGS',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.close, color: theme.textSecondary, size: 18),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          Divider(color: theme.border, height: 20),

          // Volume slider
          Text(
            'MASTER VOLUME',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                volume == 0 ? Icons.volume_off : Icons.volume_up,
                color: theme.textSecondary,
                size: 18,
              ),
              Expanded(
                child: Slider(
                  value: volume,
                  onChanged: onVolumeChanged,
                  activeColor: FluxForgeTheme.accentBlue,
                  inactiveColor: theme.bgSurface,
                ),
              ),
              Text(
                '${(volume * 100).toInt()}%',
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Audio toggles
          Row(
            children: [
              Expanded(
                child: _SettingToggle(
                  icon: Icons.music_note,
                  label: 'Music',
                  isOn: isMusicOn,
                  onToggle: onMusicToggle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SettingToggle(
                  icon: Icons.volume_up,
                  label: 'SFX',
                  isOn: isSfxOn,
                  onToggle: onSfxToggle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quality selector
          Text(
            'GRAPHICS QUALITY',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _QualityButton(
                label: 'LOW',
                isSelected: quality == 0,
                onTap: () => onQualityChanged(0),
              ),
              const SizedBox(width: 8),
              _QualityButton(
                label: 'MED',
                isSelected: quality == 1,
                onTap: () => onQualityChanged(1),
              ),
              const SizedBox(width: 8),
              _QualityButton(
                label: 'HIGH',
                isSelected: quality == 2,
                onTap: () => onQualityChanged(2),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Animations toggle
          _SettingToggle(
            icon: Icons.animation,
            label: 'Animations',
            isOn: animationsEnabled,
            onToggle: onAnimationsToggle,
          ),

          Divider(color: theme.border, height: 24),

          // P6: Device Section
          Text(
            '📱 DEVICE',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: DeviceSimulation.values.map((device) {
              final isSelected = device == deviceSimulation;
              return GestureDetector(
                onTap: () => onDeviceChanged(device),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                        : theme.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? FluxForgeTheme.accentBlue.withOpacity(0.5)
                          : theme.border.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(device.icon, size: 14,
                        color: isSelected ? FluxForgeTheme.accentBlue : theme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        device.label,
                        style: TextStyle(
                          color: isSelected ? FluxForgeTheme.accentBlue : theme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          Divider(color: theme.border, height: 24),

          // P6: Theme Section
          Text(
            '🎨 THEME',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ThemeDropdown(
                  value: currentTheme,
                  onChanged: onThemeChanged,
                ),
              ),
              const SizedBox(width: 8),
              // Comparison theme dropdown (optional)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.bgMid.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.border.withOpacity(0.5)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SlotThemePreset?>(
                      value: comparisonTheme,
                      isDense: true,
                      hint: Text('Compare', style: TextStyle(color: theme.textMuted, fontSize: 12)),
                      icon: Icon(Icons.arrow_drop_down, color: theme.textSecondary, size: 18),
                      dropdownColor: theme.bgDark,
                      style: TextStyle(color: theme.textPrimary, fontSize: 12),
                      items: [
                        const DropdownMenuItem<SlotThemePreset?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ...SlotThemePreset.values.map((preset) {
                          return DropdownMenuItem(
                            value: preset,
                            child: Text(preset.label),
                          );
                        }),
                      ],
                      onChanged: onComparisonThemeChanged,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // P6: Debug Section (debug mode only)
          if (kDebugMode) ...[
            Divider(color: theme.border, height: 24),
            Text(
              '🔧 DEBUG',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SettingToggle(
                    icon: Icons.speed,
                    label: 'FPS',
                    isOn: showFps,
                    onToggle: onShowFpsToggle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SettingToggle(
                    icon: Icons.record_voice_over,
                    label: 'Voices',
                    isOn: showVoices,
                    onToggle: onShowVoicesToggle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SettingToggle(
                    icon: Icons.memory,
                    label: 'Memory',
                    isOn: showMemory,
                    onToggle: onShowMemoryToggle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SettingToggle(
                    icon: Icons.timeline,
                    label: 'Stages',
                    isOn: showStageTrace,
                    onToggle: onShowStageTraceToggle,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingToggle extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isOn;
  final VoidCallback onToggle;

  const _SettingToggle({
    required this.icon,
    required this.label,
    required this.isOn,
    required this.onToggle,
  });

  @override
  State<_SettingToggle> createState() => _SettingToggleState();
}

class _SettingToggleState extends State<_SettingToggle> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isOn
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : (_isHovered ? theme.bgSurface : theme.bgDark),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isOn
                  ? FluxForgeTheme.accentBlue
                  : theme.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: widget.isOn
                    ? FluxForgeTheme.accentBlue
                    : theme.textMuted,
                size: 14,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isOn
                        ? theme.textPrimary
                        : theme.textSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 28,
                height: 16,
                decoration: BoxDecoration(
                  color: widget.isOn
                      ? FluxForgeTheme.accentBlue
                      : theme.bgSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 150),
                  alignment: widget.isOn
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityButton extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _QualityButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_QualityButton> createState() => _QualityButtonState();
}

class _QualityButtonState extends State<_QualityButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.slotTheme;
    return Expanded(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? FluxForgeTheme.accentBlue
                  : (_isHovered ? theme.bgSurface : theme.bgDark),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.isSelected
                    ? FluxForgeTheme.accentBlue
                    : theme.border,
              ),
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.isSelected
                      ? Colors.white
                      : theme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AMBIENT PARTICLES (Reused)
// =============================================================================
// MAIN PREMIUM SLOT PREVIEW WIDGET
// =============================================================================

class PremiumSlotPreview extends StatefulWidget {
  final VoidCallback onExit;
  final int reels;
  final int rows;
  /// When true, this widget handles SPACE key for spin/stop.
  /// When false (embedded mode), SPACE is ignored and handled by parent (slot_lab_screen).
  final bool isFullscreen;

  /// P5: Project provider for dynamic win tier configuration
  /// When null, uses context.read or legacy fallback
  final SlotLabProjectProvider? projectProvider;

  /// Show splash loading screen before entering base game
  final bool showSplash;

  /// Called when splash completes and user clicks CONTINUE
  final VoidCallback? onSplashComplete;

  /// Called when user clicks Reload button in header
  final VoidCallback? onReload;

  const PremiumSlotPreview({
    super.key,
    required this.onExit,
    this.reels = 3,
    this.rows = 3,
    this.isFullscreen = false,
    this.projectProvider,
    this.showSplash = false,
    this.onSplashComplete,
    this.onReload,
  });

  @override
  State<PremiumSlotPreview> createState() => _PremiumSlotPreviewState();
}

class _PremiumSlotPreviewState extends State<PremiumSlotPreview>
    with TickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();

  // Animation controllers
  late AnimationController _jackpotTickController;

  final _random = math.Random();

  // === STATE ===

  // Splash screen — shown before base game (only after auto-bind or GENERATE)
  late bool _showSplashScreen;

  // Session
  double _balance = 1000.0;
  double _sessionTotalBet = 0.0; // Total amount bet in session (for RTP calc)
  double _totalWin = 0.0;
  int _totalSpins = 0;
  int _wins = 0;
  int _losses = 0;
  // NOTE: Recent wins are now tracked in SlotLabProjectProvider.sessionStats
  // Access via Dashboard → Stats tab

  // ═══════════════════════════════════════════════════════════════════════════
  // SPACE KEY DEBOUNCE — Prevents double-trigger within 200ms
  // This fixes the bug where SPACE immediately stops reels after starting spin
  // ═══════════════════════════════════════════════════════════════════════════
  int _lastSpaceKeyTime = 0;
  static const int _spaceKeyDebounceMs = 200;

  // Jackpots (simulated progressive)
  // Seed values (reset after jackpot win)
  static const double _miniJackpotSeed = 100.0;
  static const double _minorJackpotSeed = 1000.0;
  static const double _majorJackpotSeed = 10000.0;
  static const double _grandJackpotSeed = 100000.0;

  // Contribution percentages of bet (industry standard ~0.5-2% total)
  // Distribution: Mini 40%, Minor 30%, Major 20%, Grand 10% of contribution
  static const double _jackpotContributionRate = 0.015; // 1.5% of bet goes to jackpots
  static const double _miniContribShare = 0.40;   // 40% of contribution → Mini
  static const double _minorContribShare = 0.30;  // 30% of contribution → Minor
  static const double _majorContribShare = 0.20;  // 20% of contribution → Major
  static const double _grandContribShare = 0.10;  // 10% of contribution → Grand

  double _miniJackpot = _miniJackpotSeed + 25.50;
  double _minorJackpot = _minorJackpotSeed + 250.00;
  double _majorJackpot = _majorJackpotSeed + 2500.00;
  double _grandJackpot = _grandJackpotSeed + 25000.00;
  double _progressiveContribution = 0.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // MODERN BET SYSTEM — Total Bet Only (Pragmatic Play style)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Current total bet amount (the ONLY bet control)
  double _totalBet = 2.00;

  /// Quick bet presets for one-tap selection
  static const List<double> _quickBetPresets = [
    0.20, 0.50, 1.00, 2.00, 5.00, 10.00, 20.00, 50.00, 100.00,
  ];

  /// Minimum and maximum bet limits
  static const double _minBet = 0.20;
  static const double _maxBet = 100.00;

  /// Bet step for +/- buttons (adjusts based on current bet)
  double get _betStep {
    if (_totalBet < 1.00) return 0.10;
    if (_totalBet < 5.00) return 0.50;
    if (_totalBet < 20.00) return 1.00;
    if (_totalBet < 50.00) return 5.00;
    return 10.00;
  }

  /// Legacy getter for compatibility (returns _totalBet directly)
  double get _totalBetAmount => _totalBet;

  // NOTE: Game rules config moved to Dashboard → Rules tab
  // Access via SlotLabProjectProvider.importedGdd

  // Feature state
  int _freeSpins = 0;
  int _freeSpinsRemaining = 0;
  double _bonusMeter = 0.0;
  double _featureProgress = 0.0;
  int _multiplier = 1;
  int _cascadeCount = 0;
  int _specialSymbolCount = 0;

  // Auto-spin
  bool _isAutoSpin = false;
  int _autoSpinCount = 0;
  int _autoSpinRemaining = 0;

  // Settings (persisted via SharedPreferences)
  bool _isTurbo = false;
  bool _isMusicOn = true;
  bool _isSfxOn = true;
  double _masterVolume = 0.8;
  int _graphicsQuality = 2;
  bool _animationsEnabled = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // P6: DEVICE SIMULATION & THEME STATE
  // ═══════════════════════════════════════════════════════════════════════════
  DeviceSimulation _deviceSimulation = DeviceSimulation.desktop;
  SlotThemePreset _themeA = SlotThemePreset.casino;
  SlotThemePreset? _themeB; // null = no comparison mode
  bool _showThemeComparison = false;

  // P6: DEBUG TOOLBAR STATE
  bool _showDebugToolbar = false;
  bool _showFpsCounter = true;
  bool _showVoiceCount = true;
  bool _showMemoryUsage = true;
  bool _showStageTrace = false;
  int _currentFps = 60;
  int _activeVoices = 0;
  int _memoryUsageMb = 0;
  Timer? _debugStatsTimer;

  // P6: Recording removed from SlotLab header

  // SharedPreferences keys
  static const _prefKeyTurbo = 'psp_turbo';
  static const _prefKeyMusic = 'psp_music';
  static const _prefKeySfx = 'psp_sfx';
  static const _prefKeyVolume = 'psp_volume';
  static const _prefKeyQuality = 'psp_quality';
  static const _prefKeyAnimations = 'psp_animations';
  static const _prefKeyDeviceSimulation = 'psp_device_simulation';
  static const _prefKeyTheme = 'psp_theme';

  // UI state
  bool _showSettingsPanel = false;
  bool _showMenuPanel = false;
  // NOTE: Paytable, Rules, History, Stats moved to ProjectDashboardDialog
  bool _showWinPresenter = false;
  bool _showGambleScreen = false;
  String _currentWinTier = '';
  double _currentWinAmount = 0.0;
  double _pendingWinAmount = 0.0; // Win waiting to be collected or gambled
  int? _gambleCardRevealed; // 0-3 for cards, null if not revealed

  // 🔴 DEBUG: On-screen messages (visible without console access)
  String _debugMessage = 'Waiting for spin...';
  int _processResultCallCount = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // BIG WIN PROTECTION — Industry Standard Skip Delay
  // ═══════════════════════════════════════════════════════════════════════════

  /// Timer for Big Win protection countdown
  Timer? _bigWinProtectionTimer;

  /// Remaining seconds of Big Win protection (0 = can skip immediately)
  double _bigWinProtectionRemaining = 0.0;

  /// Two-phase skip: first skip → play BIG_WIN_END, second skip → stop everything
  bool _isPlayingBigWinEnd = false;

  /// Timestamp when win presentation started (for protection tracking)
  int _winPresentationStartMs = 0;
  bool? _gambleWon; // Result of gamble

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC STATE — PSP-P0 Audio-Visual Synchronization
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tracks which reels have visually stopped (for staggered audio triggering)
  late List<bool> _reelsStopped;

  /// Timers for scheduled reel stops (canceled on dispose)
  final List<Timer> _reelStopTimers = [];

  // (Legacy coin values removed — using modern Total Bet system)

  // Listen to FeatureComposerProvider for isConfigured changes
  late final FeatureComposerProvider _composer;

  @override
  void initState() {
    super.initState();
    _showSplashScreen = widget.showSplash;
    _reelsStopped = List.filled(widget.reels, true); // Start as stopped
    _composer = GetIt.instance<FeatureComposerProvider>();
    _composer.addListener(_onComposerChanged);
    _initAnimations();
    _loadSettings(); // Load persisted settings
    // NOTE: Game config now loaded via Dashboard → Rules tab

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _onComposerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PremiumSlotPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Splash toggled from parent
    if (!oldWidget.showSplash && widget.showSplash) {
      setState(() => _showSplashScreen = true);
    }

    // Grid dimensions changed — reset reel state arrays
    if (oldWidget.reels != widget.reels || oldWidget.rows != widget.rows) {
      setState(() {
        _reelsStopped = List.filled(widget.reels, true);
        // Force re-render with new dimensions
      });
    }
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _isTurbo = prefs.getBool(_prefKeyTurbo) ?? false;
      _isMusicOn = prefs.getBool(_prefKeyMusic) ?? true;
      _isSfxOn = prefs.getBool(_prefKeySfx) ?? true;
      _masterVolume = prefs.getDouble(_prefKeyVolume) ?? 0.8;
      _graphicsQuality = prefs.getInt(_prefKeyQuality) ?? 2;
      _animationsEnabled = prefs.getBool(_prefKeyAnimations) ?? true;

      // P6: Load device simulation and theme
      final deviceIndex = prefs.getInt(_prefKeyDeviceSimulation) ?? 0;
      _deviceSimulation = DeviceSimulation.values[deviceIndex.clamp(0, DeviceSimulation.values.length - 1)];
      final themeIndex = prefs.getInt(_prefKeyTheme) ?? 0;
      _themeA = SlotThemePreset.values[themeIndex.clamp(0, SlotThemePreset.values.length - 1)];
    });

    // Apply loaded settings to FFI — bus 1=music, bus 2=sfx
    NativeFFI.instance.setBusMute(1, !_isMusicOn);
    NativeFFI.instance.setBusMute(2, !_isSfxOn);
    NativeFFI.instance.setMasterVolume(_masterVolume);
  }

  /// Save all settings to SharedPreferences
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyTurbo, _isTurbo);
    await prefs.setBool(_prefKeyMusic, _isMusicOn);
    await prefs.setBool(_prefKeySfx, _isSfxOn);
    await prefs.setDouble(_prefKeyVolume, _masterVolume);
    await prefs.setInt(_prefKeyQuality, _graphicsQuality);
    await prefs.setBool(_prefKeyAnimations, _animationsEnabled);

    // P6: Save device simulation and theme
    await prefs.setInt(_prefKeyDeviceSimulation, _deviceSimulation.index);
    await prefs.setInt(_prefKeyTheme, _themeA.index);
  }

  // NOTE: Game config loading moved to ProjectDashboardDialog._buildRulesTab()
  // Uses SlotLabProjectProvider.importedGdd for GDD-based rules

  void _initAnimations() {
    _jackpotTickController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
    _jackpotTickController.addListener(_tickJackpots);
  }

  void _tickJackpots() {
    if (!mounted) return;
    // Jackpots grow based on bet contribution during active play
    // Uses proper distribution percentages
    if (_progressiveContribution > 0) {
      setState(() {
        // Distribute contribution across tiers based on share percentages
        // Divided by 100 for smooth per-tick animation (100ms tick rate)
        final tickContrib = _progressiveContribution / 100;
        _miniJackpot += tickContrib * _miniContribShare;
        _minorJackpot += tickContrib * _minorContribShare;
        _majorJackpot += tickContrib * _majorContribShare;
        _grandJackpot += tickContrib * _grandContribShare;
      });
    }
  }

  /// Award jackpot based on tier (called from _processResult)
  void _awardJackpot(String tier) {
    double jackpotAmount = 0;
    setState(() {
      switch (tier) {
        case 'MINI':
          jackpotAmount = _miniJackpot;
          _miniJackpot = _miniJackpotSeed; // Reset to seed
        case 'MINOR':
          jackpotAmount = _minorJackpot;
          _minorJackpot = _minorJackpotSeed;
        case 'MAJOR':
          jackpotAmount = _majorJackpot;
          _majorJackpot = _majorJackpotSeed;
        case 'GRAND':
          jackpotAmount = _grandJackpot;
          _grandJackpot = _grandJackpotSeed;
      }
      _balance += jackpotAmount;
      _totalWin += jackpotAmount;
      _currentWinAmount = jackpotAmount;
      _currentWinTier = tier;
      _showWinPresenter = true;
    });
    context.read<SlotLabProvider>().setWinPresentationActive(true); // Sync with provider for SKIP detection

    // Track win in provider (for Dashboard Stats tab)
    _projectProvider?.recordWin(jackpotAmount, 'JACKPOT $tier');
  }

  @override
  void dispose() {
    // Stop ALL audio before disposing — prevents FS music bleeding into base game
    final reg = EventRegistry.instance;
    reg.stopAllSpinLoops();
    reg.stopAllMusicVoices(fadeMs: 100);
    reg.stopEvent('COIN_SHOWER_START');
    reg.stopEvent('ROLLUP');
    reg.stopEvent('WIN_COLLECT');
    reg.stopEvent('WIN_PRESENT');
    reg.stopEvent('BIG_WIN_START');
    reg.stopEvent('BIG_WIN_END');
    AudioPlaybackService.instance.stopAll();

    _composer.removeListener(_onComposerChanged);
    _jackpotTickController.dispose();
    _focusNode.dispose();
    // Cancel any pending Visual-Sync timers
    for (final timer in _reelStopTimers) {
      timer.cancel();
    }
    _reelStopTimers.clear();

    // P6: Cleanup debug timer
    _debugStatsTimer?.cancel();

    // Big Win protection timer cleanup
    _bigWinProtectionTimer?.cancel();

    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BIG WIN PROTECTION HANDLERS — Industry Standard Skip Delay
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start Big Win protection countdown based on win tier.
  /// Called when win presentation starts for Big Wins (20x+).
  void _startBigWinProtection(String tier) {
    final protectionDuration = BigWinProtection.forTier(tier);
    if (protectionDuration <= 0) {
      // No protection for regular wins
      _bigWinProtectionRemaining = 0.0;
      return;
    }

    _winPresentationStartMs = DateTime.now().millisecondsSinceEpoch;
    _bigWinProtectionRemaining = protectionDuration;

    // Start countdown timer (updates every 100ms for smooth countdown)
    _bigWinProtectionTimer?.cancel();
    _bigWinProtectionTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final elapsed = (DateTime.now().millisecondsSinceEpoch - _winPresentationStartMs) / 1000.0;
        final remaining = protectionDuration - elapsed;

        if (remaining <= 0) {
          timer.cancel();
          setState(() => _bigWinProtectionRemaining = 0.0);
        } else {
          setState(() => _bigWinProtectionRemaining = remaining);
        }
      },
    );
  }

  /// Stop Big Win protection countdown (called on collect or skip).
  void _stopBigWinProtection() {
    _bigWinProtectionTimer?.cancel();
    _bigWinProtectionTimer = null;
    _bigWinProtectionRemaining = 0.0;
  }

  /// Handle SKIP button press during win presentation.
  ///
  /// TWO-PHASE SKIP for Big Wins:
  /// - Phase 1 (first skip): Stop celebration, trigger BIG_WIN_END event (plays fully)
  /// - Phase 2 (second skip): Stop BIG_WIN_END, collect immediately
  ///
  /// Regular wins skip in one phase (no BIG_WIN_END).
  void _handleSkipWinPresentation() {
    // Don't allow skip if protection is still active
    if (_bigWinProtectionRemaining > 0) {
      return;
    }

    final provider = context.read<SlotLabProvider>();
    final eventRegistry = EventRegistry.instance;

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 2: BIG_WIN_END is already playing → stop it and collect
    // ═══════════════════════════════════════════════════════════════════════
    if (_isPlayingBigWinEnd) {
      _isPlayingBigWinEnd = false;

      // Stop BIG_WIN_END audio only — NOT base game music
      eventRegistry.stopEvent('BIG_WIN_END');
      eventRegistry.stopEvent('BIG_WIN_START');
      eventRegistry.stopEvent('MUSIC_BIG_WIN');

      // Trigger collect and restore base game
      eventRegistry.triggerStage('WIN_COLLECT');

      // Re-trigger base game music if it was playing before win
      _restoreBaseGameMusic(eventRegistry);

      // Collect win IMMEDIATELY
      _stopBigWinProtection();
      setState(() {
        _balance += _pendingWinAmount;
        _pendingWinAmount = 0.0;
        _showWinPresenter = false;
        _showGambleScreen = false;
        _currentWinTier = '';
      });
      provider.setWinPresentationActive(false);
      return;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 1: First skip — stop celebration, play BIG_WIN_END
    // ═══════════════════════════════════════════════════════════════════════

    // Stop ALL stage playback timers immediately
    if (provider.isPlayingStages) {
      provider.stopStagePlayback();
    }

    // Kill any lingering anticipation audio
    _stopAnticipationAudio();

    // Stop win-specific music (NOT base game music)
    _stopWinMusic(eventRegistry);

    // Stop all win-related sfx events
    eventRegistry.stopEvent('COIN_SHOWER_START');
    eventRegistry.stopEvent('BIG_WIN_START');
    eventRegistry.stopEvent('ROLLUP');
    eventRegistry.stopEvent('ROLLUP_TICK');
    eventRegistry.stopEvent('SYMBOL_WIN');
    eventRegistry.stopEvent('WIN_LINE_SHOW');
    eventRegistry.stopEvent('WIN_PRESENT');

    // Stop any tier-specific audio
    for (int i = 1; i <= 8; i++) {
      eventRegistry.stopEvent('WIN_PRESENT_$i');
      eventRegistry.stopEvent('BIG_WIN_TIER_$i');
    }

    // Trigger END stages
    eventRegistry.triggerStage('ROLLUP_END');

    if (_isBigWinTier(_currentWinTier)) {
      // Big Win ONLY: trigger BIG_WIN_END and enter Phase 2 (wait for second skip)
      eventRegistry.triggerStage('BIG_WIN_END');
      GetIt.instance<SlotLabCoordinator>().audioProvider.musicLayerController.resetToBaseLayer();
      eventRegistry.triggerStage('WIN_PRESENT_END');
      _stopBigWinProtection();
      setState(() {
        _isPlayingBigWinEnd = true;
        // Show win amount but keep presenter visible while BIG_WIN_END plays
        _balance += _pendingWinAmount;
        _pendingWinAmount = 0.0;
      });
      // WIN presentation stays active — user can skip again (Phase 2)
      return;
    }

    // Regular win (no big win tier): collect immediately
    eventRegistry.triggerStage('WIN_COLLECT');

    // Re-trigger base game music after regular win skip
    _restoreBaseGameMusic(eventRegistry);

    _stopBigWinProtection();
    setState(() {
      _balance += _pendingWinAmount;
      _pendingWinAmount = 0.0;
      _showWinPresenter = false;
      _showGambleScreen = false;
      _currentWinTier = '';
    });
    provider.setWinPresentationActive(false);
  }

  /// Stop only win-related music events, preserving base game music
  void _stopWinMusic(EventRegistry eventRegistry) {
    eventRegistry.stopEvent('BIG_WIN_START');
    eventRegistry.stopEvent('BIG_WIN_END');
    eventRegistry.stopEvent('BIG_WIN_TRIGGER');
    eventRegistry.stopEvent('MUSIC_BIG_WIN');
    eventRegistry.stopEvent('MUSIC_JACKPOT');
    eventRegistry.stopEvent('MUSIC_GAMBLE');
    for (int i = 1; i <= 8; i++) {
      eventRegistry.stopEvent('BIG_WIN_MUSIC_$i');
    }
  }

  /// Re-trigger base game music (GAME_START composite) if it was active
  void _restoreBaseGameMusic(EventRegistry eventRegistry) {
    if (eventRegistry.hasEventForStage('GAME_START')) {
      eventRegistry.triggerStage('GAME_START');
    } else if (eventRegistry.hasEventForStage('MUSIC_BASE_L1')) {
      eventRegistry.triggerStage('MUSIC_BASE_L1');
    }
  }

  // === HANDLERS ===

  /// Toggle music bus mute state (bus ID 1 = music)
  void _toggleMusic() {
    setState(() => _isMusicOn = !_isMusicOn);
    // Mute/unmute music bus via FFI — bus 1 = music
    NativeFFI.instance.setBusMute(1, !_isMusicOn);
    _saveSettings();
  }

  /// Toggle SFX bus mute state (bus ID 2 = sfx)
  void _toggleSfx() {
    setState(() => _isSfxOn = !_isSfxOn);
    // Mute/unmute SFX bus via FFI — bus 2 = sfx
    NativeFFI.instance.setBusMute(2, !_isSfxOn);
    _saveSettings();
  }

  /// Reset entire session to initial state (R key or Reset button)
  void _resetSession() {
    // ═══════════════════════════════════════════════════════════════════════════
    // ULTIMATIVNI RESET — Sve na početak kao da je igra tek pokrenuta
    // ═══════════════════════════════════════════════════════════════════════════

    final reg = EventRegistry.instance;

    // 1. STOP SVE AUDIO (spin loops, music, win effects)
    reg.stopAllSpinLoops();
    reg.stopAllMusicVoices(fadeMs: 100);

    // Stop specific win/celebration events
    reg.stopEvent('COIN_SHOWER_START');
    reg.stopEvent('ROLLUP');
    reg.stopEvent('WIN_COLLECT');
    reg.stopEvent('WIN_PRESENT');

    // 2. STOP Big Win protection timer
    _stopBigWinProtection();

    // 3. Cancel all reel stop timers
    for (final timer in _reelStopTimers) {
      timer.cancel();
    }
    _reelStopTimers.clear();

    // 4. Cancel debug stats timer
    _debugStatsTimer?.cancel();

    // 6. Reset animation controller
    _jackpotTickController.reset();

    setState(() {
      // ═══════════════════════════════════════════════════════════════════════════
      // SESSION STATS — Back to fresh start
      // ═══════════════════════════════════════════════════════════════════════════
      _balance = 1000.0;
      _sessionTotalBet = 0.0;
      _totalWin = 0.0;
      _totalSpins = 0;
      _wins = 0;
      _losses = 0;

      // ═══════════════════════════════════════════════════════════════════════════
      // JACKPOTS — Reset to seed + initial bonus
      // ═══════════════════════════════════════════════════════════════════════════
      _miniJackpot = _miniJackpotSeed + 25.50;
      _minorJackpot = _minorJackpotSeed + 250.00;
      _majorJackpot = _majorJackpotSeed + 2500.00;
      _grandJackpot = _grandJackpotSeed + 25000.00;
      _progressiveContribution = 0.0;

      // ═══════════════════════════════════════════════════════════════════════════
      // BET — Back to default
      // ═══════════════════════════════════════════════════════════════════════════
      _totalBet = 2.00;

      // ═══════════════════════════════════════════════════════════════════════════
      // FEATURE STATE — All features cleared
      // ═══════════════════════════════════════════════════════════════════════════
      _freeSpins = 0;
      _freeSpinsRemaining = 0;
      _bonusMeter = 0.0;
      _featureProgress = 0.0;
      _multiplier = 1;
      _cascadeCount = 0;
      _specialSymbolCount = 0;

      // ═══════════════════════════════════════════════════════════════════════════
      // AUTO-SPIN — Disabled
      // ═══════════════════════════════════════════════════════════════════════════
      _isAutoSpin = false;
      _autoSpinCount = 0;
      _autoSpinRemaining = 0;

      // ═══════════════════════════════════════════════════════════════════════════
      // WIN STATE — Cleared
      // ═══════════════════════════════════════════════════════════════════════════
      _currentWinTier = '';
      _currentWinAmount = 0.0;
      _pendingWinAmount = 0.0;
      _bigWinProtectionRemaining = 0.0;
      _isPlayingBigWinEnd = false;
      _winPresentationStartMs = 0;
      _gambleWon = null;
      _gambleCardRevealed = null;

      // ═══════════════════════════════════════════════════════════════════════════
      // UI STATE — All panels closed, ready for play
      // ═══════════════════════════════════════════════════════════════════════════
      _showWinPresenter = false;
      _showGambleScreen = false;
      _showMenuPanel = false;
      _showSettingsPanel = false;

      // ═══════════════════════════════════════════════════════════════════════════
      // VISUAL-SYNC STATE — All reels stopped
      // ═══════════════════════════════════════════════════════════════════════════
      _reelsStopped = List.filled(widget.reels, true);

      // ═══════════════════════════════════════════════════════════════════════════
      // DEBUG STATE — Clear message
      // ═══════════════════════════════════════════════════════════════════════════
      _debugMessage = 'Session reset. Waiting for spin...';
      _processResultCallCount = 0;
    });

  }

  /// Set master volume via FFI
  void _setMasterVolume(double volume) {
    setState(() => _masterVolume = volume);
    NativeFFI.instance.setMasterVolume(volume);
    _saveSettings();
  }

  /// Set graphics quality
  void _setGraphicsQuality(int quality) {
    setState(() => _graphicsQuality = quality);
    _saveSettings();
  }

  /// Toggle animations
  void _toggleAnimations() {
    setState(() => _animationsEnabled = !_animationsEnabled);
    _saveSettings();
  }

  /// Toggle turbo mode
  void _toggleTurbo() {
    setState(() => _isTurbo = !_isTurbo);
    _saveSettings();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P6: DEVICE SIMULATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set device simulation mode
  void _setDeviceSimulation(DeviceSimulation device) {
    setState(() => _deviceSimulation = device);
    _saveSettings();
  }

  /// Build device frame wrapper around content
  Widget _buildDeviceFrame(Widget child) {
    final size = _deviceSimulation.size;
    if (size == null) {
      // Desktop mode — no frame, full size
      return child;
    }

    switch (_deviceSimulation) {
      case DeviceSimulation.desktop:
        return child;
      case DeviceSimulation.tablet:
        return _buildTabletFrame(child, size);
      case DeviceSimulation.mobileLandscape:
        return _buildPhoneFrame(child, size, isLandscape: true);
      case DeviceSimulation.mobilePortrait:
        return _buildPhoneFrame(child, size, isLandscape: false);
    }
  }

  /// Build phone frame with bezels and notch
  Widget _buildPhoneFrame(Widget child, Size size, {required bool isLandscape}) {
    final bezelH = 20.0;
    final bezelV = isLandscape ? 20.0 : 40.0;
    final notchHeight = isLandscape ? 0.0 : 30.0;

    return Center(
      child: Container(
        width: size.width + bezelH * 2,
        height: size.height + bezelV * 2 + notchHeight,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(isLandscape ? 24 : 40),
          border: Border.all(color: Colors.grey.shade800, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Notch (only in portrait)
            if (!isLandscape)
              Container(
                width: 120,
                height: notchHeight,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(15),
                    bottomRight: Radius.circular(15),
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 60,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            // Screen content
            ClipRRect(
              borderRadius: BorderRadius.circular(isLandscape ? 20 : 36),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: child,
                  ),
                ),
              ),
            ),
            // Home indicator
            if (!isLandscape)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(
                  width: 100,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build tablet frame with thinner bezels
  Widget _buildTabletFrame(Widget child, Size size) {
    const bezel = 16.0;

    return Center(
      child: Container(
        width: size.width + bezel * 2,
        height: size.height + bezel * 2,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade800, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 3,
            ),
          ],
        ),
        padding: const EdgeInsets.all(bezel),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P6: THEME SYSTEM METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set primary theme
  void _setThemeA(SlotThemePreset theme) {
    setState(() => _themeA = theme);
    _saveSettings();
  }

  /// Set comparison theme (null to disable comparison)
  void _setThemeB(SlotThemePreset? theme) {
    setState(() {
      _themeB = theme;
      _showThemeComparison = theme != null;
    });
  }

  /// Toggle theme comparison mode
  void _toggleThemeComparison() {
    setState(() {
      if (_showThemeComparison) {
        _showThemeComparison = false;
        _themeB = null;
      } else {
        // Default to neon for B if not set
        _themeB ??= SlotThemePreset.neon;
        _showThemeComparison = true;
      }
    });
  }

  /// Swap themes A and B
  void _swapThemes() {
    if (_themeB == null) return;
    setState(() {
      final temp = _themeA;
      _themeA = _themeB!;
      _themeB = temp;
    });
    _saveSettings();
  }

  /// Get current theme data
  SlotThemeData get _currentThemeData => _themeA.data;

  // ═══════════════════════════════════════════════════════════════════════════
  // P6: Recording removed from SlotLab

  // ═══════════════════════════════════════════════════════════════════════════
  // P6: DEBUG TOOLBAR METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Toggle debug toolbar visibility
  void _toggleDebugToolbar() {
    setState(() {
      _showDebugToolbar = !_showDebugToolbar;
      if (_showDebugToolbar) {
        _startDebugStatsTimer();
      } else {
        _debugStatsTimer?.cancel();
        _debugStatsTimer = null;
      }
    });
  }

  /// Start timer to update debug stats
  void _startDebugStatsTimer() {
    _debugStatsTimer?.cancel();
    _debugStatsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        // Get real stats from FFI when available
        try {
          final stats = NativeFFI.instance.getVoicePoolStats();
          _activeVoices = stats.activeCount;
        } catch (_) {
          _activeVoices = 0;
        }
        // FPS would come from SchedulerBinding in production
        _currentFps = 60; // Placeholder
        // Memory from platform channel in production
        _memoryUsageMb = 128; // Placeholder
      });
    });
  }

  /// Force a specific outcome (debug)
  ///
  /// Force outcome mapping (P5 Win Tier System with EXACT target multipliers):
  /// 1=Lose, 2=WIN_1, 3=WIN_2, 4=WIN_3, 5=WIN_4, 6=WIN_5, 7=FS, 8=Cascade, 9=BIG WIN, 0=Jackpot
  /// (WIN_6 REMOVED — WIN_5 is now default for >13x regular wins)
  ///
  /// Each WIN button now produces a DISTINCT tier using spinForcedWithMultiplier:
  /// - Uses mid-range multiplier values to ensure correct tier evaluation
  void _forceOutcome(int outcomeIndex) {
    final provider = context.read<SlotLabProvider>();

    // P5: Use ForcedOutcomeConfig as single source of truth
    // Find config by keyboard shortcut
    final key = outcomeIndex.toString();
    final config = ForcedOutcomeConfig.outcomes.cast<ForcedOutcomeConfig?>().firstWhere(
      (c) => c?.keyboardShortcut == key,
      orElse: () => null,
    );

    if (config == null) {
      return;
    }


    // Use expectedWinMultiplier if available
    if (config.expectedWinMultiplier != null && config.expectedWinMultiplier! > 0) {
      provider.spinForcedWithMultiplier(config.outcome, config.expectedWinMultiplier!);
    } else {
      provider.spinForced(config.outcome);
    }
  }

  void _handleSpin(SlotLabProvider provider) {
    if (!provider.initialized) {
      return;
    }
    if (!GetIt.instance<FeatureComposerProvider>().isConfigured) {
      return;
    }
    if (_balance < _totalBetAmount) {
      return;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // V13: WIN PRESENTATION SKIP — Fade out first, then spin
    // If win presentation is active, request skip and wait for fade-out to complete
    // ═══════════════════════════════════════════════════════════════════════════
    if (provider.isWinPresentationActive) {
      provider.requestSkipPresentation(() {
        _executeSpinAfterSkip(provider);
      });
      return;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FIX (2026-02-14): If previous stage playback is still running (timer-based
    // stages like WIN_PRESENT, ROLLUP, SPIN_END), stop it before starting new spin.
    // Previously this blocked with "Already playing stages" which prevented the
    // user from starting a new spin after reels had visually stopped.
    // ═══════════════════════════════════════════════════════════════════════════
    if (provider.isPlayingStages) {
      provider.stopStagePlayback();
    }

    // No presentation active — proceed immediately with spin
    _executeSpinAfterSkip(provider);
  }

  /// V13: Execute spin after skip fade-out is complete (or when no skip needed)
  /// This contains the actual spin logic extracted from _handleSpin
  void _executeSpinAfterSkip(SlotLabProvider provider) {
    setState(() {
      _balance -= _totalBetAmount;
      _sessionTotalBet += _totalBetAmount; // Session tracking for RTP calculation
      _totalSpins++;
      // Progressive contribution based on bet amount (1% of bet goes to jackpot pool)
      _progressiveContribution = _jackpotContributionRate * _totalBetAmount;
      // Add small amount to each jackpot per bet
      _miniJackpot += _totalBetAmount * 0.005;
      _minorJackpot += _totalBetAmount * 0.003;
      _majorJackpot += _totalBetAmount * 0.002;
      _grandJackpot += _totalBetAmount * 0.001;
      _showWinPresenter = false;
      _isPlayingBigWinEnd = false;
    });
    provider.setWinPresentationActive(false); // Sync with provider

    // ═══════════════════════════════════════════════════════════════════════
    // VISUAL-SYNC: Schedule reel stop callbacks IMMEDIATELY on spin start
    // Result will be stored when it arrives for win stage triggering
    // ═══════════════════════════════════════════════════════════════════════
    _scheduleVisualSyncCallbacks();

    setState(() {
      _debugMessage = 'Spin started, waiting for result...';
    });

    provider.spin().then((result) {
      if (result != null && mounted) {
        setState(() {
          _debugMessage = 'Got result! spinId=${result.spinId}, calling _processResult...';
        });
        // Diagnostics: stage triggers + onSpinComplete already handled by
        // SlotStageProvider._triggerStage() in real-time — no retroactive replay needed
        // Store result for win stage triggering (used by _onAllReelsStopped)
        _processResult(result);
      } else {
        setState(() {
          _debugMessage = 'ERROR: spin() returned NULL!';
        });
      }
    });
  }

  void _handleForcedSpin(SlotLabProvider provider, ForcedOutcome outcome) {
    if (!provider.initialized) return;
    if (!GetIt.instance<FeatureComposerProvider>().isConfigured) return;
    if (_balance < _totalBetAmount) return;

    // V13: Handle skip with fade-out for forced spin as well
    if (provider.isWinPresentationActive) {
      provider.requestSkipPresentation(() {
        _executeForcedSpinAfterSkip(provider, outcome);
      });
      return;
    }

    // FIX (2026-02-14): If previous stage playback is still running (timer-based
    // stages like WIN_PRESENT, ROLLUP, SPIN_END), stop it before starting new spin.
    if (provider.isPlayingStages) {
      provider.stopStagePlayback();
    }

    _executeForcedSpinAfterSkip(provider, outcome);
  }

  /// V13: Execute forced spin after skip fade-out is complete
  void _executeForcedSpinAfterSkip(SlotLabProvider provider, ForcedOutcome outcome) {
    setState(() {
      _balance -= _totalBetAmount;
      _sessionTotalBet += _totalBetAmount; // Session tracking for RTP calculation
      _totalSpins++;
      _showWinPresenter = false;
      _isPlayingBigWinEnd = false;
    });
    provider.setWinPresentationActive(false); // Sync with provider

    // ═══════════════════════════════════════════════════════════════════════
    // VISUAL-SYNC: Schedule reel stop callbacks IMMEDIATELY on spin start
    // ═══════════════════════════════════════════════════════════════════════
    _scheduleVisualSyncCallbacks();

    setState(() {
      _debugMessage = 'Forced spin started, waiting for result...';
    });

    provider.spinForced(outcome).then((result) {
      if (result != null && mounted) {
        setState(() {
          _debugMessage = 'Got forced result! Calling _processResult...';
        });
        // Store result for win stage triggering (used by _onAllReelsStopped)
        _processResult(result);
      } else {
        setState(() {
          _debugMessage = 'ERROR: spinForced() returned NULL!';
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC METHODS — PSP-P0 Audio-Visual Synchronization
  // ═══════════════════════════════════════════════════════════════════════════

  /// Schedule Visual-Sync callbacks for staggered reel stops
  /// Called at SPIN START — triggers REEL_STOP_0..4 at visual stop moments
  void _scheduleVisualSyncCallbacks() {
    // Cancel any existing timers
    for (final timer in _reelStopTimers) {
      timer.cancel();
    }
    _reelStopTimers.clear();

    // Reset reels stopped state
    setState(() {
      _reelsStopped = List.filled(widget.reels, false);
    });

    // ═══════════════════════════════════════════════════════════════════════
    // UI_SPIN_PRESS — DISABLED: Engine stages handle this via SlotLabProvider._playStages()
    // Keeping visual-sync here caused DUPLICATE TRIGGERS (audio played twice)
    // ═══════════════════════════════════════════════════════════════════════
    // eventRegistry.triggerStage('UI_SPIN_PRESS'); // REMOVED - causes double trigger

    // ═══════════════════════════════════════════════════════════════════════
    // Staggered reel stop timing — matches SlotPreviewWidget animation
    // Normal: 250ms per reel | Turbo: 100ms per reel
    // Reel animation duration: 1000ms + (index * 250ms)
    // Stagger start: index * 120ms
    // Total time = stagger + duration
    // ═══════════════════════════════════════════════════════════════════════
    final baseDelay = _isTurbo ? 100 : 250;
    final baseAnimDuration = _isTurbo ? 600 : 1000;
    final staggerDelay = _isTurbo ? 60 : 120;

    for (int i = 0; i < widget.reels; i++) {
      // Calculate when this reel visually stops
      // = staggerStart + animationDuration
      final stopTime = (staggerDelay * i) + baseAnimDuration + (baseDelay * i);

      final timer = Timer(Duration(milliseconds: stopTime), () {
        if (!mounted) return;

        setState(() {
          _reelsStopped[i] = true;
        });

        // ═══════════════════════════════════════════════════════════════════
        // REEL_STOP_i — DISABLED: SlotPreviewWidget (child) handles this!
        // SlotPreviewWidget uses animation callback (_onReelStopVisual) which triggers
        // REEL_STOP_$reelIndex at the EXACT moment the animation reaches bouncing phase.
        // Triggering here (Timer-based) DUPLICATES the audio — DO NOT ENABLE!
        // See: slot_preview_widget.dart:929 — eventRegistry.triggerStage('REEL_STOP_$reelIndex')
        // ═══════════════════════════════════════════════════════════════════
        // final eventRegistry = EventRegistry.instance;
        // eventRegistry.triggerStage('REEL_STOP_$i');  // CAUSES DUPLICATE AUDIO!

        // ANTICIPATION — DISABLED (engine handles via SlotLabProvider._playStages())
        // Kept for visual state tracking only, method is now a no-op
        if (i == widget.reels - 2) {
          _checkAnticipation();
        }

        // REVEAL/WIN — DISABLED (engine handles via SlotLabProvider._playStages())
        // Kept for visual state tracking only, method is now a no-op
        if (i == widget.reels - 1) {
          _onAllReelsStopped();
        }
      });

      _reelStopTimers.add(timer);
    }
  }

  /// Check for anticipation (2+ scatters visible before last reel)
  /// Called when second-to-last reel stops
  void _checkAnticipation() {
    // ═══════════════════════════════════════════════════════════════════════
    // ANTICIPATION_TENSION — DISABLED: Engine generates ANTICIPATION_TENSION stages
    // with correct timestamps. Visual-sync timing causes mismatch/duplicates.
    // See: crates/rf-slot-lab/src/spin.rs — Stage::AnticipationOn
  }

  /// Called when ALL reels have visually stopped
  /// NOTE: WIN stages are now handled by engine via SlotLabProvider._playStages()
  void _onAllReelsStopped() {
    // CRITICAL: Notify provider that reels stopped visually
    // This hides STOP button and enables SKIP button during win presentation
    final provider = context.read<SlotLabProvider>();
    provider.onAllReelsVisualStop();

  }

  // ═══════════════════════════════════════════════════════════════════════════
  // END VISUAL-SYNC METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _processResult(SlotLabSpinResult result) {
    // DEBUG: ENTRY LOG — check if method is even being called
    _processResultCallCount++;
    setState(() {
      _debugMessage = 'CALLED #$_processResultCallCount | isWin=${result.isWin} | ratio=${result.winRatio.toStringAsFixed(2)}';
    });

    // CRITICAL: Use winRatio (multiplier) from engine, not totalWin (absolute amount)
    // Engine calculates: total_win = engine_bet * target_multiplier
    // But engine_bet may differ from UI bet (_totalBetAmount), so:
    // Correct win = winRatio * _totalBetAmount
    final winAmount = result.winRatio * _totalBetAmount;

    // Reset progressive contribution after spin
    _progressiveContribution = 0.0;

    setState(() {
      _totalWin += winAmount;
      // DON'T add to balance immediately - store as pending for Collect/Gamble
      _pendingWinAmount = winAmount;

      if (result.isWin) {
        _wins++;
        // Use engine's win tier classification when available, fallback to winRatio-based tier
        final engineTier = _winTierFromEngine(result.bigWinTier);
        final ratioTier = _getWinTierFromRatio(result.winRatio);
        _currentWinTier = engineTier ?? ratioTier;
        _currentWinAmount = winAmount;

        // 🔴 DEBUG: On-screen message for WIN path
        _debugMessage = 'WIN! engineTier=$engineTier | ratioTier=$ratioTier | FINAL=$_currentWinTier';

        // DEBUG: Log win tier for plaque display

        // Jackpot chance based on win RATIO from ENGINE (not absolute amount)
        // Uses probability bands tied to multiplier - engine determines the win,
        // we just apply jackpot chance based on that ratio
        final jackpotRoll = (result.winRatio * 1000).toInt() % 100; // Deterministic from engine result
        if (result.winRatio >= 100) {
          // ULTRA win (100x+) - chance for GRAND jackpot
          if (jackpotRoll < 1) {
            _awardJackpot('GRAND');
            return;
          } else if (jackpotRoll < 6) {
            _awardJackpot('MAJOR');
            return;
          }
        } else if (result.winRatio >= 50) {
          // EPIC win (50x-100x) - chance for MAJOR/MINOR
          if (jackpotRoll < 2) {
            _awardJackpot('MAJOR');
            return;
          } else if (jackpotRoll < 10) {
            _awardJackpot('MINOR');
            return;
          }
        } else if (result.winRatio >= 25) {
          // MEGA win (25x-50x) - chance for MINOR/MINI
          if (jackpotRoll < 5) {
            _awardJackpot('MINOR');
            return;
          } else if (jackpotRoll < 20) {
            _awardJackpot('MINI');
            return;
          }
        } else if (result.winRatio >= 10) {
          // BIG win (10x-25x) - small chance for MINI
          if (jackpotRoll < 10) {
            _awardJackpot('MINI');
            return;
          }
        }

        // Show win presenter for ALL wins (Big and Regular)
        // Big Win (20x+): Shows tier escalation (BIG WIN!, MEGA WIN!, etc.)
        // Regular Win (< 20x): Shows simple TOTAL WIN panel
        _showWinPresenter = true;
        context.read<SlotLabProvider>().setWinPresentationActive(true); // Sync with provider for SKIP detection

        // START BIG WIN when big win detected (20x+)
        // Composite event handles everything: FadeVoice base music → StopVoice → Play big win
        if (_isBigWinTier(_currentWinTier)) {
          eventRegistry.triggerStage('BIG_WIN_TRIGGER');
          eventRegistry.triggerStage('BIG_WIN_START');
        }

        // Start Big Win protection countdown for big wins
        // Regular wins have 0s protection (immediate skip available)
        _startBigWinProtection(_currentWinTier);

        // Track win in provider (for Dashboard Stats tab)
        _projectProvider?.recordWin(
          winAmount,
          _currentWinTier.isNotEmpty ? _currentWinTier : 'WIN',
        );
      } else {
        // 🔴 DEBUG: On-screen message for NO WIN path
        _debugMessage = 'NO WIN — isWin=false, ratio=${result.winRatio}';
        _losses++;
        _currentWinTier = '';
        _pendingWinAmount = 0.0; // No win to collect
      }
    });

    // Handle auto-spin
    if (_isAutoSpin && _autoSpinRemaining > 0) {
      _autoSpinRemaining--;
      if (_autoSpinRemaining > 0) {
        Future.delayed(
          Duration(milliseconds: _isTurbo ? 500 : 1500),
          () {
            if (mounted && _isAutoSpin) {
              _handleSpin(context.read<SlotLabProvider>());
            }
          },
        );
      } else {
        setState(() => _isAutoSpin = false);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P5 WIN TIER SYSTEM — Dynamic, configurable win tiers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get project provider (widget parameter or context)
  SlotLabProjectProvider? get _projectProvider {
    if (widget.projectProvider != null) return widget.projectProvider;
    try {
      return context.read<SlotLabProjectProvider>();
    } catch (_) {
      return null;
    }
  }

  /// P5: Get complete win tier result from configurable system
  WinTierResult? _getP5WinTierResult(double totalWin, double bet) {
    if (totalWin <= 0 || bet <= 0) return null;

    final projectProvider = _projectProvider;
    if (projectProvider != null) {
      return projectProvider.getWinTierForAmount(totalWin, bet);
    }

    // Legacy fallback
    return _legacyGetWinTierResult(totalWin, bet);
  }

  /// Fallback when projectProvider is not available.
  /// Uses SlotWinConfiguration.defaultConfig() to avoid any hardcoded values.
  WinTierResult? _legacyGetWinTierResult(double totalWin, double bet) {
    final defaultConfig = SlotWinConfiguration.defaultConfig();
    return defaultConfig.getWinTierResult(totalWin, bet);
  }



  /// P5: Get win tier string from winRatio (multiplier) directly
  /// This is the CORRECT method - uses ratio without bet calculation errors
  /// Returns 'BIG_WIN_TIER_1' through 'BIG_WIN_TIER_5' for big wins, or WIN_X for regular
  String _getWinTierFromRatio(double winRatio) {
    // P5 data-driven: use project provider's config or default config
    // Zero hardcoded thresholds — all values come from SlotWinConfiguration
    final bet = _totalBet;
    final winAmount = winRatio * bet;
    final provider = _projectProvider;
    final WinTierResult? result;

    if (provider != null) {
      result = provider.getWinTierForAmount(winAmount, bet);
    } else {
      result = SlotWinConfiguration.defaultConfig().getWinTierResult(winAmount, bet);
    }

    if (result == null) return 'WIN_LOW';
    return result.primaryStageName;
  }

  /// Check if tier is a BIG WIN tier (20x+ - BIG_WIN_TIER_1 through BIG_WIN_TIER_5)
  /// Returns false for regular wins (WIN_1 through WIN_5, WIN_EQUAL, WIN_LOW)
  bool _isBigWinTier(String tier) {
    return tier.startsWith('BIG_WIN_TIER_');
  }

  /// P5: Get display label from configurable tier system
  /// Returns user-configured label instead of hardcoded "BIG WIN!" etc.
  String _getP5WinTierDisplayLabel(double totalWin, double bet) {
    final tierResult = _getP5WinTierResult(totalWin, bet);
    if (tierResult == null) return '';

    if (tierResult.isBigWin) {
      return tierResult.bigWinTier?.displayLabel ?? 'BIG WIN TIER 1';
    }

    return '';
  }

  /// Convert engine win tier to UI tier string
  /// Returns null for regular wins (so fallback to ratio-based tier can be used)
  /// Only returns tier string for BIG WINS (20x+)
  String? _winTierFromEngine(SlotLabWinTier? tier) {
    if (tier == null) return null;
    switch (tier) {
      case SlotLabWinTier.ultraWin:
        return 'BIG_WIN_TIER_5';
      case SlotLabWinTier.epicWin:
        return 'BIG_WIN_TIER_4';
      case SlotLabWinTier.megaWin:
        return 'BIG_WIN_TIER_3';
      case SlotLabWinTier.bigWin:
        return 'BIG_WIN_TIER_1';
      case SlotLabWinTier.win:
        // Regular win - return null so _getWinTierFromRatio() can determine exact tier
        return null;
      case SlotLabWinTier.none:
        return null;
    }
  }

  /// Collect pending win - add to balance and close presenter
  void _collectWin() {
    // Stop Big Win protection timer
    _stopBigWinProtection();

    // Stop all music on collect and restore base game music
    if (_isBigWinTier(_currentWinTier)) {
      eventRegistry.stopAllMusicVoices(fadeMs: 300);
      // Restore ALL base music layers
      for (final layer in const ['MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_BASE_L3', 'MUSIC_BASE_L4', 'MUSIC_BASE_L5']) {
        if (eventRegistry.hasEventForStage(layer)) {
          eventRegistry.triggerStage(layer);
        }
      }
    }

    setState(() {
      _balance += _pendingWinAmount;
      _pendingWinAmount = 0.0;
      _showWinPresenter = false;
      _showGambleScreen = false;
      _isPlayingBigWinEnd = false;
    });
    context.read<SlotLabProvider>().setWinPresentationActive(false); // Sync with provider
  }

  /// Start gamble game - show gamble screen
  void _startGamble() {
    setState(() {
      _showWinPresenter = false;
      _showGambleScreen = true;
      _gambleCardRevealed = null;
      _gambleWon = null;
      _isPlayingBigWinEnd = false;
    });
    context.read<SlotLabProvider>().setWinPresentationActive(false); // Sync with provider (gamble is separate flow)
  }

  /// Make gamble choice (0=Red, 1=Black)
  void _makeGambleChoice(int choice) {
    // 50/50 chance - 0,1 = Red, 2,3 = Black
    final result = _random.nextInt(4);
    final isRed = result < 2;
    final playerChoseRed = choice == 0;
    final won = isRed == playerChoseRed;

    setState(() {
      _gambleCardRevealed = result;
      _gambleWon = won;
    });

    // After reveal, process result
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        if (won) {
          // Double the win
          _pendingWinAmount *= 2;
          _currentWinAmount = _pendingWinAmount;
          // Reset for another gamble
          _gambleCardRevealed = null;
          _gambleWon = null;
        } else {
          // Lose everything
          _pendingWinAmount = 0.0;
          _showGambleScreen = false;
        }
      });
    });
  }

  void _handleStop() {
    // Stop all reels immediately by stopping stage playback
    // This triggers SlotPreviewWidget._onProviderUpdate() which calls _finalizeSpin()
    // which in turn calls _reelAnimController.stopImmediately()
    final provider = context.read<SlotLabProvider>();
    if (provider.isPlayingStages) {
      provider.stopStagePlayback();
    }

    // Kill anticipation audio immediately (don't wait for widget listener cycle)
    _stopAnticipationAudio();
  }

  /// Stop all anticipation audio events immediately.
  /// Called from STOP button to prevent lingering anticipation sounds.
  void _stopAnticipationAudio() {
    final er = EventRegistry.instance;
    // Stop per-reel tension stages (all reels × all levels)
    for (int reel = 0; reel < 7; reel++) {
      er.stopEvent('ANTICIPATION_TENSION_R$reel');
      for (int l = 1; l <= 4; l++) {
        er.stopEvent('ANTICIPATION_TENSION_R${reel}_L$l');
      }
    }
    er.stopEvent('ANTICIPATION_TENSION');
    er.stopEvent('ANTICIPATION_MISS');
    // Brute-force: stop ANY playing instance with ANTICIPATION in its event ID or stage
    er.stopEventsByPrefix('ANTICIPATION');
  }

  void _handleMaxBet() {
    setState(() {
      _totalBet = _maxBet;
    });
  }

  void _handleAutoSpinToggle() {
    if (_isAutoSpin) {
      setState(() {
        _isAutoSpin = false;
        _autoSpinRemaining = 0;
      });
    } else {
      setState(() {
        _isAutoSpin = true;
        _autoSpinCount = 50;
        _autoSpinRemaining = 50;
      });
      _handleSpin(context.read<SlotLabProvider>());
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context != null) {
      final editable = primaryFocus.context!.findAncestorWidgetOfExactType<EditableText>();
      if (editable != null) return KeyEventResult.ignored;
    }

    final provider = context.read<SlotLabProvider>();

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        if (_showMenuPanel) {
          setState(() => _showMenuPanel = false);
        } else if (_showSettingsPanel) {
          setState(() => _showSettingsPanel = false);
        } else if (_showWinPresenter) {
          setState(() {
            _showWinPresenter = false;
            _isPlayingBigWinEnd = false;
          });
          context.read<SlotLabProvider>().setWinPresentationActive(false); // Sync with provider
        } else {
          widget.onExit();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.space:
        // ═══════════════════════════════════════════════════════════════════════
        // UNCONFIGURED GUARD — No keyboard interaction without a built slot machine
        // ═══════════════════════════════════════════════════════════════════════
        if (!GetIt.instance<FeatureComposerProvider>().isConfigured) {
          return KeyEventResult.handled; // Swallow the event
        }

        // ═══════════════════════════════════════════════════════════════════════
        // EMBEDDED MODE CHECK — Skip SPACE handling when NOT in fullscreen
        // Let slot_lab_screen global handler handle SPACE in embedded mode
        // This prevents double-handling where both handlers process same event
        // ═══════════════════════════════════════════════════════════════════════
        if (!widget.isFullscreen) {
          return KeyEventResult.ignored;
        }

        // ═══════════════════════════════════════════════════════════════════════
        // DEBOUNCE CHECK — Prevents double-trigger from rapid key presses
        // ═══════════════════════════════════════════════════════════════════════
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastSpaceKeyTime < _spaceKeyDebounceMs) {
          return KeyEventResult.handled;
        }
        _lastSpaceKeyTime = now;

        // ═══════════════════════════════════════════════════════════════════════
        // SPACE KEY LOGIC (INDUSTRY STANDARD):
        // - isReelsSpinning = true ONLY while reels are visually spinning
        // - isPlayingStages = true during BOTH spin AND win presentation
        // - isWinPresentationActive = true ONLY during win presentation
        //
        // Correct behavior (IGT, NetEnt, Pragmatic Play standard):
        // - During reel spin → STOP (stop reels immediately)
        // - During win presentation → SKIP (skip to END event, NO new spin)
        // - Idle → SPIN (start new spin)
        //
        // IMPORTANT: SKIP does NOT start a new spin! Only SPIN button starts spins.
        // SKIP jumps to END event of current phase (BIG_WIN_END, ROLLUP_END, etc.)
        // ═══════════════════════════════════════════════════════════════════════

        if (provider.isReelsSpinning) {
          // During reel spin → STOP (stop reels immediately)
          _handleStop();
        } else if (provider.isWinPresentationActive) {
          // During win presentation → SKIP to END event (NO new spin!)
          _handleSkipWinPresentation();
        } else {
          // Idle → SPIN (start new spin)
          _handleSpin(provider);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyM:
        _toggleMusic();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyS:
        // S = Open Dashboard (Stats tab) — stats panel moved to Dashboard
        ProjectDashboardDialog.show(context, initialTab: 5); // Stats tab index
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyT:
        // P6: T = Cycle themes (A→B→A), Shift+T = Turbo toggle
        if (HardwareKeyboard.instance.isShiftPressed) {
          _toggleTurbo();
        } else {
          // Cycle through themes
          final themes = SlotThemePreset.values;
          final currentIndex = themes.indexOf(_themeA);
          final nextIndex = (currentIndex + 1) % themes.length;
          _setThemeA(themes[nextIndex]);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyA:
        _handleAutoSpinToggle();
        return KeyEventResult.handled;

      // D = Debug/Forced Outcome panel toggle
      case LogicalKeyboardKey.keyD:
        _toggleDebugToolbar();
        return KeyEventResult.handled;

      // P6: R = Recording toggle, Shift+R = Reset session
      case LogicalKeyboardKey.keyR:
        if (HardwareKeyboard.instance.isShiftPressed) {
          _resetSession();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      // Forced outcomes (debug only)
      case LogicalKeyboardKey.digit1:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.lose);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit2:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.smallWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit3:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.bigWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit4:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.megaWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit5:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.epicWin);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit6:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.freeSpins);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.digit7:
        if (kDebugMode) _handleForcedSpin(provider, ForcedOutcome.jackpotGrand);
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;

      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ═══════════════════════════════════════════════════════════════════════════
    // SPLASH SCREEN — Loading screen before base game (industry standard)
    // ═══════════════════════════════════════════════════════════════════════════
    if (_showSplashScreen) {
      return _SlotSplashScreen(
        onContinue: () {
          setState(() => _showSplashScreen = false);
          widget.onSplashComplete?.call();
          // Trigger GAME_START → starts base game music via composite event
          // Composite has L1=vol1.0, L2/L3=vol0.0 (crossfade-ready)
          // Do NOT trigger individual MUSIC_BASE layers — they'd play at full volume
          final eventRegistry = EventRegistry.instance;
          if (eventRegistry.hasEventForStage('GAME_START')) {
            eventRegistry.triggerStage('GAME_START');
          }
        },
      );
    }

    final provider = context.watch<SlotLabProvider>();
    final projectProvider = context.watch<SlotLabProjectProvider>();

    // FIX: React to external skipRequested (e.g. from global SPACE handler in embedded mode)
    // The slot_preview_widget handles the fade-out via _executeSkipFadeOut(),
    // but premium_slot_preview needs to clean up its local state too.
    if (provider.skipRequested && _showWinPresenter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleSkipWinPresentation();
      });
    }

    // isReelsSpinning: True ONLY while reels are visually spinning — for STOP button
    final isReelsActuallySpinning = provider.isReelsSpinning;
    final isInitialized = provider.initialized;
    final composer = GetIt.instance<FeatureComposerProvider>();
    final isSlotConfigured = composer.isConfigured;
    // Spin blocked when: not initialized, not configured, insufficient balance, or reels spinning
    final canSpin = isInitialized && isSlotConfigured && _balance >= _totalBetAmount && !isReelsActuallySpinning;
    final sessionRtp = _sessionTotalBet > 0 ? (_totalWin / _sessionTotalBet * 100) : 0.0;
    // Get GDD symbols from project provider (if imported)
    final gddSymbols = projectProvider.gddSymbols;

    // Get current theme data
    final theme = _currentThemeData;

    return SlotThemeProvider(
      theme: theme,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: theme.bgDeep,
        body: Stack(
          children: [
            // Main layout
            Column(
              children: [
                // A. Header Zone
                _HeaderZone(
                  balance: _balance,
                  isMusicOn: _isMusicOn,
                  isSfxOn: _isSfxOn,
                  onMenuTap: () => setState(() {
                    _showMenuPanel = !_showMenuPanel;
                    if (_showMenuPanel) _showSettingsPanel = false;
                  }),
                  onMusicToggle: _toggleMusic,
                  onSfxToggle: _toggleSfx,
                  onSettingsTap: () => setState(() {
                    _showSettingsPanel = !_showSettingsPanel;
                    if (_showSettingsPanel) _showMenuPanel = false;
                  }),
                  deviceSimulation: _deviceSimulation,
                  onDeviceChanged: _setDeviceSimulation,
                  currentTheme: _themeA,
                  onThemeChanged: _setThemeA,
                  showDebugToolbar: _showDebugToolbar,
                  onDebugToggle: _toggleDebugToolbar,
                  onReload: widget.onReload,
                ),

                // P6: Debug Toolbar — REMOVED (disabled per user request)
                // Debug tools available via Dashboard (Ctrl+D) instead

                // B. Jackpot Zone — REMOVED for default slot machine
                // Jackpot plaques (Mini, Minor, Major, Grand) are added via specific templates
                // when user needs jackpot functionality

                // C. Main Game Zone (with P6 device frame wrapper)
                Expanded(
                  child: _buildDeviceFrame(
                    _MainGameZone(
                      provider: provider,
                      projectProvider: widget.projectProvider,
                      reels: widget.reels,
                      rows: widget.rows,
                      winTier: _currentWinTier,
                    ),
                  ),
                ),

                // F. Control Bar — Modern Total Bet System with SPIN/STOP/SKIP
                _ControlBar(
                  // Modern bet system
                  totalBet: _totalBet,
                  minBet: _minBet,
                  maxBet: _maxBet,
                  betStep: _betStep,
                  quickBetPresets: _quickBetPresets,
                  // WAYS/PAYLINES from GDD (if available)
                  waysCount: projectProvider.gridConfig?.ways,
                  paylinesCount: projectProvider.gridConfig?.paylines ?? 20, // default 20 paylines
                  // Spin controls — isSpinning disables bet controls during active spin/win
                  isSpinning: provider.isPlayingStages || isReelsActuallySpinning,
                  showStopButton: provider.isPlayingStages || isReelsActuallySpinning,
                  isAutoSpin: _isAutoSpin,
                  autoSpinCount: _autoSpinRemaining,
                  isTurbo: _isTurbo,
                  canSpin: canSpin,
                  isConfigured: isSlotConfigured,
                  // SKIP button controls (industry-standard win presentation skip)
                  // FIX: Use provider.isWinPresentationActive instead of local _showWinPresenter
                  // This ensures Skip button appears when SlotPreviewWidget is in win presentation
                  isInWinPresentation: provider.isWinPresentationActive,
                  currentWinTier: _currentWinTier,
                  bigWinProtectionRemaining: _bigWinProtectionRemaining,
                  // Callbacks
                  onBetChanged: (v) => setState(() => _totalBet = v),
                  onMaxBet: _handleMaxBet,
                  onSpin: () => _handleSpin(provider),
                  onStop: _handleStop,
                  onSkip: _handleSkipWinPresentation,
                  onAutoSpinToggle: _handleAutoSpinToggle,
                  onTurboToggle: _toggleTurbo,
                  onAfterInteraction: () => _focusNode.requestFocus(),
                ),
              ],
            ),

            // G. Info Panels — REMOVED (moved to Dashboard)
            // Use Dashboard (Ctrl+D) for Paytable, Rules, History, and Stats

            // D. Win Presenter — REMOVED
            // SlotPreviewWidget (child) already has complete win presentation system
            // that WORKS correctly with tier labels. No need for duplicate overlay.

            // Gamble Screen (overlay) — disabled for basic mockup
            // To re-enable: uncomment the block below
            // if (_showGambleScreen)
            //   Positioned.fill(
            //     child: _GambleOverlay(
            //       stakeAmount: _pendingWinAmount,
            //       cardRevealed: _gambleCardRevealed,
            //       won: _gambleWon,
            //       onChooseRed: () => _makeGambleChoice(0),
            //       onChooseBlack: () => _makeGambleChoice(1),
            //       onCollect: _collectWin,
            //     ),
            //   ),

            // G2. Menu Panel (overlay)
            if (_showMenuPanel)
              Positioned(
                top: 70,
                left: 16,
                child: _MenuPanel(
                  onDashboard: () {
                    setState(() => _showMenuPanel = false);
                    ProjectDashboardDialog.show(context);
                  },
                  onSettings: () => setState(() {
                    _showSettingsPanel = true;
                    _showMenuPanel = false;
                  }),
                  onHelp: () {
                    setState(() => _showMenuPanel = false);
                    final dialogTheme = context.slotTheme;
                    // Show a simple help dialog
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: dialogTheme.bgPanel,
                        title: Text(
                          'Premium Slot Preview',
                          style: TextStyle(color: dialogTheme.textPrimary),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Audio Testing Sandbox',
                              style: TextStyle(
                                color: FluxForgeTheme.accentCyan,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Keyboard Shortcuts:',
                              style: TextStyle(
                                color: dialogTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '• SPACE - Spin\n'
                              '• M - Toggle Music\n'
                              '• S - Toggle Stats\n'
                              '• T - Toggle Turbo\n'
                              '• A - Toggle Auto-Spin\n'
                              '• ESC - Exit\n'
                              '• 1-7 - Forced Outcomes (Debug)',
                              style: TextStyle(color: dialogTheme.textSecondary),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  onClose: () => setState(() => _showMenuPanel = false),
                ),
              ),

            // H2. Debug / Forced Outcome Panel (D key toggle)
            if (_showDebugToolbar)
              Positioned(
                top: 56,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // GameFlow state indicator
                    Consumer<GameFlowProvider>(
                      builder: (context, flow, _) {
                        final state = flow.currentState;
                        final isFeature = flow.isInFeature;
                        final fsState = flow.freeSpinsState;
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          color: isFeature
                              ? const Color(0xFF4CAF50).withOpacity(0.85)
                              : Colors.black54,
                          child: Row(
                            children: [
                              Icon(
                                isFeature ? Icons.star : Icons.casino,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'State: ${state.displayName}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (fsState != null) ...[
                                const SizedBox(width: 12),
                                Text(
                                  'Spins: ${fsState.spinsRemaining}/${fsState.totalSpins}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                                if (fsState.currentMultiplier > 1.0) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '${fsState.currentMultiplier.toStringAsFixed(1)}x',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                              const Spacer(),
                              Text(
                                'D to close',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    // Force outcome buttons — always visible, no FeatureBuilder dependency
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      color: const Color(0xFF1A1A2E),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _ForceButton(label: 'LOSE', color: const Color(0xFF4A4A5A), onTap: () => provider.spinForced(ForcedOutcome.lose)),
                          _ForceButton(label: 'WIN 1', color: const Color(0xFF66BB6A), onTap: () => provider.spinForced(ForcedOutcome.smallWin)),
                          _ForceButton(label: 'WIN 2', color: const Color(0xFF42A5F5), onTap: () => provider.spinForced(ForcedOutcome.mediumWin)),
                          _ForceButton(label: 'WIN 3', color: const Color(0xFFFFA726), onTap: () => provider.spinForced(ForcedOutcome.bigWin)),
                          _ForceButton(label: 'WIN 4', color: const Color(0xFFEF5350), onTap: () => provider.spinForced(ForcedOutcome.megaWin)),
                          _ForceButton(label: 'WIN 5', color: const Color(0xFFAB47BC), onTap: () => provider.spinForced(ForcedOutcome.epicWin)),
                          _ForceButton(label: 'FREE SPINS', color: const Color(0xFFE040FB), onTap: () => provider.spinForced(ForcedOutcome.freeSpins)),
                          _ForceButton(label: 'NEAR MISS', color: const Color(0xFFFF7043), onTap: () => provider.spinForced(ForcedOutcome.nearMiss)),
                          _ForceButton(label: 'CASCADE', color: const Color(0xFF26C6DA), onTap: () => provider.spinForced(ForcedOutcome.cascade)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // H. Settings Panel (overlay) — P6: Consolidated with all settings
            if (_showSettingsPanel)
              Positioned(
                top: 70,
                right: 16,
                child: SingleChildScrollView(
                  child: _AudioVisualPanel(
                    volume: _masterVolume,
                    isMusicOn: _isMusicOn,
                    isSfxOn: _isSfxOn,
                    quality: _graphicsQuality,
                    animationsEnabled: _animationsEnabled,
                    onVolumeChanged: _setMasterVolume,
                    onMusicToggle: _toggleMusic,
                    onSfxToggle: _toggleSfx,
                    onQualityChanged: _setGraphicsQuality,
                    onAnimationsToggle: _toggleAnimations,
                    onClose: () => setState(() => _showSettingsPanel = false),
                    // P6: Device
                    deviceSimulation: _deviceSimulation,
                    onDeviceChanged: _setDeviceSimulation,
                    // P6: Theme
                    currentTheme: _themeA,
                    comparisonTheme: _themeB,
                    onThemeChanged: _setThemeA,
                    onComparisonThemeChanged: _setThemeB,
                    // P6: Debug
                    showFps: _showFpsCounter,
                    showVoices: _showVoiceCount,
                    showMemory: _showMemoryUsage,
                    showStageTrace: _showStageTrace,
                    onShowFpsToggle: () => setState(() => _showFpsCounter = !_showFpsCounter),
                    onShowVoicesToggle: () => setState(() => _showVoiceCount = !_showVoiceCount),
                    onShowMemoryToggle: () => setState(() => _showMemoryUsage = !_showMemoryUsage),
                    onShowStageTraceToggle: () => setState(() => _showStageTrace = !_showStageTrace),
                  ),
                ),
              ),

          ],
        ),
      ),
      ), // End of SlotThemeProvider
    );
  }
}

/// Compact force outcome button for debug panel
class _ForceButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ForceButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.8),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SLOT SPLASH SCREEN — Loading screen before base game
// =============================================================================

class _SlotSplashScreen extends StatefulWidget {
  final VoidCallback onContinue;

  const _SlotSplashScreen({required this.onContinue});

  @override
  State<_SlotSplashScreen> createState() => _SlotSplashScreenState();
}

class _SlotSplashScreenState extends State<_SlotSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  int _currentPhase = 0;
  bool _loadingComplete = false;

  static const _phases = [
    (label: 'Initializing audio engine...', weight: 0.10),
    (label: 'Loading sound assets...', weight: 0.25),
    (label: 'Preparing reel strips...', weight: 0.15),
    (label: 'Building paytable...', weight: 0.10),
    (label: 'Configuring win evaluation...', weight: 0.10),
    (label: 'Loading symbol animations...', weight: 0.10),
    (label: 'Setting up free spins engine...', weight: 0.08),
    (label: 'Calibrating RTP model...', weight: 0.07),
    (label: 'Ready!', weight: 0.05),
  ];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );
    _progressController.addListener(_updatePhase);
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _loadingComplete = true);
      }
    });
    // Start loading after a brief delay (feels more natural)
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _progressController.forward();
    });
  }

  void _updatePhase() {
    final progress = _progressController.value;
    double accumulated = 0;
    for (int i = 0; i < _phases.length; i++) {
      accumulated += _phases[i].weight;
      if (progress <= accumulated) {
        if (_currentPhase != i && mounted) {
          setState(() => _currentPhase = i);
        }
        break;
      }
    }
  }

  @override
  void dispose() {
    _progressController.removeListener(_updatePhase);
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),
      body: Center(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo / Title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFFD700)],
                ).createShader(bounds),
                child: const Text(
                  'FLUXFORGE',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'S L O T   L A B',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 6,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(height: 48),

              // Progress bar
              AnimatedBuilder(
                animation: _progressController,
                builder: (context, _) {
                  final progress = _progressController.value;
                  final percent = (progress * 100).round();
                  return Column(
                    children: [
                      // Phase label
                      SizedBox(
                        height: 20,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _phases[_currentPhase].label,
                            key: ValueKey(_currentPhase),
                            style: const TextStyle(
                              color: Color(0xFFAAAAAA),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Progress bar track
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFFFD700).withOpacity(0.8),
                                      const Color(0xFFFFA500),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFD700).withOpacity(0.4),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Percentage
                      Text(
                        '$percent%',
                        style: TextStyle(
                          color: _loadingComplete
                              ? const Color(0xFFFFD700)
                              : const Color(0xFF666666),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 32),

              // CONTINUE button (appears when loading complete)
              AnimatedOpacity(
                opacity: _loadingComplete ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: AnimatedScale(
                  scale: _loadingComplete ? 1.0 : 0.8,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutBack,
                  child: GestureDetector(
                    onTap: _loadingComplete ? widget.onContinue : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Text(
                        'CONTINUE',
                        style: TextStyle(
                          color: Color(0xFF1A1000),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
