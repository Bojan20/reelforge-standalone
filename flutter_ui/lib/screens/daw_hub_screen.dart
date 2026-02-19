/// FluxForge Studio DAW Hub Screen
///
/// Professional welcome screen inspired by:
/// - Cubase Hub (recent projects, news, templates)
/// - Pro Tools Dashboard (quick start, recent sessions)
/// - Logic Pro Start Screen (templates, recent)
/// - Reaper (minimal, efficient)
/// - Pyramix (broadcast-focused)
///
/// Hybrid design taking the best from each.

import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recent_projects_provider.dart';
import '../theme/fluxforge_theme.dart';

class DawHubScreen extends StatefulWidget {
  final void Function(String name) onNewProject;
  final void Function(String path) onOpenProject;
  final VoidCallback onBackToLauncher;

  const DawHubScreen({
    super.key,
    required this.onNewProject,
    required this.onOpenProject,
    required this.onBackToLauncher,
  });

  @override
  State<DawHubScreen> createState() => _DawHubScreenState();
}

class _DawHubScreenState extends State<DawHubScreen>
    with TickerProviderStateMixin {
  // Entry animations
  late AnimationController _entryController;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;
  late Animation<double> _scaleIn;

  // Continuous animations
  late AnimationController _pulseController;
  late AnimationController _waveController;

  // UI State
  int _selectedTemplateIndex = 0;
  String _projectName = '';
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();

  // Templates (Cubase-inspired categories)
  final List<_ProjectTemplate> _templates = [
    _ProjectTemplate(
      name: 'Empty',
      description: 'Start with a blank canvas',
      icon: Icons.add_rounded,
      color: const Color(0xFF4A9EFF),
      tracks: 0,
    ),
    _ProjectTemplate(
      name: 'Music Production',
      description: '8 audio + 4 MIDI tracks, basic effects',
      icon: Icons.music_note_rounded,
      color: const Color(0xFF40C8FF),
      tracks: 12,
    ),
    _ProjectTemplate(
      name: 'Podcast / Voice',
      description: '2 mono tracks, EQ & compression',
      icon: Icons.mic_rounded,
      color: const Color(0xFF40FF90),
      tracks: 2,
    ),
    _ProjectTemplate(
      name: 'Film Scoring',
      description: '16 tracks, video sync ready',
      icon: Icons.movie_rounded,
      color: const Color(0xFFFF9040),
      tracks: 16,
    ),
    _ProjectTemplate(
      name: 'Mastering',
      description: 'Stereo I/O, metering suite',
      icon: Icons.graphic_eq_rounded,
      color: const Color(0xFFFF4060),
      tracks: 1,
    ),
    _ProjectTemplate(
      name: 'Sound Design',
      description: '6 tracks, advanced DSP routing',
      icon: Icons.waves_rounded,
      color: const Color(0xFFAA40FF),
      tracks: 6,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startEntryAnimation();
  }

  void _initAnimations() {
    // Entry animation (from launcher transition)
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideUp = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.1, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _scaleIn = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Continuous pulse
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);

    // Wave animation
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat();
  }

  void _startEntryAnimation() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _entryController.forward();
      }
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _createProject() {
    final name = _projectName.isEmpty ? 'Untitled Project' : _projectName;
    widget.onNewProject(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FluxForgeTheme.bgVoid,
      body: AnimatedBuilder(
        animation: _entryController,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeIn.value,
            child: Transform.translate(
              offset: Offset(0, _slideUp.value),
              child: Transform.scale(
                scale: _scaleIn.value,
                child: child,
              ),
            ),
          );
        },
        child: Stack(
          children: [
            // Background
            _buildBackground(),

            // Main content
            Row(
              children: [
                // Left panel - Templates & Create
                Expanded(
                  flex: 3,
                  child: _buildLeftPanel(),
                ),

                // Divider
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 60),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.1),
                        Colors.white.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

                // Right panel - Recent Projects
                Expanded(
                  flex: 2,
                  child: _buildRightPanel(),
                ),
              ],
            ),

            // Header
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildHeader(),
            ),

            // Footer
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildFooter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.3, -0.3),
              radius: 1.5,
              colors: [
                FluxForgeTheme.bgMid,
                FluxForgeTheme.bgVoid,
              ],
            ),
          ),
        ),

        // Blue accent glow
        Positioned(
          left: -150,
          top: 100,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final intensity = 0.08 + 0.04 * _pulseController.value;
              return Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      FluxForgeTheme.accentBlue.withValues(alpha: intensity),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Grid pattern
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(opacity: 0.02),
          ),
        ),

        // Waveform decoration
        Positioned(
          left: 40,
          bottom: 80,
          child: AnimatedBuilder(
            animation: _waveController,
            builder: (context, _) {
              return CustomPaint(
                size: const Size(200, 60),
                painter: _WaveformDecorationPainter(
                  progress: _waveController.value,
                  color: FluxForgeTheme.accentBlue,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        children: [
          // Back button
          _buildBackButton(),

          const SizedBox(width: 24),

          // Logo & Title
          _buildLogoTitle(),

          const Spacer(),

          // Quick actions
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onBackToLauncher,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoTitle() {
    return Row(
      children: [
        // Mini logo
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/branding/fluxforge_icon.png',
            width: 80,
            height: 80,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FluxForge Studio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            Text(
              'DAW MODE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.accentBlue,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _buildQuickAction(
          icon: Icons.folder_open_rounded,
          label: 'Open',
          onTap: () => _showOpenDialog(),
        ),
        const SizedBox(width: 12),
        _buildQuickAction(
          icon: Icons.settings_rounded,
          label: 'Settings',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 100, 24, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          const Text(
            'CREATE NEW PROJECT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              color: Color(0xFF666666),
            ),
          ),

          const SizedBox(height: 24),

          // Project name input
          _buildProjectNameInput(),

          const SizedBox(height: 32),

          // Templates section
          const Text(
            'TEMPLATES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: Color(0xFF555555),
            ),
          ),

          const SizedBox(height: 16),

          // Template grid
          Expanded(
            child: _buildTemplateGrid(),
          ),

          const SizedBox(height: 24),

          // Create button
          _buildCreateButton(),
        ],
      ),
    );
  }

  Widget _buildProjectNameInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _nameFocusNode.hasFocus
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: _nameFocusNode.hasFocus ? 2 : 1,
        ),
      ),
      child: TextField(
        controller: _nameController,
        focusNode: _nameFocusNode,
        onChanged: (value) => setState(() => _projectName = value),
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        decoration: InputDecoration(
          hintText: 'Project Name',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
          ),
          prefixIcon: Icon(
            Icons.edit_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildTemplateGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: _templates.length,
      itemBuilder: (context, index) {
        return _buildTemplateCard(_templates[index], index);
      },
    );
  }

  Widget _buildTemplateCard(_ProjectTemplate template, int index) {
    final isSelected = _selectedTemplateIndex == index;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _selectedTemplateIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected
                ? template.color.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? template.color.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.06),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: template.color.withValues(alpha: 0.2),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: template.color.withValues(alpha: isSelected ? 0.3 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        template.icon,
                        size: 16,
                        color: isSelected ? template.color : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: template.color,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  template.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  template.description,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    final template = _templates[_selectedTemplateIndex];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _createProject,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                FluxForgeTheme.accentBlue,
                FluxForgeTheme.accentCyan,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, size: 20, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                'Create ${template.name} Project',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 100, 48, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          Row(
            children: [
              const Text(
                'RECENT PROJECTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                  color: Color(0xFF666666),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showOpenDialog(),
                child: Text(
                  'Browse All',
                  style: TextStyle(
                    fontSize: 11,
                    color: FluxForgeTheme.accentBlue,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Recent projects list
          Expanded(
            child: Consumer<RecentProjectsProvider>(
              builder: (context, provider, _) {
                if (provider.projects.isEmpty) {
                  return _buildEmptyRecentProjects();
                }
                return _buildRecentProjectsList(provider.projects);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRecentProjects() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 48,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'No recent projects',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new project or open an existing one',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentProjectsList(List<RecentProject> projects) {
    return ListView.builder(
      itemCount: projects.length,
      itemBuilder: (context, index) {
        return _buildRecentProjectItem(projects[index], index);
      },
    );
  }

  Widget _buildRecentProjectItem(RecentProject project, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.onOpenProject(project.path),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: Row(
              children: [
                // Project icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.audio_file_rounded,
                    size: 20,
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 14),
                // Project info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        project.path,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Date
                if (project.lastOpened != null)
                  Text(
                    _formatDate(project.lastOpened!),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
      child: Row(
        children: [
          // Keyboard shortcuts hint
          _buildShortcutHint('⌘N', 'New'),
          const SizedBox(width: 24),
          _buildShortcutHint('⌘O', 'Open'),
          const Spacer(),
          // Version
          Text(
            'v0.1.0',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.2),
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutHint(String shortcut, String action) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            shortcut,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          action,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  Future<void> _showOpenDialog() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['rfp'],
      dialogTitle: 'Open DAW Project',
    );
    if (result != null && result.files.single.path != null) {
      widget.onOpenProject(result.files.single.path!);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class _ProjectTemplate {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final int tracks;

  const _ProjectTemplate({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.tracks,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  final double opacity;

  _GridPainter({this.opacity = 0.03});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 0.5;

    const spacing = 50.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WaveformDecorationPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformDecorationPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final path = Path();
    final midY = size.height / 2;

    path.moveTo(0, midY);

    for (double x = 0; x <= size.width; x += 2) {
      final phase = progress * 2 * math.pi;
      final y = midY + math.sin((x / size.width) * 4 * math.pi + phase) *
          (size.height * 0.3) * (1 - (x / size.width) * 0.5);
      path.lineTo(x, y);
    }

    path.lineTo(size.width, midY);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveformDecorationPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
