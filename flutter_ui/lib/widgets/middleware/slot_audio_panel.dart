/// FluxForge Studio — Slot Audio Middleware Panel
///
/// Casino-themed middleware panel designed for slot audio professionals.
/// Features:
/// - Gold/amber casino aesthetic
/// - Card-based layout with clear categories
/// - Quick action grid for common operations
/// - Animated visual feedback
/// - Slot-specific terminology and icons
///
/// Categories:
/// 1. SPIN CYCLE — Reel sounds, spins, stops, anticipation
/// 2. WINS & PAYOUTS — Win tiers, rollups, celebrations
/// 3. FEATURES & BONUSES — Free spins, bonus rounds, jackpots
/// 4. AMBIENCE & UI — Background music, button sounds
/// 5. GAME SYNC — Engine integration, STAGES, RTPC

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';
import 'ducking_matrix_panel.dart';
import 'blend_container_panel.dart';
import 'random_container_panel.dart';
import 'sequence_container_panel.dart';
import 'music_system_panel.dart';
import 'attenuation_curve_panel.dart';
import '../stage/engine_connection_panel.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SLOT AUDIO COLOR PALETTE — Casino Gold Theme
// ═══════════════════════════════════════════════════════════════════════════════

class SlotAudioColors {
  // Primary Gold gradient
  static const Color goldLight = Color(0xFFFFD54F);
  static const Color goldPrimary = Color(0xFFFFC107);
  static const Color goldDark = Color(0xFFFF8F00);
  static const Color goldDeep = Color(0xFFE65100);

  // Casino accents
  static const Color casinoRed = Color(0xFFD32F2F);
  static const Color casinoGreen = Color(0xFF4CAF50);
  static const Color casinoPurple = Color(0xFF9C27B0);
  static const Color casinoBlue = Color(0xFF2196F3);

  // Win tier colors
  static const Color winSmall = Color(0xFF81C784);
  static const Color winMedium = Color(0xFF64B5F6);
  static const Color winBig = Color(0xFFFFD54F);
  static const Color winMega = Color(0xFFFF8A65);
  static const Color winJackpot = Color(0xFFE040FB);

  // Backgrounds
  static const Color bgCard = Color(0xFF1A1A24);
  static const Color bgCardHover = Color(0xFF242430);
  static const Color bgHeader = Color(0xFF12121A);

  // Gradients
  static LinearGradient get goldGradient => const LinearGradient(
    colors: [goldLight, goldPrimary, goldDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get headerGradient => LinearGradient(
    colors: [
      goldDark.withValues(alpha: 0.3),
      goldPrimary.withValues(alpha: 0.1),
      Colors.transparent,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SLOT AUDIO PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class SlotAudioPanel extends StatefulWidget {
  const SlotAudioPanel({super.key});

  @override
  State<SlotAudioPanel> createState() => _SlotAudioPanelState();
}

class _SlotAudioPanelState extends State<SlotAudioPanel>
    with SingleTickerProviderStateMixin {
  int _selectedCategoryIndex = 0;
  late AnimationController _pulseController;

  final List<_SlotCategory> _categories = const [
    _SlotCategory(
      id: 'spin',
      name: 'Spin Cycle',
      icon: Icons.casino,
      description: 'Reels, spins, stops, anticipation',
      color: SlotAudioColors.goldPrimary,
      emoji: '🎰',
    ),
    _SlotCategory(
      id: 'wins',
      name: 'Wins & Payouts',
      icon: Icons.emoji_events,
      description: 'Win tiers, rollups, celebrations',
      color: SlotAudioColors.winBig,
      emoji: '💰',
    ),
    _SlotCategory(
      id: 'features',
      name: 'Features & Bonuses',
      icon: Icons.stars,
      description: 'Free spins, bonus rounds, jackpots',
      color: SlotAudioColors.casinoPurple,
      emoji: '🌟',
    ),
    _SlotCategory(
      id: 'ambience',
      name: 'Ambience & UI',
      icon: Icons.music_note,
      description: 'Background music, button sounds',
      color: SlotAudioColors.casinoBlue,
      emoji: '🎵',
    ),
    _SlotCategory(
      id: 'sync',
      name: 'Game Sync',
      icon: Icons.lan,
      description: 'Engine integration, STAGES',
      color: SlotAudioColors.casinoGreen,
      emoji: '🔗',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<MiddlewareProvider, MiddlewareStats>(
      selector: (_, p) => p.stats,
      builder: (context, stats, _) {
        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: SlotAudioColors.goldPrimary.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              // Casino-style header
              _buildHeader(context, stats),
              // Category selector
              _buildCategorySelector(),
              // Main content
              Expanded(
                child: _buildCategoryContent(),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER — Casino-style with gold accents
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, MiddlewareStats stats) {

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: SlotAudioColors.headerGradient,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
        border: Border(
          bottom: BorderSide(
            color: SlotAudioColors.goldPrimary.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Animated slot icon
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.05),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: SlotAudioColors.goldGradient,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: SlotAudioColors.goldPrimary.withValues(
                          alpha: 0.3 + (_pulseController.value * 0.2),
                        ),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.casino,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          // Title and badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'SLOT AUDIO',
                    style: TextStyle(
                      color: SlotAudioColors.goldLight,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildBadge('STUDIO', SlotAudioColors.goldPrimary),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Professional Game Audio Middleware',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Quick preset buttons
          _QuickPresetButton(
            icon: Icons.casino,
            label: 'Load Demo',
            color: SlotAudioColors.goldPrimary,
            onTap: () {
              context.read<MiddlewareProvider>().loadSlotMachinePreset();
              _showSnackBar(context, 'Slot preset loaded!', SlotAudioColors.casinoGreen);
            },
          ),
          const SizedBox(width: 8),
          _QuickPresetButton(
            icon: Icons.refresh,
            label: 'Reset',
            color: SlotAudioColors.casinoRed,
            onTap: () {
              context.read<MiddlewareProvider>().resetToDefaults();
              _showSnackBar(context, 'Reset to defaults', SlotAudioColors.goldPrimary);
            },
          ),
          const SizedBox(width: 16),
          // Stats pills
          _buildStatsPills(stats),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildStatsPills(({
    int stateGroups,
    int switchGroups,
    int rtpcs,
    int objectsWithSwitches,
    int objectsWithRtpcs,
    int duckingRules,
    int blendContainers,
    int randomContainers,
    int sequenceContainers,
    int musicSegments,
    int stingers,
    int attenuationCurves,
  }) stats) {
    final total = stats.stateGroups + stats.switchGroups + stats.rtpcs +
        stats.duckingRules + stats.blendContainers + stats.randomContainers +
        stats.sequenceContainers + stats.musicSegments + stats.attenuationCurves;

    return Row(
      children: [
        _StatPill(label: 'EVENTS', count: stats.stateGroups + stats.switchGroups, color: SlotAudioColors.goldPrimary),
        const SizedBox(width: 6),
        _StatPill(label: 'RULES', count: stats.duckingRules, color: SlotAudioColors.casinoBlue),
        const SizedBox(width: 6),
        _StatPill(label: 'TOTAL', count: total, color: SlotAudioColors.casinoGreen),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORY SELECTOR — Visual card-based tabs
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategorySelector() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _categories.asMap().entries.map((entry) {
          final index = entry.key;
          final category = entry.value;
          final isSelected = index == _selectedCategoryIndex;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategoryIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? category.color.withValues(alpha: 0.2)
                      : SlotAudioColors.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? category.color
                        : FluxForgeTheme.borderSubtle,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: category.color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ] : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          category.emoji,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          category.icon,
                          color: isSelected ? category.color : FluxForgeTheme.textSecondary,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category.name,
                      style: TextStyle(
                        color: isSelected ? category.color : FluxForgeTheme.textPrimary,
                        fontSize: 10,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORY CONTENT — Dynamic based on selection
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoryContent() {
    final category = _categories[_selectedCategoryIndex];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(category.id),
        padding: const EdgeInsets.all(16),
        child: _getCategoryWidget(category.id),
      ),
    );
  }

  Widget _getCategoryWidget(String categoryId) {
    switch (categoryId) {
      case 'spin':
        return const _SpinCycleContent();
      case 'wins':
        return const _WinsPayoutsContent();
      case 'features':
        return const _FeaturesContent();
      case 'ambience':
        return const _AmbienceContent();
      case 'sync':
        return const _GameSyncContent();
      default:
        return const SizedBox.shrink();
    }
  }

  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPIN CYCLE CONTENT — Reel sounds, spins, stops
// ═══════════════════════════════════════════════════════════════════════════════

class _SpinCycleContent extends StatelessWidget {
  const _SpinCycleContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Quick actions grid
        Expanded(
          flex: 2,
          child: _QuickActionsCard(
            title: 'SPIN EVENTS',
            emoji: '🎰',
            color: SlotAudioColors.goldPrimary,
            actions: [
              _QuickAction('Spin Start', Icons.play_circle, SlotAudioColors.casinoGreen),
              _QuickAction('Reel Stop 1', Icons.stop_circle, SlotAudioColors.goldLight),
              _QuickAction('Reel Stop 2', Icons.stop_circle, SlotAudioColors.goldPrimary),
              _QuickAction('Reel Stop 3', Icons.stop_circle, SlotAudioColors.goldDark),
              _QuickAction('Anticipation', Icons.hourglass_top, SlotAudioColors.casinoPurple),
              _QuickAction('Near Miss', Icons.warning_amber, SlotAudioColors.casinoRed),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right: Random container for reel variations
        Expanded(
          flex: 3,
          child: _FeatureCard(
            title: 'REEL VARIATIONS',
            subtitle: 'Random container for reel stop sounds',
            emoji: '🔀',
            color: SlotAudioColors.goldPrimary,
            child: const RandomContainerPanel(),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WINS & PAYOUTS CONTENT — Win tiers, rollups
// ═══════════════════════════════════════════════════════════════════════════════

class _WinsPayoutsContent extends StatelessWidget {
  const _WinsPayoutsContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Win tier buttons
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _QuickActionsCard(
                title: 'WIN TIERS',
                emoji: '💰',
                color: SlotAudioColors.winBig,
                actions: [
                  _QuickAction('Small Win', Icons.star_border, SlotAudioColors.winSmall),
                  _QuickAction('Medium Win', Icons.star_half, SlotAudioColors.winMedium),
                  _QuickAction('Big Win', Icons.star, SlotAudioColors.winBig),
                  _QuickAction('Mega Win', Icons.auto_awesome, SlotAudioColors.winMega),
                  _QuickAction('JACKPOT!', Icons.workspace_premium, SlotAudioColors.winJackpot),
                  _QuickAction('Rollup', Icons.trending_up, SlotAudioColors.goldPrimary),
                ],
              ),
              const SizedBox(height: 16),
              // Attenuation curves for win amounts
              Expanded(
                child: _FeatureCard(
                  title: 'WIN AMOUNT CURVES',
                  subtitle: 'Map win size to audio intensity',
                  emoji: '📈',
                  color: SlotAudioColors.winBig,
                  child: const AttenuationCurvePanel(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right: Sequence for win celebration
        Expanded(
          flex: 3,
          child: _FeatureCard(
            title: 'WIN CELEBRATION SEQUENCE',
            subtitle: 'Timed sequence for win presentations',
            emoji: '🎉',
            color: SlotAudioColors.winBig,
            child: const SequenceContainerPanel(),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURES & BONUSES CONTENT — Free spins, jackpots
// ═══════════════════════════════════════════════════════════════════════════════

class _FeaturesContent extends StatelessWidget {
  const _FeaturesContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Feature events
        Expanded(
          flex: 2,
          child: _QuickActionsCard(
            title: 'FEATURE EVENTS',
            emoji: '🌟',
            color: SlotAudioColors.casinoPurple,
            actions: [
              _QuickAction('Free Spins', Icons.replay, SlotAudioColors.casinoGreen),
              _QuickAction('Bonus Round', Icons.card_giftcard, SlotAudioColors.casinoPurple),
              _QuickAction('Multiplier', Icons.close, SlotAudioColors.goldPrimary),
              _QuickAction('Scatter Hit', Icons.scatter_plot, SlotAudioColors.casinoBlue),
              _QuickAction('Wild Expand', Icons.fullscreen, SlotAudioColors.winMega),
              _QuickAction('Retrigger', Icons.autorenew, SlotAudioColors.winJackpot),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right: Music system for feature music
        Expanded(
          flex: 3,
          child: _FeatureCard(
            title: 'FEATURE MUSIC',
            subtitle: 'Beat-synced music for bonus rounds',
            emoji: '🎼',
            color: SlotAudioColors.casinoPurple,
            child: const MusicSystemPanel(),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AMBIENCE & UI CONTENT — Background music, buttons
// ═══════════════════════════════════════════════════════════════════════════════

class _AmbienceContent extends StatelessWidget {
  const _AmbienceContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Ducking matrix
        Expanded(
          flex: 3,
          child: _FeatureCard(
            title: 'AUDIO DUCKING',
            subtitle: 'Auto-duck music during wins & events',
            emoji: '🔊',
            color: SlotAudioColors.casinoBlue,
            child: const DuckingMatrixPanel(),
          ),
        ),
        const SizedBox(width: 16),
        // Right: Blend containers
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _QuickActionsCard(
                title: 'UI SOUNDS',
                emoji: '🎵',
                color: SlotAudioColors.casinoBlue,
                actions: [
                  _QuickAction('Button Click', Icons.touch_app, SlotAudioColors.casinoBlue),
                  _QuickAction('Bet Change', Icons.monetization_on, SlotAudioColors.goldPrimary),
                  _QuickAction('Menu Open', Icons.menu_open, SlotAudioColors.casinoGreen),
                  _QuickAction('Error', Icons.error, SlotAudioColors.casinoRed),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _FeatureCard(
                  title: 'MUSIC BLEND',
                  subtitle: 'Crossfade between game states',
                  emoji: '🎚️',
                  color: SlotAudioColors.casinoBlue,
                  child: const BlendContainerPanel(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GAME SYNC CONTENT — Engine integration
// ═══════════════════════════════════════════════════════════════════════════════

class _GameSyncContent extends StatelessWidget {
  const _GameSyncContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Stage events overview
        const Expanded(
          flex: 2,
          child: _StageEventsCard(),
        ),
        const SizedBox(width: 16),
        // Right: Engine connection
        Expanded(
          flex: 3,
          child: _FeatureCard(
            title: 'ENGINE CONNECTION',
            subtitle: 'Live integration with game engines',
            emoji: '🔗',
            color: SlotAudioColors.casinoGreen,
            child: const EngineConnectionPanel(),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAGE EVENTS CARD — Compact STAGE overview
// ═══════════════════════════════════════════════════════════════════════════════

class _StageEventsCard extends StatelessWidget {
  const _StageEventsCard();

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('SPIN_START', Icons.play_arrow, SlotAudioColors.casinoGreen),
      ('REEL_STOP', Icons.stop, SlotAudioColors.goldPrimary),
      ('ANTICIPATION', Icons.hourglass_top, SlotAudioColors.casinoPurple),
      ('WIN_PRESENT', Icons.emoji_events, SlotAudioColors.winBig),
      ('ROLLUP_START', Icons.trending_up, SlotAudioColors.goldLight),
      ('ROLLUP_END', Icons.check_circle, SlotAudioColors.casinoGreen),
      ('BIGWIN_TIER', Icons.star, SlotAudioColors.winMega),
      ('FEATURE_ENTER', Icons.door_front_door, SlotAudioColors.casinoPurple),
      ('FEATURE_EXIT', Icons.exit_to_app, SlotAudioColors.casinoBlue),
      ('JACKPOT', Icons.workspace_premium, SlotAudioColors.winJackpot),
    ];

    return Container(
      decoration: BoxDecoration(
        color: SlotAudioColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SlotAudioColors.casinoGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SlotAudioColors.casinoGreen.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                const Text('🔗', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'STAGE EVENTS',
                  style: TextStyle(
                    color: SlotAudioColors.casinoGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: SlotAudioColors.casinoGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'UNIVERSAL',
                    style: TextStyle(
                      color: SlotAudioColors.casinoGreen,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Stage list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: stages.length,
              itemBuilder: (context, index) {
                final (name, icon, color) = stages[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _SlotCategory {
  final String id;
  final String name;
  final IconData icon;
  final String description;
  final Color color;
  final String emoji;

  const _SlotCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.color,
    required this.emoji,
  });
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;

  const _QuickAction(this.label, this.icon, this.color);
}

class _QuickActionsCard extends StatelessWidget {
  final String title;
  final String emoji;
  final Color color;
  final List<_QuickAction> actions;

  const _QuickActionsCard({
    required this.title,
    required this.emoji,
    required this.color,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SlotAudioColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          // Actions grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.5,
                ),
                itemCount: actions.length,
                itemBuilder: (context, index) {
                  final action = actions[index];
                  return _ActionButton(
                    label: action.label,
                    icon: action.icon,
                    color: action.color,
                    onTap: () {
                      // Trigger event
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isPressed
                ? widget.color.withValues(alpha: 0.3)
                : _isHovered
                    ? widget.color.withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered || _isPressed
                  ? widget.color
                  : FluxForgeTheme.borderSubtle,
              width: _isPressed ? 2 : 1,
            ),
            boxShadow: _isHovered ? [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.2),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: _isHovered || _isPressed
                    ? widget.color
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: _isHovered || _isPressed
                        ? widget.color
                        : FluxForgeTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: _isHovered ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final Color color;
  final Widget child;

  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SlotAudioColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPresetButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickPresetButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_QuickPresetButton> createState() => _QuickPresetButtonState();
}

class _QuickPresetButtonState extends State<_QuickPresetButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.color.withValues(alpha: 0.25)
                : widget.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.color.withValues(alpha: _isHovered ? 0.8 : 0.5),
            ),
            boxShadow: _isHovered ? [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.3),
                blurRadius: 8,
              ),
            ] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: widget.color),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 11,
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

class _StatPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatPill({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: count > 0 ? color.withValues(alpha: 0.15) : FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: count > 0 ? color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: count > 0 ? color : FluxForgeTheme.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: count > 0 ? color : FluxForgeTheme.textTertiary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: count > 0 ? Colors.white : FluxForgeTheme.bgMid,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
