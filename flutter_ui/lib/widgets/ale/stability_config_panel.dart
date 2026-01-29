/// Stability Config Panel Widget
///
/// Editor for ALE stability configuration (cooldown, hold, hysteresis, etc.)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';

/// Stability configuration editor panel
class StabilityConfigPanel extends StatefulWidget {
  final VoidCallback? onConfigChanged;

  const StabilityConfigPanel({
    super.key,
    this.onConfigChanged,
  });

  @override
  State<StabilityConfigPanel> createState() => _StabilityConfigPanelState();
}

class _StabilityConfigPanelState extends State<StabilityConfigPanel> {
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AleProvider>(
      builder: (context, ale, child) {
        final config = ale.profile?.stability ?? const AleStabilityConfig();

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2a2a35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(),

              // Config sections
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    // Timing section
                    _buildSection(
                      'Timing',
                      Icons.timer,
                      [
                        _ConfigSlider(
                          label: 'Global Cooldown',
                          value: config.cooldownMs.toDouble(),
                          min: 0,
                          max: 5000,
                          unit: 'ms',
                          description: 'Minimum time between any level changes',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(cooldownMs: v.toInt()));
                            widget.onConfigChanged?.call();
                          },
                        ),
                        _ConfigSlider(
                          label: 'Level Hold',
                          value: config.holdMs.toDouble(),
                          min: 0,
                          max: 10000,
                          unit: 'ms',
                          description: 'Time to hold a level before allowing decrease',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(holdMs: v.toInt()));
                            widget.onConfigChanged?.call();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Hysteresis section
                    _buildSection(
                      'Hysteresis',
                      Icons.trending_flat,
                      [
                        _ConfigSlider(
                          label: 'Upward Threshold',
                          value: config.hysteresisUp,
                          min: 0,
                          max: 0.5,
                          unit: '',
                          description: 'Extra threshold to step up',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(hysteresisUp: v));
                            widget.onConfigChanged?.call();
                          },
                        ),
                        _ConfigSlider(
                          label: 'Downward Threshold',
                          value: config.hysteresisDown,
                          min: 0,
                          max: 0.5,
                          unit: '',
                          description: 'Extra threshold to step down',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(hysteresisDown: v));
                            widget.onConfigChanged?.call();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Inertia section
                    _buildSection(
                      'Inertia & Decay',
                      Icons.speed,
                      [
                        _ConfigSlider(
                          label: 'Level Inertia',
                          value: config.levelInertia,
                          min: 0,
                          max: 1,
                          unit: '',
                          description: 'Resistance to level changes (0=none, 1=max)',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(levelInertia: v));
                            widget.onConfigChanged?.call();
                          },
                        ),
                        _ConfigSlider(
                          label: 'Decay Time',
                          value: config.decayMs.toDouble(),
                          min: 0,
                          max: 60000,
                          unit: 'ms',
                          description: 'Time before automatic level decay starts',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(decayMs: v.toInt()));
                            widget.onConfigChanged?.call();
                          },
                        ),
                        _ConfigSlider(
                          label: 'Decay Rate',
                          value: config.decayRate,
                          min: 0,
                          max: 1,
                          unit: '',
                          description: 'Speed of automatic level decay',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(decayRate: v));
                            widget.onConfigChanged?.call();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Momentum section
                    _buildSection(
                      'Momentum',
                      Icons.trending_up,
                      [
                        _ConfigSlider(
                          label: 'Window Size',
                          value: config.momentumWindow.toDouble(),
                          min: 1000,
                          max: 30000,
                          unit: 'ms',
                          description: 'Time window for momentum calculation',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(momentumWindow: v.toInt()));
                            widget.onConfigChanged?.call();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Prediction section
                    _buildSection(
                      'Prediction',
                      Icons.auto_graph,
                      [
                        _ConfigToggle(
                          label: 'Enable Prediction',
                          value: config.predictionEnabled,
                          description: 'Use ML-based level prediction',
                          enabled: _isEditing,
                          onChanged: (v) {
                            ale.updateStability(config.copyWith(predictionEnabled: v));
                            widget.onConfigChanged?.call();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Footer with edit toggle
              _buildFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, color: Color(0xFFffff40), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Stability',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          _StabilityIndicator(),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF666666), size: 14),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2a2a35)),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border(
          top: BorderSide(color: Color(0xFF2a2a35)),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Stability prevents erratic level changes',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _isEditing = !_isEditing),
            icon: Icon(
              _isEditing ? Icons.check : Icons.edit,
              size: 14,
            ),
            label: Text(_isEditing ? 'Done' : 'Edit'),
            style: TextButton.styleFrom(
              foregroundColor: _isEditing
                  ? const Color(0xFF40ff90)
                  : const Color(0xFF4a9eff),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stability status indicator
class _StabilityIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AleProvider>(
      builder: (context, ale, child) {
        // Simplified indicator - shows if stability is active
        final config = ale.profile?.stability;
        final isActive = config != null &&
            (config.cooldownMs > 0 ||
                config.holdMs > 0 ||
                config.levelInertia > 0);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF40ff90).withValues(alpha: 0.15)
                : const Color(0xFF666666).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? const Color(0xFF40ff90)
                      : const Color(0xFF666666),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                isActive ? 'Active' : 'Disabled',
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF40ff90)
                      : const Color(0xFF666666),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Config slider widget
class _ConfigSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final String description;
  final bool enabled;
  final Function(double)? onChanged;

  const _ConfigSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.description,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = unit == 'ms'
        ? '${value.toInt()}$unit'
        : value.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFcccccc),
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                displayValue,
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFF4a9eff)
                      : const Color(0xFF666666),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: enabled
                  ? const Color(0xFF4a9eff)
                  : const Color(0xFF3a3a45),
              inactiveTrackColor: const Color(0xFF2a2a35),
              thumbColor: enabled
                  ? const Color(0xFF4a9eff)
                  : const Color(0xFF3a3a45),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 6,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 12,
              ),
              overlayColor: const Color(0xFF4a9eff).withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF555555),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Config toggle widget
class _ConfigToggle extends StatelessWidget {
  final String label;
  final bool value;
  final String description;
  final bool enabled;
  final Function(bool)? onChanged;

  const _ConfigToggle({
    required this.label,
    required this.value,
    required this.description,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFcccccc),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF555555),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeColor: const Color(0xFF4a9eff),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
