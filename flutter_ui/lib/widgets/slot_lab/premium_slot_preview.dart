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
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/win_tier_config.dart';
import '../../providers/slot_lab_provider.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../services/event_registry.dart';
import '../../services/gdd_import_service.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
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

/// Complete theme data for slot UI
class SlotThemeData {
  final Color bgDeep;
  final Color bgDark;
  final Color bgMid;
  final Color bgSurface;
  final Color gold;
  final Color accent;
  final Color winSmall;
  final Color winBig;
  final Color winMega;
  final Color winEpic;
  final Color winUltra;
  final List<Color> jackpotColors;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  const SlotThemeData({
    required this.bgDeep,
    required this.bgDark,
    required this.bgMid,
    required this.bgSurface,
    required this.gold,
    required this.accent,
    required this.winSmall,
    required this.winBig,
    required this.winMega,
    required this.winEpic,
    required this.winUltra,
    required this.jackpotColors,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
  });

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
// A. HEADER ZONE
// =============================================================================

class _HeaderZone extends StatelessWidget {
  final double balance;
  final int vipLevel;
  final bool isMusicOn;
  final bool isSfxOn;
  final bool isFullscreen;
  final VoidCallback onMenuTap;
  final VoidCallback onMusicToggle;
  final VoidCallback onSfxToggle;
  final VoidCallback onSettingsTap;
  final VoidCallback onFullscreenToggle;
  final VoidCallback onExit;

  // P6: Device simulation
  final DeviceSimulation deviceSimulation;
  final ValueChanged<DeviceSimulation> onDeviceChanged;

  // P6: Theme
  final SlotThemePreset currentTheme;
  final ValueChanged<SlotThemePreset> onThemeChanged;

  // P6: Recording
  final bool isRecording;
  final Duration recordingDuration;
  final VoidCallback onRecordingToggle;

  // P6: Debug
  final bool showDebugToolbar;
  final VoidCallback onDebugToggle;

  const _HeaderZone({
    required this.balance,
    required this.vipLevel,
    required this.isMusicOn,
    required this.isSfxOn,
    required this.isFullscreen,
    required this.onMenuTap,
    required this.onMusicToggle,
    required this.onSfxToggle,
    required this.onSettingsTap,
    required this.onFullscreenToggle,
    required this.onExit,
    // P6 params
    this.deviceSimulation = DeviceSimulation.desktop,
    required this.onDeviceChanged,
    this.currentTheme = SlotThemePreset.casino,
    required this.onThemeChanged,
    this.isRecording = false,
    this.recordingDuration = Duration.zero,
    required this.onRecordingToggle,
    this.showDebugToolbar = false,
    required this.onDebugToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48, // Reduced from 56
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _SlotTheme.bgDark,
            _SlotTheme.bgDark.withOpacity(0.95),
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: _SlotTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Menu button
          _HeaderIconButton(
            icon: Icons.menu,
            tooltip: 'Menu',
            onTap: onMenuTap,
          ),
          const SizedBox(width: 12),

          // Logo
          _buildLogo(),
          const SizedBox(width: 24),

          // Balance display (animated)
          _BalanceDisplay(balance: balance),

          const SizedBox(width: 16),

          // VIP badge
          _VipBadge(level: vipLevel),

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

          // P6: Recording button
          _RecordingButton(
            isRecording: isRecording,
            duration: recordingDuration,
            onTap: onRecordingToggle,
          ),
          const SizedBox(width: 12),

          // P6: Debug toggle (debug mode only)
          if (kDebugMode) ...[
            _HeaderIconButton(
              icon: showDebugToolbar ? Icons.bug_report : Icons.bug_report_outlined,
              tooltip: 'Debug Toolbar (D)',
              isActive: showDebugToolbar,
              onTap: onDebugToggle,
            ),
            const SizedBox(width: 12),
          ],

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
          const SizedBox(width: 16),

          // Settings
          _HeaderIconButton(
            icon: Icons.settings,
            tooltip: 'Settings',
            onTap: onSettingsTap,
          ),
          const SizedBox(width: 8),

          // Fullscreen toggle
          _HeaderIconButton(
            icon: isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
            onTap: onFullscreenToggle,
          ),
          const SizedBox(width: 8),

          // Exit button
          _HeaderIconButton(
            icon: Icons.close,
            tooltip: 'Exit (ESC)',
            isDestructive: true,
            onTap: onExit,
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [FluxForgeTheme.accentBlue, FluxForgeTheme.accentCyan],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: FluxForgeTheme.accentBlue.withOpacity(0.4),
                blurRadius: 8,
              ),
            ],
          ),
          child: const Icon(Icons.casino, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        const Text(
          'FLUXFORGE',
          style: TextStyle(
            color: _SlotTheme.textPrimary,
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
    final color = widget.isDestructive
        ? FluxForgeTheme.accentRed
        : widget.isActive
            ? FluxForgeTheme.accentBlue
            : _SlotTheme.textSecondary;

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _SlotTheme.bgMid.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _SlotTheme.border.withOpacity(0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeviceSimulation>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, color: _SlotTheme.textSecondary, size: 18),
          dropdownColor: _SlotTheme.bgDark,
          style: const TextStyle(color: _SlotTheme.textPrimary, fontSize: 12),
          items: DeviceSimulation.values.map((device) {
            return DropdownMenuItem(
              value: device,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(device.icon, size: 16, color: _SlotTheme.textSecondary),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _SlotTheme.bgMid.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _SlotTheme.border.withOpacity(0.5)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SlotThemePreset>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, color: _SlotTheme.textSecondary, size: 18),
          dropdownColor: _SlotTheme.bgDark,
          style: const TextStyle(color: _SlotTheme.textPrimary, fontSize: 12),
          items: SlotThemePreset.values.map((theme) {
            return DropdownMenuItem(
              value: theme,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.palette, size: 16, color: theme.data.accent),
                  const SizedBox(width: 6),
                  Text(theme.label),
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

class _RecordingButton extends StatelessWidget {
  final bool isRecording;
  final Duration duration;
  final VoidCallback onTap;

  const _RecordingButton({
    required this.isRecording,
    required this.duration,
    required this.onTap,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isRecording ? 'Stop Recording (R)' : 'Start Recording (R)',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isRecording
                ? FluxForgeTheme.accentRed.withOpacity(0.2)
                : _SlotTheme.bgMid.withOpacity(0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isRecording
                  ? FluxForgeTheme.accentRed.withOpacity(0.5)
                  : _SlotTheme.border.withOpacity(0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing red dot when recording
              if (isRecording)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.5, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentRed.withOpacity(value),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                )
              else
                Icon(
                  Icons.fiber_manual_record,
                  size: 14,
                  color: _SlotTheme.textSecondary,
                ),
              const SizedBox(width: 6),
              Text(
                isRecording ? _formatDuration(duration) : 'REC',
                style: TextStyle(
                  color: isRecording
                      ? FluxForgeTheme.accentRed
                      : _SlotTheme.textSecondary,
                  fontSize: 12,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _SlotTheme.bgDark.withOpacity(0.95),
        border: const Border(
          bottom: BorderSide(color: _SlotTheme.border, width: 1),
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

          // Forced outcome buttons
          _DebugOutcomeButton(label: 'Lose', index: 1, onTap: onForceOutcome),
          _DebugOutcomeButton(label: 'Small', index: 2, onTap: onForceOutcome),
          _DebugOutcomeButton(label: 'Big', index: 3, onTap: onForceOutcome),
          _DebugOutcomeButton(label: 'Mega', index: 4, onTap: onForceOutcome),
          _DebugOutcomeButton(label: 'FS', index: 5, onTap: onForceOutcome),
          _DebugOutcomeButton(label: 'JP', index: 6, onTap: onForceOutcome),

          const Spacer(),

          // Stats
          _DebugStat(label: 'FPS', value: '$fps', color: fps >= 55 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed),
          const SizedBox(width: 16),
          _DebugStat(label: 'Voices', value: '$activeVoices/48', color: _SlotTheme.textSecondary),
          const SizedBox(width: 16),
          _DebugStat(label: 'Mem', value: '${memoryMb}MB', color: _SlotTheme.textSecondary),
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
                      : _SlotTheme.border.withOpacity(0.3),
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
                        : _SlotTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Stages',
                    style: TextStyle(
                      color: showStageTrace
                          ? FluxForgeTheme.accentBlue
                          : _SlotTheme.textSecondary,
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

  const _DebugOutcomeButton({
    required this.label,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _SlotTheme.bgMid.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _SlotTheme.border.withOpacity(0.3)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _SlotTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: _SlotTheme.textSecondary,
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
            color: _SlotTheme.bgPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _glowController.isAnimating
                  ? glowColor.withOpacity(glowOpacity)
                  : _SlotTheme.border,
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
                color: _SlotTheme.gold,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '\$${_displayedBalance.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: _SlotTheme.textPrimary,
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

class _VipBadge extends StatelessWidget {
  final int level;

  const _VipBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final colors = _getVipColors(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors[0].withOpacity(0.4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            'VIP $level',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _getVipColors(int level) {
    if (level >= 10) return [_SlotTheme.gold, _SlotTheme.goldLight];
    if (level >= 7) return [_SlotTheme.jackpotMajor, const Color(0xFFFF6090)];
    if (level >= 4) return [_SlotTheme.jackpotMinor, const Color(0xFFB080FF)];
    return [_SlotTheme.jackpotMini, const Color(0xFF60D060)];
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), // Reduced padding
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _SlotTheme.bgDark.withOpacity(0.95),
            _SlotTheme.bgMid.withOpacity(0.85),
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
            color: _SlotTheme.jackpotMini,
            size: _JackpotSize.small,
          ),
          const SizedBox(width: 12),
          _JackpotTicker(
            label: 'MINOR',
            amount: minorJackpot,
            color: _SlotTheme.jackpotMinor,
            size: _JackpotSize.medium,
          ),
          const SizedBox(width: 16),
          _JackpotTicker(
            label: 'MAJOR',
            amount: majorJackpot,
            color: _SlotTheme.jackpotMajor,
            size: _JackpotSize.large,
          ),
          const SizedBox(width: 16),
          _JackpotTicker(
            label: 'GRAND',
            amount: grandJackpot,
            color: _SlotTheme.jackpotGrand,
            size: _JackpotSize.grand,
          ),
          if (mysteryJackpot != null) ...[
            const SizedBox(width: 12),
            _JackpotTicker(
              label: 'MYSTERY',
              amount: mysteryJackpot!,
              color: _SlotTheme.jackpotMystery,
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
    final dimensions = _getDimensions();

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = 0.8 + (_pulseController.value * 0.2);

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
              color: widget.color.withOpacity(pulse * 0.6),
              width: widget.size == _JackpotSize.grand ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(pulse * 0.3),
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
                        color: _SlotTheme.textPrimary,
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
    return SizedBox(
      width: 180,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CONTRIBUTION',
                style: TextStyle(
                  color: _SlotTheme.textMuted,
                  fontSize: 8,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '\$${(contribution * 100).toStringAsFixed(2)}',
                style: const TextStyle(
                  color: _SlotTheme.gold,
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
              color: _SlotTheme.bgSurface,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: contribution.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_SlotTheme.jackpotMini, _SlotTheme.gold],
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
  final bool showScatterCollect;
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
    this.showScatterCollect = false,
    this.showCascade = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background theme layer
        _buildBackgroundLayer(),

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

        // Scatter collection layer
        if (showScatterCollect) _buildScatterCollect(),

        // Cascade/tumble layer
        if (showCascade) _buildCascadeLayer(),
      ],
    );
  }

  Widget _buildBackgroundLayer() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.5,
          colors: [
            _SlotTheme.bgMid,
            _SlotTheme.bgDeep,
          ],
        ),
      ),
    );
  }

  Widget _buildReelFrame(BuildContext context) {
    final glowColor = _getWinColor(winTier);
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
                color: isWinning ? glowColor : _SlotTheme.gold.withOpacity(0.4),
                width: isWinning ? 5 : 3,
              ),
              boxShadow: [
                // Inner glow
                BoxShadow(
                  color: _SlotTheme.gold.withOpacity(0.15),
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
                  SlotPreviewWidget(
                    key: ValueKey('slot_preview_${reels}x$rows'),
                    provider: provider,
                    projectProvider: projectProvider ?? context.read<SlotLabProjectProvider>(),
                    reels: reels,
                    rows: rows,
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

  Widget _buildScatterCollect() {
    return const _ScatterCollectOverlay();
  }

  Widget _buildCascadeLayer() {
    return const _CascadeOverlay();
  }

  Color _getWinColor(String? tier) {
    return switch (tier) {
      'ULTRA' => _SlotTheme.winUltra,
      'EPIC' => _SlotTheme.winEpic,
      'MEGA' => _SlotTheme.winMega,
      'BIG' => _SlotTheme.winBig,
      'SMALL' => _SlotTheme.winSmall,
      _ => FluxForgeTheme.accentBlue,
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
    return CustomPaint(
      size: Size.infinite,
      painter: _PaylinePainter(
        payline: payline,
        reels: reels,
        rows: rows,
      ),
    );
  }
}

class _PaylinePainter extends CustomPainter {
  final List<int> payline;
  final int reels;
  final int rows;

  _PaylinePainter({
    required this.payline,
    required this.reels,
    required this.rows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (payline.isEmpty) return;

    final paint = Paint()
      ..color = _SlotTheme.gold
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = _SlotTheme.gold.withOpacity(0.3)
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
    final color = _getColor();

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

  Color _getColor() {
    return switch (widget.tier) {
      'ULTRA' => _SlotTheme.winUltra,
      'EPIC' => _SlotTheme.winEpic,
      'MEGA' => _SlotTheme.winMega,
      'BIG' => _SlotTheme.winBig,
      _ => _SlotTheme.winSmall,
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
                    _SlotTheme.gold.withOpacity(glowOpacity),
                    _SlotTheme.gold.withOpacity(glowOpacity * 0.3),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),

            // Sparkles
            CustomPaint(
              size: Size.infinite,
              painter: _SparklePainter(sparkles: _sparkles),
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
                      color: _SlotTheme.gold.withOpacity(0.6),
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

  _SparklePainter({required this.sparkles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparkles) {
      if (s.life <= 0) continue;
      final x = s.x * size.width;
      final y = s.y * size.height;
      final opacity = s.life;

      final paint = Paint()
        ..color = _SlotTheme.gold.withOpacity(opacity * 0.8);
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
// SCATTER COLLECT OVERLAY — Scatter symbols flying to counter
// =============================================================================

class _ScatterCollectOverlay extends StatefulWidget {
  const _ScatterCollectOverlay();

  @override
  State<_ScatterCollectOverlay> createState() => _ScatterCollectOverlayState();
}

class _ScatterCollectOverlayState extends State<_ScatterCollectOverlay>
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
                    _SlotTheme.jackpotMinor.withOpacity(0.3 + _glowController.value * 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),

            // Scatter symbols
            CustomPaint(
              size: Size.infinite,
              painter: _ScatterPainter(scatters: _scatters),
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
                    color: _SlotTheme.jackpotMinor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _SlotTheme.jackpotMinor.withOpacity(0.5 + _glowController.value * 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _SlotTheme.jackpotMinor.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '◆',
                        style: TextStyle(
                          fontSize: 24,
                          color: _SlotTheme.jackpotMinor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'SCATTER',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _SlotTheme.jackpotMinor,
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

  _ScatterPainter({required this.scatters});

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
          ..color = _SlotTheme.jackpotMinor.withOpacity(trailOpacity);
        canvas.drawCircle(
          Offset(trailX * size.width, trailY * size.height),
          symbolSize * 0.3,
          trailPaint,
        );
      }

      // Glow
      final glowPaint = Paint()
        ..color = _SlotTheme.jackpotMinor.withOpacity(s.opacity * 0.5)
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
                _SlotTheme.bgSurface.withOpacity(0.95),
                _SlotTheme.bgMid.withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _SlotTheme.gold.withOpacity(0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: _SlotTheme.gold.withOpacity(0.3),
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
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [_SlotTheme.gold, _SlotTheme.jackpotMajor],
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
                  color: _SlotTheme.bgDeep,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _SlotTheme.gold.withOpacity(0.3)),
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
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _SlotTheme.gold,
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
                _buildRevealedCard(isRed, won ?? false),
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

  Widget _buildRevealedCard(bool isRed, bool won) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
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
                      colors: [_SlotTheme.bgMid, _SlotTheme.bgDeep],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _SlotTheme.gold, width: 2),
                  ),
                  child: const Center(
                    child: Text(
                      '?',
                      style: TextStyle(
                        color: _SlotTheme.gold,
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
// D. WIN PRESENTER
// =============================================================================

class _WinPresenter extends StatefulWidget {
  final double winAmount;
  final String winTier;
  final double multiplier;
  final bool showCollect;
  final bool showGamble;
  final VoidCallback? onCollect;
  final VoidCallback? onGamble;

  const _WinPresenter({
    required this.winAmount,
    required this.winTier,
    this.multiplier = 1.0,
    this.showCollect = false,
    this.showGamble = false,
    this.onCollect,
    this.onGamble,
  });

  @override
  State<_WinPresenter> createState() => _WinPresenterState();
}

class _WinPresenterState extends State<_WinPresenter>
    with TickerProviderStateMixin {
  late AnimationController _rollupController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  double _displayedAmount = 0;
  final List<_CoinParticle> _particles = [];
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _rollupController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _initParticles();
    _startRollup();
  }

  void _initParticles() {
    for (int i = 0; i < 30; i++) {
      _particles.add(_CoinParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        vx: (_random.nextDouble() - 0.5) * 0.02,
        vy: -_random.nextDouble() * 0.03 - 0.01,
        size: _random.nextDouble() * 8 + 4,
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.2,
      ));
    }
  }

  void _startRollup() {
    _rollupController.forward();
    _rollupController.addListener(() {
      setState(() {
        _displayedAmount = widget.winAmount * _rollupController.value;
      });
    });
  }

  @override
  void dispose() {
    _rollupController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _getWinColor();

    return Stack(
      alignment: Alignment.center,
      children: [
        // Coin burst particles
        AnimatedBuilder(
          animation: _particleController,
          builder: (context, _) {
            _updateParticles();
            return CustomPaint(
              size: const Size(400, 300),
              painter: _CoinParticlePainter(particles: _particles),
            );
          },
        ),

        // Win celebration frame
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final scale = 0.95 + _pulseController.value * 0.1;

            return Transform.scale(
              scale: scale,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color,
                      color.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.6),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Win tier badge
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getWinIcon(), color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          '${widget.winTier} WIN!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            shadows: [
                              Shadow(
                                  color: Colors.black45,
                                  blurRadius: 4,
                                  offset: Offset(2, 2)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(_getWinIcon(), color: Colors.white, size: 28),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Win amount (rollup)
                    Text(
                      '\$${_displayedAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        shadows: [
                          Shadow(
                              color: Colors.black45,
                              blurRadius: 8,
                              offset: Offset(3, 3)),
                        ],
                      ),
                    ),

                    // Multiplier display
                    if (widget.multiplier > 1.0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${widget.multiplier.toStringAsFixed(0)}x MULTIPLIER',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],

                    // Collect / Gamble buttons
                    if (widget.showCollect || widget.showGamble) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.showCollect)
                            _WinButton(
                              label: 'COLLECT',
                              color: FluxForgeTheme.accentGreen,
                              onTap: widget.onCollect,
                            ),
                          if (widget.showCollect && widget.showGamble)
                            const SizedBox(width: 16),
                          if (widget.showGamble)
                            _WinButton(
                              label: 'GAMBLE',
                              color: FluxForgeTheme.accentOrange,
                              onTap: widget.onGamble,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _updateParticles() {
    for (final p in _particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.001; // Gravity
      p.rotation += p.rotationSpeed;

      // Reset if off screen
      if (p.y > 1.2) {
        p.x = _random.nextDouble();
        p.y = -0.1;
        p.vy = -_random.nextDouble() * 0.03 - 0.01;
      }
    }
  }

  Color _getWinColor() {
    return switch (widget.winTier) {
      'ULTRA' => _SlotTheme.winUltra,
      'EPIC' => _SlotTheme.winEpic,
      'MEGA' => _SlotTheme.winMega,
      'SUPER' => _SlotTheme.winBig,
      'BIG' => const Color(0xFF4CAF50), // Green for BIG
      _ => _SlotTheme.winSmall,
    };
  }

  IconData _getWinIcon() {
    return switch (widget.winTier) {
      'ULTRA' => Icons.auto_awesome,
      'EPIC' => Icons.bolt,
      'MEGA' => Icons.stars,
      'SUPER' => Icons.celebration,
      'BIG' => Icons.star,
      _ => Icons.check_circle,
    };
  }
}

class _WinButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _WinButton({
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.color
                : widget.color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.color, width: 2),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _isHovered ? Colors.white : widget.color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoinParticle {
  double x, y, vx, vy, size, rotation, rotationSpeed;

  _CoinParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class _CoinParticlePainter extends CustomPainter {
  final List<_CoinParticle> particles;

  _CoinParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = _SlotTheme.gold
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(p.x * size.width, p.y * size.height);
      canvas.rotate(p.rotation);

      // Draw coin as ellipse (simulates 3D rotation)
      final scaleX = (math.cos(p.rotation) * 0.5 + 0.5).clamp(0.3, 1.0);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size * scaleX,
          height: p.size,
        ),
        paint,
      );

      // Highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(-p.size * 0.15, -p.size * 0.15),
          width: p.size * 0.3 * scaleX,
          height: p.size * 0.3,
        ),
        highlightPaint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CoinParticlePainter oldDelegate) => true;
}

// =============================================================================
// E. FEATURE INDICATORS
// =============================================================================

class _FeatureIndicators extends StatelessWidget {
  final int freeSpins;
  final int freeSpinsRemaining;
  final double bonusMeter;
  final double featureProgress;
  final int multiplier;
  final int cascadeCount;
  final int specialSymbolCount;

  const _FeatureIndicators({
    this.freeSpins = 0,
    this.freeSpinsRemaining = 0,
    this.bonusMeter = 0.0,
    this.featureProgress = 0.0,
    this.multiplier = 1,
    this.cascadeCount = 0,
    this.specialSymbolCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Only show if there's something to display
    final hasContent = freeSpins > 0 ||
        bonusMeter > 0 ||
        featureProgress > 0 ||
        multiplier > 1 ||
        cascadeCount > 0 ||
        specialSymbolCount > 0;

    if (!hasContent) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Free spin counter
          if (freeSpins > 0) ...[
            _FeatureBadge(
              icon: Icons.star,
              label: 'FREE SPINS',
              value: '$freeSpinsRemaining / $freeSpins',
              color: _SlotTheme.jackpotMinor,
            ),
            const SizedBox(width: 16),
          ],

          // Bonus meter
          if (bonusMeter > 0) ...[
            _FeatureMeter(
              label: 'BONUS',
              value: bonusMeter,
              color: _SlotTheme.jackpotMajor,
            ),
            const SizedBox(width: 16),
          ],

          // Feature progress
          if (featureProgress > 0) ...[
            _FeatureMeter(
              label: 'FEATURE',
              value: featureProgress,
              color: FluxForgeTheme.accentCyan,
            ),
            const SizedBox(width: 16),
          ],

          // Multiplier trail
          if (multiplier > 1) ...[
            _FeatureBadge(
              icon: Icons.close,
              label: 'MULTIPLIER',
              value: '${multiplier}x',
              color: _SlotTheme.gold,
            ),
            const SizedBox(width: 16),
          ],

          // Cascade counter
          if (cascadeCount > 0) ...[
            _FeatureBadge(
              icon: Icons.waterfall_chart,
              label: 'CASCADE',
              value: '$cascadeCount',
              color: FluxForgeTheme.accentCyan,
            ),
            const SizedBox(width: 16),
          ],

          // Special symbol counter
          if (specialSymbolCount > 0)
            _FeatureBadge(
              icon: Icons.auto_awesome,
              label: 'SPECIAL',
              value: '$specialSymbolCount',
              color: _SlotTheme.gold,
            ),
        ],
      ),
    );
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
    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _SlotTheme.bgPanel,
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
              color: _SlotTheme.bgSurface,
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
            style: const TextStyle(
              color: _SlotTheme.textSecondary,
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

class _ControlBar extends StatelessWidget {
  final int lines;
  final int maxLines;
  final double coinValue;
  final List<double> coinValues;
  final int betLevel;
  final int maxBetLevel;
  final double totalBet;
  final bool isSpinning;
  final bool showStopButton; // True ONLY during actual reel spinning
  final bool isAutoSpin;
  final int autoSpinCount;
  final bool isTurbo;
  final bool canSpin;
  final ValueChanged<int> onLinesChanged;
  final ValueChanged<double> onCoinChanged;
  final ValueChanged<int> onBetLevelChanged;
  final VoidCallback onMaxBet;
  final VoidCallback onSpin;
  final VoidCallback onStop;
  final VoidCallback onAutoSpinToggle;
  final VoidCallback onTurboToggle;
  final VoidCallback? onAfterInteraction; // Request focus back after any interaction

  const _ControlBar({
    required this.lines,
    required this.maxLines,
    required this.coinValue,
    required this.coinValues,
    required this.betLevel,
    required this.maxBetLevel,
    required this.totalBet,
    required this.isSpinning,
    required this.showStopButton,
    required this.isAutoSpin,
    required this.autoSpinCount,
    required this.isTurbo,
    required this.canSpin,
    required this.onLinesChanged,
    required this.onCoinChanged,
    required this.onBetLevelChanged,
    required this.onMaxBet,
    required this.onSpin,
    required this.onStop,
    required this.onAutoSpinToggle,
    required this.onTurboToggle,
    this.onAfterInteraction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Reduced padding
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _SlotTheme.bgMid.withOpacity(0.95),
            _SlotTheme.bgDark,
          ],
        ),
        border: const Border(
          top: BorderSide(color: Color(0xFF3a3a48), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lines selector
          _BetSelector(
            label: 'LINES',
            value: '$lines',
            onDecrease: lines > 1 ? () { onLinesChanged(lines - 1); onAfterInteraction?.call(); } : null,
            onIncrease: lines < maxLines ? () { onLinesChanged(lines + 1); onAfterInteraction?.call(); } : null,
            isDisabled: isSpinning,
          ),
          const SizedBox(width: 12),

          // Coin selector
          _BetSelector(
            label: 'COIN',
            value: coinValue.toStringAsFixed(2),
            onDecrease: coinValues.indexOf(coinValue) > 0
                ? () { onCoinChanged(coinValues[coinValues.indexOf(coinValue) - 1]); onAfterInteraction?.call(); }
                : null,
            onIncrease: coinValues.indexOf(coinValue) < coinValues.length - 1
                ? () { onCoinChanged(coinValues[coinValues.indexOf(coinValue) + 1]); onAfterInteraction?.call(); }
                : null,
            isDisabled: isSpinning,
          ),
          const SizedBox(width: 12),

          // Bet level selector
          _BetSelector(
            label: 'BET',
            value: '$betLevel',
            onDecrease: betLevel > 1 ? () { onBetLevelChanged(betLevel - 1); onAfterInteraction?.call(); } : null,
            onIncrease: betLevel < maxBetLevel ? () { onBetLevelChanged(betLevel + 1); onAfterInteraction?.call(); } : null,
            isDisabled: isSpinning,
          ),
          const SizedBox(width: 16),

          // Total bet display
          _TotalBetDisplay(totalBet: totalBet),
          const SizedBox(width: 16),

          // Max bet button
          _ControlButton(
            label: 'MAX\nBET',
            gradient: _SlotTheme.maxBetGradient,
            onTap: isSpinning ? null : () { onMaxBet(); onAfterInteraction?.call(); },
            width: 54,
            height: 54,
          ),
          const SizedBox(width: 10),

          // Auto spin button
          _ControlButton(
            label: isAutoSpin ? 'STOP\n$autoSpinCount' : 'AUTO\nSPIN',
            gradient: isAutoSpin ? _SlotTheme.autoSpinGradient : null,
            onTap: () { onAutoSpinToggle(); onAfterInteraction?.call(); },
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
            onTap: () { onTurboToggle(); onAfterInteraction?.call(); },
            width: 54,
            height: 54,
            isActive: isTurbo,
          ),
          const SizedBox(width: 20),

          // Main spin/stop button
          _SpinButton(
            isSpinning: isSpinning,
            showStopButton: showStopButton,
            canSpin: canSpin,
            onSpin: onSpin,
            onStop: onStop,
          ),
        ],
      ),
    );
  }
}

class _BetSelector extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final bool isDisabled;

  const _BetSelector({
    required this.label,
    required this.value,
    this.onDecrease,
    this.onIncrease,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _SlotTheme.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _SlotTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrease button
          _SelectorArrow(
            icon: Icons.chevron_left,
            onTap: isDisabled ? null : onDecrease,
          ),
          const SizedBox(width: 8),

          // Value display
          SizedBox(
            width: 50,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _SlotTheme.textMuted,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: _SlotTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Increase button
          _SelectorArrow(
            icon: Icons.chevron_right,
            onTap: isDisabled ? null : onIncrease,
          ),
        ],
      ),
    );
  }
}

class _SelectorArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _SelectorArrow({required this.icon, this.onTap});

  @override
  State<_SelectorArrow> createState() => _SelectorArrowState();
}

class _SelectorArrowState extends State<_SelectorArrow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _isHovered && isEnabled
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            color: isEnabled
                ? (_isHovered ? FluxForgeTheme.accentBlue : _SlotTheme.textSecondary)
                : _SlotTheme.textMuted.withOpacity(0.5),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _TotalBetDisplay extends StatelessWidget {
  final double totalBet;

  const _TotalBetDisplay({required this.totalBet});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _SlotTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _SlotTheme.gold.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'TOTAL BET',
            style: TextStyle(
              color: _SlotTheme.gold,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '\$${totalBet.toStringAsFixed(2)}',
            style: const TextStyle(
              color: _SlotTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

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
        child: AnimatedContainer(
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
                    ? _SlotTheme.bgSurface
                    : _SlotTheme.bgPanel),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasGradient
                  ? widget.gradient![0].withOpacity(_isHovered ? 1.0 : 0.6)
                  : _SlotTheme.border,
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
                      : _SlotTheme.textSecondary,
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
                      : _SlotTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpinButton extends StatefulWidget {
  final bool isSpinning;
  final bool showStopButton; // True ONLY while reels are visually spinning
  final bool canSpin;
  final VoidCallback onSpin;
  final VoidCallback onStop;

  const _SpinButton({
    required this.isSpinning,
    required this.showStopButton,
    required this.canSpin,
    required this.onSpin,
    required this.onStop,
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

  @override
  Widget build(BuildContext context) {
    // Button is enabled when can spin OR when STOP button should be shown
    final isEnabled = widget.canSpin || widget.showStopButton;
    // Show STOP button ONLY during actual reel spinning (not during win presentation)
    final showStop = widget.showStopButton;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: () {
          if (showStop) {
            widget.onStop();
          } else if (widget.canSpin) {
            widget.onSpin();
          }
        },
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final pulse = showStop
                ? 1.0
                : (0.95 + _pulseController.value * 0.1);

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
                    colors: showStop
                        ? [FluxForgeTheme.accentRed, const Color(0xFFCC2040)]
                        : (isEnabled
                            ? _SlotTheme.spinGradient
                            : [_SlotTheme.bgSurface, _SlotTheme.bgPanel]),
                  ),
                  border: Border.all(
                    color: showStop
                        ? FluxForgeTheme.accentRed
                        : (isEnabled
                            ? FluxForgeTheme.accentBlue
                            : _SlotTheme.border),
                    width: _isHovered ? 4 : 3,
                  ),
                  boxShadow: [
                    if (isEnabled)
                      BoxShadow(
                        color: (showStop
                                ? FluxForgeTheme.accentRed
                                : FluxForgeTheme.accentBlue)
                            .withOpacity(_isHovered ? 0.6 : 0.4),
                        blurRadius: _isHovered ? 24 : 16,
                        spreadRadius: _isHovered ? 4 : 2,
                      ),
                  ],
                ),
                child: Center(
                  child: showStop
                      ? const Column(
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
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow,
                              color: isEnabled ? Colors.white : _SlotTheme.textMuted,
                              size: 36,
                            ),
                            Text(
                              'SPIN',
                              style: TextStyle(
                                color: isEnabled ? Colors.white : _SlotTheme.textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
// G. INFO PANELS
// =============================================================================

class _InfoPanels extends StatelessWidget {
  final bool showPaytable;
  final bool showRules;
  final bool showHistory;
  final bool showStats;
  final List<_RecentWin> recentWins;
  final int totalSpins;
  final double rtp;
  final _GameRulesConfig gameConfig;
  final VoidCallback onPaytableToggle;
  final VoidCallback onRulesToggle;
  final VoidCallback onHistoryToggle;
  final VoidCallback onStatsToggle;
  /// GDD symbols from imported Game Design Document (if any)
  final List<GddSymbol> gddSymbols;

  const _InfoPanels({
    this.showPaytable = false,
    this.showRules = false,
    this.showHistory = false,
    this.showStats = false,
    this.recentWins = const [],
    this.totalSpins = 0,
    this.rtp = 0.0,
    this.gameConfig = const _GameRulesConfig(),
    required this.onPaytableToggle,
    required this.onRulesToggle,
    required this.onHistoryToggle,
    required this.onStatsToggle,
    this.gddSymbols = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      top: 160,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Paytable button
          _InfoButton(
            icon: Icons.table_chart,
            label: 'PAY',
            isActive: showPaytable,
            onTap: onPaytableToggle,
          ),
          const SizedBox(height: 8),

          // Rules button
          _InfoButton(
            icon: Icons.info_outline,
            label: 'INFO',
            isActive: showRules,
            onTap: onRulesToggle,
          ),
          const SizedBox(height: 8),

          // History button
          _InfoButton(
            icon: Icons.history,
            label: 'HIST',
            isActive: showHistory,
            onTap: onHistoryToggle,
          ),
          const SizedBox(height: 8),

          // Stats button
          _InfoButton(
            icon: Icons.analytics,
            label: 'STAT',
            isActive: showStats,
            onTap: onStatsToggle,
          ),

          // Expanded panels
          if (showHistory) ...[
            const SizedBox(height: 16),
            _RecentWinsPanel(wins: recentWins),
          ],

          if (showStats) ...[
            const SizedBox(height: 16),
            _SessionStatsPanel(
              totalSpins: totalSpins,
              rtp: rtp,
            ),
          ],

          if (showPaytable) ...[
            const SizedBox(height: 16),
            _PaytablePanel(gddSymbols: gddSymbols),
          ],

          if (showRules) ...[
            const SizedBox(height: 16),
            _RulesPanel(config: gameConfig),
          ],
        ],
      ),
    );
  }
}

/// Paytable panel showing symbol pay values
/// Uses GDD symbols when available, falls back to defaults
class _PaytablePanel extends StatelessWidget {
  /// GDD symbols from imported Game Design Document
  final List<GddSymbol> gddSymbols;

  const _PaytablePanel({this.gddSymbols = const []});

  // Default symbol data — fallback when no GDD imported
  static const List<_SymbolPayData> _defaultSymbols = [
    // High paying (HP1-HP4)
    _SymbolPayData('HP1 (Seven)', '7', [20.0, 100.0, 500.0], isHighPay: true),
    _SymbolPayData('HP2 (Bar)', '▬', [15.0, 75.0, 300.0], isHighPay: true),
    _SymbolPayData('HP3 (Bell)', '🔔', [10.0, 50.0, 200.0], isHighPay: true),
    _SymbolPayData('HP4 (Cherry)', '🍒', [8.0, 40.0, 150.0], isHighPay: true),
    // Low paying (LP1-LP6)
    _SymbolPayData('LP1 (Lemon)', '🍋', [5.0, 25.0, 100.0]),
    _SymbolPayData('LP2 (Orange)', '🍊', [4.0, 20.0, 80.0]),
    _SymbolPayData('LP3 (Grape)', '🍇', [3.0, 15.0, 60.0]),
    _SymbolPayData('LP4 (Apple)', '🍏', [2.0, 10.0, 40.0]),
    _SymbolPayData('LP5 (Strawberry)', '🍓', [1.0, 5.0, 20.0]),
    _SymbolPayData('LP6 (Blueberry)', '🫐', [1.0, 5.0, 20.0]),
  ];

  static const List<_SpecialSymbolData> _defaultSpecials = [
    _SpecialSymbolData(
      'WILD',
      '★',
      _SlotTheme.gold,
      'Substitutes for all symbols except Scatter',
      [50.0, 200.0, 1000.0],
    ),
    _SpecialSymbolData(
      'SCATTER',
      '◆',
      _SlotTheme.jackpotMinor,
      '3+ anywhere triggers Free Spins',
      [2.0, 5.0, 20.0],
    ),
    _SpecialSymbolData(
      'BONUS',
      '♦',
      _SlotTheme.jackpotMajor,
      '3+ on reels 2-4 triggers Bonus Game',
      null,
    ),
  ];

  /// Convert GDD symbol to display data
  _SymbolPayData _gddToPayData(GddSymbol gdd) {
    // Convert payouts map to array [3x, 4x, 5x]
    final pays = <double>[];
    for (var i = 3; i <= 5; i++) {
      pays.add(gdd.payouts[i] ?? 0.0);
    }

    // Get emoji based on tier/name
    final icon = _getSymbolEmoji(gdd);

    // High pay = premium, high tier
    final isHighPay = gdd.tier == SymbolTier.premium ||
        gdd.tier == SymbolTier.high;

    return _SymbolPayData(gdd.name, icon, pays, isHighPay: isHighPay);
  }

  /// Get emoji for symbol based on name/tier
  String _getSymbolEmoji(GddSymbol gdd) {
    final name = gdd.name.toLowerCase();
    // Theme-based emoji mapping
    if (name.contains('zeus') || name.contains('thunder')) return '⚡';
    if (name.contains('poseidon') || name.contains('trident')) return '🔱';
    if (name.contains('hades') || name.contains('death')) return '💀';
    if (name.contains('athena') || name.contains('wisdom')) return '🦉';
    if (name.contains('dragon')) return '🐉';
    if (name.contains('phoenix') || name.contains('fire')) return '🔥';
    if (name.contains('tiger')) return '🐅';
    if (name.contains('lion')) return '🦁';
    if (name.contains('eagle') || name.contains('bird')) return '🦅';
    if (name.contains('wolf')) return '🐺';
    if (name.contains('crown') || name.contains('king')) return '👑';
    if (name.contains('diamond')) return '💎';
    if (name.contains('gem') || name.contains('jewel')) return '💍';
    if (name.contains('gold') || name.contains('coin')) return '🪙';
    if (name.contains('treasure') || name.contains('chest')) return '📦';
    if (name.contains('sword')) return '⚔️';
    if (name.contains('shield')) return '🛡️';
    if (name.contains('helmet')) return '⛑️';
    if (name.contains('star')) return '⭐';
    if (name.contains('moon')) return '🌙';
    if (name.contains('sun')) return '☀️';
    if (name.contains('heart')) return '❤️';
    if (name.contains('ace') || name.contains('a')) return '🂡';
    if (name.contains('king') || name.contains('k')) return '🂮';
    if (name.contains('queen') || name.contains('q')) return '🂭';
    if (name.contains('jack') || name.contains('j')) return '🂫';
    if (name.contains('10') || name.contains('ten')) return '🔟';
    if (name.contains('9') || name.contains('nine')) return '9️⃣';
    // Tier-based fallback
    switch (gdd.tier) {
      case SymbolTier.premium: return '👑';
      case SymbolTier.high: return '💎';
      case SymbolTier.mid: return '🎲';
      case SymbolTier.low: return '🃏';
      case SymbolTier.wild: return '★';
      case SymbolTier.scatter: return '◆';
      case SymbolTier.bonus: return '♦';
      case SymbolTier.special: return '✦';
    }
  }

  /// Convert GDD special symbol to display data
  _SpecialSymbolData? _gddToSpecialData(GddSymbol gdd) {
    final pays = <double>[];
    for (var i = 3; i <= 5; i++) {
      pays.add(gdd.payouts[i] ?? 0.0);
    }

    final icon = _getSymbolEmoji(gdd);
    Color color;
    String description;

    if (gdd.isWild || gdd.tier == SymbolTier.wild) {
      color = _SlotTheme.gold;
      description = 'Substitutes for all symbols except Scatter';
    } else if (gdd.isScatter || gdd.tier == SymbolTier.scatter) {
      color = _SlotTheme.jackpotMinor;
      description = '3+ anywhere triggers Free Spins';
    } else if (gdd.isBonus || gdd.tier == SymbolTier.bonus) {
      color = _SlotTheme.jackpotMajor;
      description = '3+ triggers Bonus Game';
    } else {
      return null; // Not a special symbol
    }

    return _SpecialSymbolData(
      gdd.name,
      icon,
      color,
      description,
      pays.any((p) => p > 0) ? pays : null,
    );
  }

  /// Get symbol list (GDD or defaults)
  List<_SymbolPayData> get _symbols {
    if (gddSymbols.isEmpty) return _defaultSymbols;

    // Filter out special symbols, convert the rest
    return gddSymbols
        .where((s) => !s.isWild && !s.isScatter && !s.isBonus &&
            s.tier != SymbolTier.wild &&
            s.tier != SymbolTier.scatter &&
            s.tier != SymbolTier.bonus)
        .map(_gddToPayData)
        .toList();
  }

  /// Get special symbols (GDD or defaults)
  List<_SpecialSymbolData> get _specials {
    if (gddSymbols.isEmpty) return _defaultSpecials;

    final specials = <_SpecialSymbolData>[];
    for (final gdd in gddSymbols) {
      final special = _gddToSpecialData(gdd);
      if (special != null) specials.add(special);
    }
    return specials.isEmpty ? _defaultSpecials : specials;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _SlotTheme.bgPanel.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _SlotTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Row(
              children: [
                const Icon(Icons.table_chart, color: _SlotTheme.gold, size: 18),
                const SizedBox(width: 8),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [_SlotTheme.gold, Colors.amber],
                  ).createShader(bounds),
                  child: const Text(
                    'PAYTABLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Column headers
            Row(
              children: [
                const SizedBox(width: 70),
                Expanded(
                  child: Text(
                    '×3',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '×4',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '×5',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Regular symbols
            ..._symbols.map((s) => _buildSymbolRow(s)),

            const Divider(color: _SlotTheme.border, height: 24),

            // Special symbols
            const Text(
              'SPECIAL SYMBOLS',
              style: TextStyle(
                color: _SlotTheme.gold,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            ..._specials.map((s) => _buildSpecialRow(s)),
          ],
        ),
      ),
    );
  }

  Widget _buildSymbolRow(_SymbolPayData symbol) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Symbol icon & name
          SizedBox(
            width: 70,
            child: Row(
              children: [
                Text(
                  symbol.icon,
                  style: TextStyle(
                    fontSize: 16,
                    color: symbol.isHighPay ? _SlotTheme.gold : Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    symbol.name,
                    style: TextStyle(
                      color: symbol.isHighPay ? _SlotTheme.gold : _SlotTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: symbol.isHighPay ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Pay values
          ...symbol.pays.map((pay) => Expanded(
                child: Text(
                  pay.toStringAsFixed(0),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: symbol.isHighPay ? Colors.amber[300] : Colors.white70,
                    fontSize: 11,
                    fontWeight: symbol.isHighPay ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSpecialRow(_SpecialSymbolData symbol) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: symbol.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: symbol.color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                symbol.icon,
                style: TextStyle(fontSize: 20, color: symbol.color),
              ),
              const SizedBox(width: 8),
              Text(
                symbol.name,
                style: TextStyle(
                  color: symbol.color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            symbol.description,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 10,
            ),
          ),
          if (symbol.pays != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Pays: ', style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                Text(
                  '×3: ${symbol.pays![0].toStringAsFixed(0)}  ×4: ${symbol.pays![1].toStringAsFixed(0)}  ×5: ${symbol.pays![2].toStringAsFixed(0)}',
                  style: TextStyle(color: symbol.color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SymbolPayData {
  final String name;
  final String icon;
  final List<double> pays;
  final bool isHighPay;

  const _SymbolPayData(this.name, this.icon, this.pays, {this.isHighPay = false});
}

class _SpecialSymbolData {
  final String name;
  final String icon;
  final Color color;
  final String description;
  final List<double>? pays;

  const _SpecialSymbolData(this.name, this.icon, this.color, this.description, this.pays);
}

/// Rules panel showing game rules
/// Game rules configuration data
class _GameRulesConfig {
  final String name;
  final int reels;
  final int rows;
  final int paylines;
  final double targetRtp;
  final String volatility;
  final bool freeSpinsEnabled;
  final int freeSpinsMin;
  final int freeSpinsMax;
  final double freeSpinsMultiplier;
  final bool cascadesEnabled;
  final int maxCascadeSteps;
  final bool holdSpinEnabled;
  final bool gambleEnabled;
  final bool jackpotEnabled;

  const _GameRulesConfig({
    this.name = 'Synthetic Slot',
    this.reels = 5,
    this.rows = 3,
    this.paylines = 20,
    this.targetRtp = 96.5,
    this.volatility = 'Medium',
    this.freeSpinsEnabled = true,
    this.freeSpinsMin = 8,
    this.freeSpinsMax = 15,
    this.freeSpinsMultiplier = 2.0,
    this.cascadesEnabled = true,
    this.maxCascadeSteps = 8,
    this.holdSpinEnabled = false,
    this.gambleEnabled = true,
    this.jackpotEnabled = true,
  });

  /// Parse from engine config JSON
  factory _GameRulesConfig.fromJson(Map<String, dynamic> json) {
    final grid = json['grid'] as Map<String, dynamic>? ?? {};
    final features = json['features'] as Map<String, dynamic>? ?? {};
    final volatility = json['volatility'] as Map<String, dynamic>? ?? {};
    final freeSpinsRange = features['free_spins_range'] as List? ?? [8, 15];

    return _GameRulesConfig(
      name: json['name'] as String? ?? 'Synthetic Slot',
      reels: grid['reels'] as int? ?? 5,
      rows: grid['rows'] as int? ?? 3,
      paylines: 20, // Standard for 5x3
      targetRtp: (json['target_rtp'] as num?)?.toDouble() ?? 96.5,
      volatility: _volatilityLabel(volatility),
      freeSpinsEnabled: features['free_spins_enabled'] as bool? ?? true,
      freeSpinsMin: (freeSpinsRange.isNotEmpty ? freeSpinsRange[0] : 8) as int,
      freeSpinsMax: (freeSpinsRange.length > 1 ? freeSpinsRange[1] : 15) as int,
      freeSpinsMultiplier:
          (features['free_spins_multiplier'] as num?)?.toDouble() ?? 2.0,
      cascadesEnabled: features['cascades_enabled'] as bool? ?? true,
      maxCascadeSteps: features['max_cascade_steps'] as int? ?? 8,
      holdSpinEnabled: features['hold_spin_enabled'] as bool? ?? false,
      gambleEnabled: features['gamble_enabled'] as bool? ?? true,
      jackpotEnabled: features['jackpot_enabled'] as bool? ?? true,
    );
  }

  static String _volatilityLabel(Map<String, dynamic> vol) {
    final hitRate = (vol['hit_rate'] as num?)?.toDouble() ?? 0.3;
    if (hitRate >= 0.35) return 'Low';
    if (hitRate >= 0.25) return 'Medium';
    if (hitRate >= 0.15) return 'Medium-High';
    return 'High';
  }
}

class _RulesPanel extends StatelessWidget {
  final _GameRulesConfig config;

  const _RulesPanel({this.config = const _GameRulesConfig()});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _SlotTheme.bgPanel.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _SlotTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title with game name
            Row(
              children: [
                const Icon(Icons.info_outline, color: FluxForgeTheme.accentCyan, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config.name.toUpperCase(),
                    style: const TextStyle(
                      color: FluxForgeTheme.accentCyan,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Grid info
            _buildRule('Grid', '${config.reels}×${config.rows} (${config.reels * config.rows} positions)'),
            _buildRule('Paylines', '${config.paylines} fixed paylines, wins pay left to right'),

            // Wild/Scatter (always present)
            _buildRule('Wild', 'Substitutes for all symbols except Scatter'),
            _buildRule('Scatter', '3+ triggers Free Spins'),

            // Free Spins (if enabled)
            if (config.freeSpinsEnabled)
              _buildRule(
                'Free Spins',
                '${config.freeSpinsMin}-${config.freeSpinsMax} spins with ${config.freeSpinsMultiplier}x multiplier',
              ),

            // Cascades (if enabled)
            if (config.cascadesEnabled)
              _buildRule(
                'Cascades',
                'Winning symbols removed, new symbols fall (max ${config.maxCascadeSteps} steps)',
              ),

            // Hold & Spin (if enabled)
            if (config.holdSpinEnabled)
              _buildRule('Hold & Spin', 'Lock symbols for respins'),

            // Gamble (if enabled)
            if (config.gambleEnabled)
              _buildRule('Gamble', 'Double or nothing on any win'),

            // Jackpots (if enabled)
            if (config.jackpotEnabled)
              _buildRule('Jackpots', '4-tier progressive: Mini, Minor, Major, Grand'),

            const Divider(color: _SlotTheme.border, height: 16),

            // RTP and Volatility
            _buildRule('RTP', 'Theoretical return: ${config.targetRtp.toStringAsFixed(1)}%'),
            _buildRule('Volatility', config.volatility),
          ],
        ),
      ),
    );
  }

  Widget _buildRule(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _InfoButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onTap,
  });

  @override
  State<_InfoButton> createState() => _InfoButtonState();
}

class _InfoButtonState extends State<_InfoButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 50,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: widget.isActive
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : (_isHovered
                    ? _SlotTheme.bgSurface
                    : _SlotTheme.bgPanel.withOpacity(0.8)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isActive
                  ? FluxForgeTheme.accentBlue
                  : (_isHovered ? _SlotTheme.borderLight : _SlotTheme.border),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: widget.isActive
                    ? FluxForgeTheme.accentBlue
                    : _SlotTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isActive
                      ? FluxForgeTheme.accentBlue
                      : _SlotTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentWin {
  final double amount;
  final String tier;
  final DateTime time;

  _RecentWin({required this.amount, required this.tier, required this.time});
}

class _RecentWinsPanel extends StatelessWidget {
  final List<_RecentWin> wins;

  const _RecentWinsPanel({required this.wins});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _SlotTheme.bgPanel.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _SlotTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'RECENT WINS',
            style: TextStyle(
              color: _SlotTheme.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Divider(color: _SlotTheme.border, height: 12),
          if (wins.isEmpty)
            const Text(
              'No wins yet',
              style: TextStyle(color: _SlotTheme.textMuted, fontSize: 11),
            )
          else
            ...wins.take(5).map((win) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '\$${win.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: _getWinColor(win.tier),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        win.tier,
                        style: TextStyle(
                          color: _getWinColor(win.tier).withOpacity(0.7),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Color _getWinColor(String tier) {
    return switch (tier) {
      'ULTRA' => _SlotTheme.winUltra,
      'EPIC' => _SlotTheme.winEpic,
      'MEGA' => _SlotTheme.winMega,
      'BIG' => _SlotTheme.winBig,
      _ => _SlotTheme.winSmall,
    };
  }
}

class _SessionStatsPanel extends StatelessWidget {
  final int totalSpins;
  final double rtp;

  const _SessionStatsPanel({
    required this.totalSpins,
    required this.rtp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _SlotTheme.bgPanel.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _SlotTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SESSION STATS',
            style: TextStyle(
              color: _SlotTheme.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Divider(color: _SlotTheme.border, height: 12),
          _buildStatRow('Spins', '$totalSpins'),
          _buildStatRow(
            'RTP',
            '${rtp.toStringAsFixed(1)}%',
            color: rtp >= 96
                ? FluxForgeTheme.accentGreen
                : (rtp >= 90 ? _SlotTheme.textPrimary : FluxForgeTheme.accentOrange),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _SlotTheme.textMuted,
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? _SlotTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// G2. MENU PANEL
// =============================================================================

class _MenuPanel extends StatelessWidget {
  final VoidCallback onPaytable;
  final VoidCallback onRules;
  final VoidCallback onHistory;
  final VoidCallback onStats;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onClose;

  const _MenuPanel({
    required this.onPaytable,
    required this.onRules,
    required this.onHistory,
    required this.onStats,
    required this.onSettings,
    required this.onHelp,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _SlotTheme.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _SlotTheme.border),
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
              const Row(
                children: [
                  Icon(Icons.menu, color: _SlotTheme.textSecondary, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'MENU',
                    style: TextStyle(
                      color: _SlotTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: _SlotTheme.textSecondary, size: 18),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(color: _SlotTheme.border, height: 16),

          // Menu items
          _MenuItem(icon: Icons.table_chart, label: 'Paytable', onTap: onPaytable),
          _MenuItem(icon: Icons.info_outline, label: 'Rules', onTap: onRules),
          _MenuItem(icon: Icons.history, label: 'History', onTap: onHistory),
          _MenuItem(icon: Icons.analytics, label: 'Statistics', onTap: onStats),
          const Divider(color: _SlotTheme.border, height: 12),
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

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
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
            color: _isHovered ? FluxForgeTheme.accentBlue.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: _isHovered ? FluxForgeTheme.accentBlue : _SlotTheme.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isHovered ? FluxForgeTheme.accentBlue : _SlotTheme.textPrimary,
                  fontSize: 13,
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

  // P6: Recording
  final bool isRecording;
  final bool hideUiForRecording;
  final VoidCallback onRecordingToggle;
  final VoidCallback onHideUiToggle;

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
    this.isRecording = false,
    this.hideUiForRecording = false,
    required this.onRecordingToggle,
    required this.onHideUiToggle,
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
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _SlotTheme.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _SlotTheme.border),
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
              const Row(
                children: [
                  Icon(Icons.settings, color: _SlotTheme.textSecondary, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'SETTINGS',
                    style: TextStyle(
                      color: _SlotTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: _SlotTheme.textSecondary, size: 18),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(color: _SlotTheme.border, height: 20),

          // Volume slider
          const Text(
            'MASTER VOLUME',
            style: TextStyle(
              color: _SlotTheme.textMuted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                volume == 0 ? Icons.volume_off : Icons.volume_up,
                color: _SlotTheme.textSecondary,
                size: 18,
              ),
              Expanded(
                child: Slider(
                  value: volume,
                  onChanged: onVolumeChanged,
                  activeColor: FluxForgeTheme.accentBlue,
                  inactiveColor: _SlotTheme.bgSurface,
                ),
              ),
              Text(
                '${(volume * 100).toInt()}%',
                style: const TextStyle(
                  color: _SlotTheme.textSecondary,
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
          const Text(
            'GRAPHICS QUALITY',
            style: TextStyle(
              color: _SlotTheme.textMuted,
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

          const Divider(color: _SlotTheme.border, height: 24),

          // P6: Device Section
          const Text(
            '📱 DEVICE',
            style: TextStyle(
              color: _SlotTheme.textMuted,
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
                        : _SlotTheme.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? FluxForgeTheme.accentBlue.withOpacity(0.5)
                          : _SlotTheme.border.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(device.icon, size: 14,
                        color: isSelected ? FluxForgeTheme.accentBlue : _SlotTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        device.label,
                        style: TextStyle(
                          color: isSelected ? FluxForgeTheme.accentBlue : _SlotTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const Divider(color: _SlotTheme.border, height: 24),

          // P6: Theme Section
          const Text(
            '🎨 THEME',
            style: TextStyle(
              color: _SlotTheme.textMuted,
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
                    color: _SlotTheme.bgMid.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _SlotTheme.border.withOpacity(0.5)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SlotThemePreset?>(
                      value: comparisonTheme,
                      isDense: true,
                      hint: const Text('Compare', style: TextStyle(color: _SlotTheme.textMuted, fontSize: 12)),
                      icon: const Icon(Icons.arrow_drop_down, color: _SlotTheme.textSecondary, size: 18),
                      dropdownColor: _SlotTheme.bgDark,
                      style: const TextStyle(color: _SlotTheme.textPrimary, fontSize: 12),
                      items: [
                        const DropdownMenuItem<SlotThemePreset?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ...SlotThemePreset.values.map((theme) {
                          return DropdownMenuItem(
                            value: theme,
                            child: Text(theme.label),
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

          const Divider(color: _SlotTheme.border, height: 24),

          // P6: Recording Section
          const Text(
            '🎬 RECORDING',
            style: TextStyle(
              color: _SlotTheme.textMuted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onRecordingToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isRecording
                    ? FluxForgeTheme.accentRed.withOpacity(0.2)
                    : _SlotTheme.bgSurface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isRecording
                      ? FluxForgeTheme.accentRed.withOpacity(0.5)
                      : _SlotTheme.border.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isRecording ? Icons.stop : Icons.fiber_manual_record,
                    size: 16,
                    color: isRecording ? FluxForgeTheme.accentRed : _SlotTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isRecording ? 'Stop Recording' : 'Start Recording',
                    style: TextStyle(
                      color: isRecording ? FluxForgeTheme.accentRed : _SlotTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SettingToggle(
            icon: Icons.visibility_off,
            label: 'Hide UI for recording',
            isOn: hideUiForRecording,
            onToggle: onHideUiToggle,
          ),

          // P6: Debug Section (debug mode only)
          if (kDebugMode) ...[
            const Divider(color: _SlotTheme.border, height: 24),
            const Text(
              '🔧 DEBUG',
              style: TextStyle(
                color: _SlotTheme.textMuted,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isOn
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : (_isHovered ? _SlotTheme.bgSurface : _SlotTheme.bgDark),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isOn
                  ? FluxForgeTheme.accentBlue
                  : _SlotTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: widget.isOn
                    ? FluxForgeTheme.accentBlue
                    : _SlotTheme.textMuted,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isOn
                      ? _SlotTheme.textPrimary
                      : _SlotTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.isOn
                      ? FluxForgeTheme.accentBlue
                      : _SlotTheme.bgSurface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 150),
                  alignment: widget.isOn
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
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
                  : (_isHovered ? _SlotTheme.bgSurface : _SlotTheme.bgDark),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.isSelected
                    ? FluxForgeTheme.accentBlue
                    : _SlotTheme.border,
              ),
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.isSelected
                      ? Colors.white
                      : _SlotTheme.textSecondary,
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
  /// When null, uses context.read<SlotLabProjectProvider>() or legacy fallback
  final SlotLabProjectProvider? projectProvider;

  const PremiumSlotPreview({
    super.key,
    required this.onExit,
    this.reels = 5,
    this.rows = 3,
    this.isFullscreen = false,
    this.projectProvider,
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

  // Session
  double _balance = 1000.0;
  int _vipLevel = 3;
  double _totalBet = 0.0;
  double _totalWin = 0.0;
  int _totalSpins = 0;
  int _wins = 0;
  int _losses = 0;
  final List<_RecentWin> _recentWins = [];

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

  // Bet settings
  int _lines = 25;
  double _coinValue = 0.10;
  int _betLevel = 5;
  double get _totalBetAmount => _lines * _coinValue * _betLevel;

  // Game rules config (loaded from engine)
  _GameRulesConfig _gameConfig = const _GameRulesConfig();

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
  bool _isFullscreen = true;

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

  // P6: RECORDING STATE
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  bool _hideUiForRecording = false;
  static const _recordingChannel = MethodChannel('fluxforge/screen_recording');

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
  bool _showPaytable = false;
  bool _showRules = false;
  bool _showHistory = false;
  bool _showStats = false;
  bool _showWinPresenter = false;
  bool _showGambleScreen = false;
  String _currentWinTier = '';
  double _currentWinAmount = 0.0;
  double _pendingWinAmount = 0.0; // Win waiting to be collected or gambled
  int? _gambleCardRevealed; // 0-3 for cards, null if not revealed
  bool? _gambleWon; // Result of gamble

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC STATE — PSP-P0 Audio-Visual Synchronization
  // ═══════════════════════════════════════════════════════════════════════════

  /// Tracks which reels have visually stopped (for staggered audio triggering)
  late List<bool> _reelsStopped;

  /// Pending result for win stage triggering after reveal
  SlotLabSpinResult? _pendingResultForWinStage;

  /// Timers for scheduled reel stops (canceled on dispose)
  final List<Timer> _reelStopTimers = [];

  // Coin values
  static const List<double> _coinValues = [0.01, 0.02, 0.05, 0.10, 0.20, 0.50, 1.00];

  @override
  void initState() {
    super.initState();
    _reelsStopped = List.filled(widget.reels, true); // Start as stopped
    _initAnimations();
    _loadSettings(); // Load persisted settings
    _loadGameConfig(); // Load game rules from engine

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(PremiumSlotPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Grid dimensions changed — reset reel state arrays
    if (oldWidget.reels != widget.reels || oldWidget.rows != widget.rows) {
      debugPrint('[PremiumSlotPreview] 📐 Grid changed: ${oldWidget.reels}x${oldWidget.rows} → ${widget.reels}x${widget.rows}');
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

    // Apply loaded settings to FFI
    NativeFFI.instance.setBusMute(2, !_isMusicOn);
    NativeFFI.instance.setBusMute(1, !_isSfxOn);
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

  /// Load game rules configuration from engine
  void _loadGameConfig() {
    try {
      final configJson = NativeFFI.instance.slotLabExportConfig();
      if (configJson != null && configJson.isNotEmpty) {
        final json = Map<String, dynamic>.from(
          (configJson.startsWith('{'))
              ? (Map<String, dynamic>.from(
                  const JsonDecoder().convert(configJson) as Map))
              : {},
        );
        if (json.isNotEmpty && mounted) {
          setState(() {
            _gameConfig = _GameRulesConfig.fromJson(json);
          });
        }
      }
    } catch (e) {
      // Fallback to defaults if config loading fails
      debugPrint('[PSP] Failed to load game config: $e');
    }
  }

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

      _recentWins.insert(
        0,
        _RecentWin(
          amount: jackpotAmount,
          tier: 'JACKPOT $tier',
          time: DateTime.now(),
        ),
      );
      if (_recentWins.length > 10) _recentWins.removeLast();
    });
  }

  @override
  void dispose() {
    _jackpotTickController.dispose();
    _focusNode.dispose();
    // Cancel any pending Visual-Sync timers
    for (final timer in _reelStopTimers) {
      timer.cancel();
    }
    _reelStopTimers.clear();

    // P6: Cleanup recording and debug timers
    _recordingTimer?.cancel();
    _debugStatsTimer?.cancel();

    super.dispose();
  }

  // === HANDLERS ===

  /// Toggle music bus mute state (bus ID 2 = music)
  void _toggleMusic() {
    setState(() => _isMusicOn = !_isMusicOn);
    // Mute/unmute music bus via FFI
    NativeFFI.instance.setBusMute(2, !_isMusicOn);
    _saveSettings();
  }

  /// Toggle SFX bus mute state (bus ID 1 = sfx)
  void _toggleSfx() {
    setState(() => _isSfxOn = !_isSfxOn);
    // Mute/unmute SFX bus via FFI
    NativeFFI.instance.setBusMute(1, !_isSfxOn);
    _saveSettings();
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
  // P6: RECORDING MODE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start screen recording
  Future<void> _startRecording() async {
    try {
      final filename = 'slot_demo_${DateTime.now().toIso8601String().replaceAll(':', '-')}.mp4';
      await _recordingChannel.invokeMethod<String>('startRecording', {
        'filename': filename,
        'fps': 60,
        'quality': 'high',
      });
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingDuration += const Duration(seconds: 1));
        }
      });
    } catch (e) {
      // Recording not available on this platform
      debugPrint('[PSP] Recording not available: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Screen recording not available on this platform'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Stop screen recording
  Future<String?> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final path = await _recordingChannel.invokeMethod<String>('stopRecording');
      setState(() => _isRecording = false);
      return path;
    } catch (e) {
      debugPrint('[PSP] Failed to stop recording: $e');
      setState(() => _isRecording = false);
      return null;
    }
  }

  /// Toggle recording state
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _stopRecording();
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording saved: ${path.split('/').last}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      await _startRecording();
    }
  }

  /// Toggle hide UI for recording
  void _toggleHideUiForRecording() {
    setState(() => _hideUiForRecording = !_hideUiForRecording);
  }

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
  void _forceOutcome(int outcomeIndex) {
    final provider = context.read<SlotLabProvider>();
    switch (outcomeIndex) {
      case 1:
        provider.spinForced(ForcedOutcome.lose);
      case 2:
        provider.spinForced(ForcedOutcome.smallWin);
      case 3:
        provider.spinForced(ForcedOutcome.bigWin);
      case 4:
        provider.spinForced(ForcedOutcome.megaWin);
      case 5:
        provider.spinForced(ForcedOutcome.freeSpins);
      case 6:
        provider.spinForced(ForcedOutcome.jackpotGrand);
      case 7:
        provider.spinForced(ForcedOutcome.nearMiss);
      case 8:
        provider.spinForced(ForcedOutcome.cascade);
      case 9:
        provider.spinForced(ForcedOutcome.epicWin);
      case 0:
        provider.spinForced(ForcedOutcome.ultraWin);
    }
  }

  void _handleSpin(SlotLabProvider provider) {
    // ═══════════════════════════════════════════════════════════════════════════
    // DEBUG LOGGING — Trace spin flow
    // ═══════════════════════════════════════════════════════════════════════════
    debugPrint('[PremiumSlotPreview] 🎰 _handleSpin called');
    debugPrint('[PremiumSlotPreview]   initialized=${provider.initialized}');
    debugPrint('[PremiumSlotPreview]   isPlayingStages=${provider.isPlayingStages}');
    debugPrint('[PremiumSlotPreview]   isWinPresentationActive=${provider.isWinPresentationActive}');
    debugPrint('[PremiumSlotPreview]   balance=$_balance, totalBet=$_totalBetAmount');

    if (!provider.initialized) {
      debugPrint('[PremiumSlotPreview] ❌ BLOCKED: Provider not initialized!');
      return;
    }
    if (provider.isPlayingStages) {
      debugPrint('[PremiumSlotPreview] ❌ BLOCKED: Already playing stages');
      return;
    }
    if (_balance < _totalBetAmount) {
      debugPrint('[PremiumSlotPreview] ❌ BLOCKED: Insufficient balance');
      return;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // V13: WIN PRESENTATION SKIP — Fade out first, then spin
    // If win presentation is active, request skip and wait for fade-out to complete
    // ═══════════════════════════════════════════════════════════════════════════
    if (provider.isWinPresentationActive) {
      debugPrint('[PremiumSlotPreview] 🎬 Win presentation active — requesting skip with fade-out');
      provider.requestSkipPresentation(() {
        debugPrint('[PremiumSlotPreview] ✅ Skip complete — proceeding with spin');
        _executeSpinAfterSkip(provider);
      });
      return;
    }

    // No presentation active — proceed immediately with spin
    _executeSpinAfterSkip(provider);
  }

  /// V13: Execute spin after skip fade-out is complete (or when no skip needed)
  /// This contains the actual spin logic extracted from _handleSpin
  void _executeSpinAfterSkip(SlotLabProvider provider) {
    setState(() {
      _balance -= _totalBetAmount;
      _totalBet += _totalBetAmount;
      _totalSpins++;
      // Progressive contribution based on bet amount (1% of bet goes to jackpot pool)
      _progressiveContribution = _jackpotContributionRate * _totalBetAmount;
      // Add small amount to each jackpot per bet
      _miniJackpot += _totalBetAmount * 0.005;
      _minorJackpot += _totalBetAmount * 0.003;
      _majorJackpot += _totalBetAmount * 0.002;
      _grandJackpot += _totalBetAmount * 0.001;
      _showWinPresenter = false;
    });

    // ═══════════════════════════════════════════════════════════════════════
    // VISUAL-SYNC: Schedule reel stop callbacks IMMEDIATELY on spin start
    // Result will be stored when it arrives for win stage triggering
    // ═══════════════════════════════════════════════════════════════════════
    _scheduleVisualSyncCallbacks(null);

    debugPrint('[PremiumSlotPreview] ✅ Calling provider.spin()...');
    provider.spin().then((result) {
      if (result != null && mounted) {
        debugPrint('[PremiumSlotPreview] ✅ spin() returned result: ${result.spinId}');
        debugPrint('[PremiumSlotPreview]   stages count: ${provider.lastStages.length}');
        debugPrint('[PremiumSlotPreview]   isPlayingStages: ${provider.isPlayingStages}');
        // Store result for win stage triggering (used by _onAllReelsStopped)
        _pendingResultForWinStage = result;
        _processResult(result);
      } else {
        debugPrint('[PremiumSlotPreview] ❌ spin() returned NULL! Provider may not be initialized.');
      }
    });
  }

  void _handleForcedSpin(SlotLabProvider provider, ForcedOutcome outcome) {
    if (provider.isPlayingStages) return;
    if (_balance < _totalBetAmount) return;

    // V13: Handle skip with fade-out for forced spin as well
    if (provider.isWinPresentationActive) {
      provider.requestSkipPresentation(() {
        _executeForcedSpinAfterSkip(provider, outcome);
      });
      return;
    }

    _executeForcedSpinAfterSkip(provider, outcome);
  }

  /// V13: Execute forced spin after skip fade-out is complete
  void _executeForcedSpinAfterSkip(SlotLabProvider provider, ForcedOutcome outcome) {
    setState(() {
      _balance -= _totalBetAmount;
      _totalBet += _totalBetAmount;
      _totalSpins++;
      _showWinPresenter = false;
    });

    // ═══════════════════════════════════════════════════════════════════════
    // VISUAL-SYNC: Schedule reel stop callbacks IMMEDIATELY on spin start
    // ═══════════════════════════════════════════════════════════════════════
    _scheduleVisualSyncCallbacks(null);

    provider.spinForced(outcome).then((result) {
      if (result != null && mounted) {
        // Store result for win stage triggering (used by _onAllReelsStopped)
        _pendingResultForWinStage = result;
        _processResult(result);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC METHODS — PSP-P0 Audio-Visual Synchronization
  // ═══════════════════════════════════════════════════════════════════════════

  /// Schedule Visual-Sync callbacks for staggered reel stops
  /// Called at SPIN START — triggers REEL_STOP_0..4 at visual stop moments
  void _scheduleVisualSyncCallbacks(SlotLabSpinResult? pendingResult) {
    // Cancel any existing timers
    for (final timer in _reelStopTimers) {
      timer.cancel();
    }
    _reelStopTimers.clear();

    // Reset reels stopped state
    setState(() {
      _reelsStopped = List.filled(widget.reels, false);
      _pendingResultForWinStage = pendingResult;
    });

    // ═══════════════════════════════════════════════════════════════════════
    // SPIN_START — DISABLED: Engine stages handle this via SlotLabProvider._playStages()
    // Keeping visual-sync here caused DUPLICATE TRIGGERS (audio played twice)
    // ═══════════════════════════════════════════════════════════════════════
    // eventRegistry.triggerStage('SPIN_START'); // REMOVED - causes double trigger

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
        // REEL_STOP_i — DISABLED: Engine stages handle this via SlotLabProvider._playStages()
        // Keeping visual-sync here caused DUPLICATE TRIGGERS (audio played twice)
        // ═══════════════════════════════════════════════════════════════════
        // eventRegistry.triggerStage('REEL_STOP_$i'); // REMOVED - causes double trigger

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
    // ANTICIPATION_ON — DISABLED: Engine generates ANTICIPATION stages with
    // correct timestamps. Visual-sync timing causes mismatch/duplicates.
    // See: crates/rf-slot-lab/src/spin.rs:170 — Stage::AnticipationOn
    // ═══════════════════════════════════════════════════════════════════════
    // final result = _pendingResultForWinStage;
    // if (result == null) return;
    //
    // final tier = _winTierFromEngine(result.bigWinTier) ?? _getWinTier(result.totalWin);
    // final shouldAnticipate = tier == 'EPIC' || tier == 'ULTRA' || tier == 'MEGA';
    //
    // if (shouldAnticipate) {
    //   eventRegistry.triggerStage('ANTICIPATION_ON');
    // }
  }

  /// Called when ALL reels have visually stopped
  /// NOTE: WIN stages are now handled by engine via SlotLabProvider._playStages()
  void _onAllReelsStopped() {
    // ═══════════════════════════════════════════════════════════════════════
    // REVEAL — DISABLED: Engine stages handle timing via SlotLabProvider._playStages()
    // Visual-sync timing is NOT synchronized with engine timestamps, causing
    // REVEAL to fire BETWEEN engine REEL_STOP stages (wrong order!)
    // ═══════════════════════════════════════════════════════════════════════
    // eventRegistry.triggerStage('REVEAL'); // REMOVED — causes timing mismatch

    // ═══════════════════════════════════════════════════════════════════════
    // WIN STAGES — DISABLED: Engine generates WIN_PRESENT and BigWinTier stages
    // with correct timestamps. Visual-sync triggering causes duplicates.
    // ═══════════════════════════════════════════════════════════════════════
    // final result = _pendingResultForWinStage;
    // if (result != null && result.isWin) {
    //   _triggerWinStage(result);
    // }

    // Clear pending result
    _pendingResultForWinStage = null;
  }

  /// Trigger appropriate WIN stage based on win tier
  void _triggerWinStage(SlotLabSpinResult result) {
    final tier = _winTierFromEngine(result.bigWinTier) ?? _getWinTier(result.totalWin);

    switch (tier) {
      case 'ULTRA':
        eventRegistry.triggerStage('WIN_ULTRA');
        break;
      case 'EPIC':
        eventRegistry.triggerStage('WIN_EPIC');
        break;
      case 'MEGA':
        eventRegistry.triggerStage('WIN_MEGA');
        break;
      case 'BIG':
        eventRegistry.triggerStage('WIN_BIG');
        break;
      default:
        eventRegistry.triggerStage('WIN_SMALL');
    }

    // Also trigger WIN_PRESENT for general win celebration
    eventRegistry.triggerStage('WIN_PRESENT');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // END VISUAL-SYNC METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _processResult(SlotLabSpinResult result) {
    final winAmount = result.totalWin * _totalBetAmount;

    // Reset progressive contribution after spin
    _progressiveContribution = 0.0;

    setState(() {
      _totalWin += winAmount;
      // DON'T add to balance immediately - store as pending for Collect/Gamble
      _pendingWinAmount = winAmount;

      if (result.isWin) {
        _wins++;
        // Use engine's win tier classification when available, fallback to manual
        _currentWinTier = _winTierFromEngine(result.bigWinTier) ?? _getWinTier(result.totalWin);
        _currentWinAmount = winAmount;

        // Jackpot chance based on win tier from ENGINE RNG (not local random)
        // Uses probability bands tied to win size - engine determines the win,
        // we just apply jackpot chance based on that result
        final jackpotRoll = (result.totalWin * 1000).toInt() % 100; // Deterministic from engine result
        if (result.totalWin >= 100) {
          // ULTRA win - chance for GRAND jackpot
          if (jackpotRoll < 1) {
            _awardJackpot('GRAND');
            return;
          } else if (jackpotRoll < 6) {
            _awardJackpot('MAJOR');
            return;
          }
        } else if (result.totalWin >= 50) {
          // EPIC win - chance for MAJOR/MINOR
          if (jackpotRoll < 2) {
            _awardJackpot('MAJOR');
            return;
          } else if (jackpotRoll < 10) {
            _awardJackpot('MINOR');
            return;
          }
        } else if (result.totalWin >= 25) {
          // MEGA win - chance for MINOR/MINI
          if (jackpotRoll < 5) {
            _awardJackpot('MINOR');
            return;
          } else if (jackpotRoll < 20) {
            _awardJackpot('MINI');
            return;
          }
        } else if (result.totalWin >= 10) {
          // BIG win - small chance for MINI
          if (jackpotRoll < 10) {
            _awardJackpot('MINI');
            return;
          }
        }

        // Only show plaque for BIG+ wins (5x or higher = tier is not empty)
        if (_currentWinTier.isNotEmpty) {
          // Big win - show presenter for Collect/Gamble
          _showWinPresenter = true;
          _recentWins.insert(
            0,
            _RecentWin(
              amount: winAmount,
              tier: _currentWinTier,
              time: DateTime.now(),
            ),
          );
          if (_recentWins.length > 10) {
            _recentWins.removeLast();
          }
        } else {
          // Small win (below 5x) - auto-collect immediately, no plaque
          _balance += _pendingWinAmount;
          _pendingWinAmount = 0.0;
        }
      } else {
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

  /// Legacy fallback when projectProvider is not available
  WinTierResult? _legacyGetWinTierResult(double totalWin, double bet) {
    final ratio = totalWin / bet;

    // Big Win threshold (legacy: 20x)
    if (ratio >= 20) {
      final int bigTierId;
      if (ratio >= 500) {
        bigTierId = 5;
      } else if (ratio >= 250) {
        bigTierId = 4;
      } else if (ratio >= 100) {
        bigTierId = 3;
      } else if (ratio >= 50) {
        bigTierId = 2;
      } else {
        bigTierId = 1;
      }

      return WinTierResult(
        isBigWin: true,
        multiplier: ratio,
        regularTier: null,
        bigWinTier: BigWinTierDefinition(
          tierId: bigTierId,
          fromMultiplier: bigTierId == 1 ? 20 : (bigTierId == 2 ? 50 : (bigTierId == 3 ? 100 : (bigTierId == 4 ? 250 : 500))),
          toMultiplier: bigTierId == 5 ? double.infinity : (bigTierId == 4 ? 500 : (bigTierId == 3 ? 250 : (bigTierId == 2 ? 100 : 50))),
          displayLabel: _legacyBigWinLabel(bigTierId),
        ),
        bigWinMaxTier: bigTierId,
      );
    }

    // Regular win (legacy - just return empty tier for small wins)
    final regularTierId = ratio >= 5 ? 4 : (ratio >= 2 ? 2 : 1);
    return WinTierResult(
      isBigWin: false,
      multiplier: ratio,
      regularTier: WinTierDefinition(
        tierId: regularTierId,
        fromMultiplier: 0,
        toMultiplier: 20,
        displayLabel: '',
        rollupDurationMs: _legacyRegularRollupDuration(regularTierId),
        rollupTickRate: 15,
      ),
      bigWinTier: null,
      bigWinMaxTier: null,
    );
  }

  /// Legacy regular tier rollup duration mapping
  int _legacyRegularRollupDuration(int tierId) {
    return switch (tierId) {
      0 => 500,
      1 => 500,
      2 => 1000,
      3 => 1500,
      4 => 2000,
      5 => 2500,
      6 => 3000,
      _ => 500,
    };
  }

  /// Legacy big win label mapping (fallback only)
  String _legacyBigWinLabel(int tierId) {
    return switch (tierId) {
      1 => 'BIG WIN!',
      2 => 'MEGA WIN!',
      3 => 'SUPER WIN!',
      4 => 'EPIC WIN!',
      5 => 'ULTRA WIN!',
      _ => 'BIG WIN!',
    };
  }

  /// P5: Get win tier string for UI display
  /// Returns 'BIG', 'MEGA', etc. for legacy compatibility
  String _getWinTier(double win) {
    // win parameter is actually totalWin in this context
    // We need bet amount to calculate ratio properly
    final bet = _totalBetAmount > 0 ? _totalBetAmount : 1.0;
    final tierResult = _getP5WinTierResult(win, bet);

    if (tierResult == null || !tierResult.isBigWin) return '';

    // Map P5 big win tier ID to legacy string
    return switch (tierResult.bigWinMaxTier) {
      1 => 'BIG',
      2 => 'MEGA',
      3 => 'SUPER',
      4 => 'EPIC',
      5 => 'ULTRA',
      _ => 'BIG',
    };
  }

  /// P5: Get display label from configurable tier system
  /// Returns user-configured label instead of hardcoded "BIG WIN!" etc.
  String _getP5WinTierDisplayLabel(double totalWin, double bet) {
    final tierResult = _getP5WinTierResult(totalWin, bet);
    if (tierResult == null) return '';

    if (tierResult.isBigWin) {
      return tierResult.bigWinTier?.displayLabel ?? 'BIG WIN!';
    }

    return '';
  }

  /// Convert engine win tier to UI tier string
  /// Returns empty string for small wins (no plaque)
  String? _winTierFromEngine(SlotLabWinTier? tier) {
    if (tier == null) return null;
    switch (tier) {
      case SlotLabWinTier.ultraWin:
        return 'ULTRA';
      case SlotLabWinTier.epicWin:
        return 'EPIC';
      case SlotLabWinTier.megaWin:
        return 'MEGA';
      case SlotLabWinTier.bigWin:
        return 'BIG';
      case SlotLabWinTier.win:
        // Small win - no plaque
        return '';
      case SlotLabWinTier.none:
        return null;
    }
  }

  /// Collect pending win - add to balance and close presenter
  void _collectWin() {
    setState(() {
      _balance += _pendingWinAmount;
      _pendingWinAmount = 0.0;
      _showWinPresenter = false;
      _showGambleScreen = false;
    });
  }

  /// Start gamble game - show gamble screen
  void _startGamble() {
    setState(() {
      _showWinPresenter = false;
      _showGambleScreen = true;
      _gambleCardRevealed = null;
      _gambleWon = null;
    });
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
      debugPrint('[PremiumSlotPreview] ⏹ STOP pressed — stopping all reels immediately');
      provider.stopStagePlayback();
    }
  }

  void _handleMaxBet() {
    setState(() {
      _lines = 25;
      _coinValue = _coinValues.last;
      _betLevel = 10;
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

    final provider = context.read<SlotLabProvider>();

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        if (_showMenuPanel) {
          setState(() => _showMenuPanel = false);
        } else if (_showSettingsPanel) {
          setState(() => _showSettingsPanel = false);
        } else if (_showWinPresenter) {
          setState(() => _showWinPresenter = false);
        } else {
          widget.onExit();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.space:
        // ═══════════════════════════════════════════════════════════════════════
        // EMBEDDED MODE CHECK — Skip SPACE handling when NOT in fullscreen
        // Let slot_lab_screen global handler handle SPACE in embedded mode
        // This prevents double-handling where both handlers process same event
        // ═══════════════════════════════════════════════════════════════════════
        if (!widget.isFullscreen) {
          debugPrint('[PremiumSlotPreview] ⏭️ SPACE ignored (embedded mode — global handler will handle)');
          return KeyEventResult.ignored;
        }

        // ═══════════════════════════════════════════════════════════════════════
        // DEBOUNCE CHECK — Prevents double-trigger from rapid key presses
        // ═══════════════════════════════════════════════════════════════════════
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastSpaceKeyTime < _spaceKeyDebounceMs) {
          debugPrint('[PremiumSlotPreview] ⏱️ SPACE debounced (${now - _lastSpaceKeyTime}ms < ${_spaceKeyDebounceMs}ms)');
          return KeyEventResult.handled;
        }
        _lastSpaceKeyTime = now;

        // ═══════════════════════════════════════════════════════════════════════
        // SPACE KEY LOGIC (FIXED):
        // - isReelsSpinning = true ONLY while reels are visually spinning
        // - isPlayingStages = true during BOTH spin AND win presentation
        //
        // Correct behavior:
        // - During reel spin → STOP (stop reels immediately)
        // - During win presentation → SPIN (skip presentation, start new spin)
        // - Idle → SPIN (start new spin)
        // ═══════════════════════════════════════════════════════════════════════
        debugPrint('[PremiumSlotPreview] 🎰 SPACE pressed — isReelsSpinning=${provider.isReelsSpinning}, isPlayingStages=${provider.isPlayingStages}');

        // STOP only when reels are actually spinning (not during win presentation)
        if (provider.isReelsSpinning) {
          _handleStop();
        } else {
          // Either idle OR win presentation — start new spin (handleSpin manages skip)
          _handleSpin(provider);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyM:
        _toggleMusic();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyS:
        setState(() => _showStats = !_showStats);
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

      // P6: D = Debug toolbar toggle
      case LogicalKeyboardKey.keyD:
        if (kDebugMode) _toggleDebugToolbar();
        return kDebugMode ? KeyEventResult.handled : KeyEventResult.ignored;

      // P6: R = Recording toggle
      case LogicalKeyboardKey.keyR:
        _toggleRecording();
        return KeyEventResult.handled;

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
    final provider = context.watch<SlotLabProvider>();
    final projectProvider = context.watch<SlotLabProjectProvider>();
    // isSpinning: True during all stages (spin + win presentation) — for disabling Spin button
    final isSpinning = provider.isPlayingStages;
    // isReelsSpinning: True ONLY while reels are visually spinning — for STOP button
    final isReelsActuallySpinning = provider.isReelsSpinning;
    final isInitialized = provider.initialized;
    final canSpin = isInitialized && _balance >= _totalBetAmount && !isSpinning;
    final sessionRtp = _totalBet > 0 ? (_totalWin / _totalBet * 100) : 0.0;
    // Get GDD symbols from project provider (if imported)
    final gddSymbols = projectProvider.gddSymbols;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: _SlotTheme.bgDeep,
        body: Stack(
          children: [
            // Main layout
            Column(
              children: [
                // A. Header Zone
                _HeaderZone(
                  balance: _balance,
                  vipLevel: _vipLevel,
                  isMusicOn: _isMusicOn,
                  isSfxOn: _isSfxOn,
                  isFullscreen: _isFullscreen,
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
                  onFullscreenToggle: () {},
                  onExit: widget.onExit,
                  // P6: Device simulation
                  deviceSimulation: _deviceSimulation,
                  onDeviceChanged: _setDeviceSimulation,
                  // P6: Theme
                  currentTheme: _themeA,
                  onThemeChanged: _setThemeA,
                  // P6: Recording
                  isRecording: _isRecording,
                  recordingDuration: _recordingDuration,
                  onRecordingToggle: _toggleRecording,
                  // P6: Debug
                  showDebugToolbar: _showDebugToolbar,
                  onDebugToggle: _toggleDebugToolbar,
                ),

                // P6: Debug Toolbar (below header when active)
                if (_showDebugToolbar)
                  _DebugToolbar(
                    fps: _currentFps,
                    activeVoices: _activeVoices,
                    memoryMb: _memoryUsageMb,
                    showStageTrace: _showStageTrace,
                    onStageTraceToggle: () => setState(() => _showStageTrace = !_showStageTrace),
                    onForceOutcome: _forceOutcome,
                  ),

                // B. Jackpot Zone
                _JackpotZone(
                  miniJackpot: _miniJackpot,
                  minorJackpot: _minorJackpot,
                  majorJackpot: _majorJackpot,
                  grandJackpot: _grandJackpot,
                  progressiveContribution: _progressiveContribution,
                ),

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

                // F. Control Bar
                _ControlBar(
                  lines: _lines,
                  maxLines: 25,
                  coinValue: _coinValue,
                  coinValues: _coinValues,
                  betLevel: _betLevel,
                  maxBetLevel: 10,
                  totalBet: _totalBetAmount,
                  isSpinning: isSpinning,
                  showStopButton: isReelsActuallySpinning, // STOP only during reel spinning
                  isAutoSpin: _isAutoSpin,
                  autoSpinCount: _autoSpinRemaining,
                  isTurbo: _isTurbo,
                  canSpin: canSpin,
                  onLinesChanged: (v) => setState(() => _lines = v),
                  onCoinChanged: (v) => setState(() => _coinValue = v),
                  onBetLevelChanged: (v) => setState(() => _betLevel = v),
                  onMaxBet: _handleMaxBet,
                  onSpin: () => _handleSpin(provider),
                  onStop: _handleStop,
                  onAutoSpinToggle: _handleAutoSpinToggle,
                  onTurboToggle: _toggleTurbo,
                  onAfterInteraction: () => _focusNode.requestFocus(), // Restore focus after button clicks
                ),
              ],
            ),

            // G. Info Panels (left side)
            _InfoPanels(
              showPaytable: _showPaytable,
              showRules: _showRules,
              showHistory: _showHistory,
              showStats: _showStats,
              recentWins: _recentWins,
              totalSpins: _totalSpins,
              rtp: sessionRtp,
              gameConfig: _gameConfig,
              gddSymbols: gddSymbols,
              onPaytableToggle: () => setState(() {
                _showPaytable = !_showPaytable;
                _showRules = false;
              }),
              onRulesToggle: () => setState(() {
                _showRules = !_showRules;
                _showPaytable = false;
              }),
              onHistoryToggle: () => setState(() => _showHistory = !_showHistory),
              onStatsToggle: () => setState(() => _showStats = !_showStats),
            ),

            // D. Win Presenter (overlay)
            if (_showWinPresenter)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _collectWin,
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    child: _WinPresenter(
                      winAmount: _pendingWinAmount,
                      winTier: _currentWinTier,
                      multiplier: _multiplier.toDouble(),
                      showCollect: true,
                      showGamble: false, // Gamble disabled for basic mockup
                      onCollect: _collectWin,
                      onGamble: _startGamble,
                    ),
                  ),
                ),
              ),

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
                  onPaytable: () => setState(() {
                    _showPaytable = true;
                    _showRules = false;
                    _showMenuPanel = false;
                  }),
                  onRules: () => setState(() {
                    _showRules = true;
                    _showPaytable = false;
                    _showMenuPanel = false;
                  }),
                  onHistory: () => setState(() {
                    _showHistory = !_showHistory;
                    _showMenuPanel = false;
                  }),
                  onStats: () => setState(() {
                    _showStats = !_showStats;
                    _showMenuPanel = false;
                  }),
                  onSettings: () => setState(() {
                    _showSettingsPanel = true;
                    _showMenuPanel = false;
                  }),
                  onHelp: () {
                    setState(() => _showMenuPanel = false);
                    // Show a simple help dialog
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: _SlotTheme.bgPanel,
                        title: const Text(
                          'Premium Slot Preview',
                          style: TextStyle(color: _SlotTheme.textPrimary),
                        ),
                        content: const Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Audio Testing Sandbox',
                              style: TextStyle(
                                color: FluxForgeTheme.accentCyan,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Keyboard Shortcuts:',
                              style: TextStyle(
                                color: _SlotTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '• SPACE - Spin\n'
                              '• M - Toggle Music\n'
                              '• S - Toggle Stats\n'
                              '• T - Toggle Turbo\n'
                              '• A - Toggle Auto-Spin\n'
                              '• ESC - Exit\n'
                              '• 1-7 - Forced Outcomes (Debug)',
                              style: TextStyle(color: _SlotTheme.textSecondary),
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
                    // P6: Recording
                    isRecording: _isRecording,
                    hideUiForRecording: _hideUiForRecording,
                    onRecordingToggle: _toggleRecording,
                    onHideUiToggle: _toggleHideUiForRecording,
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
    );
  }
}
