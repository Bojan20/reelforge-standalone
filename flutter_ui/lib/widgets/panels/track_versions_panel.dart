/// Track Versions Panel - Cubase-style track playlists UI
///
/// Features:
/// - Version list per track
/// - Quick A/B comparison
/// - Duplicate/rename/delete versions
/// - Color coding

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/track_versions_provider.dart';
import '../../theme/fluxforge_theme.dart';

class TrackVersionsPanel extends StatefulWidget {
  const TrackVersionsPanel({super.key});

  @override
  State<TrackVersionsPanel> createState() => _TrackVersionsPanelState();
}

class _TrackVersionsPanelState extends State<TrackVersionsPanel> {
  int? _selectedTrackId;

  static const _accentColor = Color(0xFF9B59B6);

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackVersionsProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              // Header
              _buildHeader(provider),

              // Main content
              Expanded(
                child: Row(
                  children: [
                    // Track list (left)
                    SizedBox(
                      width: 180,
                      child: _buildTrackList(provider),
                    ),

                    Container(width: 1, color: FluxForgeTheme.borderSubtle),

                    // Version list (center)
                    Expanded(
                      child: _buildVersionList(provider),
                    ),

                    Container(width: 1, color: FluxForgeTheme.borderSubtle),

                    // Version details (right)
                    SizedBox(
                      width: 200,
                      child: _buildVersionDetails(provider),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(TrackVersionsProvider provider) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers, size: 16, color: _accentColor),
          const SizedBox(width: 8),
          Text(
            'Track Versions',
            style: FluxForgeTheme.label.copyWith(
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),

          const SizedBox(width: 16),

          // Enable toggle
          _buildEnableToggle(provider),

          const Spacer(),

          // Show version lane toggle
          _buildToggleButton(
            'Show Lane',
            Icons.view_stream,
            provider.showVersionLane,
            () => provider.setShowVersionLane(!provider.showVersionLane),
          ),
        ],
      ),
    );
  }

  Widget _buildEnableToggle(TrackVersionsProvider provider) {
    return GestureDetector(
      onTap: provider.toggleEnabled,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: provider.enabled
              ? _accentColor.withValues(alpha: 0.15)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: provider.enabled ? _accentColor : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              provider.enabled ? Icons.check_circle : Icons.circle_outlined,
              size: 12,
              color: provider.enabled ? _accentColor : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              provider.enabled ? 'Enabled' : 'Disabled',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: provider.enabled ? _accentColor : FluxForgeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(String label, IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? _accentColor.withValues(alpha: 0.15)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? _accentColor : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isActive ? _accentColor : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? _accentColor : FluxForgeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackList(TrackVersionsProvider provider) {
    final trackIds = provider.tracksWithVersions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                'TRACKS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${trackIds.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _accentColor,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: trackIds.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No tracks with versions\n\nRight-click a track to create a version',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: trackIds.length,
                  itemBuilder: (context, index) {
                    final trackId = trackIds[index];
                    final container = provider.getContainer(trackId);
                    final isSelected = _selectedTrackId == trackId;
                    final versionCount = container?.versions.length ?? 0;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedTrackId = trackId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _accentColor.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected ? _accentColor : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.music_note,
                              size: 14,
                              color: isSelected
                                  ? _accentColor
                                  : FluxForgeTheme.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Track $trackId',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected
                                      ? _accentColor
                                      : FluxForgeTheme.textPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: FluxForgeTheme.bgDeep,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$versionCount',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: FluxForgeTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Create version for selected track
        Container(
          padding: const EdgeInsets.all(8),
          child: _buildActionButton(
            'New Track Version',
            Icons.add,
            _selectedTrackId == null
                ? null
                : () => provider.createVersion(_selectedTrackId!),
          ),
        ),
      ],
    );
  }

  Widget _buildVersionList(TrackVersionsProvider provider) {
    if (_selectedTrackId == null) {
      return Center(
        child: Text(
          'Select a track to view versions',
          style: TextStyle(
            fontSize: 12,
            color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    final versions = provider.getVersions(_selectedTrackId!);
    final activeVersion = provider.getActiveVersion(_selectedTrackId!);
    final compareVersion = provider.getCompareVersion(_selectedTrackId!);
    final isComparing = provider.isComparing(_selectedTrackId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with actions
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                'VERSIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),

              // Compare mode toggle
              if (versions.length > 1)
                _buildToggleButton(
                  'Compare',
                  Icons.compare,
                  isComparing,
                  () {
                    if (isComparing) {
                      provider.stopCompare(_selectedTrackId!);
                    } else if (versions.length > 1) {
                      final otherVersion = versions.firstWhere(
                        (v) => v.id != activeVersion?.id,
                      );
                      provider.startCompare(_selectedTrackId!, otherVersion.id);
                    }
                  },
                ),
            ],
          ),
        ),

        // Version cards
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: versions.length,
            itemBuilder: (context, index) {
              final version = versions[index];
              final isActive = version.id == activeVersion?.id;
              final isCompare = isComparing && version.id == compareVersion?.id;

              return _buildVersionCard(
                provider,
                version,
                isActive,
                isCompare,
              );
            },
          ),
        ),

        // Quick actions footer
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSmallButton(
                'New',
                Icons.add,
                () => provider.createVersion(_selectedTrackId!),
              ),
              const SizedBox(width: 8),
              _buildSmallButton(
                'Duplicate',
                Icons.copy,
                activeVersion == null
                    ? null
                    : () => provider.duplicateVersion(_selectedTrackId!, activeVersion.id),
              ),
              const SizedBox(width: 8),
              _buildSmallButton(
                'Delete',
                Icons.delete_outline,
                activeVersion == null || versions.length <= 1
                    ? null
                    : () => provider.deleteVersion(_selectedTrackId!, activeVersion.id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVersionCard(
    TrackVersionsProvider provider,
    TrackVersion version,
    bool isActive,
    bool isCompare,
  ) {
    final borderColor = isActive
        ? _accentColor
        : isCompare
            ? FluxForgeTheme.accentOrange
            : Colors.transparent;

    return GestureDetector(
      onTap: () => provider.activateVersion(_selectedTrackId!, version.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? _accentColor.withValues(alpha: 0.1)
              : isCompare
                  ? FluxForgeTheme.accentOrange.withValues(alpha: 0.1)
                  : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: isActive || isCompare ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Color indicator
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: version.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),

                // Name and badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              version.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                color: FluxForgeTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (isActive)
                            _buildBadge('Active', _accentColor),
                          if (isCompare)
                            _buildBadge('Compare', FluxForgeTheme.accentOrange),
                          if (version.isLocked)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.lock,
                                size: 12,
                                color: FluxForgeTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${version.clips.length} clips',
                        style: TextStyle(
                          fontSize: 10,
                          color: FluxForgeTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Actions menu
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 16,
                    color: FluxForgeTheme.textSecondary,
                  ),
                  color: FluxForgeTheme.bgElevated,
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    const PopupMenuItem(value: 'lock', child: Text('Toggle Lock')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                  onSelected: (action) {
                    switch (action) {
                      case 'rename':
                        _showRenameDialog(provider, version);
                        break;
                      case 'duplicate':
                        provider.duplicateVersion(_selectedTrackId!, version.id);
                        break;
                      case 'lock':
                        provider.toggleVersionLocked(_selectedTrackId!, version.id);
                        break;
                      case 'delete':
                        provider.deleteVersion(_selectedTrackId!, version.id);
                        break;
                    }
                  },
                ),
              ],
            ),

            // Description if present
            if (version.description != null && version.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                version.description!,
                style: TextStyle(
                  fontSize: 10,
                  color: FluxForgeTheme.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildVersionDetails(TrackVersionsProvider provider) {
    if (_selectedTrackId == null) {
      return const SizedBox();
    }

    final activeVersion = provider.getActiveVersion(_selectedTrackId!);
    if (activeVersion == null) {
      return Center(
        child: Text(
          'No version selected',
          style: TextStyle(
            fontSize: 11,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Text(
            'VERSION DETAILS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _buildDetailRow('Name', activeVersion.name),
              _buildDetailRow('Clips', '${activeVersion.clips.length}'),
              _buildDetailRow('Type', activeVersion.contentType.name),
              _buildDetailRow(
                'Created',
                _formatDate(activeVersion.createdAt),
              ),
              _buildDetailRow(
                'Modified',
                _formatDate(activeVersion.modifiedAt),
              ),
              _buildDetailRow(
                'Locked',
                activeVersion.isLocked ? 'Yes' : 'No',
              ),

              const SizedBox(height: 16),

              // Color picker
              Text(
                'Color',
                style: TextStyle(
                  fontSize: 10,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _buildColorPicker(provider, activeVersion),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(TrackVersionsProvider provider, TrackVersion version) {
    final colors = [
      FluxForgeTheme.accentBlue,
      _accentColor,
      FluxForgeTheme.accentGreen,
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentCyan,
      FluxForgeTheme.errorRed,
      const Color(0xFFFFD700),
      const Color(0xFFFF69B4),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) {
        final isSelected = version.color.value == color.value;
        return GestureDetector(
          onTap: () => provider.setVersionColor(
            _selectedTrackId!,
            version.id,
            color,
          ),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback? onTap) {
    final isDisabled = onTap == null;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: _accentColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallButton(String label, IconData icon, VoidCallback? onTap) {
    final isDisabled = onTap == null;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: FluxForgeTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showRenameDialog(TrackVersionsProvider provider, TrackVersion version) {
    final controller = TextEditingController(text: version.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: const Text('Rename Version', style: TextStyle(fontSize: 14)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Version name',
            isDense: true,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.renameVersion(
                  _selectedTrackId!,
                  version.id,
                  controller.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}
