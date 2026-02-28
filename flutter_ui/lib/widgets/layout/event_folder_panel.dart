/// Event Folder Panel — DAW left zone section showing SlotLab events
///
/// Displays read-only event folders with their layer tracks.
/// Layers can be dragged into the DAW timeline for editing.
/// Structure owned by SlotLab; audio params bidirectional.
///
/// See: .claude/architecture/UNIFIED_TRACK_GRAPH.md
library;

import 'package:flutter/material.dart';
import '../../models/event_folder_models.dart';
import '../../theme/fluxforge_theme.dart';

class EventFolderPanel extends StatelessWidget {
  final List<EventFolder> folders;
  final VoidCallback? onToggleCollapsed;
  final void Function(String eventId)? onFolderToggle;
  final void Function(String eventId, String layerId)? onLayerTap;
  final void Function(String eventId)? onOpenInSlotLab;
  final bool isCollapsed;

  const EventFolderPanel({
    super.key,
    this.folders = const [],
    this.onToggleCollapsed,
    this.onFolderToggle,
    this.onLayerTap,
    this.onOpenInSlotLab,
    this.isCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        if (!isCollapsed) _buildFolderList(),
        const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
      ],
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final layerCount = folders.fold<int>(0, (sum, f) => sum + f.layers.length);

    return GestureDetector(
      onTap: onToggleCollapsed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
          border: const Border(
            bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isCollapsed ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: FluxForgeTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.link_rounded,
              size: 12,
              color: Color(0xFFFF9850),
            ),
            const SizedBox(width: 4),
            const Text(
              'EVENT FOLDERS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF9850),
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Text(
              '${folders.length} events / $layerCount layers',
              style: const TextStyle(
                fontSize: 8,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Folder List ───────────────────────────────────────────────────────────

  Widget _buildFolderList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: folders.length,
        itemBuilder: (context, index) => _EventFolderItem(
          folder: folders[index],
          onToggle: () => onFolderToggle?.call(folders[index].eventId),
          onLayerTap: (layerId) =>
              onLayerTap?.call(folders[index].eventId, layerId),
          onOpenInSlotLab: () =>
              onOpenInSlotLab?.call(folders[index].eventId),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT FOLDER ITEM
// ═══════════════════════════════════════════════════════════════════════════════

class _EventFolderItem extends StatelessWidget {
  final EventFolder folder;
  final VoidCallback? onToggle;
  final void Function(String layerId)? onLayerTap;
  final VoidCallback? onOpenInSlotLab;

  const _EventFolderItem({
    required this.folder,
    this.onToggle,
    this.onLayerTap,
    this.onOpenInSlotLab,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Folder header
        GestureDetector(
          onTap: onToggle,
          onSecondaryTap: onOpenInSlotLab,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: folder.hasLayersInTimeline
                  ? folder.color.withValues(alpha: 0.08)
                  : null,
            ),
            child: Row(
              children: [
                // Expand/collapse
                Icon(
                  folder.isCollapsed
                      ? Icons.chevron_right
                      : Icons.expand_more,
                  size: 13,
                  color: FluxForgeTheme.textTertiary,
                ),
                // Color bar
                Container(
                  width: 3,
                  height: 14,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: folder.color,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                // Category badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: folder.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                    border:
                        Border.all(color: folder.color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    folder.category.toUpperCase(),
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: folder.color,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                // Event name
                Expanded(
                  child: Text(
                    folder.name,
                    style: const TextStyle(
                      fontSize: 11,
                      color: FluxForgeTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Variant groups badge
                if (folder.variantGroups.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9C27B0).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      '${folder.variantGroups.length}V',
                      style: const TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFCE93D8),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                // Conditional layers indicator
                if (folder.conditionalLayers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.filter_alt_outlined,
                      size: 10,
                      color: const Color(0xFFFF9800).withValues(alpha: 0.7),
                    ),
                  ),
                // Crossfade indicator
                if (folder.crossfade.fadeInMs > 0 || folder.crossfade.fadeOutMs > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.swap_horiz,
                      size: 10,
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.7),
                    ),
                  ),
                // Layer count
                Text(
                  '${folder.layers.length}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: FluxForgeTheme.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
                // Lock icon (read-only structure)
                const Icon(
                  Icons.lock_outline,
                  size: 10,
                  color: FluxForgeTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),

        // Layer tracks
        if (!folder.isCollapsed)
          ...folder.layers.map((layer) => _LayerItem(
                layer: layer,
                folderColor: folder.color,
                onTap: () => onLayerTap?.call(layer.layerId),
              )),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER ITEM — draggable audio track within event folder
// ═══════════════════════════════════════════════════════════════════════════════

class _LayerItem extends StatelessWidget {
  final EventLayerRef layer;
  final Color folderColor;
  final VoidCallback? onTap;

  const _LayerItem({
    required this.layer,
    required this.folderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isInTimeline = layer.isInTimeline;

    return Draggable<EventLayerRef>(
      data: layer,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: folderColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: folderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audiotrack, size: 12, color: folderColor),
              const SizedBox(width: 4),
              Text(
                layer.name,
                style: TextStyle(
                  fontSize: 10,
                  color: folderColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(left: 28, right: 8, top: 3, bottom: 3),
          decoration: BoxDecoration(
            color: isInTimeline
                ? folderColor.withValues(alpha: 0.05)
                : null,
          ),
          child: Row(
            children: [
              // Audio icon
              Icon(
                Icons.audiotrack,
                size: 11,
                color: isInTimeline
                    ? folderColor
                    : FluxForgeTheme.textTertiary,
              ),
              const SizedBox(width: 5),
              // Layer name
              Expanded(
                child: Text(
                  layer.name,
                  style: TextStyle(
                    fontSize: 10,
                    color: isInTimeline
                        ? FluxForgeTheme.textPrimary
                        : FluxForgeTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Shared track indicator (×N events)
              if (layer.isShared)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: const Color(0xFF2196F3).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '\u00d7${layer.sharedCount}',
                    style: const TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64B5F6),
                    ),
                  ),
                ),
              // Variant group badge
              if (layer.variantGroup != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9C27B0).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    layer.variantGroup!,
                    style: const TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFCE93D8),
                    ),
                  ),
                ),
              // Conditional layer indicator
              if (layer.isConditional)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(
                    Icons.filter_alt_outlined,
                    size: 9,
                    color: const Color(0xFFFF9800).withValues(alpha: 0.7),
                  ),
                ),
              // Mute indicator
              if (layer.muted)
                const Padding(
                  padding: EdgeInsets.only(left: 3),
                  child: Text(
                    'M',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF9040),
                    ),
                  ),
                ),
              // Solo indicator
              if (layer.solo)
                const Padding(
                  padding: EdgeInsets.only(left: 3),
                  child: Text(
                    'S',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                ),
              // Timeline indicator
              if (isInTimeline)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(
                    Icons.timeline,
                    size: 10,
                    color: folderColor.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
