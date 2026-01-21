/// Audio Browser Panel — Drag Source for Auto Event Builder
///
/// Left-side collapsible panel with audio asset browser:
/// - Folder tree view (SFX, Music, VO, Ambience)
/// - Search with tag filtering
/// - Hover preview (waveform + playback)
/// - Draggable items for drop onto slot mockup
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section A.1
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../services/audio_playback_service.dart';
import '../../../services/waveform_cache_service.dart';
import '../../../src/rust/native_ffi.dart';
import '../../../theme/fluxforge_theme.dart';
import 'drop_target_wrapper.dart';

// =============================================================================
// AUDIO BROWSER PANEL
// =============================================================================

/// Collapsible audio browser panel for drag-drop workflow
class AudioBrowserPanel extends StatefulWidget {
  /// Whether the panel is expanded
  final bool isExpanded;

  /// Callback when expand/collapse button is pressed
  final VoidCallback? onToggleExpand;

  /// Fixed width when expanded
  final double expandedWidth;

  /// Fixed width when collapsed (icon bar only)
  final double collapsedWidth;

  const AudioBrowserPanel({
    super.key,
    this.isExpanded = true,
    this.onToggleExpand,
    this.expandedWidth = 280,
    this.collapsedWidth = 48,
  });

  @override
  State<AudioBrowserPanel> createState() => _AudioBrowserPanelState();
}

class _AudioBrowserPanelState extends State<AudioBrowserPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  AssetType? _selectedTypeFilter;
  String? _selectedTagFilter;
  String _searchQuery = '';
  String? _expandedFolder;

  // Hover preview state
  AudioAsset? _hoveredAsset;
  Timer? _hoverTimer;
  bool _isPreviewPlaying = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _hoverTimer?.cancel();
    _stopPreview();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  void _onTypeFilterChanged(AssetType? type) {
    setState(() {
      _selectedTypeFilter = type;
    });
  }

  void _onTagFilterChanged(String? tag) {
    setState(() {
      _selectedTagFilter = tag;
    });
  }

  void _onAssetHoverStart(AudioAsset asset) {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _hoveredAsset = asset;
        });
        _startPreview(asset);
      }
    });
  }

  void _onAssetHoverEnd() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    if (mounted) {
      setState(() {
        _hoveredAsset = null;
      });
      _stopPreview();
    }
  }

  int? _previewVoiceId;

  void _startPreview(AudioAsset asset) {
    if (_isPreviewPlaying) return;

    final playbackService = AudioPlaybackService.instance;
    _previewVoiceId = playbackService.previewFile(
      asset.path,
      volume: 0.8,
      source: PlaybackSource.browser,
    );
    if (_previewVoiceId != null && _previewVoiceId! >= 0) {
      _isPreviewPlaying = true;
    }
  }

  void _stopPreview() {
    if (!_isPreviewPlaying) return;

    if (_previewVoiceId != null && _previewVoiceId! >= 0) {
      final playbackService = AudioPlaybackService.instance;
      playbackService.stopVoice(_previewVoiceId!);
    }
    _previewVoiceId = null;
    _isPreviewPlaying = false;
  }

  List<AudioAsset> _filterAssets(List<AudioAsset> assets) {
    return assets.where((asset) {
      // Type filter
      if (_selectedTypeFilter != null && asset.assetType != _selectedTypeFilter) {
        return false;
      }

      // Tag filter
      if (_selectedTagFilter != null && !asset.tags.contains(_selectedTagFilter)) {
        return false;
      }

      // Search query
      if (_searchQuery.isNotEmpty) {
        final nameMatch = asset.displayName.toLowerCase().contains(_searchQuery);
        final tagMatch = asset.tags.any((t) => t.toLowerCase().contains(_searchQuery));
        return nameMatch || tagMatch;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: widget.isExpanded ? widget.expandedWidth : widget.collapsedWidth,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          right: BorderSide(
            color: FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: widget.isExpanded ? _buildExpandedContent() : _buildCollapsedContent(),
    );
  }

  Widget _buildCollapsedContent() {
    return Column(
      children: [
        // Expand button
        _CollapsedIconButton(
          icon: Icons.chevron_right,
          tooltip: 'Expand Browser',
          onTap: widget.onToggleExpand,
        ),

        const Divider(height: 1, color: FluxForgeTheme.borderSubtle),

        // Type filter icons
        _CollapsedIconButton(
          icon: Icons.surround_sound,
          tooltip: 'SFX',
          isActive: _selectedTypeFilter == AssetType.sfx,
          color: FluxForgeTheme.accentBlue,
          onTap: () => _onTypeFilterChanged(
            _selectedTypeFilter == AssetType.sfx ? null : AssetType.sfx,
          ),
        ),
        _CollapsedIconButton(
          icon: Icons.music_note,
          tooltip: 'Music',
          isActive: _selectedTypeFilter == AssetType.music,
          color: FluxForgeTheme.accentOrange,
          onTap: () => _onTypeFilterChanged(
            _selectedTypeFilter == AssetType.music ? null : AssetType.music,
          ),
        ),
        _CollapsedIconButton(
          icon: Icons.mic,
          tooltip: 'VO',
          isActive: _selectedTypeFilter == AssetType.vo,
          color: FluxForgeTheme.accentGreen,
          onTap: () => _onTypeFilterChanged(
            _selectedTypeFilter == AssetType.vo ? null : AssetType.vo,
          ),
        ),
        _CollapsedIconButton(
          icon: Icons.waves,
          tooltip: 'Ambience',
          isActive: _selectedTypeFilter == AssetType.amb,
          color: FluxForgeTheme.accentCyan,
          onTap: () => _onTypeFilterChanged(
            _selectedTypeFilter == AssetType.amb ? null : AssetType.amb,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedContent() {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        final allAssets = provider.audioAssets;
        final filteredAssets = _filterAssets(allAssets);
        final allTags = provider.allAssetTags;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(),

            // Search bar
            _buildSearchBar(),

            // Type filter tabs
            _buildTypeFilterTabs(),

            // Tag filter chips
            if (allTags.isNotEmpty) _buildTagFilterChips(allTags),

            // Asset list
            Expanded(
              child: filteredAssets.isEmpty
                  ? _buildEmptyState()
                  : _buildAssetList(filteredAssets),
            ),

            // Hover preview panel
            if (_hoveredAsset != null)
              _HoverPreviewPanel(asset: _hoveredAsset!),

            // Import button
            _buildImportButton(provider),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_special,
            size: 16,
            color: FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          const Text(
            'AUDIO BROWSER',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          // Collapse button
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Collapse',
            color: FluxForgeTheme.textMuted,
            onPressed: widget.onToggleExpand,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: const TextStyle(
          color: FluxForgeTheme.textPrimary,
          fontSize: 12,
        ),
        decoration: InputDecoration(
          hintText: 'Search assets...',
          hintStyle: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 12,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 16,
            color: FluxForgeTheme.textMuted,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: FluxForgeTheme.textMuted,
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: FluxForgeTheme.bgDeep,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
          ),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildTypeFilterTabs() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _TypeFilterTab(
            label: 'All',
            isSelected: _selectedTypeFilter == null,
            onTap: () => _onTypeFilterChanged(null),
          ),
          _TypeFilterTab(
            label: 'SFX',
            icon: Icons.surround_sound,
            color: FluxForgeTheme.accentBlue,
            isSelected: _selectedTypeFilter == AssetType.sfx,
            onTap: () => _onTypeFilterChanged(AssetType.sfx),
          ),
          _TypeFilterTab(
            label: 'Music',
            icon: Icons.music_note,
            color: FluxForgeTheme.accentOrange,
            isSelected: _selectedTypeFilter == AssetType.music,
            onTap: () => _onTypeFilterChanged(AssetType.music),
          ),
          _TypeFilterTab(
            label: 'VO',
            icon: Icons.mic,
            color: FluxForgeTheme.accentGreen,
            isSelected: _selectedTypeFilter == AssetType.vo,
            onTap: () => _onTypeFilterChanged(AssetType.vo),
          ),
          _TypeFilterTab(
            label: 'Amb',
            icon: Icons.waves,
            color: FluxForgeTheme.accentCyan,
            isSelected: _selectedTypeFilter == AssetType.amb,
            onTap: () => _onTypeFilterChanged(AssetType.amb),
          ),
        ],
      ),
    );
  }

  Widget _buildTagFilterChips(List<String> tags) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (_selectedTagFilter != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _TagChip(
                tag: 'Clear',
                isSelected: false,
                onTap: () => _onTagFilterChanged(null),
                icon: Icons.clear,
              ),
            ),
          ...tags.take(10).map((tag) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _TagChip(
                  tag: tag,
                  isSelected: _selectedTagFilter == tag,
                  onTap: () => _onTagFilterChanged(
                    _selectedTagFilter == tag ? null : tag,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildAssetList(List<AudioAsset> assets) {
    final provider = context.read<AutoEventBuilderProvider>();
    final recentAssets = provider.recentAssets;

    // Group by type
    final Map<AssetType, List<AudioAsset>> grouped = {};
    for (final asset in assets) {
      grouped.putIfAbsent(asset.assetType, () => []).add(asset);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        // Recent assets section (C.8)
        if (recentAssets.isNotEmpty && _searchQuery.isEmpty && _selectedTypeFilter == null)
          _RecentAssetsSection(
            assets: recentAssets.take(8).toList(),
            isExpanded: _expandedFolder == 'recent',
            onToggle: () {
              setState(() {
                _expandedFolder = _expandedFolder == 'recent' ? null : 'recent';
              });
            },
            onAssetHoverStart: _onAssetHoverStart,
            onAssetHoverEnd: _onAssetHoverEnd,
          ),

        // Type folders
        for (final type in AssetType.values)
          if (grouped.containsKey(type) && grouped[type]!.isNotEmpty)
            _AssetTypeFolder(
              type: type,
              assets: grouped[type]!,
              isExpanded: _expandedFolder == type.name || _selectedTypeFilter == type,
              onToggle: () {
                setState(() {
                  _expandedFolder = _expandedFolder == type.name ? null : type.name;
                });
              },
              onAssetHoverStart: _onAssetHoverStart,
              onAssetHoverEnd: _onAssetHoverEnd,
            ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open,
            size: 48,
            color: FluxForgeTheme.textMuted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty ? 'No matches found' : 'No audio assets',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Import audio files to get started',
            style: TextStyle(
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportButton(AutoEventBuilderProvider provider) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: ElevatedButton.icon(
        onPressed: () => _importAudioFiles(provider),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Import Audio'),
        style: ElevatedButton.styleFrom(
          backgroundColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
          foregroundColor: FluxForgeTheme.accentBlue,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importAudioFiles(AutoEventBuilderProvider provider) async {
    // Use file picker to import audio
    // For now, just show a placeholder
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Import audio files (use File > Import)'),
        backgroundColor: FluxForgeTheme.bgMid,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// =============================================================================
// COLLAPSED ICON BUTTON
// =============================================================================

class _CollapsedIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? color;

  const _CollapsedIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isActive = false,
    this.color,
  });

  @override
  State<_CollapsedIconButton> createState() => _CollapsedIconButtonState();
}

class _CollapsedIconButtonState extends State<_CollapsedIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? FluxForgeTheme.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 48,
            height: 40,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? color.withValues(alpha: 0.15)
                  : _isHovered
                      ? FluxForgeTheme.bgDeep
                      : Colors.transparent,
              border: widget.isActive
                  ? Border(
                      left: BorderSide(color: color, width: 2),
                    )
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: widget.isActive || _isHovered
                  ? color
                  : FluxForgeTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TYPE FILTER TAB
// =============================================================================

class _TypeFilterTab extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeFilterTab({
    required this.label,
    this.icon,
    this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TypeFilterTab> createState() => _TypeFilterTabState();
}

class _TypeFilterTabState extends State<_TypeFilterTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? FluxForgeTheme.textSecondary;

    return Expanded(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? color.withValues(alpha: 0.15)
                  : _isHovered
                      ? FluxForgeTheme.bgDeep
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: widget.isSelected
                  ? Border.all(color: color.withValues(alpha: 0.3))
                  : null,
            ),
            child: Center(
              child: widget.icon != null
                  ? Icon(
                      widget.icon,
                      size: 14,
                      color: widget.isSelected || _isHovered
                          ? color
                          : FluxForgeTheme.textMuted,
                    )
                  : Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.isSelected || _isHovered
                            ? FluxForgeTheme.textPrimary
                            : FluxForgeTheme.textMuted,
                        fontSize: 10,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TAG CHIP
// =============================================================================

class _TagChip extends StatefulWidget {
  final String tag;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  const _TagChip({
    required this.tag,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                : _isHovered
                    ? FluxForgeTheme.bgDeep
                    : FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: widget.isSelected
                ? Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 10,
                  color: FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.tag,
                style: TextStyle(
                  color: widget.isSelected
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// RECENT ASSETS SECTION (C.8)
// =============================================================================

class _RecentAssetsSection extends StatelessWidget {
  final List<AudioAsset> assets;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(AudioAsset) onAssetHoverStart;
  final VoidCallback onAssetHoverEnd;

  const _RecentAssetsSection({
    required this.assets,
    required this.isExpanded,
    required this.onToggle,
    required this.onAssetHoverStart,
    required this.onAssetHoverEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.history,
                  size: 14,
                  color: FluxForgeTheme.accentOrange,
                ),
                const SizedBox(width: 8),
                Text(
                  'RECENT',
                  style: TextStyle(
                    color: FluxForgeTheme.accentOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${assets.length}',
                    style: const TextStyle(
                      color: FluxForgeTheme.accentOrange,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Assets list
        if (isExpanded)
          ...assets.map((asset) => _AssetListItem(
                asset: asset,
                onHoverStart: () => onAssetHoverStart(asset),
                onHoverEnd: onAssetHoverEnd,
              )),

        // Divider
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Divider(
              color: FluxForgeTheme.borderSubtle,
              height: 1,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// ASSET TYPE FOLDER
// =============================================================================

class _AssetTypeFolder extends StatelessWidget {
  final AssetType type;
  final List<AudioAsset> assets;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(AudioAsset) onAssetHoverStart;
  final VoidCallback onAssetHoverEnd;

  const _AssetTypeFolder({
    required this.type,
    required this.assets,
    required this.isExpanded,
    required this.onToggle,
    required this.onAssetHoverStart,
    required this.onAssetHoverEnd,
  });

  Color get _typeColor {
    switch (type) {
      case AssetType.sfx:
        return FluxForgeTheme.accentBlue;
      case AssetType.music:
        return FluxForgeTheme.accentOrange;
      case AssetType.vo:
        return FluxForgeTheme.accentGreen;
      case AssetType.amb:
        return FluxForgeTheme.accentCyan;
    }
  }

  IconData get _typeIcon {
    switch (type) {
      case AssetType.sfx:
        return Icons.surround_sound;
      case AssetType.music:
        return Icons.music_note;
      case AssetType.vo:
        return Icons.mic;
      case AssetType.amb:
        return Icons.waves;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Folder header
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Icon(
                  _typeIcon,
                  size: 14,
                  color: _typeColor,
                ),
                const SizedBox(width: 8),
                Text(
                  type.displayName.toUpperCase(),
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${assets.length}',
                    style: TextStyle(
                      color: _typeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Assets list
        if (isExpanded)
          ...assets.map((asset) => _AssetListItem(
                asset: asset,
                onHoverStart: () => onAssetHoverStart(asset),
                onHoverEnd: onAssetHoverEnd,
              )),
      ],
    );
  }
}

// =============================================================================
// MULTI-ASSET DRAGGABLE (C.7)
// =============================================================================

/// Draggable wrapper that supports dragging multiple assets at once
class _MultiAssetDraggable extends StatelessWidget {
  final List<AudioAsset> assets;
  final Widget child;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  const _MultiAssetDraggable({
    required this.assets,
    required this.child,
    this.onDragStarted,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) return child;

    // Single asset: use standard DraggableAudioAsset
    if (assets.length == 1) {
      return DraggableAudioAsset(
        asset: assets.first,
        onDragStarted: onDragStarted,
        onDragEnd: onDragEnd,
        child: child,
      );
    }

    // Multiple assets: custom drag with count indicator
    return Draggable<List<AudioAsset>>(
      data: assets,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd?.call(),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.library_music,
                size: 16,
                color: FluxForgeTheme.accentBlue,
              ),
              const SizedBox(width: 8),
              Text(
                '${assets.length} assets',
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: child,
      ),
      child: child,
    );
  }
}

// =============================================================================
// ASSET LIST ITEM (Draggable)
// =============================================================================

class _AssetListItem extends StatefulWidget {
  final AudioAsset asset;
  final VoidCallback onHoverStart;
  final VoidCallback onHoverEnd;
  final bool showCheckbox;

  const _AssetListItem({
    required this.asset,
    required this.onHoverStart,
    required this.onHoverEnd,
    this.showCheckbox = false,
  });

  @override
  State<_AssetListItem> createState() => _AssetListItemState();
}

class _AssetListItemState extends State<_AssetListItem> {
  bool _isHovered = false;
  bool _isDragging = false;

  Color get _typeColor {
    switch (widget.asset.assetType) {
      case AssetType.sfx:
        return FluxForgeTheme.accentBlue;
      case AssetType.music:
        return FluxForgeTheme.accentOrange;
      case AssetType.vo:
        return FluxForgeTheme.accentGreen;
      case AssetType.amb:
        return FluxForgeTheme.accentCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AutoEventBuilderProvider>();
    final isSelected = provider.isAssetSelected(widget.asset.assetId);

    // Multi-select drag: if this asset is selected and others are too,
    // drag all selected assets together
    final assetsTooDrag = isSelected && provider.selectionCount > 1
        ? provider.selectedAssets
        : [widget.asset];

    return _MultiAssetDraggable(
      assets: assetsTooDrag,
      onDragStarted: () {
        setState(() => _isDragging = true);
        widget.onHoverEnd();
      },
      onDragEnd: () {
        setState(() => _isDragging = false);
      },
      child: GestureDetector(
        onTap: widget.showCheckbox
            ? () => provider.toggleAssetSelection(widget.asset.assetId)
            : null,
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _isHovered = true);
            widget.onHoverStart();
          },
          onExit: (_) {
            setState(() => _isHovered = false);
            widget.onHoverEnd();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? _typeColor.withValues(alpha: 0.2)
                  : _isDragging
                      ? _typeColor.withValues(alpha: 0.15)
                      : _isHovered
                          ? FluxForgeTheme.bgDeep
                          : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isSelected || _isDragging
                  ? Border.all(color: _typeColor.withValues(alpha: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                // Selection checkbox (when in multi-select mode)
                if (widget.showCheckbox)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 16,
                      color: isSelected ? _typeColor : FluxForgeTheme.textMuted,
                    ),
                  )
                else ...[
                  // Drag handle
                  Icon(
                    Icons.drag_indicator,
                    size: 14,
                    color: _isHovered ? FluxForgeTheme.textMuted : Colors.transparent,
                  ),
                  const SizedBox(width: 6),
                ],

                // Loop indicator
                if (widget.asset.isLoop)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.loop,
                      size: 12,
                      color: _typeColor.withValues(alpha: 0.7),
                    ),
                  ),

                // Asset name
                Expanded(
                  child: Text(
                    widget.asset.displayName,
                    style: TextStyle(
                      color: isSelected || _isHovered
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Duration
              Text(
                _formatDuration(widget.asset.durationMs),
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  String _formatDuration(int ms) {
    final seconds = ms / 1000;
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)}s';
    }
    final minutes = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// MINI WAVEFORM THUMBNAIL (C.5)
// =============================================================================

/// Compact waveform thumbnail for audio browser
class MiniWaveformThumbnail extends StatefulWidget {
  final String audioPath;
  final double height;
  final Color? color;
  final Color? backgroundColor;

  const MiniWaveformThumbnail({
    super.key,
    required this.audioPath,
    this.height = 32,
    this.color,
    this.backgroundColor,
  });

  @override
  State<MiniWaveformThumbnail> createState() => _MiniWaveformThumbnailState();
}

class _MiniWaveformThumbnailState extends State<MiniWaveformThumbnail> {
  List<double>? _waveformData;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  @override
  void didUpdateWidget(MiniWaveformThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPath != widget.audioPath) {
      _loadWaveform();
    }
  }

  Future<void> _loadWaveform() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Try to get from cache service first
      final cacheService = WaveformCacheService.instance;
      await cacheService.init();

      var data = await cacheService.get(widget.audioPath);

      if (data == null) {
        // Generate via FFI if not cached
        data = await _generateWaveformData();
        if (data != null && data.isNotEmpty) {
          await cacheService.put(widget.audioPath, data);
        }
      }

      if (mounted) {
        setState(() {
          _waveformData = data != null ? _downsampleWaveform(data, 64) : null;
          _isLoading = false;
          _hasError = data == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<List<double>?> _generateWaveformData() async {
    try {
      // Use NativeFFI to generate waveform peaks
      final ffi = NativeFFI.instance;
      if (!ffi.isLoaded) return null;

      // This would call the actual FFI function
      // For now, generate placeholder data based on path hash
      final hash = widget.audioPath.hashCode;
      final rng = math.Random(hash.abs());

      // Generate 256 samples (enough for thumbnail)
      return List.generate(256, (i) {
        // Create a somewhat realistic waveform shape
        final base = rng.nextDouble() * 0.6 + 0.2;
        final envelope = math.sin(i / 256.0 * math.pi) * 0.3;
        return (base + envelope).clamp(0.1, 1.0);
      });
    } catch (e) {
      return null;
    }
  }

  List<double> _downsampleWaveform(List<double> data, int targetSamples) {
    if (data.length <= targetSamples) return data;

    final result = <double>[];
    final ratio = data.length / targetSamples;

    for (int i = 0; i < targetSamples; i++) {
      final start = (i * ratio).floor();
      final end = ((i + 1) * ratio).floor().clamp(start + 1, data.length);

      // Get max value in this chunk
      var maxVal = 0.0;
      for (int j = start; j < end; j++) {
        if (data[j].abs() > maxVal) maxVal = data[j].abs();
      }
      result.add(maxVal);
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? FluxForgeTheme.bgMid;
    final fgColor = widget.color ?? FluxForgeTheme.accentCyan;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: _isLoading
            ? _buildLoadingState(fgColor)
            : _hasError || _waveformData == null
                ? _buildErrorState()
                : CustomPaint(
                    size: Size.infinite,
                    painter: _MiniWaveformPainter(
                      data: _waveformData!,
                      color: fgColor,
                    ),
                  ),
      ),
    );
  }

  Widget _buildLoadingState(Color color) {
    return Center(
      child: SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Icon(
        Icons.graphic_eq,
        size: 16,
        color: FluxForgeTheme.textMuted.withValues(alpha: 0.3),
      ),
    );
  }
}

/// Custom painter for mini waveform bars
class _MiniWaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _MiniWaveformPainter({
    required this.data,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final barCount = data.length;
    final barWidth = size.width / barCount;
    final barSpacing = barWidth * 0.2;
    final actualBarWidth = barWidth - barSpacing;
    final centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final amplitude = data[i].clamp(0.05, 1.0);
      final barHeight = amplitude * size.height * 0.8;

      final x = i * barWidth + barSpacing / 2;
      final y = centerY - barHeight / 2;

      // Draw bar as a rounded rect
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, actualBarWidth, barHeight),
        const Radius.circular(1),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_MiniWaveformPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}

// =============================================================================
// HOVER PREVIEW PANEL
// =============================================================================

class _HoverPreviewPanel extends StatelessWidget {
  final AudioAsset asset;

  const _HoverPreviewPanel({required this.asset});

  Color get _typeColor {
    switch (asset.assetType) {
      case AssetType.sfx: return FluxForgeTheme.accentBlue;
      case AssetType.music: return FluxForgeTheme.accentOrange;
      case AssetType.vo: return FluxForgeTheme.accentGreen;
      case AssetType.amb: return FluxForgeTheme.accentCyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Waveform preview
          MiniWaveformThumbnail(
            audioPath: asset.path,
            height: 40,
            color: _typeColor,
          ),
          const SizedBox(height: 6),

          // Asset info
          Row(
            children: [
              Expanded(
                child: Text(
                  asset.displayName,
                  style: const TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(asset.durationMs / 1000).toStringAsFixed(1)}s',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),

          // Tags
          if (asset.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                children: asset.tags.take(4).map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgMid,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: FluxForgeTheme.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    )).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
