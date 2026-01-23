/// Priority Tier Preset Panel — P3.8
///
/// UI for managing priority tier presets:
/// - View/apply built-in presets (Balanced, Aggressive, etc.)
/// - Create custom presets
/// - Edit category-based priorities
/// - Add stage-specific overrides
/// - Preview priority distribution
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/stage_configuration_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PRIORITY TIER PRESET PANEL
// ═══════════════════════════════════════════════════════════════════════════

class PriorityTierPresetPanel extends StatefulWidget {
  const PriorityTierPresetPanel({super.key});

  @override
  State<PriorityTierPresetPanel> createState() => _PriorityTierPresetPanelState();
}

class _PriorityTierPresetPanelState extends State<PriorityTierPresetPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _service = StageConfigurationService.instance;

  // Edit state for custom preset
  String _editPresetName = '';
  String _editPresetDescription = '';
  PriorityProfileStyle _editPresetStyle = PriorityProfileStyle.custom;
  Map<StageCategory, int> _editCategoryPriorities = {};
  Map<String, int> _editStageOverrides = {};
  bool _isEditing = false;
  String? _editingPresetId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        _buildHeader(),

        // Tab bar
        Container(
          color: const Color(0xFF1a1a20),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF4A9EFF),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: 'Presets'),
              Tab(text: 'Categories'),
              Tab(text: 'Overrides'),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPresetsTab(),
              _buildCategoriesTab(),
              _buildOverridesTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    final active = _service.activePreset;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2a2a30)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, color: Color(0xFF4A9EFF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Priority Presets',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          if (active != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Color(active.style.color).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Color(active.style.color)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getStyleIcon(active.style),
                    color: Color(active.style.color),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    active.name,
                    style: TextStyle(
                      color: Color(active.style.color),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Default',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
          const Spacer(),
          if (active != null)
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reset'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange,
              ),
              onPressed: () {
                _service.resetToDefaults();
              },
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESETS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPresetsTab() {
    final presets = _service.allPresets;
    final builtIn = presets.where((p) => p.isBuiltIn).toList();
    final custom = presets.where((p) => !p.isBuiltIn).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Built-in presets
        _buildSectionHeader('Built-in Presets', Icons.star),
        const SizedBox(height: 8),
        ...builtIn.map((p) => _buildPresetCard(p)),

        const SizedBox(height: 16),

        // Custom presets
        Row(
          children: [
            Expanded(child: _buildSectionHeader('Custom Presets', Icons.create)),
            IconButton(
              icon: const Icon(Icons.add, color: Color(0xFF4A9EFF)),
              tooltip: 'Create New Preset',
              onPressed: _startCreatePreset,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (custom.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2a2a30)),
            ),
            child: const Center(
              child: Text(
                'No custom presets yet.\nClick + to create one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          )
        else
          ...custom.map((p) => _buildPresetCard(p, canDelete: true)),

        // Create/Edit form
        if (_isEditing) ...[
          const SizedBox(height: 16),
          _buildEditForm(),
        ],
      ],
    );
  }

  Widget _buildPresetCard(PriorityTierPreset preset, {bool canDelete = false}) {
    final isActive = _service.activePreset?.id == preset.id;

    return Card(
      color: isActive ? Color(preset.style.color).withValues(alpha: 0.1) : const Color(0xFF1a1a20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isActive ? Color(preset.style.color) : const Color(0xFF2a2a30),
          width: isActive ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _service.applyPreset(preset),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(preset.style.color).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getStyleIcon(preset.style),
                  color: Color(preset.style.color),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          preset.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (preset.isBuiltIn) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Built-in',
                              style: TextStyle(color: Colors.grey, fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preset.description,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Priority preview
              _buildPriorityPreview(preset),

              const SizedBox(width: 12),

              // Actions
              if (isActive)
                const Icon(Icons.check_circle, color: Color(0xFF40FF90), size: 24)
              else if (canDelete) ...[
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  color: Colors.grey,
                  onPressed: () => _startEditPreset(preset),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  color: Colors.red.withValues(alpha: 0.7),
                  onPressed: () => _confirmDeletePreset(preset),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityPreview(PriorityTierPreset preset) {
    // Mini bar chart showing category priorities
    return SizedBox(
      width: 80,
      height: 40,
      child: CustomPaint(
        painter: _PriorityPreviewPainter(
          categoryPriorities: preset.categoryPriorities,
        ),
      ),
    );
  }

  Widget _buildEditForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4A9EFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingPresetId == null ? 'Create New Preset' : 'Edit Preset',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Name
          TextField(
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => _editPresetName = v),
            controller: TextEditingController(text: _editPresetName),
          ),
          const SizedBox(height: 12),

          // Description
          TextField(
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            onChanged: (v) => setState(() => _editPresetDescription = v),
            controller: TextEditingController(text: _editPresetDescription),
          ),
          const SizedBox(height: 12),

          // Style
          DropdownButtonFormField<PriorityProfileStyle>(
            value: _editPresetStyle,
            decoration: const InputDecoration(
              labelText: 'Style',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            dropdownColor: const Color(0xFF1a1a20),
            items: PriorityProfileStyle.values.map((s) {
              return DropdownMenuItem(
                value: s,
                child: Row(
                  children: [
                    Icon(_getStyleIcon(s), color: Color(s.color), size: 16),
                    const SizedBox(width: 8),
                    Text(s.label, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) => setState(() => _editPresetStyle = v!),
          ),
          const SizedBox(height: 16),

          // Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelEdit,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _savePreset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A9EFF),
                ),
                child: Text(_editingPresetId == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CATEGORIES TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoriesTab() {
    final active = _service.activePreset;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSectionHeader('Category Priorities', Icons.category),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2a2a30)),
          ),
          child: Column(
            children: StageCategory.values.map((category) {
              final priority = active?.getCategoryPriority(category) ??
                  _getDefaultCategoryPriority(category);

              return _buildCategoryPriorityRow(category, priority, active != null);
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        // Priority distribution chart
        _buildSectionHeader('Priority Distribution', Icons.bar_chart),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2a2a30)),
          ),
          child: CustomPaint(
            painter: _CategoryDistributionPainter(
              preset: active,
            ),
            size: const Size(double.infinity, 200),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPriorityRow(StageCategory category, int priority, bool isEditable) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          // Category icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Color(category.color).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              _getCategoryIcon(category),
              color: Color(category.color),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),

          // Category name
          SizedBox(
            width: 100,
            child: Text(
              category.label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),

          // Priority bar
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2a2a30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: priority / 100,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(category.color).withValues(alpha: 0.5),
                          Color(category.color),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Priority value
          SizedBox(
            width: 40,
            child: Text(
              '$priority',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _getPriorityColor(priority),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OVERRIDES TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOverridesTab() {
    final active = _service.activePreset;
    final overrides = active?.stageOverrides ?? {};

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSectionHeader('Stage-Specific Overrides', Icons.edit_note),
        const SizedBox(height: 8),

        if (overrides.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2a2a30)),
            ),
            child: const Center(
              child: Text(
                'No stage overrides defined.\nOverrides allow fine-tuning priority for specific stages.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2a2a30)),
            ),
            child: Column(
              children: overrides.entries.map((entry) {
                return _buildOverrideRow(entry.key, entry.value);
              }).toList(),
            ),
          ),

        const SizedBox(height: 16),

        // Quick reference
        _buildSectionHeader('Priority Levels Reference', Icons.info_outline),
        const SizedBox(height: 8),
        _buildPriorityLegend(),
      ],
    );
  }

  Widget _buildOverrideRow(String stageName, int priority) {
    final stage = _service.getStage(stageName);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF2a2a30)),
        ),
      ),
      child: Row(
        children: [
          // Stage category indicator
          if (stage != null)
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: Color(stage.category.color),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          const SizedBox(width: 12),

          // Stage name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stageName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                if (stage != null)
                  Text(
                    stage.category.label,
                    style: TextStyle(
                      color: Color(stage.category.color),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),

          // Priority badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getPriorityColor(priority).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$priority',
              style: TextStyle(
                color: _getPriorityColor(priority),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2a2a30)),
      ),
      child: const Column(
        children: [
          _PriorityLevelRow(label: 'Highest', range: '80-100', color: Color(0xFFFF4040), desc: 'Jackpots, Epic Wins'),
          _PriorityLevelRow(label: 'High', range: '60-79', color: Color(0xFFFF9040), desc: 'Big Wins, Feature Triggers'),
          _PriorityLevelRow(label: 'Medium', range: '40-59', color: Color(0xFFFFFF40), desc: 'Standard Events, Cascade'),
          _PriorityLevelRow(label: 'Low', range: '20-39', color: Color(0xFF40FF90), desc: 'UI, Symbol Lands'),
          _PriorityLevelRow(label: 'Lowest', range: '0-19', color: Color(0xFF40C8FF), desc: 'Music, Ambient'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  IconData _getStyleIcon(PriorityProfileStyle style) {
    return switch (style) {
      PriorityProfileStyle.balanced => Icons.balance,
      PriorityProfileStyle.aggressive => Icons.bolt,
      PriorityProfileStyle.conservative => Icons.shield,
      PriorityProfileStyle.cinematic => Icons.movie,
      PriorityProfileStyle.arcade => Icons.sports_esports,
      PriorityProfileStyle.custom => Icons.tune,
    };
  }

  IconData _getCategoryIcon(StageCategory category) {
    return switch (category) {
      StageCategory.spin => Icons.casino,
      StageCategory.win => Icons.emoji_events,
      StageCategory.feature => Icons.star,
      StageCategory.cascade => Icons.waterfall_chart,
      StageCategory.jackpot => Icons.diamond,
      StageCategory.hold => Icons.lock,
      StageCategory.gamble => Icons.question_mark,
      StageCategory.ui => Icons.touch_app,
      StageCategory.music => Icons.music_note,
      StageCategory.symbol => Icons.widgets,
      StageCategory.custom => Icons.tune,
    };
  }

  Color _getPriorityColor(int priority) {
    if (priority >= 80) return const Color(0xFFFF4040);
    if (priority >= 60) return const Color(0xFFFF9040);
    if (priority >= 40) return const Color(0xFFFFFF40);
    if (priority >= 20) return const Color(0xFF40FF90);
    return const Color(0xFF40C8FF);
  }

  int _getDefaultCategoryPriority(StageCategory category) {
    return switch (category) {
      StageCategory.jackpot => 95,
      StageCategory.feature => 70,
      StageCategory.hold => 65,
      StageCategory.win => 60,
      StageCategory.cascade => 55,
      StageCategory.gamble => 55,
      StageCategory.spin => 50,
      StageCategory.symbol => 40,
      StageCategory.ui => 25,
      StageCategory.music => 15,
      StageCategory.custom => 50,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _startCreatePreset() {
    setState(() {
      _isEditing = true;
      _editingPresetId = null;
      _editPresetName = '';
      _editPresetDescription = '';
      _editPresetStyle = PriorityProfileStyle.custom;
      _editCategoryPriorities = {};
      _editStageOverrides = {};
    });
  }

  void _startEditPreset(PriorityTierPreset preset) {
    setState(() {
      _isEditing = true;
      _editingPresetId = preset.id;
      _editPresetName = preset.name;
      _editPresetDescription = preset.description;
      _editPresetStyle = preset.style;
      _editCategoryPriorities = Map.from(preset.categoryPriorities);
      _editStageOverrides = Map.from(preset.stageOverrides);
    });
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _editingPresetId = null;
    });
  }

  void _savePreset() {
    if (_editPresetName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    final preset = PriorityTierPreset(
      id: _editingPresetId ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: _editPresetName.trim(),
      description: _editPresetDescription.trim(),
      style: _editPresetStyle,
      isBuiltIn: false,
      createdAt: DateTime.now(),
      categoryPriorities: _editCategoryPriorities,
      stageOverrides: _editStageOverrides,
    );

    _service.savePreset(preset);
    _cancelEdit();
  }

  void _confirmDeletePreset(PriorityTierPreset preset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: const Text('Delete Preset', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${preset.name}"? This cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _service.deletePreset(preset.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRIORITY LEVEL ROW WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _PriorityLevelRow extends StatelessWidget {
  final String label;
  final String range;
  final Color color;
  final String desc;

  const _PriorityLevelRow({
    required this.label,
    required this.range,
    required this.color,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              range,
              style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════

class _PriorityPreviewPainter extends CustomPainter {
  final Map<StageCategory, int> categoryPriorities;

  _PriorityPreviewPainter({required this.categoryPriorities});

  @override
  void paint(Canvas canvas, Size size) {
    final categories = [
      StageCategory.jackpot,
      StageCategory.win,
      StageCategory.feature,
      StageCategory.spin,
      StageCategory.ui,
    ];

    final barWidth = size.width / categories.length - 2;
    var x = 1.0;

    for (final category in categories) {
      final priority = categoryPriorities[category] ?? 50;
      final height = (priority / 100) * size.height;

      final paint = Paint()
        ..color = Color(category.color).withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - height, barWidth, height),
          const Radius.circular(2),
        ),
        paint,
      );

      x += barWidth + 2;
    }
  }

  @override
  bool shouldRepaint(covariant _PriorityPreviewPainter oldDelegate) {
    return categoryPriorities != oldDelegate.categoryPriorities;
  }
}

class _CategoryDistributionPainter extends CustomPainter {
  final PriorityTierPreset? preset;

  _CategoryDistributionPainter({this.preset});

  @override
  void paint(Canvas canvas, Size size) {
    final categories = StageCategory.values.where((c) => c != StageCategory.custom).toList();
    final padding = 40.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    final barWidth = chartWidth / categories.length - 8;

    // Background grid
    final gridPaint = Paint()
      ..color = const Color(0xFF2a2a30)
      ..strokeWidth = 1;

    for (var i = 0; i <= 10; i++) {
      final y = padding + chartHeight - (i / 10) * chartHeight;
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );

      // Labels
      if (i % 2 == 0) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${i * 10}',
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(padding - 24, y - 6));
      }
    }

    // Bars
    var x = padding + 4.0;
    for (final category in categories) {
      final priority = preset?.getCategoryPriority(category) ?? _getDefaultPriority(category);
      final height = (priority / 100) * chartHeight;

      // Bar
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(category.color).withValues(alpha: 0.4),
            Color(category.color),
          ],
        ).createShader(Rect.fromLTWH(x, padding + chartHeight - height, barWidth, height));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, padding + chartHeight - height, barWidth, height),
          const Radius.circular(4),
        ),
        paint,
      );

      // Label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: category.label.substring(0, math.min(4, category.label.length)),
          style: TextStyle(color: Color(category.color), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      labelPainter.paint(
        canvas,
        Offset(x + (barWidth - labelPainter.width) / 2, size.height - padding + 4),
      );

      // Value on top
      final valuePainter = TextPainter(
        text: TextSpan(
          text: '$priority',
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      valuePainter.paint(
        canvas,
        Offset(x + (barWidth - valuePainter.width) / 2, padding + chartHeight - height - 14),
      );

      x += barWidth + 8;
    }
  }

  int _getDefaultPriority(StageCategory category) {
    return switch (category) {
      StageCategory.jackpot => 95,
      StageCategory.feature => 70,
      StageCategory.hold => 65,
      StageCategory.win => 60,
      StageCategory.cascade => 55,
      StageCategory.gamble => 55,
      StageCategory.spin => 50,
      StageCategory.symbol => 40,
      StageCategory.ui => 25,
      StageCategory.music => 15,
      StageCategory.custom => 50,
    };
  }

  @override
  bool shouldRepaint(covariant _CategoryDistributionPainter oldDelegate) {
    return preset != oldDelegate.preset;
  }
}
