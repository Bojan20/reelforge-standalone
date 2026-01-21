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
import '../../providers/slot_lab_provider.dart';
import '../../src/rust/native_ffi.dart'
    show ForcedOutcome, SlotLabSpinResult;
import '../../theme/fluxforge_theme.dart';
import 'slot_preview_widget.dart';

// =============================================================================
// CONSTANTS & THEME
// =============================================================================

class _SlotTheme {
  // Background colors
  static const bgDeep = Color(0xFF0a0a12);
  static const bgDark = Color(0xFF121218);
  static const bgMid = Color(0xFF1a1a24);
  static const bgSurface = Color(0xFF242432);
  static const bgPanel = Color(0xFF1e1e2a);

  // Accent colors
  static const gold = Color(0xFFFFD700);
  static const goldLight = Color(0xFFFFE55C);
  static const silver = Color(0xFFC0C0C0);
  static const bronze = Color(0xFFCD7F32);

  // Jackpot tier colors
  static const jackpotGrand = Color(0xFFFFD700); // Gold
  static const jackpotMajor = Color(0xFFFF4080); // Magenta
  static const jackpotMinor = Color(0xFF8B5CF6); // Purple
  static const jackpotMini = Color(0xFF4CAF50); // Green
  static const jackpotMystery = Color(0xFF40C8FF); // Cyan

  // Win tier colors
  static const winUltra = Color(0xFFFF4080);
  static const winEpic = Color(0xFFE040FB);
  static const winMega = Color(0xFFFFD700);
  static const winBig = Color(0xFF40FF90);
  static const winSmall = Color(0xFF40C8FF);

  // UI colors
  static const border = Color(0xFF3a3a48);
  static const borderLight = Color(0xFF4a4a58);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB0B0B8);
  static const textMuted = Color(0xFF707080);

  // Button gradients
  static const spinGradient = [Color(0xFF4A9EFF), Color(0xFF2060CC)];
  static const maxBetGradient = [Color(0xFFFFD700), Color(0xFFFF9040)];
  static const autoSpinGradient = [Color(0xFF40FF90), Color(0xFF20A060)];
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
  final int reels;
  final int rows;
  final String? winTier;
  final List<int>? winningPayline;
  final bool isAnticipation;
  final bool showWildExpansion;
  final bool showScatterCollect;
  final bool showCascade;
  final List<_AmbientParticle> particles;
  final double animationTime;

  const _MainGameZone({
    required this.provider,
    required this.reels,
    required this.rows,
    this.winTier,
    this.winningPayline,
    this.isAnticipation = false,
    this.showWildExpansion = false,
    this.showScatterCollect = false,
    this.showCascade = false,
    required this.particles,
    required this.animationTime,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background theme layer
        _buildBackgroundLayer(),

        // Ambient particle layer
        CustomPaint(
          size: Size.infinite,
          painter: _AmbientParticlePainter(
            particles: particles,
            time: animationTime,
          ),
        ),

        // Reel frame with effects
        _buildReelFrame(context),

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
    final screenSize = MediaQuery.of(context).size;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // MAXIMIZED reel size - 80% width, 85% of available height
          maxWidth: screenSize.width * 0.80,
          maxHeight: screenSize.height * 0.85,
        ),
        child: AspectRatio(
          aspectRatio: reels / rows * 1.2, // Slightly less stretched
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
                  // Reel content
                  SlotPreviewWidget(
                    provider: provider,
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
        ),
      ),
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
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            _SlotTheme.gold.withOpacity(0.3),
            Colors.transparent,
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.auto_awesome,
          color: _SlotTheme.gold,
          size: 80,
        ),
      ),
    );
  }

  Widget _buildScatterCollect() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            _SlotTheme.jackpotMinor.withOpacity(0.3),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  Widget _buildCascadeLayer() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            FluxForgeTheme.accentCyan.withOpacity(0.2),
          ],
        ),
      ),
    );
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
      'BIG' => _SlotTheme.winBig,
      _ => _SlotTheme.winSmall,
    };
  }

  IconData _getWinIcon() {
    return switch (widget.winTier) {
      'ULTRA' => Icons.auto_awesome,
      'EPIC' => Icons.bolt,
      'MEGA' => Icons.stars,
      'BIG' => Icons.celebration,
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

  const _ControlBar({
    required this.lines,
    required this.maxLines,
    required this.coinValue,
    required this.coinValues,
    required this.betLevel,
    required this.maxBetLevel,
    required this.totalBet,
    required this.isSpinning,
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
            onDecrease: lines > 1 ? () => onLinesChanged(lines - 1) : null,
            onIncrease: lines < maxLines ? () => onLinesChanged(lines + 1) : null,
            isDisabled: isSpinning,
          ),
          const SizedBox(width: 12),

          // Coin selector
          _BetSelector(
            label: 'COIN',
            value: coinValue.toStringAsFixed(2),
            onDecrease: coinValues.indexOf(coinValue) > 0
                ? () => onCoinChanged(coinValues[coinValues.indexOf(coinValue) - 1])
                : null,
            onIncrease: coinValues.indexOf(coinValue) < coinValues.length - 1
                ? () => onCoinChanged(coinValues[coinValues.indexOf(coinValue) + 1])
                : null,
            isDisabled: isSpinning,
          ),
          const SizedBox(width: 12),

          // Bet level selector
          _BetSelector(
            label: 'BET',
            value: '$betLevel',
            onDecrease: betLevel > 1 ? () => onBetLevelChanged(betLevel - 1) : null,
            onIncrease: betLevel < maxBetLevel ? () => onBetLevelChanged(betLevel + 1) : null,
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
            onTap: isSpinning ? null : onMaxBet,
            width: 54,
            height: 54,
          ),
          const SizedBox(width: 10),

          // Auto spin button
          _ControlButton(
            label: isAutoSpin ? 'STOP\n$autoSpinCount' : 'AUTO\nSPIN',
            gradient: isAutoSpin ? _SlotTheme.autoSpinGradient : null,
            onTap: onAutoSpinToggle,
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
            onTap: onTurboToggle,
            width: 54,
            height: 54,
            isActive: isTurbo,
          ),
          const SizedBox(width: 20),

          // Main spin/stop button
          _SpinButton(
            isSpinning: isSpinning,
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
  final bool canSpin;
  final VoidCallback onSpin;
  final VoidCallback onStop;

  const _SpinButton({
    required this.isSpinning,
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
    final isEnabled = widget.canSpin || widget.isSpinning;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: () {
          if (widget.isSpinning) {
            widget.onStop();
          } else if (widget.canSpin) {
            widget.onSpin();
          }
        },
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final pulse = widget.isSpinning
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
                    colors: widget.isSpinning
                        ? [FluxForgeTheme.accentRed, const Color(0xFFCC2040)]
                        : (isEnabled
                            ? _SlotTheme.spinGradient
                            : [_SlotTheme.bgSurface, _SlotTheme.bgPanel]),
                  ),
                  border: Border.all(
                    color: widget.isSpinning
                        ? FluxForgeTheme.accentRed
                        : (isEnabled
                            ? FluxForgeTheme.accentBlue
                            : _SlotTheme.border),
                    width: _isHovered ? 4 : 3,
                  ),
                  boxShadow: [
                    if (isEnabled)
                      BoxShadow(
                        color: (widget.isSpinning
                                ? FluxForgeTheme.accentRed
                                : FluxForgeTheme.accentBlue)
                            .withOpacity(_isHovered ? 0.6 : 0.4),
                        blurRadius: _isHovered ? 24 : 16,
                        spreadRadius: _isHovered ? 4 : 2,
                      ),
                  ],
                ),
                child: Center(
                  child: widget.isSpinning
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
  final VoidCallback onPaytableToggle;
  final VoidCallback onRulesToggle;
  final VoidCallback onHistoryToggle;
  final VoidCallback onStatsToggle;

  const _InfoPanels({
    this.showPaytable = false,
    this.showRules = false,
    this.showHistory = false,
    this.showStats = false,
    this.recentWins = const [],
    this.totalSpins = 0,
    this.rtp = 0.0,
    required this.onPaytableToggle,
    required this.onRulesToggle,
    required this.onHistoryToggle,
    required this.onStatsToggle,
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
// H. AUDIO/VISUAL CONTROLS
// =============================================================================

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

class _AmbientParticle {
  double x, y, vx, vy, size, opacity, pulsePhase;
  Color color;

  _AmbientParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.pulsePhase,
    required this.color,
  });

  void update() {
    x += vx;
    y += vy;

    if (x < -0.1) x = 1.1;
    if (x > 1.1) x = -0.1;
    if (y < -0.1) y = 1.1;
    if (y > 1.1) y = -0.1;

    vy += (math.Random().nextDouble() - 0.5) * 0.0001;
    vy = vy.clamp(-0.002, 0.002);
  }
}

class _AmbientParticlePainter extends CustomPainter {
  final List<_AmbientParticle> particles;
  final double time;

  _AmbientParticlePainter({required this.particles, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final pulse = (math.sin(time * 2 + p.pulsePhase) + 1) / 2;
      final opacity = p.opacity * (0.3 + pulse * 0.7);

      final paint = Paint()
        ..color = p.color.withOpacity(opacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.5);

      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );

      final corePaint = Paint()
        ..color = Colors.white.withOpacity((opacity * 0.5).clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size * 0.3,
        corePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientParticlePainter oldDelegate) =>
      oldDelegate.time != time;
}

// =============================================================================
// MAIN PREMIUM SLOT PREVIEW WIDGET
// =============================================================================

class PremiumSlotPreview extends StatefulWidget {
  final VoidCallback onExit;
  final int reels;
  final int rows;

  const PremiumSlotPreview({
    super.key,
    required this.onExit,
    this.reels = 5,
    this.rows = 3,
  });

  @override
  State<PremiumSlotPreview> createState() => _PremiumSlotPreviewState();
}

class _PremiumSlotPreviewState extends State<PremiumSlotPreview>
    with TickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();

  // Animation controllers
  late AnimationController _ambientController;
  late AnimationController _jackpotTickController;

  // Particles
  final List<_AmbientParticle> _particles = [];
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

  // Jackpots (simulated progressive)
  double _miniJackpot = 125.50;
  double _minorJackpot = 1250.00;
  double _majorJackpot = 12500.00;
  double _grandJackpot = 125000.00;
  double _progressiveContribution = 0.0;

  // Bet settings
  int _lines = 25;
  double _coinValue = 0.10;
  int _betLevel = 5;
  double get _totalBetAmount => _lines * _coinValue * _betLevel;

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

  // Settings
  bool _isTurbo = false;
  bool _isMusicOn = true;
  bool _isSfxOn = true;
  double _masterVolume = 0.8;
  int _graphicsQuality = 2;
  bool _animationsEnabled = true;
  bool _isFullscreen = true;

  // UI state
  bool _showSettingsPanel = false;
  bool _showPaytable = false;
  bool _showRules = false;
  bool _showHistory = false;
  bool _showStats = false;
  bool _showWinPresenter = false;
  String _currentWinTier = '';
  double _currentWinAmount = 0.0;

  // Coin values
  static const List<double> _coinValues = [0.01, 0.02, 0.05, 0.10, 0.20, 0.50, 1.00];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initParticles();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _initAnimations() {
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _ambientController.addListener(_updateParticles);

    _jackpotTickController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
    _jackpotTickController.addListener(_tickJackpots);
  }

  void _initParticles() {
    final colors = [
      FluxForgeTheme.accentBlue.withOpacity(0.6),
      FluxForgeTheme.accentCyan.withOpacity(0.5),
      _SlotTheme.gold.withOpacity(0.4),
      _SlotTheme.jackpotMinor.withOpacity(0.3),
    ];

    for (int i = 0; i < 40; i++) {
      _particles.add(_AmbientParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        vx: (_random.nextDouble() - 0.5) * 0.001,
        vy: (_random.nextDouble() - 0.5) * 0.001,
        size: _random.nextDouble() * 4 + 2,
        opacity: _random.nextDouble() * 0.4 + 0.2,
        pulsePhase: _random.nextDouble() * math.pi * 2,
        color: colors[_random.nextInt(colors.length)],
      ));
    }
  }

  void _updateParticles() {
    if (!mounted) return;
    for (final p in _particles) {
      p.update();
    }
  }

  void _tickJackpots() {
    if (!mounted) return;
    // Only tick jackpots slowly when NOT during a spin
    // The contribution increases when player bets
    if (_progressiveContribution > 0) {
      setState(() {
        // Each tier grows at different rates (slower, more realistic)
        // Mini: $0.001/tick, Minor: $0.003/tick, Major: $0.008/tick, Grand: $0.02/tick
        _miniJackpot += 0.001 * _progressiveContribution;
        _minorJackpot += 0.003 * _progressiveContribution;
        _majorJackpot += 0.008 * _progressiveContribution;
        _grandJackpot += 0.02 * _progressiveContribution;
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
          _miniJackpot = 100.0; // Reset to seed
        case 'MINOR':
          jackpotAmount = _minorJackpot;
          _minorJackpot = 1000.0;
        case 'MAJOR':
          jackpotAmount = _majorJackpot;
          _majorJackpot = 10000.0;
        case 'GRAND':
          jackpotAmount = _grandJackpot;
          _grandJackpot = 100000.0;
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
    _ambientController.dispose();
    _jackpotTickController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // === HANDLERS ===

  void _handleSpin(SlotLabProvider provider) {
    if (provider.isPlayingStages) return;
    if (_balance < _totalBetAmount) return;

    setState(() {
      _balance -= _totalBetAmount;
      _totalBet += _totalBetAmount;
      _totalSpins++;
      // Progressive contribution based on bet amount (1% of bet goes to jackpot pool)
      _progressiveContribution = 0.01 * _totalBetAmount;
      // Add small amount to each jackpot per bet
      _miniJackpot += _totalBetAmount * 0.005;
      _minorJackpot += _totalBetAmount * 0.003;
      _majorJackpot += _totalBetAmount * 0.002;
      _grandJackpot += _totalBetAmount * 0.001;
      _showWinPresenter = false;
    });

    provider.spin().then((result) {
      if (result != null && mounted) {
        _processResult(result);
      }
    });
  }

  void _handleForcedSpin(SlotLabProvider provider, ForcedOutcome outcome) {
    if (provider.isPlayingStages) return;
    if (_balance < _totalBetAmount) return;

    setState(() {
      _balance -= _totalBetAmount;
      _totalBet += _totalBetAmount;
      _totalSpins++;
      _showWinPresenter = false;
    });

    provider.spinForced(outcome).then((result) {
      if (result != null && mounted) {
        _processResult(result);
      }
    });
  }

  void _processResult(SlotLabSpinResult result) {
    final winAmount = result.totalWin * _totalBetAmount;

    // Reset progressive contribution after spin
    _progressiveContribution = 0.0;

    setState(() {
      _totalWin += winAmount;
      _balance += winAmount;

      if (result.isWin) {
        _wins++;
        _currentWinTier = _getWinTier(result.totalWin);
        _currentWinAmount = winAmount;

        // Check for jackpot win (based on forced outcome or random chance)
        if (result.totalWin >= 100) {
          // ULTRA win - chance for GRAND jackpot
          if (_random.nextDouble() < 0.01) {
            _awardJackpot('GRAND');
            return;
          } else if (_random.nextDouble() < 0.05) {
            _awardJackpot('MAJOR');
            return;
          }
        } else if (result.totalWin >= 50) {
          // EPIC win - chance for MAJOR/MINOR
          if (_random.nextDouble() < 0.02) {
            _awardJackpot('MAJOR');
            return;
          } else if (_random.nextDouble() < 0.08) {
            _awardJackpot('MINOR');
            return;
          }
        } else if (result.totalWin >= 25) {
          // MEGA win - chance for MINOR/MINI
          if (_random.nextDouble() < 0.05) {
            _awardJackpot('MINOR');
            return;
          } else if (_random.nextDouble() < 0.15) {
            _awardJackpot('MINI');
            return;
          }
        } else if (result.totalWin >= 10) {
          // BIG win - small chance for MINI
          if (_random.nextDouble() < 0.10) {
            _awardJackpot('MINI');
            return;
          }
        }

        if (winAmount > _totalBetAmount * 2) {
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
        }
      } else {
        _losses++;
        _currentWinTier = '';
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

  String _getWinTier(double win) {
    final ratio = win;
    if (ratio >= 100) return 'ULTRA';
    if (ratio >= 50) return 'EPIC';
    if (ratio >= 25) return 'MEGA';
    if (ratio >= 10) return 'BIG';
    return 'SMALL';
  }

  void _handleStop() {
    // Stop current spin animation (if supported)
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
        if (_showSettingsPanel) {
          setState(() => _showSettingsPanel = false);
        } else if (_showWinPresenter) {
          setState(() => _showWinPresenter = false);
        } else {
          widget.onExit();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.space:
        _handleSpin(provider);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyM:
        setState(() => _isMusicOn = !_isMusicOn);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyS:
        setState(() => _showStats = !_showStats);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyT:
        setState(() => _isTurbo = !_isTurbo);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyA:
        _handleAutoSpinToggle();
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
    final isSpinning = provider.isPlayingStages;
    final canSpin = _balance >= _totalBetAmount && !isSpinning;
    final sessionRtp = _totalBet > 0 ? (_totalWin / _totalBet * 100) : 0.0;

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
                  onMenuTap: () {},
                  onMusicToggle: () => setState(() => _isMusicOn = !_isMusicOn),
                  onSfxToggle: () => setState(() => _isSfxOn = !_isSfxOn),
                  onSettingsTap: () => setState(() => _showSettingsPanel = !_showSettingsPanel),
                  onFullscreenToggle: () {},
                  onExit: widget.onExit,
                ),

                // B. Jackpot Zone
                _JackpotZone(
                  miniJackpot: _miniJackpot,
                  minorJackpot: _minorJackpot,
                  majorJackpot: _majorJackpot,
                  grandJackpot: _grandJackpot,
                  progressiveContribution: _progressiveContribution,
                ),

                // E. Feature Indicators (above game zone)
                _FeatureIndicators(
                  freeSpins: _freeSpins,
                  freeSpinsRemaining: _freeSpinsRemaining,
                  bonusMeter: _bonusMeter,
                  featureProgress: _featureProgress,
                  multiplier: _multiplier,
                  cascadeCount: _cascadeCount,
                  specialSymbolCount: _specialSymbolCount,
                ),

                // C. Main Game Zone
                Expanded(
                  child: _MainGameZone(
                    provider: provider,
                    reels: widget.reels,
                    rows: widget.rows,
                    winTier: _currentWinTier,
                    particles: _particles,
                    animationTime: _ambientController.value * 10,
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
                  onTurboToggle: () => setState(() => _isTurbo = !_isTurbo),
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
                  onTap: () => setState(() => _showWinPresenter = false),
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    child: _WinPresenter(
                      winAmount: _currentWinAmount,
                      winTier: _currentWinTier,
                      multiplier: _multiplier.toDouble(),
                      showCollect: true,
                      onCollect: () => setState(() => _showWinPresenter = false),
                    ),
                  ),
                ),
              ),

            // H. Settings Panel (overlay)
            if (_showSettingsPanel)
              Positioned(
                top: 70,
                right: 16,
                child: _AudioVisualPanel(
                  volume: _masterVolume,
                  isMusicOn: _isMusicOn,
                  isSfxOn: _isSfxOn,
                  quality: _graphicsQuality,
                  animationsEnabled: _animationsEnabled,
                  onVolumeChanged: (v) => setState(() => _masterVolume = v),
                  onMusicToggle: () => setState(() => _isMusicOn = !_isMusicOn),
                  onSfxToggle: () => setState(() => _isSfxOn = !_isSfxOn),
                  onQualityChanged: (v) => setState(() => _graphicsQuality = v),
                  onAnimationsToggle: () =>
                      setState(() => _animationsEnabled = !_animationsEnabled),
                  onClose: () => setState(() => _showSettingsPanel = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
