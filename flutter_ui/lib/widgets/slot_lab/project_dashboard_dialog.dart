/// Project Dashboard Dialog (M1 Task 4)
///
/// Comprehensive project overview for Producers and Product Owners.
/// Shows progress metrics, export validation, and project notes.
///
/// Features:
/// - Audio coverage by section
/// - Export readiness validation
/// - Project notes (markdown)
/// - Quick stats and metrics

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Project Dashboard Dialog
class ProjectDashboardDialog extends StatefulWidget {
  const ProjectDashboardDialog({super.key});

  /// Show the dashboard dialog
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const ProjectDashboardDialog(),
    );
  }

  @override
  State<ProjectDashboardDialog> createState() => _ProjectDashboardDialogState();
}

class _ProjectDashboardDialogState extends State<ProjectDashboardDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _projectNotes = '';
  bool _notesEditing = false;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.85).clamp(800.0, 1200.0);
    final dialogHeight = (screenSize.height * 0.8).clamp(600.0, 900.0);

    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildCoverageTab(),
                  _buildValidationTab(),
                  _buildNotesTab(),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.dashboard, color: FluxForgeTheme.accentBlue, size: 24),
          const SizedBox(width: 12),
          Text(
            'PROJECT DASHBOARD',
            style: FluxForgeTheme.body.copyWith(
              color: FluxForgeTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          _buildQuickStats(),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.close, color: FluxForgeTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Consumer2<SlotLabProjectProvider, MiddlewareProvider>(
      builder: (context, projectProvider, middlewareProvider, _) {
        final counts = projectProvider.getAudioAssignmentCounts();
        final symbolTotal = counts['symbol_total'] ?? 0;
        final musicTotal = counts['music_total'] ?? 0;
        final total = symbolTotal + musicTotal;
        const maxSlots = 341;
        final percent = maxSlots > 0 ? (total / maxSlots * 100).round() : 0;
        final events = middlewareProvider.compositeEvents.length;

        return Row(
          children: [
            _buildQuickStatBadge('$percent%', 'Coverage', _getCoverageColor(percent)),
            const SizedBox(width: 12),
            _buildQuickStatBadge('$events', 'Events', FluxForgeTheme.accentCyan),
            const SizedBox(width: 12),
            _buildQuickStatBadge('$total', 'Audio', FluxForgeTheme.accentOrange),
          ],
        );
      },
    );
  }

  Widget _buildQuickStatBadge(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: FluxForgeTheme.body.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: FluxForgeTheme.bodySmall.copyWith(
              color: color.withValues(alpha: 0.8),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 44,
      color: FluxForgeTheme.bgSurface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: FluxForgeTheme.accentBlue,
        labelColor: FluxForgeTheme.accentBlue,
        unselectedLabelColor: FluxForgeTheme.textSecondary,
        labelStyle: FluxForgeTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
        tabs: const [
          Tab(icon: Icon(Icons.dashboard, size: 18), text: 'Overview'),
          Tab(icon: Icon(Icons.pie_chart, size: 18), text: 'Coverage'),
          Tab(icon: Icon(Icons.verified, size: 18), text: 'Validation'),
          Tab(icon: Icon(Icons.notes, size: 18), text: 'Notes'),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // OVERVIEW TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    return Consumer2<SlotLabProjectProvider, MiddlewareProvider>(
      builder: (context, projectProvider, middlewareProvider, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Project Summary', Icons.info_outline),
              const SizedBox(height: 16),
              _buildProjectSummaryCards(projectProvider, middlewareProvider),
              const SizedBox(height: 32),
              _buildSectionHeader('Audio Coverage', Icons.music_note),
              const SizedBox(height: 16),
              _buildCoverageProgress(projectProvider),
              const SizedBox(height: 32),
              _buildSectionHeader('Recent Activity', Icons.history),
              const SizedBox(height: 16),
              _buildRecentActivity(middlewareProvider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: FluxForgeTheme.accentBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: FluxForgeTheme.body.copyWith(
            color: FluxForgeTheme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildProjectSummaryCards(
    SlotLabProjectProvider projectProvider,
    MiddlewareProvider middlewareProvider,
  ) {
    final gdd = projectProvider.importedGdd;
    final symbols = projectProvider.symbols.length;
    final contexts = projectProvider.contexts.length;
    final events = middlewareProvider.compositeEvents.length;
    final containers = middlewareProvider.blendContainers.length +
        middlewareProvider.randomContainers.length +
        middlewareProvider.sequenceContainers.length;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSummaryCard(
          'Game',
          gdd?.name ?? 'Untitled Project',
          Icons.sports_esports,
          FluxForgeTheme.accentCyan,
        ),
        _buildSummaryCard(
          'Grid',
          gdd != null ? '${gdd.grid.columns}×${gdd.grid.rows}' : '5×3',
          Icons.grid_on,
          FluxForgeTheme.accentOrange,
        ),
        _buildSummaryCard(
          'Symbols',
          symbols.toString(),
          Icons.category,
          FluxForgeTheme.accentPurple,
        ),
        _buildSummaryCard(
          'Contexts',
          contexts.toString(),
          Icons.layers,
          FluxForgeTheme.accentGreen,
        ),
        _buildSummaryCard(
          'Events',
          events.toString(),
          Icons.event,
          FluxForgeTheme.accentBlue,
        ),
        _buildSummaryCard(
          'Containers',
          containers.toString(),
          Icons.inventory_2,
          FluxForgeTheme.accentRed,
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: FluxForgeTheme.body.copyWith(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCoverageProgress(SlotLabProjectProvider provider) {
    final counts = provider.getAudioAssignmentCounts();
    final symbolTotal = counts['symbol_total'] ?? 0;
    final musicTotal = counts['music_total'] ?? 0;
    final total = symbolTotal + musicTotal;
    const maxSlots = 341;
    final percent = maxSlots > 0 ? total / maxSlots : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Audio Assignment Progress',
                style: FluxForgeTheme.body.copyWith(
                  color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$total / $maxSlots (${(percent * 100).round()}%)',
                style: FluxForgeTheme.body.copyWith(
                  color: _getCoverageColor((percent * 100).round()),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 12,
              backgroundColor: FluxForgeTheme.bgMid,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getCoverageColor((percent * 100).round()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildCoverageDetail('Symbols', symbolTotal, FluxForgeTheme.accentPurple),
              const SizedBox(width: 24),
              _buildCoverageDetail('Music Layers', musicTotal, FluxForgeTheme.accentCyan),
              const SizedBox(width: 24),
              _buildCoverageDetail('Remaining', maxSlots - total, FluxForgeTheme.textTertiary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoverageDetail(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: $count',
          style: FluxForgeTheme.bodySmall.copyWith(
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity(MiddlewareProvider provider) {
    final events = provider.compositeEvents.take(5).toList();

    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Center(
          child: Text(
            'No events created yet',
            style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: events.map((event) {
          final layerCount = event.layers.length;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.audiotrack, size: 16, color: FluxForgeTheme.accentBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    event.name,
                    style: FluxForgeTheme.bodySmall.copyWith(
                      color: FluxForgeTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$layerCount layer${layerCount == 1 ? '' : 's'}',
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // COVERAGE TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildCoverageTab() {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, provider, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Coverage by Section', Icons.pie_chart),
              const SizedBox(height: 16),
              _buildSectionCoverageList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCoverageList() {
    // Section definitions matching UltimateAudioPanel V8
    final sections = [
      ('Base Game Loop', 41, Icons.refresh, FluxForgeTheme.accentBlue),
      ('Symbols & Lands', 46, Icons.category, FluxForgeTheme.accentPurple),
      ('Win Presentation', 41, Icons.star, FluxForgeTheme.accentYellow),
      ('Cascading Mechanics', 24, Icons.water_drop, FluxForgeTheme.accentRed),
      ('Multipliers', 18, Icons.close, FluxForgeTheme.accentOrange),
      ('Free Spins', 24, Icons.redeem, FluxForgeTheme.accentGreen),
      ('Bonus Games', 32, Icons.card_giftcard, FluxForgeTheme.accentPurple),
      ('Hold & Win', 24, Icons.lock, FluxForgeTheme.accentCyan),
      ('Jackpots', 26, Icons.emoji_events, FluxForgeTheme.accentYellow),
      ('Gamble', 16, Icons.casino, FluxForgeTheme.accentRed),
      ('Music & Ambience', 27, Icons.music_note, FluxForgeTheme.accentCyan),
      ('UI & System', 22, Icons.computer, FluxForgeTheme.textTertiary),
    ];

    return Column(
      children: sections.map((section) {
        final (name, slots, icon, color) = section;
        // TODO: Get actual assigned count from provider
        final assigned = 0; // Placeholder - would need section-specific counting
        final percent = slots > 0 ? (assigned / slots * 100).round() : 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: FluxForgeTheme.bodySmall.copyWith(
                        color: FluxForgeTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent / 100,
                        minHeight: 6,
                        backgroundColor: FluxForgeTheme.bgMid,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$assigned/$slots',
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // VALIDATION TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildValidationTab() {
    return Consumer2<SlotLabProjectProvider, MiddlewareProvider>(
      builder: (context, projectProvider, middlewareProvider, _) {
        final validations = _runValidations(projectProvider, middlewareProvider);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Export Validation', Icons.verified),
              const SizedBox(height: 8),
              Text(
                'Pre-flight checks before packaging your audio for export.',
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 24),
              _buildValidationSummary(validations),
              const SizedBox(height: 24),
              ...validations.map((v) => _buildValidationItem(v)),
            ],
          ),
        );
      },
    );
  }

  List<_ValidationResult> _runValidations(
    SlotLabProjectProvider projectProvider,
    MiddlewareProvider middlewareProvider,
  ) {
    final results = <_ValidationResult>[];

    // Check 1: Has events
    final eventCount = middlewareProvider.compositeEvents.length;
    results.add(_ValidationResult(
      name: 'Events Created',
      description: 'At least one audio event should be defined',
      passed: eventCount > 0,
      value: '$eventCount events',
      severity: _ValidationSeverity.critical,
    ));

    // Check 2: Core stages covered
    final coreStages = ['SPIN_START', 'REEL_STOP', 'WIN_PRESENT'];
    final coveredCoreStages = coreStages.where((stage) {
      return middlewareProvider.compositeEvents.any(
        (e) => e.triggerStages.any((s) => s.contains(stage)),
      );
    }).length;
    results.add(_ValidationResult(
      name: 'Core Stages',
      description: 'Essential gameplay stages should have audio',
      passed: coveredCoreStages >= 2,
      value: '$coveredCoreStages/${coreStages.length} covered',
      severity: _ValidationSeverity.warning,
    ));

    // Check 3: Audio files exist
    int missingFiles = 0;
    int totalFiles = 0;
    for (final event in middlewareProvider.compositeEvents) {
      for (final layer in event.layers) {
        totalFiles++;
        final path = layer.audioPath;
        if (path.isNotEmpty && !File(path).existsSync()) {
          missingFiles++;
        }
      }
    }
    results.add(_ValidationResult(
      name: 'Audio Files',
      description: 'All referenced audio files should exist',
      passed: missingFiles == 0,
      value: missingFiles == 0 ? '$totalFiles files OK' : '$missingFiles missing',
      severity: _ValidationSeverity.critical,
    ));

    // Check 4: Coverage percentage
    final counts = projectProvider.getAudioAssignmentCounts();
    final symbolTotal = counts['symbol_total'] ?? 0;
    final musicTotal = counts['music_total'] ?? 0;
    final total = symbolTotal + musicTotal;
    const maxSlots = 341;
    final coveragePercent = maxSlots > 0 ? (total / maxSlots * 100).round() : 0;
    results.add(_ValidationResult(
      name: 'Audio Coverage',
      description: 'Recommended: at least 25% of audio slots assigned',
      passed: coveragePercent >= 25,
      value: '$coveragePercent%',
      severity: _ValidationSeverity.info,
    ));

    // Check 5: GDD imported
    final hasGdd = projectProvider.importedGdd != null;
    results.add(_ValidationResult(
      name: 'Game Design',
      description: 'GDD import helps with proper stage generation',
      passed: hasGdd,
      value: hasGdd ? 'Imported' : 'Not imported',
      severity: _ValidationSeverity.info,
    ));

    // Check 6: Symbols defined
    final symbolCount = projectProvider.symbols.length;
    results.add(_ValidationResult(
      name: 'Symbol Setup',
      description: 'Symbol definitions for proper audio mapping',
      passed: symbolCount >= 5,
      value: '$symbolCount symbols',
      severity: _ValidationSeverity.warning,
    ));

    return results;
  }

  Widget _buildValidationSummary(List<_ValidationResult> validations) {
    final passed = validations.where((v) => v.passed).length;
    final failed = validations.length - passed;
    final criticalFailed = validations.where(
      (v) => !v.passed && v.severity == _ValidationSeverity.critical,
    ).length;

    final allPassed = failed == 0;
    final hasCritical = criticalFailed > 0;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (allPassed) {
      statusColor = FluxForgeTheme.accentGreen;
      statusText = 'Ready for Export';
      statusIcon = Icons.check_circle;
    } else if (hasCritical) {
      statusColor = FluxForgeTheme.accentRed;
      statusText = 'Critical Issues Found';
      statusIcon = Icons.error;
    } else {
      statusColor = FluxForgeTheme.accentOrange;
      statusText = 'Warnings Found';
      statusIcon = Icons.warning;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 48, color: statusColor),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: FluxForgeTheme.body.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$passed of ${validations.length} checks passed',
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationItem(_ValidationResult validation) {
    Color color;
    IconData icon;

    if (validation.passed) {
      color = FluxForgeTheme.accentGreen;
      icon = Icons.check_circle;
    } else {
      switch (validation.severity) {
        case _ValidationSeverity.critical:
          color = FluxForgeTheme.accentRed;
          icon = Icons.error;
        case _ValidationSeverity.warning:
          color = FluxForgeTheme.accentOrange;
          icon = Icons.warning;
        case _ValidationSeverity.info:
          color = FluxForgeTheme.accentBlue;
          icon = Icons.info;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  validation.name,
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  validation.description,
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              validation.value,
              style: FluxForgeTheme.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // NOTES TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildNotesTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionHeader('Project Notes', Icons.notes),
              const Spacer(),
              TextButton.icon(
                icon: Icon(
                  _notesEditing ? Icons.check : Icons.edit,
                  size: 16,
                ),
                label: Text(_notesEditing ? 'Save' : 'Edit'),
                onPressed: () {
                  setState(() {
                    if (_notesEditing) {
                      _projectNotes = _notesController.text;
                    } else {
                      _notesController.text = _projectNotes;
                    }
                    _notesEditing = !_notesEditing;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Add notes about your project, requirements, or delivery instructions.',
            style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _notesEditing
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: _notesEditing
                  ? TextField(
                      controller: _notesController,
                      maxLines: null,
                      expands: true,
                      style: FluxForgeTheme.bodySmall.copyWith(
                        color: FluxForgeTheme.textPrimary,
                        height: 1.6,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Enter project notes here...\n\n'
                            'You can include:\n'
                            '- Delivery requirements\n'
                            '- Sound design notes\n'
                            '- Target platforms\n'
                            '- Team contacts',
                        hintStyle: FluxForgeTheme.bodySmall.copyWith(
                          color: FluxForgeTheme.textTertiary,
                        ),
                      ),
                    )
                  : _projectNotes.isEmpty
                      ? Center(
                          child: Text(
                            'No notes yet. Click Edit to add project notes.',
                            style: FluxForgeTheme.bodySmall.copyWith(
                              color: FluxForgeTheme.textTertiary,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Text(
                            _projectNotes,
                            style: FluxForgeTheme.bodySmall.copyWith(
                              color: FluxForgeTheme.textPrimary,
                              height: 1.6,
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FOOTER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildFooter() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.file_download, size: 18),
            label: const Text('Export Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: _exportReport,
          ),
        ],
      ),
    );
  }

  void _exportReport() {
    // TODO: Implement report export to markdown/JSON
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report export coming soon!'),
        backgroundColor: FluxForgeTheme.accentBlue,
      ),
    );
  }

  Color _getCoverageColor(int percent) {
    if (percent >= 75) return FluxForgeTheme.accentGreen;
    if (percent >= 25) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// VALIDATION MODELS
// ════════════════════════════════════════════════════════════════════════════

enum _ValidationSeverity { critical, warning, info }

class _ValidationResult {
  final String name;
  final String description;
  final bool passed;
  final String value;
  final _ValidationSeverity severity;

  const _ValidationResult({
    required this.name,
    required this.description,
    required this.passed,
    required this.value,
    required this.severity,
  });
}
