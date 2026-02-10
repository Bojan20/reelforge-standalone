// Open Project Dialog
//
// Provides project loading functionality with:
// - Recent projects list
// - File browser
// - Project preview

import 'dart:io';
import 'package:flutter/material.dart';
import '../src/rust/native_ffi.dart';
import '../theme/fluxforge_theme.dart';

class RecentProject {
  final String path;
  final String name;
  final DateTime lastOpened;
  final bool exists;

  RecentProject({
    required this.path,
    required this.name,
    required this.lastOpened,
    this.exists = true,
  });
}

class OpenProjectDialog extends StatefulWidget {
  const OpenProjectDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const OpenProjectDialog(),
    );
  }

  @override
  State<OpenProjectDialog> createState() => _OpenProjectDialogState();
}

class _OpenProjectDialogState extends State<OpenProjectDialog> {
  final _pathController = TextEditingController();
  List<RecentProject> _recentProjects = [];
  bool _isLoading = true;
  bool _isOpening = false;

  @override
  void initState() {
    super.initState();
    _loadRecentProjects();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentProjects() async {
    setState(() => _isLoading = true);

    try {
      // Call Rust API to get recent projects
      final paths = NativeFFI.instance.projectGetRecentProjects();

      _recentProjects = [];
      for (final path in paths) {
        // Extract name from path
        final name = path.split('/').last.replaceAll('.rfproj', '');
        // Check if file exists
        final file = File(path.replaceFirst('~', Platform.environment['HOME'] ?? ''));
        final exists = file.existsSync();
        // Get last modified time if file exists
        final lastOpened = exists ? file.lastModifiedSync() : DateTime.now();

        _recentProjects.add(RecentProject(
          path: path,
          name: name,
          lastOpened: lastOpened,
          exists: exists,
        ));
      }
    } catch (e) { /* ignored */ }

    setState(() => _isLoading = false);
  }

  Future<void> _browseFile() async {
    // TODO: Use file_picker package or native dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('File browser not yet implemented'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openProject(String path) async {
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a file path'),
          backgroundColor: FluxForgeTheme.accentRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isOpening = true);

    try {
      // Call Rust API to load project
      final success = NativeFFI.instance.projectLoad(path);
      if (!success) {
        throw Exception('Failed to load project');
      }

      // Add to recent projects
      NativeFFI.instance.projectRecentAdd(path);

      if (mounted) {
        Navigator.of(context).pop(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening project: $e'),
            backgroundColor: FluxForgeTheme.accentRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    setState(() => _isOpening = false);
  }

  void _removeFromRecent(RecentProject project) {
    // Call Rust API to remove from recent list
    NativeFFI.instance.projectRecentRemove(project.path);
    setState(() {
      _recentProjects.remove(project);
    });
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minutes ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_open,
                  color: FluxForgeTheme.accentBlue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Open Project',
                  style: FluxForgeTheme.h2,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // File path input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontFamily: FluxForgeTheme.monoFontFamily,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter file path or select from recent...',
                      hintStyle: TextStyle(color: FluxForgeTheme.textTertiary),
                      filled: true,
                      fillColor: FluxForgeTheme.bgSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: _openProject,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _browseFile,
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Browse...',
                  style: IconButton.styleFrom(
                    backgroundColor: FluxForgeTheme.bgSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Recent projects
            Row(
              children: [
                Icon(
                  Icons.history,
                  color: FluxForgeTheme.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Projects',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _recentProjects.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_off,
                                color: FluxForgeTheme.textTertiary,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No recent projects',
                                style: TextStyle(
                                  color: FluxForgeTheme.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _recentProjects.length,
                          itemBuilder: (context, index) {
                            return _buildRecentProjectItem(_recentProjects[index]);
                          },
                        ),
            ),

            const SizedBox(height: 16),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isOpening
                      ? null
                      : () => _openProject(_pathController.text),
                  icon: _isOpening
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: FluxForgeTheme.textPrimary,
                          ),
                        )
                      : const Icon(Icons.folder_open, size: 18),
                  label: Text(_isOpening ? 'Opening...' : 'Open'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FluxForgeTheme.accentBlue,
                    foregroundColor: FluxForgeTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentProjectItem(RecentProject project) {
    return Material(
      color: FluxForgeTheme.bgVoid.withValues(alpha: 0.0),
      child: InkWell(
        onTap: () {
          _pathController.text = project.path;
          _openProject(project.path);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.description,
                color: project.exists
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textTertiary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: TextStyle(
                        color: project.exists
                            ? FluxForgeTheme.textPrimary
                            : FluxForgeTheme.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.path,
                      style: TextStyle(
                        color: FluxForgeTheme.textTertiary,
                        fontSize: 11,
                        fontFamily: FluxForgeTheme.monoFontFamily,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDate(project.lastOpened),
                style: TextStyle(
                  color: FluxForgeTheme.textTertiary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeFromRecent(project),
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Remove from recent',
                style: IconButton.styleFrom(
                  foregroundColor: FluxForgeTheme.textTertiary,
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(24, 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
