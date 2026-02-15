/// Plugin Manager Screen
///
/// Manages VST/AU/CLAP plugins:
/// - Scan for plugins
/// - Enable/disable plugins
/// - View plugin info
/// - Plugin paths configuration

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Plugin format types (internal to this screen)
enum _PluginFormat { vst3, au, clap, vst2 }

/// Plugin info (internal to this screen)
class _PluginInfo {
  final String id;
  final String name;
  final String vendor;
  final String version;
  final _PluginFormat format;
  final String path;
  final bool isEnabled;
  final bool isInstrument;
  final bool isBridged;
  final int inputChannels;
  final int outputChannels;

  _PluginInfo({
    required this.id,
    required this.name,
    required this.vendor,
    required this.version,
    required this.format,
    required this.path,
    this.isEnabled = true,
    this.isInstrument = false,
    this.isBridged = false,
    this.inputChannels = 2,
    this.outputChannels = 2,
  });

  _PluginInfo copyWith({bool? isEnabled}) {
    return _PluginInfo(
      id: id,
      name: name,
      vendor: vendor,
      version: version,
      format: format,
      path: path,
      isEnabled: isEnabled ?? this.isEnabled,
      isInstrument: isInstrument,
      isBridged: isBridged,
      inputChannels: inputChannels,
      outputChannels: outputChannels,
    );
  }

  String get formatName {
    switch (format) {
      case _PluginFormat.vst3:
        return 'VST3';
      case _PluginFormat.au:
        return 'AU';
      case _PluginFormat.clap:
        return 'CLAP';
      case _PluginFormat.vst2:
        return 'VST2';
    }
  }
}

class PluginManagerScreen extends StatefulWidget {
  const PluginManagerScreen({super.key});

  @override
  State<PluginManagerScreen> createState() => _PluginManagerScreenState();
}

class _PluginManagerScreenState extends State<PluginManagerScreen>
    with SingleTickerProviderStateMixin {
  List<_PluginInfo> _plugins = [];
  List<String> _scanPaths = [];
  bool _isLoading = true;
  bool _isScanning = false;
  double _scanProgress = 0;
  String _scanStatus = '';
  String _searchQuery = '';
  _PluginFormat? _filterFormat;
  bool _showInstrumentsOnly = false;
  bool _showEffectsOnly = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlugins();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPlugins() async {
    setState(() => _isLoading = true);

    // TODO: Call Rust FFI to get actual plugins
    await Future.delayed(const Duration(milliseconds: 300));

    _plugins = [
      _PluginInfo(
        id: 'ff-q-64',
        name: 'FF-Q 64',
        vendor: 'FluxForge',
        version: '1.0',
        format: _PluginFormat.vst3,
        path: '/Library/Audio/Plug-Ins/VST3/FF-Q 64.vst3',
        isInstrument: false,
      ),
      _PluginInfo(
        id: 'ff-c',
        name: 'FF-C',
        vendor: 'FluxForge',
        version: '1.0',
        format: _PluginFormat.vst3,
        path: '/Library/Audio/Plug-Ins/VST3/FF-C.vst3',
        isInstrument: false,
      ),
      _PluginInfo(
        id: 'serum',
        name: 'Serum',
        vendor: 'Xfer Records',
        version: '1.363',
        format: _PluginFormat.vst3,
        path: '/Library/Audio/Plug-Ins/VST3/Serum.vst3',
        isInstrument: true,
      ),
      _PluginInfo(
        id: 'vital',
        name: 'Vital',
        vendor: 'Matt Tytel',
        version: '1.5.5',
        format: _PluginFormat.clap,
        path: '/Library/Audio/Plug-Ins/CLAP/Vital.clap',
        isInstrument: true,
      ),
      _PluginInfo(
        id: 'soundtoys-decapitator',
        name: 'Decapitator',
        vendor: 'Soundtoys',
        version: '5.4',
        format: _PluginFormat.au,
        path: '/Library/Audio/Plug-Ins/Components/Decapitator.component',
        isInstrument: false,
      ),
      _PluginInfo(
        id: 'valhalla-room',
        name: 'ValhallaRoom',
        vendor: 'Valhalla DSP',
        version: '1.6.5',
        format: _PluginFormat.vst3,
        path: '/Library/Audio/Plug-Ins/VST3/ValhallaRoom.vst3',
        isInstrument: false,
      ),
    ];

    _scanPaths = [
      '/Library/Audio/Plug-Ins/VST3',
      '/Library/Audio/Plug-Ins/Components',
      '/Library/Audio/Plug-Ins/CLAP',
      '~/Library/Audio/Plug-Ins/VST3',
      '~/Library/Audio/Plug-Ins/Components',
    ];

    setState(() => _isLoading = false);
  }

  Future<void> _scanPlugins() async {
    setState(() {
      _isScanning = true;
      _scanProgress = 0;
      _scanStatus = 'Scanning...';
    });

    // Simulate scanning
    for (int i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 50));
      setState(() {
        _scanProgress = i / 100;
        _scanStatus = 'Scanning: ${_scanPaths[i % _scanPaths.length]}';
      });
    }

    // Reload plugins after scan
    await _loadPlugins();

    setState(() {
      _isScanning = false;
      _scanStatus = '';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found ${_plugins.length} plugins'),
          backgroundColor: FluxForgeTheme.accentGreen,
        ),
      );
    }
  }

  void _togglePlugin(int index) {
    setState(() {
      _plugins[index] = _plugins[index].copyWith(
        isEnabled: !_plugins[index].isEnabled,
      );
    });
    // TODO: Call Rust FFI to enable/disable plugin
  }

  List<_PluginInfo> get _filteredPlugins {
    var filtered = _plugins;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((p) {
        return p.name.toLowerCase().contains(query) ||
            p.vendor.toLowerCase().contains(query);
      }).toList();
    }

    // Apply format filter
    if (_filterFormat != null) {
      filtered = filtered.where((p) => p.format == _filterFormat).toList();
    }

    // Apply type filter
    if (_showInstrumentsOnly) {
      filtered = filtered.where((p) => p.isInstrument).toList();
    } else if (_showEffectsOnly) {
      filtered = filtered.where((p) => !p.isInstrument).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FluxForgeTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: FluxForgeTheme.bgMid,
        title: const Text('Plugin Manager'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: FluxForgeTheme.accentBlue,
          tabs: const [
            Tab(text: 'Plugins'),
            Tab(text: 'Paths'),
          ],
        ),
        actions: [
          if (!_isScanning)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Scan for plugins',
              onPressed: _scanPlugins,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_isScanning) _buildScanProgress(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPluginsTab(),
                      _buildPathsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildScanProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: FluxForgeTheme.bgMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _scanStatus,
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _scanProgress,
            backgroundColor: FluxForgeTheme.bgSurface,
            valueColor: AlwaysStoppedAnimation(FluxForgeTheme.accentBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginsTab() {
    return Column(
      children: [
        _buildSearchAndFilters(),
        Expanded(
          child: _filteredPlugins.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.extension_off,
                        size: 48,
                        color: FluxForgeTheme.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No plugins found',
                        style: TextStyle(color: FluxForgeTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _scanPlugins,
                        icon: const Icon(Icons.search),
                        label: const Text('Scan for Plugins'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FluxForgeTheme.accentBlue,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredPlugins.length,
                  itemBuilder: (context, index) {
                    final plugin = _filteredPlugins[index];
                    final originalIndex = _plugins.indexOf(plugin);
                    return _buildPluginItem(plugin, originalIndex);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          // Search field
          TextField(
            style: TextStyle(color: FluxForgeTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search plugins...',
              hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
              prefixIcon: Icon(Icons.search, color: FluxForgeTheme.textSecondary),
              filled: true,
              fillColor: FluxForgeTheme.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 12),
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Format filter
                _buildFilterChip(
                  label: 'All Formats',
                  isSelected: _filterFormat == null,
                  onSelected: () => setState(() => _filterFormat = null),
                ),
                const SizedBox(width: 8),
                ..._PluginFormat.values.map((format) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildFilterChip(
                      label: _getFormatName(format),
                      isSelected: _filterFormat == format,
                      onSelected: () => setState(() => _filterFormat = format),
                    ),
                  );
                }),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Instruments',
                  isSelected: _showInstrumentsOnly,
                  onSelected: () => setState(() {
                    _showInstrumentsOnly = !_showInstrumentsOnly;
                    if (_showInstrumentsOnly) _showEffectsOnly = false;
                  }),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Effects',
                  isSelected: _showEffectsOnly,
                  onSelected: () => setState(() {
                    _showEffectsOnly = !_showEffectsOnly;
                    if (_showEffectsOnly) _showInstrumentsOnly = false;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      backgroundColor: FluxForgeTheme.bgSurface,
      selectedColor: FluxForgeTheme.accentBlue,
      checkmarkColor: FluxForgeTheme.textPrimary,
      labelStyle: TextStyle(
        color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textPrimary,
        fontSize: 12,
      ),
    );
  }

  Widget _buildPluginItem(_PluginInfo plugin, int originalIndex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: plugin.isEnabled
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.3)
              : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getFormatColor(plugin.format).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              plugin.formatName,
              style: TextStyle(
                color: _getFormatColor(plugin.format),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                plugin.name,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (plugin.isInstrument)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentPurple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'INST',
                  style: TextStyle(
                    color: FluxForgeTheme.accentPurple,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${plugin.vendor} v${plugin.version}',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: Switch(
          value: plugin.isEnabled,
          onChanged: (_) => _togglePlugin(originalIndex),
          activeColor: FluxForgeTheme.accentGreen,
        ),
        onTap: () => _showPluginDetails(plugin),
      ),
    );
  }

  void _showPluginDetails(_PluginInfo plugin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: Text(
          plugin.name,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Vendor', plugin.vendor),
            _buildDetailRow('Version', plugin.version),
            _buildDetailRow('Format', plugin.formatName),
            _buildDetailRow('Type', plugin.isInstrument ? 'Instrument' : 'Effect'),
            _buildDetailRow('Channels', '${plugin.inputChannels} in / ${plugin.outputChannels} out'),
            const SizedBox(height: 8),
            Text(
              'Path',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                plugin.path,
                style: TextStyle(
                  color: FluxForgeTheme.textTertiary,
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plugin Search Paths',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _scanPaths.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder,
                        color: FluxForgeTheme.accentBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _scanPaths[index],
                          style: TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: FluxForgeTheme.textSecondary,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _scanPaths.removeAt(index));
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                // TODO: Open folder picker and add path
                setState(() {
                  _scanPaths.add('/New/Plugin/Path');
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Path'),
              style: OutlinedButton.styleFrom(
                foregroundColor: FluxForgeTheme.accentBlue,
                side: BorderSide(color: FluxForgeTheme.accentBlue),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getFormatName(_PluginFormat format) {
    switch (format) {
      case _PluginFormat.vst3:
        return 'VST3';
      case _PluginFormat.au:
        return 'AU';
      case _PluginFormat.clap:
        return 'CLAP';
      case _PluginFormat.vst2:
        return 'VST2';
    }
  }

  Color _getFormatColor(_PluginFormat format) {
    switch (format) {
      case _PluginFormat.vst3:
        return FluxForgeTheme.accentBlue;
      case _PluginFormat.au:
        return FluxForgeTheme.accentGreen;
      case _PluginFormat.clap:
        return FluxForgeTheme.accentOrange;
      case _PluginFormat.vst2:
        return FluxForgeTheme.accentPurple;
    }
  }
}
