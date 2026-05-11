/// Stem Routing Matrix (P10.1.2)
///
/// Visual matrix for assigning tracks to stems (batch export workflow).
///
/// Layout:
/// ```
///          │ Drums │ Bass │ Melody │ Vocals │ FX │ Amb │ Master │
/// ─────────┼───────┼──────┼────────┼────────┼────┼─────┼────────┤
/// Track 1  │  [X]  │      │        │        │    │     │  [X]   │
/// Track 2  │       │ [X]  │        │        │    │     │  [X]   │
/// Track 3  │       │      │  [X]   │        │    │     │  [X]   │
/// Bus SFX  │       │      │        │        │[X] │     │  [X]   │
/// ```
///
/// Created: 2026-02-02

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/stem_routing_provider.dart';
import '../../providers/mixer_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../lower_zone/lower_zone_types.dart';

// =============================================================================
// INTERNAL TYPES
// =============================================================================

/// Result of the multi-output conflict dialog (BUG#74).
enum _MultiOutputChoice { replace, add, cancel }

// =============================================================================
// STEM ROUTING MATRIX WIDGET
// =============================================================================

/// Visual matrix for track → stem routing.
class StemRoutingMatrix extends StatefulWidget {
  /// Accent color for highlights.
  final Color accentColor;

  /// Called when export is requested.
  final VoidCallback? onExport;

  /// Height of header row.
  final double headerHeight;

  /// Width of track name column.
  final double trackColumnWidth;

  /// Size of each routing cell.
  final double cellSize;

  /// Whether to show compact mode.
  final bool compactMode;

  const StemRoutingMatrix({
    super.key,
    this.accentColor = LowerZoneColors.dawAccent,
    this.onExport,
    this.headerHeight = 36,
    this.trackColumnWidth = 120,
    this.cellSize = 40,
    this.compactMode = false,
  });

  @override
  State<StemRoutingMatrix> createState() => _StemRoutingMatrixState();
}

class _StemRoutingMatrixState extends State<StemRoutingMatrix> {
  // UI State
  String? _hoveredTrackId;
  StemType? _hoveredStem;
  bool _showBatchMenu = false;

  // Available stems (excluding custom for now)
  final List<StemType> _stems = [
    StemType.drums,
    StemType.bass,
    StemType.melody,
    StemType.vocals,
    StemType.fx,
    StemType.ambience,
    StemType.master,
  ];

  @override
  void initState() {
    super.initState();
    // Sync tracks from MixerProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTracksFromMixer();
    });
  }

  void _syncTracksFromMixer() {
    final mixer = context.read<MixerProvider>();
    final stemRouting = context.read<StemRoutingProvider>();

    // Register tracks and buses from mixer
    final tracks = <({String id, String name, bool isTrack})>[];

    for (final channel in mixer.channels) {
      tracks.add((
        id: channel.id,
        name: channel.name,
        isTrack: channel.type == ChannelType.audio ||
            channel.type == ChannelType.instrument,
      ));
    }

    // Also add buses
    for (final bus in mixer.buses) {
      tracks.add((
        id: bus.id,
        name: bus.name,
        isTrack: false,
      ));
    }

    stemRouting.registerTracks(tracks);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StemRoutingProvider>(
      builder: (context, provider, _) {
        return Container(
          color: LowerZoneColors.bgDeep,
          child: Column(
            children: [
              _buildHeader(provider),
              Expanded(child: _buildMatrix(provider)),
              _buildFooter(provider),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(StemRoutingProvider provider) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        border: Border(
          bottom: BorderSide(color: LowerZoneColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.view_module, color: widget.accentColor, size: 16),
          const SizedBox(width: 8),
          Text(
            'STEM ROUTING MATRIX',
            style: FluxForgeTheme.dockSans(
              size: 11,
              weight: FontWeight.w600,
              color: LowerZoneColors.textPrimary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 16),

          // Stats
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${provider.trackCount} tracks · ${provider.connectionCount} routes',
              style: FluxForgeTheme.dockMono(
                size: 10,
                color: LowerZoneColors.textSecondary,
              ),
            ),
          ),
          const Spacer(),

          // Batch actions
          _buildBatchActionsDropdown(provider),
          const SizedBox(width: 8),

          // Clear all
          _buildActionButton(
            'Clear All',
            Icons.clear_all,
            () => provider.clearAllRouting(),
            isDestructive: true,
          ),
          const SizedBox(width: 8),

          // Refresh from mixer
          _buildActionButton(
            'Sync Mixer',
            Icons.sync,
            _syncTracksFromMixer,
          ),
        ],
      ),
    );
  }

  Widget _buildBatchActionsDropdown(StemRoutingProvider provider) {
    return PopupMenuButton<String>(
      tooltip: 'Batch auto-detect actions',
      offset: const Offset(0, 36),
      color: LowerZoneColors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: LowerZoneColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_fix_high, size: 14, color: widget.accentColor),
            const SizedBox(width: 6),
            Text(
              'Auto-Detect',
              style: FluxForgeTheme.dockSans(
                size: 10,
                weight: FontWeight.w600,
                color: widget.accentColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: widget.accentColor),
          ],
        ),
      ),
      onSelected: (value) {
        switch (value) {
          case 'drums':
            provider.autoSelectDrums();
          case 'bass':
            provider.autoSelectBass();
          case 'melody':
            provider.autoSelectMelody();
          case 'vocals':
            provider.autoSelectVocals();
          case 'fx':
            provider.autoSelectFx();
          case 'ambience':
            provider.autoSelectAmbience();
          case 'all':
            provider.autoDetectAll();
          case 'master':
            provider.selectAllToMaster();
        }
      },
      itemBuilder: (context) => [
        _buildMenuItem('all', 'Auto-Detect All', Icons.auto_awesome),
        const PopupMenuDivider(),
        _buildMenuItem('drums', 'Select Drums', Icons.circle,
            color: StemType.drums.color),
        _buildMenuItem('bass', 'Select Bass', Icons.graphic_eq,
            color: StemType.bass.color),
        _buildMenuItem('melody', 'Select Melody', Icons.music_note,
            color: StemType.melody.color),
        _buildMenuItem('vocals', 'Select Vocals', Icons.mic,
            color: StemType.vocals.color),
        _buildMenuItem('fx', 'Select FX', Icons.auto_awesome,
            color: StemType.fx.color),
        _buildMenuItem('ambience', 'Select Ambience', Icons.cloud,
            color: StemType.ambience.color),
        const PopupMenuDivider(),
        _buildMenuItem('master', 'All → Master', Icons.speaker,
            color: StemType.master.color),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(String value, String label, IconData icon,
      {Color? color}) {
    return PopupMenuItem<String>(
      value: value,
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? LowerZoneColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: FluxForgeTheme.dockSans(
              size: 11,
              color: LowerZoneColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap,
      {bool isDestructive = false}) {
    final color = isDestructive ? LowerZoneColors.error : LowerZoneColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: FluxForgeTheme.dockSans(
                size: 9,
                weight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MATRIX
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMatrix(StemRoutingProvider provider) {
    final routing = provider.allRouting;
    if (routing.isEmpty) {
      return _buildEmptyState();
    }

    // Separate tracks and buses
    final tracks = routing.where((r) => r.isTrack).toList();
    final buses = routing.where((r) => !r.isTrack).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row (stem names)
              _buildStemHeaderRow(provider),
              const SizedBox(height: 4),

              // Tracks section
              if (tracks.isNotEmpty) ...[
                _buildSectionLabel('TRACKS', Icons.audiotrack),
                ...tracks.map((r) => _buildTrackRow(r, provider)),
                const SizedBox(height: 8),
              ],

              // Buses section
              if (buses.isNotEmpty) ...[
                _buildSectionLabel('BUSES', Icons.shuffle),
                ...buses.map((r) => _buildTrackRow(r, provider)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStemHeaderRow(StemRoutingProvider provider) {
    return Row(
      children: [
        // Corner cell (track name column header)
        Container(
          width: widget.trackColumnWidth,
          height: widget.headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: LowerZoneColors.bgMid,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              'TRACK → STEM',
              style: FluxForgeTheme.dockSans(
                size: 9,
                weight: FontWeight.w600,
                color: LowerZoneColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),

        // Stem headers
        ..._stems.map((stem) => _buildStemHeader(stem, provider)),
      ],
    );
  }

  Widget _buildStemHeader(StemType stem, StemRoutingProvider provider) {
    final isHovered = _hoveredStem == stem;
    final trackCount = provider.getTrackCountForStem(stem);
    final hasRouting = trackCount > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredStem = stem),
      onExit: (_) => setState(() => _hoveredStem = null),
      child: GestureDetector(
        onTap: () => _showStemContextMenu(stem, provider),
        child: Container(
          width: widget.cellSize,
          height: widget.headerHeight,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isHovered
                ? stem.color.withValues(alpha: 0.2)
                : hasRouting
                    ? stem.color.withValues(alpha: 0.1)
                    : LowerZoneColors.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isHovered
                  ? stem.color
                  : hasRouting
                      ? stem.color.withValues(alpha: 0.5)
                      : LowerZoneColors.borderSubtle,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stem.icon, size: 10, color: stem.color),
              const SizedBox(height: 2),
              Text(
                stem.code,
                style: FluxForgeTheme.dockSans(
                  size: 8,
                  weight: FontWeight.w600,
                  color: isHovered || hasRouting ? stem.color : LowerZoneColors.textSecondary,
                ),
              ),
              if (hasRouting)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: stem.color.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '$trackCount',
                    style: FluxForgeTheme.dockMono(
                      size: 7,
                      weight: FontWeight.bold,
                      color: stem.color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: LowerZoneColors.textTertiary),
          const SizedBox(width: 6),
          Text(
            label,
            style: FluxForgeTheme.dockSans(
              size: 9,
              weight: FontWeight.w600,
              color: LowerZoneColors.textTertiary,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRow(StemRouting routing, StemRoutingProvider provider) {
    final isHovered = _hoveredTrackId == routing.trackId;

    return Row(
      children: [
        // Track name
        MouseRegion(
          onEnter: (_) => setState(() => _hoveredTrackId = routing.trackId),
          onExit: (_) => setState(() => _hoveredTrackId = null),
          child: Container(
            width: widget.trackColumnWidth,
            height: widget.cellSize,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isHovered
                  ? LowerZoneColors.bgSurface
                  : LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isHovered
                    ? widget.accentColor.withValues(alpha: 0.5)
                    : LowerZoneColors.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                // Type indicator
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: routing.isTrack
                        ? widget.accentColor
                        : LowerZoneColors.success,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    routing.trackName,
                    style: FluxForgeTheme.dockSans(
                      size: 10,
                      weight: FontWeight.w500,
                      color: isHovered
                          ? LowerZoneColors.textPrimary
                          : LowerZoneColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Route count badge
                if (routing.stems.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${routing.stems.length}',
                      style: FluxForgeTheme.dockMono(
                        size: 8,
                        weight: FontWeight.bold,
                        color: widget.accentColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),

        // Routing cells
        ..._stems.map((stem) => _buildRoutingCell(routing, stem, provider)),
      ],
    );
  }

  /// Handles a tap on a routing cell. Fixes BUG#74.
  ///
  /// Toggling OFF is always immediate. When toggling ON and the track already
  /// has a final output assigned to a different stem column, a dialog warns the
  /// user and offers two choices:
  ///   • Replace — clears all existing stem routes for this track, then routes
  ///     to the newly selected stem.
  ///   • Add — allows multi-stem routing (intentional; the track will be
  ///     exported into every assigned stem).
  void _onCellTap(
      StemRouting routing, StemType stem, StemRoutingProvider provider) {
    final isCurrentlyRouted = routing.stems.contains(stem);

    // Toggling OFF: no dialog needed.
    if (isCurrentlyRouted) {
      provider.toggleStemRouting(routing.trackId, stem);
      return;
    }

    // Toggling ON: check whether the track already has another stem assigned.
    final existingStems =
        routing.stems.where((s) => s != stem).toList(growable: false);
    if (existingStems.isEmpty) {
      // No conflict — assign directly.
      provider.toggleStemRouting(routing.trackId, stem);
      return;
    }

    // Conflict — ask the user whether to replace or add.
    final existingNames =
        existingStems.map((s) => s.label).join(', ');
    showDialog<_MultiOutputChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: LowerZoneColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: stem.color.withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: LowerZoneColors.warning, size: 20),
            const SizedBox(width: 8),
            Text(
              'Multiple Stem Outputs',
              style: FluxForgeTheme.dockSans(
                size: 14,
                weight: FontWeight.w600,
                color: LowerZoneColors.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          '"${routing.trackName}" is already routed to: $existingNames.\n\n'
          'Do you want to replace that assignment with ${stem.label}, '
          'or add ${stem.label} as an additional output?',
          style: FluxForgeTheme.dockSans(
            size: 12,
            color: LowerZoneColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_MultiOutputChoice.cancel),
            child: Text(
              'Cancel',
              style: FluxForgeTheme.dockSans(
                color: LowerZoneColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_MultiOutputChoice.add),
            child: Text(
              'Add',
              style: FluxForgeTheme.dockSans(
                color: stem.color,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: stem.color.withValues(alpha: 0.2),
              foregroundColor: stem.color,
              elevation: 0,
            ),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_MultiOutputChoice.replace),
            child: const Text('Replace'),
          ),
        ],
      ),
    ).then((choice) {
      if (choice == null || choice == _MultiOutputChoice.cancel) return;
      if (choice == _MultiOutputChoice.replace) {
        // Clear all existing stem assignments for this track, then assign
        // only the newly selected stem.
        provider.setStemRouting(routing.trackId, {stem});
      } else {
        // Add: keep existing assignments and add the new stem.
        provider.addStemToTrack(routing.trackId, stem);
      }
    });
  }

  Widget _buildRoutingCell(
      StemRouting routing, StemType stem, StemRoutingProvider provider) {
    final isRouted = routing.stems.contains(stem);
    final isHovered =
        _hoveredTrackId == routing.trackId || _hoveredStem == stem;

    return GestureDetector(
      onTap: () => _onCellTap(routing, stem, provider),
      child: MouseRegion(
        onEnter: (_) => setState(() {
          _hoveredTrackId = routing.trackId;
          _hoveredStem = stem;
        }),
        onExit: (_) => setState(() {
          _hoveredTrackId = null;
          _hoveredStem = null;
        }),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.cellSize,
          height: widget.cellSize,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isRouted
                ? stem.color.withValues(alpha: 0.3)
                : isHovered
                    ? LowerZoneColors.bgSurface
                    : LowerZoneColors.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isRouted
                  ? stem.color
                  : isHovered
                      ? stem.color.withValues(alpha: 0.5)
                      : LowerZoneColors.borderSubtle,
              width: isRouted ? 2 : 1,
            ),
            boxShadow: isRouted
                ? [
                    BoxShadow(
                      color: stem.color.withValues(alpha: 0.3),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: isRouted
              ? Center(
                  child: Icon(
                    Icons.check,
                    size: widget.cellSize * 0.45,
                    color: stem.color,
                  ),
                )
              : isHovered
                  ? Center(
                      child: Icon(
                        Icons.add,
                        size: widget.cellSize * 0.35,
                        color: stem.color.withValues(alpha: 0.5),
                      ),
                    )
                  : null,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.view_module_outlined,
            size: 48,
            color: LowerZoneColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            'No tracks registered',
            style: FluxForgeTheme.dockSans(
              size: 14,
              weight: FontWeight.w500,
              color: LowerZoneColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _syncTracksFromMixer,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: widget.accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync, size: 14, color: widget.accentColor),
                  const SizedBox(width: 6),
                  Text(
                    'Sync from Mixer',
                    style: FluxForgeTheme.dockSans(
                      size: 11,
                      weight: FontWeight.w500,
                      color: widget.accentColor,
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

  void _showStemContextMenu(StemType stem, StemRoutingProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LowerZoneColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: stem.color.withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            Icon(stem.icon, color: stem.color, size: 20),
            const SizedBox(width: 8),
            Text(
              stem.label,
              style: FluxForgeTheme.dockSans(
                size: 14,
                weight: FontWeight.w600,
                color: stem.color,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stem.description,
              style: FluxForgeTheme.dockSans(
                size: 11,
                color: LowerZoneColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${provider.getTrackCountForStem(stem)} tracks assigned',
              style: FluxForgeTheme.dockMono(
                size: 11,
                weight: FontWeight.w500,
                color: stem.color,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              provider.clearStemRouting(stem);
              Navigator.pop(context);
            },
            child: Text(
              'Clear All',
              style: FluxForgeTheme.dockSans(
                color: LowerZoneColors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOOTER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFooter(StemRoutingProvider provider) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        border: Border(
          top: BorderSide(color: LowerZoneColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Legend
          ..._stems.take(5).map((stem) => _buildLegendItem(stem)),
          const SizedBox(width: 8),
          Text(
            '+${_stems.length - 5} more',
            style: FluxForgeTheme.dockSans(
              size: 9,
              color: LowerZoneColors.textTertiary,
            ),
          ),
          const Spacer(),

          // Export button
          if (widget.onExport != null && provider.hasRouting)
            GestureDetector(
              onTap: widget.onExport,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.accentColor,
                      widget.accentColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.upload, size: 14, color: Colors.black),
                    const SizedBox(width: 6),
                    Text(
                      'EXPORT STEMS',
                      style: FluxForgeTheme.dockSans(
                        size: 10,
                        weight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: 0.5,
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

  Widget _buildLegendItem(StemType stem) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: stem.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            stem.label,
            style: FluxForgeTheme.dockSans(
              size: 9,
              color: LowerZoneColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
