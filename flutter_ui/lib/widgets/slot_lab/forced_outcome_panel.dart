/// Forced Outcome Panel
///
/// Prominent test buttons for forced slot outcomes:
/// - Visual outcome selectors (BIG WIN, MEGA WIN, FREE SPINS, etc.)
/// - One-click testing for audio designers
/// - Outcome preview with expected stages
/// - Keyboard shortcuts for rapid testing
/// - History of triggered outcomes
///
/// P13.8.7: Dynamic controls based on Feature Builder enabled blocks.
/// Buttons only appear when the corresponding feature block is enabled.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../providers/feature_builder_provider.dart';
import '../../providers/slot_lab_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FORCED OUTCOME DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Forced outcome configuration for testing
class ForcedOutcomeConfig {
  final ForcedOutcome outcome;
  final String label;
  final String shortLabel;
  final String description;
  final IconData icon;
  final List<Color> gradientColors;
  final List<String> expectedStages;
  final String? keyboardShortcut;
  final double? expectedWinMultiplier;

  /// P13.8.7: Feature Builder block ID that enables this outcome.
  /// If null, outcome is always visible. If set, only shown when block is enabled.
  final String? featureBlockId;

  const ForcedOutcomeConfig({
    required this.outcome,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.icon,
    required this.gradientColors,
    required this.expectedStages,
    this.keyboardShortcut,
    this.expectedWinMultiplier,
    this.featureBlockId,
  });

  /// All available forced outcomes - P5 Dynamic Win Tier System
  /// Each WIN tier is separate (WIN_1, WIN_2, WIN_3, WIN_4, WIN_5, WIN_6)
  static const List<ForcedOutcomeConfig> outcomes = [
    // ═══════════════════════════════════════════════════════════════════
    // LOSE
    // ═══════════════════════════════════════════════════════════════════
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.lose,
      label: 'LOSE',
      shortLabel: 'LOSE',
      description: 'No winning combinations',
      icon: Icons.close,
      gradientColors: [Color(0xFF4A4A5A), Color(0xFF2A2A3A)],
      expectedStages: ['SPIN_START', 'REEL_STOP', 'EVALUATE_WINS', 'SPIN_END'],
      keyboardShortcut: '1',
    ),

    // ═══════════════════════════════════════════════════════════════════
    // REGULAR WINS (P5: WIN_LOW, WIN_EQUAL, WIN_1 through WIN_5)
    // WIN_1: >1x, ≤2x | WIN_2: >2x, ≤4x | WIN_3: >4x, ≤8x
    // WIN_4: >8x, ≤13x | WIN_5: >13x (default for regular wins)
    // ═══════════════════════════════════════════════════════════════════
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.smallWin,
      label: 'WIN LOW',
      shortLabel: 'LOW',
      description: 'WIN_LOW: < 1x bet (sub-bet win)',
      icon: Icons.arrow_downward,
      gradientColors: [Color(0xFF78909C), Color(0xFF546E7A)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'EVALUATE_WINS',
        'WIN_PRESENT_LOW', 'SPIN_END',  // No rollup for sub-bet
      ],
      keyboardShortcut: '2',
      expectedWinMultiplier: 0.5,  // 0.5x bet
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.smallWin,
      label: 'WIN =',
      shortLabel: 'EQ',
      description: 'WIN_EQUAL: = 1x bet (push/break-even)',
      icon: Icons.drag_handle,
      gradientColors: [Color(0xFF90A4AE), Color(0xFF78909C)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'EVALUATE_WINS',
        'WIN_PRESENT_EQUAL', 'SPIN_END',  // No rollup for push
      ],
      keyboardShortcut: '3',
      expectedWinMultiplier: 1.0,  // Exactly 1x bet
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.smallWin,
      label: 'WIN 1',
      shortLabel: 'W1',
      description: 'WIN_1: >1x, ≤2x bet',
      icon: Icons.looks_one,
      gradientColors: [Color(0xFF64B5F6), Color(0xFF42A5F5)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'EVALUATE_WINS',
        'WIN_PRESENT_1', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END', 'SPIN_END',
      ],
      keyboardShortcut: '4',
      expectedWinMultiplier: 1.5,  // Mid-range: (1+2)/2 = 1.5x
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.smallWin,
      label: 'WIN 2',
      shortLabel: 'W2',
      description: 'WIN_2: >2x, ≤4x bet',
      icon: Icons.looks_two,
      gradientColors: [Color(0xFF4FC3F7), Color(0xFF29B6F6)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'EVALUATE_WINS',
        'WIN_PRESENT_2', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END', 'SPIN_END',
      ],
      keyboardShortcut: '5',
      expectedWinMultiplier: 3.0,  // Mid-range: (2+4)/2 = 3.0x
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.mediumWin,
      label: 'WIN 3',
      shortLabel: 'W3',
      description: 'WIN_3: >4x, ≤8x bet',
      icon: Icons.looks_3,
      gradientColors: [Color(0xFF81C784), Color(0xFF66BB6A)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'EVALUATE_WINS',
        'WIN_PRESENT_3', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END', 'SPIN_END',
      ],
      keyboardShortcut: '6',
      expectedWinMultiplier: 6.0,  // Mid-range: (4+8)/2 = 6.0x
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.mediumWin,
      label: 'WIN 4',
      shortLabel: 'W4',
      description: 'WIN_4: >8x, ≤13x bet',
      icon: Icons.looks_4,
      gradientColors: [Color(0xFF4DB6AC), Color(0xFF26A69A)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'EVALUATE_WINS',
        'WIN_PRESENT_4', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END', 'SPIN_END',
      ],
      keyboardShortcut: '7',
      expectedWinMultiplier: 10.5,  // Mid-range: (8+13)/2 = 10.5x
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.bigWin,
      label: 'WIN 5',
      shortLabel: 'W5',
      description: 'WIN_5: >13x bet (default regular win)',
      icon: Icons.looks_5,
      gradientColors: [Color(0xFF4CAF50), Color(0xFF43A047)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'EVALUATE_WINS',
        'WIN_PRESENT_5', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END', 'SPIN_END',
      ],
      keyboardShortcut: '8',
      expectedWinMultiplier: 15.0,  // Default: 15x (>13x threshold)
    ),

    // ═══════════════════════════════════════════════════════════════════
    // BIG WIN (P5: 20x+ with tier escalation 1→2→3→4→5)
    // ═══════════════════════════════════════════════════════════════════
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.megaWin, // Maps to BIG_WIN in P5
      label: 'BIG WIN',
      shortLabel: 'BIG WIN TIER 1',
      description: 'Big Win: 20x+ bet with tier escalation (BIG_WIN_TIER_1→5)',
      icon: Icons.auto_awesome,
      gradientColors: [Color(0xFFFFD700), Color(0xFFFFA500)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'EVALUATE_WINS',
        'BIG_WIN_INTRO',
        'BIG_WIN_TIER_1', 'BIG_WIN_TIER_2', 'BIG_WIN_TIER_3',
        'BIG_WIN_ROLLUP_TICK',
        'BIG_WIN_END', 'SPIN_END',
      ],
      keyboardShortcut: '9',  // Was '0', now '9' since WIN_6 removed
      expectedWinMultiplier: 50.0,
    ),

    // ═══════════════════════════════════════════════════════════════════
    // FEATURES (NO keyboard shortcuts - use panel)
    // P13.8.7: Show only when corresponding block is enabled
    // ═══════════════════════════════════════════════════════════════════
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.freeSpins,
      label: 'FREE SPINS',
      shortLabel: 'FREE',
      description: 'Trigger free spins feature',
      icon: Icons.loop,
      gradientColors: [Color(0xFFE040FB), Color(0xFF7C4DFF)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP', 'ANTICIPATION_ON', 'ANTICIPATION_OFF',
        'FEATURE_ENTER', 'FEATURE_STEP', 'FEATURE_EXIT', 'SPIN_END',
      ],
      featureBlockId: 'free_spins',  // P13.8.7
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.cascade,
      label: 'CASCADE',
      shortLabel: 'CASC',
      description: 'Tumbling reels / Avalanche',
      icon: Icons.waterfall_chart,
      gradientColors: [Color(0xFF00BCD4), Color(0xFF00ACC1)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP',
        'CASCADE_START', 'CASCADE_STEP', 'CASCADE_STEP', 'CASCADE_END',
        'SPIN_END',
      ],
      featureBlockId: 'cascades',  // P13.8.7
    ),

    // ═══════════════════════════════════════════════════════════════════
    // JACKPOTS (4 tiers) - NO keyboard shortcuts, use panel
    // P13.8.7: Show only when jackpot block is enabled
    // ═══════════════════════════════════════════════════════════════════
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.jackpotMini,
      label: 'JP MINI',
      shortLabel: 'MINI',
      description: 'Mini jackpot hit',
      icon: Icons.workspace_premium,
      gradientColors: [Color(0xFF9CA3AF), Color(0xFF6B7280)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP',
        'JACKPOT_TRIGGER', 'JACKPOT_PRESENT_MINI', 'JACKPOT_AWARD',
        'SPIN_END',
      ],
      expectedWinMultiplier: 50.0,
      featureBlockId: 'jackpot',  // P13.8.7
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.jackpotMinor,
      label: 'JP MINOR',
      shortLabel: 'MINOR',
      description: 'Minor jackpot hit',
      icon: Icons.workspace_premium,
      gradientColors: [Color(0xFF60A5FA), Color(0xFF3B82F6)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP',
        'JACKPOT_TRIGGER', 'JACKPOT_PRESENT_MINOR', 'JACKPOT_AWARD',
        'SPIN_END',
      ],
      expectedWinMultiplier: 100.0,
      featureBlockId: 'jackpot',  // P13.8.7
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.jackpotMajor,
      label: 'JP MAJOR',
      shortLabel: 'MAJOR',
      description: 'Major jackpot hit',
      icon: Icons.emoji_events,
      gradientColors: [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP',
        'JACKPOT_TRIGGER', 'JACKPOT_PRESENT_MAJOR', 'JACKPOT_AWARD',
        'SPIN_END',
      ],
      expectedWinMultiplier: 500.0,
      featureBlockId: 'jackpot',  // P13.8.7
    ),
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.jackpotGrand,
      label: 'JP GRAND',
      shortLabel: 'GRAND',
      description: 'Grand jackpot hit (progressive)',
      icon: Icons.emoji_events,
      gradientColors: [Color(0xFFFFD700), Color(0xFFFF6B00)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP',
        'JACKPOT_TRIGGER', 'JACKPOT_PRESENT_GRAND', 'JACKPOT_AWARD',
        'SPIN_END',
      ],
      expectedWinMultiplier: 1000.0,
      featureBlockId: 'jackpot',  // P13.8.7
    ),

    // ═══════════════════════════════════════════════════════════════════
    // SPECIAL - NO keyboard shortcuts, use panel
    // ═══════════════════════════════════════════════════════════════════
    ForcedOutcomeConfig(
      outcome: ForcedOutcome.nearMiss,
      label: 'NEAR MISS',
      shortLabel: 'NEAR',
      description: 'Almost won - anticipation trigger',
      icon: Icons.track_changes,
      gradientColors: [Color(0xFFFF9040), Color(0xFFFF6B00)],
      expectedStages: [
        'SPIN_START', 'REEL_STOP',
        'ANTICIPATION_ON', 'ANTICIPATION_TENSION_R3_L2', 'ANTICIPATION_OFF',
        'EVALUATE_WINS', 'SPIN_END',
      ],
    ),
  ];

  static ForcedOutcomeConfig? getConfig(ForcedOutcome outcome) {
    return outcomes.firstWhere(
      (c) => c.outcome == outcome,
      orElse: () => outcomes.first,
    );
  }

  /// P13.8.7: Get filtered outcomes based on enabled block IDs.
  /// Returns only outcomes whose featureBlockId is null or in enabledBlockIds.
  static List<ForcedOutcomeConfig> getVisibleOutcomes(Set<String> enabledBlockIds) {
    return outcomes.where((config) {
      if (config.featureBlockId == null) return true;
      return enabledBlockIds.contains(config.featureBlockId);
    }).toList();
  }

  /// P13.8.7: Check if a specific outcome is visible given enabled block IDs.
  static bool isOutcomeVisible(ForcedOutcomeConfig config, Set<String> enabledBlockIds) {
    if (config.featureBlockId == null) return true;
    return enabledBlockIds.contains(config.featureBlockId);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRIGGERED OUTCOME HISTORY
// ═══════════════════════════════════════════════════════════════════════════

class OutcomeHistoryEntry {
  final DateTime timestamp;
  final ForcedOutcomeConfig config;
  final double? winAmount;
  final Duration? duration;

  OutcomeHistoryEntry({
    required this.timestamp,
    required this.config,
    this.winAmount,
    this.duration,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FORCED OUTCOME PANEL
// P13.8.7: Dynamic controls based on Feature Builder enabled blocks
// ═══════════════════════════════════════════════════════════════════════════

class ForcedOutcomePanel extends StatefulWidget {
  final SlotLabProvider provider;
  final double height;
  final bool showHistory;
  final bool compact;

  /// P13.8.7: Optional FeatureBuilderProvider for dynamic button visibility.
  /// When provided, buttons are shown/hidden based on enabled feature blocks.
  /// When null, all buttons are shown (backwards compatibility).
  final FeatureBuilderProvider? featureBuilderProvider;

  const ForcedOutcomePanel({
    super.key,
    required this.provider,
    this.height = 200,
    this.showHistory = true,
    this.compact = false,
    this.featureBuilderProvider,
  });

  @override
  State<ForcedOutcomePanel> createState() => _ForcedOutcomePanelState();
}

class _ForcedOutcomePanelState extends State<ForcedOutcomePanel>
    with SingleTickerProviderStateMixin {
  final List<OutcomeHistoryEntry> _history = [];
  ForcedOutcomeConfig? _selectedOutcome;
  ForcedOutcomeConfig? _lastTriggeredOutcome;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isTriggering = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // P13.8.7: Check if an outcome should be visible based on Feature Builder state
  bool _isOutcomeVisible(ForcedOutcomeConfig config) {
    // If no feature block is required, always visible
    if (config.featureBlockId == null) return true;

    // If no FeatureBuilderProvider, show all outcomes (backwards compatible)
    final fbProvider = widget.featureBuilderProvider;
    if (fbProvider == null) return true;

    // Check if the required feature block is enabled
    final block = fbProvider.getBlock(config.featureBlockId!);
    return block?.isEnabled ?? false;
  }

  // P13.8.7: Get filtered list of visible outcomes
  List<ForcedOutcomeConfig> get _visibleOutcomes {
    return ForcedOutcomeConfig.outcomes
        .where(_isOutcomeVisible)
        .toList();
  }

  void _triggerOutcome(ForcedOutcomeConfig config) async {
    if (_isTriggering) return;

    setState(() {
      _isTriggering = true;
      _lastTriggeredOutcome = config;
    });

    _pulseController.repeat(reverse: true);

    final startTime = DateTime.now();

    // Trigger the spin with forced outcome
    // P5: Use expectedWinMultiplier for precise tier targeting
    if (config.expectedWinMultiplier != null && config.expectedWinMultiplier! > 0) {
      await widget.provider.spinForcedWithMultiplier(
        config.outcome,
        config.expectedWinMultiplier!,
      );
    } else {
      await widget.provider.spinForced(config.outcome);
    }

    final duration = DateTime.now().difference(startTime);

    setState(() {
      _isTriggering = false;
      _history.insert(
        0,
        OutcomeHistoryEntry(
          timestamp: DateTime.now(),
          config: config,
          winAmount: widget.provider.lastResult?.totalWin,
          duration: duration,
        ),
      );

      // Limit history
      if (_history.length > 20) {
        _history.removeLast();
      }
    });

    _pulseController.stop();
    _pulseController.reset();
  }

  void _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Check for number keys 1-0
    // P13.8.7: Only trigger if outcome is visible (block enabled)
    final char = event.character;
    if (char != null) {
      final config = ForcedOutcomeConfig.outcomes.firstWhere(
        (c) => c.keyboardShortcut == char,
        orElse: () => ForcedOutcomeConfig.outcomes.first,
      );
      if (config.keyboardShortcut == char && _isOutcomeVisible(config)) {
        _triggerOutcome(config);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactPanel();
    }

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyPress,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildOutcomeGrid()),
            if (widget.showHistory) _buildHistoryStrip(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPanel() {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'FORCED OUTCOME',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Quick test buttons (1-9)',
                style: TextStyle(color: Colors.white38, fontSize: 9),
              ),
              const Spacer(),
              if (_lastTriggeredOutcome != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _lastTriggeredOutcome!.gradientColors[0].withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Last: ${_lastTriggeredOutcome!.shortLabel}',
                    style: const TextStyle(color: Colors.white70, fontSize: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Quick buttons grid (fills available space)
          // P13.8.7: Only show visible outcomes based on Feature Builder
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate how many buttons fit per row
                const buttonWidth = 70.0;
                const spacing = 6.0;
                final buttonsPerRow = ((constraints.maxWidth + spacing) / (buttonWidth + spacing)).floor().clamp(1, 10);
                final visibleOutcomes = _visibleOutcomes;

                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: buttonsPerRow,
                    childAspectRatio: 1.6,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                  ),
                  itemCount: visibleOutcomes.length,
                  itemBuilder: (context, index) {
                    final config = visibleOutcomes[index];
                    return _buildCompactButton(config);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactButton(ForcedOutcomeConfig config) {
    final isTriggering = _isTriggering && _lastTriggeredOutcome == config;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final scale = isTriggering ? _pulseAnimation.value : 1.0;

        return Transform.scale(
          scale: scale,
          child: InkWell(
            onTap: () => _triggerOutcome(config),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: config.gradientColors,
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: isTriggering
                    ? [
                        BoxShadow(
                          color: config.gradientColors[0].withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(config.icon, size: 14, color: Colors.white),
                  const SizedBox(height: 2),
                  Text(
                    config.shortLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (config.keyboardShortcut != null)
                    Text(
                      '[${config.keyboardShortcut}]',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 7,
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

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.science,
            size: 14,
            color: _isTriggering
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.accentOrange,
          ),
          const SizedBox(width: 8),
          Text(
            'FORCED OUTCOMES',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (_isTriggering)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        FluxForgeTheme.accentGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'TESTING...',
                    style: TextStyle(
                      color: FluxForgeTheme.accentGreen,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Press 1-0 for quick trigger',
              style: TextStyle(color: Colors.white38, fontSize: 9),
            ),
        ],
      ),
    );
  }

  Widget _buildOutcomeGrid() {
    // P13.8.7: Only show visible outcomes based on Feature Builder
    final visibleOutcomes = _visibleOutcomes;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate grid layout
          const itemWidth = 100.0;
          const itemHeight = 80.0;
          final crossAxisCount =
              (constraints.maxWidth / (itemWidth + 8)).floor().clamp(2, 5);

          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: itemWidth / itemHeight,
            ),
            itemCount: visibleOutcomes.length,
            itemBuilder: (context, index) {
              return _buildOutcomeCard(visibleOutcomes[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildOutcomeCard(ForcedOutcomeConfig config) {
    final isTriggering = _isTriggering && _lastTriggeredOutcome == config;
    final isSelected = _selectedOutcome == config;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final scale = isTriggering ? _pulseAnimation.value : 1.0;

        return Transform.scale(
          scale: scale,
          child: MouseRegion(
            onEnter: (_) => setState(() => _selectedOutcome = config),
            onExit: (_) => setState(() => _selectedOutcome = null),
            child: GestureDetector(
              onTap: () => _triggerOutcome(config),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      config.gradientColors[0]
                          .withOpacity(isSelected ? 0.5 : 0.3),
                      config.gradientColors[1]
                          .withOpacity(isSelected ? 0.3 : 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isTriggering
                        ? Colors.white
                        : isSelected
                            ? config.gradientColors[0]
                            : config.gradientColors[0].withOpacity(0.3),
                    width: isTriggering ? 2 : 1,
                  ),
                  boxShadow: isTriggering
                      ? [
                          BoxShadow(
                            color: config.gradientColors[0].withOpacity(0.5),
                            blurRadius: 15,
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    // Main content
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: config.gradientColors,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  config.icon,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              // Keyboard shortcut badge
                              if (config.keyboardShortcut != null)
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: Colors.white24,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      config.keyboardShortcut!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            config.label,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            config.description,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 8,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Win multiplier badge
                    if (config.expectedWinMultiplier != null)
                      Positioned(
                        top: 4,
                        right: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.accentGreen.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${config.expectedWinMultiplier!.toInt()}x',
                            style: TextStyle(
                              color: FluxForgeTheme.accentGreen,
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // Triggering overlay
                    if (isTriggering)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
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
          ),
        );
      },
    );
  }

  Widget _buildHistoryStrip() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.history, size: 12, color: Colors.white38),
          const SizedBox(width: 8),
          Text(
            'History:',
            style: TextStyle(color: Colors.white38, fontSize: 9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _history.isEmpty
                ? Text(
                    'No outcomes triggered yet',
                    style: TextStyle(color: Colors.white24, fontSize: 9),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final entry = _history[index];
                      final isLatest = index == 0;

                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Tooltip(
                          message:
                              '${entry.config.label}\nWin: ${entry.winAmount?.toStringAsFixed(2) ?? "N/A"}\nTime: ${entry.formattedTime}',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: isLatest
                                  ? LinearGradient(
                                      colors: [
                                        entry.config.gradientColors[0]
                                            .withOpacity(0.3),
                                        entry.config.gradientColors[1]
                                            .withOpacity(0.2),
                                      ],
                                    )
                                  : null,
                              color: isLatest
                                  ? null
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isLatest
                                    ? entry.config.gradientColors[0]
                                    : Colors.transparent,
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  entry.config.icon,
                                  size: 10,
                                  color: isLatest
                                      ? entry.config.gradientColors[0]
                                      : Colors.white54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  entry.config.shortLabel,
                                  style: TextStyle(
                                    color: isLatest
                                        ? entry.config.gradientColors[0]
                                        : Colors.white54,
                                    fontSize: 8,
                                    fontWeight: isLatest
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (entry.winAmount != null &&
                                    entry.winAmount! > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    entry.winAmount!.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: FluxForgeTheme.accentGreen,
                                      fontSize: 8,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Clear history button
          if (_history.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear_all, size: 14, color: Colors.white38),
              onPressed: () => setState(() => _history.clear()),
              tooltip: 'Clear history',
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// QUICK OUTCOME BAR — Plain Text Only (No Styling)
// ═══════════════════════════════════════════════════════════════════════════

/// Ultra-minimal text-only outcome selector
class QuickOutcomeBar extends StatefulWidget {
  final SlotLabProvider provider;
  final double height;

  const QuickOutcomeBar({
    super.key,
    required this.provider,
    this.height = 22,
  });

  @override
  State<QuickOutcomeBar> createState() => _QuickOutcomeBarState();
}

class _QuickOutcomeBarState extends State<QuickOutcomeBar> {
  ForcedOutcome? _lastOutcome;
  bool _isSpinning = false;

  static const _outcomes = [
    (ForcedOutcome.lose, 'LOSE'),
    (ForcedOutcome.smallWin, 'SMALL'),
    (ForcedOutcome.bigWin, 'BIG WIN TIER 1'),
    (ForcedOutcome.megaWin, 'BIG WIN TIER 2'),
    (ForcedOutcome.epicWin, 'BIG WIN TIER 3'),
    (ForcedOutcome.freeSpins, 'FREE'),
    (ForcedOutcome.jackpotGrand, 'JP'),
    (ForcedOutcome.nearMiss, 'NEAR'),
    (ForcedOutcome.cascade, 'CASC'),
  ];

  void _triggerOutcome(ForcedOutcome outcome) async {
    if (_isSpinning) return;
    setState(() {
      _isSpinning = true;
      _lastOutcome = outcome;
    });
    await widget.provider.spinForced(outcome);
    if (mounted) setState(() => _isSpinning = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          Text('TEST:', style: TextStyle(color: Colors.white38, fontSize: 9)),
          const SizedBox(width: 8),
          ..._outcomes.map((o) {
            final (outcome, label) = o;
            final isActive = _lastOutcome == outcome;
            return GestureDetector(
              onTap: () => _triggerOutcome(outcome),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white54,
                    fontSize: 9,
                  ),
                ),
              ),
            );
          }),
          if (_isSpinning)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 8, height: 8,
                child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}
