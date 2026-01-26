/// DAW Plugin Scanner Panel (P0.1 Extracted)
///
/// Plugin browser with VST3/AU/CLAP/LV2 scanning:
/// - Real-time plugin scanning with progress
/// - Format filtering (VST3, AU, CLAP, LV2)
/// - Search by name/vendor
/// - Favorites system
/// - Category grouping
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 820-1227 (~407 LOC)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/plugin_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PLUGINS SCANNER PANEL
// ═══════════════════════════════════════════════════════════════════════════

class PluginsScannerPanel extends StatelessWidget {
  const PluginsScannerPanel({super.key});

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

    // Group plugins by format
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
          const SizedBox(height: 12),
          // Search bar
          _buildSearchBar(pluginProvider),
          const SizedBox(height: 8),
          // Format filter chips
          _buildFormatFilters(pluginProvider),
          const SizedBox(height: 8),
          // Plugin list
          Expanded(
            child: plugins.isEmpty
                ? _buildNoPluginsMessage(pluginProvider)
                : ListView(
                    children: [
                      if (vst3Plugins.isNotEmpty)
                        _buildPluginCategory('VST3', vst3Plugins, pluginProvider),
                      if (auPlugins.isNotEmpty)
                        _buildPluginCategory('AU', auPlugins, pluginProvider),
                      if (clapPlugins.isNotEmpty)
                        _buildPluginCategory('CLAP', clapPlugins, pluginProvider),
                      if (lv2Plugins.isNotEmpty)
                        _buildPluginCategory('LV2', lv2Plugins, pluginProvider),
                    ],
                  ),
          ),
        ],
      ),
    );
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

  Widget _buildPluginCategory(String category, List<PluginInfo> plugins, PluginProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${plugins.length} plugins',
                  style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                ),
              ],
            ),
          ),
          // Plugin items
          ...plugins.map((p) => _buildPluginItem(p, provider)),
        ],
      ),
    );
  }

  Widget _buildPluginItem(PluginInfo plugin, PluginProvider provider) {
    return GestureDetector(
      onTap: () {
        // Add to recent when clicked
        provider.addToRecent(plugin.id);
        // TODO: Insert into track slot (needs callback)
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: LowerZoneColors.border.withValues(alpha: 0.3))),
        ),
        child: Row(
          children: [
            // Plugin icon based on category
            Icon(
              plugin.category == PluginCategory.instrument ? Icons.piano : Icons.tune,
              size: 14,
              color: LowerZoneColors.dawAccent,
            ),
            const SizedBox(width: 8),
            // Plugin name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.name,
                    style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    plugin.vendor,
                    style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
                  ),
                ],
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
