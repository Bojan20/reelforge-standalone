// Plugin Browser Widget
//
// Professional plugin browser with filtering, search, and categorization
// Supports VST3, CLAP, AU, LV2, and Internal plugins
//
// Connected to PluginProvider for:
// - Plugin scanning and discovery (FFI)
// - Search and filtering
// - Favorites management
// - Recent plugins
// - Plugin loading

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/plugin_provider.dart';

/// Plugin browser panel for selecting and loading plugins
class PluginBrowser extends StatefulWidget {
  /// Callback when plugin is selected for loading
  final void Function(PluginInfo plugin)? onPluginSelected;

  /// Callback when plugin is double-clicked to load
  final void Function(PluginInfo plugin)? onPluginLoad;

  /// Track ID for loading plugins (optional, for insert context)
  final int? trackId;

  /// Slot index for loading plugins (optional, for insert context)
  final int? slotIndex;

  const PluginBrowser({
    super.key,
    this.onPluginSelected,
    this.onPluginLoad,
    this.trackId,
    this.slotIndex,
  });

  @override
  State<PluginBrowser> createState() => _PluginBrowserState();
}

class _PluginBrowserState extends State<PluginBrowser> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  PluginInfo? _selectedPlugin;

  @override
  void initState() {
    super.initState();

    // Initialize provider if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PluginProvider>();
      if (provider.allPlugins.isEmpty) {
        provider.init();
      }
      // Sync search controller with provider state
      _searchController.text = provider.searchQuery;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    context.read<PluginProvider>().setSearchQuery(value);
  }

  void _onFormatFilterChanged(PluginFormat? format) {
    context.read<PluginProvider>().setFormatFilter(format);
  }

  void _onCategoryFilterChanged(PluginCategory? category) {
    context.read<PluginProvider>().setCategoryFilter(category);
  }

  void _onPluginTap(PluginInfo plugin) {
    setState(() => _selectedPlugin = plugin);
    widget.onPluginSelected?.call(plugin);
  }

  void _onPluginDoubleTap(PluginInfo plugin) {
    widget.onPluginLoad?.call(plugin);
  }

  Future<void> _scanPlugins() async {
    await context.read<PluginProvider>().scanPlugins();
  }

  void _toggleFavorite(String pluginId) {
    context.read<PluginProvider>().toggleFavorite(pluginId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121216),
      child: Column(
        children: [
          _buildHeader(),
          _buildFilters(),
          Expanded(child: _buildPluginList()),
          if (_selectedPlugin != null) _buildDetailPanel(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        final isScanning = provider.scanState == ScanState.scanning;

        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A20),
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
          ),
          child: Row(
            children: [
              const Icon(Icons.extension, size: 16, color: Color(0xFF4A9EFF)),
              const SizedBox(width: 8),
              const Text(
                'Plugin Browser',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${provider.filteredPlugins.length} plugins',
                style: const TextStyle(color: Color(0xFF808080), fontSize: 11),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: isScanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Color(0xFF4A9EFF)),
                        ),
                      )
                    : const Icon(Icons.refresh, size: 16, color: Color(0xFF808080)),
                onPressed: isScanning ? null : _scanPlugins,
                tooltip: 'Rescan Plugins',
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters() {
    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A20),
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
          ),
          child: Column(
            children: [
              // Search field
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search plugins...',
                  hintStyle: const TextStyle(color: Color(0xFF606060)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF606060)),
                  suffixIcon: provider.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: Color(0xFF606060)),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF0A0A0C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 8),
              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Favorites toggle
                    _buildFilterChip(
                      provider.showFavoritesOnly ? 'Favorites' : 'All',
                      provider.showFavoritesOnly,
                      () => provider.setShowFavoritesOnly(!provider.showFavoritesOnly),
                      icon: provider.showFavoritesOnly ? Icons.star : Icons.star_border,
                      color: const Color(0xFFFFD43B),
                    ),
                    const SizedBox(width: 8),
                    // Format filters
                    _buildFilterChip('All Types', provider.formatFilter == null, () => _onFormatFilterChanged(null)),
                    _buildFilterChip('VST3', provider.formatFilter == PluginFormat.vst3,
                        () => _onFormatFilterChanged(PluginFormat.vst3),
                        color: const Color(0xFF4A9EFF)),
                    _buildFilterChip('CLAP', provider.formatFilter == PluginFormat.clap,
                        () => _onFormatFilterChanged(PluginFormat.clap),
                        color: const Color(0xFFFF9040)),
                    _buildFilterChip('AU', provider.formatFilter == PluginFormat.audioUnit,
                        () => _onFormatFilterChanged(PluginFormat.audioUnit),
                        color: const Color(0xFF40FF90)),
                    _buildFilterChip('LV2', provider.formatFilter == PluginFormat.lv2,
                        () => _onFormatFilterChanged(PluginFormat.lv2),
                        color: const Color(0xFFFF4060)),
                    _buildFilterChip('Internal', provider.formatFilter == PluginFormat.internal,
                        () => _onFormatFilterChanged(PluginFormat.internal),
                        color: const Color(0xFF40C8FF)),
                    const SizedBox(width: 12),
                    // Category filters
                    _buildFilterChip('All', provider.categoryFilter == null, () => _onCategoryFilterChanged(null)),
                    _buildFilterChip('Effects', provider.categoryFilter == PluginCategory.effect,
                        () => _onCategoryFilterChanged(PluginCategory.effect)),
                    _buildFilterChip('Instruments', provider.categoryFilter == PluginCategory.instrument,
                        () => _onCategoryFilterChanged(PluginCategory.instrument)),
                    _buildFilterChip('Analyzers', provider.categoryFilter == PluginCategory.analyzer,
                        () => _onCategoryFilterChanged(PluginCategory.analyzer)),
                    _buildFilterChip('Utility', provider.categoryFilter == PluginCategory.utility,
                        () => _onCategoryFilterChanged(PluginCategory.utility)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap, {Color? color, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? (color ?? const Color(0xFF4A9EFF)).withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? (color ?? const Color(0xFF4A9EFF)) : const Color(0xFF3A3A40),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: isSelected ? (color ?? const Color(0xFF4A9EFF)) : const Color(0xFF808080)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? (color ?? const Color(0xFF4A9EFF)) : const Color(0xFF808080),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPluginList() {
    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        final plugins = provider.filteredPlugins;

        if (provider.scanState == ScanState.scanning) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFF4A9EFF)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Scanning plugins... ${(provider.scanProgress * 100).toInt()}%',
                  style: const TextStyle(color: Color(0xFF808080), fontSize: 13),
                ),
              ],
            ),
          );
        }

        if (plugins.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.extension_off, size: 48, color: Colors.white.withOpacity(0.2)),
                const SizedBox(height: 12),
                Text(
                  provider.searchQuery.isNotEmpty
                      ? 'No plugins match your search'
                      : provider.allPlugins.isEmpty
                          ? 'No plugins found'
                          : 'No plugins match filters',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (provider.allPlugins.isEmpty)
                  TextButton.icon(
                    onPressed: _scanPlugins,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Scan for Plugins'),
                  )
                else
                  TextButton.icon(
                    onPressed: () => provider.clearFilters(),
                    icon: const Icon(Icons.filter_alt_off, size: 16),
                    label: const Text('Clear Filters'),
                  ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          itemCount: plugins.length,
          itemBuilder: (context, index) {
            final plugin = plugins[index];
            final isSelected = plugin.id == _selectedPlugin?.id;
            final isFavorite = provider.isFavorite(plugin.id);

            return InkWell(
              onTap: () => _onPluginTap(plugin),
              onDoubleTap: () => _onPluginDoubleTap(plugin),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF2A3A4A) : Colors.transparent,
                  border: const Border(bottom: BorderSide(color: Color(0xFF1A1A20))),
                ),
                child: Row(
                  children: [
                    // Plugin type badge
                    Container(
                      width: 32,
                      height: 18,
                      decoration: BoxDecoration(
                        color: _getFormatColor(plugin.format).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _getFormatLabel(plugin.format),
                        style: TextStyle(
                          color: _getFormatColor(plugin.format),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Plugin name
                    Expanded(
                      child: Text(
                        plugin.name,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Vendor
                    Text(
                      plugin.vendor,
                      style: const TextStyle(color: Color(0xFF606060), fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    // Favorite toggle
                    GestureDetector(
                      onTap: () => _toggleFavorite(plugin.id),
                      child: Icon(
                        isFavorite ? Icons.star : Icons.star_border,
                        size: 14,
                        color: isFavorite ? const Color(0xFFFFD43B) : const Color(0xFF404040),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Editor indicator
                    if (plugin.hasEditor)
                      const Icon(Icons.tune, size: 14, color: Color(0xFF606060)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailPanel() {
    final plugin = _selectedPlugin!;

    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        final isFavorite = provider.isFavorite(plugin.id);

        return Container(
          height: 80,
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A20),
            border: Border(top: BorderSide(color: Color(0xFF2A2A30))),
          ),
          child: Row(
            children: [
              // Plugin icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _getFormatColor(plugin.format).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  _getFormatLabel(plugin.format),
                  style: TextStyle(
                    color: _getFormatColor(plugin.format),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Plugin info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plugin.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _toggleFavorite(plugin.id),
                          child: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            size: 18,
                            color: isFavorite ? const Color(0xFFFFD43B) : const Color(0xFF606060),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${plugin.vendor} \u2022 ${plugin.categoryName}',
                      style: const TextStyle(color: Color(0xFF808080), fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plugin.id,
                      style: const TextStyle(color: Color(0xFF505050), fontSize: 10),
                    ),
                  ],
                ),
              ),
              // Load button
              ElevatedButton(
                onPressed: () => widget.onPluginLoad?.call(plugin),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A9EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                child: const Text('Load', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getFormatColor(PluginFormat format) {
    switch (format) {
      case PluginFormat.vst3:
        return const Color(0xFF4A9EFF);
      case PluginFormat.clap:
        return const Color(0xFFFF9040);
      case PluginFormat.audioUnit:
        return const Color(0xFF40FF90);
      case PluginFormat.lv2:
        return const Color(0xFFFF4060);
      case PluginFormat.internal:
        return const Color(0xFF40C8FF);
    }
  }

  String _getFormatLabel(PluginFormat format) {
    switch (format) {
      case PluginFormat.vst3:
        return 'VST3';
      case PluginFormat.clap:
        return 'CLAP';
      case PluginFormat.audioUnit:
        return 'AU';
      case PluginFormat.lv2:
        return 'LV2';
      case PluginFormat.internal:
        return 'INT';
    }
  }
}

/// Compact plugin selector dropdown (uses PluginProvider)
class PluginSelector extends StatelessWidget {
  final String? selectedPluginId;
  final void Function(PluginInfo)? onPluginSelected;
  final PluginCategory? categoryFilter;
  final int? trackId;
  final int? slotIndex;

  const PluginSelector({
    super.key,
    this.selectedPluginId,
    this.onPluginSelected,
    this.categoryFilter,
    this.trackId,
    this.slotIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        final selectedPlugin = selectedPluginId != null
            ? provider.allPlugins.firstWhere(
                (p) => p.id == selectedPluginId,
                orElse: () => PluginInfo(
                  id: '',
                  name: '',
                  vendor: '',
                  format: PluginFormat.internal,
                  category: PluginCategory.effect,
                  path: '',
                ),
              )
            : null;

        return InkWell(
          onTap: () => _showPluginPicker(context),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3A3A40)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.extension, size: 14, color: Color(0xFF808080)),
                const SizedBox(width: 6),
                Text(
                  selectedPlugin?.name ?? 'Select Plugin',
                  style: TextStyle(
                    color: selectedPlugin != null ? Colors.white : const Color(0xFF606060),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF808080)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPluginPicker(BuildContext context) {
    // Set category filter before showing dialog
    if (categoryFilter != null) {
      context.read<PluginProvider>().setCategoryFilter(categoryFilter);
    }

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF121216),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 400,
          height: 500,
          child: PluginBrowser(
            trackId: trackId,
            slotIndex: slotIndex,
            onPluginLoad: (plugin) {
              onPluginSelected?.call(plugin);
              Navigator.of(dialogContext).pop();
            },
          ),
        ),
      ),
    );
  }
}

/// Recent plugins quick access widget
class RecentPluginsBar extends StatelessWidget {
  final void Function(PluginInfo)? onPluginSelected;
  final int maxVisible;

  const RecentPluginsBar({
    super.key,
    this.onPluginSelected,
    this.maxVisible = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        final recent = provider.recentPlugins.take(maxVisible).toList();

        if (recent.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A20),
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
          ),
          child: Row(
            children: [
              const Icon(Icons.history, size: 14, color: Color(0xFF606060)),
              const SizedBox(width: 8),
              const Text(
                'Recent:',
                style: TextStyle(color: Color(0xFF606060), fontSize: 11),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recent.length,
                  separatorBuilder: (_, _i) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final plugin = recent[index];
                    return InkWell(
                      onTap: () => onPluginSelected?.call(plugin),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0C),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          plugin.name,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
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
}
