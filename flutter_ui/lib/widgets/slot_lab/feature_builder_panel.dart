// ============================================================================
// FluxForge Studio — Feature Builder Panel
// ============================================================================
// P13: Unified Feature Builder Panel for SlotLab
// Single panel accessible from SlotLab header button.
// Enables/disables feature blocks and configures their options.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/feature_builder/block_category.dart';
import '../../models/feature_builder/feature_block.dart';
import '../../models/feature_builder/block_options.dart';
import '../../providers/feature_builder_provider.dart';

/// Feature Builder Panel — unified panel for configuring slot features.
///
/// Shows all feature blocks organized by category with enable/disable toggles
/// and configurable options for each block.
class FeatureBuilderPanel extends StatefulWidget {
  /// Callback when panel should close
  final VoidCallback? onClose;

  /// Callback when configuration changes
  final VoidCallback? onConfigChanged;

  const FeatureBuilderPanel({
    super.key,
    this.onClose,
    this.onConfigChanged,
  });

  /// Show as a modal dialog
  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 900,
            height: 700,
            decoration: BoxDecoration(
              color: const Color(0xFF121218),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF4A9EFF).withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4A9EFF).withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: FeatureBuilderPanel(
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<FeatureBuilderPanel> createState() => _FeatureBuilderPanelState();
}

class _FeatureBuilderPanelState extends State<FeatureBuilderPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _expandedBlockId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FeatureBuilderProvider>(
      builder: (context, provider, _) {
        return Column(
          children: [
            // Header
            _buildHeader(provider),

            // Tab Bar
            _buildTabBar(),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: BlockCategory.values.map((category) {
                  return _buildCategoryTab(provider, category);
                }).toList(),
              ),
            ),

            // Footer with stats
            _buildFooter(provider),
          ],
        );
      },
    );
  }

  Widget _buildHeader(FeatureBuilderProvider provider) {
    final validationResult = provider.validate();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A22), Color(0xFF242430)],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFF4A9EFF), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4A9EFF).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.extension,
              color: Color(0xFF4A9EFF),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),

          // Title
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FEATURE BUILDER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Text(
                'Configure slot features and audio stages',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Validation status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: validationResult.isValid
                  ? const Color(0xFF40FF90).withOpacity(0.2)
                  : const Color(0xFFFF4040).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: validationResult.isValid
                    ? const Color(0xFF40FF90)
                    : const Color(0xFFFF4040),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  validationResult.isValid ? Icons.check_circle : Icons.warning,
                  color: validationResult.isValid
                      ? const Color(0xFF40FF90)
                      : const Color(0xFFFF4040),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  validationResult.isValid
                      ? 'Valid'
                      : '${validationResult.errors.length} issues',
                  style: TextStyle(
                    color: validationResult.isValid
                        ? const Color(0xFF40FF90)
                        : const Color(0xFFFF4040),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Stage count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers, color: Color(0xFFFFD700), size: 16),
                const SizedBox(width: 6),
                Text(
                  '${provider.totalStageCount} stages',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Undo/Redo
          IconButton(
            icon: Icon(
              Icons.undo,
              color: provider.canUndo ? Colors.white70 : Colors.white24,
            ),
            onPressed: provider.canUndo
                ? () {
                    provider.undo();
                    widget.onConfigChanged?.call();
                  }
                : null,
            tooltip: 'Undo',
            iconSize: 20,
          ),
          IconButton(
            icon: Icon(
              Icons.redo,
              color: provider.canRedo ? Colors.white70 : Colors.white24,
            ),
            onPressed: provider.canRedo
                ? () {
                    provider.redo();
                    widget.onConfigChanged?.call();
                  }
                : null,
            tooltip: 'Redo',
            iconSize: 20,
          ),

          const SizedBox(width: 8),

          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: widget.onClose,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF1a1a24),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF4A9EFF),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        tabs: BlockCategory.values.map((category) {
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getCategoryIcon(category), size: 16),
                const SizedBox(width: 8),
                Text(category.displayName),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategoryTab(FeatureBuilderProvider provider, BlockCategory category) {
    final blocks = provider.getBlocksByCategory(category);

    if (blocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getCategoryIcon(category),
              size: 48,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              'No ${category.displayName.toLowerCase()} blocks available',
              style: const TextStyle(color: Colors.white38),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        final block = blocks[index];
        return _buildBlockCard(provider, block);
      },
    );
  }

  Widget _buildBlockCard(FeatureBuilderProvider provider, FeatureBlock block) {
    final isExpanded = _expandedBlockId == block.id;
    final categoryColor = Color(block.category.colorValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: block.isEnabled
              ? categoryColor.withOpacity(0.5)
              : Colors.white12,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Block header
          InkWell(
            onTap: () {
              setState(() {
                _expandedBlockId = isExpanded ? null : block.id;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Enable toggle
                  Switch(
                    value: block.isEnabled,
                    onChanged: block.canBeDisabled
                        ? (value) {
                            if (value) {
                              provider.enableBlock(block.id);
                            } else {
                              provider.disableBlock(block.id);
                            }
                            widget.onConfigChanged?.call();
                          }
                        : null,
                    activeColor: categoryColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 12),

                  // Block icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: block.isEnabled
                          ? categoryColor.withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getBlockIcon(block.id),
                      color: block.isEnabled ? categoryColor : Colors.white38,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Block name and description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          block.name,
                          style: TextStyle(
                            color: block.isEnabled ? Colors.white : Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          block.description,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Stage count badge
                  if (block.isEnabled) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: categoryColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${block.generateStages().length} stages',
                        style: TextStyle(
                          color: categoryColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Expand icon
                  if (block.options.isNotEmpty)
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white38,
                    ),
                ],
              ),
            ),
          ),

          // Block options (expanded)
          if (isExpanded && block.options.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white12),
                ),
              ),
              child: _buildBlockOptions(provider, block),
            ),
        ],
      ),
    );
  }

  Widget _buildBlockOptions(FeatureBuilderProvider provider, FeatureBlock block) {
    // Group options by group name
    final groups = <String, List<BlockOption>>{};
    for (final option in block.options) {
      final groupName = option.group ?? 'General';
      groups.putIfAbsent(groupName, () => []).add(option);
    }

    // Sort options within each group by order
    for (final options in groups.values) {
      options.sort((a, b) => a.order.compareTo(b.order));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: groups.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.key != 'General') ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 8),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
              ...entry.value.map((option) {
                return _buildOptionControl(provider, block, option);
              }),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOptionControl(
    FeatureBuilderProvider provider,
    FeatureBlock block,
    BlockOption option,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Option label
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                if (option.description != null)
                  Text(
                    option.description!,
                    style: const TextStyle(
                      color: Colors.white30,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Option control
          Expanded(
            child: _buildOptionWidget(provider, block, option),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionWidget(
    FeatureBuilderProvider provider,
    FeatureBlock block,
    BlockOption option,
  ) {
    switch (option.type) {
      case BlockOptionType.toggle:
        return Align(
          alignment: Alignment.centerLeft,
          child: Switch(
            value: option.value as bool? ?? false,
            onChanged: block.isEnabled
                ? (value) {
                    provider.setBlockOption(block.id, option.id, value);
                    widget.onConfigChanged?.call();
                  }
                : null,
            activeColor: Color(block.category.colorValue),
          ),
        );

      case BlockOptionType.dropdown:
        final choices = option.choices ?? [];
        return DropdownButton<dynamic>(
          value: option.value,
          isExpanded: true,
          dropdownColor: const Color(0xFF242430),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          underline: Container(height: 1, color: Colors.white24),
          onChanged: block.isEnabled
              ? (value) {
                  provider.setBlockOption(block.id, option.id, value);
                  widget.onConfigChanged?.call();
                }
              : null,
          items: choices.map((choice) {
            return DropdownMenuItem(
              value: choice.value,
              child: Text(choice.label),
            );
          }).toList(),
        );

      case BlockOptionType.range:
      case BlockOptionType.percentage:
        final min = (option.min ?? 0).toDouble();
        final max = (option.max ?? 100).toDouble();
        final value = (option.value as num?)?.toDouble() ?? min;
        return Row(
          children: [
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: option.step != null
                    ? ((max - min) / option.step!).round()
                    : null,
                activeColor: Color(block.category.colorValue),
                onChanged: block.isEnabled
                    ? (value) {
                        provider.setBlockOption(block.id, option.id, value);
                        widget.onConfigChanged?.call();
                      }
                    : null,
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                option.type == BlockOptionType.percentage
                    ? '${value.toInt()}%'
                    : value.toStringAsFixed(option.step != null && option.step! < 1 ? 1 : 0),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );

      case BlockOptionType.count:
        final min = (option.min ?? 0).toInt();
        final max = (option.max ?? 100).toInt();
        final value = (option.value as int?) ?? min;
        return Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              onPressed: block.isEnabled && value > min
                  ? () {
                      provider.setBlockOption(block.id, option.id, value - 1);
                      widget.onConfigChanged?.call();
                    }
                  : null,
              color: Colors.white54,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: block.isEnabled && value < max
                  ? () {
                      provider.setBlockOption(block.id, option.id, value + 1);
                      widget.onConfigChanged?.call();
                    }
                  : null,
              color: Colors.white54,
            ),
          ],
        );

      case BlockOptionType.text:
        return TextField(
          controller: TextEditingController(text: option.value as String? ?? ''),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Color(block.category.colorValue)),
            ),
          ),
          enabled: block.isEnabled,
          onChanged: (value) {
            provider.setBlockOption(block.id, option.id, value);
            widget.onConfigChanged?.call();
          },
        );

      case BlockOptionType.multiSelect:
        final choices = option.choices ?? [];
        final selectedValues = (option.value as List<dynamic>?) ?? [];
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          children: choices.map((choice) {
            final isSelected = selectedValues.contains(choice.value);
            return FilterChip(
              label: Text(choice.label),
              selected: isSelected,
              selectedColor: Color(block.category.colorValue).withOpacity(0.3),
              checkmarkColor: Color(block.category.colorValue),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 11,
              ),
              onSelected: block.isEnabled
                  ? (selected) {
                      final newValues = List<dynamic>.from(selectedValues);
                      if (selected) {
                        newValues.add(choice.value);
                      } else {
                        newValues.remove(choice.value);
                      }
                      provider.setBlockOption(block.id, option.id, newValues);
                      widget.onConfigChanged?.call();
                    }
                  : null,
            );
          }).toList(),
        );

      case BlockOptionType.color:
        return const Text(
          'Color picker not implemented',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        );
    }
  }

  Widget _buildFooter(FeatureBuilderProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A22),
        border: Border(
          top: BorderSide(color: Colors.white12),
        ),
      ),
      child: Row(
        children: [
          // Enabled blocks summary
          Text(
            '${provider.enabledBlockCount} of ${provider.allBlocks.length} blocks enabled',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),

          const Spacer(),

          // Reset button
          TextButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reset All'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
            ),
            onPressed: () {
              provider.resetAll();
              widget.onConfigChanged?.call();
            },
          ),

          const SizedBox(width: 8),

          // Generate stages button
          ElevatedButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Generate Stages'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final result = provider.generateStages();
              if (result.isValid) {
                provider.exportStagesToConfiguration();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${result.stages.length} stages generated and exported!',
                    ),
                    backgroundColor: const Color(0xFF40FF90),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Generation failed: ${result.warnings.map((w) => w.message).join(", ")}',
                    ),
                    backgroundColor: const Color(0xFFFF4040),
                  ),
                );
              }
              widget.onConfigChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(BlockCategory category) {
    switch (category) {
      case BlockCategory.core:
        return Icons.settings;
      case BlockCategory.feature:
        return Icons.extension;
      case BlockCategory.presentation:
        return Icons.palette;
      case BlockCategory.bonus:
        return Icons.star;
    }
  }

  IconData _getBlockIcon(String blockId) {
    switch (blockId) {
      case 'game_core':
        return Icons.casino;
      case 'grid':
        return Icons.grid_view;
      case 'symbol_set':
        return Icons.emoji_symbols;
      case 'free_spins':
        return Icons.replay_circle_filled;
      case 'respin':
        return Icons.refresh;
      case 'hold_and_win':
        return Icons.lock;
      case 'cascades':
        return Icons.waterfall_chart;
      case 'collector':
        return Icons.shopping_basket;
      case 'win_presentation':
        return Icons.celebration;
      case 'music_states':
        return Icons.music_note;
      default:
        return Icons.extension;
    }
  }
}
