/// FluxForge Studio Middleware Hub Screen
///
/// Professional project launcher inspired by:
/// - Wwise Project Launcher (recent projects, templates)
/// - FMOD Studio Start Screen (projects, import)
/// - Unity Hub (project management)
///
/// Tailored for game audio authoring workflow.

import 'dart:math' as math;
import '../utils/safe_file_picker.dart';
import 'package:flutter/material.dart';

class MiddlewareHubScreen extends StatefulWidget {
  final void Function(String name) onNewProject;
  final void Function(String path) onOpenProject;
  final VoidCallback onQuickStart;
  final VoidCallback onBackToLauncher;

  const MiddlewareHubScreen({
    super.key,
    required this.onNewProject,
    required this.onOpenProject,
    required this.onQuickStart,
    required this.onBackToLauncher,
  });

  @override
  State<MiddlewareHubScreen> createState() => _MiddlewareHubScreenState();
}

class _MiddlewareHubScreenState extends State<MiddlewareHubScreen>
    with TickerProviderStateMixin {
  // Entry animations
  late AnimationController _entryController;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;
  late Animation<double> _scaleIn;

  // Continuous animations
  late AnimationController _pulseController;
  late AnimationController _nodeController;

  // UI State
  int _selectedWorkflowIndex = 0;
  String _projectName = '';
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  int? _hoveredRecentIndex;

  // Workflow templates (Wwise-inspired)
  final List<_WorkflowTemplate> _workflows = [
    _WorkflowTemplate(
      name: 'Slot Machine',
      description: 'Full slot game audio template with events, states, and RTPC',
      icon: Icons.casino_rounded,
      color: const Color(0xFFFF9040),
      features: ['Spin Events', 'Win Tiers', 'Feature Audio', 'Ambient Loops'],
    ),
    _WorkflowTemplate(
      name: 'Interactive Music',
      description: 'Adaptive music system with segments and stingers',
      icon: Icons.music_note_rounded,
      color: const Color(0xFFAA40FF),
      features: ['Music Segments', 'Stingers', 'Transitions', 'Stems'],
    ),
    _WorkflowTemplate(
      name: 'Mobile Game',
      description: 'Optimized for mobile with compression profiles',
      icon: Icons.phone_android_rounded,
      color: const Color(0xFF40C8FF),
      features: ['Size Optimized', 'Bank Streaming', 'Memory Pools', 'Codec Profiles'],
    ),
    _WorkflowTemplate(
      name: 'Casino Floor',
      description: 'Multi-cabinet audio with ducking and spatial',
      icon: Icons.grid_view_rounded,
      color: const Color(0xFFFFD700),
      features: ['Ducking Matrix', 'Cabinet Zones', 'Attract Mode', 'Jackpot Systems'],
    ),
    _WorkflowTemplate(
      name: 'Empty Project',
      description: 'Start from scratch with minimal setup',
      icon: Icons.add_rounded,
      color: const Color(0xFF4A9EFF),
      features: ['Basic Structure', 'Default Buses', 'Master Output'],
    ),
  ];

  // Mock recent projects
  final List<_RecentMiddlewareProject> _recentProjects = [
    _RecentMiddlewareProject(
      name: 'Dragon Fortune Slots',
      path: '/Projects/DragonFortune/DragonFortune.fxm',
      lastOpened: DateTime.now().subtract(const Duration(hours: 2)),
      eventCount: 847,
      soundCount: 1234,
    ),
    _RecentMiddlewareProject(
      name: 'Lucky Casino Mobile',
      path: '/Projects/LuckyCasino/LuckyCasino.fxm',
      lastOpened: DateTime.now().subtract(const Duration(days: 1)),
      eventCount: 523,
      soundCount: 892,
    ),
    _RecentMiddlewareProject(
      name: 'Pharaoh Riches',
      path: '/Projects/PharaohRiches/PharaohRiches.fxm',
      lastOpened: DateTime.now().subtract(const Duration(days: 3)),
      eventCount: 612,
      soundCount: 1056,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startEntryAnimation();
  }

  void _initAnimations() {
    // Entry animation
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

    // Node graph animation
    _nodeController = AnimationController(
      duration: const Duration(milliseconds: 5000),
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
    _nodeController.dispose();
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
      backgroundColor: const Color(0xFF08080A),
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
                // Left panel - Create & Workflows
                Expanded(
                  flex: 5,
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

                // Right panel - Recent & Quick Actions
                Expanded(
                  flex: 3,
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
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.3, -0.3),
              radius: 1.5,
              colors: [
                Color(0xFF101014),
                Color(0xFF08080A),
              ],
            ),
          ),
        ),

        // Orange accent glow
        Positioned(
          right: -150,
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
                      const Color(0xFFFF9040).withValues(alpha: intensity),
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

        // Node graph decoration
        Positioned(
          right: 40,
          bottom: 80,
          child: AnimatedBuilder(
            animation: _nodeController,
            builder: (context, _) {
              return CustomPaint(
                size: const Size(180, 120),
                painter: _NodeGraphDecorationPainter(
                  progress: _nodeController.value,
                  color: const Color(0xFFFF9040),
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
          _buildHeaderActions(),
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
              'MIDDLEWARE MODE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFF9040),
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderActions() {
    return Row(
      children: [
        _buildHeaderAction(
          icon: Icons.folder_open_rounded,
          label: 'Open',
          onTap: () => _showOpenDialog(),
        ),
        const SizedBox(width: 12),
        _buildHeaderAction(
          icon: Icons.cloud_download_rounded,
          label: 'Import',
          onTap: () {},
        ),
        const SizedBox(width: 12),
        _buildHeaderAction(
          icon: Icons.settings_rounded,
          label: 'Settings',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildHeaderAction({
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

          // Workflow templates
          const Text(
            'WORKFLOW TEMPLATES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: Color(0xFF555555),
            ),
          ),

          const SizedBox(height: 16),

          // Workflow list (horizontal scroll)
          SizedBox(
            height: 180,
            child: _buildWorkflowList(),
          ),

          const SizedBox(height: 24),

          // Selected workflow details
          _buildSelectedWorkflowDetails(),

          const Spacer(),

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
              ? const Color(0xFFFF9040).withValues(alpha: 0.5)
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

  Widget _buildWorkflowList() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: _workflows.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: _buildWorkflowCard(_workflows[index], index),
        );
      },
    );
  }

  Widget _buildWorkflowCard(_WorkflowTemplate workflow, int index) {
    final isSelected = _selectedWorkflowIndex == index;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _selectedWorkflowIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 160,
          decoration: BoxDecoration(
            color: isSelected
                ? workflow.color.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? workflow.color.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.06),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: workflow.color.withValues(alpha: 0.2),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: workflow.color.withValues(alpha: isSelected ? 0.3 : 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        workflow.icon,
                        size: 20,
                        color: isSelected ? workflow.color : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: workflow.color,
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  workflow.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  workflow.description,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.4,
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

  Widget _buildSelectedWorkflowDetails() {
    final workflow = _workflows[_selectedWorkflowIndex];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: workflow.color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                workflow.icon,
                size: 20,
                color: workflow.color,
              ),
              const SizedBox(width: 12),
              Text(
                'INCLUDES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: workflow.color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: workflow.features.map((feature) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: workflow.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: workflow.color.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  feature,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateButton() {
    final workflow = _workflows[_selectedWorkflowIndex];

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
                const Color(0xFFFF9040),
                const Color(0xFFFFD700),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9040).withValues(alpha: 0.3),
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
                'Create ${workflow.name} Project',
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
          // Quick Start
          _buildQuickStartSection(),

          const SizedBox(height: 32),

          // Recent Projects
          const Text(
            'RECENT PROJECTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              color: Color(0xFF666666),
            ),
          ),

          const SizedBox(height: 16),

          // Recent projects list
          Expanded(
            child: _buildRecentProjectsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK START',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
            color: Color(0xFF666666),
          ),
        ),
        const SizedBox(height: 16),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onQuickStart,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFF9040).withValues(alpha: 0.15),
                    const Color(0xFFFFD700).withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF9040).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9040).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 28,
                      color: Color(0xFFFF9040),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Slot Lab Sandbox',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Jump directly into the audio authoring environment',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: const Color(0xFFFF9040),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentProjectsList() {
    if (_recentProjects.isEmpty) {
      return _buildEmptyRecentProjects();
    }

    return ListView.builder(
      itemCount: _recentProjects.length,
      itemBuilder: (context, index) {
        return _buildRecentProjectItem(_recentProjects[index], index);
      },
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
        ],
      ),
    );
  }

  Widget _buildRecentProjectItem(_RecentMiddlewareProject project, int index) {
    final isHovered = _hoveredRecentIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredRecentIndex = index),
        onExit: (_) => setState(() => _hoveredRecentIndex = null),
        child: GestureDetector(
          onTap: () => widget.onOpenProject(project.path),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isHovered
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isHovered
                    ? const Color(0xFFFF9040).withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: Row(
              children: [
                // Project icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9040).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.casino_rounded,
                    size: 22,
                    color: const Color(0xFFFF9040).withValues(alpha: 0.7),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildStatBadge(
                            '${project.eventCount} events',
                            const Color(0xFFFF9040),
                          ),
                          const SizedBox(width: 8),
                          _buildStatBadge(
                            '${project.soundCount} sounds',
                            const Color(0xFF40C8FF),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Date
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDate(project.lastOpened),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isHovered)
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: const Color(0xFFFF9040),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: color.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inHours < 1) {
      return 'Just now';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
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
          const SizedBox(width: 24),
          _buildShortcutHint('⌘I', 'Import'),
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
    final result = await SafeFilePicker.pickFiles(context,
      type: FileType.custom,
      allowedExtensions: ['fxm'],
      dialogTitle: 'Open Middleware Project',
    );
    if (result != null && result.files.single.path != null) {
      widget.onOpenProject(result.files.single.path!);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class _WorkflowTemplate {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final List<String> features;

  const _WorkflowTemplate({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.features,
  });
}

class _RecentMiddlewareProject {
  final String name;
  final String path;
  final DateTime lastOpened;
  final int eventCount;
  final int soundCount;

  const _RecentMiddlewareProject({
    required this.name,
    required this.path,
    required this.lastOpened,
    required this.eventCount,
    required this.soundCount,
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

class _NodeGraphDecorationPainter extends CustomPainter {
  final double progress;
  final Color color;

  _NodeGraphDecorationPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final nodePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    // Define node positions
    final nodes = <Offset>[
      Offset(size.width * 0.1, size.height * 0.3),
      Offset(size.width * 0.3, size.height * 0.1),
      Offset(size.width * 0.5, size.height * 0.4),
      Offset(size.width * 0.4, size.height * 0.7),
      Offset(size.width * 0.7, size.height * 0.2),
      Offset(size.width * 0.8, size.height * 0.6),
      Offset(size.width * 0.9, size.height * 0.8),
    ];

    // Draw connections
    final connections = [
      [0, 1], [0, 2], [1, 2], [1, 4],
      [2, 3], [2, 4], [4, 5], [3, 5], [5, 6],
    ];

    for (final conn in connections) {
      canvas.drawLine(nodes[conn[0]], nodes[conn[1]], linePaint);
    }

    // Draw nodes with animation
    for (int i = 0; i < nodes.length; i++) {
      final phase = (progress + i / nodes.length) % 1.0;
      final pulse = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
      final radius = 3.0 + pulse * 2.0;

      nodePaint.color = color.withValues(alpha: 0.15 + pulse * 0.15);
      canvas.drawCircle(nodes[i], radius, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NodeGraphDecorationPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
