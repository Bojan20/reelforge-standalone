// Open Project Dialog
//
// Provides project loading functionality with:
// - Recent projects list
// - File browser
// - Project preview

import 'package:flutter/material.dart';
import '../theme/reelforge_theme.dart';

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
      // TODO: Call Rust API
      // final paths = await api.projectGetRecent();

      // Mock data
      _recentProjects = [
        RecentProject(
          path: '~/Documents/MyProject.rfproj',
          name: 'MyProject',
          lastOpened: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        RecentProject(
          path: '~/Documents/SoundDesign/Ambience.rfproj',
          name: 'Ambience',
          lastOpened: DateTime.now().subtract(const Duration(days: 1)),
        ),
        RecentProject(
          path: '~/Documents/Music/Song1.rfproj',
          name: 'Song1',
          lastOpened: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];
    } catch (e) {
      debugPrint('Error loading recent projects: $e');
    }

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
          backgroundColor: ReelForgeTheme.accentRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isOpening = true);

    try {
      // TODO: Call Rust API
      // await api.projectLoadSync(path);

      await Future.delayed(const Duration(milliseconds: 500)); // Simulate load

      if (mounted) {
        Navigator.of(context).pop(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening project: $e'),
            backgroundColor: ReelForgeTheme.accentRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    setState(() => _isOpening = false);
  }

  void _removeFromRecent(RecentProject project) {
    setState(() {
      _recentProjects.remove(project);
    });
    // TODO: Call Rust API to update recent list
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
      backgroundColor: ReelForgeTheme.bgMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ReelForgeTheme.borderSubtle),
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
                  color: ReelForgeTheme.accentBlue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Open Project',
                  style: ReelForgeTheme.h2,
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
                      color: ReelForgeTheme.textPrimary,
                      fontFamily: ReelForgeTheme.monoFontFamily,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter file path or select from recent...',
                      hintStyle: TextStyle(color: ReelForgeTheme.textTertiary),
                      filled: true,
                      fillColor: ReelForgeTheme.bgSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: ReelForgeTheme.accentBlue),
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
                    backgroundColor: ReelForgeTheme.bgSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: ReelForgeTheme.borderSubtle),
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
                  color: ReelForgeTheme.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Projects',
                  style: TextStyle(
                    color: ReelForgeTheme.textSecondary,
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
                                color: ReelForgeTheme.textTertiary,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No recent projects',
                                style: TextStyle(
                                  color: ReelForgeTheme.textTertiary,
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
                            color: ReelForgeTheme.textPrimary,
                          ),
                        )
                      : const Icon(Icons.folder_open, size: 18),
                  label: Text(_isOpening ? 'Opening...' : 'Open'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ReelForgeTheme.accentBlue,
                    foregroundColor: ReelForgeTheme.textPrimary,
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
      color: ReelForgeTheme.bgVoid.withValues(alpha: 0.0),
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
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.textTertiary,
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
                            ? ReelForgeTheme.textPrimary
                            : ReelForgeTheme.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.path,
                      style: TextStyle(
                        color: ReelForgeTheme.textTertiary,
                        fontSize: 11,
                        fontFamily: ReelForgeTheme.monoFontFamily,
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
                  color: ReelForgeTheme.textTertiary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeFromRecent(project),
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Remove from recent',
                style: IconButton.styleFrom(
                  foregroundColor: ReelForgeTheme.textTertiary,
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
