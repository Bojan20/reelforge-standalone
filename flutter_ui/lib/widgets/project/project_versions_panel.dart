/// Project Versions Panel
///
/// UI for project versioning:
/// - List all versions with metadata
/// - Create new version (snapshot)
/// - Restore from version
/// - Mark milestones
/// - Export versions

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Project version data
class ProjectVersionData {
  final String id;
  final int number;
  final String name;
  final String description;
  final int createdAt;
  final int size;
  final String projectName;
  final List<String> tags;
  final bool isMilestone;

  ProjectVersionData({
    required this.id,
    required this.number,
    required this.name,
    this.description = '',
    this.createdAt = 0,
    this.size = 0,
    this.projectName = '',
    this.tags = const [],
    this.isMilestone = false,
  });

  factory ProjectVersionData.fromJson(Map<String, dynamic> json) {
    return ProjectVersionData(
      id: json['id'] ?? '',
      number: json['number'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      createdAt: json['created_at'] ?? 0,
      size: json['size'] ?? 0,
      projectName: json['project_name'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      isMilestone: json['is_milestone'] ?? false,
    );
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Project Versions Panel Widget
class ProjectVersionsPanel extends StatefulWidget {
  final VoidCallback? onVersionRestored;

  const ProjectVersionsPanel({
    super.key,
    this.onVersionRestored,
  });

  @override
  State<ProjectVersionsPanel> createState() => _ProjectVersionsPanelState();
}

class _ProjectVersionsPanelState extends State<ProjectVersionsPanel> {
  final _ffi = NativeFFI.instance;
  List<ProjectVersionData> _versions = [];
  bool _showMilestonesOnly = false;
  String? _selectedVersionId;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  void _loadVersions() {
    final json = _showMilestonesOnly
        ? _ffi.versionListMilestones()
        : _ffi.versionListAll();
    final list = jsonDecode(json) as List;
    setState(() {
      _versions = list.map((e) => ProjectVersionData.fromJson(e)).toList();
      _versions.sort((a, b) => b.number.compareTo(a.number)); // Newest first
    });
  }

  void _createVersion() {
    final nameController = TextEditingController(text: 'Version ${_versions.length + 1}');
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: const Text('Create Version', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Version Name',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final id = _ffi.versionCreate(nameController.text, descController.text);
              if (id != null) {
                _loadVersions();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Created version "${nameController.text}"'),
                    backgroundColor: FluxForgeTheme.accentGreen,
                  ),
                );
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: FluxForgeTheme.accentBlue),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _toggleMilestone(ProjectVersionData version) {
    _ffi.versionSetMilestone(version.id, !version.isMilestone);
    _loadVersions();
  }

  void _deleteVersion(ProjectVersionData version) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: const Text('Delete Version?', style: TextStyle(color: Colors.white)),
        content: Text(
          version.isMilestone
              ? '"${version.name}" is a milestone. Force delete?'
              : 'Are you sure you want to delete "${version.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (version.isMilestone) {
                _ffi.versionForceDelete(version.id);
              } else {
                _ffi.versionDelete(version.id);
              }
              _loadVersions();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: FluxForgeTheme.accentRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          _buildToolbar(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(child: _buildVersionList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.history, color: FluxForgeTheme.accentGreen, size: 18),
          const SizedBox(width: 8),
          const Text(
            'PROJECT VERSIONS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            '${_versions.length} versions',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: FluxForgeTheme.bgMid.withOpacity(0.5),
      child: Row(
        children: [
          // Create version button
          ElevatedButton.icon(
            onPressed: _createVersion,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Save Version', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentGreen,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 26),
            ),
          ),
          const SizedBox(width: 12),
          // Milestones filter
          FilterChip(
            selected: _showMilestonesOnly,
            label: const Text('Milestones', style: TextStyle(fontSize: 10)),
            avatar: Icon(
              Icons.star,
              size: 14,
              color: _showMilestonesOnly ? Colors.black : Colors.amber,
            ),
            onSelected: (v) {
              setState(() => _showMilestonesOnly = v);
              _loadVersions();
            },
            backgroundColor: FluxForgeTheme.bgDeep,
            selectedColor: Colors.amber,
            checkmarkColor: Colors.black,
            labelStyle: TextStyle(
              color: _showMilestonesOnly ? Colors.black : Colors.white70,
            ),
          ),
          const Spacer(),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            color: Colors.white54,
            onPressed: _loadVersions,
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionList() {
    if (_versions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 16),
            const Text(
              'No versions yet',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Click "Save Version" to create a snapshot',
              style: TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _versions.length,
      itemBuilder: (context, index) => _buildVersionItem(_versions[index]),
    );
  }

  Widget _buildVersionItem(ProjectVersionData version) {
    final isSelected = version.id == _selectedVersionId;

    return GestureDetector(
      onTap: () => setState(() => _selectedVersionId = version.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withOpacity(0.15)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accentBlue
                : version.isMilestone
                    ? Colors.amber.withOpacity(0.4)
                    : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            // Version number badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: version.isMilestone
                    ? Colors.amber.withOpacity(0.2)
                    : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: version.isMilestone ? Colors.amber : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: Center(
                child: version.isMilestone
                    ? const Icon(Icons.star, size: 16, color: Colors.amber)
                    : Text(
                        'v${version.number}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Version info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    version.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        version.formattedDate,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        version.formattedSize,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                  if (version.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      version.description,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    version.isMilestone ? Icons.star : Icons.star_border,
                    size: 18,
                    color: version.isMilestone ? Colors.amber : Colors.white38,
                  ),
                  onPressed: () => _toggleMilestone(version),
                  tooltip: version.isMilestone ? 'Remove milestone' : 'Mark as milestone',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white38),
                  onPressed: () => _deleteVersion(version),
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
