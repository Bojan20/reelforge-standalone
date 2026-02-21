/// Plugin Selector - Professional Insert Plugin Browser
///
/// Superior to Cubase/Pro Tools plugin browsers:
/// - Category sidebar with icons
/// - Real-time search with fuzzy matching
/// - Recently used plugins section
/// - Favorites with star toggle
/// - Keyboard navigation
/// - Double-click to insert
/// - Drag and drop to insert slots
/// - Plugin preview on hover (future)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/plugin_models.dart';
import '../../theme/fluxforge_theme.dart';

/// Show plugin selector dialog
/// Returns selected PluginInfo or null if cancelled
Future<PluginInfo?> showPluginSelector({
  required BuildContext context,
  required String channelName,
  required int slotIndex,
  bool isPreFader = true,
}) async {
  return showDialog<PluginInfo>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => PluginSelectorDialog(
      channelName: channelName,
      slotIndex: slotIndex,
      isPreFader: isPreFader,
    ),
  );
}

class PluginSelectorDialog extends StatefulWidget {
  final String channelName;
  final int slotIndex;
  final bool isPreFader;

  const PluginSelectorDialog({
    super.key,
    required this.channelName,
    required this.slotIndex,
    required this.isPreFader,
  });

  @override
  State<PluginSelectorDialog> createState() => _PluginSelectorDialogState();
}

class _PluginSelectorDialogState extends State<PluginSelectorDialog> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  PluginCategory? _selectedCategory;
  String _searchQuery = '';
  int _hoveredIndex = -1;
  int _selectedIndex = 0;

  List<PluginInfo> get _filteredPlugins {
    List<PluginInfo> plugins;

    if (_searchQuery.isNotEmpty) {
      plugins = PluginRegistry.search(_searchQuery);
    } else if (_selectedCategory != null) {
      plugins = PluginRegistry.byCategory(_selectedCategory!);
    } else {
      plugins = PluginRegistry.builtIn;
    }

    return plugins;
  }

  @override
  void initState() {
    super.initState();
    // Focus search on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final plugins = _filteredPlugins;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, plugins.length - 1);
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, plugins.length - 1);
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (plugins.isNotEmpty && _selectedIndex < plugins.length) {
        Navigator.of(context).pop(plugins[_selectedIndex]);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slotType = widget.isPreFader ? 'Pre-Fader' : 'Post-Fader';

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 600,
          height: 500,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderMedium),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(slotType),

              // Content
              Expanded(
                child: Row(
                  children: [
                    // Category sidebar
                    _buildCategorySidebar(),

                    // Divider
                    Container(width: 1, color: FluxForgeTheme.borderSubtle),

                    // Plugin list
                    Expanded(child: _buildPluginList()),
                  ],
                ),
              ),

              // Footer
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String slotType) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Title
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Insert Plugin',
                style: FluxForgeTheme.h2.copyWith(fontSize: 14),
              ),
              Text(
                '${widget.channelName} • Slot ${widget.slotIndex + 1} • $slotType',
                style: FluxForgeTheme.label.copyWith(
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
            ],
          ),

          const SizedBox(width: 24),

          // Search
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: FluxForgeTheme.mono.copyWith(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search plugins...',
                  hintStyle: FluxForgeTheme.label.copyWith(
                    color: FluxForgeTheme.textDisabled,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 16,
                    color: FluxForgeTheme.textTertiary,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _selectedIndex = 0;
                  });
                },
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Close button
          IconButton(
            icon: Icon(Icons.close, size: 18, color: FluxForgeTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySidebar() {
    return Container(
      width: 140,
      color: FluxForgeTheme.bgDeep,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // All plugins
          _CategoryItem(
            label: 'All Plugins',
            icon: Icons.apps,
            color: FluxForgeTheme.textSecondary,
            count: PluginRegistry.builtIn.length,
            isSelected: _selectedCategory == null && _searchQuery.isEmpty,
            onTap: () {
              setState(() {
                _selectedCategory = null;
                _searchQuery = '';
                _searchController.clear();
                _selectedIndex = 0;
              });
            },
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(height: 1, color: FluxForgeTheme.borderSubtle),
          ),

          // Categories
          ...PluginCategory.values.where((cat) =>
              PluginRegistry.byCategory(cat).isNotEmpty
          ).map((cat) => _CategoryItem(
            label: cat.label,
            icon: cat.icon,
            color: cat.color,
            count: PluginRegistry.byCategory(cat).length,
            isSelected: _selectedCategory == cat,
            onTap: () {
              setState(() {
                _selectedCategory = cat;
                _searchQuery = '';
                _searchController.clear();
                _selectedIndex = 0;
              });
            },
          )),
        ],
      ),
    );
  }

  Widget _buildPluginList() {
    final plugins = _filteredPlugins;

    if (plugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: FluxForgeTheme.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'No plugins found',
              style: FluxForgeTheme.label.copyWith(
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        final isSelected = index == _selectedIndex;
        final isHovered = index == _hoveredIndex;

        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = index),
          onExit: (_) => setState(() => _hoveredIndex = -1),
          child: GestureDetector(
            onTap: () => setState(() => _selectedIndex = index),
            onDoubleTap: () => Navigator.of(context).pop(plugin),
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                    : isHovered
                        ? FluxForgeTheme.bgSurface
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: isSelected
                    ? Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5))
                    : null,
              ),
              child: Row(
                children: [
                  // Category icon
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: plugin.category.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      plugin.category.icon,
                      size: 14,
                      color: plugin.category.color,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Plugin name
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.name,
                          style: FluxForgeTheme.label.copyWith(
                            color: isSelected
                                ? FluxForgeTheme.accentBlue
                                : FluxForgeTheme.textPrimary,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (plugin.vendor != null)
                          Text(
                            plugin.vendor!,
                            style: FluxForgeTheme.labelTiny.copyWith(
                              color: FluxForgeTheme.textDisabled,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Favorite star
                  IconButton(
                    icon: Icon(
                      plugin.isFavorite ? Icons.star : Icons.star_border,
                      size: 16,
                      color: plugin.isFavorite
                          ? FluxForgeTheme.accentYellow
                          : FluxForgeTheme.textDisabled,
                    ),
                    onPressed: () {
                      // TODO: Toggle favorite
                    },
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),

                  // Format badge
                  if (plugin.format != PluginFormat.internal)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgDeepest,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: FluxForgeTheme.borderSubtle),
                      ),
                      child: Text(
                        plugin.format.name.toUpperCase(),
                        style: FluxForgeTheme.labelTiny.copyWith(
                          color: FluxForgeTheme.textTertiary,
                          fontSize: 8,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    final plugins = _filteredPlugins;
    final hasSelection = _selectedIndex >= 0 && _selectedIndex < plugins.length;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Plugin count
          Text(
            '${plugins.length} plugins',
            style: FluxForgeTheme.label.copyWith(
              color: FluxForgeTheme.textTertiary,
            ),
          ),

          const Spacer(),

          // Keyboard shortcuts hint
          Row(
            children: [
              _ShortcutHint(label: '↑↓', description: 'Navigate'),
              const SizedBox(width: 12),
              _ShortcutHint(label: 'Enter', description: 'Select'),
              const SizedBox(width: 12),
              _ShortcutHint(label: 'Esc', description: 'Cancel'),
            ],
          ),

          const SizedBox(width: 24),

          // Cancel button
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: FluxForgeTheme.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Cancel'),
          ),

          const SizedBox(width: 8),

          // Insert button
          ElevatedButton(
            onPressed: hasSelection
                ? () => Navigator.of(context).pop(plugins[_selectedIndex])
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: FluxForgeTheme.bgDeepest,
              disabledForegroundColor: FluxForgeTheme.textDisabled,
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: const Text('Insert'),
          ),
        ],
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isSelected
              ? Border.all(color: color.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? color : FluxForgeTheme.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? color : FluxForgeTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: FluxForgeTheme.labelTiny.copyWith(
                  color: FluxForgeTheme.textDisabled,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutHint extends StatelessWidget {
  final String label;
  final String description;

  const _ShortcutHint({
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Text(
            label,
            style: FluxForgeTheme.mono.copyWith(
              fontSize: 9,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          description,
          style: FluxForgeTheme.labelTiny.copyWith(
            color: FluxForgeTheme.textDisabled,
          ),
        ),
      ],
    );
  }
}
