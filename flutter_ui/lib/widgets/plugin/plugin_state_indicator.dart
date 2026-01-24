/// Plugin State Indicator
///
/// Visual indicator for plugin state in insert slots.
/// Shows installed, missing, frozen, or state-preserved status.
///
/// Documentation: .claude/architecture/PLUGIN_STATE_SYSTEM.md

import 'package:flutter/material.dart';

import '../../models/plugin_manifest.dart';

// =============================================================================
// PLUGIN STATE ENUM
// =============================================================================

/// Visual state of a plugin
enum PluginVisualState {
  /// Plugin is installed and working
  installed,

  /// Plugin is missing but state is preserved
  missingPreserved,

  /// Plugin is missing, using freeze audio
  missingFrozen,

  /// Plugin is missing with no fallback
  missingNoFallback,

  /// Plugin slot is empty
  empty,

  /// Plugin is being loaded
  loading,
}

// =============================================================================
// PLUGIN STATE INDICATOR
// =============================================================================

/// Visual indicator widget for plugin state
class PluginStateIndicator extends StatelessWidget {
  final PluginVisualState state;
  final String? pluginName;
  final String? tooltip;
  final double size;
  final VoidCallback? onTap;

  const PluginStateIndicator({
    super.key,
    required this.state,
    this.pluginName,
    this.tooltip,
    this.size = 16,
    this.onTap,
  });

  /// Create from plugin reference
  factory PluginStateIndicator.fromPlugin({
    Key? key,
    required PluginReference? plugin,
    required bool isInstalled,
    required bool hasStatePreserved,
    required bool hasFreezeAudio,
    double size = 16,
    VoidCallback? onTap,
  }) {
    if (plugin == null) {
      return PluginStateIndicator(
        key: key,
        state: PluginVisualState.empty,
        size: size,
        onTap: onTap,
      );
    }

    final PluginVisualState state;
    if (isInstalled) {
      state = PluginVisualState.installed;
    } else if (hasFreezeAudio) {
      state = PluginVisualState.missingFrozen;
    } else if (hasStatePreserved) {
      state = PluginVisualState.missingPreserved;
    } else {
      state = PluginVisualState.missingNoFallback;
    }

    return PluginStateIndicator(
      key: key,
      state: state,
      pluginName: plugin.name,
      size: size,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _getStateConfig();

    Widget indicator = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: config.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(
          color: config.color.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Icon(
        config.icon,
        size: size * 0.65,
        color: config.color,
      ),
    );

    // Add animation for loading state
    if (state == PluginVisualState.loading) {
      indicator = _AnimatedLoadingIndicator(size: size);
    }

    // Wrap with tooltip
    final tooltipText = tooltip ?? _getDefaultTooltip(config);
    indicator = Tooltip(
      message: tooltipText,
      child: indicator,
    );

    // Add tap handler
    if (onTap != null) {
      indicator = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: indicator,
        ),
      );
    }

    return indicator;
  }

  _StateConfig _getStateConfig() {
    switch (state) {
      case PluginVisualState.installed:
        return const _StateConfig(
          icon: Icons.check_circle_outline,
          color: Color(0xFF40ff90),
          label: 'Installed',
        );
      case PluginVisualState.missingPreserved:
        return const _StateConfig(
          icon: Icons.save_outlined,
          color: Color(0xFF4a9eff),
          label: 'Missing (State Preserved)',
        );
      case PluginVisualState.missingFrozen:
        return const _StateConfig(
          icon: Icons.ac_unit,
          color: Color(0xFF40c8ff),
          label: 'Missing (Freeze Audio)',
        );
      case PluginVisualState.missingNoFallback:
        return const _StateConfig(
          icon: Icons.error_outline,
          color: Color(0xFFff4060),
          label: 'Missing (No Fallback)',
        );
      case PluginVisualState.empty:
        return const _StateConfig(
          icon: Icons.add,
          color: Color(0xFF666666),
          label: 'Empty Slot',
        );
      case PluginVisualState.loading:
        return const _StateConfig(
          icon: Icons.hourglass_empty,
          color: Color(0xFFff9040),
          label: 'Loading...',
        );
    }
  }

  String _getDefaultTooltip(_StateConfig config) {
    if (pluginName != null) {
      return '$pluginName\n${config.label}';
    }
    return config.label;
  }
}

class _StateConfig {
  final IconData icon;
  final Color color;
  final String label;

  const _StateConfig({
    required this.icon,
    required this.color,
    required this.label,
  });
}

// =============================================================================
// ANIMATED LOADING INDICATOR
// =============================================================================

class _AnimatedLoadingIndicator extends StatefulWidget {
  final double size;

  const _AnimatedLoadingIndicator({required this.size});

  @override
  State<_AnimatedLoadingIndicator> createState() =>
      _AnimatedLoadingIndicatorState();
}

class _AnimatedLoadingIndicatorState extends State<_AnimatedLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: const Color(0xFFff9040).withOpacity(0.2),
            borderRadius: BorderRadius.circular(widget.size / 4),
            border: Border.all(
              color: const Color(0xFFff9040).withOpacity(0.6),
              width: 1,
            ),
          ),
          child: Transform.rotate(
            angle: _controller.value * 2 * 3.14159,
            child: Icon(
              Icons.hourglass_empty,
              size: widget.size * 0.65,
              color: const Color(0xFFff9040),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// PLUGIN STATE BADGE
// =============================================================================

/// Compact badge showing plugin state with text label
class PluginStateBadge extends StatelessWidget {
  final PluginVisualState state;
  final String? label;

  const PluginStateBadge({
    super.key,
    required this.state,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: config.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: config.color.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            config.icon,
            size: 14,
            color: config.color,
          ),
          const SizedBox(width: 6),
          Text(
            label ?? config.label,
            style: TextStyle(
              color: config.color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  _StateConfig _getConfig() {
    switch (state) {
      case PluginVisualState.installed:
        return const _StateConfig(
          icon: Icons.check_circle_outline,
          color: Color(0xFF40ff90),
          label: 'Installed',
        );
      case PluginVisualState.missingPreserved:
        return const _StateConfig(
          icon: Icons.save_outlined,
          color: Color(0xFF4a9eff),
          label: 'Preserved',
        );
      case PluginVisualState.missingFrozen:
        return const _StateConfig(
          icon: Icons.ac_unit,
          color: Color(0xFF40c8ff),
          label: 'Frozen',
        );
      case PluginVisualState.missingNoFallback:
        return const _StateConfig(
          icon: Icons.error_outline,
          color: Color(0xFFff4060),
          label: 'Missing',
        );
      case PluginVisualState.empty:
        return const _StateConfig(
          icon: Icons.add,
          color: Color(0xFF666666),
          label: 'Empty',
        );
      case PluginVisualState.loading:
        return const _StateConfig(
          icon: Icons.hourglass_empty,
          color: Color(0xFFff9040),
          label: 'Loading',
        );
    }
  }
}

// =============================================================================
// INSERT SLOT STATUS ROW
// =============================================================================

/// Row showing plugin name with state indicator
class InsertSlotStatusRow extends StatelessWidget {
  final String slotLabel;
  final PluginReference? plugin;
  final bool isInstalled;
  final bool hasStatePreserved;
  final bool hasFreezeAudio;
  final VoidCallback? onTap;
  final VoidCallback? onStatusTap;

  const InsertSlotStatusRow({
    super.key,
    required this.slotLabel,
    this.plugin,
    this.isInstalled = true,
    this.hasStatePreserved = false,
    this.hasFreezeAudio = false,
    this.onTap,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPlugin = plugin != null;
    final PluginVisualState state;

    if (!hasPlugin) {
      state = PluginVisualState.empty;
    } else if (isInstalled) {
      state = PluginVisualState.installed;
    } else if (hasFreezeAudio) {
      state = PluginVisualState.missingFrozen;
    } else if (hasStatePreserved) {
      state = PluginVisualState.missingPreserved;
    } else {
      state = PluginVisualState.missingNoFallback;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            // Slot label
            SizedBox(
              width: 24,
              child: Text(
                slotLabel,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Status indicator
            PluginStateIndicator(
              state: state,
              pluginName: plugin?.name,
              size: 14,
              onTap: onStatusTap,
            ),
            const SizedBox(width: 8),

            // Plugin name
            Expanded(
              child: Text(
                plugin?.name ?? '(Empty)',
                style: TextStyle(
                  color: hasPlugin ? Colors.white : Colors.white38,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Warning icon for missing plugins
            if (hasPlugin && !isInstalled && !hasFreezeAudio)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: hasStatePreserved
                      ? 'Plugin missing but state preserved'
                      : 'Plugin missing - no audio output',
                  child: Icon(
                    Icons.warning_amber,
                    size: 14,
                    color: hasStatePreserved
                        ? const Color(0xFF4a9eff)
                        : const Color(0xFFff4060),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
