// ═══════════════════════════════════════════════════════════════════════════
// P3.2: STAGE COLOR PICKER — Custom color configuration for stages
// ═══════════════════════════════════════════════════════════════════════════
//
// Allows users to customize stage colors for timeline visualization.
// Supports per-stage and per-category color customization.
//
// Usage:
//   StageColorPicker.show(context);
//   StageColorPickerPanel() // Embeddable panel
//
library;

import 'package:flutter/material.dart';
import '../../config/stage_config.dart';

/// Preset color palette for quick selection
const List<Color> _presetColors = [
  Color(0xFF4A9EFF), // Blue
  Color(0xFF40FF90), // Green
  Color(0xFFFF9040), // Orange
  Color(0xFFFF4060), // Red
  Color(0xFF8B5CF6), // Purple
  Color(0xFFFFD700), // Gold
  Color(0xFF40C8FF), // Cyan
  Color(0xFFFF6B9D), // Pink
  Color(0xFF6B7280), // Gray
  Color(0xFFFFFFFF), // White
  Color(0xFF00FFFF), // Cyan bright
  Color(0xFFFF00FF), // Magenta
];

/// P3.2: Dialog to show color picker
class StageColorPicker {
  /// Show color picker dialog
  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1a1a20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          child: const StageColorPickerPanel(),
        ),
      ),
    );
  }
}

/// P3.2: Embeddable panel for stage color customization
class StageColorPickerPanel extends StatefulWidget {
  const StageColorPickerPanel({super.key});

  @override
  State<StageColorPickerPanel> createState() => _StageColorPickerPanelState();
}

class _StageColorPickerPanelState extends State<StageColorPickerPanel> {
  StageCategory? _selectedCategory;
  String? _selectedStage;
  final TextEditingController _hexController = TextEditingController();

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF242430),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              const Icon(Icons.palette, color: Color(0xFF4A9EFF), size: 24),
              const SizedBox(width: 12),
              const Text(
                'Stage Color Configuration',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.restore, color: Colors.white70),
                tooltip: 'Reset All to Defaults',
                onPressed: _resetAllColors,
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: Row(
            children: [
              // Categories list
              SizedBox(
                width: 180,
                child: _buildCategoryList(),
              ),

              // Vertical divider
              Container(width: 1, color: const Color(0xFF3a3a45)),

              // Stages list
              Expanded(
                child: _selectedCategory != null
                    ? _buildStageList()
                    : _buildEmptyState(),
              ),

              // Color picker (when stage selected)
              if (_selectedStage != null) ...[
                Container(width: 1, color: const Color(0xFF3a3a45)),
                SizedBox(
                  width: 160,
                  child: _buildColorPicker(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: StageCategory.values.map((category) {
        final isSelected = _selectedCategory == category;
        final stagesInCategory = _getStagesForCategory(category);

        return ListTile(
          dense: true,
          selected: isSelected,
          selectedTileColor: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
          leading: Icon(
            _getCategoryIcon(category),
            color: isSelected ? const Color(0xFF4A9EFF) : Colors.white54,
            size: 20,
          ),
          title: Text(
            category.name.toUpperCase(),
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF3a3a45),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${stagesInCategory.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
          onTap: () {
            setState(() {
              _selectedCategory = category;
              _selectedStage = null;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildStageList() {
    final stages = _getStagesForCategory(_selectedCategory!);

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: stages.length,
      itemBuilder: (context, index) {
        final stageType = stages[index];
        final config = StageConfig.instance.getConfig(stageType);
        final isSelected = _selectedStage == stageType;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4A9EFF).withValues(alpha: 0.2)
                : const Color(0xFF242430),
            borderRadius: BorderRadius.circular(6),
            border: isSelected
                ? Border.all(color: const Color(0xFF4A9EFF), width: 1)
                : null,
          ),
          child: ListTile(
            dense: true,
            leading: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: config?.color ?? StageConfig.defaultColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
            ),
            title: Text(
              stageType,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            subtitle: config?.description != null
                ? Text(
                    config!.description!,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  )
                : null,
            trailing: config?.isPooled == true
                ? const Tooltip(
                    message: 'Pooled (rapid-fire)',
                    child: Icon(Icons.bolt, color: Colors.amber, size: 16),
                  )
                : null,
            onTap: () {
              setState(() {
                _selectedStage = stageType;
                _updateHexController();
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildColorPicker() {
    final config = StageConfig.instance.getConfig(_selectedStage!);
    final currentColor = config?.color ?? StageConfig.defaultColor;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current color preview
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(height: 12),

          // Hex input
          TextField(
            controller: _hexController,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'HEX',
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
              prefixText: '#',
              prefixStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF242430),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (value) => _applyHexColor(value),
          ),
          const SizedBox(height: 12),

          // Preset colors
          const Text(
            'PRESETS',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: _presetColors.length,
              itemBuilder: (context, index) {
                final color = _presetColors[index];
                final isSelected = currentColor.value == color.value;
                final colorName = _getColorName(index);

                return Semantics(
                  label: '$colorName color${isSelected ? ', selected' : ''}',
                  button: true,
                  child: GestureDetector(
                    onTap: () => _applyColor(color),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white24,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Reset button
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _resetStageColor,
            icon: const Icon(Icons.restore, size: 14),
            label: const Text('Reset', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              backgroundColor: const Color(0xFF242430),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, color: Colors.white24, size: 48),
          SizedBox(height: 12),
          Text(
            'Select a category',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  List<String> _getStagesForCategory(StageCategory category) {
    return StageConfig.instance.getStagesInCategory(category);
  }

  IconData _getCategoryIcon(StageCategory category) {
    switch (category) {
      case StageCategory.spin:
        return Icons.rotate_right;
      case StageCategory.anticipation:
        return Icons.warning_amber;
      case StageCategory.win:
        return Icons.emoji_events;
      case StageCategory.rollup:
        return Icons.trending_up;
      case StageCategory.bigwin:
        return Icons.star;
      case StageCategory.feature:
        return Icons.auto_awesome;
      case StageCategory.cascade:
        return Icons.layers;
      case StageCategory.jackpot:
        return Icons.diamond;
      case StageCategory.bonus:
        return Icons.card_giftcard;
      case StageCategory.gamble:
        return Icons.casino;
      case StageCategory.music:
        return Icons.music_note;
      case StageCategory.ui:
        return Icons.touch_app;
      case StageCategory.system:
        return Icons.settings;
      case StageCategory.custom:
        return Icons.extension;
    }
  }

  void _updateHexController() {
    final config = StageConfig.instance.getConfig(_selectedStage!);
    final color = config?.color ?? StageConfig.defaultColor;
    _hexController.text = color.value.toRadixString(16).substring(2).toUpperCase();
  }

  void _applyHexColor(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final colorValue = int.tryParse('FF$cleaned', radix: 16);
      if (colorValue != null) {
        _applyColor(Color(colorValue));
      }
    }
  }

  void _applyColor(Color color) {
    if (_selectedStage == null) return;

    StageConfig.instance.updateStage(_selectedStage!, color: color);
    setState(() {
      _updateHexController();
    });
  }

  void _resetStageColor() {
    if (_selectedStage == null) return;

    // Get default color from built-in stages
    final defaultConfig = StageConfig.instance.getBuiltInConfig(_selectedStage!);
    if (defaultConfig != null) {
      StageConfig.instance.updateStage(_selectedStage!, color: defaultConfig.color);
      setState(() {
        _updateHexController();
      });
    }
  }

  void _resetAllColors() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242430),
        title: const Text(
          'Reset All Colors?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will reset all stage colors to their default values.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              StageConfig.instance.resetToDefaults();
              Navigator.pop(ctx);
              setState(() {});
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset All'),
          ),
        ],
      ),
    );
  }

  /// P3.6: Get color name for accessibility
  String _getColorName(int index) {
    const colorNames = [
      'Blue', 'Green', 'Orange', 'Red', 'Purple', 'Gold',
      'Cyan', 'Pink', 'Gray', 'White', 'Bright Cyan', 'Magenta',
    ];
    return index < colorNames.length ? colorNames[index] : 'Color ${index + 1}';
  }
}
