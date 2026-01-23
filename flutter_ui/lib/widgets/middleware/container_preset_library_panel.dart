/// FluxForge Studio Container Preset Library Panel
///
/// P4.1: Container preset library UI
/// - Factory presets by category
/// - User presets with search
/// - Preview before apply
/// - Save/Load/Delete functionality
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../services/container_preset_service.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PRESET CATEGORIES
// ═══════════════════════════════════════════════════════════════════════════════

enum PresetCategory {
  all('All', Icons.folder),
  blend('Blend', Icons.blur_linear),
  random('Random', Icons.shuffle),
  sequence('Sequence', Icons.timeline),
  factory('Factory', Icons.inventory_2),
  user('User', Icons.person);

  final String label;
  final IconData icon;
  const PresetCategory(this.label, this.icon);
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACTORY PRESETS
// ═══════════════════════════════════════════════════════════════════════════════

class FactoryPreset {
  final String id;
  final String name;
  final String category;
  final String type; // blend, random, sequence
  final String description;
  final Map<String, dynamic> data;

  const FactoryPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.type,
    required this.description,
    required this.data,
  });
}

/// Factory preset definitions
const List<FactoryPreset> _factoryPresets = [
  // Blend presets
  FactoryPreset(
    id: 'blend_win_intensity',
    name: 'Win Intensity Crossfade',
    category: 'Wins',
    type: 'blend',
    description: 'Crossfade between win layers based on win amount',
    data: {
      'rtpcId': 1,
      'crossfadeCurve': 1, // equalPower
      'children': [
        {'name': 'Small Win', 'rtpcStart': 0.0, 'rtpcEnd': 0.3, 'crossfadeWidth': 0.1},
        {'name': 'Medium Win', 'rtpcStart': 0.25, 'rtpcEnd': 0.6, 'crossfadeWidth': 0.15},
        {'name': 'Big Win', 'rtpcStart': 0.55, 'rtpcEnd': 0.85, 'crossfadeWidth': 0.15},
        {'name': 'Mega Win', 'rtpcStart': 0.8, 'rtpcEnd': 1.0, 'crossfadeWidth': 0.1},
      ],
    },
  ),
  FactoryPreset(
    id: 'blend_tension_layers',
    name: 'Tension Builder',
    category: 'Music',
    type: 'blend',
    description: 'Layered tension music with intensity control',
    data: {
      'rtpcId': 2,
      'crossfadeCurve': 2, // sCurve
      'children': [
        {'name': 'Calm', 'rtpcStart': 0.0, 'rtpcEnd': 0.4, 'crossfadeWidth': 0.2},
        {'name': 'Building', 'rtpcStart': 0.3, 'rtpcEnd': 0.7, 'crossfadeWidth': 0.2},
        {'name': 'Intense', 'rtpcStart': 0.6, 'rtpcEnd': 1.0, 'crossfadeWidth': 0.2},
      ],
    },
  ),
  FactoryPreset(
    id: 'blend_distance',
    name: 'Distance Attenuation',
    category: 'Spatial',
    type: 'blend',
    description: 'Near/far audio blend for spatial positioning',
    data: {
      'rtpcId': 3,
      'crossfadeCurve': 0, // linear
      'children': [
        {'name': 'Close', 'rtpcStart': 0.0, 'rtpcEnd': 0.5, 'crossfadeWidth': 0.25},
        {'name': 'Far', 'rtpcStart': 0.4, 'rtpcEnd': 1.0, 'crossfadeWidth': 0.25},
      ],
    },
  ),

  // Random presets
  FactoryPreset(
    id: 'random_footsteps',
    name: 'Footsteps Variation',
    category: 'SFX',
    type: 'random',
    description: 'Random footstep variations with pitch/volume variance',
    data: {
      'mode': 0, // random
      'globalPitchMin': -0.1,
      'globalPitchMax': 0.1,
      'globalVolumeMin': 0.9,
      'globalVolumeMax': 1.0,
      'children': [
        {'name': 'Step 1', 'weight': 1.0},
        {'name': 'Step 2', 'weight': 1.0},
        {'name': 'Step 3', 'weight': 1.0},
        {'name': 'Step 4', 'weight': 1.0},
      ],
    },
  ),
  FactoryPreset(
    id: 'random_reel_stop',
    name: 'Reel Stop Variations',
    category: 'Reels',
    type: 'random',
    description: 'Weighted reel stop sounds with shuffle mode',
    data: {
      'mode': 1, // shuffle
      'globalPitchMin': -0.05,
      'globalPitchMax': 0.05,
      'globalVolumeMin': 0.95,
      'globalVolumeMax': 1.0,
      'children': [
        {'name': 'Stop Soft', 'weight': 2.0},
        {'name': 'Stop Medium', 'weight': 1.5},
        {'name': 'Stop Hard', 'weight': 1.0},
      ],
    },
  ),
  FactoryPreset(
    id: 'random_coin_drops',
    name: 'Coin Drop Variations',
    category: 'Wins',
    type: 'random',
    description: 'Coin drop sound variations for win animations',
    data: {
      'mode': 0, // random
      'globalPitchMin': -0.15,
      'globalPitchMax': 0.15,
      'globalVolumeMin': 0.8,
      'globalVolumeMax': 1.0,
      'children': [
        {'name': 'Coin 1', 'weight': 1.0, 'pitchMin': 0.0, 'pitchMax': 0.1},
        {'name': 'Coin 2', 'weight': 1.0, 'pitchMin': -0.05, 'pitchMax': 0.05},
        {'name': 'Coin 3', 'weight': 1.0, 'pitchMin': -0.1, 'pitchMax': 0.0},
      ],
    },
  ),
  FactoryPreset(
    id: 'random_ui_click',
    name: 'UI Click Variations',
    category: 'UI',
    type: 'random',
    description: 'Subtle UI click variations',
    data: {
      'mode': 2, // roundRobin
      'globalPitchMin': -0.02,
      'globalPitchMax': 0.02,
      'globalVolumeMin': 0.95,
      'globalVolumeMax': 1.0,
      'children': [
        {'name': 'Click A', 'weight': 1.0},
        {'name': 'Click B', 'weight': 1.0},
      ],
    },
  ),

  // Sequence presets
  FactoryPreset(
    id: 'sequence_cascade',
    name: 'Cascade Steps',
    category: 'Cascades',
    type: 'sequence',
    description: 'Timed cascade collapse sequence',
    data: {
      'endBehavior': 0, // stop
      'speed': 1.0,
      'steps': [
        {'childName': 'Pop 1', 'delayMs': 0, 'durationMs': 100, 'volume': 1.0},
        {'childName': 'Pop 2', 'delayMs': 80, 'durationMs': 100, 'volume': 0.95},
        {'childName': 'Pop 3', 'delayMs': 160, 'durationMs': 100, 'volume': 0.9},
        {'childName': 'Pop 4', 'delayMs': 240, 'durationMs': 100, 'volume': 0.85},
        {'childName': 'Impact', 'delayMs': 350, 'durationMs': 200, 'volume': 1.0},
      ],
    },
  ),
  FactoryPreset(
    id: 'sequence_rollup',
    name: 'Win Rollup',
    category: 'Wins',
    type: 'sequence',
    description: 'Win amount rollup with accelerating ticks',
    data: {
      'endBehavior': 1, // loop
      'speed': 1.0,
      'steps': [
        {'childName': 'Tick', 'delayMs': 0, 'durationMs': 50, 'volume': 0.7},
        {'childName': 'Tick', 'delayMs': 50, 'durationMs': 50, 'volume': 0.75},
        {'childName': 'Tick', 'delayMs': 100, 'durationMs': 50, 'volume': 0.8},
        {'childName': 'Tick', 'delayMs': 150, 'durationMs': 50, 'volume': 0.85},
      ],
    },
  ),
  FactoryPreset(
    id: 'sequence_anticipation',
    name: 'Anticipation Build',
    category: 'Features',
    type: 'sequence',
    description: 'Building anticipation sequence before feature',
    data: {
      'endBehavior': 0, // stop
      'speed': 1.0,
      'steps': [
        {'childName': 'Riser Start', 'delayMs': 0, 'durationMs': 500, 'fadeInMs': 100, 'volume': 0.6},
        {'childName': 'Riser Mid', 'delayMs': 400, 'durationMs': 500, 'fadeInMs': 50, 'volume': 0.8},
        {'childName': 'Riser Peak', 'delayMs': 800, 'durationMs': 300, 'fadeInMs': 50, 'volume': 1.0},
        {'childName': 'Impact', 'delayMs': 1000, 'durationMs': 500, 'volume': 1.0},
      ],
    },
  ),
  FactoryPreset(
    id: 'sequence_bonus_intro',
    name: 'Bonus Intro',
    category: 'Features',
    type: 'sequence',
    description: 'Bonus mode entrance fanfare',
    data: {
      'endBehavior': 0, // stop
      'speed': 1.0,
      'steps': [
        {'childName': 'Whoosh', 'delayMs': 0, 'durationMs': 300, 'volume': 0.9},
        {'childName': 'Fanfare', 'delayMs': 200, 'durationMs': 2000, 'fadeInMs': 100, 'volume': 1.0},
        {'childName': 'Sparkle', 'delayMs': 500, 'durationMs': 1000, 'volume': 0.7},
      ],
    },
  ),
];

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class ContainerPresetLibraryPanel extends StatefulWidget {
  final int? targetContainerId;
  final String? targetContainerType; // blend, random, sequence
  final VoidCallback? onClose;

  const ContainerPresetLibraryPanel({
    super.key,
    this.targetContainerId,
    this.targetContainerType,
    this.onClose,
  });

  @override
  State<ContainerPresetLibraryPanel> createState() => _ContainerPresetLibraryPanelState();
}

class _ContainerPresetLibraryPanelState extends State<ContainerPresetLibraryPanel> {
  PresetCategory _selectedCategory = PresetCategory.all;
  String _searchQuery = '';
  FactoryPreset? _selectedFactoryPreset;
  ContainerPreset? _selectedUserPreset;
  List<ContainerPreset> _userPresets = [];
  bool _isLoadingUserPresets = false;
  String? _userPresetsDirectory;

  @override
  void initState() {
    super.initState();
    _loadUserPresets();
    // Auto-filter by target type if provided
    if (widget.targetContainerType != null) {
      switch (widget.targetContainerType) {
        case 'blend':
          _selectedCategory = PresetCategory.blend;
          break;
        case 'random':
          _selectedCategory = PresetCategory.random;
          break;
        case 'sequence':
          _selectedCategory = PresetCategory.sequence;
          break;
      }
    }
  }

  Future<void> _loadUserPresets() async {
    setState(() => _isLoadingUserPresets = true);
    try {
      // Load from documents directory
      final homeDir = Platform.environment['HOME'] ?? '';
      final presetsDir = Directory('$homeDir/Documents/FluxForge/Presets/Containers');
      _userPresetsDirectory = presetsDir.path;

      if (await presetsDir.exists()) {
        final files = await presetsDir
            .list()
            .where((f) => f.path.endsWith(kPresetExtension))
            .toList();

        final presets = <ContainerPreset>[];
        for (final file in files) {
          final preset = await ContainerPresetService.instance.importPreset(file.path);
          if (preset != null) {
            presets.add(preset);
          }
        }
        setState(() => _userPresets = presets);
      }
    } catch (e) {
      debugPrint('[PresetLibrary] Error loading user presets: $e');
    } finally {
      setState(() => _isLoadingUserPresets = false);
    }
  }

  List<FactoryPreset> get _filteredFactoryPresets {
    return _factoryPresets.where((p) {
      // Category filter
      if (_selectedCategory == PresetCategory.user) return false;
      if (_selectedCategory != PresetCategory.all &&
          _selectedCategory != PresetCategory.factory) {
        if (p.type != _selectedCategory.name.toLowerCase()) return false;
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

  List<ContainerPreset> get _filteredUserPresets {
    if (_selectedCategory == PresetCategory.factory) return [];
    return _userPresets.where((p) {
      // Category filter
      if (_selectedCategory != PresetCategory.all &&
          _selectedCategory != PresetCategory.user) {
        if (p.type != _selectedCategory.name.toLowerCase()) return false;
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return p.name.toLowerCase().contains(query) ||
            p.type.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildSearchBar(),
          const SizedBox(height: 12),
          _buildCategoryTabs(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preset list
                Expanded(
                  flex: 2,
                  child: _buildPresetList(),
                ),
                const SizedBox(width: 16),
                // Preview panel
                Expanded(
                  flex: 3,
                  child: _buildPreviewPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.library_music, color: Colors.amber, size: 20),
        const SizedBox(width: 8),
        Text(
          'Container Preset Library',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (widget.targetContainerId != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 12, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'Target: ${widget.targetContainerType ?? 'Container'} #${widget.targetContainerId}',
                  style: TextStyle(color: Colors.green, fontSize: 10),
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _importPreset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_download, size: 12, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  'Import',
                  style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        if (widget.onClose != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.close, size: 14, color: FluxForgeTheme.textSecondary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: FluxForgeTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search presets...',
                hintStyle: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _searchQuery = ''),
              child: Icon(Icons.clear, size: 14, color: FluxForgeTheme.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: PresetCategory.values.map((cat) {
          final isActive = _selectedCategory == cat;
          final count = cat == PresetCategory.all
              ? _factoryPresets.length + _userPresets.length
              : cat == PresetCategory.factory
                  ? _factoryPresets.length
                  : cat == PresetCategory.user
                      ? _userPresets.length
                      : _factoryPresets.where((p) => p.type == cat.name.toLowerCase()).length +
                          _userPresets.where((p) => p.type == cat.name.toLowerCase()).length;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedCategory = cat;
                _selectedFactoryPreset = null;
                _selectedUserPreset = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? _getCategoryColor(cat).withValues(alpha: 0.2)
                      : FluxForgeTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive ? _getCategoryColor(cat) : FluxForgeTheme.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cat.icon,
                      size: 14,
                      color: isActive ? _getCategoryColor(cat) : FluxForgeTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat.label,
                      style: TextStyle(
                        color: isActive ? _getCategoryColor(cat) : FluxForgeTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isActive
                            ? _getCategoryColor(cat).withValues(alpha: 0.3)
                            : FluxForgeTheme.backgroundDeep,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: isActive ? _getCategoryColor(cat) : FluxForgeTheme.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getCategoryColor(PresetCategory cat) {
    switch (cat) {
      case PresetCategory.all:
        return Colors.amber;
      case PresetCategory.blend:
        return Colors.purple;
      case PresetCategory.random:
        return Colors.orange;
      case PresetCategory.sequence:
        return Colors.teal;
      case PresetCategory.factory:
        return Colors.blue;
      case PresetCategory.user:
        return Colors.green;
    }
  }

  Widget _buildPresetList() {
    final factoryList = _filteredFactoryPresets;
    final userList = _filteredUserPresets;

    if (factoryList.isEmpty && userList.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Center(
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
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: ListView(
        children: [
          // Factory presets section
          if (factoryList.isNotEmpty) ...[
            _buildSectionHeader('Factory Presets', Icons.inventory_2, Colors.blue),
            ...factoryList.map((preset) => _buildFactoryPresetItem(preset)),
          ],
          // User presets section
          if (userList.isNotEmpty) ...[
            _buildSectionHeader('User Presets', Icons.person, Colors.green),
            ...userList.map((preset) => _buildUserPresetItem(preset)),
          ],
          if (_isLoadingUserPresets)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFactoryPresetItem(FactoryPreset preset) {
    final isSelected = _selectedFactoryPreset?.id == preset.id;
    final typeColor = _getTypeColor(preset.type);

    return GestureDetector(
      onTap: () => setState(() {
        _selectedFactoryPreset = preset;
        _selectedUserPreset = null;
      }),
      onDoubleTap: () => _applyFactoryPreset(preset),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? typeColor.withValues(alpha: 0.1) : Colors.transparent,
          border: Border(
            left: isSelected
                ? BorderSide(color: typeColor, width: 3)
                : BorderSide.none,
            bottom: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.3)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getTypeIcon(preset.type), size: 14, color: typeColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    preset.name,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    preset.type.toUpperCase(),
                    style: TextStyle(color: typeColor, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.backgroundDeep,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    preset.category,
                    style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserPresetItem(ContainerPreset preset) {
    final isSelected = _selectedUserPreset?.name == preset.name;
    final typeColor = _getTypeColor(preset.type);

    return GestureDetector(
      onTap: () => setState(() {
        _selectedUserPreset = preset;
        _selectedFactoryPreset = null;
      }),
      onDoubleTap: () => _applyUserPreset(preset),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? typeColor.withValues(alpha: 0.1) : Colors.transparent,
          border: Border(
            left: isSelected
                ? BorderSide(color: typeColor, width: 3)
                : BorderSide.none,
            bottom: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.3)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getTypeIcon(preset.type), size: 14, color: typeColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    preset.name,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _deleteUserPreset(preset),
                  child: Icon(Icons.delete_outline, size: 14, color: Colors.red.withValues(alpha: 0.7)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    preset.type.toUpperCase(),
                    style: TextStyle(color: typeColor, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDate(preset.createdAt),
                  style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'blend':
        return Colors.purple;
      case 'random':
        return Colors.orange;
      case 'sequence':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'blend':
        return Icons.blur_linear;
      case 'random':
        return Icons.shuffle;
      case 'sequence':
        return Icons.timeline;
      default:
        return Icons.help_outline;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildPreviewPanel() {
    if (_selectedFactoryPreset != null) {
      return _buildFactoryPresetPreview(_selectedFactoryPreset!);
    }
    if (_selectedUserPreset != null) {
      return _buildUserPresetPreview(_selectedUserPreset!);
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 40, color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'Select a preset to preview',
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Double-click to apply',
              style: TextStyle(color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFactoryPresetPreview(FactoryPreset preset) {
    final typeColor = _getTypeColor(preset.type);

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: typeColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Icon(_getTypeIcon(preset.type), size: 20, color: typeColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preset.description,
                        style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildPresetDataPreview(preset.type, preset.data, typeColor),
            ),
          ),
          // Actions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: FluxForgeTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _applyFactoryPreset(preset),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            widget.targetContainerId != null ? 'Apply to Container' : 'Create New Container',
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserPresetPreview(ContainerPreset preset) {
    final typeColor = _getTypeColor(preset.type);

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: typeColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Icon(Icons.person, size: 20, color: Colors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Created: ${_formatDate(preset.createdAt)}',
                        style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    preset.type.toUpperCase(),
                    style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildPresetDataPreview(preset.type, preset.data, typeColor),
            ),
          ),
          // Actions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: FluxForgeTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _applyUserPreset(preset),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            widget.targetContainerId != null ? 'Apply to Container' : 'Create New Container',
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
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _exportUserPreset(preset),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: FluxForgeTheme.border),
                    ),
                    child: Icon(Icons.file_upload, size: 16, color: FluxForgeTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetDataPreview(String type, Map<String, dynamic> data, Color color) {
    switch (type) {
      case 'blend':
        return _buildBlendPreview(data, color);
      case 'random':
        return _buildRandomPreview(data, color);
      case 'sequence':
        return _buildSequencePreview(data, color);
      default:
        return Text('Unknown type', style: TextStyle(color: FluxForgeTheme.textSecondary));
    }
  }

  Widget _buildBlendPreview(Map<String, dynamic> data, Color color) {
    final children = data['children'] as List<dynamic>? ?? [];
    final curves = ['Linear', 'Equal Power', 'S-Curve', 'Sin/Cos'];
    final curveIndex = data['crossfadeCurve'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewRow('RTPC ID', '${data['rtpcId'] ?? 0}'),
        _buildPreviewRow('Curve', curves[curveIndex.clamp(0, curves.length - 1)]),
        const SizedBox(height: 12),
        Text(
          'Children (${children.length})',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children.map((c) {
          final child = c as Map<String, dynamic>;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    child['name'] as String? ?? 'Child',
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                  ),
                ),
                Text(
                  '${((child['rtpcStart'] as num?)?.toStringAsFixed(2) ?? '0')} - ${((child['rtpcEnd'] as num?)?.toStringAsFixed(2) ?? '1')}',
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRandomPreview(Map<String, dynamic> data, Color color) {
    final children = data['children'] as List<dynamic>? ?? [];
    final modes = ['Random', 'Shuffle', 'Round Robin'];
    final modeIndex = data['mode'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewRow('Mode', modes[modeIndex.clamp(0, modes.length - 1)]),
        _buildPreviewRow(
          'Pitch Range',
          '${((data['globalPitchMin'] as num?)?.toStringAsFixed(2) ?? '0')} to ${((data['globalPitchMax'] as num?)?.toStringAsFixed(2) ?? '0')}',
        ),
        _buildPreviewRow(
          'Volume Range',
          '${((data['globalVolumeMin'] as num?)?.toStringAsFixed(2) ?? '1')} to ${((data['globalVolumeMax'] as num?)?.toStringAsFixed(2) ?? '1')}',
        ),
        const SizedBox(height: 12),
        Text(
          'Children (${children.length})',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children.map((c) {
          final child = c as Map<String, dynamic>;
          final weight = (child['weight'] as num?)?.toDouble() ?? 1.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    child['name'] as String? ?? 'Child',
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                  ),
                ),
                Container(
                  width: 50,
                  height: 6,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.backgroundDeep,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (weight / 3.0).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${weight.toStringAsFixed(1)}',
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSequencePreview(Map<String, dynamic> data, Color color) {
    final steps = data['steps'] as List<dynamic>? ?? [];
    final behaviors = ['Stop', 'Loop', 'Ping-Pong', 'Hold'];
    final behaviorIndex = data['endBehavior'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreviewRow('End Behavior', behaviors[behaviorIndex.clamp(0, behaviors.length - 1)]),
        _buildPreviewRow('Speed', '${((data['speed'] as num?)?.toStringAsFixed(1) ?? '1.0')}x'),
        const SizedBox(height: 12),
        Text(
          'Steps (${steps.length})',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...steps.asMap().entries.map((entry) {
          final step = entry.value as Map<String, dynamic>;
          final delay = (step['delayMs'] as num?)?.toInt() ?? 0;
          final duration = (step['durationMs'] as num?)?.toInt() ?? 100;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${entry.key + 1}',
                      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step['childName'] as String? ?? 'Step',
                    style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                  ),
                ),
                Text(
                  '@${delay}ms (${duration}ms)',
                  style: TextStyle(color: color, fontSize: 9),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════════

  void _applyFactoryPreset(FactoryPreset preset) {
    final provider = context.read<MiddlewareProvider>();

    switch (preset.type) {
      case 'blend':
        final container = ContainerPresetService.instance._presetDataToBlend(
          {'name': preset.name, ...preset.data},
          newId: widget.targetContainerId,
        );
        if (widget.targetContainerId != null) {
          provider.updateBlendContainer(container);
        } else {
          provider.addBlendContainer(
            name: container.name,
            rtpcId: container.rtpcId,
          );
          // Add children after creation
          final created = provider.blendContainers.lastOrNull;
          if (created != null) {
            for (final child in container.children) {
              provider.addBlendChild(
                created.id,
                name: child.name,
                rtpcStart: child.rtpcStart,
                rtpcEnd: child.rtpcEnd,
              );
            }
          }
        }
        break;
      case 'random':
        final container = ContainerPresetService.instance._presetDataToRandom(
          {'name': preset.name, ...preset.data},
          newId: widget.targetContainerId,
        );
        if (widget.targetContainerId != null) {
          provider.updateRandomContainer(container);
        } else {
          provider.addRandomContainer(name: container.name);
          final created = provider.randomContainers.lastOrNull;
          if (created != null) {
            for (final child in container.children) {
              provider.addRandomChild(
                created.id,
                name: child.name,
                weight: child.weight,
              );
            }
          }
        }
        break;
      case 'sequence':
        final container = ContainerPresetService.instance._presetDataToSequence(
          {'name': preset.name, ...preset.data},
          newId: widget.targetContainerId,
        );
        if (widget.targetContainerId != null) {
          provider.updateSequenceContainer(container);
        } else {
          provider.addSequenceContainer(name: container.name);
          final created = provider.sequenceContainers.lastOrNull;
          if (created != null) {
            for (final step in container.steps) {
              provider.addSequenceStep(
                created.id,
                childId: step.childId,
                childName: step.childName,
                delayMs: step.delayMs,
                durationMs: step.durationMs,
              );
            }
          }
        }
        break;
    }

    _showSnackBar('Applied preset: ${preset.name}', Colors.green);
  }

  void _applyUserPreset(ContainerPreset preset) {
    final provider = context.read<MiddlewareProvider>();

    switch (preset.type) {
      case 'blend':
        final container = ContainerPresetService.instance._presetDataToBlend(
          preset.data,
          newId: widget.targetContainerId,
        );
        if (widget.targetContainerId != null) {
          provider.updateBlendContainer(container);
        } else {
          provider.addBlendContainer(
            name: container.name,
            rtpcId: container.rtpcId,
          );
        }
        break;
      case 'random':
        final container = ContainerPresetService.instance._presetDataToRandom(
          preset.data,
          newId: widget.targetContainerId,
        );
        if (widget.targetContainerId != null) {
          provider.updateRandomContainer(container);
        } else {
          provider.addRandomContainer(name: container.name);
        }
        break;
      case 'sequence':
        final container = ContainerPresetService.instance._presetDataToSequence(
          preset.data,
          newId: widget.targetContainerId,
        );
        if (widget.targetContainerId != null) {
          provider.updateSequenceContainer(container);
        } else {
          provider.addSequenceContainer(name: container.name);
        }
        break;
    }

    _showSnackBar('Applied preset: ${preset.name}', Colors.green);
  }

  Future<void> _importPreset() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ffxcontainer', 'json'],
        dialogTitle: 'Import Container Preset',
      );

      if (result != null && result.files.single.path != null) {
        final preset = await ContainerPresetService.instance.importPreset(result.files.single.path!);
        if (preset != null) {
          setState(() {
            _userPresets.add(preset);
            _selectedUserPreset = preset;
            _selectedFactoryPreset = null;
          });
          _showSnackBar('Imported: ${preset.name}', Colors.green);
        } else {
          _showSnackBar('Failed to import preset', Colors.red);
        }
      }
    } catch (e) {
      _showSnackBar('Import error: $e', Colors.red);
    }
  }

  Future<void> _exportUserPreset(ContainerPreset preset) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Container Preset',
        fileName: '${preset.name}$kPresetExtension',
        type: FileType.custom,
        allowedExtensions: ['ffxcontainer'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(preset.toJson()),
        );
        _showSnackBar('Exported: ${preset.name}', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Export error: $e', Colors.red);
    }
  }

  Future<void> _deleteUserPreset(ContainerPreset preset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surfaceDark,
        title: Text('Delete Preset', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: Text(
          'Are you sure you want to delete "${preset.name}"?',
          style: TextStyle(color: FluxForgeTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _userPresets.removeWhere((p) => p.name == preset.name);
        if (_selectedUserPreset?.name == preset.name) {
          _selectedUserPreset = null;
        }
      });
      _showSnackBar('Deleted: ${preset.name}', Colors.orange);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXTENSION FOR PRIVATE ACCESS
// ═══════════════════════════════════════════════════════════════════════════════

extension _ContainerPresetServicePrivate on ContainerPresetService {
  BlendContainer _presetDataToBlend(Map<String, dynamic> data, {int? newId}) {
    final children = (data['children'] as List<dynamic>?)?.asMap().entries.map((e) {
      final childData = e.value as Map<String, dynamic>;
      return BlendChild(
        id: e.key + 1,
        name: childData['name'] as String? ?? 'Child ${e.key + 1}',
        rtpcStart: (childData['rtpcStart'] as num?)?.toDouble() ?? 0.0,
        rtpcEnd: (childData['rtpcEnd'] as num?)?.toDouble() ?? 1.0,
        crossfadeWidth: (childData['crossfadeWidth'] as num?)?.toDouble() ?? 0.1,
        audioPath: null,
      );
    }).toList() ?? [];

    return BlendContainer(
      id: newId ?? 0,
      name: data['name'] as String? ?? 'Imported Blend',
      rtpcId: data['rtpcId'] as int? ?? 0,
      crossfadeCurve: CrossfadeCurve.values[(data['crossfadeCurve'] as int?) ?? 0],
      enabled: data['enabled'] as bool? ?? true,
      children: children,
    );
  }

  RandomContainer _presetDataToRandom(Map<String, dynamic> data, {int? newId}) {
    final children = (data['children'] as List<dynamic>?)?.asMap().entries.map((e) {
      final childData = e.value as Map<String, dynamic>;
      return RandomChild(
        id: e.key + 1,
        name: childData['name'] as String? ?? 'Child ${e.key + 1}',
        weight: (childData['weight'] as num?)?.toDouble() ?? 1.0,
        pitchMin: (childData['pitchMin'] as num?)?.toDouble() ?? 0.0,
        pitchMax: (childData['pitchMax'] as num?)?.toDouble() ?? 0.0,
        volumeMin: (childData['volumeMin'] as num?)?.toDouble() ?? 1.0,
        volumeMax: (childData['volumeMax'] as num?)?.toDouble() ?? 1.0,
        audioPath: null,
      );
    }).toList() ?? [];

    return RandomContainer(
      id: newId ?? 0,
      name: data['name'] as String? ?? 'Imported Random',
      mode: RandomMode.values[(data['mode'] as int?) ?? 0],
      enabled: data['enabled'] as bool? ?? true,
      globalPitchMin: (data['globalPitchMin'] as num?)?.toDouble() ?? 0.0,
      globalPitchMax: (data['globalPitchMax'] as num?)?.toDouble() ?? 0.0,
      globalVolumeMin: (data['globalVolumeMin'] as num?)?.toDouble() ?? 1.0,
      globalVolumeMax: (data['globalVolumeMax'] as num?)?.toDouble() ?? 1.0,
      children: children,
    );
  }

  SequenceContainer _presetDataToSequence(Map<String, dynamic> data, {int? newId}) {
    final steps = (data['steps'] as List<dynamic>?)?.asMap().entries.map((e) {
      final stepData = e.value as Map<String, dynamic>;
      return SequenceStep(
        index: e.key,
        childId: e.key + 1,
        childName: stepData['childName'] as String? ?? 'Step ${e.key + 1}',
        audioPath: null,
        delayMs: (stepData['delayMs'] as num?)?.toDouble() ?? 0.0,
        durationMs: (stepData['durationMs'] as num?)?.toDouble() ?? 100.0,
        fadeInMs: (stepData['fadeInMs'] as num?)?.toDouble() ?? 0.0,
        fadeOutMs: (stepData['fadeOutMs'] as num?)?.toDouble() ?? 0.0,
        loopCount: stepData['loopCount'] as int? ?? 1,
        volume: (stepData['volume'] as num?)?.toDouble() ?? 1.0,
      );
    }).toList() ?? [];

    return SequenceContainer(
      id: newId ?? 0,
      name: data['name'] as String? ?? 'Imported Sequence',
      endBehavior: SequenceEndBehavior.values[(data['endBehavior'] as int?) ?? 0],
      speed: (data['speed'] as num?)?.toDouble() ?? 1.0,
      enabled: data['enabled'] as bool? ?? true,
      steps: steps,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPACT BADGE
// ═══════════════════════════════════════════════════════════════════════════════

class ContainerPresetLibraryBadge extends StatelessWidget {
  final VoidCallback onTap;

  const ContainerPresetLibraryBadge({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music, size: 14, color: Colors.amber),
            const SizedBox(width: 6),
            Text(
              'Presets',
              style: TextStyle(
                color: Colors.amber,
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

// ═══════════════════════════════════════════════════════════════════════════════
// DIALOG WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════

class ContainerPresetLibraryDialog extends StatelessWidget {
  final int? targetContainerId;
  final String? targetContainerType;

  const ContainerPresetLibraryDialog({
    super.key,
    this.targetContainerId,
    this.targetContainerType,
  });

  static Future<void> show(
    BuildContext context, {
    int? targetContainerId,
    String? targetContainerType,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ContainerPresetLibraryDialog(
        targetContainerId: targetContainerId,
        targetContainerType: targetContainerType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 800,
        height: 600,
        decoration: BoxDecoration(
          color: FluxForgeTheme.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FluxForgeTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ContainerPresetLibraryPanel(
          targetContainerId: targetContainerId,
          targetContainerType: targetContainerType,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
