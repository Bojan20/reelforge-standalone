/// Scenario Controls for Slot Lab
///
/// Force specific outcomes for testing audio:
/// - Force Win (Small/Medium/Big)
/// - Force Big Win Tier 1/2/3
/// - Force Free Spins trigger
/// - Force Near-Miss
/// - Force Anticipation
/// - Replay Last Spin
/// - Batch Play (50/100 spins)

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Scenario control result
class ScenarioResult {
  final String type;
  final Map<String, dynamic> parameters;

  ScenarioResult(this.type, this.parameters);
}

/// Scenario Controls Widget
class ScenarioControls extends StatefulWidget {
  final ValueChanged<ScenarioResult>? onScenarioTriggered;
  final VoidCallback? onReplayLastSpin;
  final ValueChanged<int>? onBatchPlay;
  final bool isSpinning;

  const ScenarioControls({
    super.key,
    this.onScenarioTriggered,
    this.onReplayLastSpin,
    this.onBatchPlay,
    this.isSpinning = false,
  });

  @override
  State<ScenarioControls> createState() => _ScenarioControlsState();
}

class _ScenarioControlsState extends State<ScenarioControls> {
  bool _expandWinOptions = false;
  bool _expandBigWinOptions = false;
  bool _expandFeatureOptions = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.science, size: 14, color: FluxForgeTheme.accentOrange),
              const SizedBox(width: 6),
              const Text(
                'SCENARIO CONTROLS',
                style: TextStyle(
                  color: FluxForgeTheme.accentOrange,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // Reset button
              GestureDetector(
                onTap: _resetToNormal,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'RESET',
                    style: TextStyle(color: Colors.white54, fontSize: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Force Win options
          _buildExpandableSection(
            'FORCE WIN',
            Icons.stars,
            FluxForgeTheme.accentGreen,
            _expandWinOptions,
            () => setState(() => _expandWinOptions = !_expandWinOptions),
            [
              _buildScenarioButton('Small', 'win_small', {'multiplier': 5.0}),
              _buildScenarioButton('Medium', 'win_medium', {'multiplier': 20.0}),
              _buildScenarioButton('Big', 'win_big', {'multiplier': 50.0}),
            ],
          ),
          const SizedBox(height: 6),

          // Force Big Win Tier
          _buildExpandableSection(
            'BIG WIN TIER',
            Icons.emoji_events,
            const Color(0xFFF1C40F),
            _expandBigWinOptions,
            () => setState(() => _expandBigWinOptions = !_expandBigWinOptions),
            [
              _buildScenarioButton('Nice (10x)', 'bigwin_nice', {'multiplier': 15.0}),
              _buildScenarioButton('Super (30x)', 'bigwin_super', {'multiplier': 35.0}),
              _buildScenarioButton('Mega (75x)', 'bigwin_mega', {'multiplier': 75.0}),
              _buildScenarioButton('Epic (150x)', 'bigwin_epic', {'multiplier': 150.0}),
              _buildScenarioButton('ULTRA (300x+)', 'bigwin_ultra', {'multiplier': 350.0}),
            ],
          ),
          const SizedBox(height: 6),

          // Force Feature/Bonus
          _buildExpandableSection(
            'FORCE FEATURE',
            Icons.auto_awesome,
            FluxForgeTheme.accentBlue,
            _expandFeatureOptions,
            () => setState(() => _expandFeatureOptions = !_expandFeatureOptions),
            [
              _buildScenarioButton('Free Spins', 'feature_freespins', {'spins': 10}),
              _buildScenarioButton('Pick Bonus', 'feature_pickbonus', {}),
              _buildScenarioButton('Wheel Bonus', 'feature_wheel', {}),
              _buildScenarioButton('Jackpot', 'jackpot_trigger', {}),
            ],
          ),
          const SizedBox(height: 8),

          // Quick actions row
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  'Near Miss',
                  Icons.close,
                  const Color(0xFFE74C3C),
                  () => _triggerScenario('near_miss', {}),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildQuickAction(
                  'Anticipation',
                  Icons.hourglass_bottom,
                  const Color(0xFF9B59B6),
                  () => _triggerScenario('anticipation', {'reels': 2}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Replay and batch controls
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  'Replay Last',
                  Icons.replay,
                  FluxForgeTheme.accentCyan,
                  widget.onReplayLastSpin,
                  enabled: !widget.isSpinning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Batch play
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  'Batch 50',
                  Icons.fast_forward,
                  Colors.white54,
                  () => widget.onBatchPlay?.call(50),
                  enabled: !widget.isSpinning,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildQuickAction(
                  'Batch 100',
                  Icons.fast_forward,
                  Colors.white54,
                  () => widget.onBatchPlay?.call(100),
                  enabled: !widget.isSpinning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection(
    String title,
    IconData icon,
    Color color,
    bool isExpanded,
    VoidCallback onToggle,
    List<Widget> children,
  ) {
    return Column(
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isExpanded ? color.withOpacity(0.15) : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isExpanded ? color.withOpacity(0.5) : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: color,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: children,
          ),
        ],
      ],
    );
  }

  Widget _buildScenarioButton(String label, String scenarioType, Map<String, dynamic> params) {
    return GestureDetector(
      onTap: widget.isSpinning ? null : () => _triggerScenario(scenarioType, params),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isSpinning
              ? FluxForgeTheme.bgDeep.withOpacity(0.5)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: widget.isSpinning ? Colors.white24 : Colors.white70,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    bool enabled = true,
  }) {
    final isEnabled = enabled && !widget.isSpinning;

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled
              ? color.withOpacity(0.15)
              : FluxForgeTheme.bgDeep.withOpacity(0.5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isEnabled ? color.withOpacity(0.5) : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isEnabled ? color : Colors.white24,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isEnabled ? color : Colors.white24,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _triggerScenario(String type, Map<String, dynamic> params) {
    widget.onScenarioTriggered?.call(ScenarioResult(type, params));
  }

  void _resetToNormal() {
    widget.onScenarioTriggered?.call(ScenarioResult('reset', {}));
  }
}

/// Compact scenario trigger button for toolbar
class ScenarioTriggerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool isActive;

  const ScenarioTriggerButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? color : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? color : Colors.white54),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color : Colors.white54,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
