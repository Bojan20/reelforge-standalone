/// AutoSpatial Panel — Main UI for AutoSpatialEngine configuration
///
/// Features:
/// - Intent Rules editor
/// - Bus Policies editor
/// - Anchor monitor
/// - Stats & config
/// - Live event visualizer

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auto_spatial_provider.dart';
import 'intent_rule_editor.dart';
import 'bus_policy_editor.dart';
import 'anchor_monitor.dart';
import 'spatial_stats_panel.dart';
import 'spatial_event_visualizer.dart';

/// Main AutoSpatial configuration panel
class AutoSpatialPanel extends StatefulWidget {
  const AutoSpatialPanel({super.key});

  @override
  State<AutoSpatialPanel> createState() => _AutoSpatialPanelState();
}

class _AutoSpatialPanelState extends State<AutoSpatialPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    // Ensure provider is initialized
    final provider = AutoSpatialProvider.instance;
    if (!provider.isInitialized) {
      provider.initialize();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: AutoSpatialProvider.instance,
      child: Container(
        color: const Color(0xFF1a1a20),
        child: Column(
          children: [
            // Header with tabs
            _buildHeader(),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  IntentRuleEditor(),
                  BusPolicyEditor(),
                  AnchorMonitor(),
                  SpatialStatsPanel(),
                  SpatialEventVisualizer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3a3a4a), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.surround_sound, color: Color(0xFF4a9eff), size: 16),
                SizedBox(width: 6),
                Text(
                  'AutoSpatial',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          Expanded(
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: const Color(0xFF4a9eff),
              indicatorWeight: 2,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Intent Rules'),
                Tab(text: 'Bus Policies'),
                Tab(text: 'Anchors'),
                Tab(text: 'Stats & Config'),
                Tab(text: 'Visualizer'),
              ],
            ),
          ),

          // Stats indicator
          Consumer<AutoSpatialProvider>(
            builder: (context, provider, _) {
              final stats = provider.stats;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatBadge(
                      label: 'Events',
                      value: '${stats.activeEvents}',
                      color: const Color(0xFF40ff90),
                    ),
                    const SizedBox(width: 8),
                    _StatBadge(
                      label: 'Pool',
                      value: '${stats.poolUtilization}%',
                      color: stats.poolUtilization > 80
                          ? const Color(0xFFff4060)
                          : const Color(0xFF4a9eff),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Small stat badge
class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact version of AutoSpatial panel for lower zone
class AutoSpatialPanelCompact extends StatelessWidget {
  const AutoSpatialPanelCompact({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: AutoSpatialProvider.instance,
      child: Container(
        color: const Color(0xFF1a1a20),
        child: Row(
          children: [
            // Left: Intent Rules list
            const Expanded(
              flex: 2,
              child: IntentRuleEditor(compact: true),
            ),

            const VerticalDivider(
              width: 1,
              color: Color(0xFF3a3a4a),
            ),

            // Center: Visualizer
            const Expanded(
              flex: 3,
              child: SpatialEventVisualizer(compact: true),
            ),

            const VerticalDivider(
              width: 1,
              color: Color(0xFF3a3a4a),
            ),

            // Right: Stats & Config
            const Expanded(
              flex: 2,
              child: SpatialStatsPanel(compact: true),
            ),
          ],
        ),
      ),
    );
  }
}
