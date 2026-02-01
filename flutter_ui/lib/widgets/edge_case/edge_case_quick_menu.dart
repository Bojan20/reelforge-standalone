/// Edge Case Quick Menu
///
/// Dropdown menu for quick selection of edge case presets.
/// Provides access to built-in and custom presets with recent history.
///
/// Created: 2026-01-30 (P4.14)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/edge_case_models.dart';
import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../services/edge_case_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Quick menu button for edge case presets
class EdgeCaseQuickMenu extends StatefulWidget {
  final VoidCallback? onPresetApplied;

  const EdgeCaseQuickMenu({
    super.key,
    this.onPresetApplied,
  });

  @override
  State<EdgeCaseQuickMenu> createState() => _EdgeCaseQuickMenuState();
}

class _EdgeCaseQuickMenuState extends State<EdgeCaseQuickMenu> {
  final _service = EdgeCaseService.instance;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _service.init();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return PopupMenuButton<EdgeCasePreset>(
      icon: Icon(
        Icons.science,
        size: 18,
        color: _service.activePreset != null
            ? const Color(0xFF40FF90)
            : Colors.white70,
      ),
      tooltip: 'Edge Case Presets',
      onSelected: _applyPreset,
      itemBuilder: (context) => _buildMenuItems(),
    );
  }

  List<PopupMenuEntry<EdgeCasePreset>> _buildMenuItems() {
    final items = <PopupMenuEntry<EdgeCasePreset>>[];

    // Recent presets section
    final recent = _service.recentPresets;
    if (recent.isNotEmpty) {
      items.add(const PopupMenuItem<EdgeCasePreset>(
        enabled: false,
        height: 28,
        child: Text(
          'RECENT',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white38,
            letterSpacing: 1.2,
          ),
        ),
      ));
      for (final preset in recent.take(3)) {
        items.add(_buildPresetItem(preset, showCategory: true));
      }
      items.add(const PopupMenuDivider());
    }

    // Categories
    for (final category in EdgeCaseCategory.values.where((c) => c != EdgeCaseCategory.custom)) {
      final presets = _service.getPresetsByCategory(category);
      if (presets.isEmpty) continue;

      items.add(PopupMenuItem<EdgeCasePreset>(
        enabled: false,
        height: 28,
        child: Text(
          category.label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white38,
            letterSpacing: 1.2,
          ),
        ),
      ));

      for (final preset in presets.take(4)) {
        items.add(_buildPresetItem(preset));
      }

      items.add(const PopupMenuDivider());
    }

    // Clear active preset
    if (_service.activePreset != null) {
      items.add(PopupMenuItem<EdgeCasePreset>(
        value: null,
        child: const Row(
          children: [
            Icon(Icons.clear, size: 16, color: Color(0xFFFF4060)),
            SizedBox(width: 8),
            Text('Clear Active Preset', style: TextStyle(color: Color(0xFFFF4060))),
          ],
        ),
      ));
    }

    return items;
  }

  PopupMenuItem<EdgeCasePreset> _buildPresetItem(EdgeCasePreset preset, {bool showCategory = false}) {
    final isActive = _service.activePreset?.id == preset.id;

    return PopupMenuItem<EdgeCasePreset>(
      value: preset,
      child: Row(
        children: [
          Icon(
            _getCategoryIcon(preset.category),
            size: 16,
            color: isActive ? const Color(0xFF40FF90) : _getCategoryColor(preset.category),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preset.name,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? const Color(0xFF40FF90) : null,
                  ),
                ),
                if (showCategory)
                  Text(
                    preset.category.label,
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
              ],
            ),
          ),
          if (isActive)
            const Icon(Icons.check, size: 14, color: Color(0xFF40FF90)),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(EdgeCaseCategory category) {
    return switch (category) {
      EdgeCaseCategory.betting => Icons.monetization_on,
      EdgeCaseCategory.balance => Icons.account_balance_wallet,
      EdgeCaseCategory.feature => Icons.star,
      EdgeCaseCategory.stress => Icons.speed,
      EdgeCaseCategory.audio => Icons.volume_up,
      EdgeCaseCategory.visual => Icons.visibility,
      EdgeCaseCategory.custom => Icons.edit,
    };
  }

  Color _getCategoryColor(EdgeCaseCategory category) {
    return switch (category) {
      EdgeCaseCategory.betting => const Color(0xFFFFD700),
      EdgeCaseCategory.balance => const Color(0xFF40C8FF),
      EdgeCaseCategory.feature => const Color(0xFF9370DB),
      EdgeCaseCategory.stress => const Color(0xFFFF6B6B),
      EdgeCaseCategory.audio => const Color(0xFF40FF90),
      EdgeCaseCategory.visual => const Color(0xFFFF9040),
      EdgeCaseCategory.custom => Colors.white54,
    };
  }

  Future<void> _applyPreset(EdgeCasePreset? preset) async {
    if (preset == null) {
      _service.clearActivePreset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preset cleared')),
        );
      }
      return;
    }

    final slotLabProvider = context.read<SlotLabProvider>();
    final result = await _service.applyPreset(
      preset,
      slotLabProvider: slotLabProvider,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Applied: ${preset.name}'
                : 'Failed: ${result.error}',
          ),
          backgroundColor: result.success
              ? const Color(0xFF40FF90).withAlpha(200)
              : const Color(0xFFFF4060).withAlpha(200),
        ),
      );
    }

    widget.onPresetApplied?.call();
  }
}

/// Compact badge showing active edge case preset
class EdgeCaseActiveBadge extends StatelessWidget {
  const EdgeCaseActiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EdgeCaseService.instance,
      builder: (context, _) {
        final preset = EdgeCaseService.instance.activePreset;
        if (preset == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF40FF90).withAlpha(50),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF40FF90).withAlpha(100)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.science, size: 12, color: Color(0xFF40FF90)),
              const SizedBox(width: 4),
              Text(
                preset.name,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF40FF90),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => EdgeCaseService.instance.clearActivePreset(),
                child: const Icon(Icons.close, size: 12, color: Color(0xFF40FF90)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Full panel for browsing and managing edge case presets
class EdgeCasePresetsPanel extends StatefulWidget {
  final double height;

  const EdgeCasePresetsPanel({
    super.key,
    this.height = 400,
  });

  @override
  State<EdgeCasePresetsPanel> createState() => _EdgeCasePresetsPanelState();
}

class _EdgeCasePresetsPanelState extends State<EdgeCasePresetsPanel> {
  final _service = EdgeCaseService.instance;
  EdgeCaseCategory? _selectedCategory;
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _service.init();
    _service.addListener(_onServiceChanged);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border.all(color: FluxForgeTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              children: [
                _buildCategorySidebar(),
                Expanded(child: _buildPresetList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science, size: 16, color: Color(0xFF9370DB)),
          const SizedBox(width: 8),
          const Text(
            'EDGE CASE PRESETS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_service.activePreset != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF40FF90).withAlpha(50),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Active: ${_service.activePreset!.name}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF40FF90),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 150,
            height: 28,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: const TextStyle(fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 14),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySidebar() {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _buildCategoryItem(null, 'All', Icons.list),
          const Divider(),
          for (final category in EdgeCaseCategory.values)
            _buildCategoryItem(
              category,
              category.label,
              _getCategoryIcon(category),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(EdgeCaseCategory? category, String label, IconData icon) {
    final isSelected = _selectedCategory == category;
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: const Color(0xFF4A9EFF).withAlpha(50),
      leading: Icon(icon, size: 16),
      title: Text(label, style: const TextStyle(fontSize: 11)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
      onTap: () => setState(() => _selectedCategory = category),
    );
  }

  IconData _getCategoryIcon(EdgeCaseCategory category) {
    return switch (category) {
      EdgeCaseCategory.betting => Icons.monetization_on,
      EdgeCaseCategory.balance => Icons.account_balance_wallet,
      EdgeCaseCategory.feature => Icons.star,
      EdgeCaseCategory.stress => Icons.speed,
      EdgeCaseCategory.audio => Icons.volume_up,
      EdgeCaseCategory.visual => Icons.visibility,
      EdgeCaseCategory.custom => Icons.edit,
    };
  }

  Widget _buildPresetList() {
    var presets = _selectedCategory == null
        ? _service.allPresets
        : _service.getPresetsByCategory(_selectedCategory!);

    if (_searchQuery.isNotEmpty) {
      presets = _service.searchPresets(_searchQuery);
      if (_selectedCategory != null) {
        presets = presets.where((p) => p.category == _selectedCategory).toList();
      }
    }

    if (presets.isEmpty) {
      return const Center(
        child: Text('No presets found', style: TextStyle(color: Colors.white38)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final preset = presets[index];
        final isActive = _service.activePreset?.id == preset.id;

        return Card(
          color: isActive
              ? const Color(0xFF40FF90).withAlpha(30)
              : FluxForgeTheme.bgMid,
          child: ListTile(
            dense: true,
            leading: Icon(
              _getCategoryIcon(preset.category),
              color: isActive ? const Color(0xFF40FF90) : null,
            ),
            title: Text(
              preset.name,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? const Color(0xFF40FF90) : null,
              ),
            ),
            subtitle: Text(
              preset.description,
              style: const TextStyle(fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  const Icon(Icons.check, size: 16, color: Color(0xFF40FF90)),
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  onPressed: () => _applyPreset(preset),
                  tooltip: 'Apply',
                ),
              ],
            ),
            onTap: () => _applyPreset(preset),
          ),
        );
      },
    );
  }

  Future<void> _applyPreset(EdgeCasePreset preset) async {
    final slotLabProvider = context.read<SlotLabProvider>();
    final result = await _service.applyPreset(
      preset,
      slotLabProvider: slotLabProvider,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Applied: ${preset.name}'
                : 'Failed: ${result.error}',
          ),
        ),
      );
    }
  }
}
