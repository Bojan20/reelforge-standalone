// ═══════════════════════════════════════════════════════════════════════════════
// BONUS SIMULATOR PANEL — Unified bonus feature testing
// ═══════════════════════════════════════════════════════════════════════════════
//
// Combines all bonus simulators into one tabbed panel:
// - Hold & Win: Grid-based locked symbols
// - Pick Bonus: Hidden prize selection
// - Gamble: Risk/double-or-nothing
//
// Uses Rust FFI for backend logic where available.

import 'package:flutter/material.dart';
import '../../../theme/fluxforge_theme.dart';
import '../../../src/rust/native_ffi.dart';
import 'hold_and_win_visualizer.dart';
import 'pick_bonus_panel.dart';
import 'gamble_simulator.dart';

/// Bonus feature type
enum BonusType {
  holdAndWin,
  pickBonus,
  gamble;

  String get displayName => switch (this) {
        holdAndWin => 'Hold & Win',
        pickBonus => 'Pick Bonus',
        gamble => 'Gamble',
      };

  IconData get icon => switch (this) {
        holdAndWin => Icons.grid_on,
        pickBonus => Icons.card_giftcard,
        gamble => Icons.casino,
      };

  Color get color => switch (this) {
        holdAndWin => Colors.amber,
        pickBonus => Colors.purple,
        gamble => Colors.red,
      };
}

/// Unified Bonus Simulator Panel
class BonusSimulatorPanel extends StatefulWidget {
  final double initialBet;
  final Function(BonusType type, double payout)? onBonusComplete;

  const BonusSimulatorPanel({
    super.key,
    this.initialBet = 1.0,
    this.onBonusComplete,
  });

  @override
  State<BonusSimulatorPanel> createState() => _BonusSimulatorPanelState();
}

class _BonusSimulatorPanelState extends State<BonusSimulatorPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ffi = NativeFFI.instance;

  // Active states from FFI
  bool _holdAndWinActive = false;
  bool _pickBonusActive = false;
  bool _gambleActive = false;

  // Stats
  double _lastPayout = 0.0;
  BonusType? _lastBonusType;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _refreshStates();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _refreshStates();
  }

  void _refreshStates() {
    setState(() {
      _holdAndWinActive = _ffi.holdAndWinIsActive();
      _pickBonusActive = _ffi.pickBonusIsActive();
      _gambleActive = _ffi.gambleIsActive();
    });
  }

  void _triggerBonus(BonusType type) {
    bool success = false;

    switch (type) {
      case BonusType.holdAndWin:
        success = _ffi.holdAndWinForceTrigger();
        break;
      case BonusType.pickBonus:
        success = _ffi.pickBonusForceTrigger();
        break;
      case BonusType.gamble:
        success = _ffi.gambleForceTrigger(widget.initialBet * 10);
        break;
    }

    if (success) {
      setState(() {
        _lastBonusType = type;
      });
      _refreshStates();

      // Switch to the appropriate tab
      final tabIndex = BonusType.values.indexOf(type);
      _tabController.animateTo(tabIndex);
    }
  }

  void _onBonusComplete(BonusType type, double payout) {
    setState(() {
      _lastPayout = payout;
      _lastBonusType = type;
    });
    _refreshStates();
    widget.onBonusComplete?.call(type, payout);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(child: _buildTabContent()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.casino, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          const Text(
            'BONUS SIMULATOR',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Quick trigger buttons
          for (final type in BonusType.values) ...[
            _QuickTriggerButton(
              type: type,
              isActive: switch (type) {
                BonusType.holdAndWin => _holdAndWinActive,
                BonusType.pickBonus => _pickBonusActive,
                BonusType.gamble => _gambleActive,
              },
              onTap: () => _triggerBonus(type),
            ),
            if (type != BonusType.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withOpacity(0.5),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        indicatorColor: Colors.amber,
        indicatorWeight: 2,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        tabs: BonusType.values.map((type) {
          final isActive = switch (type) {
            BonusType.holdAndWin => _holdAndWinActive,
            BonusType.pickBonus => _pickBonusActive,
            BonusType.gamble => _gambleActive,
          };

          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(type.icon, size: 14),
                const SizedBox(width: 4),
                Text(type.displayName),
                if (isActive) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        // Hold & Win
        _HoldAndWinTab(
          isActive: _holdAndWinActive,
          onComplete: (payout) =>
              _onBonusComplete(BonusType.holdAndWin, payout),
          onTrigger: () => _triggerBonus(BonusType.holdAndWin),
        ),

        // Pick Bonus
        _PickBonusTab(
          isActive: _pickBonusActive,
          onComplete: (payout) =>
              _onBonusComplete(BonusType.pickBonus, payout),
          onTrigger: () => _triggerBonus(BonusType.pickBonus),
        ),

        // Gamble
        _GambleTab(
          isActive: _gambleActive,
          initialStake: widget.initialBet * 10,
          onComplete: (payout) => _onBonusComplete(BonusType.gamble, payout),
          onTrigger: () => _triggerBonus(BonusType.gamble),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Status indicators
          _StatusBadge(
            label: 'H&W',
            isActive: _holdAndWinActive,
            color: BonusType.holdAndWin.color,
          ),
          const SizedBox(width: 8),
          _StatusBadge(
            label: 'Pick',
            isActive: _pickBonusActive,
            color: BonusType.pickBonus.color,
          ),
          const SizedBox(width: 8),
          _StatusBadge(
            label: 'Gamble',
            isActive: _gambleActive,
            color: BonusType.gamble.color,
          ),
          const Spacer(),
          // Last payout
          if (_lastPayout > 0 && _lastBonusType != null) ...[
            Icon(_lastBonusType!.icon,
                size: 14, color: _lastBonusType!.color),
            const SizedBox(width: 4),
            Text(
              'Last: ${_lastPayout.toStringAsFixed(2)}',
              style: TextStyle(
                color: _lastBonusType!.color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Quick trigger button
class _QuickTriggerButton extends StatelessWidget {
  final BonusType type;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickTriggerButton({
    required this.type,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isActive ? '${type.displayName} Active' : 'Trigger ${type.displayName}',
      child: InkWell(
        onTap: isActive ? null : onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? type.color.withOpacity(0.3)
                : type.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? type.color : type.color.withOpacity(0.3),
            ),
          ),
          child: Icon(
            type.icon,
            size: 14,
            color: isActive ? type.color : type.color.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}

/// Status badge
class _StatusBadge extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.isActive,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? color : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? color : Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB CONTENT WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Hold & Win tab content
class _HoldAndWinTab extends StatefulWidget {
  final bool isActive;
  final Function(double) onComplete;
  final VoidCallback onTrigger;

  const _HoldAndWinTab({
    required this.isActive,
    required this.onComplete,
    required this.onTrigger,
  });

  @override
  State<_HoldAndWinTab> createState() => _HoldAndWinTabState();
}

class _HoldAndWinTabState extends State<_HoldAndWinTab> {
  final _ffi = NativeFFI.instance;

  void _onComplete() {
    final payout = _ffi.holdAndWinComplete();
    widget.onComplete(payout);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return _InactiveState(
        type: BonusType.holdAndWin,
        onTrigger: widget.onTrigger,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: HoldAndWinVisualizer(
        onComplete: _onComplete,
      ),
    );
  }
}

/// Pick Bonus tab content
class _PickBonusTab extends StatefulWidget {
  final bool isActive;
  final Function(double) onComplete;
  final VoidCallback onTrigger;

  const _PickBonusTab({
    required this.isActive,
    required this.onComplete,
    required this.onTrigger,
  });

  @override
  State<_PickBonusTab> createState() => _PickBonusTabState();
}

class _PickBonusTabState extends State<_PickBonusTab> {
  final _ffi = NativeFFI.instance;

  void _makePick() {
    final result = _ffi.pickBonusMakePick();
    if (result != null) {
      final gameOver = result['game_over'] as bool? ?? false;
      if (gameOver) {
        final payout = _ffi.pickBonusComplete();
        widget.onComplete(payout);
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return _InactiveState(
        type: BonusType.pickBonus,
        onTrigger: widget.onTrigger,
      );
    }

    final state = _ffi.pickBonusGetStateJson();
    if (state == null) {
      return const Center(child: Text('Loading...'));
    }

    final picksMade = state['picks_made'] as int? ?? 0;
    final totalItems = state['total_items'] as int? ?? 12;
    final multiplier = state['multiplier'] as double? ?? 1.0;
    final totalWin = state['total_win'] as double? ?? 0.0;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCard('Picks', '$picksMade / $totalItems', Icons.touch_app),
              _StatCard('Multiplier', '${multiplier.toStringAsFixed(1)}x',
                  Icons.trending_up),
              _StatCard(
                  'Total Win', totalWin.toStringAsFixed(2), Icons.attach_money),
            ],
          ),
          const SizedBox(height: 16),

          // Pick grid (visual representation)
          Expanded(
            child: PickBonusPanel(
              config: PickBonusConfig(
                totalItems: totalItems,
              ),
              onComplete: () => widget.onComplete(_ffi.pickBonusTotalWin()),
            ),
          ),

          const SizedBox(height: 12),

          // Make pick button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _makePick,
              icon: const Icon(Icons.touch_app),
              label: const Text('MAKE PICK (FFI)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: BonusType.pickBonus.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gamble tab content
class _GambleTab extends StatefulWidget {
  final bool isActive;
  final double initialStake;
  final Function(double) onComplete;
  final VoidCallback onTrigger;

  const _GambleTab({
    required this.isActive,
    required this.initialStake,
    required this.onComplete,
    required this.onTrigger,
  });

  @override
  State<_GambleTab> createState() => _GambleTabState();
}

class _GambleTabState extends State<_GambleTab> {
  final _ffi = NativeFFI.instance;

  void _makeChoice(int index) {
    final result = _ffi.gambleMakeChoice(index);
    if (result != null) {
      final gameOver = result['game_over'] as bool? ?? false;
      if (gameOver) {
        final payout = _ffi.gambleCollect();
        widget.onComplete(payout);
      }
      setState(() {});
    }
  }

  void _collect() {
    final payout = _ffi.gambleCollect();
    widget.onComplete(payout);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return _InactiveState(
        type: BonusType.gamble,
        onTrigger: widget.onTrigger,
      );
    }

    final state = _ffi.gambleGetStateJson();
    if (state == null) {
      // Fall back to UI-only simulator
      return Padding(
        padding: const EdgeInsets.all(12),
        child: GambleSimulator(
          initialStake: widget.initialStake,
          onCollect: () => widget.onComplete(widget.initialStake),
          onGambleComplete: (amount, won) {
            if (!won || amount <= 0) {
              widget.onComplete(amount);
            }
          },
        ),
      );
    }

    final currentStake = state['current_stake'] as double? ?? 0.0;
    final attemptsUsed = state['attempts_used'] as int? ?? 0;
    final maxAttempts = state['max_attempts'] as int? ?? 5;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCard(
                  'Stake', currentStake.toStringAsFixed(2), Icons.attach_money),
              _StatCard('Attempts', '$attemptsUsed / $maxAttempts', Icons.repeat),
            ],
          ),
          const SizedBox(height: 16),

          // Choice buttons
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        label: 'RED',
                        color: Colors.red,
                        onTap: () => _makeChoice(0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ChoiceButton(
                        label: 'BLACK',
                        color: Colors.black87,
                        onTap: () => _makeChoice(1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Collect button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _collect,
              icon: const Icon(Icons.check),
              label: Text('COLLECT ${currentStake.toStringAsFixed(2)}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green,
                side: const BorderSide(color: Colors.green),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inactive state placeholder
class _InactiveState extends StatelessWidget {
  final BonusType type;
  final VoidCallback onTrigger;

  const _InactiveState({
    required this.type,
    required this.onTrigger,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            type.icon,
            size: 48,
            color: type.color.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '${type.displayName} Inactive',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onTrigger,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: Text('Trigger ${type.displayName}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: type.color,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stat card widget
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.white54),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Choice button for gamble
class _ChoiceButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color == Colors.black87 ? Colors.white : color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
