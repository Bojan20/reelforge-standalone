/// DAW Plugin Scanner Panel (P0.1 Extracted)
///
/// Plugin browser with VST3/AU/CLAP/LV2 scanning:
/// - Real-time plugin scanning with progress
/// - Format filtering (VST3, AU, CLAP, LV2)
/// - Search by name/vendor
/// - Favorites system
/// - Category grouping
/// - Double-click to load plugin + open native editor
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/plugin_provider.dart';
import '../../../../providers/dsp_chain_provider.dart';
import '../../../../src/rust/native_ffi.dart' show NativePluginParamInfo;

// ═══════════════════════════════════════════════════════════════════════════
// PLUGINS SCANNER PANEL
// ═══════════════════════════════════════════════════════════════════════════

class PluginsScannerPanel extends StatefulWidget {
  /// Selected track ID for plugin insertion target
  final int? selectedTrackId;

  /// Callback when a plugin is inserted (pluginId, trackId)
  final void Function(String pluginId, int trackId)? onPluginInserted;

  /// Callback to create a track with plugin from the host DAW layout
  /// (pluginName, isInstrument) → created trackId
  final int Function(String pluginName, bool isInstrument)? onCreateTrackWithPlugin;

  const PluginsScannerPanel({
    super.key,
    this.selectedTrackId,
    this.onPluginInserted,
    this.onCreateTrackWithPlugin,
  });

  @override
  State<PluginsScannerPanel> createState() => _PluginsScannerPanelState();
}

class _PluginsScannerPanelState extends State<PluginsScannerPanel> {
  String? _selectedPluginId;
  String? _activeParamEditorInstanceId;
  final Set<String> _loadingPlugins = {};
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  Widget build(BuildContext context) {
    // Try to get PluginProvider from context
    PluginProvider? pluginProvider;
    try {
      pluginProvider = context.watch<PluginProvider>();
    } catch (_) {
      // Provider not available
    }

    if (pluginProvider == null) {
      return _buildFallback();
    }

    final isScanning = pluginProvider.scanState == ScanState.scanning;
    final plugins = pluginProvider.filteredPlugins;

    // Separate internal from external
    final internalPlugins = plugins.where((p) => p.format == PluginFormat.internal).toList();
    final vst3Plugins = plugins.where((p) => p.format == PluginFormat.vst3).toList();
    final auPlugins = plugins.where((p) => p.format == PluginFormat.audioUnit).toList();
    final clapPlugins = plugins.where((p) => p.format == PluginFormat.clap).toList();
    final lv2Plugins = plugins.where((p) => p.format == PluginFormat.lv2).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Rescan button
          Row(
            children: [
              _buildBrowserHeader('PLUGINS', Icons.extension),
              const SizedBox(width: 8),
              // Plugin count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LowerZoneColors.dawAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${plugins.length}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.dawAccent,
                  ),
                ),
              ),
              const Spacer(),
              // Scan progress
              if (isScanning && pluginProvider.scanProgress > 0) ...[
                SizedBox(
                  width: 40,
                  child: LinearProgressIndicator(
                    value: pluginProvider.scanProgress,
                    backgroundColor: LowerZoneColors.bgDeepest,
                    valueColor: const AlwaysStoppedAnimation(LowerZoneColors.dawAccent),
                    minHeight: 2,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Rescan button
              GestureDetector(
                onTap: isScanning ? null : () => pluginProvider?.scanPlugins(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isScanning
                        ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
                        : LowerZoneColors.bgSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isScanning ? LowerZoneColors.dawAccent : LowerZoneColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isScanning)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation(LowerZoneColors.dawAccent),
                          ),
                        )
                      else
                        const Icon(Icons.refresh, size: 12, color: LowerZoneColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        isScanning ? 'Scanning...' : 'Rescan',
                        style: TextStyle(
                          fontSize: 9,
                          color: isScanning ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Hint text
          const Text(
            'Click to insert on track  \u2022  Double-click to open editor',
            style: TextStyle(fontSize: 8, color: LowerZoneColors.textTertiary),
          ),
          const SizedBox(height: 8),
          // Search bar
          _buildSearchBar(pluginProvider),
          const SizedBox(height: 8),
          // Format filter chips
          _buildFormatFilters(pluginProvider),
          const SizedBox(height: 8),
          // Scan error
          if (pluginProvider.scanState == ScanState.error && pluginProvider.scanError != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: LowerZoneColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                pluginProvider.scanError!,
                style: const TextStyle(fontSize: 9, color: LowerZoneColors.error),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Status message bar
          if (_statusMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusIsError
                    ? LowerZoneColors.error.withValues(alpha: 0.15)
                    : const Color(0xFF40FF90).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 9,
                  color: _statusIsError ? LowerZoneColors.error : const Color(0xFF40FF90),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
          ],
          // Plugin list + optional parameter editor
          Expanded(
            child: _activeParamEditorInstanceId != null
                ? _buildParamEditorAndList(context, plugins, pluginProvider,
                    internalPlugins, vst3Plugins, auPlugins, clapPlugins, lv2Plugins)
                : plugins.isEmpty
                    ? _buildNoPluginsMessage(pluginProvider)
                    : _buildPluginList(context, pluginProvider,
                        internalPlugins, vst3Plugins, auPlugins, clapPlugins, lv2Plugins),
          ),
        ],
      ),
    );
  }

  // ─── Plugin Actions ───────────────────────────────────────────────────────

  Future<void> _insertPlugin(BuildContext context, PluginInfo plugin, PluginProvider provider) async {
    final isInstrument = plugin.category == PluginCategory.instrument;
    int trackId = widget.selectedTrackId ?? 0;

    // Create track via host DAW callback (engine_connected_layout)
    if (widget.onCreateTrackWithPlugin != null) {
      trackId = widget.onCreateTrackWithPlugin!(plugin.name, isInstrument);
    }

    // For internal plugins, also add to DSP chain
    if (plugin.format == PluginFormat.internal) {
      final nodeType = _pluginCategoryToNodeType(plugin);
      if (nodeType != null) {
        DspChainProvider.instance.addNode(trackId, nodeType);
      }
    }

    // Load plugin into engine via FFI
    final instanceId = await provider.loadPlugin(plugin.id, trackId, 0);
    if (!mounted) return;
    if (instanceId == null) {
      _setStatus('Failed to load ${plugin.name}', isError: true);
      return;
    }

    provider.addToRecent(plugin.id);
    if (mounted) {
      widget.onPluginInserted?.call(plugin.id, trackId);
      _setStatus('${plugin.name} → ${isInstrument ? "instrument" : "audio"} track #$trackId');
    }
  }

  void _setStatus(String msg, {bool isError = false}) {
    if (mounted) {
      setState(() {
        _statusMessage = msg;
        _statusIsError = isError;
      });
    }
  }

  Future<void> _loadAndOpenEditor(BuildContext context, PluginInfo plugin, PluginProvider provider) async {
    // If already loaded, toggle editor
    final existingInstance = provider.instances.values
        .where((i) => i.pluginId == plugin.id)
        .firstOrNull;
    if (existingInstance != null) {
      if (existingInstance.hasEditor) {
        if (existingInstance.isEditorOpen) {
          provider.closeEditor(existingInstance.instanceId);
          _setStatus('Closed editor: ${plugin.name}');
        } else {
          _setStatus('Opening editor: ${plugin.name}...');
          final opened = await provider.openEditor(existingInstance.instanceId);
          if (!opened && mounted) {
            _setStatus('Native GUI unavailable — showing params', isError: true);
            setState(() => _activeParamEditorInstanceId = existingInstance.instanceId);
          } else {
            _setStatus('Editor opened: ${plugin.name}');
          }
        }
      } else {
        _setStatus('No native editor — showing params');
        setState(() => _activeParamEditorInstanceId = existingInstance.instanceId);
      }
      return;
    }

    if (_loadingPlugins.contains(plugin.id)) return;
    setState(() => _loadingPlugins.add(plugin.id));

    try {
      _setStatus('Loading ${plugin.name} [${plugin.formatName}]...');

      // Step 1: Create track via host DAW callback
      final isInstrument = plugin.category == PluginCategory.instrument;
      int trackId = widget.selectedTrackId ?? 0;

      if (widget.onCreateTrackWithPlugin != null) {
        trackId = widget.onCreateTrackWithPlugin!(plugin.name, isInstrument);
        _setStatus('Created ${isInstrument ? "instrument" : "audio"} track #$trackId');
      }

      // Step 2: Load plugin into engine via FFI
      _setStatus('FFI pluginLoad("${plugin.id}") on track $trackId...');
      final instanceId = await provider.loadPlugin(plugin.id, trackId, 0);
      if (instanceId == null) {
        _setStatus('pluginLoad FAILED for ${plugin.id} — Rust returned null', isError: true);
        return;
      }
      _setStatus('Loaded: instanceId=$instanceId');

      // Step 3: Try to open native GUI editor
      bool editorOpened = false;
      if (plugin.hasEditor) {
        _setStatus('Opening native editor for $instanceId...');
        editorOpened = await provider.openEditor(instanceId);
      }

      if (editorOpened) {
        _setStatus('${plugin.name} — editor opened');
      } else {
        // Only AU plugins have native GUI via rack crate.
        // For VST3/CLAP: suggest using AU version.
        final isAU = plugin.format == PluginFormat.audioUnit;
        if (isAU) {
          _setStatus('${plugin.name} AU loaded but GUI failed to open', isError: true);
        } else {
          _setStatus('${plugin.name} loaded — use AU version for native editor');
        }
      }

      if (mounted) widget.onPluginInserted?.call(plugin.id, trackId);
    } catch (e) {
      _setStatus('Exception: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loadingPlugins.remove(plugin.id));
      }
    }
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  Widget _buildBrowserHeader(String title, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFallback() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrowserHeader('PLUGINS', Icons.extension),
          const SizedBox(height: 24),
          const Center(
            child: Column(
              children: [
                Icon(Icons.extension_off, size: 48, color: LowerZoneColors.textMuted),
                SizedBox(height: 12),
                Text(
                  'Plugin Provider not available',
                  style: TextStyle(fontSize: 12, color: LowerZoneColors.textMuted),
                ),
                SizedBox(height: 4),
                Text(
                  'Add PluginProvider to widget tree',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(PluginProvider provider) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: TextField(
        onChanged: provider.setSearchQuery,
        style: const TextStyle(fontSize: 11, color: LowerZoneColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search plugins...',
          hintStyle: const TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
          prefixIcon: const Icon(Icons.search, size: 14, color: LowerZoneColors.textMuted),
          suffixIcon: provider.searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () => provider.setSearchQuery(''),
                  child: const Icon(Icons.clear, size: 14, color: LowerZoneColors.textMuted),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),
    );
  }

  Widget _buildFormatFilters(PluginProvider provider) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFormatChip('All', null, provider),
          const SizedBox(width: 4),
          _buildFormatChip('VST3', PluginFormat.vst3, provider),
          const SizedBox(width: 4),
          _buildFormatChip('AU', PluginFormat.audioUnit, provider),
          const SizedBox(width: 4),
          _buildFormatChip('CLAP', PluginFormat.clap, provider),
          const SizedBox(width: 4),
          _buildFormatChip('LV2', PluginFormat.lv2, provider),
          const SizedBox(width: 4),
          _buildFormatChip('Internal', PluginFormat.internal, provider),
          const SizedBox(width: 8),
          // Favorites toggle
          GestureDetector(
            onTap: () => provider.setShowFavoritesOnly(!provider.showFavoritesOnly),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: provider.showFavoritesOnly
                    ? LowerZoneColors.warning.withValues(alpha: 0.2)
                    : LowerZoneColors.bgSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: provider.showFavoritesOnly ? LowerZoneColors.warning : LowerZoneColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    provider.showFavoritesOnly ? Icons.star : Icons.star_border,
                    size: 12,
                    color: provider.showFavoritesOnly ? LowerZoneColors.warning : LowerZoneColors.textMuted,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'Favorites',
                    style: TextStyle(
                      fontSize: 9,
                      color: provider.showFavoritesOnly ? LowerZoneColors.warning : LowerZoneColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatChip(String label, PluginFormat? format, PluginProvider provider) {
    final isSelected = provider.formatFilter == format;
    return GestureDetector(
      onTap: () => provider.setFormatFilter(format),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? LowerZoneColors.dawAccent.withValues(alpha: 0.2) : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildPluginCategory(
    BuildContext context,
    String category,
    List<PluginInfo> plugins,
    PluginProvider provider, {
    Color color = LowerZoneColors.dawAccent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header with colored accent
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            child: Row(
              children: [
                Text(
                  category,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  '${plugins.length}',
                  style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                ),
              ],
            ),
          ),
          // Plugin items
          ...plugins.map((p) => _buildPluginItem(context, p, provider)),
        ],
      ),
    );
  }

  DspNodeType? _pluginCategoryToNodeType(PluginInfo plugin) {
    // Map known plugin names/categories to internal DSP node types
    final nameLower = plugin.name.toLowerCase();
    if (nameLower.contains('eq') || nameLower.contains('equalizer')) return DspNodeType.eq;
    if (nameLower.contains('compressor') || nameLower.contains('comp')) return DspNodeType.compressor;
    if (nameLower.contains('limiter')) return DspNodeType.limiter;
    if (nameLower.contains('gate') || nameLower.contains('expander')) return DspNodeType.gate;
    if (nameLower.contains('reverb')) return DspNodeType.reverb;
    if (nameLower.contains('delay')) return DspNodeType.delay;
    if (nameLower.contains('saturat') || nameLower.contains('distort')) return DspNodeType.saturation;
    if (nameLower.contains('de-ess') || nameLower.contains('deess')) return DspNodeType.deEsser;
    return null; // External plugin — no internal DSP node
  }

  Color _formatColor(PluginFormat format) {
    switch (format) {
      case PluginFormat.vst3:
        return const Color(0xFF4A9EFF);
      case PluginFormat.audioUnit:
        return const Color(0xFF40FF90);
      case PluginFormat.clap:
        return const Color(0xFFFF9040);
      case PluginFormat.lv2:
        return const Color(0xFFFF4060);
      case PluginFormat.internal:
        return const Color(0xFF40C8FF);
    }
  }

  String _formatLabel(PluginFormat format) {
    switch (format) {
      case PluginFormat.vst3:
        return 'VST3';
      case PluginFormat.audioUnit:
        return 'AU';
      case PluginFormat.clap:
        return 'CLAP';
      case PluginFormat.lv2:
        return 'LV2';
      case PluginFormat.internal:
        return 'INT';
    }
  }

  Widget _buildPluginItem(BuildContext context, PluginInfo plugin, PluginProvider provider) {
    final isSelected = _selectedPluginId == plugin.id;
    final isLoading = _loadingPlugins.contains(plugin.id);
    // Check if this plugin has any loaded instances
    final isLoaded = provider.instances.values.any((i) => i.pluginId == plugin.id);
    final fmtColor = _formatColor(plugin.format);

    return GestureDetector(
      onTap: () {
        setState(() => _selectedPluginId = plugin.id);
        provider.addToRecent(plugin.id);
        _insertPlugin(context, plugin, provider);
      },
      onDoubleTap: () {
        _loadAndOpenEditor(context, plugin, provider);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? LowerZoneColors.dawAccent.withValues(alpha: 0.08)
              : isLoaded
                  ? const Color(0xFF40FF90).withValues(alpha: 0.05)
                  : null,
          border: Border(bottom: BorderSide(color: LowerZoneColors.border.withValues(alpha: 0.3))),
        ),
        child: Row(
          children: [
            // Plugin icon based on category
            Icon(
              plugin.category == PluginCategory.instrument
                  ? Icons.piano
                  : plugin.category == PluginCategory.analyzer
                      ? Icons.analytics
                      : Icons.tune,
              size: 14,
              color: isLoaded ? const Color(0xFF40FF90) : LowerZoneColors.dawAccent,
            ),
            const SizedBox(width: 8),
            // Format badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: fmtColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _formatLabel(plugin.format),
                style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: fmtColor),
              ),
            ),
            const SizedBox(width: 6),
            // Plugin name + vendor
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.name,
                    style: TextStyle(
                      fontSize: 10,
                      color: isLoaded ? const Color(0xFF40FF90) : LowerZoneColors.textPrimary,
                      fontWeight: isLoaded ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (plugin.vendor.isNotEmpty)
                    Text(
                      plugin.vendor,
                      style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
                    ),
                ],
              ),
            ),
            // Loading indicator
            if (isLoading) ...[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(LowerZoneColors.dawAccent),
                ),
              ),
              const SizedBox(width: 4),
            ],
            // Loaded indicator
            if (isLoaded && !isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle, size: 12, color: Color(0xFF40FF90)),
              ),
            // Editor button (if loaded + has editor)
            if (isLoaded && plugin.hasEditor)
              GestureDetector(
                onTap: () {
                  final instance = provider.instances.values
                      .where((i) => i.pluginId == plugin.id)
                      .firstOrNull;
                  if (instance != null) {
                    if (instance.isEditorOpen) {
                      provider.closeEditor(instance.instanceId);
                    } else {
                      provider.openEditor(instance.instanceId);
                    }
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.open_in_new,
                    size: 12,
                    color: provider.instances.values
                            .where((i) => i.pluginId == plugin.id)
                            .any((i) => i.isEditorOpen)
                        ? LowerZoneColors.dawAccent
                        : LowerZoneColors.textMuted,
                  ),
                ),
              ),
            // Favorite toggle
            GestureDetector(
              onTap: () => provider.toggleFavorite(plugin.id),
              child: Icon(
                plugin.isFavorite ? Icons.star : Icons.star_border,
                size: 14,
                color: plugin.isFavorite ? LowerZoneColors.warning : LowerZoneColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPluginList(
    BuildContext context,
    PluginProvider pluginProvider,
    List<PluginInfo> internalPlugins,
    List<PluginInfo> vst3Plugins,
    List<PluginInfo> auPlugins,
    List<PluginInfo> clapPlugins,
    List<PluginInfo> lv2Plugins,
  ) {
    return ListView(
      children: [
        if (internalPlugins.isNotEmpty)
          _buildPluginCategory(context, 'INTERNAL', internalPlugins, pluginProvider,
              color: const Color(0xFF40C8FF)),
        if (vst3Plugins.isNotEmpty)
          _buildPluginCategory(context, 'VST3', vst3Plugins, pluginProvider,
              color: const Color(0xFF4A9EFF)),
        if (auPlugins.isNotEmpty)
          _buildPluginCategory(context, 'AUDIO UNITS', auPlugins, pluginProvider,
              color: const Color(0xFF40FF90)),
        if (clapPlugins.isNotEmpty)
          _buildPluginCategory(context, 'CLAP', clapPlugins, pluginProvider,
              color: const Color(0xFFFF9040)),
        if (lv2Plugins.isNotEmpty)
          _buildPluginCategory(context, 'LV2', lv2Plugins, pluginProvider,
              color: const Color(0xFFFF4060)),
      ],
    );
  }

  Widget _buildParamEditorAndList(
    BuildContext context,
    List<PluginInfo> allPlugins,
    PluginProvider pluginProvider,
    List<PluginInfo> internalPlugins,
    List<PluginInfo> vst3Plugins,
    List<PluginInfo> auPlugins,
    List<PluginInfo> clapPlugins,
    List<PluginInfo> lv2Plugins,
  ) {
    return Column(
      children: [
        // Parameter editor at top
        Expanded(
          flex: 3,
          child: _buildParamEditor(pluginProvider),
        ),
        const Divider(height: 1, color: LowerZoneColors.border),
        // Plugin list below
        Expanded(
          flex: 2,
          child: allPlugins.isEmpty
              ? _buildNoPluginsMessage(pluginProvider)
              : _buildPluginList(context, pluginProvider,
                  internalPlugins, vst3Plugins, auPlugins, clapPlugins, lv2Plugins),
        ),
      ],
    );
  }

  Widget _buildParamEditor(PluginProvider provider) {
    final instanceId = _activeParamEditorInstanceId;
    if (instanceId == null) return const SizedBox.shrink();

    final instance = provider.getInstance(instanceId);
    if (instance == null) {
      // Instance was removed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _activeParamEditorInstanceId = null);
      });
      return const SizedBox.shrink();
    }

    final params = provider.getPluginParams(instanceId);

    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with close button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  instance.format == PluginFormat.internal ? Icons.tune : Icons.extension,
                  size: 12,
                  color: LowerZoneColors.dawAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    instance.name,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: LowerZoneColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Try native editor button
                if (instance.hasEditor)
                  GestureDetector(
                    onTap: () async {
                      final opened = await provider.openEditor(instanceId);
                      if (opened && mounted) {
                        setState(() => _activeParamEditorInstanceId = null);
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.open_in_new, size: 12, color: LowerZoneColors.textMuted),
                    ),
                  ),
                // Unload button
                GestureDetector(
                  onTap: () async {
                    await provider.unloadPlugin(instanceId);
                    if (mounted) setState(() => _activeParamEditorInstanceId = null);
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.power_settings_new, size: 12, color: LowerZoneColors.error),
                  ),
                ),
                // Close editor view
                GestureDetector(
                  onTap: () => setState(() => _activeParamEditorInstanceId = null),
                  child: const Icon(Icons.close, size: 12, color: LowerZoneColors.textMuted),
                ),
              ],
            ),
          ),
          // Parameters
          Expanded(
            child: params.isEmpty
                ? const Center(
                    child: Text(
                      'No parameters exposed',
                      style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: params.length,
                    itemBuilder: (context, index) {
                      final param = params[index];
                      return _buildParamRow(provider, instanceId, param);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamRow(PluginProvider provider, String instanceId, NativePluginParamInfo param) {
    final value = provider.getPluginParam(instanceId, param.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              param.name,
              style: const TextStyle(fontSize: 9, color: LowerZoneColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: LowerZoneColors.dawAccent,
                inactiveTrackColor: LowerZoneColors.bgMid,
                thumbColor: LowerZoneColors.dawAccent,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              ),
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: (v) {
                  provider.setPluginParam(instanceId, param.id, v);
                },
              ),
            ),
          ),
          SizedBox(
            width: 35,
            child: Text(
              value.toStringAsFixed(2),
              style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPluginsMessage(PluginProvider provider) {
    final hasFilters = provider.searchQuery.isNotEmpty ||
        provider.formatFilter != null ||
        provider.showFavoritesOnly;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilters ? Icons.search_off : Icons.extension_off,
            size: 32,
            color: LowerZoneColors.textMuted,
          ),
          const SizedBox(height: 8),
          Text(
            hasFilters ? 'No plugins match filters' : 'No plugins found',
            style: const TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: provider.clearFilters,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: LowerZoneColors.dawAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: LowerZoneColors.dawAccent),
                ),
                child: const Text(
                  'Clear Filters',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.dawAccent),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Click "Rescan" to scan for plugins',
              style: TextStyle(fontSize: 9, color: LowerZoneColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
