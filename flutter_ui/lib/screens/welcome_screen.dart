/// ReelForge Welcome Screen
///
/// Professional welcome/start screen with:
/// - New Project creation
/// - Open existing project
/// - Recent projects list
/// - Quick start templates

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/reelforge_theme.dart';

class WelcomeScreen extends StatefulWidget {
  final void Function(String name) onNewProject;
  final void Function(String path) onOpenProject;
  final VoidCallback? onSkip;

  const WelcomeScreen({
    super.key,
    required this.onNewProject,
    required this.onOpenProject,
    this.onSkip,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final _projectNameController = TextEditingController(text: 'Untitled Project');
  bool _showNewProjectDialog = false;

  // Mock recent projects - TODO: Load from storage
  final List<_RecentProject> _recentProjects = [
    _RecentProject(
      name: 'Game Audio Master',
      path: '/Projects/GameAudio/master.rfp',
      lastOpened: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    _RecentProject(
      name: 'Podcast Episode 12',
      path: '/Projects/Podcast/ep12.rfp',
      lastOpened: DateTime.now().subtract(const Duration(days: 1)),
    ),
    _RecentProject(
      name: 'Sound Effects Pack',
      path: '/Projects/SFX/pack.rfp',
      lastOpened: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _projectNameController.dispose();
    super.dispose();
  }

  void _handleNewProject() {
    setState(() => _showNewProjectDialog = true);
  }

  void _confirmNewProject() {
    final name = _projectNameController.text.trim();
    if (name.isNotEmpty) {
      widget.onNewProject(name);
    }
  }

  Future<void> _handleOpenProject() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Project',
      type: FileType.custom,
      allowedExtensions: ['rfp', 'json'],
    );

    if (result != null && result.files.single.path != null) {
      widget.onOpenProject(result.files.single.path!);
    }
  }

  void _handleOpenRecent(_RecentProject project) {
    widget.onOpenProject(project.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReelForgeTheme.bgDeepest,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Background
            _buildBackground(),

            // Main content
            Center(
              child: _showNewProjectDialog
                  ? _buildNewProjectDialog()
                  : _buildMainContent(),
            ),

            // Skip button (for testing)
            if (widget.onSkip != null)
              Positioned(
                top: 16,
                right: 16,
                child: TextButton(
                  onPressed: widget.onSkip,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: ReelForgeTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),

            // EQ Test Lab button
            Positioned(
              top: 16,
              left: 16,
              child: TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/eq-test'),
                icon: Icon(Icons.graphic_eq, color: ReelForgeTheme.accentBlue, size: 16),
                label: Text(
                  'EQ Test Lab',
                  style: TextStyle(
                    color: ReelForgeTheme.accentBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: ReelForgeTheme.accentBlue.withOpacity(0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.5),
          radius: 1.5,
          colors: [
            const Color(0xFF1A1A24),
            ReelForgeTheme.bgDeepest,
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 900),
      padding: const EdgeInsets.all(48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side - Logo and actions
          Expanded(
            flex: 5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo
                _buildLogo(),
                const SizedBox(height: 48),

                // Action buttons
                _buildActionButton(
                  icon: Icons.add_rounded,
                  label: 'New Project',
                  sublabel: 'Start a fresh project',
                  onTap: _handleNewProject,
                  primary: true,
                ),
                const SizedBox(height: 16),
                _buildActionButton(
                  icon: Icons.folder_open_rounded,
                  label: 'Open Project',
                  sublabel: 'Open an existing .rfp file',
                  onTap: _handleOpenProject,
                ),
                const SizedBox(height: 16),
                _buildActionButton(
                  icon: Icons.music_note_rounded,
                  label: 'Import Audio',
                  sublabel: 'Create project from audio files',
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(
                      dialogTitle: 'Import Audio Files',
                      type: FileType.audio,
                      allowMultiple: true,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      widget.onNewProject('Imported Audio');
                    }
                  },
                ),

                const SizedBox(height: 32),

                // Version
                Text(
                  'ReelForge v0.1.0',
                  style: TextStyle(
                    fontSize: 11,
                    color: ReelForgeTheme.textSecondary.withAlpha(128),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 48),

          // Right side - Recent projects
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RECENT PROJECTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: ReelForgeTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),

                if (_recentProjects.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgElevated.withAlpha(128),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ReelForgeTheme.borderSubtle,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'No recent projects',
                        style: TextStyle(
                          color: ReelForgeTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  ...List.generate(
                    _recentProjects.length,
                    (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildRecentProjectItem(_recentProjects[i]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ReelForgeTheme.accentBlue.withAlpha(77),
                ReelForgeTheme.accentCyan.withAlpha(51),
              ],
            ),
            border: Border.all(
              color: ReelForgeTheme.accentBlue.withAlpha(128),
              width: 1.5,
            ),
          ),
          child: Center(
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  ReelForgeTheme.accentBlue,
                  ReelForgeTheme.accentCyan,
                ],
              ).createShader(bounds),
              child: const Text(
                'R',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        // Title
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  ReelForgeTheme.accentBlue,
                  ReelForgeTheme.accentCyan,
                ],
              ).createShader(bounds),
              child: const Text(
                'ReelForge',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              'DIGITAL AUDIO WORKSTATION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 3,
                color: ReelForgeTheme.textSecondary.withAlpha(179),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: primary
                ? ReelForgeTheme.accentBlue.withAlpha(26)
                : ReelForgeTheme.bgElevated.withAlpha(128),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: primary
                  ? ReelForgeTheme.accentBlue.withAlpha(77)
                  : ReelForgeTheme.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary
                      ? ReelForgeTheme.accentBlue.withAlpha(51)
                      : ReelForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  color: primary
                      ? ReelForgeTheme.accentBlue
                      : ReelForgeTheme.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: primary
                          ? ReelForgeTheme.textPrimary
                          : ReelForgeTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: ReelForgeTheme.textSecondary.withAlpha(179),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentProjectItem(_RecentProject project) {
    final timeAgo = _formatTimeAgo(project.lastOpened);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _handleOpenRecent(project),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgElevated.withAlpha(77),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: ReelForgeTheme.borderSubtle.withAlpha(128),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ReelForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.audio_file_rounded,
                  color: ReelForgeTheme.textSecondary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: ReelForgeTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 10,
                        color: ReelForgeTheme.textSecondary.withAlpha(179),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewProjectDialog() {
    return Container(
      width: 400,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ReelForgeTheme.borderSubtle,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(128),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New Project',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: ReelForgeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 24),

          // Project name
          Text(
            'PROJECT NAME',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: ReelForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _projectNameController,
            autofocus: true,
            style: TextStyle(
              fontSize: 14,
              color: ReelForgeTheme.textPrimary,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: ReelForgeTheme.bgMid,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: ReelForgeTheme.borderSubtle,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: ReelForgeTheme.borderSubtle,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: ReelForgeTheme.accentBlue,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
            onSubmitted: (_) => _confirmNewProject(),
          ),

          const SizedBox(height: 32),

          // Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _showNewProjectDialog = false),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: ReelForgeTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _confirmNewProject,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ReelForgeTheme.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _RecentProject {
  final String name;
  final String path;
  final DateTime lastOpened;

  _RecentProject({
    required this.name,
    required this.path,
    required this.lastOpened,
  });
}
