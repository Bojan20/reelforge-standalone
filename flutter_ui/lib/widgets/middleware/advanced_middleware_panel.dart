/// FluxForge Studio Advanced Middleware Panel
///
/// Combined panel with tabs for all advanced middleware features:
/// - Ducking Matrix
/// - Blend Containers
/// - Random Containers
/// - Sequence Containers
/// - Music System
/// - Attenuation Curves

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

/// Advanced Middleware Panel - All features in one tabbed interface
class AdvancedMiddlewarePanel extends StatefulWidget {
  const AdvancedMiddlewarePanel({super.key});

  @override
  State<AdvancedMiddlewarePanel> createState() => _AdvancedMiddlewarePanelState();
}

class _AdvancedMiddlewarePanelState extends State<AdvancedMiddlewarePanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _tabs = const [
    _TabInfo(
      icon: Icons.account_tree,
      label: 'States',
      color: Colors.orange,
    ),
    _TabInfo(
      icon: Icons.alt_route,
      label: 'Switches',
      color: Colors.green,
    ),
    _TabInfo(
      icon: Icons.tune,
      label: 'RTPC',
      color: Colors.cyan,
    ),
    _TabInfo(
      icon: Icons.grid_on,
      label: 'Ducking',
      color: Colors.blue,
    ),
    _TabInfo(
      icon: Icons.blur_linear,
      label: 'Blend',
      color: Colors.purple,
    ),
    _TabInfo(
      icon: Icons.shuffle,
      label: 'Random',
      color: Colors.amber,
    ),
    _TabInfo(
      icon: Icons.queue_music,
      label: 'Sequence',
      color: Colors.teal,
    ),
    _TabInfo(
      icon: Icons.music_note,
      label: 'Music',
      color: Colors.pink,
    ),
    _TabInfo(
      icon: Icons.show_chart,
      label: 'Curves',
      color: Colors.indigo,
    ),
    _TabInfo(
      icon: Icons.lan,
      label: 'Integration',
      color: Colors.lightGreen,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(provider),
              // Tab bar
              _buildTabBar(),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    _StateGroupsPanel(),
                    _SwitchGroupsPanel(),
                    _RtpcPanel(),
                    DuckingMatrixPanel(),
                    BlendContainerPanel(),
                    RandomContainerPanel(),
                    SequenceContainerPanel(),
                    MusicSystemPanel(),
                    AttenuationCurvePanel(),
                    _IntegrationPanel(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(MiddlewareProvider provider) {
    final stats = provider.stats;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          // Title
          Icon(Icons.audiotrack, color: FluxForgeTheme.accentBlue, size: 20),
          const SizedBox(width: 8),
          Text(
            'Advanced Middleware',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Wwise + FMOD + Custom',
              style: TextStyle(
                color: Colors.green,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          // Preset buttons
          _PresetButton(
            icon: Icons.casino,
            label: 'Load Slot Preset',
            color: Colors.amber,
            onTap: () {
              provider.loadSlotMachinePreset();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Slot Machine preset loaded!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          _PresetButton(
            icon: Icons.refresh,
            label: 'Reset',
            color: Colors.red,
            onTap: () {
              provider.resetToDefaults();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Reset to defaults'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: FluxForgeTheme.border),
          const SizedBox(width: 12),
          // Stats
          _buildStatChip('States', stats.stateGroups, Colors.orange),
          const SizedBox(width: 6),
          _buildStatChip('Switches', stats.switchGroups, Colors.green),
          const SizedBox(width: 6),
          _buildStatChip('RTPC', stats.rtpcs, Colors.cyan),
          const SizedBox(width: 6),
          _buildStatChip('Duck', stats.duckingRules, Colors.blue),
          const SizedBox(width: 6),
          _buildStatChip('Blend', stats.blendContainers, Colors.purple),
          const SizedBox(width: 6),
          _buildStatChip('Rand', stats.randomContainers, Colors.amber),
          const SizedBox(width: 6),
          _buildStatChip('Seq', stats.sequenceContainers, Colors.teal),
          const SizedBox(width: 6),
          _buildStatChip('Music', stats.musicSegments + stats.stingers, Colors.pink),
          const SizedBox(width: 6),
          _buildStatChip('Curves', stats.attenuationCurves, Colors.indigo),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: count > 0 ? color.withValues(alpha: 0.2) : FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: count > 0 ? color.withValues(alpha: 0.5) : FluxForgeTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: count > 0 ? color : FluxForgeTheme.textSecondary,
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: count > 0 ? color : FluxForgeTheme.textSecondary,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: count > 0 ? Colors.white : FluxForgeTheme.surface,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: _tabs[_tabController.index].color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        labelPadding: EdgeInsets.zero,
        tabs: _tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
          final isActive = _tabController.index == index;

          return Tab(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.icon,
                    size: 14,
                    color: isActive ? tab.color : FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tab.label,
                    style: TextStyle(
                      color: isActive ? tab.color : FluxForgeTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  final Color color;

  const _TabInfo({
    required this.icon,
    required this.label,
    required this.color,
  });
}

/// Compact version for sidebar/panel use
class MiddlewareQuickPanel extends StatelessWidget {
  const MiddlewareQuickPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final stats = provider.stats;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.audiotrack, size: 14, color: FluxForgeTheme.accentBlue),
                  const SizedBox(width: 8),
                  Text(
                    'Advanced Middleware',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Quick stats
              _buildQuickStat('Ducking Rules', stats.duckingRules, Icons.grid_on, Colors.blue),
              _buildQuickStat('Blend Containers', stats.blendContainers, Icons.blur_linear, Colors.purple),
              _buildQuickStat('Random Containers', stats.randomContainers, Icons.shuffle, Colors.amber),
              _buildQuickStat('Sequences', stats.sequenceContainers, Icons.queue_music, Colors.teal),
              _buildQuickStat('Music Segments', stats.musicSegments, Icons.music_note, Colors.pink),
              _buildQuickStat('Stingers', stats.stingers, Icons.flash_on, Colors.orange),
              _buildQuickStat('Attenuation Curves', stats.attenuationCurves, Icons.show_chart, Colors.indigo),
              const SizedBox(height: 8),
              // Open full panel button
              GestureDetector(
                onTap: () => _openFullPanel(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.accentBlue),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.open_in_new, size: 12, color: FluxForgeTheme.accentBlue),
                      const SizedBox(width: 4),
                      Text(
                        'Open Editor',
                        style: TextStyle(
                          color: FluxForgeTheme.accentBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStat(String label, int count, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: count > 0 ? color.withValues(alpha: 0.2) : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: count > 0 ? color : FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFullPanel(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: FluxForgeTheme.surfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Column(
            children: [
              // Dialog header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.audiotrack, size: 18, color: FluxForgeTheme.accentBlue),
                    const SizedBox(width: 8),
                    Text(
                      'Advanced Middleware Editor',
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.surface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: FluxForgeTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              const Expanded(
                child: AdvancedMiddlewarePanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATE GROUPS PANEL
// ═══════════════════════════════════════════════════════════════════════════

class _StateGroupsPanel extends StatelessWidget {
  const _StateGroupsPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final stateGroups = provider.stateGroups;

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    'State Groups',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  _AddButton(
                    label: 'Add State Group',
                    onTap: () => _showAddStateGroupDialog(context, provider),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Global game states that trigger sound changes (Wwise-style)',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 16),
              // State groups list
              Expanded(
                child: stateGroups.isEmpty
                    ? _EmptyState(
                        icon: Icons.account_tree,
                        message: 'No state groups defined',
                        hint: 'Add state groups like "GameState", "MusicMood", etc.',
                      )
                    : ListView.builder(
                        itemCount: stateGroups.length,
                        itemBuilder: (context, index) {
                          final group = stateGroups[index];
                          return _StateGroupCard(
                            group: group,
                            currentState: group.currentStateName,
                            onStateChange: (stateName) => provider.setStateByName(group.id, stateName),
                            onDelete: () => provider.unregisterStateGroup(group.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddStateGroupDialog(BuildContext context, MiddlewareProvider provider) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: Text('Add State Group', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: nameController,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Group Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
            hintText: 'e.g., GameState, MusicMood',
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                provider.registerStateGroupFromPreset(nameController.text, ['Default']);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _StateGroupCard extends StatelessWidget {
  final dynamic group;
  final String? currentState;
  final ValueChanged<String> onStateChange;
  final VoidCallback onDelete;

  const _StateGroupCard({
    required this.group,
    required this.currentState,
    required this.onStateChange,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              Text(group.name, style: TextStyle(color: FluxForgeTheme.textPrimary, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: FluxForgeTheme.textSecondary),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: (group.states as List).map<Widget>((state) {
              final isActive = state.name == currentState;
              return GestureDetector(
                onTap: () => onStateChange(state.name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.orange.withValues(alpha: 0.3) : FluxForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive ? Colors.orange : FluxForgeTheme.borderSubtle,
                    ),
                  ),
                  child: Text(
                    state.name,
                    style: TextStyle(
                      color: isActive ? Colors.orange : FluxForgeTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SWITCH GROUPS PANEL
// ═══════════════════════════════════════════════════════════════════════════

class _SwitchGroupsPanel extends StatelessWidget {
  const _SwitchGroupsPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final switchGroups = provider.switchGroups;

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    'Switch Groups',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  _AddButton(
                    label: 'Add Switch Group',
                    onTap: () => _showAddSwitchGroupDialog(context, provider),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Per-object sound variants (footsteps on different surfaces, etc.)',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 16),
              // Switch groups list
              Expanded(
                child: switchGroups.isEmpty
                    ? _EmptyState(
                        icon: Icons.alt_route,
                        message: 'No switch groups defined',
                        hint: 'Add switch groups like "Surface", "WeaponType", etc.',
                      )
                    : ListView.builder(
                        itemCount: switchGroups.length,
                        itemBuilder: (context, index) {
                          final group = switchGroups[index];
                          return _SwitchGroupCard(
                            group: group,
                            onDelete: () => provider.unregisterSwitchGroup(group.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddSwitchGroupDialog(BuildContext context, MiddlewareProvider provider) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: Text('Add Switch Group', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: nameController,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Group Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
            hintText: 'e.g., Surface, WeaponType',
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                provider.registerSwitchGroupFromPreset(nameController.text, ['Default']);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _SwitchGroupCard extends StatelessWidget {
  final dynamic group;
  final VoidCallback onDelete;

  const _SwitchGroupCard({
    required this.group,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Text(group.name, style: TextStyle(color: FluxForgeTheme.textPrimary, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: FluxForgeTheme.textSecondary),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: (group.switches as List).map<Widget>((sw) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                ),
                child: Text(
                  sw.name,
                  style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RTPC PANEL
// ═══════════════════════════════════════════════════════════════════════════

class _RtpcPanel extends StatelessWidget {
  const _RtpcPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final rtpcs = provider.rtpcDefinitions;

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    'Real-Time Parameter Controls (RTPC)',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  _AddButton(
                    label: 'Add RTPC',
                    onTap: () => _showAddRtpcDialog(context, provider),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Continuous parameters that modulate audio (health, speed, distance, etc.)',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 16),
              // RTPC list
              Expanded(
                child: rtpcs.isEmpty
                    ? _EmptyState(
                        icon: Icons.tune,
                        message: 'No RTPCs defined',
                        hint: 'Add parameters like "Health", "Speed", "Distance"',
                      )
                    : ListView.builder(
                        itemCount: rtpcs.length,
                        itemBuilder: (context, index) {
                          final rtpc = rtpcs[index];
                          return _RtpcCard(
                            rtpc: rtpc,
                            currentValue: rtpc.currentValue,
                            onValueChange: (v) => provider.setRtpc(rtpc.id, v),
                            onDelete: () => provider.unregisterRtpc(rtpc.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddRtpcDialog(BuildContext context, MiddlewareProvider provider) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: Text('Add RTPC', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: nameController,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Parameter Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
            hintText: 'e.g., Health, Speed, Distance',
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                provider.registerRtpcFromPreset({
                  'id': DateTime.now().millisecondsSinceEpoch,
                  'name': nameController.text,
                  'min': 0.0,
                  'max': 100.0,
                  'default': 50.0,
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _RtpcCard extends StatelessWidget {
  final dynamic rtpc;
  final double currentValue;
  final ValueChanged<double> onValueChange;
  final VoidCallback onDelete;

  const _RtpcCard({
    required this.rtpc,
    required this.currentValue,
    required this.onValueChange,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 16, color: Colors.cyan),
              const SizedBox(width: 8),
              Text(rtpc.name, style: TextStyle(color: FluxForgeTheme.textPrimary, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                '${currentValue.toStringAsFixed(1)}',
                style: TextStyle(color: Colors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: FluxForgeTheme.textSecondary),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${rtpc.min}', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
              Expanded(
                child: Slider(
                  value: currentValue.clamp(rtpc.min, rtpc.max).toDouble(),
                  min: rtpc.min,
                  max: rtpc.max,
                  activeColor: Colors.cyan,
                  inactiveColor: FluxForgeTheme.bgMid,
                  onChanged: onValueChange,
                ),
              ),
              Text('${rtpc.max}', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _PresetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PresetButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.accentBlue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: FluxForgeTheme.accentBlue),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: FluxForgeTheme.accentBlue, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String hint;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: FluxForgeTheme.textTertiary),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 8),
          Text(hint, style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTEGRATION PANEL — Engine Connection & Stage Ingest
// ═══════════════════════════════════════════════════════════════════════════

class _IntegrationPanel extends StatelessWidget {
  const _IntegrationPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Engine Integration',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.lightGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Unity • Unreal • Custom',
                  style: TextStyle(
                    color: Colors.lightGreen,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Connect to game engines for real-time STAGE events or import offline JSON traces',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 16),
          // Engine connection panel
          const Expanded(
            child: EngineConnectionPanel(),
          ),
        ],
      ),
    );
  }
}
