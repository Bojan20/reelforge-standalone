/// Variant Group Panel
///
/// UI for managing audio variant groups and A/B comparison.
///
/// Features:
/// - Create groups by dragging multiple audio files
/// - A/B comparison between variants
/// - Global replace variant in all events
/// - Visual diff indicators (LUFS, duration, etc.)
/// - Quick switch active variant
///
/// Task: P1-01 Variant Group Panel UI

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/audio_variant_group.dart';
import '../../services/audio_variant_service.dart';
import '../../services/audio_playback_service.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../slot_lab/audio_ab_comparison.dart';

class VariantGroupPanel extends StatefulWidget {
  const VariantGroupPanel({super.key});

  @override
  State<VariantGroupPanel> createState() => _VariantGroupPanelState();
}

class _VariantGroupPanelState extends State<VariantGroupPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _expandedGroupId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioVariantService>(
      builder: (context, service, _) {
        final groups = _filteredGroups(service.groups);

        return Container(
          color: const Color(0xFF0D0D10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, service),
              const Divider(height: 1, color: Color(0xFF2A2A35)),
              Expanded(
                child: groups.isEmpty
                    ? _buildEmptyState(context)
                    : _buildGroupList(context, service, groups),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AudioVariantService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF16161C),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, size: 20, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          const Text(
            'Audio Variants',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${service.groups.length}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.accentBlue,
              ),
            ),
          ),
          const Spacer(),
          // Search
          SizedBox(
            width: 200,
            height: 32,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(fontSize: 11, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search groups...',
                hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0D0D10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Create group button
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Group', style: TextStyle(fontSize: 11)),
            onPressed: () => _showCreateGroupDialog(context, service),
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentGreen,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.compare_arrows, size: 64, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(
            'No Variant Groups',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a group to compare audio variants',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList(
    BuildContext context,
    AudioVariantService service,
    List<AudioVariantGroup> groups,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final group = groups[index];
        final isExpanded = _expandedGroupId == group.id;

        return _buildGroupCard(context, service, group, isExpanded);
      },
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
    bool isExpanded,
  ) {
    final activeVariant = group.activeVariant;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() {
              _expandedGroupId = isExpanded ? null : group.id;
            }),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 8),
                  // Color indicator (if set)
                  if (group.color != null) ...[
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: group.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (group.description != null)
                          Text(
                            group.description!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white38,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Variant count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentPurple.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${group.variants.length} variants',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: FluxForgeTheme.accentPurple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Active variant indicator
                  if (activeVariant != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 12,
                            color: FluxForgeTheme.accentGreen,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            activeVariant.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: FluxForgeTheme.accentGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  // Actions
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18, color: Colors.white54),
                    onSelected: (value) => _handleGroupAction(context, service, group, value),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFF2A2A35)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Variants list
                  ...group.variants.map((variant) => _buildVariantRow(
                        context,
                        service,
                        group,
                        variant,
                      )),

                  const SizedBox(height: 12),

                  // Actions row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // A/B Compare button
                      if (group.variants.length >= 2)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.compare, size: 14),
                          label: const Text('A/B Compare', style: TextStyle(fontSize: 11)),
                          onPressed: () => _showABComparison(context, service, group),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: FluxForgeTheme.accentBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),

                      // Add variant button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add Variant', style: TextStyle(fontSize: 11)),
                        onPressed: () => _showAddVariantDialog(context, service, group),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2A35),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),

                      // Global replace button
                      if (activeVariant != null)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.find_replace, size: 14),
                          label: const Text('Replace All', style: TextStyle(fontSize: 11)),
                          onPressed: () => _showReplaceDialog(context, service, group),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: FluxForgeTheme.accentOrange,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantRow(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
    AudioVariant variant,
  ) {
    final isActive = group.activeVariantId == variant.id;
    final fileName = variant.audioPath.split('/').last;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isActive
            ? FluxForgeTheme.accentGreen.withOpacity(0.1)
            : const Color(0xFF0D0D10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? FluxForgeTheme.accentGreen.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Active indicator
          Icon(
            isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 16,
            color: isActive ? FluxForgeTheme.accentGreen : Colors.white38,
          ),
          const SizedBox(width: 8),
          // Label
          Text(
            variant.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? FluxForgeTheme.accentGreen : Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          // File name
          Expanded(
            child: Text(
              fileName,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Metadata badges
          if (variant.lufs != null)
            _buildMetadataBadge('${variant.lufs!.toStringAsFixed(1)} LUFS'),
          if (variant.duration != null)
            _buildMetadataBadge('${variant.duration!.toStringAsFixed(1)}s'),
          const SizedBox(width: 8),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play button
              IconButton(
                icon: const Icon(Icons.play_arrow, size: 16),
                onPressed: () => _playVariant(variant),
                color: FluxForgeTheme.accentBlue,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Play',
              ),
              // Set active button
              if (!isActive)
                IconButton(
                  icon: const Icon(Icons.check, size: 16),
                  onPressed: () => service.setActiveVariant(group.id, variant.id),
                  color: Colors.white54,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Set Active',
                ),
              // Remove button
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => service.removeVariantFromGroup(group.id, variant.id),
                color: Colors.red.withOpacity(0.7),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Remove',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          color: Colors.white38,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  List<AudioVariantGroup> _filteredGroups(List<AudioVariantGroup> groups) {
    if (_searchQuery.isEmpty) return groups;

    final query = _searchQuery.toLowerCase();
    return groups.where((g) {
      return g.name.toLowerCase().contains(query) ||
          (g.description?.toLowerCase().contains(query) ?? false) ||
          g.variants.any((v) => v.label.toLowerCase().contains(query));
    }).toList();
  }

  void _playVariant(AudioVariant variant) {
    AudioPlaybackService.instance.previewFile(
      variant.audioPath,
      source: PlaybackSource.browser,
    );
  }

  void _handleGroupAction(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
    String action,
  ) {
    switch (action) {
      case 'rename':
        _showRenameDialog(context, service, group);
        break;
      case 'delete':
        _confirmDelete(context, service, group);
        break;
    }
  }

  // ============================================================================
  // DIALOGS
  // ============================================================================

  void _showCreateGroupDialog(BuildContext context, AudioVariantService service) {
    // TODO: Implement file picker for multiple audio files
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create group: Use drag-drop or file picker (TODO)')),
    );
  }

  void _showAddVariantDialog(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
  ) {
    // TODO: Implement file picker for single audio file
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add variant: Use file picker (TODO)')),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
  ) {
    final controller = TextEditingController(text: group.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('Rename Group', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Group name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text('Rename'),
            onPressed: () {
              service.renameGroup(group.id, controller.text);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('Delete Group?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${group.name}" and all its variants?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
            onPressed: () {
              service.deleteGroup(group.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showABComparison(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
  ) {
    if (group.variants.length < 2) return;

    final variantA = group.variants[0];
    final variantB = group.variants[1];

    AudioABComparison.show(
      context,
      audioPathA: variantA.audioPath,
      audioPathB: variantB.audioPath,
      labelA: variantA.label,
      labelB: variantB.label,
    ).then((result) {
      if (result == null) return;

      if (result == 'swap') {
        // Swap A and B
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Swap functionality: TODO')),
        );
      } else {
        // Set selected variant as active
        final selectedVariant =
            group.variants.where((v) => v.audioPath == result).firstOrNull;
        if (selectedVariant != null) {
          service.setActiveVariant(group.id, selectedVariant.id);
        }
      }
    });
  }

  void _showReplaceDialog(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
  ) {
    final activeVariant = group.activeVariant;
    if (activeVariant == null) return;

    final otherVariants = group.variants.where((v) => v.id != activeVariant.id).toList();
    if (otherVariants.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('Replace All Occurrences', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Replace all uses of:',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 8),
            Text(
              activeVariant.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.accentGreen,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'With:',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 8),
            ...otherVariants.map((v) => ListTile(
                  title: Text(v.label, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    v.audioPath.split('/').last,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _performGlobalReplace(context, service, group, activeVariant, v);
                  },
                )),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _performGlobalReplace(
    BuildContext context,
    AudioVariantService service,
    AudioVariantGroup group,
    AudioVariant oldVariant,
    AudioVariant newVariant,
  ) {
    final middlewareProvider = context.read<MiddlewareProvider>();

    service.replaceVariantGlobally(
      groupId: group.id,
      oldVariantId: oldVariant.id,
      newVariantId: newVariant.id,
      replaceCallback: (oldPath, newPath) async {
        // Replace in all middleware events
        final events = middlewareProvider.compositeEvents;
        for (final event in events) {
          for (final layer in event.layers) {
            if (layer.audioPath == oldPath) {
              middlewareProvider.updateEventLayer(
                event.id,
                layer.copyWith(audioPath: newPath),
              );
            }
          }
        }
      },
    ).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Replaced ${oldVariant.label} with ${newVariant.label}'),
          backgroundColor: FluxForgeTheme.accentGreen,
        ),
      );
    });
  }
}
