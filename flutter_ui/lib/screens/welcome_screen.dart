/// FluxForge Studio Welcome Screen
///
/// Professional welcome/start screen with:
/// - New Project creation
/// - Open existing project
/// - Recent projects list (from Rust FFI)
/// - Quick start templates

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../theme/fluxforge_theme.dart';
import '../providers/recent_projects_provider.dart';

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

    // Initialize recent projects from Rust FFI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecentProjectsProvider>().initialize();
    });
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

  void _handleOpenRecent(RecentProject project) {
    widget.onOpenProject(project.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FluxForgeTheme.bgDeepest,
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
                      color: FluxForgeTheme.textSecondary,
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
                icon: Icon(Icons.graphic_eq, color: FluxForgeTheme.accentBlue, size: 16),
                label: Text(
                  'EQ Test Lab',
                  style: TextStyle(
                    color: FluxForgeTheme.accentBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accentBlue.withOpacity(0.1),
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
            FluxForgeTheme.bgMid,
            FluxForgeTheme.bgDeepest,
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
                  'FluxForge Studio v0.1.0',
                  style: TextStyle(
                    fontSize: 11,
                    color: FluxForgeTheme.textSecondary.withAlpha(128),
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
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),

                Consumer<RecentProjectsProvider>(
                  builder: (context, recentProvider, _) {
                    if (recentProvider.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgElevated.withAlpha(128),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: FluxForgeTheme.borderSubtle,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'No recent projects',
                            style: TextStyle(
                              color: FluxForgeTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: List.generate(
                        recentProvider.projects.length.clamp(0, 5),
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildRecentProjectItem(recentProvider.projects[i]),
                        ),
                      ),
                    );
                  },
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
        ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Image.asset(
            'assets/branding/fluxforge_icon.png',
            width: 220,
            height: 220,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 32),
        // Title
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  FluxForgeTheme.accentBlue,
                  FluxForgeTheme.accentCyan,
                ],
              ).createShader(bounds),
              child: Text(
                'FluxForge Studio',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 5,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ),
            Text(
              'AUTHORING TOOL & DAW',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 4,
                color: FluxForgeTheme.textSecondary.withAlpha(179),
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
                ? FluxForgeTheme.accentBlue.withAlpha(26)
                : FluxForgeTheme.bgElevated.withAlpha(128),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: primary
                  ? FluxForgeTheme.accentBlue.withAlpha(77)
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary
                      ? FluxForgeTheme.accentBlue.withAlpha(51)
                      : FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  color: primary
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textSecondary,
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
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: FluxForgeTheme.textSecondary.withAlpha(179),
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

  Widget _buildRecentProjectItem(RecentProject project) {
    final timeAgo = project.lastOpened != null
        ? _formatTimeAgo(project.lastOpened!)
        : 'Unknown';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _handleOpenRecent(project),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgElevated.withAlpha(77),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.borderSubtle.withAlpha(128),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.audio_file_rounded,
                  color: FluxForgeTheme.textSecondary,
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
                        color: FluxForgeTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 10,
                        color: FluxForgeTheme.textSecondary.withAlpha(179),
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
        color: FluxForgeTheme.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FluxForgeTheme.borderSubtle,
        ),
        boxShadow: [
          BoxShadow(
            color: FluxForgeTheme.bgVoid.withAlpha(200),
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
              color: FluxForgeTheme.textPrimary,
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
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _projectNameController,
            autofocus: true,
            style: TextStyle(
              fontSize: 14,
              color: FluxForgeTheme.textPrimary,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: FluxForgeTheme.bgMid,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: FluxForgeTheme.borderSubtle,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: FluxForgeTheme.borderSubtle,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: FluxForgeTheme.accentBlue,
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
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _confirmNewProject,
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accentBlue,
                  foregroundColor: FluxForgeTheme.textPrimary,
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
