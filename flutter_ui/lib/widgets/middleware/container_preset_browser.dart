/// FluxForge Studio Container Preset Browser
///
/// P2-MW-1: Browse and drag container presets to events
/// - Category filtering (Blend/Random/Sequence)
/// - Search functionality
/// - Drag to event for quick assignment
/// - Preview before apply
library;

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PRESET ENTRY MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Container preset entry for browsing
class ContainerPresetEntry {
  final String id;
  final String name;
  final String category;
  final ContainerPresetType type;
  final String description;
  final Map<String, dynamic> previewData;
  final bool isFactory;

  const ContainerPresetEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.type,
    required this.description,
    required this.previewData,
    this.isFactory = true,
  });

  Color get typeColor {
    switch (type) {
      case ContainerPresetType.blend:
        return Colors.purple;
      case ContainerPresetType.random:
        return Colors.orange;
      case ContainerPresetType.sequence:
        return Colors.teal;
    }
  }

  IconData get typeIcon {
    switch (type) {
      case ContainerPresetType.blend:
        return Icons.blur_linear;
      case ContainerPresetType.random:
        return Icons.shuffle;
      case ContainerPresetType.sequence:
        return Icons.timeline;
    }
  }
}

enum ContainerPresetType { blend, random, sequence }

// ═══════════════════════════════════════════════════════════════════════════════
// FACTORY PRESETS
// ═══════════════════════════════════════════════════════════════════════════════

const List<ContainerPresetEntry> _factoryPresets = [
  // Blend presets
  ContainerPresetEntry(
    id: 'blend_win_layers',
    name: 'Win Intensity Layers',
    category: 'Wins',
    type: ContainerPresetType.blend,
    description: 'Crossfade between win tiers based on win amount',
    previewData: {'children': 4, 'rtpcId': 'WinAmount'},
  ),
  ContainerPresetEntry(
    id: 'blend_music_tension',
    name: 'Music Tension',
    category: 'Music',
    type: ContainerPresetType.blend,
    description: 'Tension-based music layering',
    previewData: {'children': 3, 'rtpcId': 'Tension'},
  ),
  ContainerPresetEntry(
    id: 'blend_distance',
    name: 'Distance Blend',
    category: 'Spatial',
    type: ContainerPresetType.blend,
    description: 'Near/far audio crossfade',
    previewData: {'children': 2, 'rtpcId': 'Distance'},
  ),

  // Random presets
  ContainerPresetEntry(
    id: 'random_reel_stop',
    name: 'Reel Stop Variations',
    category: 'Reels',
    type: ContainerPresetType.random,
    description: 'Weighted reel stop sounds',
    previewData: {'children': 4, 'mode': 'Shuffle'},
  ),
  ContainerPresetEntry(
    id: 'random_coin_drop',
    name: 'Coin Drop',
    category: 'Wins',
    type: ContainerPresetType.random,
    description: 'Random coin drop variations',
    previewData: {'children': 5, 'mode': 'Random'},
  ),
  ContainerPresetEntry(
    id: 'random_ui_click',
    name: 'UI Click',
    category: 'UI',
    type: ContainerPresetType.random,
    description: 'Subtle UI click variations',
    previewData: {'children': 3, 'mode': 'RoundRobin'},
  ),

  // Sequence presets
  ContainerPresetEntry(
    id: 'sequence_cascade',
    name: 'Cascade Steps',
    category: 'Cascades',
    type: ContainerPresetType.sequence,
    description: 'Timed cascade collapse sequence',
    previewData: {'steps': 5, 'totalMs': 500},
  ),
  ContainerPresetEntry(
    id: 'sequence_rollup',
    name: 'Win Rollup',
    category: 'Wins',
    type: ContainerPresetType.sequence,
    description: 'Accelerating rollup ticks',
    previewData: {'steps': 4, 'totalMs': 200},
  ),
  ContainerPresetEntry(
    id: 'sequence_anticipation',
    name: 'Anticipation Build',
    category: 'Features',
    type: ContainerPresetType.sequence,
    description: 'Building anticipation sequence',
    previewData: {'steps': 4, 'totalMs': 1100},
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact preset browser for container presets
/// Supports drag to event and quick filtering
class ContainerPresetBrowser extends StatefulWidget {
  final Function(ContainerPresetEntry preset)? onPresetSelected;
  final bool compactMode;

  const ContainerPresetBrowser({
    super.key,
    this.onPresetSelected,
    this.compactMode = false,
  });

  @override
  State<ContainerPresetBrowser> createState() => _ContainerPresetBrowserState();
}

class _ContainerPresetBrowserState extends State<ContainerPresetBrowser> {
  String _searchQuery = '';
  ContainerPresetType? _selectedType;
  String? _selectedCategory;
  ContainerPresetEntry? _hoveredPreset;

  List<ContainerPresetEntry> get _filteredPresets {
    return _factoryPresets.where((p) {
      // Type filter
      if (_selectedType != null && p.type != _selectedType) return false;
      // Category filter
      if (_selectedCategory != null && p.category != _selectedCategory) {
        return false;
      }
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return p.name.toLowerCase().contains(query) ||
            p.category.toLowerCase().contains(query) ||
            p.description.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  Set<String> get _allCategories {
    return _factoryPresets.map((p) => p.category).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildTypeFilter(),
          _buildSearchBar(),
          Expanded(child: _buildPresetGrid()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.dashboard_customize, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Text(
            'Container Presets',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          _buildCategoryDropdown(),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedCategory,
          hint: Text(
            'All Categories',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
          icon: Icon(Icons.arrow_drop_down,
              size: 16, color: FluxForgeTheme.textSecondary),
          isDense: true,
          dropdownColor: FluxForgeTheme.surfaceDark,
          style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
          items: [
            const DropdownMenuItem(value: null, child: Text('All Categories')),
            ..._allCategories.map(
              (c) => DropdownMenuItem(value: c, child: Text(c)),
            ),
          ],
          onChanged: (v) => setState(() => _selectedCategory = v),
        ),
      ),
    );
  }

  Widget _buildTypeFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _buildTypeChip(null, 'All', Icons.apps),
          const SizedBox(width: 6),
          _buildTypeChip(
              ContainerPresetType.blend, 'Blend', Icons.blur_linear),
          const SizedBox(width: 6),
          _buildTypeChip(
              ContainerPresetType.random, 'Random', Icons.shuffle),
          const SizedBox(width: 6),
          _buildTypeChip(
              ContainerPresetType.sequence, 'Sequence', Icons.timeline),
        ],
      ),
    );
  }

  Widget _buildTypeChip(ContainerPresetType? type, String label, IconData icon) {
    final isSelected = _selectedType == type;
    final color = type == null
        ? Colors.grey
        : type == ContainerPresetType.blend
            ? Colors.purple
            : type == ContainerPresetType.random
                ? Colors.orange
                : Colors.teal;

    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? color : FluxForgeTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isSelected ? color : FluxForgeTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 14, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search presets...',
                  hintStyle: TextStyle(
                      color: FluxForgeTheme.textSecondary, fontSize: 12),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _searchQuery = ''),
                child: Icon(Icons.clear,
                    size: 12, color: FluxForgeTheme.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetGrid() {
    final presets = _filteredPresets;

    if (presets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 32, color: FluxForgeTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              'No presets found',
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: presets.length,
        itemBuilder: (context, index) => _buildPresetCard(presets[index]),
      ),
    );
  }

  Widget _buildPresetCard(ContainerPresetEntry preset) {
    final isHovered = _hoveredPreset?.id == preset.id;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredPreset = preset),
      onExit: (_) => setState(() => _hoveredPreset = null),
      child: Draggable<ContainerPresetEntry>(
        data: preset,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: preset.typeColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(preset.typeIcon, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  preset.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.5,
          child: _buildCardContent(preset, false),
        ),
        child: GestureDetector(
          onTap: () => widget.onPresetSelected?.call(preset),
          child: _buildCardContent(preset, isHovered),
        ),
      ),
    );
  }

  Widget _buildCardContent(ContainerPresetEntry preset, bool isHovered) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHovered
            ? preset.typeColor.withValues(alpha: 0.15)
            : FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHovered ? preset.typeColor : FluxForgeTheme.border,
          width: isHovered ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(preset.typeIcon, size: 14, color: preset.typeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  preset.name,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            preset.description,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: preset.typeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  preset.type.name.toUpperCase(),
                  style: TextStyle(
                    color: preset.typeColor,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.backgroundDeep,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  preset.category,
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DROP TARGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Drop target for receiving container preset drops
class ContainerPresetDropTarget extends StatelessWidget {
  final Widget child;
  final Function(ContainerPresetEntry preset) onPresetDropped;

  const ContainerPresetDropTarget({
    super.key,
    required this.child,
    required this.onPresetDropped,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<ContainerPresetEntry>(
      onAcceptWithDetails: (details) => onPresetDropped(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: isHovering
                ? Border.all(color: Colors.amber, width: 2)
                : null,
          ),
          child: child,
        );
      },
    );
  }
}
