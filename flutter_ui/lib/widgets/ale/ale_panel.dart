/// ALE Panel Widget
///
/// Main panel for Adaptive Layer Engine with all sub-components.
/// Provides context management, signal monitoring, rule editing, and layer control.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';
import 'context_editor.dart';
import 'rule_editor.dart';
import 'signal_monitor.dart';
import 'layer_visualizer.dart';
import 'transition_editor.dart';
import 'stability_config_panel.dart';

/// Main ALE panel widget
class AlePanel extends StatefulWidget {
  const AlePanel({super.key});

  @override
  State<AlePanel> createState() => _AlePanelState();
}

class _AlePanelState extends State<AlePanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showSignalMonitor = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Initialize ALE on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ale = context.read<AleProvider>();
      if (!ale.initialized) {
        ale.initialize();
        // Load demo profile if none loaded
        if (ale.profile == null) {
          _loadDemoProfile(ale);
        }
        ale.startTickLoop(intervalMs: 50); // 20fps for UI updates
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadDemoProfile(AleProvider ale) {
    const demoProfile = '''
{
  "version": "2.0",
  "format": "ale_profile",
  "author": "FluxForge",
  "metadata": {
    "game_name": "Demo Slot",
    "game_id": "demo_slot_001",
    "target_platforms": ["desktop", "mobile"],
    "audio_budget_mb": 150
  },
  "contexts": {
    "BASE": {
      "id": "BASE",
      "name": "Base Game",
      "description": "Main gameplay context",
      "layers": [
        {"index": 0, "asset_id": "base_ambient", "base_volume": 0.3},
        {"index": 1, "asset_id": "base_rhythm", "base_volume": 0.5},
        {"index": 2, "asset_id": "base_melody", "base_volume": 0.7},
        {"index": 3, "asset_id": "base_energy", "base_volume": 0.9},
        {"index": 4, "asset_id": "base_climax", "base_volume": 1.0}
      ],
      "constraints": {
        "min_level": 0,
        "max_level": 4
      }
    },
    "FREESPINS": {
      "id": "FREESPINS",
      "name": "Free Spins",
      "description": "Bonus feature context",
      "layers": [
        {"index": 0, "asset_id": "fs_base", "base_volume": 0.4},
        {"index": 1, "asset_id": "fs_build", "base_volume": 0.6},
        {"index": 2, "asset_id": "fs_peak", "base_volume": 0.8},
        {"index": 3, "asset_id": "fs_climax", "base_volume": 1.0}
      ],
      "constraints": {
        "min_level": 0,
        "max_level": 3
      }
    },
    "BIGWIN": {
      "id": "BIGWIN",
      "name": "Big Win",
      "description": "Celebration context",
      "layers": [
        {"index": 0, "asset_id": "bw_fanfare", "base_volume": 0.8},
        {"index": 1, "asset_id": "bw_celebration", "base_volume": 1.0}
      ],
      "constraints": {
        "min_level": 0,
        "max_level": 1
      }
    }
  },
  "rules": [
    {
      "id": "momentum_up",
      "name": "Momentum Step Up",
      "condition": {
        "signal": "momentum",
        "op": "gte",
        "value": 0.7
      },
      "action": {"type": "step_up", "value": 1},
      "contexts": ["BASE", "FREESPINS"],
      "priority": 10,
      "cooldown_ms": 2000
    },
    {
      "id": "win_tier_up",
      "name": "Win Tier Step Up",
      "condition": {
        "signal": "winTier",
        "op": "gte",
        "value": 3
      },
      "action": {"type": "step_up", "value": 1},
      "contexts": ["BASE"],
      "priority": 20,
      "cooldown_ms": 1500
    },
    {
      "id": "big_win_max",
      "name": "Big Win Max Level",
      "condition": {
        "signal": "winTier",
        "op": "gte",
        "value": 5
      },
      "action": {"type": "set_level", "value": 4},
      "contexts": ["BASE"],
      "priority": 30
    },
    {
      "id": "idle_decay",
      "name": "Idle Decay",
      "condition": {
        "signal": "timeSinceWin",
        "op": "gte",
        "value": 10000
      },
      "action": {"type": "step_down", "value": 1},
      "contexts": ["BASE", "FREESPINS"],
      "priority": 5,
      "cooldown_ms": 5000
    }
  ],
  "transitions": {
    "default": {
      "id": "default",
      "name": "Default",
      "sync_mode": "immediate",
      "fade_in": {"duration_ms": 500, "curve": "ease_out_quad"},
      "fade_out": {"duration_ms": 500, "curve": "ease_out_quad"},
      "overlap": 0.5
    },
    "beat_sync": {
      "id": "beat_sync",
      "name": "Beat Sync",
      "sync_mode": "beat",
      "fade_in": {"duration_ms": 250, "curve": "linear"},
      "fade_out": {"duration_ms": 250, "curve": "linear"},
      "overlap": 0.3
    },
    "dramatic": {
      "id": "dramatic",
      "name": "Dramatic",
      "sync_mode": "bar",
      "fade_in": {"duration_ms": 1000, "curve": "ease_in_out_cubic"},
      "fade_out": {"duration_ms": 1000, "curve": "ease_in_out_cubic"},
      "overlap": 0.7
    }
  },
  "stability": {
    "global_cooldown_ms": 500,
    "level_hold_ms": 2000,
    "hysteresis": {
      "up_threshold": 0.1,
      "down_threshold": 0.05
    },
    "level_inertia": 0.3,
    "decay": {
      "enabled": true,
      "timeout_ms": 10000,
      "rate": 0.1
    },
    "momentum_buffer": {
      "window_ms": 5000,
      "weight": 0.5
    }
  }
}
''';
    ale.loadProfile(demoProfile);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AleProvider>(
      builder: (context, ale, child) {
        return KeyboardListener(
          focusNode: FocusNode()..requestFocus(),
          onKeyEvent: (event) => _handleKeyEvent(event, ale),
          child: Container(
            color: const Color(0xFF0a0a0c),
            child: Column(
              children: [
                // Top bar
                _buildTopBar(ale),

                // Main content
                Expanded(
                  child: Row(
                    children: [
                      // Left panel: Layer visualizer + Signal monitor
                      SizedBox(
                        width: 320,
                        child: Column(
                          children: [
                            // Layer visualizer
                            const SizedBox(
                              height: 200,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: LayerVisualizer(),
                              ),
                            ),

                            // Signal monitor toggle
                            if (_showSignalMonitor)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                  child: SignalMonitor(),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Main content area with tabs
                      Expanded(
                        child: Column(
                          children: [
                            // Tab bar
                            Container(
                              color: const Color(0xFF121216),
                              child: TabBar(
                                controller: _tabController,
                                indicatorColor: const Color(0xFF4a9eff),
                                labelColor: const Color(0xFF4a9eff),
                                unselectedLabelColor: const Color(0xFF888888),
                                tabs: const [
                                  Tab(
                                    icon: Icon(Icons.folder_special, size: 18),
                                    text: 'Contexts',
                                  ),
                                  Tab(
                                    icon: Icon(Icons.rule, size: 18),
                                    text: 'Rules',
                                  ),
                                  Tab(
                                    icon: Icon(Icons.swap_horiz, size: 18),
                                    text: 'Transitions',
                                  ),
                                  Tab(
                                    icon: Icon(Icons.tune, size: 18),
                                    text: 'Stability',
                                  ),
                                ],
                              ),
                            ),

                            // Tab content
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  // Contexts tab
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: ContextEditor(
                                      onContextChanged: () => setState(() {}),
                                    ),
                                  ),

                                  // Rules tab
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: RuleEditor(
                                      filterContextId: ale.state.activeContextId,
                                    ),
                                  ),

                                  // Transitions tab
                                  const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: TransitionEditor(),
                                  ),

                                  // Stability tab
                                  const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: StabilityConfigPanel(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom status bar
                _buildStatusBar(ale),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(AleProvider ale) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2a2a35)),
        ),
      ),
      child: Row(
        children: [
          // ALE logo/title
          const Icon(Icons.auto_awesome, color: Color(0xFF4a9eff), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Adaptive Layer Engine',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),

          const SizedBox(width: 16),

          // Profile name
          if (ale.profile?.gameName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a35),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                ale.profile!.gameName!,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                ),
              ),
            ),

          const Spacer(),

          // Signal monitor toggle
          _ToolbarButton(
            icon: Icons.monitor_heart,
            label: 'Signals',
            isActive: _showSignalMonitor,
            onPressed: () => setState(() => _showSignalMonitor = !_showSignalMonitor),
          ),

          const SizedBox(width: 8),

          // Test signals dropdown
          _TestSignalsDropdown(ale: ale),

          const SizedBox(width: 8),

          // Profile actions
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF888888), size: 20),
            color: const Color(0xFF1a1a20),
            onSelected: (value) => _handleProfileAction(value, ale),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 16, color: Color(0xFF888888)),
                    SizedBox(width: 8),
                    Text('New Profile', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'load',
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 16, color: Color(0xFF888888)),
                    SizedBox(width: 8),
                    Text('Load Profile', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'save',
                child: Row(
                  children: [
                    Icon(Icons.save, size: 16, color: Color(0xFF888888)),
                    SizedBox(width: 8),
                    Text('Save Profile', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 16, color: Color(0xFF888888)),
                    SizedBox(width: 8),
                    Text('Export JSON', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(AleProvider ale) {
    final activeContext = ale.activeContext;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          top: BorderSide(color: Color(0xFF2a2a35)),
        ),
      ),
      child: Row(
        children: [
          // Engine status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: ale.initialized
                  ? const Color(0xFF40ff90).withValues(alpha: 0.15)
                  : const Color(0xFFff4060).withValues(alpha: 0.15),
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
                    color: ale.initialized
                        ? const Color(0xFF40ff90)
                        : const Color(0xFFff4060),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  ale.initialized ? 'Engine Running' : 'Engine Stopped',
                  style: TextStyle(
                    color: ale.initialized
                        ? const Color(0xFF40ff90)
                        : const Color(0xFFff4060),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Active context
          if (activeContext != null) ...[
            const Icon(Icons.folder, color: Color(0xFF4a9eff), size: 14),
            const SizedBox(width: 4),
            Text(
              activeContext.id,
              style: const TextStyle(
                color: Color(0xFF4a9eff),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Level ${ale.currentLevel + 1}/${ale.layerCount}',
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
              ),
            ),
          ] else
            const Text(
              'No active context',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 11,
              ),
            ),

          const Spacer(),

          // Transition indicator
          if (ale.inTransition)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFffff40).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFFffff40)),
                    ),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Transitioning',
                    style: TextStyle(
                      color: Color(0xFFffff40),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(width: 12),

          // Tempo display
          Text(
            '${ale.tempo.toStringAsFixed(1)} BPM',
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event, AleProvider ale) {
    if (event is! KeyDownEvent) return;

    // Arrow keys for level control
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      ale.stepUp();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      ale.stepDown();
    }

    // Number keys for direct level set
    if (event.logicalKey.keyId >= LogicalKeyboardKey.digit1.keyId &&
        event.logicalKey.keyId <= LogicalKeyboardKey.digit5.keyId) {
      final level = event.logicalKey.keyId - LogicalKeyboardKey.digit1.keyId;
      ale.setLevel(level);
    }

    // Space to toggle context (demo)
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final contexts = ale.contextIds;
      if (contexts.isNotEmpty) {
        final currentIndex =
            contexts.indexOf(ale.state.activeContextId ?? '');
        final nextIndex = (currentIndex + 1) % contexts.length;
        ale.enterContext(contexts[nextIndex]);
      }
    }
  }

  void _handleProfileAction(String action, AleProvider ale) {
    switch (action) {
      case 'new':
        ale.createNewProfile(gameName: 'New Game');
        break;
      case 'load':
        // TODO: Show file picker
        break;
      case 'save':
        // TODO: Show save dialog
        break;
      case 'export':
        final json = ale.exportProfile();
        if (json != null) {
          Clipboard.setData(ClipboardData(text: json));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile JSON copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        break;
    }
  }
}

/// Toolbar button
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive
          ? const Color(0xFF4a9eff).withValues(alpha: 0.15)
          : const Color(0xFF2a2a35),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive
                    ? const Color(0xFF4a9eff)
                    : const Color(0xFF888888),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF4a9eff)
                      : const Color(0xFF888888),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Test signals dropdown for quick testing
class _TestSignalsDropdown extends StatelessWidget {
  final AleProvider ale;

  const _TestSignalsDropdown({required this.ale});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Map<String, double>>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2a2a35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science, color: Color(0xFFff9040), size: 16),
            SizedBox(width: 6),
            Text(
              'Test',
              style: TextStyle(
                color: Color(0xFFff9040),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: Color(0xFFff9040), size: 16),
          ],
        ),
      ),
      color: const Color(0xFF1a1a20),
      onSelected: (signals) => ale.updateSignals(signals),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: {'winTier': 0.0, 'momentum': 0.2},
          child: const _TestMenuItem(
            label: 'Idle State',
            description: 'Low momentum, no win',
            color: Color(0xFF4a9eff),
          ),
        ),
        PopupMenuItem(
          value: {'winTier': 2.0, 'momentum': 0.5},
          child: const _TestMenuItem(
            label: 'Small Win',
            description: 'Medium momentum',
            color: Color(0xFF40ff90),
          ),
        ),
        PopupMenuItem(
          value: {'winTier': 4.0, 'momentum': 0.8},
          child: const _TestMenuItem(
            label: 'Big Win',
            description: 'High momentum',
            color: Color(0xFFffff40),
          ),
        ),
        PopupMenuItem(
          value: {'winTier': 5.0, 'momentum': 1.0},
          child: const _TestMenuItem(
            label: 'Epic Win',
            description: 'Maximum intensity',
            color: Color(0xFFff9040),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: {'winTier': 0.0, 'momentum': 0.0, 'timeSinceWin': 15000.0},
          child: const _TestMenuItem(
            label: 'Decay Trigger',
            description: 'Long idle time',
            color: Color(0xFF888888),
          ),
        ),
      ],
    );
  }
}

/// Test menu item
class _TestMenuItem extends StatelessWidget {
  final String label;
  final String description;
  final Color color;

  const _TestMenuItem({
    required this.label,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
