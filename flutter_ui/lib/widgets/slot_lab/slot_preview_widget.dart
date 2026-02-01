/// Slot Preview Widget
///
/// Full-screen slot reels - NO header/footer, maximum visibility
/// - Reels fill entire available space
/// - Smooth vertical spinning animation
/// - Premium 3D symbols
/// - Win amount overlay with animated counter
/// - Particle system for Big Win celebrations
/// - Enhanced symbol animations (bounce, glow)
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../../models/win_tier_config.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../providers/slot_lab_provider.dart';
import '../../services/event_registry.dart';
import '../../services/win_analytics_service.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
import 'professional_reel_animation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SLOT SYMBOL DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

class SlotSymbol {
  final int id;
  final String name;
  final String displayChar;
  final List<Color> gradientColors;
  final Color glowColor;
  final bool isSpecial;

  const SlotSymbol({
    required this.id,
    required this.name,
    required this.displayChar,
    required this.gradientColors,
    required this.glowColor,
    this.isSpecial = false,
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // DYNAMIC SYMBOL REGISTRY — Populated from GDD when imported
  // Falls back to default symbols when empty
  // ═══════════════════════════════════════════════════════════════════════════
  static Map<int, SlotSymbol> _dynamicSymbols = {};

  /// Set dynamic symbols from GDD import
  static void setDynamicSymbols(Map<int, SlotSymbol> symbols) {
    _dynamicSymbols = Map.from(symbols);
  }

  /// Clear dynamic symbols (reset to defaults)
  static void clearDynamicSymbols() {
    _dynamicSymbols.clear();
  }

  /// Get effective symbols map (dynamic if set, otherwise defaults)
  static Map<int, SlotSymbol> get effectiveSymbols =>
      _dynamicSymbols.isNotEmpty ? _dynamicSymbols : _defaultSymbols;

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL ID MAPPING — MUST MATCH RUST ENGINE (crates/rf-slot-lab/src/symbols.rs)
  // Rust StandardSymbolSet: HP1=1, HP2=2, HP3=3, HP4=4, LP1=5..LP6=10, WILD=11, SCATTER=12, BONUS=13
  // ═══════════════════════════════════════════════════════════════════════════
  static const Map<int, SlotSymbol> _defaultSymbols = {
    // ═══════════════════════════════════════════════════════════════════════════
    // HIGH PAYING SYMBOLS — PRECIOUS GEM/METAL COLORS (Saturated, Bright, Premium)
    // Design principle: HP uses WARM spectrum (Red→Gold) with high saturation
    // Visual hierarchy: More valuable = brighter, more saturated, warmer
    // ═══════════════════════════════════════════════════════════════════════════
    1: SlotSymbol(
      id: 1, name: 'HP1', displayChar: '7',
      // RUBY RED — Pure crimson, maximum prestige, no pink/orange tint
      gradientColors: [Color(0xFFFF3333), Color(0xFFE60000), Color(0xFF990000)],
      glowColor: Color(0xFFFF0000),
    ),
    2: SlotSymbol(
      id: 2, name: 'HP2', displayChar: '▬',
      // ROYAL GOLD — Rich metallic gold, distinct from yellow fruits
      gradientColors: [Color(0xFFFFDD44), Color(0xFFDAA520), Color(0xFFB8860B)],
      glowColor: Color(0xFFFFCC00),
    ),
    3: SlotSymbol(
      id: 3, name: 'HP3', displayChar: '🔔',
      // BRONZE/COPPER — Warm metallic, completely distinct from any fruit
      gradientColors: [Color(0xFFE8A060), Color(0xFFCD7F32), Color(0xFF8B4513)],
      glowColor: Color(0xFFD4954A),
    ),
    4: SlotSymbol(
      id: 4, name: 'HP4', displayChar: '🍒',
      // HOT PINK/MAGENTA — Warm but distinct, NOT purple (no LP confusion)
      gradientColors: [Color(0xFFFF66AA), Color(0xFFFF1493), Color(0xFFB30059)],
      glowColor: Color(0xFFFF3399),
    ),
    // ═══════════════════════════════════════════════════════════════════════════
    // LOW PAYING SYMBOLS — NATURAL FRUIT COLORS (Cooler, Less Saturated, Muted)
    // Design principle: LP uses COOL spectrum (Green→Blue→Purple) with lower saturation
    // Visual hierarchy: Clearly "lesser value" through muted, cooler tones
    // ═══════════════════════════════════════════════════════════════════════════
    5: SlotSymbol(
      id: 5, name: 'LP1', displayChar: '🍋',
      // LEMON — Pale yellow-green, NOT gold (distinct from HP2)
      gradientColors: [Color(0xFFE8E855), Color(0xFFCDCD00), Color(0xFF9A9A00)],
      glowColor: Color(0xFFD4D400),
    ),
    6: SlotSymbol(
      id: 6, name: 'LP2', displayChar: '🍊',
      // ORANGE — Muted orange, NOT bright like HP colors
      gradientColors: [Color(0xFFE89040), Color(0xFFCC7722), Color(0xFF995511)],
      glowColor: Color(0xFFDD8833),
    ),
    7: SlotSymbol(
      id: 7, name: 'LP3', displayChar: '🍇',
      // GRAPE — DEEP VIOLET/INDIGO, NOT purple-pink like HP4
      gradientColors: [Color(0xFF7744AA), Color(0xFF4B0082), Color(0xFF2E0052)],
      glowColor: Color(0xFF6633AA),
    ),
    8: SlotSymbol(
      id: 8, name: 'LP4', displayChar: '🍏',
      // APPLE GREEN — Cool green, NOT warm/bright
      gradientColors: [Color(0xFF88CC55), Color(0xFF669944), Color(0xFF446622)],
      glowColor: Color(0xFF77BB44),
    ),
    9: SlotSymbol(
      id: 9, name: 'LP5', displayChar: '🍓',
      // STRAWBERRY — Muted coral/salmon, NOT pure red like HP1
      gradientColors: [Color(0xFFDD7766), Color(0xFFBB5544), Color(0xFF883322)],
      glowColor: Color(0xFFCC6655),
    ),
    10: SlotSymbol(
      id: 10, name: 'LP6', displayChar: '🫐',
      // BLUEBERRY — Deep teal/blue-green, cool and muted
      gradientColors: [Color(0xFF5588AA), Color(0xFF336688), Color(0xFF224455)],
      glowColor: Color(0xFF447799),
    ),
    // ═══════════════════════════════════════════════════════════════════════════
    // SPECIAL SYMBOLS — MAXIMUM VISUAL IMPACT (Neon/Electric, Ultra-Bright)
    // Design principle: MUST be instantly recognizable from any HP/LP symbol
    // Uses electric/neon colors that NO other symbol uses
    // ═══════════════════════════════════════════════════════════════════════════
    11: SlotSymbol(
      id: 11, name: 'WILD', displayChar: '★',
      // RAINBOW/IRIDESCENT — Multi-color shimmer effect (white-gold-silver)
      // NOT plain gold (HP2 uses gold now), uses platinum/silver-white
      gradientColors: [Color(0xFFFFFFEE), Color(0xFFE8E8D0), Color(0xFFC0C0A0)],
      glowColor: Color(0xFFFFFFCC), isSpecial: true,
    ),
    12: SlotSymbol(
      id: 12, name: 'SCATTER', displayChar: '◆',
      // ELECTRIC LIME/CHARTREUSE — Neon green-yellow, triggers features
      // NOT magenta (too close to HP4 pink), uses unique neon green
      gradientColors: [Color(0xFFCCFF00), Color(0xFFAADD00), Color(0xFF77AA00)],
      glowColor: Color(0xFFBBEE00), isSpecial: true,
    ),
    13: SlotSymbol(
      id: 13, name: 'BONUS', displayChar: '♦',
      // ELECTRIC CYAN/AQUA — Pure cyan, bonus trigger
      // Distinct from all LP blues (which are teal/muted)
      gradientColors: [Color(0xFF00FFFF), Color(0xFF00DDDD), Color(0xFF009999)],
      glowColor: Color(0xFF00EEEE), isSpecial: true,
    ),
    // Fallback for ID 0 (should not occur in normal operation)
    0: SlotSymbol(
      id: 0, name: 'BLANK', displayChar: '·',
      gradientColors: [Color(0xFF666666), Color(0xFF444444), Color(0xFF333333)],
      glowColor: Color(0xFF666666),
    ),
  };

  /// Legacy alias for compatibility
  static Map<int, SlotSymbol> get symbols => effectiveSymbols;

  /// Get symbol by ID — uses dynamic symbols if set, falls back to defaults
  static SlotSymbol getSymbol(int id) => effectiveSymbols[id] ?? effectiveSymbols[7] ?? _defaultSymbols[7]!; // Fallback to LP3

  // ═══════════════════════════════════════════════════════════════════════════
  // DYNAMIC SCATTER DETECTION — Works with both default and GDD-imported symbols
  // Returns ALL symbol IDs that are scatter-type (name contains 'SCATTER' or 'SCAT')
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all scatter symbol IDs (dynamic detection)
  /// Works with both default symbols (ID 12) and GDD-imported symbols (any ID)
  static Set<int> get scatterSymbolIds {
    final scatterIds = <int>{};
    for (final entry in effectiveSymbols.entries) {
      final name = entry.value.name.toUpperCase();
      // Match "SCATTER", "SCAT", or anything with "SCATTER" in name
      if (name.contains('SCATTER') || name == 'SCAT') {
        scatterIds.add(entry.key);
      }
    }
    // Fallback: if no scatter found, use default ID 12
    if (scatterIds.isEmpty) {
      scatterIds.add(12);
    }
    return scatterIds;
  }

  /// Check if a symbol ID is a scatter symbol (dynamic detection)
  static bool isScatterSymbol(int symbolId) => scatterSymbolIds.contains(symbolId);

  /// Get short label for symbol — MUST MATCH RUST ENGINE
  /// Rust: HP1=1, HP2=2, HP3=3, HP4=4, LP1=5..LP6=10, WILD=11, SCATTER=12, BONUS=13
  String get shortLabel {
    switch (id) {
      case 1: return 'HP1';   // Seven - High Pay 1 (highest)
      case 2: return 'HP2';   // Bar - High Pay 2
      case 3: return 'HP3';   // Bell - High Pay 3
      case 4: return 'HP4';   // Cherry - High Pay 4
      case 5: return 'LP1';   // Lemon - Low Pay 1 (highest of low)
      case 6: return 'LP2';   // Orange - Low Pay 2
      case 7: return 'LP3';   // Grape - Low Pay 3
      case 8: return 'LP4';   // Apple - Low Pay 4
      case 9: return 'LP5';   // Strawberry - Low Pay 5
      case 10: return 'LP6';  // Blueberry - Low Pay 6 (lowest)
      case 11: return 'WILD';
      case 12: return 'SCAT';
      case 13: return 'BONUS';
      case 0: return 'BLANK';
      default: return 'SYM';
    }
  }

  /// Get label color based on symbol type — MUST MATCH RUST ENGINE
  Color get labelColor {
    switch (id) {
      case 11: return const Color(0xFFFFD700);  // WILD - Gold
      case 12: return const Color(0xFFE040FB);  // SCATTER - Purple
      case 13: return const Color(0xFF40C8FF);  // BONUS - Cyan
      case 1:
      case 2:
      case 3:
      case 4: return const Color(0xFFFF4080);   // HP - Red/Pink
      case 5:
      case 6:
      case 7:
      case 8:
      case 9:
      case 10: return const Color(0xFF90CAF9); // LP - Light Blue
      default: return const Color(0xFF666666);  // BLANK/Unknown - Gray
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT PREVIEW WIDGET - FULLSCREEN REELS
// ═══════════════════════════════════════════════════════════════════════════

class SlotPreviewWidget extends StatefulWidget {
  final SlotLabProvider provider;

  /// P5: Project provider for dynamic win tier configuration
  /// When provided, win tier stages use P5 configurable thresholds
  /// When null, falls back to legacy hardcoded thresholds
  final SlotLabProjectProvider? projectProvider;

  final int reels;
  final int rows;

  /// Called when parent's Space key handler should delegate to this widget.
  /// Parent should check [canHandleSpaceKey] before calling [handleSpaceKey].
  final void Function()? onSpaceKeyHandled;

  /// 🔴 CRITICAL: Disable win presentation when used inside PremiumSlotPreview
  /// PremiumSlotPreview has its own _WinPresenter overlay — this prevents DOUBLE PLAQUE
  final bool showWinPresentation;

  const SlotPreviewWidget({
    super.key,
    required this.provider,
    this.projectProvider,
    this.reels = 5,
    this.rows = 3,
    this.onSpaceKeyHandled,
    this.showWinPresentation = true, // Default: show (for standalone usage)
  });

  @override
  State<SlotPreviewWidget> createState() => SlotPreviewWidgetState();
}

/// Public state class so parent can access handleSpaceKey() via GlobalKey
class SlotPreviewWidgetState extends State<SlotPreviewWidget>
    with TickerProviderStateMixin {
  // ═══════════════════════════════════════════════════════════════════════════
  // PROFESSIONAL REEL ANIMATION SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════
  late ProfessionalReelAnimationController _reelAnimController;
  Ticker? _animationTicker;
  final Set<int> _reelStoppedFlags = {}; // Track which reels have triggered audio

  // ═══════════════════════════════════════════════════════════════════════════
  // IGT-STYLE SEQUENTIAL REEL STOP BUFFER
  // Animation callbacks can fire OUT OF ORDER. We must trigger audio SEQUENTIALLY.
  // If Reel 4 finishes before Reel 3, we buffer it and wait for Reel 3.
  // ═══════════════════════════════════════════════════════════════════════════
  int _nextExpectedReelIndex = 0; // Which reel we're waiting for (0, 1, 2, 3, 4)
  final Set<int> _pendingReelStops = {}; // Buffered out-of-order reel stops

  // Legacy controllers (kept for win effects)
  late AnimationController _winPulseController;
  late Animation<double> _winPulseAnimation;

  // Win amount overlay animations
  late AnimationController _winAmountController;
  late Animation<double> _winAmountScale;
  late Animation<double> _winAmountOpacity;
  late AnimationController _winCounterController;

  // Symbol bounce animation for wins
  late AnimationController _symbolBounceController;
  late Animation<double> _symbolBounceAnimation;

  // Particle system with object pool (eliminates GC pressure)
  final List<_WinParticle> _particles = [];
  final _ParticlePool _particlePool = _ParticlePool();
  late AnimationController _particleController;

  // Anticipation/Near Miss animations
  late AnimationController _anticipationController;
  late Animation<double> _anticipationPulse;
  late AnimationController _nearMissController;
  late Animation<double> _nearMissShake;

  // Cascade animations
  late AnimationController _cascadePopController;
  late Animation<double> _cascadePopAnimation;

  // P1.2: Win line grow animation (line "grows" from first to last symbol)
  late AnimationController _lineGrowController;
  double _lineDrawProgress = 1.0; // 0.0 = no line, 1.0 = full line

  List<List<int>> _displayGrid = [];
  List<List<int>> _targetGrid = [];
  bool _isSpinning = false;
  bool _spinFinalized = false; // Prevents re-trigger after finalize
  bool _symbolHighlightPreTriggered = false; // P0.2: Prevents double-trigger of WIN_SYMBOL_HIGHLIGHT
  String? _lastProcessedSpinId; // Track which spin result we've processed
  int _spinStartTimeMs = 0; // Timestamp when spin started (for Event Log ordering)
  Set<int> _winningReels = {};
  Set<String> _winningPositions = {}; // "reel,row" format

  // ═══════════════════════════════════════════════════════════════════════════
  // V14: PER-SYMBOL WIN HIGHLIGHT — Symbol-specific audio triggers
  // When HP1 is part of winning line → trigger WIN_SYMBOL_HIGHLIGHT_HP1
  // Each symbol type gets its own highlight stage for audio design flexibility
  // ═══════════════════════════════════════════════════════════════════════════
  Map<String, Set<String>> _winningPositionsBySymbol = {}; // symbolName → {"reel,row", ...}
  Set<String> _winningSymbolNames = {}; // Unique symbol names that are winning

  // ═══════════════════════════════════════════════════════════════════════════
  // PER-REEL ANTICIPATION SYSTEM — Condition-based (scatter detection)
  // Industry standard: Anticipation triggers when 2+ scatters land, extends remaining reels
  // ═══════════════════════════════════════════════════════════════════════════
  bool _isAnticipation = false;
  bool _isNearMiss = false;
  Set<int> _anticipationReels = {}; // Reels currently showing anticipation
  Set<String> _nearMissPositions = {}; // Positions that "just missed"
  final Map<int, Timer> _anticipationTimers = {}; // Per-reel anticipation timers
  final Map<int, double> _anticipationProgress = {}; // Per-reel progress (0.0 → 1.0)
  final Map<int, int> _anticipationTensionLevel = {}; // Per-reel tension level (1-4)
  final Map<int, String> _anticipationReason = {}; // Per-reel reason (scatter, bonus, wild, jackpot)
  static const int _anticipationDurationMs = 3000; // 3 seconds per reel
  // NOTE: Scatter symbol ID is now DYNAMIC — use SlotSymbol.isScatterSymbol(id) instead
  // This supports both default symbols (ID 12) and GDD-imported symbols (any ID)
  static const int _scattersNeededForAnticipation = 2; // 2 scatters needed to trigger
  Set<int> _scatterReels = {}; // Reels that have landed with scatter symbols

  // P2.2: Anticipation particle trail system
  // Intensity escalates per tension level (L1: 5 particles/tick, L2: 10, L3: 15, L4: 20)
  final List<_AnticipationParticle> _anticipationParticles = [];
  final _AnticipationParticlePool _anticipationParticlePool = _AnticipationParticlePool();

  // ═══════════════════════════════════════════════════════════════════════════
  // P7.2.1: SEQUENTIAL ANTICIPATION MODE — Reels stop one-by-one during anticipation
  // Industry standard (IGT, Pragmatic Play, NetEnt): Each reel waits for previous to
  // complete its anticipation phase before stopping. Creates maximum tension.
  // ═══════════════════════════════════════════════════════════════════════════
  bool _sequentialAnticipationMode = false; // When true, reels stop sequentially
  final List<int> _sequentialAnticipationQueue = []; // Queue of reels waiting to stop
  int? _currentSequentialReel; // Reel currently in anticipation sequence

  // P3.1: Camera zoom — zoom intensity escalates with number of reels in anticipation
  // Industry standard: subtle zoom (1.02-1.08) creates focus and tension
  double _anticipationZoom = 1.0; // 1.0 = no zoom, 1.08 = max zoom
  static const double _anticipationZoomBase = 1.02; // Base zoom per reel
  static const double _anticipationZoomMax = 1.08; // Maximum zoom

  // Industry-standard color progression by tension level
  // L1=Gold, L2=Orange, L3=Red-Orange, L4=Red
  static const Map<int, Color> _tensionColors = {
    1: Color(0xFFFFD700), // Gold
    2: Color(0xFFFFA500), // Orange
    3: Color(0xFFFF6347), // Red-Orange (Tomato)
    4: Color(0xFFFF4500), // Red (OrangeRed)
  };

  // Cascade state
  bool _isCascading = false;
  Set<String> _cascadePopPositions = {}; // Positions being popped
  int _cascadeStep = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // V2: LANDING IMPACT EFFECT — Scale pop only (flash disabled per user request)
  // ═══════════════════════════════════════════════════════════════════════════
  final Map<int, double> _landingPopScale = {}; // Per-reel scale pop (1.0 - 1.05 - 1.0)

  // ═══════════════════════════════════════════════════════════════════════════
  // SPINNING→DECEL TRANSITION FIX — Prevent symbol jump when phase changes
  // Store last spinning verticalOffset per reel to interpolate smoothly
  // ═══════════════════════════════════════════════════════════════════════════
  final Map<int, double> _lastSpinningOffset = {}; // Per-reel last offset in spinning phase
  bool _screenShakeActive = false; // Screen shake on last reel (big wins only)

  // ═══════════════════════════════════════════════════════════════════════════
  // V6: ENHANCED SYMBOL HIGHLIGHT — Staggered popup for winning symbols
  // Industry standard: individual symbol "pop" on first highlight
  // ═══════════════════════════════════════════════════════════════════════════
  final Map<String, double> _symbolPopScale = {}; // Per-position popup scale (1.0 → 1.15 → 1.0)
  final Map<String, double> _symbolPopRotation = {}; // Micro-rotation wiggle (radians)
  static const double _symbolPopMaxScale = 1.15; // Peak popup scale
  // P1.3: Sequential L→R wave with 100ms offset between positions
  static const int _symbolPopStaggerMs = 100; // Industry standard: 100ms per position

  // ═══════════════════════════════════════════════════════════════════════════
  // V7: ROLLUP VISUAL FEEDBACK — Meter + counter shake for engaging rollup
  // Industry standard: visual feedback makes rollup feel substantial
  // ═══════════════════════════════════════════════════════════════════════════
  double _rollupProgress = 0.0; // 0.0 to 1.0 for progress meter
  double _counterShakeScale = 1.0; // Scale pulse on tick (1.0 → 1.08 → 1.0)
  bool _isRollingUp = false; // Currently in rollup phase

  // ═══════════════════════════════════════════════════════════════════════════
  // V8: ENHANCED WIN PLAQUE — Screen flash, dramatic entrance, particles
  // Industry standard: NetEnt, Pragmatic Play dramatic win celebration
  // ═══════════════════════════════════════════════════════════════════════════
  late AnimationController _screenFlashController;
  late Animation<double> _screenFlashOpacity;
  late AnimationController _plaqueGlowController;
  late Animation<double> _plaqueGlowPulse;
  bool _showScreenFlash = false; // True during initial flash

  // Win display state
  double _displayedWinAmount = 0;
  double _targetWinAmount = 0;
  String _winTier = ''; // BIG, SUPER, MEGA, EPIC, ULTRA (no plaque for small wins)

  // Industry-standard rollup animation state
  // When true, display uses _formatRtlRollupDisplay() for counting-up effect
  bool _useRtlRollup = false;
  double _rtlRollupProgress = 0.0; // 0.0 = start (0), 1.0 = target reached

  // ═══════════════════════════════════════════════════════════════════════════
  // TIER PROGRESSION SYSTEM — Progressive reveal from BIG to final tier
  // Each tier displays for 4 seconds, building excitement to the final tier
  // ═══════════════════════════════════════════════════════════════════════════
  String _currentDisplayTier = ''; // Currently shown tier label on plaque
  Timer? _tierProgressionTimer;
  int _tierProgressionIndex = 0;
  List<String> _tierProgressionList = []; // Tiers to progress through (e.g., ['BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3'])
  bool _isInTierProgression = false;

  // Tier progression timing constants
  static const int _bigWinIntroDurationMs = 500;  // BIG_WIN_INTRO duration
  static const int _tierDisplayDurationMs = 4000;  // Each tier shows for 4s
  static const int _bigWinEndDurationMs = 4000;    // BIG_WIN_END duration

  // All possible tiers in order — generic names per CLAUDE.md (no hardcoded labels)
  static const List<String> _allTiersInOrder = ['BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_TIER_4', 'BIG_WIN_TIER_5'];

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN LINE PRESENTATION — Cycles through each winning line
  // ═══════════════════════════════════════════════════════════════════════════
  List<LineWin> _lineWinsForPresentation = [];
  int _currentPresentingLineIndex = 0;
  bool _isShowingWinLines = false;
  Timer? _winLineCycleTimer;
  Set<String> _currentLinePositions = {}; // Positions for currently shown line
  static const Duration _winLineCycleDuration = Duration(milliseconds: 1500);

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN AUDIO FLOW — 3-Phase sequential presentation
  // Phase 1: Symbol Highlight (1050ms) — winning symbols glow/bounce
  // Phase 2: Tier Plaque + Coin Counter Rollup — "BIG WIN!" + counter animation
  // Phase 3: Win Lines (visual lines only, NO symbol info like "3x Grapes")
  // Win lines start AFTER rollup completes (strict sequential)
  // ═══════════════════════════════════════════════════════════════════════════
  Timer? _rollupTickTimer;
  int _rollupTickCount = 0;
  static const int _rollupTicksTotal = 15; // Default ~1.5s rollup duration at 100ms intervals

  // Timing constants
  static const int _symbolHighlightDurationMs = 1050; // 3 cycles × 350ms
  static const int _symbolPulseCycleMs = 350;
  static const int _symbolPulseCycles = 3;

  // Tier-specific rollup durations (ms) — V9: MUCH FASTER + RTL digit animation
  // Empty string ('') uses default for small wins (< 5x)
  // User request: "rollup mora da bude dosta brzi"
  static const Map<String, int> _rollupDurationByTier = {
    'BIG_WIN_TIER_1': 800,      // First major tier (5x-15x) — was 2500ms
    'BIG_WIN_TIER_2': 1200,     // Second tier (15x-30x) — was 4000ms
    'BIG_WIN_TIER_3': 2000,     // Third tier (30x-60x) — was 7000ms
    'BIG_WIN_TIER_4': 3500,     // Fourth tier (60x-100x) — was 12000ms
    'BIG_WIN_TIER_5': 6000,     // Maximum (100x+) — was 20000ms
  };
  static const int _defaultRollupDuration = 800;  // Small wins — SAME as BIG WIN

  // Tier-specific rollup tick rate (ticks per second) — V9: Faster ticks
  static const Map<String, int> _rollupTickRateByTier = {
    'BIG_WIN_TIER_1': 20,     // First major tier — was 12
    'BIG_WIN_TIER_2': 18,     // Second tier — was 10
    'BIG_WIN_TIER_3': 15,     // Third tier — was 8
    'BIG_WIN_TIER_4': 12,     // Fourth tier — was 6
    'BIG_WIN_TIER_5': 8,      // Maximum — was 4
  };
  static const int _defaultRollupTickRate = 20;  // Small wins — SAME as BIG WIN

  // Currency formatter for win display — Industry standard: 2 decimal places
  // Examples: 1234.50 → "1,234.50" | 50.00 → "50.00" | 1234567.89 → "1,234,567.89"
  static final _currencyFormatter = NumberFormat.currency(
    symbol: '',
    decimalDigits: 2,
    locale: 'en_US',
  );

  final _random = math.Random();
  List<List<int>> _spinSymbols = [];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeGrid();
    widget.provider.addListener(_onProviderUpdate);

    // P0.3: Connect anticipation callbacks for visual-audio sync
    // Wrapper needed for named parameter support (tensionLevel)
    widget.provider.onAnticipationStart = (reelIndex, reason, {int tensionLevel = 1}) {
      _onProviderAnticipationStart(reelIndex, reason, tensionLevel: tensionLevel);
    };
    widget.provider.onAnticipationEnd = _onProviderAnticipationEnd;
  }

  @override
  void didUpdateWidget(SlotPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reels != widget.reels || oldWidget.rows != widget.rows) {
      _disposeControllers();
      _initializeControllers();
      _initializeGrid();
    }
  }

  void _initializeControllers() {
    // ═══════════════════════════════════════════════════════════════════════════
    // PROFESSIONAL REEL ANIMATION - Phase-based with precise timing
    // ═══════════════════════════════════════════════════════════════════════════
    _reelAnimController = ProfessionalReelAnimationController(
      reelCount: widget.reels,
      rowCount: widget.rows,
      profile: ReelTimingProfile.normal, // Must match Rust TimingConfig::normal()
    );

    // Connect reel stop callback to audio triggering
    _reelAnimController.onReelStop = _onReelStopVisual;
    _reelAnimController.onAllReelsStopped = _onAllReelsStoppedVisual;

    // Create ticker for continuous animation updates
    _animationTicker = createTicker((_) {
      _reelAnimController.tick();

      // Backup finalize check: Widget spinning but controller done
      // Primary callback is onAllReelsStopped (line 538), this is just safety net
      if (_isSpinning && !_spinFinalized && !_reelAnimController.isSpinning) {
        _onAllReelsStoppedVisual();
      }

      if (mounted) setState(() {}); // Trigger rebuild for visual update
    });
    _animationTicker!.start();

    _winPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _winPulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _winPulseController, curve: Curves.easeInOut),
    );

    // Win amount overlay animation
    _winAmountController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _winAmountScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _winAmountController,
        curve: Curves.elasticOut,
      ),
    );
    _winAmountOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _winAmountController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    // Win counter rollup animation
    _winCounterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(_updateWinCounter);

    // Symbol bounce for winning symbols — Industry standard: 3 pulse cycles × 350ms = 1050ms
    _symbolBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _symbolPulseCycleMs),
    );
    _symbolBounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _symbolBounceController, curve: Curves.easeInOut),
    );

    // Particle system controller
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..addListener(_updateParticles);

    // Anticipation animation - glowing pulse effect
    _anticipationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
    _anticipationPulse = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _anticipationController, curve: Curves.easeInOut),
    );

    // Near miss shake animation
    _nearMissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _nearMissShake = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _nearMissController, curve: Curves.elasticOut),
    );

    // Cascade pop animation (symbols exploding/popping)
    _cascadePopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _cascadePopAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _cascadePopController, curve: Curves.easeInBack),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // V8: SCREEN FLASH + PLAQUE GLOW — Dramatic entrance animations
    // Industry standard: Flash on entrance, pulsing glow during display
    // ═══════════════════════════════════════════════════════════════════════════
    _screenFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _screenFlashOpacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _screenFlashController, curve: Curves.easeOut),
    );

    // Pulsing glow effect for plaque (faster than win pulse)
    _plaqueGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
    _plaqueGlowPulse = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _plaqueGlowController, curve: Curves.easeInOut),
    );

    // P1.2: Win line grow animation (250ms for line to "grow" from first to last symbol)
    _lineGrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
      setState(() {
        _lineDrawProgress = _lineGrowController.value;
      });
    });

    _spinSymbols = List.generate(
      widget.reels,
      (_) => List.generate(20, (_) => _random.nextInt(10)),
    );
  }

  void _updateWinCounter() {
    if (!mounted) return;
    setState(() {
      _displayedWinAmount = ui.lerpDouble(0, _targetWinAmount, _winCounterController.value) ?? 0;
      // V9: Update RTL progress for digit reveal animation
      _rtlRollupProgress = _winCounterController.value;
    });
  }

  void _updateParticles() {
    if (!mounted) return;
    setState(() {
      // Update win particles
      for (final particle in _particles) {
        particle.update();
      }
      // Return dead particles to pool before removing
      final deadParticles = _particles.where((p) => p.isDead).toList();
      _particlePool.releaseAll(deadParticles);
      _particles.removeWhere((p) => p.isDead);

      // P2.2: Update anticipation particles
      for (final particle in _anticipationParticles) {
        particle.update();
      }
      final deadAnticipationParticles = _anticipationParticles.where((p) => p.isDead).toList();
      _anticipationParticlePool.releaseAll(deadAnticipationParticles);
      _anticipationParticles.removeWhere((p) => p.isDead);

      // P2.2: Emit new anticipation particles for each anticipating reel
      _emitAnticipationParticles();
    });
  }

  /// P2.2: Emit anticipation particles per reel based on tension level
  /// L1: 2 particles/tick, L2: 4, L3: 6, L4: 8
  void _emitAnticipationParticles() {
    if (_anticipationReels.isEmpty) return;

    final reelWidth = 1.0 / widget.reels;

    for (final reelIndex in _anticipationReels) {
      final tensionLevel = _anticipationTensionLevel[reelIndex] ?? 1;
      final color = _tensionColors[tensionLevel] ?? const Color(0xFFFFD700);

      // Particle count escalates with tension level
      final particleCount = tensionLevel * 2; // L1=2, L2=4, L3=6, L4=8

      // Particle size escalates with tension
      final baseSize = 2.0 + tensionLevel * 0.5; // L1=2.5, L2=3, L3=3.5, L4=4

      // Fade speed decreases with tension (particles last longer)
      final fadeSpeed = 0.025 - (tensionLevel * 0.003); // L1=0.022, L4=0.013

      for (int i = 0; i < particleCount; i++) {
        // Random position within reel column
        final reelCenterX = (reelIndex + 0.5) * reelWidth;
        final x = reelCenterX + (_random.nextDouble() - 0.5) * reelWidth * 0.8;
        final y = _random.nextDouble(); // Random vertical position

        // Upward drift with slight horizontal spread
        final vx = (_random.nextDouble() - 0.5) * 0.002;
        final vy = -0.001 - _random.nextDouble() * 0.002 * tensionLevel; // Faster up for higher tension

        _anticipationParticles.add(_anticipationParticlePool.acquire(
          x: x,
          y: y,
          vx: vx,
          vy: vy,
          size: baseSize + _random.nextDouble() * 1.5,
          color: color,
          fadeSpeed: fadeSpeed,
          rotation: _random.nextDouble() * math.pi * 2,
          rotationSpeed: (_random.nextDouble() - 0.5) * 0.1,
        ));
      }
    }
  }

  void _initializeGrid() {
    _displayGrid = List.generate(
      widget.reels,
      (_) => List.generate(widget.rows, (_) => _random.nextInt(10)),
    );
    _targetGrid = List.generate(
      widget.reels,
      (r) => List.from(_displayGrid[r]),
    );
  }

  void _disposeControllers() {
    // Dispose professional animation controller
    _animationTicker?.stop();
    _animationTicker?.dispose();
    _reelAnimController.dispose();

    // Dispose legacy effect controllers
    _winPulseController.dispose();
    _winAmountController.dispose();
    _winCounterController.dispose();
    _symbolBounceController.dispose();
    _particleController.dispose();
    _anticipationController.dispose();
    _nearMissController.dispose();
    _cascadePopController.dispose();
    _lineGrowController.dispose(); // P1.2: Win line grow animation

    // Cancel per-reel anticipation timers
    for (final timer in _anticipationTimers.values) {
      timer.cancel();
    }
    _anticipationTimers.clear();

    // V8: Dispose enhanced plaque controllers
    _screenFlashController.dispose();
    _plaqueGlowController.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC CALLBACKS — Audio triggers on VISUAL reel stop
  // IGT STANDARD: Reels MUST stop in order 0→1→2→3→4, audio fires sequentially
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when a reel VISUALLY stops - uses IGT-style sequential buffer
  /// Animation callbacks can fire OUT OF ORDER. We must trigger audio SEQUENTIALLY.
  void _onReelStopVisual(int reelIndex) {
    if (!mounted) return;

    // Prevent duplicate triggers
    if (_reelStoppedFlags.contains(reelIndex)) return;
    _reelStoppedFlags.add(reelIndex);

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: Update _displayGrid IMMEDIATELY when reel stops
    // This ensures the symbols shown during bouncing stay after stopped phase
    // ═══════════════════════════════════════════════════════════════════════════
    setState(() {
      if (reelIndex < _targetGrid.length && reelIndex < _displayGrid.length) {
        for (int row = 0; row < widget.rows && row < _targetGrid[reelIndex].length; row++) {
          _displayGrid[reelIndex][row] = _targetGrid[reelIndex][row];
        }
      }
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // V2: LANDING IMPACT EFFECT — DISABLED per user request
    // To re-enable: uncomment _triggerLandingImpact(reelIndex);
    // ═══════════════════════════════════════════════════════════════════════════
    // _triggerLandingImpact(reelIndex);

    // ═══════════════════════════════════════════════════════════════════════════
    // IGT-STYLE SEQUENTIAL BUFFER
    // If this reel is the next expected one, trigger audio immediately
    // If not, buffer it and wait for the expected one
    // ═══════════════════════════════════════════════════════════════════════════
    if (reelIndex == _nextExpectedReelIndex) {
      // This is the next expected reel — trigger immediately
      _triggerReelStopAudio(reelIndex);
      _nextExpectedReelIndex++;

      // Flush any buffered reels that are now in sequence
      _flushPendingReelStops();
    } else {
      // Out of order — buffer it for later
      debugPrint('[SlotPreview] 📦 REEL $reelIndex BUFFERED (waiting for reel $_nextExpectedReelIndex)');
      _pendingReelStops.add(reelIndex);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V2: LANDING IMPACT — Scale pop only (flash disabled per user request)
  // ═══════════════════════════════════════════════════════════════════════════
  void _triggerLandingImpact(int reelIndex) {
    // Start at peak scale (no flash)
    setState(() {
      _landingPopScale[reelIndex] = 1.08;
    });

    // Animate scale pop decay (100ms)
    Future.delayed(const Duration(milliseconds: 30), () {
      if (!mounted) return;
      setState(() => _landingPopScale[reelIndex] = 1.05);
    });
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      setState(() => _landingPopScale[reelIndex] = 1.02);
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() => _landingPopScale[reelIndex] = 1.0);
    });
  }

  /// Brief screen shake when last reel lands (anticipation effect)
  void _triggerScreenShake() {
    if (!mounted) return;
    setState(() => _screenShakeActive = true);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() => _screenShakeActive = false);
    });
  }

  /// Triggers REEL_STOP audio for a specific reel with correct timestamp
  ///
  /// AUDIO-VISUAL SYNC: Uses addPostFrameCallback to ensure audio triggers
  /// AFTER the visual frame renders. This guarantees perfect sync because:
  /// 1. Animation callback fires → widget state updates → build() scheduled
  /// 2. Frame renders (visual reel lands)
  /// 3. PostFrameCallback executes → audio triggers
  /// Result: Audio plays exactly when user SEES reel land, not before.
  void _triggerReelStopAudio(int reelIndex) {
    // Stop anticipation for this reel if active
    _stopReelAnticipation(reelIndex);

    // Get RUST PLANNED timestamp for correct Event Log ordering
    double timestampMs = 0.0;
    try {
      final stages = widget.provider.lastStages;
      final matchingStage = stages.firstWhere(
        (s) => s.stageType.toUpperCase() == 'REEL_STOP' && s.rawStage['reel_index'] == reelIndex,
        orElse: () => stages.firstWhere(
          (s) => s.stageType.toUpperCase() == 'REEL_STOP',
          orElse: () => throw StateError('No REEL_STOP stage found'),
        ),
      );
      timestampMs = matchingStage.timestampMs;
    } catch (e) {
      // Fallback to elapsed time if stage not found
      timestampMs = (DateTime.now().millisecondsSinceEpoch - _spinStartTimeMs).toDouble();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AUDIO-VISUAL SYNC FIX: Defer audio trigger to AFTER frame renders
    // This ensures audio plays exactly when user SEES the reel land visually
    // ═══════════════════════════════════════════════════════════════════════════
    final capturedTimestampMs = timestampMs;
    final capturedReelIndex = reelIndex;

    // Capture target grid for symbol land detection inside callback
    final capturedTargetGrid = reelIndex < _targetGrid.length
        ? List<int>.from(_targetGrid[reelIndex])
        : <int>[];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // ═══════════════════════════════════════════════════════════════════════════
      // 1. REEL_STOP AUDIO — Primary reel landing sound
      // ═══════════════════════════════════════════════════════════════════════════
      debugPrint('[SlotPreview] 🎰 REEL $capturedReelIndex STOPPED → triggering REEL_STOP_$capturedReelIndex (rust_ts: ${capturedTimestampMs.toStringAsFixed(0)}ms) [POST-FRAME]');
      eventRegistry.triggerStage('REEL_STOP_$capturedReelIndex', context: {'timestamp_ms': capturedTimestampMs});

      // ═══════════════════════════════════════════════════════════════════════════
      // 2. SPECIAL SYMBOL LAND EVENTS — Trigger when WILD, SCATTER, BONUS land on reel
      // This connects the left panel symbol audio assignments to actual gameplay
      // Symbol IDs: WILD=11, SCATTER=12, BONUS=13 (matches StandardSymbolSet)
      // ═══════════════════════════════════════════════════════════════════════════
      for (int rowIndex = 0; rowIndex < capturedTargetGrid.length; rowIndex++) {
        final symbolId = capturedTargetGrid[rowIndex];
        String? symbolLandStage;

        switch (symbolId) {
          case 11: // WILD
            symbolLandStage = 'SYMBOL_LAND_WILD';
            break;
          case 12: // SCATTER
            symbolLandStage = 'SYMBOL_LAND_SCATTER';
            break;
          case 13: // BONUS
            symbolLandStage = 'SYMBOL_LAND_BONUS';
            break;
        }

        if (symbolLandStage != null) {
          debugPrint('[SlotPreview] ✨ SPECIAL SYMBOL LAND: $symbolLandStage at reel $capturedReelIndex, row $rowIndex [POST-FRAME]');
          eventRegistry.triggerStage(symbolLandStage, context: {
            'reel_index': capturedReelIndex,
            'row_index': rowIndex,
            'symbol_id': symbolId,
            'timestamp_ms': capturedTimestampMs,
          });
        }
      }
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.2: PRE-TRIGGER WIN_SYMBOL_HIGHLIGHT ON LAST REEL
    // Industry standard: Eliminate 50-100ms silence gap between reel stop and win reveal
    // Trigger symbol highlight IMMEDIATELY on last reel stop if there's a win
    // This creates seamless audio: REEL_STOP → WIN_SYMBOL_HIGHLIGHT (no gap)
    // ═══════════════════════════════════════════════════════════════════════════
    if (reelIndex == widget.reels - 1 && !_symbolHighlightPreTriggered) {
      final result = widget.provider.lastResult;
      if (result != null && result.isWin) {
        debugPrint('[SlotPreview] P0.2: Last reel stopped with WIN → pre-triggering WIN_SYMBOL_HIGHLIGHT');

        // Pre-populate winning symbols info (normally done in _finalizeSpin)
        // WILD PRIORITY RULE: When WILD substitutes for another symbol in a win,
        // WILD gets audio priority. Check actual grid symbols, not just lineWin.symbolName.
        _winningPositionsBySymbol.clear();
        _winningSymbolNames.clear();

        // Track WILD symbols in winning positions
        // NOTE: WILD gets win priority because it SUBSTITUTES for other symbols
        // SCATTER and BONUS do NOT get win priority - they trigger features (free spins, bonus)
        // Their audio plays on LAND (SYMBOL_LAND_SCATTER/BONUS), not on WIN
        bool hasWildInWin = false;
        final Set<String> wildPositions = {};

        for (final lineWin in result.lineWins) {
          final symbolName = lineWin.symbolName.toUpperCase();
          if (symbolName.isNotEmpty) {
            _winningSymbolNames.add(symbolName);
            _winningPositionsBySymbol.putIfAbsent(symbolName, () => <String>{});
          }
          for (final pos in lineWin.positions) {
            if (pos.length >= 2) {
              final reelIdx = pos[0];
              final rowIdx = pos[1];
              final posKey = '$reelIdx,$rowIdx';
              _winningPositions.add(posKey);
              _winningReels.add(reelIdx);
              if (symbolName.isNotEmpty) {
                _winningPositionsBySymbol[symbolName]!.add(posKey);
              }

              // WILD PRIORITY: Check if actual symbol on grid is WILD
              // When WILD substitutes for another symbol, WILD's win audio should play
              if (reelIdx < _targetGrid.length && rowIdx < _targetGrid[reelIdx].length) {
                final actualSymbolId = _targetGrid[reelIdx][rowIdx];
                if (actualSymbolId == 11) { // WILD
                  hasWildInWin = true;
                  wildPositions.add(posKey);
                }
              }
            }
          }
        }

        // WILD PRIORITY: Add WILD to winning symbols if present in any win
        if (hasWildInWin) {
          _winningSymbolNames.add('WILD');
          _winningPositionsBySymbol['WILD'] = wildPositions;
          debugPrint('[SlotPreview] P0.2: ⭐ WILD detected in win (${wildPositions.length} positions)');
        }

        // Trigger symbol-specific highlights (V14)
        for (final symbolName in _winningSymbolNames) {
          final stage = 'WIN_SYMBOL_HIGHLIGHT_$symbolName';
          debugPrint('[SlotPreview] P0.2: Pre-triggering $stage');
          eventRegistry.triggerStage(stage);
        }

        // Generic highlight for backwards compatibility
        eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');
        _startSymbolPulseAnimation();

        _symbolHighlightPreTriggered = true;
        debugPrint('[SlotPreview] P0.2: ✅ WIN_SYMBOL_HIGHLIGHT pre-triggered (${_winningSymbolNames.length} symbols, flag set)');
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // V9: CONDITION-BASED ANTICIPATION — Detect scatters, trigger on 2nd scatter
    // Industry standard: Anticipation only activates when there's potential for 3rd scatter
    // Example: 2 scatters landed on reels 0,1 → anticipation on remaining reels 2,3,4
    // ═══════════════════════════════════════════════════════════════════════════
    _checkScatterAndTriggerAnticipation(reelIndex);
  }

  /// Check if the stopped reel has scatter symbols and trigger anticipation if 2+ found
  /// P7.2.1: Now activates SEQUENTIAL anticipation mode where reels stop one-by-one
  /// DYNAMIC SCATTER DETECTION: Works with default symbols (ID 12) AND GDD-imported symbols
  void _checkScatterAndTriggerAnticipation(int reelIndex) {
    // Check if this reel has any scatter symbols (DYNAMIC detection)
    if (reelIndex < _targetGrid.length) {
      final reelSymbols = _targetGrid[reelIndex];
      // Use dynamic scatter detection — works with any symbol configuration
      final hasScatter = reelSymbols.any((symbolId) => SlotSymbol.isScatterSymbol(symbolId));

      if (hasScatter) {
        _scatterReels.add(reelIndex);
        debugPrint('[SlotPreview] ◆ SCATTER detected on reel $reelIndex (total: ${_scatterReels.length})');

        // Trigger anticipation when we have 2 scatters and remaining reels exist
        if (_scatterReels.length >= _scattersNeededForAnticipation) {
          // Find remaining reels that haven't stopped yet
          final remainingReels = <int>[];
          for (int r = 0; r < widget.reels; r++) {
            if (!_reelStoppedFlags.contains(r) && !_scatterReels.contains(r)) {
              remainingReels.add(r);
            }
          }

          if (remainingReels.isNotEmpty) {
            debugPrint('[SlotPreview] 🎯 ANTICIPATION TRIGGERED! Scatters: $_scatterReels, extending reels: $remainingReels');

            // ═══════════════════════════════════════════════════════════════════════════
            // P7.2.1: SEQUENTIAL ANTICIPATION MODE
            // Industry standard (IGT, Pragmatic Play, NetEnt): Reels stop one-by-one
            // Each reel waits for previous to complete anticipation before stopping
            // ═══════════════════════════════════════════════════════════════════════════
            setState(() {
              _sequentialAnticipationMode = true;
              _sequentialAnticipationQueue.clear();
              _sequentialAnticipationQueue.addAll(remainingReels..sort()); // Sort ascending
              _currentSequentialReel = null;
              _isAnticipation = true;
            });

            debugPrint('[SlotPreview] P7.2.1: SEQUENTIAL MODE ACTIVATED, queue: $_sequentialAnticipationQueue');

            // Start first reel in sequence
            _startNextSequentialAnticipationReel();

            // Trigger anticipation audio stage
            eventRegistry.triggerStage('ANTICIPATION_ON');
          }
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P7.2.1: SEQUENTIAL ANTICIPATION REEL PROCESSING
  // Each reel gets anticipation → tension escalation → stop → next reel
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start anticipation on the next reel in the sequential queue
  void _startNextSequentialAnticipationReel() {
    if (_sequentialAnticipationQueue.isEmpty) {
      debugPrint('[SlotPreview] P7.2.1: Sequential queue empty, all anticipation reels processed');
      _sequentialAnticipationMode = false;
      _currentSequentialReel = null;
      return;
    }

    final nextReel = _sequentialAnticipationQueue.removeAt(0);
    _currentSequentialReel = nextReel;

    // Calculate tension level based on position in queue (L1 → L2 → L3 → L4)
    // First anticipation reel = L1, second = L2, etc.
    final tensionLevel = (_anticipationReels.length + 1).clamp(1, 4);

    debugPrint('[SlotPreview] P7.2.1: Starting SEQUENTIAL anticipation on reel $nextReel (tension L$tensionLevel, remaining: $_sequentialAnticipationQueue)');

    // Extend spin time SIGNIFICANTLY for this reel (others stay spinning)
    _reelAnimController.extendReelSpinTime(nextReel, _anticipationDurationMs);

    // Start visual anticipation with tension level
    _startSequentialReelAnticipation(nextReel, tensionLevel);

    // Trigger per-reel anticipation audio with tension level
    eventRegistry.triggerStage('ANTICIPATION_TENSION_R${nextReel}_L$tensionLevel', context: {
      'reel_index': nextReel,
      'tension_level': tensionLevel,
    });
  }

  /// Start anticipation on a specific reel in sequential mode
  /// This version schedules the reel to stop after anticipation completes
  void _startSequentialReelAnticipation(int reelIndex, int tensionLevel) {
    if (_anticipationReels.contains(reelIndex)) return;

    debugPrint('[SlotPreview] P7.2.1: SEQUENTIAL ANTICIPATION START: Reel $reelIndex, tension L$tensionLevel');

    setState(() {
      _anticipationReels.add(reelIndex);
      _anticipationProgress[reelIndex] = 0.0;
      _anticipationTensionLevel[reelIndex] = tensionLevel;
      _anticipationReason[reelIndex] = 'scatter';
      _anticipationZoom = _calculateAnticipationZoom();
    });

    // Slow down this reel animation
    _reelAnimController.setReelSpeedMultiplier(reelIndex, 0.3);

    // Start anticipation overlay animation
    _anticipationController.repeat(reverse: true);

    // Progress timer with sequential completion callback
    const updateInterval = 50;
    int elapsed = 0;
    _anticipationTimers[reelIndex]?.cancel();
    _anticipationTimers[reelIndex] = Timer.periodic(
      const Duration(milliseconds: updateInterval),
      (timer) {
        elapsed += updateInterval;
        final progress = (elapsed / _anticipationDurationMs).clamp(0.0, 1.0);

        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _anticipationProgress[reelIndex] = progress;
        });

        // Anticipation complete — stop this reel and start next
        if (elapsed >= _anticipationDurationMs) {
          timer.cancel();
          _completeSequentialReelAnticipation(reelIndex);
        }
      },
    );
  }

  /// Complete anticipation for a reel and trigger next in sequence
  void _completeSequentialReelAnticipation(int reelIndex) {
    debugPrint('[SlotPreview] P7.2.1: SEQUENTIAL ANTICIPATION COMPLETE: Reel $reelIndex → stopping reel');

    // End anticipation visuals
    _anticipationTimers[reelIndex]?.cancel();
    _anticipationTimers.remove(reelIndex);

    // Restore normal speed (reel will stop naturally now)
    _reelAnimController.setReelSpeedMultiplier(reelIndex, 1.0);

    // Trigger per-reel anticipation off
    eventRegistry.triggerStage('ANTICIPATION_OFF_$reelIndex', context: {'reel_index': reelIndex});

    setState(() {
      _anticipationReels.remove(reelIndex);
      _anticipationProgress.remove(reelIndex);
      _anticipationTensionLevel.remove(reelIndex);
      _anticipationReason.remove(reelIndex);
      _isAnticipation = _anticipationReels.isNotEmpty || _sequentialAnticipationQueue.isNotEmpty;
      _anticipationZoom = _calculateAnticipationZoom();
    });

    // Force reel to stop NOW (don't wait for natural stop)
    _reelAnimController.forceStopReel(reelIndex);

    // After brief delay for reel stop animation, start next sequential reel
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (_sequentialAnticipationMode && _sequentialAnticipationQueue.isNotEmpty) {
        _startNextSequentialAnticipationReel();
      } else {
        // All sequential reels processed
        _sequentialAnticipationMode = false;
        _currentSequentialReel = null;

        // Stop global anticipation overlay if no more reels
        if (_anticipationReels.isEmpty) {
          _anticipationController.stop();
          _anticipationController.reset();
          _anticipationParticlePool.releaseAll(_anticipationParticles);
          _anticipationParticles.clear();
        }
      }
    });
  }

  /// Flush buffered reel stops that are now in sequence
  void _flushPendingReelStops() {
    while (_pendingReelStops.contains(_nextExpectedReelIndex)) {
      final reelToFlush = _nextExpectedReelIndex;
      _pendingReelStops.remove(reelToFlush);
      debugPrint('[SlotPreview] 📤 FLUSHING BUFFERED REEL $reelToFlush');
      _triggerReelStopAudio(reelToFlush);
      _nextExpectedReelIndex++;
    }
  }

  /// Called when ALL reels have stopped - trigger win evaluation
  void _onAllReelsStoppedVisual() {
    if (!mounted) return;

    // Guard against multiple calls (stopImmediately also fires this callback)
    if (_spinFinalized) return;

    // Notify provider: Reels no longer spinning (for STOP button visibility)
    widget.provider.onAllReelsVisualStop();

    // Finalize with the result
    final result = widget.provider.lastResult;
    if (result != null) {
      _finalizeSpin(result);
    }
  }

  @override
  @override
  void dispose() {
    widget.provider.removeListener(_onProviderUpdate);
    // P0.3: Clean up anticipation callbacks
    widget.provider.onAnticipationStart = null;
    widget.provider.onAnticipationEnd = null;
    _winLineCycleTimer?.cancel();
    _tierProgressionTimer?.cancel(); // Clean up tier progression
    _stopRollupTicks(); // Clean up rollup audio sequence
    _disposeControllers();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;

    // ═══════════════════════════════════════════════════════════════════════════
    // V13: SKIP PRESENTATION REQUEST — Fade out before new spin
    // ═══════════════════════════════════════════════════════════════════════════
    if (widget.provider.skipRequested) {
      debugPrint('[SlotPreview] 📤 SKIP REQUESTED — starting fade-out');
      _executeSkipFadeOut();
      return; // Don't process other updates during fade-out
    }

    final result = widget.provider.lastResult;
    final isPlaying = widget.provider.isPlayingStages;
    final stages = widget.provider.lastStages;
    final spinId = result?.spinId;

    // ═══════════════════════════════════════════════════════════════════════════
    // DETAILED DEBUG — Track every state change
    // ═══════════════════════════════════════════════════════════════════════════
    debugPrint('╔══════════════════════════════════════════════════════════════╗');
    debugPrint('║ [SlotPreview] _onProviderUpdate                              ║');
    debugPrint('╠══════════════════════════════════════════════════════════════╣');
    debugPrint('║ Provider state:');
    debugPrint('║   isPlayingStages = $isPlaying');
    debugPrint('║   stages.length = ${stages.length}');
    debugPrint('║   result.spinId = $spinId');
    debugPrint('║ Widget state:');
    debugPrint('║   _isSpinning = $_isSpinning');
    debugPrint('║   _spinFinalized = $_spinFinalized');
    debugPrint('║   _lastProcessedSpinId = $_lastProcessedSpinId');
    debugPrint('╚══════════════════════════════════════════════════════════════╝');

    // ═══════════════════════════════════════════════════════════════════════════
    // SPIN START LOGIC — Guard against re-triggering after finalize
    // ═══════════════════════════════════════════════════════════════════════════
    // Conditions to start spin:
    // 1. Provider is playing stages
    // 2. We have stages to process
    // 3. We're not already spinning
    // 4. We haven't just finalized this spin (prevents double-trigger)
    // 5. This is a NEW spin result (different spinId)

    final canStartSpin = isPlaying && stages.isNotEmpty && !_isSpinning && !_spinFinalized;
    debugPrint('[SlotPreview] canStartSpin=$canStartSpin (isPlaying=$isPlaying, stages=${stages.length}, !spinning=${!_isSpinning}, !finalized=${!_spinFinalized})');

    if (canStartSpin) {
      final hasSpinStart = stages.any((s) => s.stageType == 'spin_start');

      // DEBUG: Log stage types for verification
      if (stages.isNotEmpty) {
        debugPrint('[SlotPreview] Stage types: ${stages.map((s) => s.stageType).take(5).join(", ")}...');
      }
      debugPrint('[SlotPreview] hasSpinStart=$hasSpinStart, spinId=$spinId, lastProcessed=$_lastProcessedSpinId');

      // Only start if this is a genuinely new spin
      if (hasSpinStart && spinId != null && spinId != _lastProcessedSpinId) {
        debugPrint('[SlotPreview] 🆕 NEW SPIN DETECTED: $spinId');
        _lastProcessedSpinId = spinId;
        _startSpin(result);
      } else if (!hasSpinStart) {
        debugPrint('[SlotPreview] ⚠️ BLOCKED: No spin_start stage found!');
      } else if (spinId == _lastProcessedSpinId) {
        debugPrint('[SlotPreview] ⚠️ BLOCKED: Same spinId as last processed ($spinId)');
      } else if (spinId == null) {
        debugPrint('[SlotPreview] ⚠️ BLOCKED: spinId is null');
      }
    } else {
      // Log WHY we can't start spin
      if (!isPlaying) debugPrint('[SlotPreview] ⏸️ Not starting: isPlaying=false');
      if (stages.isEmpty) debugPrint('[SlotPreview] ⏸️ Not starting: stages empty');
      if (_isSpinning) debugPrint('[SlotPreview] ⏸️ Not starting: already spinning');
      if (_spinFinalized) debugPrint('[SlotPreview] ⏸️ Not starting: spinFinalized=true');
    }

    // Reset finalized flag when provider stops playing (ready for next spin)
    if (!isPlaying && _spinFinalized) {
      debugPrint('[SlotPreview] 🔄 RESET: spinFinalized false → ready for next spin');
      setState(() {
        _spinFinalized = false;
        _isSpinning = false; // CRITICAL: Reset spinning state so STOP→SPIN button transition happens
      });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STOP BUTTON HANDLER — Only activates when user explicitly pressed STOP
    // CRITICAL: Check provider.isReelsSpinning to differentiate:
    //   - STOP button: isPlayingStages=false AND isReelsSpinning=false (provider reset both)
    //   - Normal end:  isPlayingStages=false BUT isReelsSpinning=true (wait for animation)
    // ═══════════════════════════════════════════════════════════════════════════
    if (!isPlaying && _isSpinning && !widget.provider.isReelsSpinning) {
      debugPrint('[SlotPreview] ⏹️ STOP BUTTON DETECTED: Provider explicitly stopped → force stop all reels');

      // Stop the visual animation immediately
      if (_reelAnimController.isSpinning) {
        _reelAnimController.stopImmediately();
      }

      // Stop all anticipation animations
      _stopAnticipation();

      // Update display grid to target (final) values
      for (int r = 0; r < widget.reels && r < _targetGrid.length; r++) {
        for (int row = 0; row < widget.rows && row < _targetGrid[r].length; row++) {
          _displayGrid[r][row] = _targetGrid[r][row];
        }
      }

      // Finalize the spin if we have a result
      if (result != null) {
        _finalizeSpin(result);
      } else {
        // No result - just reset state
        setState(() {
          _isSpinning = false;
          _spinFinalized = true;
        });
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FIX (2026-01-31): AUTOMATIC FINALIZE WHEN ANIMATION COMPLETES
    // This handles the case where:
    //   - Provider finished stages (!isPlaying)
    //   - Widget thinks spin is active (_isSpinning)
    //   - Provider thinks reels are spinning (isReelsSpinning=true)
    //   - BUT animation controller has actually finished (!_reelAnimController.isSpinning)
    // This happens when the callback chain breaks or timing mismatches occur.
    // ═══════════════════════════════════════════════════════════════════════════
    if (!isPlaying && _isSpinning && widget.provider.isReelsSpinning && !_reelAnimController.isSpinning) {
      debugPrint('[SlotPreview] 🔧 AUTO-FINALIZE: Animation done but callback missed!');
      debugPrint('  → Provider stages: DONE, widget spinning: YES, provider reels: YES, controller: DONE');

      // Manually trigger the same flow as onAllReelsStopped callback
      _onAllReelsStoppedVisual();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ANTICIPATION HANDLING — Via provider callbacks ONLY (P0.3 fix)
    // ═══════════════════════════════════════════════════════════════════════════
    // Anticipation is now ONLY triggered via provider.onAnticipationStart callback
    // which is connected in initState. The provider parses ANTICIPATION_ON stages
    // from the Rust engine and calls the callback with reel index and tension level.
    //
    // REMOVED: Direct _startAnticipation() call from stage matching
    // REASON: Was triggering anticipation on EVERY spin because loose string
    // matching would match stages like "REEL_STOP_0" (contains no "anticipation"
    // but the fallback _startAnticipation always targeted reels 3,4).
    //
    // Now anticipation ONLY triggers when Rust engine sends ANTICIPATION_ON
    // (i.e., when 2+ scatters are detected on allowed reels).
    // ═══════════════════════════════════════════════════════════════════════════
    if (isPlaying && stages.isNotEmpty) {
      // Safety net: Stop anticipation if ANTICIPATION_OFF stage arrives
      // (in case provider callback doesn't fire)
      final anticipationOff = stages.any((s) {
        final stage = s.stageType.toUpperCase();
        return stage == 'ANTICIPATION_OFF' || stage.startsWith('ANTICIPATION_OFF_');
      });
      if (anticipationOff && _isAnticipation) {
        _stopAnticipation();
      }

      // Check for near miss events
      // DISABLED: NearMiss visual effect temporarily disabled to fix red background bug
      // TODO: Re-enable after fixing false positive detection
      // final nearMiss = stages.any((s) =>
      //     s.stageType.toLowerCase().contains('near') &&
      //     s.stageType.toLowerCase().contains('miss'));
      // if (nearMiss && !_isNearMiss) {
      //   _triggerNearMiss(result);
      // }

      // Check for cascade events
      final cascadeStart = stages.any((s) =>
          s.stageType.toLowerCase().contains('cascade') &&
          s.stageType.toLowerCase().contains('start'));
      final cascadeStep = stages.any((s) =>
          s.stageType.toLowerCase().contains('cascade') &&
          s.stageType.toLowerCase().contains('step'));
      if (cascadeStart && !_isCascading) {
        _startCascade(result);
      } else if (cascadeStep && _isCascading) {
        _cascadeStepAnimation(result);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REMOVED: Early finalize when provider stops playing
    // REASON: Visual animation may still be running!
    // CORRECT: Only call _finalizeSpin() from _onAllReelsStoppedVisual()
    // This ensures ALL reels land visually BEFORE win evaluation starts
    // ═══════════════════════════════════════════════════════════════════════════
    // OLD CODE (WRONG):
    // if (!isPlaying && result != null && _isSpinning) {
    //   _finalizeSpin(result);
    // }
  }

  void _startSpin(SlotLabSpinResult? result) {
    debugPrint('[SlotPreview] 🎬 _startSpin() called, _isSpinning=$_isSpinning');
    if (_isSpinning) {
      debugPrint('[SlotPreview] ❌ _startSpin BLOCKED: already spinning!');
      return;
    }
    debugPrint('[SlotPreview] ✅ _startSpin PROCEEDING — will set _isSpinning=true');

    // Stop any previous win line presentation and tier progression
    _stopWinLinePresentation();
    _stopTierProgression();

    // Capture spin start time for Event Log timestamp ordering
    _spinStartTimeMs = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _isSpinning = true;
      _spinFinalized = false; // Clear finalized flag for new spin
      _symbolHighlightPreTriggered = false; // P0.2: Clear pre-trigger flag for new spin
      _winningReels = {};
      _winningPositions = {};
      _winningPositionsBySymbol = {}; // V14: Clear per-symbol positions
      _winningSymbolNames = {}; // V14: Clear symbol names
      _currentLinePositions = {}; // Clear line presentation positions
      _winTier = '';
      _currentDisplayTier = ''; // Reset display tier for new spin
      _displayedWinAmount = 0;
      _targetWinAmount = 0;
      _particles.clear();
      // P2.2: Clear anticipation particles on spin start
      _anticipationParticlePool.releaseAll(_anticipationParticles);
      _anticipationParticles.clear();
      // Reset anticipation/near miss state
      _isAnticipation = false;
      _isNearMiss = false;
      _anticipationReels = {};
      _nearMissPositions = {};
      _anticipationTensionLevel.clear();
      _anticipationReason.clear();
      // V9: Reset scatter tracking for condition-based anticipation
      _scatterReels = {};
      // Clear reel stopped flags for new spin
      _reelStoppedFlags.clear();
      // Reset IGT-style sequential buffer for new spin
      _nextExpectedReelIndex = 0;
      _pendingReelStops.clear();
      // P3.1: Reset zoom for new spin
      _anticipationZoom = 1.0;
      // P7.2.1: Reset sequential anticipation mode for new spin
      _sequentialAnticipationMode = false;
      _sequentialAnticipationQueue.clear();
      _currentSequentialReel = null;
      // SPINNING→DECEL FIX: Clear last spinning offsets for new spin
      _lastSpinningOffset.clear();
    });

    // Hide win overlay
    _winAmountController.reverse();
    _winCounterController.reset();

    // Set target grid for final display
    if (result != null) {
      _targetGrid = List.generate(widget.reels, (r) {
        if (r < result.grid.length) {
          return List.generate(widget.rows, (row) {
            if (row < result.grid[r].length) return result.grid[r][row];
            return _random.nextInt(10);
          });
        }
        return List.generate(widget.rows, (_) => _random.nextInt(10));
      });
    }

    // Generate random symbols for spinning blur effect
    _spinSymbols = List.generate(
      widget.reels,
      (_) => List.generate(30, (_) => _random.nextInt(10)),
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // PROFESSIONAL ANIMATION START
    // Set target symbols and start spin via controller
    // ═══════════════════════════════════════════════════════════════════════════
    _reelAnimController.setTargetGrid(_targetGrid);
    _reelAnimController.startSpin();

    // NOTE: SPIN_START audio is triggered by SlotLabProvider._playStage()
    // DO NOT trigger here - causes double trigger!
    debugPrint('[SlotPreview] 🎰 SPIN STARTED (visual only, audio via provider)');
  }

  void _finalizeSpin(SlotLabSpinResult result) {
    debugPrint('[SlotPreview] ✅ FINALIZE SPIN — _isSpinning=$_isSpinning, _spinFinalized=$_spinFinalized');

    // Guard against double finalize
    if (_spinFinalized) {
      debugPrint('[SlotPreview] ⚠️ _finalizeSpin SKIPPED: already finalized');
      return;
    }

    // Stop visual animation ONLY if still spinning (avoid duplicate callback from stopImmediately)
    if (_reelAnimController.isSpinning) {
      debugPrint('[SlotPreview] Stopping animation controller...');
      _reelAnimController.stopImmediately();
    } else {
      debugPrint('[SlotPreview] Animation already stopped, skipping stopImmediately()');
    }

    // Stop any existing win line presentation
    _stopWinLinePresentation();

    setState(() {
      // CRITICAL FIX: Use _targetGrid (set at spin start) NOT result.grid
      // This ensures symbols don't change after last reel stops
      // _targetGrid was already set from result.grid in _startSpin()
      for (int r = 0; r < widget.reels && r < _targetGrid.length; r++) {
        for (int row = 0; row < widget.rows && row < _targetGrid[r].length; row++) {
          _displayGrid[r][row] = _targetGrid[r][row];
        }
      }

      _isSpinning = false;
      _spinFinalized = true; // CRITICAL: Prevent re-trigger in _onProviderUpdate

      if (result.isWin) {
        // V13: Mark win presentation as active (blocks new spin until complete)
        widget.provider.setWinPresentationActive(true);

        // V14: Collect winning positions AND group by symbol name
        // This enables symbol-specific audio triggers: WIN_SYMBOL_HIGHLIGHT_HP1, etc.
        //
        // WILD PRIORITY RULE: When WILD substitutes for another symbol in a win,
        // WILD gets audio priority. Check actual grid symbols, not just lineWin.symbolName.
        _winningPositionsBySymbol.clear();
        _winningSymbolNames.clear();

        // Track WILD symbols in winning positions
        // NOTE: Only WILD gets win priority because it SUBSTITUTES for other symbols
        // SCATTER and BONUS do NOT get win priority - they trigger features (free spins, bonus)
        // Their audio plays on LAND (SYMBOL_LAND_SCATTER/BONUS), not on WIN
        bool hasWildInWin = false;
        final Set<String> wildPositions = {};

        for (final lineWin in result.lineWins) {
          final symbolName = lineWin.symbolName.toUpperCase();
          if (symbolName.isNotEmpty) {
            _winningSymbolNames.add(symbolName);
            _winningPositionsBySymbol.putIfAbsent(symbolName, () => <String>{});
          }

          for (final pos in lineWin.positions) {
            if (pos.length >= 2) {
              final reelIdx = pos[0];
              final rowIdx = pos[1];
              _winningReels.add(reelIdx);
              final posKey = '$reelIdx,$rowIdx';
              _winningPositions.add(posKey);

              // Track position by symbol name
              if (symbolName.isNotEmpty) {
                _winningPositionsBySymbol[symbolName]!.add(posKey);
              }

              // WILD PRIORITY: Check if actual symbol on grid is WILD
              // When WILD substitutes for another symbol, WILD's win audio should play
              if (reelIdx < _targetGrid.length && rowIdx < _targetGrid[reelIdx].length) {
                final actualSymbolId = _targetGrid[reelIdx][rowIdx];
                if (actualSymbolId == 11) { // WILD
                  hasWildInWin = true;
                  wildPositions.add(posKey);
                }
              }
            } else if (pos.isNotEmpty) {
              _winningReels.add(pos[0]);
            }
          }
        }

        // WILD PRIORITY: Add WILD to winning symbols if present in any win
        // This ensures WIN_SYMBOL_HIGHLIGHT_WILD triggers when WILD substitutes
        if (hasWildInWin) {
          _winningSymbolNames.add('WILD');
          _winningPositionsBySymbol['WILD'] = wildPositions;
          debugPrint('[SlotPreview] ⭐ WILD detected in win (${wildPositions.length} positions)');
        }

        debugPrint('[SlotPreview] 🎯 V14: Winning symbols: ${_winningSymbolNames.join(', ')}');

        // ═══════════════════════════════════════════════════════════════════════
        // ULTIMATIVNO REŠENJE: P5 Win Tier System
        // Koristi SlotLabProjectProvider.getWinTierForAmount() za SVE winove
        // NIKADA ne vraća prazan string — svaki win ima svoj tier label
        // ═══════════════════════════════════════════════════════════════════════
        _targetWinAmount = result.totalWin.toDouble();
        _winTier = _getP5WinTierStringId(_targetWinAmount);

        // ═══════════════════════════════════════════════════════════════════════
        // ANALYTICS: Track win tier triggered
        // ═══════════════════════════════════════════════════════════════════════
        WinAnalyticsService.instance.trackWinTier(
          _winTier,
          winAmount: _targetWinAmount,
          betAmount: widget.provider.betAmount,
        );

        // ═══════════════════════════════════════════════════════════════════════
        // V9: WIN PRESENTATION SYSTEM
        // Per user spec:
        // - SMALL wins: "WIN!" plaque with counter (this IS the total win plaque)
        // - BIG+ wins: Tier progression (BIG WIN! → SUPER WIN! → ...) with counter
        //   The big win plaque IS the total win for big wins (no separate plaque)
        // ═══════════════════════════════════════════════════════════════════════

        // Store lineWins for later use in callback
        final lineWinsForPhase3 = result.lineWins;

        // Symbol highlight duration before plaque starts
        const symbolHighlightMs = 1050; // 3 cycles × 350ms

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE 1: SYMBOL HIGHLIGHT (0ms → symbolHighlightMs)
        // Winning symbols glow and pulse - builds anticipation
        // NO WIN AUDIO HERE — audio triggers in Phase 2 when plaque appears
        //
        // V14: SYMBOL-SPECIFIC TRIGGERS
        // Ako HP1 je sastavni deo win symbola → pusti HP1 win zvuk
        // Svaki simbol tip ima svoj highlight stage za fleksibilan audio dizajn
        // ═══════════════════════════════════════════════════════════════════════

        // V14: Trigger symbol-specific highlight stages (HP1 → WIN_SYMBOL_HIGHLIGHT_HP1)
        // P0.2: Guard with pre-trigger flag - may have been triggered on last reel stop
        if (!_symbolHighlightPreTriggered) {
          debugPrint('[SlotPreview] 🎯 WIN_SYMBOL_HIGHLIGHT PHASE 1 START:');
          debugPrint('[SlotPreview]   → Winning symbols: ${_winningSymbolNames.isEmpty ? "(empty)" : _winningSymbolNames.join(", ")}');
          debugPrint('[SlotPreview]   → LineWins count: ${result.lineWins.length}');

          for (final symbolName in _winningSymbolNames) {
            final stage = 'WIN_SYMBOL_HIGHLIGHT_$symbolName';
            debugPrint('[SlotPreview] 🔊 V14: Triggering $stage (${_winningPositionsBySymbol[symbolName]?.length ?? 0} positions)');
            eventRegistry.triggerStage(stage);
          }

          // Also trigger generic stage for backwards compatibility
          debugPrint('[SlotPreview] 🔊 Triggering generic WIN_SYMBOL_HIGHLIGHT');
          eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');

          _startSymbolPulseAnimation();
        } else {
          debugPrint('[SlotPreview] P0.2: WIN_SYMBOL_HIGHLIGHT SKIPPED (already pre-triggered on last reel stop)');
        }
        _triggerStaggeredSymbolPopups(); // V6: Staggered popup effect (always runs)

        // Store win tier info for Phase 2 audio trigger
        final winPresentTier = _getWinPresentTier(result.totalWin);

        debugPrint('[SlotPreview] 🎰 PHASE 1: Symbol highlight (tier: ${_winTier.isEmpty ? "SMALL" : _winTier}, duration: ${symbolHighlightMs}ms)');

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE 2: WIN PLAQUE (after symbol highlight)
        // ═══════════════════════════════════════════════════════════════════════
        Future.delayed(const Duration(milliseconds: symbolHighlightMs), () {
          if (!mounted) return;
          // FIX: Guard against skip race condition
          if (widget.provider.skipRequested) {
            debugPrint('[SlotPreview] ⚠️ Phase 2 skipped — skip was requested during symbol highlight');
            return;
          }

          // Check if BIG WIN (tier progression) vs REGULAR WIN (simple plaque)
          final projectProvider = widget.projectProvider;
          final bet = widget.provider.betAmount;
          final tierResult = projectProvider?.getWinTierForAmount(_targetWinAmount, bet);
          final isBigWin = tierResult?.isBigWin ?? false;

          if (!isBigWin) {
            // ═══════════════════════════════════════════════════════════════════
            // REGULAR WIN: Simple plaque with counter, then win lines
            // WIN_PRESENT_X audio triggers NOW when plaque appears (not during symbol highlight)
            // ═══════════════════════════════════════════════════════════════════
            debugPrint('[SlotPreview] 💰 PHASE 2: Regular win plaque (tier: $_winTier, win: ${result.totalWin})');

            // 🔊 Trigger WIN_PRESENT audio when plaque appears
            eventRegistry.triggerStage('WIN_PRESENT_$winPresentTier');

            // Show plaque with tier label (WIN_1, WIN_2, etc.)
            setState(() {
              _currentDisplayTier = _winTier;
            });
            _winAmountController.forward(from: 0);

            // Start rollup with callback for win lines
            // V9: Pass winPresentTier for tier 1 skip logic (≤ 1x wins skip animation)
            _startTierBasedRollupWithCallback(_winTier, () {
              if (!mounted) return;

              // Fade out plaque
              _winAmountController.reverse().then((_) {
                if (!mounted) return;

                // Start win line presentation
                if (lineWinsForPhase3.isNotEmpty) {
                  debugPrint('[SlotPreview] 🎰 PHASE 3: Win lines (after regular win)');
                  _startWinLinePresentation(lineWinsForPhase3);
                } else {
                  // V13: No win lines — win presentation is COMPLETE
                  debugPrint('[SlotPreview] 🏁 Win presentation COMPLETE (regular win, no lines)');
                  widget.provider.setWinPresentationActive(false);
                }
              });
            }, winPresentTier: winPresentTier);
          } else {
            // ═══════════════════════════════════════════════════════════════════
            // BIG+ WIN: Tier progression plaque with counter (this IS the total win)
            // BIG_WIN_INTRO → BIG → SUPER → ... → BIG_WIN_END → Win lines
            // No separate "total win" plaque — the tier plaque shows the counter
            // WIN_PRESENT_X audio triggers NOW when plaque appears (not during symbol highlight)
            // ═══════════════════════════════════════════════════════════════════
            debugPrint('[SlotPreview] 🎰 PHASE 2: Tier progression (${result.totalWin}) → $_winTier');

            // 🔊 Trigger WIN_PRESENT audio when plaque appears
            eventRegistry.triggerStage('WIN_PRESENT_$winPresentTier');

            // ═══════════════════════════════════════════════════════════════════
            // BIG WIN (≥20x bet) — Trigger celebration loop and coins
            // ═══════════════════════════════════════════════════════════════════
            final bet = widget.provider.betAmount;
            final winRatio = bet > 0 ? result.totalWin / bet : 0.0;
            if (winRatio >= 20) {
              debugPrint('[SlotPreview] 🌟 BIG WIN TRIGGERED (${winRatio.toStringAsFixed(1)}x bet)');
              eventRegistry.triggerStage('BIG_WIN_LOOP');
              eventRegistry.triggerStage('BIG_WIN_COINS');
            }

            // Start tier progression — this handles everything:
            // - BIG_WIN_INTRO
            // - Each tier display (4s each)
            // - BIG_WIN_END
            // - Plaque fade-out
            // - Win lines (Phase 3)
            _startTierProgression(_winTier, lineWinsForPhase3, null);
          }
        });

        // Spawn particles for ALL wins (bigger = more particles)
        _spawnWinParticles(_winTier);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // WIN LINE PRESENTATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Start cycling through winning lines one by one
  void _startWinLinePresentation(List<LineWin> lineWins) {
    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL FIX: Must use setState() to trigger rebuild and show win lines!
    // Without setState(), _isShowingWinLines and _currentLinePositions changes
    // are not reflected in the UI
    // ═══════════════════════════════════════════════════════════════════════════
    setState(() {
      _lineWinsForPresentation = lineWins;
      _currentPresentingLineIndex = 0;
      _isShowingWinLines = true;
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // SAKRIJ TIER PLAKETU — win lines se prikazuju bez overlay-a
    // Ostaju SAMO vizualne linije, BEZ info o simbolima
    // ═══════════════════════════════════════════════════════════════════════════
    _winAmountController.reverse();

    // Show first line immediately (also needs setState for _currentLinePositions)
    _showCurrentWinLineWithSetState();

    // Start cycling timer
    _winLineCycleTimer?.cancel();
    _winLineCycleTimer = Timer.periodic(_winLineCycleDuration, (_) {
      if (!mounted || !_isShowingWinLines) {
        _winLineCycleTimer?.cancel();
        return;
      }
      _advanceToNextWinLine();
    });

    debugPrint('[SlotPreview] 🎯 Started win line presentation: ${lineWins.length} lines (counter hidden)');
  }

  /// Stop win line presentation
  void _stopWinLinePresentation() {
    _winLineCycleTimer?.cancel();
    _winLineCycleTimer = null;
    _stopRollupTicks(); // Also stop any ongoing rollup audio

    // ═══════════════════════════════════════════════════════════════════════════
    // FIX (2026-01-31): Use setState to ensure UI immediately reflects the change
    // Without setState, win lines could remain visible during the next spin start
    // ═══════════════════════════════════════════════════════════════════════════
    if (mounted) {
      setState(() {
        _isShowingWinLines = false;
        _lineWinsForPresentation = [];
        _currentPresentingLineIndex = 0;
        _currentLinePositions = {};
      });
    } else {
      _isShowingWinLines = false;
      _lineWinsForPresentation = [];
      _currentPresentingLineIndex = 0;
      _currentLinePositions = {};
    }

    // V13: Mark win presentation as COMPLETE — allows next spin
    widget.provider.setWinPresentationActive(false);
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // V13: SKIP PRESENTATION WITH FADE-OUT
  // When user presses Spin during win presentation, fade out first
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Execute fade-out of all win presentation elements
  /// Called when provider.skipRequested is true
  void _executeSkipFadeOut() {
    debugPrint('[SlotPreview] 🎬 _executeSkipFadeOut — stopping timers, starting fade');

    // 1. Stop all presentation timers (but don't reset visual state yet)
    _winLineCycleTimer?.cancel();
    _winLineCycleTimer = null;
    _tierProgressionTimer?.cancel();
    _tierProgressionTimer = null;
    _rollupTickTimer?.cancel();
    _rollupTickTimer = null;

    // Helper to reset state and notify provider
    void completeSkip() {
      if (!mounted) return;

      // Reset all presentation state
      setState(() {
        _isShowingWinLines = false;
        _isInTierProgression = false;
        _isRollingUp = false;
        _lineWinsForPresentation = [];
        _currentPresentingLineIndex = 0;
        _currentLinePositions = {};
        _tierProgressionList = [];
        _tierProgressionIndex = 0;
        _winningPositions = {};
        _winningPositionsBySymbol = {}; // V14: Clear per-symbol positions
        _winningSymbolNames = {}; // V14: Clear symbol names
        _winningReels = {};
        _winTier = '';
        _currentDisplayTier = '';
        // FIX: Clear pre-trigger flag so next win can trigger symbol highlights
        _symbolHighlightPreTriggered = false;
      });

      debugPrint('[SlotPreview] ✅ Skip fade-out COMPLETE — calling onSkipComplete()');

      // ANALYTICS: Track skip completed
      WinAnalyticsService.instance.trackSkipCompleted(
        _winTier,
        fadeOutDurationMs: 200, // Fade-out duration
      );

      // Notify provider that skip is complete
      widget.provider.onSkipComplete();
    }

    // 2. Check if plaque is already hidden — if so, complete immediately
    if (_winAmountController.value == 0 && !_winAmountController.isAnimating) {
      debugPrint('[SlotPreview] ⚡ Plaque already hidden — completing skip immediately');
      completeSkip();
      return;
    }

    // 3. Trigger fade-out animation (300ms)
    _winAmountController.reverse().then((_) {
      completeSkip();
    });
  }

  /// Advance to next win line — NO LOOPING, single pass through all lines
  void _advanceToNextWinLine() {
    if (_lineWinsForPresentation.isEmpty) return;

    final nextIndex = _currentPresentingLineIndex + 1;

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: NO LOOPING — stop after showing all unique lines ONCE
    // When last line is reached, stop the timer and end presentation
    // ═══════════════════════════════════════════════════════════════════════════
    if (nextIndex >= _lineWinsForPresentation.length) {
      debugPrint('[SlotPreview] 🏁 Win line presentation COMPLETE (${_lineWinsForPresentation.length} lines shown once)');
      _stopWinLinePresentation();
      return;
    }

    setState(() {
      _currentPresentingLineIndex = nextIndex;
      _showCurrentWinLine(); // Audio triggered inside _showCurrentWinLine()
    });
  }

  /// Update visual state for currently shown win line
  void _showCurrentWinLine({bool triggerAudio = true}) {
    if (_lineWinsForPresentation.isEmpty) return;

    final currentLine = _lineWinsForPresentation[_currentPresentingLineIndex];

    // Update positions for current line only
    _currentLinePositions = {};
    for (final pos in currentLine.positions) {
      if (pos.length >= 2) {
        _currentLinePositions.add('${pos[0]},${pos[1]}');
      }
    }

    // P1.2: Animate line growth (250ms, 0→1)
    _lineGrowController.forward(from: 0);

    // Trigger WIN_LINE_SHOW audio (for first line and cycling)
    if (triggerAudio) {
      eventRegistry.triggerStage('WIN_LINE_SHOW');
    }

    debugPrint('[SlotPreview] 🎯 Showing line ${_currentPresentingLineIndex + 1}/${_lineWinsForPresentation.length}: '
        '${currentLine.symbolName} x${currentLine.matchCount} = ${currentLine.winAmount}');
  }

  /// Update visual state for currently shown win line WITH setState
  /// Used for initial line presentation to trigger UI rebuild
  void _showCurrentWinLineWithSetState({bool triggerAudio = true}) {
    if (_lineWinsForPresentation.isEmpty) return;

    final currentLine = _lineWinsForPresentation[_currentPresentingLineIndex];

    // Update positions for current line only - WITH setState to trigger rebuild
    setState(() {
      _currentLinePositions = {};
      for (final pos in currentLine.positions) {
        if (pos.length >= 2) {
          _currentLinePositions.add('${pos[0]},${pos[1]}');
        }
      }
    });

    // P1.2: Animate line growth (250ms, 0→1)
    _lineGrowController.forward(from: 0);

    // Trigger WIN_LINE_SHOW audio (for first line and cycling)
    if (triggerAudio) {
      eventRegistry.triggerStage('WIN_LINE_SHOW');
    }

    debugPrint('[SlotPreview] 🎯 [setState] Showing line ${_currentPresentingLineIndex + 1}/${_lineWinsForPresentation.length}: '
        '${currentLine.symbolName} x${currentLine.matchCount} = ${currentLine.winAmount}');
  }

  /// Get current line win for display (or null if no presentation active)
  LineWin? get _currentPresentingLine {
    if (!_isShowingWinLines || _lineWinsForPresentation.isEmpty) return null;
    return _lineWinsForPresentation[_currentPresentingLineIndex];
  }

  /// @deprecated Use `widget.provider.getVisualTierForWin()` instead.
  ///
  /// This hardcoded method is kept for backward compatibility.
  // ═══════════════════════════════════════════════════════════════════════════
  // P5 WIN TIER SYSTEM — Dynamic, configurable win tiers
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Uses SlotLabProjectProvider.getWinTierForAmount() when available.
  // Falls back to legacy hardcoded logic when projectProvider is null.
  //
  // P5 Regular Tiers (< bigWinThreshold):
  //   WIN_LOW, WIN_EQUAL, WIN_1, WIN_2, WIN_3, WIN_4, WIN_5
  //   (WIN_6 REMOVED — WIN_5 is now default for >13x regular wins)
  //   All labels are FULLY CONFIGURABLE by user
  //
  // P5 Big Win Tiers (>= bigWinThreshold, default 20x):
  //   BIG_WIN_TIER_1 (20x-50x), BIG_WIN_TIER_2 (50x-100x),
  //   BIG_WIN_TIER_3 (100x-250x), BIG_WIN_TIER_4 (250x-500x),
  //   BIG_WIN_TIER_5 (500x+)
  //   All labels are FULLY CONFIGURABLE (no hardcoded "MEGA WIN!" etc.)
  //
  // ═══════════════════════════════════════════════════════════════════════════

  /// P5: Get complete win tier result from configurable system
  /// Returns null for no win, or full WinTierResult with tier info
  WinTierResult? _getP5WinTierResult(double totalWin) {
    final projectProvider = widget.projectProvider;
    final bet = widget.provider.betAmount;

    if (totalWin <= 0 || bet <= 0) return null;

    // P5 system: use project provider's configurable tiers
    if (projectProvider != null) {
      return projectProvider.getWinTierForAmount(totalWin, bet);
    }

    // Legacy fallback: simulate P5 result with hardcoded thresholds
    return _legacyGetWinTierResult(totalWin, bet);
  }

  /// Legacy fallback when projectProvider is not available
  /// Returns P5-compatible WinTierResult with hardcoded thresholds
  WinTierResult? _legacyGetWinTierResult(double totalWin, double bet) {
    final ratio = totalWin / bet;

    // Big Win threshold (legacy: 20x)
    if (ratio >= 20) {
      // Determine which big win tier (1-5)
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

    // Regular win tiers (legacy) - using simple tier identifiers
    final int regularTierId;
    final String regularLabel;
    if (ratio < 1) {
      regularTierId = 0; // WIN_LOW
      regularLabel = 'WIN LOW';
    } else if (ratio == 1) {
      regularTierId = -1; // WIN_EQUAL
      regularLabel = 'WIN =';
    } else if (ratio <= 2) {
      regularTierId = 1;
      regularLabel = 'WIN 1';
    } else if (ratio <= 4) {
      regularTierId = 2;
      regularLabel = 'WIN 2';
    } else if (ratio <= 6) {
      regularTierId = 3;
      regularLabel = 'WIN 3';
    } else if (ratio <= 10) {
      regularTierId = 4;
      regularLabel = 'WIN 4';
    } else if (ratio <= 15) {
      regularTierId = 5;
      regularLabel = 'WIN 5';
    } else {
      regularTierId = 6;
      regularLabel = 'WIN 5'; // No WIN_6, use WIN 5 for high regular wins
    }

    return WinTierResult(
      isBigWin: false,
      multiplier: ratio,
      regularTier: WinTierDefinition(
        tierId: regularTierId,
        fromMultiplier: 0,
        toMultiplier: 20,
        displayLabel: regularLabel,
        rollupDurationMs: _legacyRegularRollupDuration(regularTierId),
        rollupTickRate: 15,
      ),
      bigWinTier: null,
      bigWinMaxTier: null,
    );
  }

  /// Legacy regular tier rollup duration mapping (WIN_6 removed)
  /// WIN_1: >1x,≤2x | WIN_2: >2x,≤4x | WIN_3: >4x,≤8x | WIN_4: >8x,≤13x | WIN_5: >13x
  int _legacyRegularRollupDuration(int tierId) {
    return switch (tierId) {
      0 => 500,   // WIN_EQUAL (push - short)
      1 => 1000,  // WIN_1: 1 second
      2 => 1500,  // WIN_2: 1.5 seconds
      3 => 2000,  // WIN_3: 2 seconds
      4 => 3000,  // WIN_4: 3 seconds
      5 => 4000,  // WIN_5: 4 seconds
      _ => 500,   // fallback
    };
  }

  /// Legacy big win label mapping (fallback only)
  /// Uses simple tier identifiers - NO hardcoded labels
  String _legacyBigWinLabel(int tierId) {
    return switch (tierId) {
      1 => 'BIG WIN TIER 1',
      2 => 'BIG WIN TIER 2',
      3 => 'BIG WIN TIER 3',
      4 => 'BIG WIN TIER 4',
      5 => 'BIG WIN TIER 5',
      _ => 'BIG WIN',
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P5 TIER LABEL SYSTEM — Fully Configurable Labels from SlotLabProjectProvider
  // Maps tier ID strings ('BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_TIER_4', 'BIG_WIN_TIER_5') to user-defined labels
  // Falls back to generic defaults when projectProvider is null — NO HARDCODED LABELS
  // ═══════════════════════════════════════════════════════════════════════════

  /// ULTIMATIVNO REŠENJE: Get tier string ID from P5 system
  /// Returns: 'WIN_LOW', 'WIN_1', 'WIN_2', ..., 'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_TIER_4', 'BIG_WIN_TIER_5'
  /// NIKADA ne vraća prazan string — svaki win ima svoj tier ID
  String _getP5WinTierStringId(double totalWin) {
    final projectProvider = widget.projectProvider;
    final bet = widget.provider.betAmount;

    debugPrint('[WIN DEBUG] ═══════════════════════════════════════');
    debugPrint('[WIN DEBUG] Bet: \$${bet.toStringAsFixed(2)}, Win: \$${totalWin.toStringAsFixed(2)}');
    debugPrint('[WIN DEBUG] Multiplier: ${bet > 0 ? (totalWin/bet).toStringAsFixed(2) : "N/A"}x');

    if (projectProvider == null || bet <= 0 || totalWin <= 0) {
      debugPrint('[WIN DEBUG] ⚠️ Fallback to legacy (provider=$projectProvider, bet=$bet, win=$totalWin)');
      return widget.provider.getVisualTierForWin(totalWin);
    }

    // P5 System: Get tier result from project provider
    final tierResult = projectProvider.getWinTierForAmount(totalWin, bet);
    if (tierResult == null) {
      debugPrint('[WIN DEBUG] ❌ tierResult is NULL!');
      return '';
    }

    debugPrint('[WIN DEBUG] isBigWin: ${tierResult.isBigWin}, maxTier: ${tierResult.bigWinMaxTier}');

    // Big Win — return big win tier ID for progression system
    if (tierResult.isBigWin) {
      final tierId = switch (tierResult.bigWinMaxTier) {
        1 => 'BIG_WIN_TIER_1',
        2 => 'BIG_WIN_TIER_2',
        3 => 'BIG_WIN_TIER_3',
        4 => 'BIG_WIN_TIER_4',
        5 => 'BIG_WIN_TIER_5',
        _ => 'BIG_WIN_TIER_1',
      };
      debugPrint('[WIN DEBUG] ✅ BIG WIN: Tier=$tierId (maxTier=${tierResult.bigWinMaxTier})');
      return tierId;
    }

    // Regular Win — return stage name as tier ID (WIN_LOW, WIN_1, WIN_2, etc.)
    if (tierResult.regularTier != null) {
      final stageName = tierResult.regularTier!.stageName;
      debugPrint('[WIN DEBUG] ✅ REGULAR WIN: Tier=$stageName (${tierResult.regularTier!.displayLabel})');
      return stageName;
    }

    debugPrint('[WIN DEBUG] ⚠️ No tier matched!');
    return '';
  }

  /// Get tier label from P5 configuration
  /// Tier ID: 'WIN_LOW', 'WIN_1', 'WIN_2', ..., 'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_TIER_4', 'BIG_WIN_TIER_5'
  /// Returns fully configurable displayLabel from SlotWinConfiguration
  ///
  /// ULTIMATIVNO REŠENJE: Uses P5 displayLabel for ALL tiers
  /// - Regular wins: displayLabel from WinTierDefinition (e.g., 'WIN 1', 'WIN 2')
  /// - Big wins: displayLabel from BigWinTierDefinition (e.g., 'BIG WIN TIER 1')
  /// - NO HARDCODED labels per CLAUDE.md
  String _getP5TierLabel(String tierStringId) {
    final projectProvider = widget.projectProvider;

    // ═══════════════════════════════════════════════════════════════════════════
    // REGULAR WIN TIERS: WIN_LOW, WIN_EQUAL, WIN_1, WIN_2, WIN_3, WIN_4, WIN_5, WIN_6
    // Get displayLabel directly from P5 RegularWinTierConfig
    // ═══════════════════════════════════════════════════════════════════════════
    if (tierStringId.startsWith('WIN_') && projectProvider != null) {
      final config = projectProvider.winConfiguration.regularWins;

      // Find matching tier by stageName
      for (final tier in config.tiers) {
        if (tier.stageName == tierStringId) {
          final label = tier.displayLabel;
          if (label.isNotEmpty) return label;
          // Fallback to tier number if no displayLabel
          return switch (tier.tierId) {
            -1 => 'WIN LOW',
            0 => 'WIN =',
            _ => 'WIN ${tier.tierId}',
          };
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BIG WIN TIERS: TIER_1..TIER_5 → BIG WIN TIER 1..5
    // Get displayLabel from P5 BigWinConfig — NO HARDCODED labels
    // ═══════════════════════════════════════════════════════════════════════════
    final p5TierId = switch (tierStringId) {
      'BIG_WIN_TIER_1' => 1,
      'BIG_WIN_TIER_2' => 2,
      'BIG_WIN_TIER_3' => 3,
      'BIG_WIN_TIER_4' => 4,
      'BIG_WIN_TIER_5' => 5,
      _ => 0,
    };

    if (p5TierId > 0 && projectProvider != null) {
      final bigTiers = projectProvider.winConfiguration.bigWins.tiers;

      for (final tier in bigTiers) {
        if (tier.tierId == p5TierId) {
          final label = tier.displayLabel;
          if (label.isNotEmpty) return label;
          break;
        }
      }

      // Fallback — neutral tier identifiers per CLAUDE.md
      return 'BIG WIN TIER $p5TierId';
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FALLBACK for legacy path (no P5 provider)
    // ═══════════════════════════════════════════════════════════════════════════
    return switch (tierStringId) {
      'WIN_LOW' => 'WIN LOW',
      'WIN_EQUAL' => 'WIN =',
      'WIN_1' => 'WIN 1',
      'WIN_2' => 'WIN 2',
      'WIN_3' => 'WIN 3',
      'WIN_4' => 'WIN 4',
      'WIN_5' => 'WIN 5',
      'WIN_6' => 'WIN 6',
      'BIG_WIN_TIER_5' => 'BIG WIN TIER 5',
      'BIG_WIN_TIER_4' => 'BIG WIN TIER 4',
      'BIG_WIN_TIER_3' => 'BIG WIN TIER 3',
      'BIG_WIN_TIER_2' => 'BIG WIN TIER 2',
      'BIG_WIN_TIER_1' => 'BIG WIN TIER 1',
      'TOTAL' => 'TOTAL WIN',  // BIG_WIN_END outro phase
      _ => 'WIN',
    };
  }

  /// Get all tier labels as a map for tier progression display
  /// Used to show tier escalation: TIER_1 → TIER_2 → TIER_3 → TIER_4 → TIER_5
  Map<String, String> get _p5TierLabels {
    return {
      'BIG_WIN_TIER_1': _getP5TierLabel('BIG_WIN_TIER_1'),
      'BIG_WIN_TIER_2': _getP5TierLabel('BIG_WIN_TIER_2'),
      'BIG_WIN_TIER_3': _getP5TierLabel('BIG_WIN_TIER_3'),
      'BIG_WIN_TIER_4': _getP5TierLabel('BIG_WIN_TIER_4'),
      'BIG_WIN_TIER_5': _getP5TierLabel('BIG_WIN_TIER_5'),
    };
  }

  /// Get display label for win tier plaque
  /// Returns empty string for small wins (no plaque)
  String _getWinTierDisplayLabel(double totalWin) {
    final tierResult = _getP5WinTierResult(totalWin);
    if (tierResult == null) return '';

    if (tierResult.isBigWin) {
      return tierResult.bigWinTier?.displayLabel ?? 'BIG WIN TIER 1';
    }

    // Regular wins don't show plaque (return empty)
    // Unless it's a significant regular win (tier 4+)
    final regularTier = tierResult.regularTier;
    if (regularTier != null && regularTier.tierId >= 4) {
      return regularTier.displayLabel;
    }

    return '';
  }

  /// Get primary stage name to trigger for this win
  String _getWinTierStageName(double totalWin) {
    final tierResult = _getP5WinTierResult(totalWin);
    if (tierResult == null) return 'WIN_PRESENT';

    return tierResult.primaryStageName;
  }

  /// Check if this win qualifies as a "big win" celebration
  bool _isBigWinTier(double totalWin) {
    final tierResult = _getP5WinTierResult(totalWin);
    return tierResult?.isBigWin ?? false;
  }

  /// Get big win tier ID (1-5) for audio/visual escalation
  int? _getBigWinTierId(double totalWin) {
    final tierResult = _getP5WinTierResult(totalWin);
    return tierResult?.bigWinMaxTier;
  }

  /// Legacy compatibility: Get win tier string ('BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', etc.)
  /// Used for existing visual tier logic - maps P5 to generic format
  @Deprecated('Use _getWinTierDisplayLabel() for P5 system')
  String _getWinTier(double totalWin) {
    final tierResult = _getP5WinTierResult(totalWin);
    if (tierResult == null || !tierResult.isBigWin) return '';

    // Map P5 big win tier ID to generic string — NO HARDCODED labels
    return switch (tierResult.bigWinMaxTier) {
      1 => 'BIG_WIN_TIER_1',
      2 => 'BIG_WIN_TIER_2',
      3 => 'BIG_WIN_TIER_3',
      4 => 'BIG_WIN_TIER_4',
      5 => 'BIG_WIN_TIER_5',
      _ => 'BIG_WIN_TIER_1',
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN PRESENTATION AUDIO SYSTEM — P5 Dynamic Stage Triggering
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get WIN_PRESENT tier for audio triggering
  /// P5: Uses configurable tier system with proper stage names
  /// Legacy: Falls back to WIN_PRESENT_1 through WIN_PRESENT_6
  int _getWinPresentTier(double totalWin) {
    final tierResult = _getP5WinTierResult(totalWin);
    if (tierResult == null) return 1;

    if (tierResult.isBigWin) {
      // Big win uses tier ID (1-5) for audio stages
      return tierResult.bigWinMaxTier ?? 1;
    }

    // Regular win: map to tier 1-6 based on regular tier ID
    final regularTierId = tierResult.regularTier?.tierId ?? 0;
    return (regularTierId + 1).clamp(1, 6);
  }

  /// Get WIN_PRESENT duration in milliseconds for the given tier
  /// P5: Uses configured rollup duration when available
  int _getWinPresentDurationMs(int tier) {
    final projectProvider = widget.projectProvider;

    // P5: Get duration from configuration if available
    if (projectProvider != null) {
      final config = projectProvider.winConfiguration;

      // For big win tiers (1-5)
      if (tier >= 1 && tier <= 5) {
        final bigTiers = config.bigWins.tiers;
        for (final bigTier in bigTiers) {
          if (bigTier.tierId == tier) {
            return bigTier.durationMs; // P5: Use durationMs field
          }
        }
      }

      // For regular tiers, find matching tier and use its rollupDurationMs
      for (final regularTier in config.regularWins.tiers) {
        if (regularTier.tierId == tier) {
          return regularTier.rollupDurationMs;
        }
      }

      // Fallback to first regular tier duration
      if (config.regularWins.tiers.isNotEmpty) {
        return config.regularWins.tiers.first.rollupDurationMs;
      }
    }

    // Legacy fallback
    return switch (tier) {
      1 => 500,   // 0.5s
      2 => 1000,  // 1.0s
      3 => 1500,  // 1.5s
      4 => 2000,  // 2.0s
      5 => 3000,  // 3.0s
      6 => 4000,  // 4.0s
      _ => 500,   // fallback
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN AUDIO FLOW — Rollup tick sequence
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start rollup tick audio sequence during win counter animation
  void _startRollupTicks() {
    _rollupTickCount = 0;
    _rollupTickTimer?.cancel();

    // Fire ROLLUP_TICK at ~100ms intervals during the counter animation
    _rollupTickTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _rollupTickCount >= _rollupTicksTotal) {
        timer.cancel();
        if (mounted) {
          // ROLLUP_END when counter finishes
          eventRegistry.triggerStage('ROLLUP_END');
          debugPrint('[SlotPreview] 🔊 ROLLUP_END');
        }
        return;
      }

      _rollupTickCount++;
      // P1.1: Pass progress context for volume/pitch escalation
      final progress = _rollupTickCount / _rollupTicksTotal;
      eventRegistry.triggerStage('ROLLUP_TICK', context: {'progress': progress});
    });

    debugPrint('[SlotPreview] 🔊 ROLLUP started ($_rollupTicksTotal ticks)');
  }

  /// Stop rollup ticks (on early interrupt)
  void _stopRollupTicks() {
    _rollupTickTimer?.cancel();
    _rollupTickTimer = null;
    _rollupTickCount = 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 1: SYMBOL PULSE ANIMATION — Industry standard 3 cycles
  // ═══════════════════════════════════════════════════════════════════════════

  int _symbolPulseCount = 0;

  /// Start symbol pulse animation with 3 cycles (industry standard)
  /// V6: Now includes staggered popup effect for winning symbols
  void _startSymbolPulseAnimation() {
    _symbolPulseCount = 0;

    // V6: Start staggered popup for each winning position
    _triggerStaggeredSymbolPopups();

    _runSymbolPulseCycle();
  }

  /// V6+V14: Trigger staggered popup animations for winning symbols
  /// V14: Groups popups BY SYMBOL TYPE — first all HP1, then HP2, etc.
  /// This synchronizes visual feedback with symbol-specific audio triggers
  void _triggerStaggeredSymbolPopups() {
    // Clear any previous popup state
    _symbolPopScale.clear();
    _symbolPopRotation.clear();

    // V14: Group positions by symbol name, then sort within each group
    // This creates a visual effect where all HP1 symbols pop together,
    // matching the WIN_SYMBOL_HIGHLIGHT_HP1 audio trigger
    final sortedSymbolNames = _winningSymbolNames.toList()..sort();

    int globalIndex = 0;

    for (final symbolName in sortedSymbolNames) {
      final positions = _winningPositionsBySymbol[symbolName] ?? {};

      // Sort positions within this symbol group (left-to-right, top-to-bottom)
      final sortedPositions = positions.toList()..sort((a, b) {
        final partsA = a.split(',').map(int.parse).toList();
        final partsB = b.split(',').map(int.parse).toList();
        if (partsA[0] != partsB[0]) return partsA[0].compareTo(partsB[0]);
        return partsA[1].compareTo(partsB[1]);
      });

      debugPrint('[SlotPreview] 🎬 V14: Popup group "$symbolName" — ${sortedPositions.length} symbols');

      // Trigger staggered popups for this symbol group
      for (final position in sortedPositions) {
        final delay = globalIndex * _symbolPopStaggerMs;
        globalIndex++;

        Future.delayed(Duration(milliseconds: delay), () {
          if (!mounted) return;
          _animateSymbolPop(position);
        });
      }
    }

    // Fallback: if no symbol names tracked, use old position-based order
    if (sortedSymbolNames.isEmpty && _winningPositions.isNotEmpty) {
      final sortedPositions = _winningPositions.toList()..sort((a, b) {
        final partsA = a.split(',').map(int.parse).toList();
        final partsB = b.split(',').map(int.parse).toList();
        if (partsA[0] != partsB[0]) return partsA[0].compareTo(partsB[0]);
        return partsA[1].compareTo(partsB[1]);
      });

      for (int i = 0; i < sortedPositions.length; i++) {
        final position = sortedPositions[i];
        final delay = i * _symbolPopStaggerMs;

        Future.delayed(Duration(milliseconds: delay), () {
          if (!mounted) return;
          _animateSymbolPop(position);
        });
      }
    }
  }

  /// V6: Animate a single symbol popup (scale 1.0 → 1.15 → 1.0 with micro-wiggle)
  void _animateSymbolPop(String position) {
    // Phase 1: Scale up to max (60ms)
    setState(() {
      _symbolPopScale[position] = _symbolPopMaxScale;
      _symbolPopRotation[position] = 0.03; // Small rotation (radians)
    });

    // Phase 2: Wiggle (40ms)
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      setState(() {
        _symbolPopRotation[position] = -0.03; // Wiggle other direction
      });
    });

    // Phase 3: Scale back to normal (100ms)
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() {
        _symbolPopScale[position] = 1.05; // Ease down
        _symbolPopRotation[position] = 0.015;
      });
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _symbolPopScale[position] = 1.0;
        _symbolPopRotation[position] = 0.0;
      });
    });
  }

  /// Run single pulse cycle, repeats until 3 cycles complete
  void _runSymbolPulseCycle() {
    if (!mounted || _symbolPulseCount >= _symbolPulseCycles) {
      debugPrint('[SlotPreview] ✅ Symbol pulse complete ($_symbolPulseCount cycles)');
      return;
    }

    _symbolPulseCount++;
    _symbolBounceController.forward(from: 0).then((_) {
      if (mounted) {
        _symbolBounceController.reverse().then((_) {
          if (mounted) {
            _runSymbolPulseCycle(); // Recurse for next cycle
          }
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE 2: TIER-BASED ROLLUP — Variable duration by win size
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start tier-based rollup with appropriate duration and tick rate
  /// V7: Now includes visual feedback (progress meter + counter shake)
  void _startTierBasedRollup(String tier) {
    _startTierBasedRollupWithCallback(tier, null);
  }

  /// Start tier-based rollup with completion callback
  /// Used for sequential win flow where win lines start after plaque fade-out
  /// V9: Now supports RTL digit animation and tier 1 skip
  void _startTierBasedRollupWithCallback(String tier, VoidCallback? onComplete, {int? winPresentTier}) {
    // ═══════════════════════════════════════════════════════════════════════════
    // V9: WIN TIER 1 SKIP — For tiny wins (≤ 1x bet), skip rollup animation
    // But still show the "WIN!" plaque briefly (800ms minimum) so player sees it
    // ═══════════════════════════════════════════════════════════════════════════
    if (winPresentTier == 1) {
      debugPrint('[SlotPreview] 💨 TIER 1 QUICK — showing plaque briefly (800ms), no rollup');

      setState(() {
        _displayedWinAmount = _targetWinAmount;
        _rtlRollupProgress = 1.0;
        _useRtlRollup = false;
        _isRollingUp = false;
        _rollupProgress = 1.0;
      });

      // Trigger ROLLUP_END audio (no tick sounds)
      eventRegistry.triggerStage('ROLLUP_END');
      debugPrint('[SlotPreview] 🔊 ROLLUP_END (tier 1 instant)');

      // P0.16 FIX: Wait 800ms so player can SEE the plaque before fading
      // Without this delay, the plaque appears and immediately fades out
      // FIX: Check for skip request to avoid race condition with new spin
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        // FIX: If skip was requested during delay, don't call onComplete
        // The skip flow will handle completion via onSkipComplete()
        if (widget.provider.skipRequested) {
          debugPrint('[SlotPreview] ⚠️ Tier 1 callback skipped — skip was requested during delay');
          return;
        }
        onComplete?.call();
      });
      return;
    }

    final duration = _rollupDurationByTier[tier] ?? _defaultRollupDuration;
    final tickRate = _rollupTickRateByTier[tier] ?? _defaultRollupTickRate;
    final tickIntervalMs = (1000 / tickRate).round();
    final totalTicks = (duration / tickIntervalMs).round();
    final incrementPerTick = _targetWinAmount / totalTicks;

    debugPrint('[WIN DEBUG] ═══════════════════════════════════════');
    debugPrint('[WIN DEBUG] ROLLUP CONFIG:');
    debugPrint('[WIN DEBUG]   Tier: $tier');
    debugPrint('[WIN DEBUG]   Duration: ${duration}ms');
    debugPrint('[WIN DEBUG]   Tick Rate: $tickRate ticks/s');
    debugPrint('[WIN DEBUG]   Tick Interval: ${tickIntervalMs}ms');
    debugPrint('[WIN DEBUG]   Total Ticks: $totalTicks');
    debugPrint('[WIN DEBUG]   Increment/Tick: \$${incrementPerTick.toStringAsFixed(2)}');
    debugPrint('[WIN DEBUG]   Target: \$${_targetWinAmount.toStringAsFixed(2)}');
    debugPrint('[WIN DEBUG] ═══════════════════════════════════════');

    // ANALYTICS: Track rollup started
    WinAnalyticsService.instance.trackRollupStarted(
      tier,
      targetAmount: _targetWinAmount,
    );

    // V9: Initialize rollup visual state with RTL mode enabled
    setState(() {
      _isRollingUp = true;
      _rollupProgress = 0.0;
      _useRtlRollup = true;
      _rtlRollupProgress = 0.0;
    });

    // INDUSTRY STANDARD: Counter rolls up FAST (300-600ms), plaque stays visible
    // Plaque duration = celebration time (4s), counter finishes in <600ms
    const counterDurationMs = 500; // Industry standard: fast rollup
    _winCounterController.duration = const Duration(milliseconds: counterDurationMs);
    _winCounterController.forward(from: 0);

    // Start tick audio
    eventRegistry.triggerStage('ROLLUP_START');

    _rollupTickCount = 0;
    _rollupTickTimer?.cancel();
    _rollupTickTimer = Timer.periodic(Duration(milliseconds: tickIntervalMs), (timer) {
      if (!mounted || _rollupTickCount >= totalTicks) {
        timer.cancel();
        if (mounted) {
          // V9: End rollup visual state, disable RTL mode
          setState(() {
            _isRollingUp = false;
            _rollupProgress = 1.0;
            _counterShakeScale = 1.0;
            _useRtlRollup = false;
            _rtlRollupProgress = 1.0;
          });
          eventRegistry.triggerStage('ROLLUP_END');
          debugPrint('[SlotPreview] 🔊 ROLLUP_END (completed $totalTicks ticks)');

          // ANALYTICS: Track rollup completed (not skipped)
          WinAnalyticsService.instance.trackRollupCompleted(
            tier,
            durationMs: duration,
          );

          // Call completion callback if provided
          onComplete?.call();
        }
        return;
      }

      _rollupTickCount++;

      // V7: Update progress and trigger counter shake
      setState(() {
        _rollupProgress = _rollupTickCount / totalTicks;
        _counterShakeScale = 1.08; // Pulse up
      });

      // V7: Counter shake decay (quick pulse down)
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          setState(() => _counterShakeScale = 1.0);
        }
      });

      // P1.1: Pass progress context for volume/pitch escalation
      eventRegistry.triggerStage('ROLLUP_TICK', context: {'progress': _rollupProgress});
    });
  }

  /// Start rollup tick audio for tier progression
  /// Used when tier plaque IS the total win (BIG+ wins)
  void _startTierProgressionRollupTicks(int totalDurationMs) {
    // Use tick rate based on final tier (or 8 tps as default for big wins)
    const tickRate = 8; // Slower, more dramatic ticks for big wins
    final tickIntervalMs = (1000 / tickRate).round();
    final totalTicks = (totalDurationMs / tickIntervalMs).round();

    debugPrint('[SlotPreview] 🔊 Tier progression rollup: ${totalDurationMs}ms, $totalTicks ticks');

    _rollupTickCount = 0;
    _rollupTickTimer?.cancel();
    _rollupTickTimer = Timer.periodic(Duration(milliseconds: tickIntervalMs), (timer) {
      if (!mounted || _rollupTickCount >= totalTicks) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isRollingUp = false;
            _rollupProgress = 1.0;
          });
          eventRegistry.triggerStage('ROLLUP_END');
          debugPrint('[SlotPreview] 🔊 Tier rollup ROLLUP_END');
        }
        return;
      }

      _rollupTickCount++;
      setState(() {
        _rollupProgress = _rollupTickCount / totalTicks;
        _counterShakeScale = 1.06; // Subtle pulse
      });

      // Counter shake decay
      Future.delayed(const Duration(milliseconds: 40), () {
        if (mounted) setState(() => _counterShakeScale = 1.0);
      });

      // P1.1: Pass progress context for volume/pitch escalation
      eventRegistry.triggerStage('ROLLUP_TICK', context: {'progress': _rollupProgress});
    });
  }

  /// Format win amount with currency-style thousand separators + 2 decimals
  /// Industry standard: NetEnt, Pragmatic Play, IGT all use 2 decimal places
  /// Examples: 1234.50 → "1,234.50" | 50.00 → "50.00" | 1234567.89 → "1,234,567.89"
  String _formatWinAmount(double amount) {
    return _currencyFormatter.format(amount);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V11: RIGHT-TO-LEFT DIGIT REVEAL — Industry-standard slot machine counter
  // ═══════════════════════════════════════════════════════════════════════════
  // Pattern used by IGT, Aristocrat, Novomatic, NetEnt, Pragmatic Play:
  // - All digits start spinning (random values)
  // - RIGHTMOST digit LANDS FIRST (stops on final value)
  // - Each digit to the left lands progressively
  // - LEFTMOST digit lands LAST
  //
  // Examples for "1,234.56":
  // progress 0.0 → "?,???.??" (all spinning)
  // progress 0.3 → "?,???.56" (last 2 landed)
  // progress 0.5 → "?,?34.56" (last 4 landed)
  // progress 1.0 → "1,234.56" (all landed)
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // INDUSTRY-STANDARD ROLLUP DISPLAY
  // ═══════════════════════════════════════════════════════════════════════════
  // Pattern used by IGT, Aristocrat, Novomatic, NetEnt, Pragmatic Play:
  // - Value counts UP from 0 to target
  // - Digits appear naturally as value grows: $0.00 → $1.25 → $12.50 → $125.00
  // - Proper comma formatting maintained throughout
  // ═══════════════════════════════════════════════════════════════════════════

  /// Format rollup display — industry-standard counting up animation.
  /// Value grows from 0 to target, digits appear naturally as magnitude increases.
  String _formatRtlRollupDisplay(double targetAmount, double progress) {
    // Current value = target * progress (counts up from 0 to target)
    final currentValue = targetAmount * progress.clamp(0.0, 1.0);

    // Format with proper comma separators
    return _currencyFormatter.format(currentValue);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIER PROGRESSION — Progressive reveal from BIG to final tier
  // Flow: BIG_WIN_INTRO (0.5s) → BIG (4s) → SUPER (4s) → ... → BIG_WIN_END (4s) → Fade → Win Lines
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build list of tiers to progress through, from BIG up to finalTier
  List<String> _buildTierProgressionList(String finalTier) {
    final finalIndex = _allTiersInOrder.indexOf(finalTier);
    if (finalIndex < 0) return ['BIG_WIN_TIER_1']; // Fallback to just TIER_1
    return _allTiersInOrder.sublist(0, finalIndex + 1);
  }

  /// Start the tier progression sequence
  /// This shows BIG_WIN_INTRO, then progresses through each tier, then BIG_WIN_END
  /// The tier plaque IS the total win plaque — includes counter rollup
  void _startTierProgression(String finalTier, List<LineWin> lineWinsForPhase3, VoidCallback? onComplete) {
    // Build the list of tiers to show
    _tierProgressionList = _buildTierProgressionList(finalTier);
    _tierProgressionIndex = 0;
    _isInTierProgression = true;

    debugPrint('[SlotPreview] 🏆 Starting tier progression: $_tierProgressionList');

    // ═══════════════════════════════════════════════════════════════════════════
    // CALCULATE TOTAL ROLLUP DURATION
    // Counter broji kroz SVE tierove + BIG_WIN_END, zaustavlja se na kraju
    // ═══════════════════════════════════════════════════════════════════════════
    final numTiers = _tierProgressionList.length;
    // Counter STAJE na početku BIG_WIN_END (ne traje kroz END)
    final counterDurationMs = _bigWinIntroDurationMs +
                              (numTiers * _tierDisplayDurationMs);

    debugPrint('[SlotPreview] 🏆 Counter duration: ${counterDurationMs}ms (intro 500ms + ${numTiers} tiers × 4s) — STOPS at BIG_WIN_END');

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 1: BIG_WIN_INTRO (0.5s) — Entry fanfare
    // ═══════════════════════════════════════════════════════════════════════════
    eventRegistry.triggerStage('BIG_WIN_INTRO');

    // Show plaque immediately with first tier
    setState(() {
      _currentDisplayTier = _tierProgressionList.first;
      _isRollingUp = true;
      _rollupProgress = 0.0;
    });
    _winAmountController.forward(from: 0);

    // ═══════════════════════════════════════════════════════════════════════════
    // COUNTER: Broji SVE VREME dok traju tierovi, zaustavlja se na BIG_WIN_END
    // ═══════════════════════════════════════════════════════════════════════════
    _winCounterController.duration = Duration(milliseconds: counterDurationMs);
    _winCounterController.forward(from: 0);

    // Start ROLLUP audio
    eventRegistry.triggerStage('ROLLUP_START');
    _startTierProgressionRollupTicks(counterDurationMs);

    // V8: Screen flash for dramatic entrance
    setState(() => _showScreenFlash = true);
    _screenFlashController.forward(from: 0).then((_) {
      if (mounted) setState(() => _showScreenFlash = false);
    });

    // V8: Spawn celebration particles
    _spawnPlaqueCelebrationParticles(_tierProgressionList.first);

    debugPrint('[SlotPreview] 🏆 BIG_WIN_INTRO → showing ${_tierProgressionList.first}');

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 2: After intro (0.5s), start tier display sequence
    // ═══════════════════════════════════════════════════════════════════════════
    Future.delayed(const Duration(milliseconds: _bigWinIntroDurationMs), () {
      if (!mounted) return;
      // FIX: Guard against skip race condition
      if (widget.provider.skipRequested) {
        debugPrint('[SlotPreview] ⚠️ Tier progression skipped — skip was requested during intro');
        return;
      }
      _advanceTierProgression(lineWinsForPhase3, onComplete);
    });
  }

  /// Advance to the next tier in progression, or finish if done
  void _advanceTierProgression(List<LineWin> lineWinsForPhase3, VoidCallback? onComplete) {
    if (!mounted || !_isInTierProgression) return;

    // Trigger visual tier stage (optional — main audio is WIN_PRESENT_N)
    final currentTier = _tierProgressionList[_tierProgressionIndex];
    eventRegistry.triggerStage('WIN_TIER_$currentTier');
    debugPrint('[SlotPreview] 🏆 Tier ${_tierProgressionIndex + 1}/${_tierProgressionList.length}: $currentTier');

    // Update display
    setState(() {
      _currentDisplayTier = currentTier;
    });

    // Spawn particles for this tier
    _spawnWinParticles(currentTier);

    // ═══════════════════════════════════════════════════════════════════════════
    // After tier display duration (4s), advance to next tier or finish
    // ═══════════════════════════════════════════════════════════════════════════
    _tierProgressionTimer?.cancel();
    _tierProgressionTimer = Timer(const Duration(milliseconds: _tierDisplayDurationMs), () {
      if (!mounted) return;
      // FIX: Guard against skip race condition
      if (widget.provider.skipRequested) {
        debugPrint('[SlotPreview] ⚠️ Tier advance skipped — skip was requested');
        return;
      }

      _tierProgressionIndex++;

      // Check if we have more tiers to show
      if (_tierProgressionIndex < _tierProgressionList.length) {
        // Show next tier
        _advanceTierProgression(lineWinsForPhase3, onComplete);
      } else {
        // All tiers shown — proceed to BIG_WIN_END
        _finishTierProgression(lineWinsForPhase3, onComplete);
      }
    });
  }

  /// Finish tier progression: show BIG_WIN_END, then fade plaque, then win lines
  void _finishTierProgression(List<LineWin> lineWinsForPhase3, VoidCallback? onComplete) {
    if (!mounted) return;

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 3: BIG_WIN_END (4s) — Exit celebration / Outro
    // Plaketa prikazuje IME POSLEDNJEG TIER-A (ne menja se na "TOTAL")
    // Counter je već STAO (dostigao target na kraju tier-ova)
    // ═══════════════════════════════════════════════════════════════════════════
    eventRegistry.triggerStage('BIG_WIN_END');
    final lastTier = _currentDisplayTier;
    debugPrint('[SlotPreview] 🏆 BIG_WIN_END — plaque ostaje: $lastTier');

    // Plaketa OSTAJE sa poslednjim tier-om (ne menja se)
    // Counter je već stao i ostaje na finalnoj vrednosti
    // setState() NIJE potreban — _currentDisplayTier već ima pravi tier

    _tierProgressionTimer?.cancel();
    _tierProgressionTimer = Timer(const Duration(milliseconds: _bigWinEndDurationMs), () {
      if (!mounted) return;
      // FIX: Guard against skip race condition
      if (widget.provider.skipRequested) {
        debugPrint('[SlotPreview] ⚠️ Big win end skipped — skip was requested');
        return;
      }

      _isInTierProgression = false;

      // ═══════════════════════════════════════════════════════════════════════
      // STEP 4: Fade out plaque
      // ═══════════════════════════════════════════════════════════════════════
      debugPrint('[SlotPreview] 🏆 Tier progression complete — fading plaque');
      _winAmountController.reverse().then((_) {
        if (!mounted) return;

        // ═══════════════════════════════════════════════════════════════════
        // STEP 5: Start win line presentation
        // ═══════════════════════════════════════════════════════════════════
        if (lineWinsForPhase3.isNotEmpty) {
          debugPrint('[SlotPreview] 🎰 PHASE 3: Win lines (after tier progression)');
          _startWinLinePresentation(lineWinsForPhase3);
        } else {
          // V13: No win lines — win presentation is COMPLETE
          debugPrint('[SlotPreview] 🏁 Win presentation COMPLETE (big win, no lines)');
          widget.provider.setWinPresentationActive(false);
        }

        onComplete?.call();
      });
    });
  }

  /// Stop tier progression (on early interrupt/new spin)
  void _stopTierProgression() {
    _tierProgressionTimer?.cancel();
    _tierProgressionTimer = null;
    _rollupTickTimer?.cancel(); // Also stop rollup ticks
    _isInTierProgression = false;
    _isRollingUp = false;
    _tierProgressionList = [];
    _tierProgressionIndex = 0;

    // V13: Mark win presentation as COMPLETE — allows next spin
    // Note: This is called when spin interrupts tier progression
    widget.provider.setWinPresentationActive(false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PER-REEL ANTICIPATION EFFECTS — 2 seconds per reel with visual overlay
  // Industry standard: Anticipation slows down specific reels with visual cue
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start anticipation on a specific reel (2 second duration)
  /// Called from stage processing when ANTICIPATION_ON_X is detected
  void _startReelAnticipation(int reelIndex) {
    if (_anticipationReels.contains(reelIndex)) return; // Already anticipating

    debugPrint('[SlotPreview] 🎯 ANTICIPATION START: Reel $reelIndex (${_anticipationDurationMs}ms)');

    setState(() {
      _isAnticipation = true;
      _anticipationReels.add(reelIndex);
      _anticipationProgress[reelIndex] = 0.0;

      // P3.1: Calculate zoom based on number of reels in anticipation
      // More reels = more zoom (tension escalation)
      _anticipationZoom = _calculateAnticipationZoom();
    });

    // Trigger audio stage
    eventRegistry.triggerStage('ANTICIPATION_ON_$reelIndex', context: {'reel_index': reelIndex});

    // Update progress periodically for smooth animation
    const updateInterval = 50; // 50ms updates
    int elapsed = 0;
    _anticipationTimers[reelIndex]?.cancel();
    _anticipationTimers[reelIndex] = Timer.periodic(
      const Duration(milliseconds: updateInterval),
      (timer) {
        elapsed += updateInterval;
        final progress = (elapsed / _anticipationDurationMs).clamp(0.0, 1.0);

        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _anticipationProgress[reelIndex] = progress;
        });

        // End anticipation after 2 seconds
        if (elapsed >= _anticipationDurationMs) {
          timer.cancel();
          _endReelAnticipation(reelIndex);
        }
      },
    );
  }

  /// End anticipation on a specific reel
  void _endReelAnticipation(int reelIndex) {
    debugPrint('[SlotPreview] 🎯 ANTICIPATION END: Reel $reelIndex');

    _anticipationTimers[reelIndex]?.cancel();
    _anticipationTimers.remove(reelIndex);

    if (!mounted) return;

    setState(() {
      _anticipationReels.remove(reelIndex);
      _anticipationProgress.remove(reelIndex);
      // Update global flag
      _isAnticipation = _anticipationReels.isNotEmpty;

      // P3.1: Update zoom when reel leaves anticipation
      _anticipationZoom = _calculateAnticipationZoom();
    });

    // Trigger audio stage
    eventRegistry.triggerStage('ANTICIPATION_OFF_$reelIndex', context: {'reel_index': reelIndex});
  }

  /// Start anticipation effect - auto-starts on last reel(s) when potential big win
  void _startAnticipation(SlotLabSpinResult? result) {
    // Start anticipation on last 1-2 reels sequentially
    final anticipationReels = [widget.reels - 2, widget.reels - 1];

    for (int i = 0; i < anticipationReels.length; i++) {
      final reelIndex = anticipationReels[i];
      if (reelIndex >= 0) {
        // Stagger start times slightly for more dramatic effect
        Future.delayed(Duration(milliseconds: i * 200), () {
          if (mounted && _isSpinning) {
            _startReelAnticipation(reelIndex);
          }
        });
      }
    }
  }

  /// Stop all anticipation effects
  void _stopAnticipation() {
    // Cancel all timers
    for (final timer in _anticipationTimers.values) {
      timer.cancel();
    }
    _anticipationTimers.clear();

    setState(() {
      _isAnticipation = false;
      _anticipationReels = {};
      _anticipationProgress.clear();
      _anticipationTensionLevel.clear();
      _anticipationReason.clear();

      // P2.2: Clear anticipation particles
      _anticipationParticlePool.releaseAll(_anticipationParticles);
      _anticipationParticles.clear();

      // P3.1: Reset zoom
      _anticipationZoom = 1.0;
    });
  }

  /// P3.1: Calculate camera zoom based on anticipation state
  /// Zoom escalates with:
  /// 1. Number of reels in anticipation (more reels = more zoom)
  /// 2. Maximum tension level (higher tension = more zoom)
  double _calculateAnticipationZoom() {
    if (_anticipationReels.isEmpty) return 1.0;

    // Base zoom per reel: 1.02 per reel in anticipation
    final reelCount = _anticipationReels.length;
    final reelZoom = _anticipationZoomBase + (reelCount - 1) * 0.015;

    // Additional zoom for high tension (L3+: extra 0.01, L4: extra 0.02)
    double tensionBonus = 0.0;
    for (final reelIndex in _anticipationReels) {
      final tension = _anticipationTensionLevel[reelIndex] ?? 1;
      if (tension >= 4) {
        tensionBonus += 0.02;
      } else if (tension >= 3) {
        tensionBonus += 0.01;
      }
    }

    // Clamp to max zoom
    final totalZoom = (reelZoom + tensionBonus).clamp(1.0, _anticipationZoomMax);

    debugPrint('[SlotPreview] 🔍 ZOOM: $totalZoom (reels: $reelCount, tensionBonus: $tensionBonus)');
    return totalZoom;
  }

  /// Stop anticipation on a specific reel (e.g., when it lands)
  void _stopReelAnticipation(int reelIndex) {
    if (!_anticipationReels.contains(reelIndex)) return;
    _endReelAnticipation(reelIndex);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.3: PROVIDER CALLBACK HANDLERS — Visual-only (audio handled by provider)
  // These are called from SlotLabProvider when ANTICIPATION stages are processed
  // ═══════════════════════════════════════════════════════════════════════════

  /// P0.3: Handle anticipation start from provider (visual only, no audio)
  /// tensionLevel: 1-4, higher = more intense (based on NUMBER of reels in anticipation)
  void _onProviderAnticipationStart(int reelIndex, String reason, {int? tensionLevel}) {
    if (_anticipationReels.contains(reelIndex)) return; // Already anticipating

    // Calculate tension level based on NUMBER OF REELS already in anticipation
    // First anticipation reel = L1, second = L2, third = L3, fourth = L4
    // NOT based on reel index! (Reel 4 should not automatically be L4/red)
    final level = tensionLevel ?? (_anticipationReels.length + 1).clamp(1, 4);

    debugPrint('[SlotPreview] P0.3: PROVIDER ANTICIPATION START: reel=$reelIndex, reason=$reason, tension=L$level');

    setState(() {
      _isAnticipation = true;
      _anticipationReels.add(reelIndex);
      _anticipationProgress[reelIndex] = 0.0;
      _anticipationTensionLevel[reelIndex] = level;
      _anticipationReason[reelIndex] = reason;
    });

    // Slow down reel animation (P0.3 speed multiplier)
    _reelAnimController.setReelSpeedMultiplier(reelIndex, 0.3); // 30% speed

    // Start anticipation overlay animation
    _anticipationController.repeat(reverse: true);

    // Extend reel spin time
    _reelAnimController.extendReelSpinTime(reelIndex, _anticipationDurationMs);

    // Update progress periodically for smooth animation
    const updateInterval = 50; // 50ms updates
    int elapsed = 0;
    _anticipationTimers[reelIndex]?.cancel();
    _anticipationTimers[reelIndex] = Timer.periodic(
      const Duration(milliseconds: updateInterval),
      (timer) {
        elapsed += updateInterval;
        final progress = (elapsed / _anticipationDurationMs).clamp(0.0, 1.0);

        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _anticipationProgress[reelIndex] = progress;
        });

        if (elapsed >= _anticipationDurationMs) {
          timer.cancel();
          // Don't auto-end - wait for provider's ANTICIPATION_OFF callback
        }
      },
    );
  }

  /// P0.3: Handle anticipation end from provider (visual only, no audio)
  void _onProviderAnticipationEnd(int reelIndex) {
    if (!_anticipationReels.contains(reelIndex)) return;

    debugPrint('[SlotPreview] P0.3: PROVIDER ANTICIPATION END: reel=$reelIndex');

    _anticipationTimers[reelIndex]?.cancel();
    _anticipationTimers.remove(reelIndex);

    // Restore normal reel speed
    _reelAnimController.setReelSpeedMultiplier(reelIndex, 1.0);

    if (!mounted) return;

    setState(() {
      _anticipationReels.remove(reelIndex);
      _anticipationProgress.remove(reelIndex);
      _anticipationTensionLevel.remove(reelIndex);
      _anticipationReason.remove(reelIndex);
      _isAnticipation = _anticipationReels.isNotEmpty;
    });

    // Stop anticipation overlay if no more anticipating reels
    if (_anticipationReels.isEmpty) {
      _anticipationController.stop();
      _anticipationController.reset();

      // P2.2: Clear anticipation particles when all anticipation ends
      _anticipationParticlePool.releaseAll(_anticipationParticles);
      _anticipationParticles.clear();
    }
  }

  /// Trigger near miss visual effect with per-reel audio
  /// P3.3: Near-miss audio — different sounds depending on which reel "missed"
  void _triggerNearMiss(SlotLabSpinResult? result) {
    // Detect which reel(s) caused the near-miss
    final nearMissReels = _detectNearMissReels(result);

    // If no actual near-miss detected, don't show visual effect
    if (nearMissReels.isEmpty) {
      debugPrint('[SlotPreview] 🎯 No actual near-miss detected, skipping visual effect');
      return;
    }

    final nearMissType = _detectNearMissType(result);

    // Build positions set for visual effect
    final positions = <String>{};
    for (final reelIndex in nearMissReels) {
      // Near-miss symbols are typically in the middle row
      positions.add('$reelIndex,1');
    }

    setState(() {
      _isNearMiss = true;
      _nearMissPositions = positions;
    });

    // P3.3: Trigger per-reel near-miss audio stages
    for (final reelIndex in nearMissReels) {
      // Calculate pan position: L=-0.8, C=0.0, R=+0.8
      final pan = (reelIndex - (widget.reels - 1) / 2) * 0.4;
      // Calculate intensity: later reels = more dramatic (higher pitch/volume)
      final intensity = 0.7 + (reelIndex / widget.reels) * 0.3;

      eventRegistry.triggerStage('NEAR_MISS_REEL_$reelIndex', context: {
        'reel_index': reelIndex,
        'pan': pan.clamp(-1.0, 1.0),
        'intensity': intensity,
        'near_miss_type': nearMissType,
      });

      debugPrint('[SlotPreview] 🎯 Near-miss on reel $reelIndex (type: $nearMissType, pan: ${pan.toStringAsFixed(2)})');
    }

    // Also trigger generic near-miss stage for backwards compatibility
    eventRegistry.triggerStage('NEAR_MISS', context: {
      'reel_count': nearMissReels.length,
      'near_miss_type': nearMissType,
    });

    // Trigger type-specific near-miss stage
    if (nearMissType != 'generic') {
      eventRegistry.triggerStage('NEAR_MISS_${nearMissType.toUpperCase()}');
    }

    _nearMissController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _isNearMiss = false;
          _nearMissPositions = {};
        });
      }
    });
  }

  /// Detect which reels caused the near-miss by analyzing the grid
  /// Returns list of reel indices where the "miss" occurred
  Set<int> _detectNearMissReels(SlotLabSpinResult? result) {
    if (result == null || result.grid.isEmpty) {
      return {}; // No near-miss if no result data — don't default to last reel!
    }

    final nearMissReels = <int>{};
    final grid = result.grid;
    final rows = widget.rows;
    final middleRow = rows ~/ 2;

    // For each reel starting from reel 2, check if it "just missed" a match
    // A near-miss is when reels 0-1 (or 0-N) have matching symbols in a line,
    // but reel N+1 has the symbol just above or below the payline
    for (int reel = 2; reel < grid.length && reel < widget.reels; reel++) {
      final col = grid[reel];
      if (col.isEmpty) continue;

      // Check if the middle row symbol differs from a potential winning pattern
      // but the same symbol exists in adjacent rows
      final middleSymbol = col[middleRow];

      // Check if matching symbol is one row above or below (just missed)
      bool nearMissDetected = false;

      // Check row above middle (if exists)
      if (middleRow > 0 && col.length > middleRow - 1) {
        final aboveSymbol = col[middleRow - 1];
        // If the symbol above would have made a win with previous reels
        if (_wouldMakeWin(grid, reel, aboveSymbol)) {
          nearMissDetected = true;
        }
      }

      // Check row below middle (if exists)
      if (middleRow < rows - 1 && col.length > middleRow + 1) {
        final belowSymbol = col[middleRow + 1];
        // If the symbol below would have made a win with previous reels
        if (_wouldMakeWin(grid, reel, belowSymbol)) {
          nearMissDetected = true;
        }
      }

      if (nearMissDetected) {
        nearMissReels.add(reel);
      }
    }

    // If no specific near-miss detected, return empty set
    // DO NOT default to last reel - that causes false positive red background
    return nearMissReels;
  }

  /// Check if a symbol at a given reel would complete a winning pattern
  bool _wouldMakeWin(List<List<int>> grid, int reelIndex, int symbolId) {
    if (reelIndex < 2) return false;

    final rows = widget.rows;
    final middleRow = rows ~/ 2;

    // Check if all previous reels have this symbol in the middle row
    int matchingReels = 0;
    for (int r = 0; r < reelIndex; r++) {
      if (grid[r].length > middleRow && grid[r][middleRow] == symbolId) {
        matchingReels++;
      }
    }

    // If all previous reels match, this would have been a win
    return matchingReels == reelIndex;
  }

  /// Detect the type of near-miss (scatter, bonus, wild, jackpot, feature, generic)
  String _detectNearMissType(SlotLabSpinResult? result) {
    if (result == null) return 'generic';

    // Check if this was a near-miss for specific features
    // by looking at the grid for special symbols

    final grid = result.grid;
    int scatterCount = 0;
    int bonusCount = 0;
    int wildCount = 0;

    for (final col in grid) {
      for (final symbolId in col) {
        // Symbol ID conventions (based on SlotSymbol definitions):
        // 2 = Scatter, 3 = Wild, 13 = Bonus (check SlotSymbol.getSymbol)
        if (symbolId == 2) scatterCount++;
        if (symbolId == 3) wildCount++;
        if (symbolId == 13) bonusCount++;
      }
    }

    // Near-miss type based on what was "almost" achieved
    // 2 scatters = near-miss scatter (needed 3)
    if (scatterCount == 2) return 'scatter';
    // 2 bonus = near-miss bonus
    if (bonusCount == 2) return 'bonus';
    // Multiple wilds without win = near-miss wild
    if (wildCount >= 2 && !result.isWin) return 'wild';
    // Feature was almost triggered
    if (result.featureTriggered == false && scatterCount >= 1) return 'feature';

    return 'generic';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CASCADE / TUMBLE EFFECTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start cascade/tumble sequence
  void _startCascade(SlotLabSpinResult? result) {
    setState(() {
      _isCascading = true;
      _cascadeStep = 0;
      // Mark winning positions for pop animation
      _cascadePopPositions = Set.from(_winningPositions);
    });
  }

  /// Animate a cascade step (symbols popping and new ones falling)
  void _cascadeStepAnimation(SlotLabSpinResult? result) {
    setState(() {
      _cascadeStep++;
    });

    // Pop animation for winning symbols
    _cascadePopController.forward(from: 0).then((_) {
      if (mounted) {
        // After pop, spawn particles and reset
        _spawnCascadeParticles();
        setState(() {
          _cascadePopPositions = {};
        });
        _cascadePopController.reset();
      }
    });
  }

  /// Spawn particles for cascade pop effect
  void _spawnCascadeParticles() {
    for (final pos in _cascadePopPositions) {
      final parts = pos.split(',');
      if (parts.length != 2) continue;
      final reelIdx = int.tryParse(parts[0]) ?? 0;
      final rowIdx = int.tryParse(parts[1]) ?? 0;

      // Calculate normalized position
      final x = (reelIdx + 0.5) / widget.reels;
      final y = (rowIdx + 0.5) / widget.rows;

      // Spawn burst of particles at symbol position
      for (int i = 0; i < 5; i++) {
        _particles.add(_particlePool.acquire(
          x: x,
          y: y,
          vx: (_random.nextDouble() - 0.5) * 0.03,
          vy: (_random.nextDouble() - 0.5) * 0.03,
          size: _random.nextDouble() * 6 + 3,
          color: const Color(0xFFFFD700),
          type: _ParticleType.sparkle,
          rotation: _random.nextDouble() * math.pi * 2,
          rotationSpeed: (_random.nextDouble() - 0.5) * 0.3,
        ));
      }
    }
    _particleController.forward(from: 0);
  }

  /// End cascade sequence
  void _endCascade() {
    setState(() {
      _isCascading = false;
      _cascadeStep = 0;
      _cascadePopPositions = {};
    });
  }

  void _spawnWinParticles(String tier) {
    final particleCount = switch (tier) {
      'BIG_WIN_TIER_5' => 60,
      'BIG_WIN_TIER_4' => 45,
      'BIG_WIN_TIER_3' => 30,
      'BIG_WIN_TIER_1' || 'BIG_WIN_TIER_2' => 20,
      _ => 10,
    };

    // Use object pool to avoid GC pressure during win animations
    for (int i = 0; i < particleCount; i++) {
      _particles.add(_particlePool.acquire(
        x: _random.nextDouble(),
        y: _random.nextDouble() * 0.3 + 0.35, // Spawn around center
        vx: (_random.nextDouble() - 0.5) * 0.02,
        vy: -_random.nextDouble() * 0.015 - 0.005,
        size: _random.nextDouble() * 8 + 4,
        color: _getParticleColor(tier),
        type: _random.nextBool() ? _ParticleType.coin : _ParticleType.sparkle,
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.2,
      ));
    }

    _particleController.forward(from: 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V8: PLAQUE CELEBRATION PARTICLES — Burst from center on plaque entrance
  // Industry standard: explosion of gold coins and sparkles for dramatic effect
  // ═══════════════════════════════════════════════════════════════════════════
  void _spawnPlaqueCelebrationParticles(String tier) {
    final particleCount = switch (tier) {
      'BIG_WIN_TIER_5' => 80,
      'BIG_WIN_TIER_4' => 60,
      'BIG_WIN_TIER_3' => 45,
      'BIG_WIN_TIER_2' => 30,
      'BIG_WIN_TIER_1' => 20,
      _ => 10,
    };

    // Burst from center outward in all directions
    for (int i = 0; i < particleCount; i++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 0.02 + _random.nextDouble() * 0.03;

      _particles.add(_particlePool.acquire(
        x: 0.5, // Center X
        y: 0.45, // Center Y (slightly above middle for plaque position)
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 0.01, // Slight upward bias
        size: _random.nextDouble() * 10 + 5,
        color: _getParticleColor(tier),
        type: i % 3 == 0 ? _ParticleType.coin : _ParticleType.sparkle,
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 0.4,
      ));
    }

    _particleController.forward(from: 0);
  }

  Color _getParticleColor(String tier) {
    final colors = switch (tier) {
      'BIG_WIN_TIER_5' => [const Color(0xFFFF4080), const Color(0xFFFF66FF), const Color(0xFFFFD700)],
      'BIG_WIN_TIER_4' => [const Color(0xFFE040FB), const Color(0xFFFF66FF), const Color(0xFF40C8FF)],
      'BIG_WIN_TIER_3' => [const Color(0xFFFFD700), const Color(0xFFFFE55C), const Color(0xFFFF9040)],
      'BIG_WIN_TIER_2' => [const Color(0xFF40C8FF), const Color(0xFF81D4FA), const Color(0xFF4FC3F7)],
      'BIG_WIN_TIER_1' => [const Color(0xFF40FF90), const Color(0xFF4CAF50), const Color(0xFFFFEB3B)],
      _ => [const Color(0xFFFFD700)],
    };
    return colors[_random.nextInt(colors.length)];
  }

  @override
  Widget build(BuildContext context) {
    // Check for reduced motion preference (accessibility)
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // ═══════════════════════════════════════════════════════════════════════════
    // KEYBOARD HANDLING — Removed nested Focus to fix focus conflict!
    // Parent (slot_lab_screen.dart) now handles Space key and calls handleSpaceKey()
    // ═══════════════════════════════════════════════════════════════════════════
    return LayoutBuilder(
        builder: (context, constraints) {
          final borderColor = _winningReels.isNotEmpty
              ? _getWinBorderColor()
              : _isSpinning
                  ? FluxForgeTheme.accentBlue.withOpacity(0.4)
                  : const Color(0xFF2A2A38);

          // ═══════════════════════════════════════════════════════════════════════
          // V2: Screen Shake — subtle shake when last reel lands
          // ═══════════════════════════════════════════════════════════════════════
          final shakeOffsetX = _screenShakeActive ? (_random.nextDouble() - 0.5) * 4 : 0.0;
          final shakeOffsetY = _screenShakeActive ? (_random.nextDouble() - 0.5) * 3 : 0.0;

          return Transform.translate(
          offset: Offset(shakeOffsetX, shakeOffsetY),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              // Main slot container
              Container(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0D0D14), Color(0xFF080810), Color(0xFF050508)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 2),
                  boxShadow: _winningReels.isNotEmpty
                      ? [
                          BoxShadow(
                            color: _getWinGlowColor().withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  // P3.1: Apply anticipation zoom to reel table
                  // Zoom escalates with number of reels in anticipation
                  child: AnimatedScale(
                    scale: _anticipationZoom,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: _buildReelTable(constraints.maxWidth - 12, constraints.maxHeight - 12),
                  ),
                ),
              ),

              // ═══════════════════════════════════════════════════════════════════════
              // P2.1: ANTICIPATION VIGNETTE — Dark edges grow with tension level
              // Intensity increases as more reels enter anticipation
              // ═══════════════════════════════════════════════════════════════════════
              if (_isAnticipation && !reduceMotion)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _anticipationPulse,
                      builder: (context, child) {
                        // Calculate max tension level across all anticipating reels
                        final maxTension = _anticipationTensionLevel.values.fold<int>(
                          1, (max, level) => level > max ? level : max,
                        );
                        // Get color for highest tension level
                        final vignetteColor = _tensionColors[maxTension] ?? const Color(0xFFFFD700);
                        // Intensity based on tension (L1=0.3, L2=0.4, L3=0.5, L4=0.6)
                        final baseIntensity = 0.2 + (maxTension * 0.1);
                        final pulseValue = _anticipationPulse.value.clamp(0.0, 1.0);

                        return CustomPaint(
                          painter: _AnticipationVignettePainter(
                            intensity: (baseIntensity + pulseValue * 0.1).clamp(0.0, 1.0),
                            color: vignetteColor,
                            pulseValue: pulseValue,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // ═══════════════════════════════════════════════════════════════════════
              // P2.2: ANTICIPATION PARTICLE TRAIL — Rising sparkles during anticipation
              // Intensity escalates per tension level (L1: subtle, L4: intense)
              // ═══════════════════════════════════════════════════════════════════════
              if (_anticipationParticles.isNotEmpty && !reduceMotion)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _anticipationPulse,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _AnticipationTrailPainter(
                            particles: _anticipationParticles,
                            pulseValue: _anticipationPulse.value.clamp(0.0, 1.0),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // ═══════════════════════════════════════════════════════════════════════
              // V5: BIG WIN BACKGROUND EFFECT — Industry standard celebration atmosphere
              // Vignette (dark edges) + Color wash (tier-colored glow)
              // Only shows for BIG tier and above
              // ═══════════════════════════════════════════════════════════════════════
              if (_winTier.isNotEmpty && !reduceMotion)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _winPulseAnimation,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _BigWinBackgroundPainter(
                            tier: _winTier,
                            pulseValue: _winPulseAnimation.value.clamp(0.0, 1.0),
                            tierColor: _getWinGlowColor(),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Win line layer — draws connecting lines between winning symbols
              // P1.2: Line "grows" from first to last symbol (250ms animation)
              if (_isShowingWinLines && _currentPresentingLine != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WinLinePainter(
                      positions: _currentPresentingLine!.positions,
                      reelCount: widget.reels,
                      rowCount: widget.rows,
                      pulseValue: _winPulseAnimation.value.clamp(0.0, 1.0),
                      lineColor: _getWinGlowColor(),
                      drawProgress: _lineDrawProgress, // P1.2: 0→1 during animation
                    ),
                  ),
                ),

              // Particle layer (respects reduced motion preference)
              if (_particles.isNotEmpty && !reduceMotion)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ParticlePainter(particles: _particles),
                  ),
                ),

              // ═══════════════════════════════════════════════════════════════════════
              // V8: SCREEN FLASH — Dramatic entrance effect for BIG+ wins
              // Quick white/gold flash when plaque appears
              // ═══════════════════════════════════════════════════════════════════════
              if (_showScreenFlash && !reduceMotion)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _screenFlashOpacity,
                      builder: (context, _) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.center,
                              radius: 0.8,
                              colors: [
                                _getWinGlowColor().withOpacity((_screenFlashOpacity.value * 0.7).clamp(0.0, 1.0)),
                                Colors.white.withOpacity((_screenFlashOpacity.value * 0.3).clamp(0.0, 1.0)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Win amount overlay — shown for ALL wins (small and big)
              // The overlay itself checks _winAmountOpacity.value to hide when faded out
              // BUG FIX: Previously only showed for _winTier.isNotEmpty (big wins)
              // Now shows when: tier exists OR win amount is being displayed
              // 🔴 CRITICAL: Only show if showWinPresentation=true (prevents double plaque in PremiumSlotPreview)
              if (widget.showWinPresentation && (_winTier.isNotEmpty || _targetWinAmount > 0))
                Positioned.fill(
                  child: _buildWinOverlay(constraints),
                ),
            ],
          ),
        ),
        ); // Close Transform.translate for screen shake
        },
      );
  }

  /// Whether this widget can handle SPACE key (true when spinning)
  bool get canHandleSpaceKey => _isSpinning;

  /// Handle SPACE key — Skip/stop spin immediately
  /// PUBLIC: Parent calls this when Space is pressed and canHandleSpaceKey is true
  void handleSpaceKey() {
    if (_isSpinning) {
      debugPrint('[SlotPreview] ⏹ SPACE pressed — stopping all reels immediately');

      // 1. Stop visual animation immediately
      _reelAnimController.stopImmediately();

      // 2. Update display grid to target (final) values
      setState(() {
        for (int r = 0; r < widget.reels && r < _targetGrid.length; r++) {
          for (int row = 0; row < widget.rows && row < _targetGrid[r].length; row++) {
            _displayGrid[r][row] = _targetGrid[r][row];
          }
        }
      });

      // 3. Finalize spin (sets _spinFinalized = true, _isSpinning = false)
      final result = widget.provider.lastResult;
      if (result != null) {
        _finalizeSpin(result);
      }

      // 4. THEN stop provider stage timers (notifies listeners)
      // CRITICAL ORDER: _finalizeSpin() MUST be called BEFORE stopStagePlayback()!
      // This way _onProviderUpdate() sees _spinFinalized = true when !isPlaying,
      // allowing it to reset _spinFinalized = false for the next spin.
      widget.provider.stopStagePlayback();

      // Notify parent that we handled the space key
      widget.onSpaceKeyHandled?.call();
    }
  }

  /// Get the tier to display (current tier during progression, or final tier)
  String get _displayTier => _currentDisplayTier.isNotEmpty ? _currentDisplayTier : _winTier;

  Color _getWinBorderColor() {
    final baseColor = switch (_displayTier) {
      'BIG_WIN_TIER_5' => const Color(0xFFFF4080),
      'BIG_WIN_TIER_4' => const Color(0xFFE040FB),
      'BIG_WIN_TIER_3' => const Color(0xFFFFD700),
      'BIG_WIN_TIER_2' => const Color(0xFF40C8FF),
      'BIG_WIN_TIER_1' => FluxForgeTheme.accentGreen,
      'TOTAL' => const Color(0xFFFFD700),  // Gold for TOTAL WIN (outro)
      _ => FluxForgeTheme.accentGreen,
    };
    return baseColor.withOpacity(_winPulseAnimation.value.clamp(0.0, 1.0));
  }

  Color _getWinGlowColor() {
    return switch (_displayTier) {
      'BIG_WIN_TIER_5' => const Color(0xFFFF4080),
      'BIG_WIN_TIER_4' => const Color(0xFFE040FB),
      'BIG_WIN_TIER_3' => const Color(0xFFFFD700),
      'BIG_WIN_TIER_2' => const Color(0xFF40C8FF),
      'BIG_WIN_TIER_1' => FluxForgeTheme.accentGreen,
      'TOTAL' => const Color(0xFFFFD700),  // Gold for TOTAL WIN (outro)
      _ => FluxForgeTheme.accentGreen,
    };
  }

  Widget _buildWinOverlay(BoxConstraints constraints) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _winAmountScale,
        _winAmountOpacity,
        _winPulseAnimation,
        _plaqueGlowPulse, // V8: Enhanced glow animation
      ]),
      builder: (context, child) {
        if (_winAmountOpacity.value < 0.01) return const SizedBox.shrink();

        // ═══════════════════════════════════════════════════════════════════════
        // V8: ENHANCED PLAQUE ENTRANCE — More dramatic slide + scale + glow
        // Industry standard: NetEnt, Pragmatic Play dramatic celebration
        // ═══════════════════════════════════════════════════════════════════════

        // Get current display tier for visual calculations
        final tier = _displayTier;

        // Slide from above: starts at -80px for BIG+ wins
        const slideDistance = -80.0;
        final slideProgress = Curves.elasticOut.transform(_winAmountScale.value.clamp(0.0, 1.0));
        final slideOffset = (1.0 - slideProgress) * slideDistance;

        // V8: Scale with tier-based overshoot (bigger tiers = bigger overshoot)
        final scaleMultiplier = switch (tier) {
          'BIG_WIN_TIER_5' => 1.25,
          'BIG_WIN_TIER_4' => 1.2,
          'BIG_WIN_TIER_3' => 1.15,
          'BIG_WIN_TIER_2' => 1.12,
          'BIG_WIN_TIER_1' => 1.1,
          'TOTAL' => 1.05,  // Slightly smaller for outro/total
          _ => 1.0,
        };
        final scale = _winAmountScale.value * scaleMultiplier;

        // V8: Pulsing scale effect during display (subtle breathing)
        final pulseScale = 1.0 + (_plaqueGlowPulse.value - 0.85) * 0.03;

        return Opacity(
          opacity: _winAmountOpacity.value,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // V4: BURST EFFECT — Radiating lines behind plaque
                if (_winAmountScale.value > 0.5)
                  CustomPaint(
                    size: Size(constraints.maxWidth * 0.8, constraints.maxHeight * 0.6),
                    painter: _PlaqueBurstPainter(
                      progress: _winAmountScale.value.clamp(0.0, 1.0),
                      pulseValue: _winPulseAnimation.value.clamp(0.0, 1.0),
                      tierColor: _getWinGlowColor(),
                      rayCount: tier == 'BIG_WIN_TIER_5' || tier == 'BIG_WIN_TIER_4' ? 16 : 12,
                    ),
                  ),
                // Main plaque with slide + scale + pulse
                Transform.translate(
                  offset: Offset(0, slideOffset),
                  child: Transform.scale(
                    scale: (scale * pulseScale).clamp(0.0, 1.35), // Allow larger scale for dramatic effect
                    child: _buildWinDisplay(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Win display — Tier plaketa SA coin counterom
  /// NE prikazuje info o simbolima/win linijama (npr. "3x Grapes")
  /// Uses _displayTier which updates during tier progression
  ///
  /// ULTIMATIVNO: Podržava P5 tier ID-ove (WIN_1, WIN_2, TIER_1, TIER_2, itd.)
  Widget _buildWinDisplay() {
    // Get current tier for display (updates during progression)
    final tier = _displayTier;

    // Helper: Check if tier is a big win (TIER_1..TIER_5) or outro
    final isBigWinTier = ['BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3', 'BIG_WIN_TIER_4', 'BIG_WIN_TIER_5', 'TOTAL'].contains(tier);

    // Boje bazirane na tier-u
    // Big wins: progression od zelene do crvene/pink
    // Regular wins (WIN_1, WIN_2, itd.): sve su zelene (industry standard)
    final tierColors = switch (tier) {
      'BIG_WIN_TIER_5' => [const Color(0xFFFF4080), const Color(0xFFFF66FF), const Color(0xFFFFD700)],
      'BIG_WIN_TIER_4' => [const Color(0xFFE040FB), const Color(0xFFFF66FF), const Color(0xFF40C8FF)],
      'BIG_WIN_TIER_3' => [const Color(0xFFFFD700), const Color(0xFFFFE55C), const Color(0xFFFF9040)],
      'BIG_WIN_TIER_2' => [const Color(0xFF40C8FF), const Color(0xFF81D4FA), const Color(0xFF4FC3F7)],
      'BIG_WIN_TIER_1' => [const Color(0xFF40FF90), const Color(0xFF88FF88), const Color(0xFFFFEB3B)],
      'TOTAL' => [const Color(0xFFFFD700), const Color(0xFFFFE55C), const Color(0xFFFFFFFF)],  // Gold outro
      // Regular wins — sve zelene
      _ => [const Color(0xFF40FF90), const Color(0xFF4CAF50)],
    };

    // Tier label tekst — P5 CONFIGURABLE SYSTEM
    // Uses SlotLabProjectProvider.winConfiguration for fully customizable labels
    final tierLabel = _getP5TierLabel(tier);

    // Font size baziran na tier-u
    // Big wins: veći fontovi za dramatičnost
    // Regular wins: manji, ali čitljivi
    final tierFontSize = switch (tier) {
      'BIG_WIN_TIER_5' => 48.0,
      'BIG_WIN_TIER_4' => 44.0,
      'BIG_WIN_TIER_3' => 40.0,
      'BIG_WIN_TIER_2' => 36.0,
      'BIG_WIN_TIER_1' => 32.0,
      'TOTAL' => 36.0,  // TOTAL WIN (outro) — medium size
      _ => 28.0,  // Regular wins (WIN_1, WIN_2, itd.)
    };

    // Counter font size
    final counterFontSize = switch (tier) {
      'BIG_WIN_TIER_5' => 72.0,
      'BIG_WIN_TIER_4' => 64.0,
      'BIG_WIN_TIER_3' => 56.0,
      'BIG_WIN_TIER_2' => 52.0,
      'BIG_WIN_TIER_1' => 48.0,
      'TOTAL' => 56.0,  // TOTAL WIN (outro) — emphasize final amount
      _ => 40.0,  // Regular wins
    };

    // ═══════════════════════════════════════════════════════════════════════════
    // V9: PREMIUM TIER PLAKETA + COIN COUNTER
    // Clean, modern design without loading simulation
    // Industry standard: NetEnt, Pragmatic Play, Big Time Gaming
    // ═══════════════════════════════════════════════════════════════════════════

    // V8: Animated glow intensity based on plaque pulse
    // CRITICAL: Clamp to 0.0-1.0 to prevent assertion errors in withOpacity()
    final glowIntensity = _plaqueGlowPulse.value.clamp(0.0, 1.0);
    final borderOpacity = (0.6 + (glowIntensity * 0.4)).clamp(0.0, 1.0); // 0.6 to 1.0
    final shadowIntensity = (0.3 + (glowIntensity * 0.4)).clamp(0.0, 1.0); // 0.3 to 0.7

    // V8: Tier-based glow radius (bigger tiers = bigger glow)
    final baseGlowRadius = switch (tier) {
      'BIG_WIN_TIER_5' => 60.0,
      'BIG_WIN_TIER_4' => 55.0,
      'BIG_WIN_TIER_3' => 50.0,
      'BIG_WIN_TIER_2' => 45.0,
      'BIG_WIN_TIER_1' => 40.0,
      'TOTAL' => 35.0,  // TOTAL WIN (outro) — subtle glow for conclusion
      _ => 30.0,  // Regular wins (WIN_1, WIN_2, itd.)
    };

    // ═══════════════════════════════════════════════════════════════════════════
    // V10: ULTRA PREMIUM WIN PLAQUE — Casino-quality visual presentation
    // Inspired by: NetEnt, Pragmatic Play, Big Time Gaming premium slots
    // Features: Metallic gradients, glossy highlights, dramatic glow, decorative stars
    // ═══════════════════════════════════════════════════════════════════════════

    return Stack(
      alignment: Alignment.center,
      children: [
        // LAYER 1: Outer dramatic glow (largest, most diffuse)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              // Massive ambient glow
              BoxShadow(
                color: tierColors.first.withOpacity(shadowIntensity * 0.6),
                blurRadius: baseGlowRadius * 4,
                spreadRadius: 30,
              ),
              // Secondary color glow for richness
              if (tierColors.length > 1)
                BoxShadow(
                  color: tierColors[1].withOpacity(shadowIntensity * 0.3),
                  blurRadius: baseGlowRadius * 3,
                  spreadRadius: 20,
                ),
            ],
          ),
        ),

        // LAYER 2: Main plaque container with premium styling
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
          decoration: BoxDecoration(
            // Premium multi-layer gradient background
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                // Top: Lighter for glossy effect
                tierColors.first.withOpacity(0.35),
                // Upper middle: Rich tier color
                tierColors.first.withOpacity(0.15),
                // Lower middle: Dark for depth
                Colors.black.withOpacity(0.85),
                // Bottom: Slight tier tint
                tierColors.first.withOpacity(0.1),
              ],
              stops: const [0.0, 0.2, 0.6, 1.0],
            ),
            borderRadius: BorderRadius.circular(24),
            // Double border effect - outer glow + inner metallic
            border: Border.all(
              color: tierColors.first.withOpacity(borderOpacity),
              width: 3,
            ),
            boxShadow: [
              // Inner shadow for depth (inset effect)
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 15,
                spreadRadius: -5,
                offset: const Offset(0, 5),
              ),
              // Primary tier glow
              BoxShadow(
                color: tierColors.first.withOpacity(shadowIntensity * 0.9),
                blurRadius: baseGlowRadius * 1.5,
                spreadRadius: 5,
              ),
              // Pulsing outer glow
              BoxShadow(
                color: tierColors.first.withOpacity(shadowIntensity * 0.6 * glowIntensity),
                blurRadius: baseGlowRadius * 2.5 * glowIntensity,
                spreadRadius: 12 * glowIntensity,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ═══════════════════════════════════════════════════════════════
              // DECORATIVE STARS ROW — Above tier label
              // ═══════════════════════════════════════════════════════════════
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDecorativeStar(tierColors.first, 16, glowIntensity),
                  const SizedBox(width: 8),
                  _buildDecorativeStar(tierColors.first, 20, glowIntensity),
                  const SizedBox(width: 8),
                  _buildDecorativeStar(tierColors.first, 24, glowIntensity),
                  const SizedBox(width: 8),
                  _buildDecorativeStar(tierColors.first, 20, glowIntensity),
                  const SizedBox(width: 8),
                  _buildDecorativeStar(tierColors.first, 16, glowIntensity),
                ],
              ),
              const SizedBox(height: 8),

              // ═══════════════════════════════════════════════════════════════
              // TIER LABEL — Premium metallic text with enhanced styling
              // NOTE: Tier escalation indicator (T1 → T2 → T3) removed per user request
              //       Only the current tier label is shown on the plaque
              // ═══════════════════════════════════════════════════════════════
              Stack(
                children: [
                  // Background glow layer
                  ShaderMask(
                    shaderCallback: (bounds) => RadialGradient(
                      colors: [
                        tierColors.first,
                        tierColors.first.withOpacity(0.5),
                        Colors.transparent,
                      ],
                    ).createShader(bounds),
                    child: Text(
                      tierLabel,
                      style: TextStyle(
                        fontSize: tierFontSize + 2,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withOpacity(0.3),
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                  // Main text with metallic gradient
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        tierColors.first,
                        tierColors.length > 1 ? tierColors[1] : tierColors.first,
                        Colors.white.withOpacity(0.9),
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ).createShader(bounds),
                    child: Text(
                      tierLabel,
                      style: TextStyle(
                        fontSize: tierFontSize,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 5,
                        shadows: [
                          // Sharp inner shadow for emboss effect
                          Shadow(
                            color: Colors.black.withOpacity(0.8),
                            blurRadius: 2,
                            offset: const Offset(1, 2),
                          ),
                          // Primary tier glow
                          Shadow(
                            color: tierColors.first,
                            blurRadius: 25,
                          ),
                          // Outer ambient glow
                          Shadow(
                            color: tierColors.first.withOpacity(0.7),
                            blurRadius: 40,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ═══════════════════════════════════════════════════════════════
              // WIN AMOUNT COUNTER — Ultra premium styling
              // ═══════════════════════════════════════════════════════════════
              Transform.scale(
                scale: 1.0 + (_plaqueGlowPulse.value - 0.85) * 0.06,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    // Subtle background for counter area
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.4),
                        tierColors.first.withOpacity(0.1),
                        Colors.black.withOpacity(0.4),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: tierColors.first.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        const Color(0xFFFFD700), // Gold
                        tierColors.first,
                        Colors.white,
                      ],
                      stops: const [0.0, 0.25, 0.75, 1.0],
                    ).createShader(bounds),
                    // V11: RTL DIGIT REVEAL — Digits land from right to left
                    // Uses _rtlRollupProgress to reveal digits progressively
                    // Combined with numeric counting for complete slot machine effect
                    // S desna na levo, brzina kao u big win-u!
                    child: Text(
                      _isRollingUp
                          ? _formatRtlRollupDisplay(_targetWinAmount, _rtlRollupProgress)
                          : _formatWinAmount(_displayedWinAmount),
                      style: TextStyle(
                        fontSize: counterFontSize,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 3,
                        height: 1.1,
                        shadows: [
                          // Crisp inner highlight
                          const Shadow(
                            color: Colors.white,
                            blurRadius: 4,
                          ),
                          // Deep shadow for 3D effect
                          Shadow(
                            color: Colors.black.withOpacity(0.9),
                            blurRadius: 3,
                            offset: const Offset(2, 3),
                          ),
                          // Primary glow
                          Shadow(
                            color: tierColors.first.withOpacity(0.95),
                            blurRadius: 35,
                          ),
                          // Gold accent glow
                          const Shadow(
                            color: Color(0xFFFFD700),
                            blurRadius: 25,
                          ),
                          // Pulsing outer glow
                          Shadow(
                            color: tierColors.first.withOpacity(glowIntensity * 0.9),
                            blurRadius: 60 * glowIntensity,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ═══════════════════════════════════════════════════════════════
              // DECORATIVE STARS ROW — Below counter
              // ═══════════════════════════════════════════════════════════════
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDecorativeStar(tierColors.first, 14, glowIntensity),
                  const SizedBox(width: 6),
                  _buildDecorativeStar(tierColors.first, 18, glowIntensity),
                  const SizedBox(width: 6),
                  _buildDecorativeStar(tierColors.first, 14, glowIntensity),
                ],
              ),

              // ═══════════════════════════════════════════════════════════════
              // WIN PROGRESS INDICATOR — Shows rollup progress (FIX: Race condition preporuka)
              // ═══════════════════════════════════════════════════════════════
              if (_isRollingUp || _rollupProgress > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildWinProgressIndicator(tierColors.first, glowIntensity),
                ),
            ],
          ),
        ),

        // LAYER 3: Glossy highlight overlay (top shine)
        Positioned(
          top: 0,
          left: 20,
          right: 20,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.25),
                  Colors.white.withOpacity(0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build decorative star for premium plaque
  /// Animated with glow pulse for dynamic effect
  Widget _buildDecorativeStar(Color color, double size, double glowIntensity) {
    return Container(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow behind star
          Container(
            width: size * 0.8,
            height: size * 0.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6 * glowIntensity),
                  blurRadius: size * 0.5,
                  spreadRadius: size * 0.1,
                ),
              ],
            ),
          ),
          // Star icon
          Icon(
            Icons.star,
            size: size,
            color: color,
            shadows: [
              Shadow(
                color: Colors.white.withOpacity(0.8),
                blurRadius: 2,
              ),
              Shadow(
                color: color,
                blurRadius: 8,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════════
  /// WIN PROGRESS INDICATOR — Horizontal progress bar during rollup animation
  /// ═══════════════════════════════════════════════════════════════════════════
  /// Shows visual feedback of rollup progress (0.0 → 1.0) with tier-colored glow.
  /// Appears below the win amount during rollup, fades when complete.
  Widget _buildWinProgressIndicator(Color tierColor, double glowIntensity) {
    final progress = _rollupProgress.clamp(0.0, 1.0);
    final isComplete = progress >= 1.0;

    // Fade out when complete
    final opacity = isComplete ? 0.0 : 1.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: opacity,
      child: Container(
        width: 200,
        height: 8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Colors.black.withOpacity(0.4),
          border: Border.all(
            color: tierColor.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: tierColor.withOpacity(0.2 * glowIntensity),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              // Background track
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.grey.shade900,
                      Colors.grey.shade800,
                    ],
                  ),
                ),
              ),
              // Progress fill
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tierColor.withOpacity(0.8),
                        tierColor,
                        HSLColor.fromColor(tierColor)
                            .withLightness(
                              (HSLColor.fromColor(tierColor).lightness + 0.2)
                                  .clamp(0.0, 1.0),
                            )
                            .toColor(),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tierColor.withOpacity(0.6 * glowIntensity),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              // Shimmer effect on progress edge
              if (progress > 0.05 && progress < 1.0)
                Positioned(
                  left: (progress * 200) - 4,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.6),
                          Colors.transparent,
                        ],
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

  /// Build reel grid using Table for precise layout without overflow
  Widget _buildReelTable(double availableWidth, double availableHeight) {
    // Calculate SQUARE cell size - leave space on sides for other elements
    final cellWidth = availableWidth / widget.reels;
    final cellHeight = availableHeight / widget.rows;
    final cellSize = math.min(cellWidth, cellHeight) * 0.82; // Smaller to leave space L/R

    // Calculate table dimensions for overlay positioning
    final tableWidth = cellSize * widget.reels;
    final tableHeight = cellSize * widget.rows;
    final tableOffsetX = (availableWidth - tableWidth) / 2;
    final tableOffsetY = (availableHeight - tableHeight) / 2;

    return Stack(
      children: [
        // Main table
        Center(
          child: Table(
            defaultColumnWidth: FixedColumnWidth(cellSize),
            children: List.generate(widget.rows, (rowIndex) {
              return TableRow(
                children: List.generate(widget.reels, (reelIndex) {
                  return _buildSymbolCell(reelIndex, rowIndex, cellSize);
                }),
              );
            }),
          ),
        ),

        // Per-reel anticipation overlays
        ..._anticipationReels.map((reelIndex) {
          final progress = _anticipationProgress[reelIndex] ?? 0.0;
          final reelX = tableOffsetX + (reelIndex * cellSize);

          return Positioned(
            left: reelX,
            top: tableOffsetY - 30, // Above the reel
            width: cellSize,
            child: _buildAnticipationOverlay(reelIndex, progress, cellSize, tableHeight),
          );
        }),

        // P1.2: Scatter counter badge — Shows "2/3" when anticipation is active
        if (_isAnticipation && _scatterReels.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: tableOffsetY - 60, // Above anticipation overlays
            child: Center(
              child: _buildScatterCounterBadge(),
            ),
          ),
      ],
    );
  }

  /// P1.2: Build scatter counter badge widget
  /// Shows current scatter count vs required (e.g., "2/3 SCATTERS")
  Widget _buildScatterCounterBadge() {
    final currentCount = _scatterReels.length;
    final requiredCount = 3; // Standard: 3 scatters for free spins
    final isComplete = currentCount >= requiredCount;

    // Get tension color based on how close we are
    final Color badgeColor;
    if (isComplete) {
      badgeColor = const Color(0xFF40FF90); // Green - triggered!
    } else if (currentCount >= 2) {
      badgeColor = const Color(0xFFFF4500); // Red - almost there!
    } else {
      badgeColor = const Color(0xFFFFD700); // Gold - building
    }

    return AnimatedBuilder(
      animation: _anticipationPulse,
      builder: (context, child) {
        final pulseValue = _anticipationPulse.value.clamp(0.0, 1.0);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: badgeColor.withOpacity((0.8 + pulseValue * 0.2).clamp(0.0, 1.0)),
              width: 2 + pulseValue,
            ),
            boxShadow: [
              BoxShadow(
                color: badgeColor.withOpacity((0.4 + pulseValue * 0.3).clamp(0.0, 1.0)),
                blurRadius: 15 + pulseValue * 10,
                spreadRadius: 2 + pulseValue * 3,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Scatter icon
              Text(
                '💎',
                style: TextStyle(fontSize: 18 + pulseValue * 2),
              ),
              const SizedBox(width: 8),
              // Counter text
              Text(
                '$currentCount/$requiredCount',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 20 + pulseValue * 2,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: badgeColor.withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Label
              Text(
                isComplete ? 'TRIGGERED!' : 'SCATTERS',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build anticipation overlay for a specific reel
  /// Uses tension level for color progression: L1=Gold → L2=Orange → L3=Red-Orange → L4=Red
  Widget _buildAnticipationOverlay(int reelIndex, double progress, double width, double tableHeight) {
    final pulseValue = _anticipationPulse.value.clamp(0.0, 1.0);
    final tensionLevel = _anticipationTensionLevel[reelIndex] ?? 1;
    final color = _tensionColors[tensionLevel] ?? const Color(0xFFFFD700);

    // Intensity multiplier based on tension level (higher tension = more intense effect)
    final intensityMultiplier = 0.7 + (tensionLevel * 0.1); // L1=0.8, L2=0.9, L3=1.0, L4=1.1

    return AnimatedBuilder(
      animation: _anticipationPulse,
      builder: (context, child) {
        // Re-clamp inside builder to ensure animation updates are also clamped
        final safePulse = _anticipationPulse.value.clamp(0.0, 1.0);
        // Glowing border animation around the reel - intensity scales with tension
        return Container(
          width: width + 8, // Slightly wider than reel for border visibility
          height: tableHeight + 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            // Pulsing outer glow - intensity scales with tension level
            boxShadow: [
              BoxShadow(
                color: color.withOpacity((safePulse * 0.8 * intensityMultiplier).clamp(0.0, 1.0)),
                blurRadius: (20 + (safePulse * 15)) * intensityMultiplier,
                spreadRadius: (2 + (safePulse * 4)) * intensityMultiplier,
              ),
              BoxShadow(
                color: color.withOpacity((safePulse * 0.5 * intensityMultiplier).clamp(0.0, 1.0)),
                blurRadius: (40 + (safePulse * 20)) * intensityMultiplier,
                spreadRadius: (4 + (safePulse * 6)) * intensityMultiplier,
              ),
              // Extra outer glow for high tension levels (L3, L4)
              if (tensionLevel >= 3)
                BoxShadow(
                  color: color.withOpacity((safePulse * 0.3).clamp(0.0, 1.0)),
                  blurRadius: 60 + (safePulse * 30),
                  spreadRadius: 8 + (safePulse * 8),
                ),
            ],
            // Animated gradient border
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withOpacity((safePulse * 0.15 * intensityMultiplier).clamp(0.0, 1.0)),
                Colors.transparent,
                color.withOpacity((safePulse * 0.15 * intensityMultiplier).clamp(0.0, 1.0)),
              ],
            ),
            border: Border.all(
              color: color.withOpacity((0.7 + safePulse * 0.3).clamp(0.0, 1.0)),
              width: (3 + safePulse * 2) * intensityMultiplier,
            ),
          ),
          // P1.1: Progress arc indicator + tension level badge
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress arc at top
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: width * 0.8,
                  height: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.black.withOpacity(0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        color.withOpacity((0.9 + safePulse * 0.1).clamp(0.0, 1.0)),
                      ),
                    ),
                  ),
                ),
              ),
              // Tension level indicator badge for L3+ (high tension)
              if (tensionLevel >= 3)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Text(
                    tensionLevel == 4 ? '🔥' : '⚡',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // V14: Helper to find which symbol name a position belongs to
  // ═══════════════════════════════════════════════════════════════════════════
  String? _getSymbolNameForPosition(String posKey) {
    for (final entry in _winningPositionsBySymbol.entries) {
      if (entry.value.contains(posKey)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Rectangular cell version - allows non-square cells to fill more space
  /// Uses PROFESSIONAL REEL ANIMATION SYSTEM for precise timing
  Widget _buildSymbolCellRect(int reelIndex, int rowIndex, double cellWidth, double cellHeight) {
    final reelState = _reelAnimController.getReelState(reelIndex);
    final posKey = '$reelIndex,$rowIndex';

    // V14: Get symbol name for this position (for label display)
    final symbolName = _getSymbolNameForPosition(posKey);

    // When win line presentation is active, only highlight CURRENT line positions
    // Otherwise highlight all winning positions
    final isWinningPosition = _isShowingWinLines
        ? _currentLinePositions.contains(posKey)
        : _winningPositions.contains(posKey);
    final isWinningReel = _winningReels.contains(reelIndex);
    final isAnticipationReel = _anticipationReels.contains(reelIndex);
    final isNearMissPosition = _nearMissPositions.contains(posKey);
    final isCascadePopPosition = _cascadePopPositions.contains(posKey);

    // Determine if reel is visually spinning
    final isReelSpinning = reelState.phase != ReelPhase.idle &&
                           reelState.phase != ReelPhase.stopped;

    // For symbol content, use the smaller dimension to keep symbols proportional
    final symbolSize = math.min(cellWidth, cellHeight);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _winPulseAnimation,
        _symbolBounceAnimation,
        _anticipationPulse,
        _nearMissShake,
        _cascadePopAnimation,
      ]),
      builder: (context, child) {
        // Calculate bounce offset for winning symbols
        double bounceOffset = 0;
        double glowIntensity = 0;
        double shakeOffset = 0;
        double cascadeScale = 1.0;
        double cascadeOpacity = 1.0;

        // Professional bounce landing from animation controller
        if (reelState.phase == ReelPhase.bouncing) {
          bounceOffset = reelState.bounceOffset;
        } else if (isWinningPosition && !isReelSpinning) {
          final bounceValue = _symbolBounceAnimation.value;
          bounceOffset = math.sin(bounceValue * math.pi) * -8;
          // CRITICAL: Clamp to prevent withOpacity assertion error (line 342 in dart:ui)
          glowIntensity = _winPulseAnimation.value.clamp(0.0, 1.0);
        }

        if (isNearMissPosition && _isNearMiss) {
          shakeOffset = math.sin(_nearMissShake.value * math.pi * 6) * 4 *
              (1 - _nearMissShake.value);
        }

        if (isCascadePopPosition && _isCascading) {
          cascadeScale = _cascadePopAnimation.value;
          // CRITICAL FIX: Curves.easeInBack can produce negative values!
          // This caused assertion error at dart:ui line 342 (withOpacity requires 0.0-1.0)
          cascadeOpacity = _cascadePopAnimation.value.clamp(0.0, 1.0);
        }

        Color borderColor;
        double borderWidth;

        if (isWinningPosition) {
          borderColor = _getWinGlowColor().withOpacity(_winPulseAnimation.value.clamp(0.0, 1.0));
          borderWidth = 2.5;
        } else if (isNearMissPosition && _isNearMiss) {
          borderColor = const Color(0xFFFF4060).withOpacity(0.8);
          borderWidth = 2.5;
        } else if (isAnticipationReel && _isAnticipation && isReelSpinning) {
          borderColor = const Color(0xFFFFD700).withOpacity(_anticipationPulse.value.clamp(0.0, 1.0));
          borderWidth = 2.0;
        } else {
          // REMOVED: isWinningReel animation on ALL cells of winning reel
          // Now only winning POSITIONS get animation, not entire reel
          borderColor = const Color(0xFF2A2A38);
          borderWidth = 1;
        }

        List<BoxShadow>? shadows;
        if (isWinningPosition && glowIntensity > 0) {
          shadows = [
            BoxShadow(
              color: _getWinGlowColor().withOpacity((glowIntensity * 0.6).clamp(0.0, 1.0)),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ];
        } else if (isNearMissPosition && _isNearMiss) {
          shadows = [
            BoxShadow(
              color: const Color(0xFFFF4060).withOpacity(0.5),
              blurRadius: 16,
              spreadRadius: 3,
            ),
          ];
        } else if (isAnticipationReel && _isAnticipation && isReelSpinning) {
          shadows = [
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity((_anticipationPulse.value * 0.4).clamp(0.0, 1.0)),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ];
        }

        // ═══════════════════════════════════════════════════════════════════════
        // V2: Landing Impact — Get landing scale for this reel (flash disabled)
        // ═══════════════════════════════════════════════════════════════════════
        final landingScale = _landingPopScale[reelIndex] ?? 1.0;

        // ═══════════════════════════════════════════════════════════════════════
        // V6: Enhanced Symbol Highlight — Staggered popup scale + micro-rotation
        // ═══════════════════════════════════════════════════════════════════════
        final symbolPopScale = _symbolPopScale[posKey] ?? 1.0;
        final symbolPopRotation = _symbolPopRotation[posKey] ?? 0.0;

        return Transform.translate(
          offset: Offset(shakeOffset, bounceOffset),
          child: Transform.rotate(
            angle: symbolPopRotation, // V6: Micro-rotation wiggle
            child: Transform.scale(
              scale: cascadeScale * landingScale * symbolPopScale, // V2 + V6: Combined scales
            child: Opacity(
              // CRITICAL: Ensure opacity is always valid (0.0-1.0) - double guard
              opacity: cascadeOpacity.clamp(0.0, 1.0),
              child: Container(
                width: cellWidth,
                height: cellHeight,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: const Color(0xFF08080C),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isCascadePopPosition && _isCascading
                        ? const Color(0xFFFFD700).withOpacity(cascadeOpacity)
                        : borderColor,
                    width: borderWidth,
                  ),
                  boxShadow: isCascadePopPosition && _isCascading
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.6 * cascadeOpacity),
                            blurRadius: 16 * cascadeScale,
                            spreadRadius: 4 * cascadeScale,
                          ),
                        ]
                      : shadows,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Main symbol content
                    isReelSpinning
                        ? _buildProfessionalSpinningContent(
                            reelIndex, rowIndex, symbolSize, reelState,
                            isAnticipation: isAnticipationReel && _isAnticipation,
                          )
                        : _buildStaticSymbolContent(
                            reelIndex, rowIndex, symbolSize, isWinningPosition,
                            isNearMiss: isNearMissPosition && _isNearMiss,
                          ),
                    // ═════════════════════════════════════════════════════════
                    // V14: Symbol Name Label — shows which symbol is winning
                    // Appears in bottom-right corner during win highlight
                    // ═════════════════════════════════════════════════════════
                    if (isWinningPosition && !isReelSpinning && symbolName != null)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: _getWinGlowColor().withOpacity(0.85),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: _getWinGlowColor().withOpacity(0.5),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            symbolName,
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ), // V6: Close Transform.rotate
        ),
        );
      },
    );
  }

  Widget _buildSymbolCell(int reelIndex, int rowIndex, double cellSize) {
    return _buildSymbolCellRect(reelIndex, rowIndex, cellSize, cellSize);
  }

  /// PROFESSIONAL SPINNING CONTENT
  /// Phase-based animation with realistic acceleration, blur, and deceleration
  Widget _buildProfessionalSpinningContent(
    int reelIndex,
    int rowIndex,
    double cellSize,
    ReelAnimationState reelState, {
    bool isAnticipation = false,
  }) {
    final spinSyms = _spinSymbols[reelIndex];
    final totalSymbols = spinSyms.length;

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE-BASED SYMBOL SELECTION
    // ═══════════════════════════════════════════════════════════════════════════
    int symbolId;
    double verticalOffset = 0;
    double blurIntensity = 0;

    switch (reelState.phase) {
      case ReelPhase.accelerating:
        // During acceleration: show blur transition, random symbols
        final accelProgress = reelState.phaseProgress;
        blurIntensity = accelProgress * 0.6; // Build up blur
        final symbolIndex = (accelProgress * 10).floor() % totalSymbols;
        symbolId = spinSyms[(symbolIndex + rowIndex) % totalSymbols];
        verticalOffset = (accelProgress * cellSize * 2) % cellSize;

      case ReelPhase.spinning:
        // Full speed: maximum blur, fast cycling symbols
        blurIntensity = 0.7; // High blur during full speed
        final cyclePosition = (reelState.spinCycles * totalSymbols).floor();
        symbolId = spinSyms[(cyclePosition + rowIndex) % totalSymbols];
        verticalOffset = (reelState.spinCycles * cellSize * 3) % cellSize;
        // SPINNING→DECEL FIX: Store current offset for smooth transition to decel phase
        if (rowIndex == 0) {
          _lastSpinningOffset[reelIndex] = verticalOffset;
        }

      case ReelPhase.decelerating:
        // ═══════════════════════════════════════════════════════════════════════════
        // DECELERATING PHASE: Show target symbols IMMEDIATELY, NO vertical movement
        // CRITICAL: When reel starts decelerating, symbols are LOCKED in place
        // Only blur fades out — symbols do NOT move during deceleration
        // ═══════════════════════════════════════════════════════════════════════════
        final decelProgress = reelState.phaseProgress;
        blurIntensity = (1 - decelProgress) * 0.5; // Fade blur only

        // ALWAYS show target symbols during deceleration (symbols are "locked")
        symbolId = _targetGrid[reelIndex][rowIndex];

        // NO vertical offset — symbols stay exactly where they landed
        verticalOffset = 0;

      case ReelPhase.bouncing:
        // Bouncing: show target symbol with bounce offset
        symbolId = _targetGrid[reelIndex][rowIndex];
        blurIntensity = 0;
        verticalOffset = 0; // Bounce is handled by parent transform

      case ReelPhase.idle:
      case ReelPhase.stopped:
        // Static display — ALWAYS use _targetGrid during/after spin
        // This ensures symbols don't change when bounce animation is skipped (bounceMs=0)
        // _targetGrid is set at spin start and remains constant throughout
        symbolId = _isSpinning || _spinFinalized
            ? _targetGrid[reelIndex][rowIndex]
            : _displayGrid[reelIndex][rowIndex];
        blurIntensity = 0;
        verticalOffset = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VISUAL RENDERING — Fixed size container to prevent layout instability
    // V9: Wrapped in SizedBox + ClipRect to ensure cells never change size during spin
    // ═══════════════════════════════════════════════════════════════════════════
    return SizedBox(
      width: cellSize,
      height: cellSize,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Main symbol with scroll offset — clipped to cell bounds
            Transform.translate(
              offset: Offset(0, verticalOffset * 0.4),
              child: SizedBox(
                width: cellSize,
                height: cellSize,
                child: _buildSymbolContent(symbolId, cellSize, false, isSpinning: true),
              ),
            ),

            // Motion blur overlay - intensity based on phase
            if (blurIntensity > 0.05)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(blurIntensity * 0.6),
                        Colors.black.withOpacity(blurIntensity * 0.2),
                        Colors.black.withOpacity(blurIntensity * 0.6),
                      ],
                    ),
                  ),
                ),
              ),

            // Speed lines effect during spinning phase
            if (reelState.phase == ReelPhase.spinning)
              Positioned.fill(
                child: CustomPaint(
                  size: Size(cellSize, cellSize),
                  painter: _SpeedLinesPainter(intensity: 0.3),
                ),
              ),

            // Anticipation golden glow overlay
            if (isAnticipation)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFFD700).withOpacity((_anticipationPulse.value * 0.4).clamp(0.0, 1.0)),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              )
            // Acceleration glow effect
            else if (reelState.phase == ReelPhase.accelerating)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        // FIX: Clamp to prevent withOpacity assertion error
                        FluxForgeTheme.accentBlue.withOpacity((reelState.phaseProgress * 0.3).clamp(0.0, 1.0)),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Legacy spinning content (kept for reference)
  Widget _buildSpinningSymbolContent(
    int reelIndex,
    int rowIndex,
    double cellSize,
    double animationValue, {
    bool isAnticipation = false,
  }) {
    final spinSyms = _spinSymbols[reelIndex];
    final totalSymbols = spinSyms.length;

    // Enhanced easing for more realistic reel feel
    final scrollProgress = Curves.easeOutCubic.transform(animationValue);
    final currentIndex = ((1 - scrollProgress) * (totalSymbols - widget.rows)).floor();
    final symbolId = currentIndex + rowIndex < totalSymbols
        ? spinSyms[currentIndex + rowIndex]
        : _targetGrid[reelIndex][rowIndex];

    // Calculate vertical offset for smooth scrolling effect
    final fractionalProgress = ((1 - scrollProgress) * (totalSymbols - widget.rows)) % 1.0;
    final verticalOffset = fractionalProgress * cellSize;

    // Speed-based blur intensity
    final speed = animationValue < 0.5
        ? animationValue * 2  // Speeding up
        : (1 - animationValue) * 2;  // Slowing down
    final blurIntensity = speed * 0.4;

    return Stack(
      children: [
        // Main symbol with scroll offset
        Transform.translate(
          offset: Offset(0, verticalOffset * 0.3),  // Subtle vertical movement
          child: _buildSymbolContent(symbolId, cellSize, false, isSpinning: true),
        ),
        // Motion blur overlay - stronger during fast spin
        if (blurIntensity > 0.05)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(blurIntensity * 0.5),
                  Colors.transparent,
                  Colors.black.withOpacity(blurIntensity * 0.5),
                ],
              ),
            ),
          ),
        // Anticipation golden glow overlay
        if (isAnticipation)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFD700).withOpacity((_anticipationPulse.value * 0.3).clamp(0.0, 1.0)),
                  Colors.transparent,
                ],
              ),
            ),
          )
        // Normal spin glow effect
        else if (animationValue < 0.3)
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  FluxForgeTheme.accentBlue.withOpacity((0.3 - animationValue) * 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStaticSymbolContent(
    int reelIndex,
    int rowIndex,
    double cellSize,
    bool isWinning, {
    bool isNearMiss = false,
  }) {
    final symbolId = _displayGrid[reelIndex][rowIndex];
    return _buildSymbolContent(
      symbolId,
      cellSize,
      isWinning,
      isNearMiss: isNearMiss,
    );
  }

  Widget _buildSymbolContent(
    int symbolId,
    double cellSize,
    bool isWinning, {
    bool isSpinning = false,
    bool isNearMiss = false,
  }) {
    final symbol = SlotSymbol.getSymbol(symbolId);
    final fontSize = (cellSize * 0.5).clamp(12.0, 60.0);

    // Enhanced glow for winning symbols or near miss
    List<Color> glowColors;
    if (isNearMiss) {
      // Near miss - desaturated red tint
      glowColors = [
        const Color(0xFFFF4060).withOpacity(0.7),
        const Color(0xFF802030),
        const Color(0xFF401020),
      ];
    } else if (isWinning) {
      glowColors = [
        symbol.glowColor.withOpacity(0.8),
        symbol.gradientColors.first,
        symbol.gradientColors.last,
      ];
    } else {
      glowColors = symbol.gradientColors;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: glowColors,
        ),
        borderRadius: BorderRadius.circular(3),
        boxShadow: isWinning
            ? [
                BoxShadow(
                  color: symbol.glowColor.withOpacity(0.6),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : isNearMiss
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF4060).withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
      ),
      child: Stack(
        children: [
          // Inner glow for special symbols
          if (symbol.isSpecial)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      symbol.glowColor.withOpacity(isSpinning ? 0.1 : 0.3),
                      Colors.transparent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          // Symbol name (text instead of emoji)
          Center(
            child: Text(
              symbol.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize * 0.5, // Smaller for text names
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.black.withOpacity(0.6), blurRadius: 3, offset: const Offset(1, 1)),
                  if (isWinning || symbol.isSpecial)
                    Shadow(color: symbol.glowColor.withOpacity(0.8), blurRadius: 8),
                ],
              ),
            ),
          ),
          // Win shimmer effect
          if (isWinning)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _winPulseAnimation,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1 + _winPulseAnimation.value * 2, -1),
                        end: Alignment(1 + _winPulseAnimation.value * 2, 1),
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.15),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                },
              ),
            ),
          // Near miss X overlay
          if (isNearMiss)
            Positioned.fill(
              child: Center(
                child: Text(
                  '✕',
                  style: TextStyle(
                    fontSize: fontSize * 1.2,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFF4060).withOpacity(0.9),
                    shadows: const [
                      Shadow(
                        color: Color(0xFFFF4060),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // ═══════════════════════════════════════════════════════════════════
          // SYMBOL TYPE LABEL - Always visible at top of each cell
          // Shows: WILD, SCAT, BONUS, HP1, HP2, MP1, MP2, LP1, LP2, LP3
          // ═══════════════════════════════════════════════════════════════════
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: symbol.labelColor.withOpacity(0.8),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: symbol.labelColor.withOpacity(0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  symbol.shortLabel,
                  style: TextStyle(
                    fontSize: (cellSize * 0.18).clamp(8.0, 14.0),
                    fontWeight: FontWeight.w900,
                    color: symbol.labelColor,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT SLOT MINI PREVIEW
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// PARTICLE SYSTEM FOR WIN CELEBRATIONS
// ═══════════════════════════════════════════════════════════════════════════

enum _ParticleType { coin, sparkle }

class _WinParticle {
  double x = 0, y = 0;
  double vx = 0, vy = 0;
  double size = 4;
  Color color = const Color(0xFFFFD700);
  _ParticleType type = _ParticleType.coin;
  double rotation = 0;
  double rotationSpeed = 0;
  double life = 1.0;
  double gravity = 0.0005;

  /// Reset particle for reuse from pool
  void reset({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double size,
    required Color color,
    required _ParticleType type,
    required double rotation,
    required double rotationSpeed,
  }) {
    this.x = x;
    this.y = y;
    this.vx = vx;
    this.vy = vy;
    this.size = size;
    this.color = color;
    this.type = type;
    this.rotation = rotation;
    this.rotationSpeed = rotationSpeed;
    life = 1.0;
    gravity = 0.0005;
  }

  void update() {
    x += vx;
    y += vy;
    vy += gravity; // Gravity pulls down
    rotation += rotationSpeed;
    life -= 0.015; // Fade out

    // Slow down horizontal movement
    vx *= 0.99;
  }

  bool get isDead => life <= 0 || y > 1.2 || x < -0.1 || x > 1.1;
}

/// Object pool for particles - eliminates GC pressure during win animations
class _ParticlePool {
  final List<_WinParticle> _available = [];
  static const int maxPoolSize = 100;

  /// Acquire a particle from the pool or create new if pool is empty
  _WinParticle acquire({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double size,
    required Color color,
    required _ParticleType type,
    required double rotation,
    required double rotationSpeed,
  }) {
    final particle = _available.isNotEmpty ? _available.removeLast() : _WinParticle();
    particle.reset(
      x: x, y: y, vx: vx, vy: vy,
      size: size, color: color, type: type,
      rotation: rotation, rotationSpeed: rotationSpeed,
    );
    return particle;
  }

  /// Return a particle to the pool for reuse
  void release(_WinParticle particle) {
    if (_available.length < maxPoolSize) {
      _available.add(particle);
    }
  }

  /// Release multiple particles
  void releaseAll(Iterable<_WinParticle> particles) {
    for (final p in particles) {
      release(p);
    }
  }
}

/// Speed lines painter for spinning reel effect
class _SpeedLinesPainter extends CustomPainter {
  final double intensity;

  _SpeedLinesPainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity < 0.1) return;

    final paint = Paint()
      ..color = Colors.white.withOpacity(intensity * 0.15)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw vertical speed lines
    final lineCount = 5;
    final spacing = size.width / (lineCount + 1);

    for (int i = 0; i < lineCount; i++) {
      final x = spacing * (i + 1);
      // Vary line lengths for more natural look
      final startY = size.height * (0.1 + (i % 3) * 0.1);
      final endY = size.height * (0.9 - (i % 2) * 0.1);

      canvas.drawLine(
        Offset(x, startY),
        Offset(x, endY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter oldDelegate) {
    return oldDelegate.intensity != intensity;
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_WinParticle> particles;

  _ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withOpacity((p.life * 0.8).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      final x = p.x * size.width;
      final y = p.y * size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation);

      if (p.type == _ParticleType.coin) {
        // Draw coin shape
        final coinPaint = Paint()
          ..color = p.color.withOpacity((p.life * 0.9).clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;

        // Outer circle
        canvas.drawCircle(Offset.zero, p.size, coinPaint);

        // Inner highlight
        final highlightPaint = Paint()
          ..color = Colors.white.withOpacity((p.life * 0.4).clamp(0.0, 1.0))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(-p.size * 0.2, -p.size * 0.2), p.size * 0.3, highlightPaint);

        // Edge shadow
        final shadowPaint = Paint()
          ..color = Colors.black.withOpacity((p.life * 0.3).clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(Offset.zero, p.size, shadowPaint);
      } else {
        // Draw sparkle/star shape
        final path = Path();
        final outerRadius = p.size;
        final innerRadius = p.size * 0.4;

        for (int i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final radius = i.isEven ? outerRadius : innerRadius;
          final px = math.cos(angle) * radius;
          final py = math.sin(angle) * radius;
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();

        canvas.drawPath(path, paint);

        // Center glow
        final glowPaint = Paint()
          ..color = Colors.white.withOpacity((p.life * 0.6).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(Offset.zero, p.size * 0.3, glowPaint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// WIN LINE PAINTER — Draws connecting lines through winning positions
// ═══════════════════════════════════════════════════════════════════════════

class _WinLinePainter extends CustomPainter {
  final List<List<int>> positions; // [[reel, row], ...]
  final int reelCount;
  final int rowCount;
  final double pulseValue; // 0.0 - 1.0 for pulse animation
  final Color lineColor;
  final double drawProgress; // P1.2: 0.0 = no line, 1.0 = full line

  _WinLinePainter({
    required this.positions,
    required this.reelCount,
    required this.rowCount,
    required this.pulseValue,
    required this.lineColor,
    this.drawProgress = 1.0, // Default to full line for backwards compatibility
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty || positions.length < 2) return;
    if (drawProgress <= 0) return; // P1.2: Nothing to draw at 0%

    // Calculate grid layout (must match _buildReelTable logic)
    // Available space = size - padding (4*2=8) - border (2*2=4) = size - 12
    final availableWidth = size.width - 12;
    final availableHeight = size.height - 12;
    final cellWidth = availableWidth / reelCount;
    final cellHeight = availableHeight / rowCount;
    final cellSize = math.min(cellWidth, cellHeight) * 0.82;

    // Calculate offset to center the table
    final tableWidth = cellSize * reelCount;
    final tableHeight = cellSize * rowCount;
    final offsetX = (size.width - tableWidth) / 2;
    final offsetY = (size.height - tableHeight) / 2;

    // Convert positions to pixel coordinates
    final points = <Offset>[];
    for (final pos in positions) {
      if (pos.length >= 2) {
        final reelIndex = pos[0];
        final rowIndex = pos[1];
        // Center of the cell
        final x = offsetX + (reelIndex + 0.5) * cellSize;
        final y = offsetY + (rowIndex + 0.5) * cellSize;
        points.add(Offset(x, y));
      }
    }

    if (points.length < 2) return;

    // ═══════════════════════════════════════════════════════════════════════════
    // P1.2: Calculate how much of the line to draw based on progress
    // Line "grows" from first position to last position
    // ═══════════════════════════════════════════════════════════════════════════
    final totalSegments = points.length - 1;
    final progressFloat = drawProgress.clamp(0.0, 1.0) * totalSegments;
    final fullSegments = progressFloat.floor();
    final partialSegment = progressFloat - fullSegments; // 0.0 to 1.0 for partial

    // Build partial path
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    // Draw full segments
    for (int i = 0; i < fullSegments && i < totalSegments; i++) {
      path.lineTo(points[i + 1].dx, points[i + 1].dy);
    }

    // Draw partial segment (if any)
    if (fullSegments < totalSegments && partialSegment > 0) {
      final startPoint = points[fullSegments];
      final endPoint = points[fullSegments + 1];
      final partialX = startPoint.dx + (endPoint.dx - startPoint.dx) * partialSegment;
      final partialY = startPoint.dy + (endPoint.dy - startPoint.dy) * partialSegment;
      path.lineTo(partialX, partialY);
    }

    // Draw outer glow (thicker, more transparent)
    final glowPaint = Paint()
      ..color = lineColor.withOpacity(0.3 + pulseValue * 0.2)
      ..strokeWidth = 14 + pulseValue * 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawPath(path, glowPaint);

    // Draw main line (solid, colored)
    final linePaint = Paint()
      ..color = lineColor.withOpacity(0.8 + pulseValue * 0.2)
      ..strokeWidth = 5 + pulseValue * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    // Draw inner highlight (white core)
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.4 + pulseValue * 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, highlightPaint);

    // P1.2: Draw dots only for positions that have been "reached"
    // A position is reached when the line has fully extended to it
    final reachedPositions = fullSegments + 1; // +1 because first position is always shown
    for (int i = 0; i < reachedPositions && i < points.length; i++) {
      final point = points[i];

      // Outer glow dot
      final dotGlowPaint = Paint()
        ..color = lineColor.withOpacity(0.5 + pulseValue * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(point, 12 + pulseValue * 4, dotGlowPaint);

      // Main dot
      final dotPaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point, 8 + pulseValue * 2, dotPaint);

      // White center
      final dotCenterPaint = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point, 3 + pulseValue, dotCenterPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WinLinePainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
           oldDelegate.positions != positions ||
           oldDelegate.drawProgress != drawProgress; // P1.2: Repaint on progress change
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// V4: PLAQUE BURST PAINTER — Radiating lines behind win plaque
// ═══════════════════════════════════════════════════════════════════════════

class _PlaqueBurstPainter extends CustomPainter {
  final double progress;
  final double pulseValue;
  final Color tierColor;
  final int rayCount;

  _PlaqueBurstPainter({
    required this.progress,
    required this.pulseValue,
    required this.tierColor,
    required this.rayCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Ray length grows with progress
    final maxRayLength = math.max(size.width, size.height) * 0.6;
    final rayLength = maxRayLength * progress;

    // Opacity fades in then pulses
    final baseOpacity = (progress * 0.3).clamp(0.0, 0.3);
    final opacity = baseOpacity * (0.6 + pulseValue * 0.4);

    final rayPaint = Paint()
      ..color = tierColor.withOpacity(opacity)
      ..strokeWidth = 3 + pulseValue * 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Draw radiating rays
    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * 2 * math.pi - math.pi / 2; // Start from top
      final startRadius = 30.0; // Start away from center for donut effect
      final startX = centerX + math.cos(angle) * startRadius;
      final startY = centerY + math.sin(angle) * startRadius;
      final endX = centerX + math.cos(angle) * rayLength;
      final endY = centerY + math.sin(angle) * rayLength;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), rayPaint);
    }

    // Inner glow circle
    final glowPaint = Paint()
      ..color = tierColor.withOpacity(opacity * 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(Offset(centerX, centerY), 40 + pulseValue * 10, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _PlaqueBurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.pulseValue != pulseValue ||
           oldDelegate.tierColor != tierColor;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// P2.1: ANTICIPATION VIGNETTE PAINTER — Dark edges with tension color glow
// Intensity increases with tension level (L1-L4)
// ═══════════════════════════════════════════════════════════════════════════

class _AnticipationVignettePainter extends CustomPainter {
  final double intensity;
  final Color color;
  final double pulseValue;

  _AnticipationVignettePainter({
    required this.intensity,
    required this.color,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Clamp input values to valid ranges
    final safeIntensity = intensity.clamp(0.0, 1.0);
    final safePulse = pulseValue.clamp(0.0, 1.0);

    // Dark vignette at edges
    final vignetteOpacity = (safeIntensity * (0.7 + safePulse * 0.3)).clamp(0.0, 1.0);

    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.3,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withOpacity((vignetteOpacity * 0.4).clamp(0.0, 1.0)),
          Colors.black.withOpacity((vignetteOpacity * 0.8).clamp(0.0, 1.0)),
        ],
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);

    // Colored glow at edges (tension color)
    final glowOpacity = (safeIntensity * 0.3 * (0.5 + safePulse * 0.5)).clamp(0.0, 1.0);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.5,
        colors: [
          Colors.transparent,
          Colors.transparent,
          color.withOpacity((glowOpacity * 0.5).clamp(0.0, 1.0)),
          color.withOpacity(glowOpacity),
        ],
        stops: const [0.0, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);
  }

  @override
  bool shouldRepaint(_AnticipationVignettePainter oldDelegate) {
    return oldDelegate.intensity != intensity ||
           oldDelegate.color != color ||
           oldDelegate.pulseValue != pulseValue;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// P2.2: ANTICIPATION PARTICLE TRAIL SYSTEM
// Per-reel particle trails that escalate in intensity with tension level
// L1: Subtle sparkles, L2: More particles, L3: Dense trail, L4: Maximum intensity
// ═══════════════════════════════════════════════════════════════════════════

class _AnticipationParticle {
  double x = 0, y = 0;
  double vx = 0, vy = 0;
  double size = 3;
  Color color = const Color(0xFFFFD700);
  double life = 1.0;
  double fadeSpeed = 0.02;
  double rotation = 0;
  double rotationSpeed = 0;

  void reset({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double size,
    required Color color,
    required double fadeSpeed,
    required double rotation,
    required double rotationSpeed,
  }) {
    this.x = x;
    this.y = y;
    this.vx = vx;
    this.vy = vy;
    this.size = size;
    this.color = color;
    this.fadeSpeed = fadeSpeed;
    this.rotation = rotation;
    this.rotationSpeed = rotationSpeed;
    life = 1.0;
  }

  void update() {
    x += vx;
    y += vy;
    vy -= 0.0001; // Slight upward drift (tension rising)
    vx *= 0.98; // Horizontal damping
    rotation += rotationSpeed;
    life -= fadeSpeed;
  }

  bool get isDead => life <= 0 || y < -0.1 || y > 1.1 || x < -0.1 || x > 1.1;
}

class _AnticipationParticlePool {
  final List<_AnticipationParticle> _available = [];
  static const int maxPoolSize = 200;

  _AnticipationParticle acquire({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double size,
    required Color color,
    required double fadeSpeed,
    required double rotation,
    required double rotationSpeed,
  }) {
    final particle = _available.isNotEmpty
        ? _available.removeLast()
        : _AnticipationParticle();
    particle.reset(
      x: x, y: y, vx: vx, vy: vy,
      size: size, color: color, fadeSpeed: fadeSpeed,
      rotation: rotation, rotationSpeed: rotationSpeed,
    );
    return particle;
  }

  void release(_AnticipationParticle particle) {
    if (_available.length < maxPoolSize) {
      _available.add(particle);
    }
  }

  void releaseAll(Iterable<_AnticipationParticle> particles) {
    for (final p in particles) {
      release(p);
    }
  }
}

class _AnticipationTrailPainter extends CustomPainter {
  final List<_AnticipationParticle> particles;
  final double pulseValue;

  _AnticipationTrailPainter({
    required this.particles,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Clamp pulse value to valid range
    final safePulse = pulseValue.clamp(0.0, 1.0);

    for (final p in particles) {
      // Clamp life to valid range (can be negative before cleanup)
      final safeLife = p.life.clamp(0.0, 1.0);
      final opacity = (safeLife * (0.7 + safePulse * 0.3)).clamp(0.0, 1.0);

      // Core particle
      final paint = Paint()
        ..color = p.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      final x = p.x * size.width;
      final y = p.y * size.height;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation);

      // Sparkle/diamond shape
      final path = Path()
        ..moveTo(0, -p.size)
        ..lineTo(p.size * 0.5, 0)
        ..lineTo(0, p.size)
        ..lineTo(-p.size * 0.5, 0)
        ..close();

      canvas.drawPath(path, paint);

      // Glow effect
      final glowPaint = Paint()
        ..color = p.color.withOpacity((opacity * 0.4).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size.abs());
      canvas.drawCircle(Offset.zero, p.size.abs() * 0.8, glowPaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AnticipationTrailPainter oldDelegate) {
    return true; // Always repaint for smooth animation
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// V5: BIG WIN BACKGROUND PAINTER — Vignette + Color wash for celebration
// ═══════════════════════════════════════════════════════════════════════════

class _BigWinBackgroundPainter extends CustomPainter {
  final String tier;
  final double pulseValue;
  final Color tierColor;

  _BigWinBackgroundPainter({
    required this.tier,
    required this.pulseValue,
    required this.tierColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Clamp pulseValue to valid range (animation can overshoot)
    final safePulse = pulseValue.clamp(0.0, 1.0);

    // ═══════════════════════════════════════════════════════════════════════
    // VIGNETTE — Dark gradient at edges (more intense for higher tiers)
    // ═══════════════════════════════════════════════════════════════════════
    final vignetteIntensity = switch (tier) {
      'BIG_WIN_TIER_5' => 0.6,
      'BIG_WIN_TIER_4' => 0.5,
      'BIG_WIN_TIER_3' => 0.4,
      'BIG_WIN_TIER_2' => 0.3,
      'BIG_WIN_TIER_1' => 0.2,
      _ => 0.15,
    };

    final vignetteOpacity = (vignetteIntensity * (0.7 + safePulse * 0.3)).clamp(0.0, 1.0);

    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withOpacity((vignetteOpacity * 0.3).clamp(0.0, 1.0)),
          Colors.black.withOpacity(vignetteOpacity.clamp(0.0, 1.0)),
        ],
        stops: const [0.0, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);

    // ═══════════════════════════════════════════════════════════════════════
    // COLOR WASH — Tier-colored glow pulsing from center
    // ═══════════════════════════════════════════════════════════════════════
    final colorWashIntensity = switch (tier) {
      'BIG_WIN_TIER_5' => 0.25,
      'BIG_WIN_TIER_4' => 0.20,
      'BIG_WIN_TIER_3' => 0.18,
      'BIG_WIN_TIER_2' => 0.12,
      'BIG_WIN_TIER_1' => 0.08,
      _ => 0.05,
    };

    final colorWashOpacity = (colorWashIntensity * (0.6 + safePulse * 0.4)).clamp(0.0, 1.0);

    final colorWashPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8 + safePulse * 0.2,
        colors: [
          tierColor.withOpacity(colorWashOpacity),
          tierColor.withOpacity((colorWashOpacity * 0.5).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), colorWashPaint);

    // ═══════════════════════════════════════════════════════════════════════
    // LIGHT RAYS — Subtle rays from center (TIER_3 and above)
    // ═══════════════════════════════════════════════════════════════════════
    if (tier == 'BIG_WIN_TIER_5' || tier == 'BIG_WIN_TIER_4' || tier == 'BIG_WIN_TIER_3') {
      final rayOpacity = switch (tier) {
        'BIG_WIN_TIER_5' => 0.15,
        'BIG_WIN_TIER_4' => 0.10,
        'BIG_WIN_TIER_3' => 0.08,
        _ => 0.05,
      };

      final rayCount = switch (tier) {
        'BIG_WIN_TIER_5' => 12,
        'BIG_WIN_TIER_4' => 8,
        'BIG_WIN_TIER_3' => 6,
        _ => 4,
      };

      final rayOpacityFinal = (rayOpacity * (0.5 + safePulse * 0.5)).clamp(0.0, 1.0);
      final rayPaint = Paint()
        ..color = tierColor.withOpacity(rayOpacityFinal)
        ..strokeWidth = 2 + safePulse * 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      final centerX = size.width / 2;
      final centerY = size.height / 2;
      final maxRadius = math.max(size.width, size.height) * 0.8;

      for (int i = 0; i < rayCount; i++) {
        final angle = (i / rayCount) * 2 * math.pi + (safePulse * math.pi * 0.1);
        final endX = centerX + math.cos(angle) * maxRadius;
        final endY = centerY + math.sin(angle) * maxRadius;

        canvas.drawLine(
          Offset(centerX, centerY),
          Offset(endX, endY),
          rayPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BigWinBackgroundPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
           oldDelegate.tier != tier ||
           oldDelegate.tierColor != tierColor;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT SLOT MINI PREVIEW
// ═══════════════════════════════════════════════════════════════════════════

class SlotMiniPreview extends StatelessWidget {
  final SlotLabProvider provider;
  final double size;

  const SlotMiniPreview({
    super.key,
    required this.provider,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, child) {
        final result = provider.lastResult;
        final grid = result?.grid ?? [];

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A4C), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: 15,
              itemBuilder: (context, index) {
                final reel = index % 5;
                final row = index ~/ 5;
                final symbolId = (grid.length > reel && grid[reel].length > row)
                    ? grid[reel][row]
                    : (reel + row) % 10;
                final symbol = SlotSymbol.getSymbol(symbolId);

                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: symbol.gradientColors),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Center(
                    child: Text(
                      symbol.name,
                      style: const TextStyle(fontSize: 6, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
