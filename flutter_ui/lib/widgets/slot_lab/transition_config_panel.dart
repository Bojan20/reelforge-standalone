/// Transition Config Panel — User-facing editor for scene transition settings
///
/// Allows per-feature configuration of:
/// - Entry/Exit duration (seconds)
/// - Entry/Exit dismiss mode (timed / click / timedOrClick)
/// - Transition style (fade / slideUp / slideDown / zoom / swoosh)
/// - Show plaque toggle
/// - Show win on exit toggle
///
/// Reads/writes through GameFlowProvider.setTransitionConfig()
/// Data-driven — zero hardcoded values.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/game_flow_models.dart';
import '../../providers/slot_lab/game_flow_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCENE TRANSITION PAIRS — All configurable transition pairs
// ═══════════════════════════════════════════════════════════════════════════

class _TransitionPair {
  final String key;
  final String label;
  final String shortLabel;
  final Color color;
  final IconData icon;
  final bool isEntry;

  const _TransitionPair({
    required this.key,
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.icon,
    this.isEntry = true,
  });
}

const _transitionPairs = [
  // Free Spins
  _TransitionPair(
    key: 'baseGame_to_freeSpins',
    label: 'Free Spins Entry',
    shortLabel: 'FS ENTRY',
    color: Color(0xFF00BCD4),
    icon: Icons.arrow_forward,
  ),
  _TransitionPair(
    key: 'freeSpins_to_baseGame',
    label: 'Free Spins Exit',
    shortLabel: 'FS EXIT',
    color: Color(0xFF00BCD4),
    icon: Icons.arrow_back,
    isEntry: false,
  ),
  // Hold & Win
  _TransitionPair(
    key: 'baseGame_to_holdAndWin',
    label: 'Hold & Win Entry',
    shortLabel: 'H&W ENTRY',
    color: Color(0xFFFFAA00),
    icon: Icons.arrow_forward,
  ),
  _TransitionPair(
    key: 'holdAndWin_to_baseGame',
    label: 'Hold & Win Exit',
    shortLabel: 'H&W EXIT',
    color: Color(0xFFFFAA00),
    icon: Icons.arrow_back,
    isEntry: false,
  ),
  // Bonus
  _TransitionPair(
    key: 'baseGame_to_bonusGame',
    label: 'Bonus Entry',
    shortLabel: 'BONUS ENTRY',
    color: Color(0xFFAB47BC),
    icon: Icons.arrow_forward,
  ),
  _TransitionPair(
    key: 'bonusGame_to_baseGame',
    label: 'Bonus Exit',
    shortLabel: 'BONUS EXIT',
    color: Color(0xFFAB47BC),
    icon: Icons.arrow_back,
    isEntry: false,
  ),
  // Jackpot
  _TransitionPair(
    key: 'baseGame_to_gamble',
    label: 'Jackpot Entry',
    shortLabel: 'JP ENTRY',
    color: Color(0xFFFF5252),
    icon: Icons.arrow_forward,
  ),
  _TransitionPair(
    key: 'gamble_to_baseGame',
    label: 'Jackpot Exit',
    shortLabel: 'JP EXIT',
    color: Color(0xFFFF5252),
    icon: Icons.arrow_back,
    isEntry: false,
  ),
];

// ═══════════════════════════════════════════════════════════════════════════
// PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class TransitionConfigPanel extends StatefulWidget {
  const TransitionConfigPanel({super.key});

  @override
  State<TransitionConfigPanel> createState() => _TransitionConfigPanelState();
}

class _TransitionConfigPanelState extends State<TransitionConfigPanel> {
  bool _showDefaults = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<GameFlowProvider>(
      builder: (context, flow, _) {
        final defaultConfig = flow.defaultTransitionConfig;

        return Column(
          children: [
            // Header
            _buildHeader(flow),
            // Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(6),
                children: [
                  // Default config (collapsible)
                  _buildDefaultSection(flow, defaultConfig),
                  const SizedBox(height: 8),
                  // Per-scene configs
                  _buildSectionLabel('PER-SCENE TRANSITIONS', Icons.swap_horiz),
                  const SizedBox(height: 4),
                  for (final pair in _transitionPairs) ...[
                    _buildTransitionRow(flow, pair),
                    const SizedBox(height: 3),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(GameFlowProvider flow) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF12121A),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A38))),
      ),
      child: Row(
        children: [
          const Icon(Icons.animation, color: Color(0xFF66BB6A), size: 14),
          const SizedBox(width: 6),
          const Text(
            'SCENE TRANSITIONS',
            style: TextStyle(
              color: Color(0xFF66BB6A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Enable/disable toggle
          GestureDetector(
            onTap: () {
              flow.configureTransitions(enabled: !flow.transitionsEnabled);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: flow.transitionsEnabled
                    ? const Color(0xFF66BB6A).withOpacity(0.15)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: flow.transitionsEnabled
                      ? const Color(0xFF66BB6A).withOpacity(0.4)
                      : Colors.white.withOpacity(0.1),
                ),
              ),
              child: Text(
                flow.transitionsEnabled ? 'ON' : 'OFF',
                style: TextStyle(
                  color: flow.transitionsEnabled
                      ? const Color(0xFF66BB6A)
                      : Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEFAULT CONFIG SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDefaultSection(GameFlowProvider flow, SceneTransitionConfig config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showDefaults = !_showDefaults),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  _showDefaults ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white38,
                  size: 14,
                ),
                const SizedBox(width: 4),
                const Text(
                  'DEFAULTS',
                  style: TextStyle(
                    color: Color(0xFF808090),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(config.durationMs / 1000).toStringAsFixed(1)}s / ${config.dismissMode.label}',
                  style: const TextStyle(color: Color(0xFF505060), fontSize: 9),
                ),
              ],
            ),
          ),
        ),
        if (_showDefaults) ...[
          const SizedBox(height: 4),
          _buildConfigEditor(
            config: config,
            onChanged: (updated) {
              flow.defaultTransitionConfig = updated;
            },
            color: const Color(0xFF808090),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PER-SCENE TRANSITION ROW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTransitionRow(GameFlowProvider flow, _TransitionPair pair) {
    final configs = flow.transitionConfigs;
    final config = configs[pair.key] ?? flow.defaultTransitionConfig;
    final hasOverride = configs.containsKey(pair.key);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF161620),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasOverride
              ? pair.color.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              Icon(pair.icon, color: pair.color, size: 12),
              const SizedBox(width: 4),
              Text(
                pair.shortLabel,
                style: TextStyle(
                  color: pair.color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (hasOverride)
                GestureDetector(
                  onTap: () {
                    // Remove override → fall back to defaults
                    flow.configureTransitions(
                      configs: Map.from(flow.transitionConfigs)..remove(pair.key),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'RESET',
                      style: TextStyle(color: Color(0xFF606068), fontSize: 8),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Config editor
          _buildConfigEditor(
            config: config,
            onChanged: (updated) {
              flow.setTransitionConfig(pair.key, updated);
            },
            color: pair.color,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIG EDITOR — Shared between default and per-scene
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConfigEditor({
    required SceneTransitionConfig config,
    required ValueChanged<SceneTransitionConfig> onChanged,
    required Color color,
  }) {
    return Column(
      children: [
        // Row 1: Duration + Dismiss Mode
        Row(
          children: [
            // Duration (seconds)
            _buildDurationField(
              value: config.durationMs / 1000.0,
              color: color,
              onChanged: (seconds) {
                onChanged(config.copyWith(durationMs: (seconds * 1000).round()));
              },
            ),
            const SizedBox(width: 6),
            // Dismiss mode
            Expanded(
              child: _buildDismissDropdown(
                mode: config.dismissMode,
                color: color,
                onChanged: (mode) {
                  onChanged(config.copyWith(dismissMode: mode));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Row 2: Style + Toggles
        Row(
          children: [
            // Style dropdown
            _buildStyleDropdown(
              style: config.style,
              color: color,
              onChanged: (style) {
                onChanged(config.copyWith(style: style));
              },
            ),
            const Spacer(),
            // Show plaque toggle
            _buildToggle(
              label: 'PLAQUE',
              value: config.showPlaque,
              color: color,
              onChanged: (v) {
                onChanged(config.copyWith(showPlaque: v));
              },
            ),
            const SizedBox(width: 4),
            // Show win on exit
            _buildToggle(
              label: 'WIN',
              value: config.showWinOnExit,
              color: color,
              onChanged: (v) {
                onChanged(config.copyWith(showWinOnExit: v));
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Row 3: Audio stage
        _buildAudioStageField(
          value: config.audioStage,
          color: color,
          onChanged: (stage) {
            onChanged(config.copyWith(audioStage: stage));
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIELD WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDurationField({
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Decrease
          GestureDetector(
            onTap: () {
              final newVal = (value - 0.5).clamp(0.5, 30.0);
              onChanged(newVal);
            },
            child: Icon(Icons.remove, color: color.withOpacity(0.6), size: 12),
          ),
          Expanded(
            child: Text(
              '${value.toStringAsFixed(1)}s',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Increase
          GestureDetector(
            onTap: () {
              final newVal = (value + 0.5).clamp(0.5, 30.0);
              onChanged(newVal);
            },
            child: Icon(Icons.add, color: color.withOpacity(0.6), size: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDismissDropdown({
    required TransitionDismissMode mode,
    required Color color,
    required ValueChanged<TransitionDismissMode> onChanged,
  }) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: DropdownButton<TransitionDismissMode>(
        value: mode,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: const Color(0xFF1E1E2E),
        style: TextStyle(color: color, fontSize: 9),
        icon: Icon(Icons.arrow_drop_down, color: color.withOpacity(0.5), size: 14),
        items: TransitionDismissMode.values.map((m) {
          return DropdownMenuItem(
            value: m,
            child: Text(m.label, style: TextStyle(color: color, fontSize: 9)),
          );
        }).toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _buildStyleDropdown({
    required TransitionStyle style,
    required Color color,
    required ValueChanged<TransitionStyle> onChanged,
  }) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: DropdownButton<TransitionStyle>(
        value: style,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: const Color(0xFF1E1E2E),
        style: TextStyle(color: color, fontSize: 9),
        icon: Icon(Icons.arrow_drop_down, color: color.withOpacity(0.5), size: 14),
        items: TransitionStyle.values.map((s) {
          return DropdownMenuItem(
            value: s,
            child: Text(s.label, style: TextStyle(color: color, fontSize: 9)),
          );
        }).toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _buildToggle({
    required String label,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: value ? color.withOpacity(0.12) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: value ? color.withOpacity(0.4) : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? color : Colors.white24,
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildAudioStageField({
    required String? value,
    required Color color,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        Icon(Icons.volume_up, color: color.withOpacity(0.5), size: 10),
        const SizedBox(width: 4),
        Text(
          'AUDIO',
          style: TextStyle(
            color: color.withOpacity(0.5),
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: value != null && value.isNotEmpty
                    ? color.withOpacity(0.3)
                    : Colors.white.withOpacity(0.06),
              ),
            ),
            child: TextField(
              controller: TextEditingController(text: value ?? ''),
              style: TextStyle(color: color, fontSize: 9),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                hintText: 'stage name...',
                hintStyle: TextStyle(
                  color: color.withOpacity(0.2),
                  fontSize: 9,
                ),
              ),
              onSubmitted: (val) {
                final stage = val.trim().toUpperCase();
                onChanged(stage.isEmpty ? '' : stage);
              },
            ),
          ),
        ),
        if (value != null && value.isNotEmpty) ...[
          const SizedBox(width: 2),
          GestureDetector(
            onTap: () => onChanged(''),
            child: Icon(Icons.close, color: color.withOpacity(0.4), size: 10),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF606068), size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF606068),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
