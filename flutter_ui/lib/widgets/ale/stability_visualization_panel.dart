/// Stability Mechanism Visualization Panel — ALE Stability System
///
/// Visualizes the 7 stability mechanisms:
/// 1. Global Cooldown — Minimum time between any level changes
/// 2. Rule Cooldown — Per-rule cooldown after firing
/// 3. Level Hold — Lock level for duration after change
/// 4. Hysteresis — Different thresholds for up vs down
/// 5. Level Inertia — Higher levels resist change more
/// 6. Decay — Auto-decrease level after inactivity
/// 7. Prediction — Anticipate player behavior

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Stability mechanism type
enum StabilityMechanism {
  globalCooldown('Global Cooldown', Icons.timer, 'Minimum time between any level changes'),
  ruleCooldown('Rule Cooldown', Icons.timer_off, 'Per-rule cooldown after firing'),
  levelHold('Level Hold', Icons.lock_clock, 'Lock level for duration after change'),
  hysteresis('Hysteresis', Icons.swap_vert, 'Different thresholds for up vs down'),
  levelInertia('Level Inertia', Icons.trending_flat, 'Higher levels resist change more'),
  decay('Decay', Icons.trending_down, 'Auto-decrease level after inactivity'),
  prediction('Prediction', Icons.psychology, 'Anticipate player behavior');

  final String label;
  final IconData icon;
  final String description;
  const StabilityMechanism(this.label, this.icon, this.description);
}

class StabilityVisualizationPanel extends StatefulWidget {
  final double height;

  const StabilityVisualizationPanel({
    super.key,
    this.height = 500,
  });

  @override
  State<StabilityVisualizationPanel> createState() => _StabilityVisualizationPanelState();
}

class _StabilityVisualizationPanelState extends State<StabilityVisualizationPanel>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _decayController;

  // Simulated state
  int _currentLevel = 1;
  final int _maxLevel = 5;
  DateTime? _lastLevelChange;
  DateTime? _holdUntil;
  bool _isInCooldown = false;
  bool _isHolding = false;
  Timer? _simulationTimer;
  final List<_LevelChangeEvent> _changeHistory = [];

  // For decay visualization
  double _decayProgress = 0.0;
  int _decayCooldownRemaining = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _decayController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    _startSimulationTimer();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _decayController.dispose();
    _simulationTimer?.cancel();
    super.dispose();
  }

  void _startSimulationTimer() {
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateSimulationState();
    });
  }

  void _updateSimulationState() {
    final now = DateTime.now();
    final config = context.read<AleProvider>().profile?.stability ?? const AleStabilityConfig();

    // Update cooldown state
    if (_lastLevelChange != null) {
      final elapsed = now.difference(_lastLevelChange!).inMilliseconds;
      _isInCooldown = elapsed < config.cooldownMs;
    }

    // Update hold state
    if (_holdUntil != null) {
      _isHolding = now.isBefore(_holdUntil!);
      if (!_isHolding) {
        _holdUntil = null;
      }
    }

    // Update decay progress
    if (_lastLevelChange != null && config.decayMs > 0) {
      final elapsed = now.difference(_lastLevelChange!).inMilliseconds;
      _decayProgress = (elapsed / config.decayMs).clamp(0.0, 1.0);
      _decayCooldownRemaining = (config.decayMs - elapsed).clamp(0, config.decayMs);
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Consumer<AleProvider>(
        builder: (context, ale, _) {
          final config = ale.profile?.stability ?? const AleStabilityConfig();
          return Column(
            children: [
              _buildHeader(ale),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Level display
                      _buildLevelDisplay(),
                      const SizedBox(height: 16),

                      // Mechanism cards
                      _buildMechanismCard(
                        StabilityMechanism.globalCooldown,
                        _buildGlobalCooldownViz(config),
                        config.cooldownMs > 0,
                      ),
                      _buildMechanismCard(
                        StabilityMechanism.levelHold,
                        _buildLevelHoldViz(config),
                        config.holdMs > 0,
                      ),
                      _buildMechanismCard(
                        StabilityMechanism.hysteresis,
                        _buildHysteresisViz(config),
                        config.hysteresisUp > 0 || config.hysteresisDown > 0,
                      ),
                      _buildMechanismCard(
                        StabilityMechanism.levelInertia,
                        _buildInertiaViz(config),
                        config.levelInertia > 0,
                      ),
                      _buildMechanismCard(
                        StabilityMechanism.decay,
                        _buildDecayViz(config),
                        config.decayMs > 0,
                      ),
                      _buildMechanismCard(
                        StabilityMechanism.prediction,
                        _buildPredictionViz(config),
                        config.predictionEnabled,
                      ),

                      const SizedBox(height: 16),

                      // Change history
                      _buildChangeHistory(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(AleProvider ale) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.balance, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Text(
            'Stability Mechanisms',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          // Quick test buttons
          _buildQuickTestButton('↑', Colors.green, _stepUp),
          const SizedBox(width: 4),
          _buildQuickTestButton('↓', Colors.orange, _stepDown),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.replay, size: 14),
            label: const Text('Reset'),
            onPressed: _resetState,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTestButton(String label, Color color, VoidCallback onPressed) {
    return Material(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelDisplay() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Current Level: ',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 12,
                ),
              ),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isHolding ? 1.0 + _pulseController.value * 0.1 : 1.0,
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getLevelColor(_currentLevel),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      if (_isHolding)
                        BoxShadow(
                          color: _getLevelColor(_currentLevel).withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                    ],
                  ),
                  child: Text(
                    'L$_currentLevel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
              if (_isHolding) ...[
                const SizedBox(width: 8),
                Icon(Icons.lock, size: 16, color: Colors.orange),
              ],
              if (_isInCooldown) ...[
                const SizedBox(width: 8),
                Icon(Icons.timer, size: 16, color: Colors.blue),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Level bar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_maxLevel, (i) {
              final level = i + 1;
              final isActive = level <= _currentLevel;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? _getLevelColor(level)
                      : FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMechanismCard(
    StabilityMechanism mechanism,
    Widget visualization,
    bool isEnabled,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEnabled
              ? _getMechanismColor(mechanism).withValues(alpha: 0.3)
              : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isEnabled
                ? _getMechanismColor(mechanism).withValues(alpha: 0.2)
                : FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            mechanism.icon,
            size: 16,
            color: isEnabled
                ? _getMechanismColor(mechanism)
                : FluxForgeTheme.textMuted,
          ),
        ),
        title: Row(
          children: [
            Text(
              mechanism.label,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isEnabled
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isEnabled ? 'ACTIVE' : 'OFF',
                style: TextStyle(
                  color: isEnabled ? Colors.green : FluxForgeTheme.textMuted,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          mechanism.description,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
          ),
        ),
        iconColor: FluxForgeTheme.textMuted,
        collapsedIconColor: FluxForgeTheme.textMuted,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: visualization,
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalCooldownViz(AleStabilityConfig config) {
    final cooldownMs = config.cooldownMs;
    int remainingMs = 0;
    double progress = 0;

    if (_lastLevelChange != null && _isInCooldown) {
      final elapsed = DateTime.now().difference(_lastLevelChange!).inMilliseconds;
      remainingMs = (cooldownMs - elapsed).clamp(0, cooldownMs);
      progress = 1.0 - (remainingMs / cooldownMs);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Cooldown: ${cooldownMs}ms',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            if (_isInCooldown)
              Text(
                '${remainingMs}ms remaining',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: FluxForgeTheme.bgDeep,
            valueColor: AlwaysStoppedAnimation(
              _isInCooldown ? Colors.orange : Colors.green,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              _isInCooldown ? Icons.timer : Icons.check_circle,
              size: 14,
              color: _isInCooldown ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 4),
            Text(
              _isInCooldown ? 'Level changes blocked' : 'Ready for changes',
              style: TextStyle(
                color: _isInCooldown ? Colors.orange : Colors.green,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLevelHoldViz(AleStabilityConfig config) {
    final holdMs = config.holdMs;
    int remainingMs = 0;
    double progress = 0;

    if (_holdUntil != null && _isHolding) {
      remainingMs = _holdUntil!.difference(DateTime.now()).inMilliseconds.clamp(0, holdMs);
      progress = 1.0 - (remainingMs / holdMs);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Hold Duration: ${holdMs}ms',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            if (_isHolding)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, size: 10, color: Colors.purple),
                    const SizedBox(width: 2),
                    Text(
                      'LOCKED L$_currentLevel',
                      style: TextStyle(
                        color: Colors.purple,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: FluxForgeTheme.bgDeep,
            valueColor: AlwaysStoppedAnimation(Colors.purple),
          ),
        ),
        if (_isHolding) ...[
          const SizedBox(height: 8),
          Text(
            '${remainingMs}ms until unlock',
            style: TextStyle(
              color: Colors.purple,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHysteresisViz(AleStabilityConfig config) {
    final upThreshold = config.hysteresisUp;
    final downThreshold = config.hysteresisDown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildThresholdBar(
                'Step Up',
                upThreshold,
                Colors.green,
                Icons.arrow_upward,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildThresholdBar(
                'Step Down',
                downThreshold,
                Colors.orange,
                Icons.arrow_downward,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Visual threshold diagram
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            size: const Size(double.infinity, 80),
            painter: _HysteresisPainter(
              upThreshold: upThreshold,
              downThreshold: downThreshold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Higher threshold for going up prevents oscillation',
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildThresholdBar(String label, double value, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: FluxForgeTheme.bgSurface,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInertiaViz(AleStabilityConfig config) {
    final inertia = config.levelInertia;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Base Inertia: ${(inertia * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        // Level-specific inertia bars
        ...List.generate(_maxLevel, (i) {
          final level = i + 1;
          final levelInertia = inertia * level / _maxLevel;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    'L$level',
                    style: TextStyle(
                      color: _currentLevel == level
                          ? _getLevelColor(level)
                          : FluxForgeTheme.textMuted,
                      fontSize: 10,
                      fontWeight: _currentLevel == level
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: levelInertia,
                      minHeight: 6,
                      backgroundColor: FluxForgeTheme.bgDeep,
                      valueColor: AlwaysStoppedAnimation(_getLevelColor(level)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(levelInertia * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        Text(
          'Higher levels are "stickier" and resist changes more',
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildDecayViz(AleStabilityConfig config) {
    final decayMs = config.decayMs;
    final decayRate = config.decayRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Decay Timer: ${decayMs}ms',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Rate: ${(decayRate * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _decayProgress,
            minHeight: 12,
            backgroundColor: FluxForgeTheme.bgDeep,
            valueColor: AlwaysStoppedAnimation(
              _decayProgress > 0.8 ? Colors.red : Colors.blue,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Last change',
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 9),
            ),
            if (_decayCooldownRemaining > 0)
              Text(
                '${(_decayCooldownRemaining / 1000).toStringAsFixed(1)}s until decay',
                style: TextStyle(
                  color: _decayProgress > 0.8 ? Colors.red : FluxForgeTheme.textMuted,
                  fontSize: 9,
                ),
              ),
            Text(
              'Decay triggers',
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 9),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Level automatically decreases after inactivity',
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionViz(AleStabilityConfig config) {
    final momentumWindow = config.momentumWindow;
    final enabled = config.predictionEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: enabled
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                enabled ? 'ENABLED' : 'DISABLED',
                style: TextStyle(
                  color: enabled ? Colors.green : FluxForgeTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Window: ${momentumWindow}ms',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 60,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            size: const Size(double.infinity, 60),
            painter: _PredictionPainter(
              events: _changeHistory,
              windowMs: momentumWindow,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Analyzes recent patterns to anticipate player behavior',
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildChangeHistory() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Change History',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '${_changeHistory.length} events',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_changeHistory.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No level changes yet. Use ↑↓ buttons to test.',
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _changeHistory.length,
                itemBuilder: (context, index) {
                  final event = _changeHistory[index];
                  return _buildHistoryEvent(event);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryEvent(_LevelChangeEvent event) {
    return Container(
      width: 60,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            event.direction == 1 ? Icons.arrow_upward : Icons.arrow_downward,
            color: event.direction == 1 ? Colors.green : Colors.orange,
            size: 16,
          ),
          const SizedBox(height: 4),
          Text(
            'L${event.fromLevel}→L${event.toLevel}',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatTimeShort(event.timestamp),
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _stepUp() {
    if (_isInCooldown || _isHolding) return;
    if (_currentLevel >= _maxLevel) return;

    final config = context.read<AleProvider>().profile?.stability ?? const AleStabilityConfig();
    final fromLevel = _currentLevel;

    setState(() {
      _currentLevel++;
      _lastLevelChange = DateTime.now();
      _holdUntil = DateTime.now().add(Duration(milliseconds: config.holdMs));
      _changeHistory.add(_LevelChangeEvent(
        fromLevel: fromLevel,
        toLevel: _currentLevel,
        timestamp: DateTime.now(),
        direction: 1,
      ));
      if (_changeHistory.length > 20) {
        _changeHistory.removeAt(0);
      }
    });
  }

  void _stepDown() {
    if (_isInCooldown || _isHolding) return;
    if (_currentLevel <= 1) return;

    final config = context.read<AleProvider>().profile?.stability ?? const AleStabilityConfig();
    final fromLevel = _currentLevel;

    setState(() {
      _currentLevel--;
      _lastLevelChange = DateTime.now();
      _holdUntil = DateTime.now().add(Duration(milliseconds: config.holdMs));
      _changeHistory.add(_LevelChangeEvent(
        fromLevel: fromLevel,
        toLevel: _currentLevel,
        timestamp: DateTime.now(),
        direction: -1,
      ));
      if (_changeHistory.length > 20) {
        _changeHistory.removeAt(0);
      }
    });
  }

  void _resetState() {
    setState(() {
      _currentLevel = 1;
      _lastLevelChange = null;
      _holdUntil = null;
      _isInCooldown = false;
      _isHolding = false;
      _changeHistory.clear();
      _decayProgress = 0;
    });
  }

  Color _getLevelColor(int level) {
    return switch (level) {
      1 => Colors.blue,
      2 => Colors.green,
      3 => Colors.yellow.shade700,
      4 => Colors.orange,
      5 => Colors.red,
      _ => FluxForgeTheme.textMuted,
    };
  }

  Color _getMechanismColor(StabilityMechanism mechanism) {
    return switch (mechanism) {
      StabilityMechanism.globalCooldown => Colors.orange,
      StabilityMechanism.ruleCooldown => Colors.amber,
      StabilityMechanism.levelHold => Colors.purple,
      StabilityMechanism.hysteresis => Colors.cyan,
      StabilityMechanism.levelInertia => Colors.green,
      StabilityMechanism.decay => Colors.blue,
      StabilityMechanism.prediction => Colors.pink,
    };
  }

  String _formatTimeShort(DateTime time) {
    return '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

class _LevelChangeEvent {
  final int fromLevel;
  final int toLevel;
  final DateTime timestamp;
  final int direction; // 1 = up, -1 = down

  _LevelChangeEvent({
    required this.fromLevel,
    required this.toLevel,
    required this.timestamp,
    required this.direction,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════

class _HysteresisPainter extends CustomPainter {
  final double upThreshold;
  final double downThreshold;

  _HysteresisPainter({
    required this.upThreshold,
    required this.downThreshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw center line
    paint.color = FluxForgeTheme.borderSubtle;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );

    // Draw up threshold
    paint.color = Colors.green;
    final upY = size.height / 2 - (upThreshold * size.height / 2);
    canvas.drawLine(
      Offset(0, upY),
      Offset(size.width, upY),
      paint..style = PaintingStyle.stroke,
    );

    // Draw down threshold
    paint.color = Colors.orange;
    final downY = size.height / 2 + (downThreshold * size.height / 2);
    canvas.drawLine(
      Offset(0, downY),
      Offset(size.width, downY),
      paint,
    );

    // Labels
    final textStyle = TextStyle(
      color: FluxForgeTheme.textMuted,
      fontSize: 9,
    );
    final upSpan = TextSpan(text: 'UP', style: textStyle.copyWith(color: Colors.green));
    final downSpan = TextSpan(text: 'DOWN', style: textStyle.copyWith(color: Colors.orange));

    TextPainter(text: upSpan, textDirection: TextDirection.ltr)
      ..layout()
      ..paint(canvas, Offset(4, upY - 12));

    TextPainter(text: downSpan, textDirection: TextDirection.ltr)
      ..layout()
      ..paint(canvas, Offset(4, downY + 2));
  }

  @override
  bool shouldRepaint(covariant _HysteresisPainter oldDelegate) {
    return upThreshold != oldDelegate.upThreshold ||
        downThreshold != oldDelegate.downThreshold;
  }
}

class _PredictionPainter extends CustomPainter {
  final List<_LevelChangeEvent> events;
  final int windowMs;

  _PredictionPainter({
    required this.events,
    required this.windowMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (events.isEmpty) {
      final textStyle = TextStyle(
        color: FluxForgeTheme.textMuted,
        fontSize: 10,
      );
      final span = TextSpan(text: 'No data', style: textStyle);
      TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout()
        ..paint(canvas, Offset(size.width / 2 - 20, size.height / 2 - 6));
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;

    final now = DateTime.now();
    final windowStart = now.subtract(Duration(milliseconds: windowMs));

    // Filter events in window
    final windowEvents = events.where((e) => e.timestamp.isAfter(windowStart)).toList();

    // Draw events as bars
    for (int i = 0; i < windowEvents.length; i++) {
      final event = windowEvents[i];
      final age = now.difference(event.timestamp).inMilliseconds;
      final x = size.width * (1 - age / windowMs);
      final barWidth = size.width / 20;

      paint.color = event.direction == 1
          ? Colors.green.withValues(alpha: 0.7)
          : Colors.orange.withValues(alpha: 0.7);

      final barHeight = size.height * 0.6;
      final y = event.direction == 1
          ? size.height / 2 - barHeight
          : size.height / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - barWidth / 2, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }

    // Draw center line
    paint.color = FluxForgeTheme.borderSubtle;
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PredictionPainter oldDelegate) {
    return events.length != oldDelegate.events.length;
  }
}
