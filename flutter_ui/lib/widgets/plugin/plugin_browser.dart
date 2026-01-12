// Plugin Browser Widget
//
// Professional plugin browser with filtering, search, and categorization
// Supports VST3, CLAP, AU, LV2, and Internal plugins

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';

/// Plugin browser panel for selecting and loading plugins
class PluginBrowser extends StatefulWidget {
  /// Callback when plugin is selected for loading
  final void Function(NativePluginInfo plugin)? onPluginSelected;

  /// Callback when plugin is double-clicked to load
  final void Function(NativePluginInfo plugin)? onPluginLoad;

  const PluginBrowser({
    super.key,
    this.onPluginSelected,
    this.onPluginLoad,
  });

  @override
  State<PluginBrowser> createState() => _PluginBrowserState();
}

class _PluginBrowserState extends State<PluginBrowser> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<NativePluginInfo> _allPlugins = [];
  List<NativePluginInfo> _filteredPlugins = [];
  NativePluginInfo? _selectedPlugin;

  NativePluginType? _typeFilter;
  NativePluginCategory? _categoryFilter;
  String _searchQuery = '';
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadPlugins();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadPlugins() {
    // In real implementation, this would call the FFI
    // For now, populate with demo internal plugins
    _allPlugins = [
      const NativePluginInfo(
        id: 'rf.eq.parametric',
        name: 'Parametric EQ',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.effect,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.eq.graphic',
        name: 'Graphic EQ',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.effect,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.dynamics.compressor',
        name: 'Compressor',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.effect,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.dynamics.limiter',
        name: 'Limiter',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.effect,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.dynamics.gate',
        name: 'Gate',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.effect,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.reverb.algorithmic',
        name: 'Algorithmic Reverb',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.effect,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.reverb.convolution',
        name: 'Convolution Reverb',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.effect,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.delay.stereo',
        name: 'Stereo Delay',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.effect,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.analysis.spectrum',
        name: 'Spectrum Analyzer',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.analyzer,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.analysis.loudness',
        name: 'Loudness Meter',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.analyzer,
        hasEditor: true,
      ),
      const NativePluginInfo(
        id: 'rf.utility.gain',
        name: 'Gain',
        vendor: 'FluxForge Studio',
        type: NativePluginType.internal,
        category: NativePluginCategory.utility,
        hasEditor: true,
      ),
    ];
    _applyFilters();
  }

  Future<void> _scanPlugins() async {
    setState(() => _isScanning = true);

    // In real implementation, call FFI scan
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _isScanning = false;
      // Reload plugins after scan
      _loadPlugins();
    });
  }

  void _applyFilters() {
    setState(() {
      _filteredPlugins = _allPlugins.where((plugin) {
        // Type filter
        if (_typeFilter != null && plugin.type != _typeFilter) {
          return false;
        }

        // Category filter
        if (_categoryFilter != null && plugin.category != _categoryFilter) {
          return false;
        }

        // Search filter
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          if (!plugin.name.toLowerCase().contains(query) &&
              !plugin.vendor.toLowerCase().contains(query)) {
            return false;
          }
        }

        return true;
      }).toList();

      // Sort by name
      _filteredPlugins.sort((a, b) => a.name.compareTo(b.name));
    });
  }

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _applyFilters();
  }

  void _onTypeFilterChanged(NativePluginType? type) {
    _typeFilter = type;
    _applyFilters();
  }

  void _onCategoryFilterChanged(NativePluginCategory? category) {
    _categoryFilter = category;
    _applyFilters();
  }

  void _onPluginTap(NativePluginInfo plugin) {
    setState(() => _selectedPlugin = plugin);
    widget.onPluginSelected?.call(plugin);
  }

  void _onPluginDoubleTap(NativePluginInfo plugin) {
    widget.onPluginLoad?.call(plugin);
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
            '${_filteredPlugins.length} plugins',
            style: const TextStyle(color: Color(0xFF808080), fontSize: 11),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF4A9EFF)),
                    ),
                  )
                : const Icon(Icons.refresh, size: 16, color: Color(0xFF808080)),
            onPressed: _isScanning ? null : _scanPlugins,
            tooltip: 'Rescan Plugins',
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
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
              suffixIcon: _searchQuery.isNotEmpty
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
                _buildFilterChip('All Types', _typeFilter == null, () => _onTypeFilterChanged(null)),
                _buildFilterChip('VST3', _typeFilter == NativePluginType.vst3,
                    () => _onTypeFilterChanged(NativePluginType.vst3),
                    color: const Color(0xFF4A9EFF)),
                _buildFilterChip('CLAP', _typeFilter == NativePluginType.clap,
                    () => _onTypeFilterChanged(NativePluginType.clap),
                    color: const Color(0xFFFF9040)),
                _buildFilterChip('AU', _typeFilter == NativePluginType.audioUnit,
                    () => _onTypeFilterChanged(NativePluginType.audioUnit),
                    color: const Color(0xFF40FF90)),
                _buildFilterChip('LV2', _typeFilter == NativePluginType.lv2,
                    () => _onTypeFilterChanged(NativePluginType.lv2),
                    color: const Color(0xFFFF4060)),
                _buildFilterChip('Internal', _typeFilter == NativePluginType.internal,
                    () => _onTypeFilterChanged(NativePluginType.internal),
                    color: const Color(0xFF40C8FF)),
                const SizedBox(width: 12),
                _buildFilterChip('All', _categoryFilter == null, () => _onCategoryFilterChanged(null)),
                _buildFilterChip('Effects', _categoryFilter == NativePluginCategory.effect,
                    () => _onCategoryFilterChanged(NativePluginCategory.effect)),
                _buildFilterChip('Instruments', _categoryFilter == NativePluginCategory.instrument,
                    () => _onCategoryFilterChanged(NativePluginCategory.instrument)),
                _buildFilterChip('Analyzers', _categoryFilter == NativePluginCategory.analyzer,
                    () => _onCategoryFilterChanged(NativePluginCategory.analyzer)),
                _buildFilterChip('Utility', _categoryFilter == NativePluginCategory.utility,
                    () => _onCategoryFilterChanged(NativePluginCategory.utility)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap, {Color? color}) {
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
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? (color ?? const Color(0xFF4A9EFF)) : const Color(0xFF808080),
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPluginList() {
    if (_filteredPlugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.extension_off, size: 48, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No plugins match your search' : 'No plugins found',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _scanPlugins,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Scan for Plugins'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _filteredPlugins.length,
      itemBuilder: (context, index) {
        final plugin = _filteredPlugins[index];
        final isSelected = plugin.id == _selectedPlugin?.id;

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
                    color: Color(plugin.typeColor).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    plugin.typeIcon,
                    style: TextStyle(
                      color: Color(plugin.typeColor),
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
                // Editor indicator
                if (plugin.hasEditor)
                  const Icon(Icons.tune, size: 14, color: Color(0xFF606060)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailPanel() {
    final plugin = _selectedPlugin!;

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
              color: Color(plugin.typeColor).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              plugin.typeIcon,
              style: TextStyle(
                color: Color(plugin.typeColor),
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
                Text(
                  plugin.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${plugin.vendor} • ${plugin.category.name.toUpperCase()}',
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
  }
}

/// Compact plugin selector dropdown (uses NativePluginInfo)
class NativePluginSelector extends StatelessWidget {
  final String? selectedPluginId;
  final void Function(NativePluginInfo)? onPluginSelected;
  final NativePluginCategory? categoryFilter;

  const NativePluginSelector({
    super.key,
    this.selectedPluginId,
    this.onPluginSelected,
    this.categoryFilter,
  });

  @override
  Widget build(BuildContext context) {
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
              selectedPluginId ?? 'Select Plugin',
              style: TextStyle(
                color: selectedPluginId != null ? Colors.white : const Color(0xFF606060),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF808080)),
          ],
        ),
      ),
    );
  }

  void _showPluginPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF121216),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 400,
          height: 500,
          child: PluginBrowser(
            onPluginLoad: (plugin) {
              onPluginSelected?.call(plugin);
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }
}
