/// Project Dashboard Dialog (M1 Task 4) — ULTIMATE VERSION
///
/// Comprehensive project overview for Producers and Product Owners.
/// Shows progress metrics, export validation, and project notes.
///
/// Features:
/// - Audio coverage by section (REAL DATA from provider)
/// - Export readiness validation (6+ checks)
/// - Project notes (PERSISTED in provider)
/// - Quick stats and metrics
/// - Export to Markdown report

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../providers/middleware_provider.dart';
import '../../services/gdd_import_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Project Dashboard Dialog
class ProjectDashboardDialog extends StatefulWidget {
  final int initialTab;

  const ProjectDashboardDialog({super.key, this.initialTab = 0});

  /// Show the dashboard dialog
  static Future<void> show(BuildContext context, {int initialTab = 0}) {
    return showDialog(
      context: context,
      builder: (context) => ProjectDashboardDialog(initialTab: initialTab),
    );
  }

  @override
  State<ProjectDashboardDialog> createState() => _ProjectDashboardDialogState();
}

class _ProjectDashboardDialogState extends State<ProjectDashboardDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _notesEditing = false;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 7,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 6),
    );
    // Load notes from provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SlotLabProjectProvider>();
      _notesController.text = provider.projectNotes;
    });
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
                  _buildPaytableTab(),
                  _buildRulesTab(),
                  _buildStatsTab(),
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
          Tab(icon: Icon(Icons.table_chart, size: 18), text: 'Paytable'),
          Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Rules'),
          Tab(icon: Icon(Icons.bar_chart, size: 18), text: 'Stats'),
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
    // Section definitions with icons and colors
    final sectionMeta = <String, (IconData, Color)>{
      'base_game_loop': (Icons.refresh, FluxForgeTheme.accentBlue),
      'symbols': (Icons.category, FluxForgeTheme.accentPurple),
      'win_presentation': (Icons.star, FluxForgeTheme.accentYellow),
      'cascading': (Icons.water_drop, FluxForgeTheme.accentRed),
      'multipliers': (Icons.close, FluxForgeTheme.accentOrange),
      'free_spins': (Icons.redeem, FluxForgeTheme.accentGreen),
      'bonus': (Icons.card_giftcard, FluxForgeTheme.accentPurple),
      'hold_win': (Icons.lock, FluxForgeTheme.accentCyan),
      'jackpots': (Icons.emoji_events, FluxForgeTheme.accentYellow),
      'gamble': (Icons.casino, FluxForgeTheme.accentRed),
      'music': (Icons.music_note, FluxForgeTheme.accentCyan),
      'ui_system': (Icons.computer, FluxForgeTheme.textTertiary),
    };

    return Consumer<SlotLabProjectProvider>(
      builder: (context, provider, _) {
        final coverageData = provider.getCoverageBySection();
        final sectionInfo = SlotLabProjectProvider.getSectionInfo();

        return Column(
          children: sectionInfo.map((section) {
            final (id, name, totalSlots) = section;
            final data = coverageData[id] ?? {'assigned': 0, 'total': totalSlots, 'percent': 0};
            final assigned = data['assigned'] ?? 0;
            final total = data['total'] ?? totalSlots;
            final percent = data['percent'] ?? 0;
            final meta = sectionMeta[id] ?? (Icons.folder, FluxForgeTheme.textTertiary);
            final (icon, color) = meta;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: percent >= 75
                      ? FluxForgeTheme.accentGreen.withValues(alpha: 0.4)
                      : percent >= 25
                          ? color.withValues(alpha: 0.3)
                          : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: FluxForgeTheme.bodySmall.copyWith(
                                color: FluxForgeTheme.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (percent >= 75) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.check_circle, size: 14, color: FluxForgeTheme.accentGreen),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent / 100,
                            minHeight: 6,
                            backgroundColor: FluxForgeTheme.bgMid,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              percent >= 75
                                  ? FluxForgeTheme.accentGreen
                                  : percent >= 25
                                      ? color
                                      : FluxForgeTheme.accentRed.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: percent >= 75
                          ? FluxForgeTheme.accentGreen.withValues(alpha: 0.15)
                          : percent >= 25
                              ? color.withValues(alpha: 0.15)
                              : FluxForgeTheme.accentRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$assigned/$total',
                      style: FluxForgeTheme.bodySmall.copyWith(
                        color: percent >= 75
                            ? FluxForgeTheme.accentGreen
                            : percent >= 25
                                ? color
                                : FluxForgeTheme.accentRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
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
        (e) => e.triggerStages.any((s) => s.toUpperCase().contains(stage)),
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
    final missingPaths = <String>[];
    for (final event in middlewareProvider.compositeEvents) {
      for (final layer in event.layers) {
        totalFiles++;
        final path = layer.audioPath;
        if (path.isNotEmpty && !File(path).existsSync()) {
          missingFiles++;
          if (missingPaths.length < 3) {
            missingPaths.add(path.split('/').last);
          }
        }
      }
    }
    results.add(_ValidationResult(
      name: 'Audio Files',
      description: missingFiles > 0
          ? 'Missing: ${missingPaths.join(", ")}${missingFiles > 3 ? "..." : ""}'
          : 'All referenced audio files should exist',
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

    // Check 7: Containers configured (NEW)
    final blendCount = middlewareProvider.blendContainers.length;
    final randomCount = middlewareProvider.randomContainers.length;
    final sequenceCount = middlewareProvider.sequenceContainers.length;
    final containerTotal = blendCount + randomCount + sequenceCount;
    results.add(_ValidationResult(
      name: 'Containers',
      description: 'Blend/Random/Sequence containers for dynamic audio',
      passed: containerTotal >= 0, // Info only, always passes
      value: 'B:$blendCount R:$randomCount S:$sequenceCount',
      severity: _ValidationSeverity.info,
    ));

    // Check 8: Audio formats (NEW)
    int wavCount = 0;
    int mp3Count = 0;
    int oggCount = 0;
    int otherCount = 0;
    for (final event in middlewareProvider.compositeEvents) {
      for (final layer in event.layers) {
        final path = layer.audioPath.toLowerCase();
        if (path.endsWith('.wav')) wavCount++;
        else if (path.endsWith('.mp3')) mp3Count++;
        else if (path.endsWith('.ogg')) oggCount++;
        else if (path.isNotEmpty) otherCount++;
      }
    }
    final hasNonWav = mp3Count > 0 || oggCount > 0 || otherCount > 0;
    results.add(_ValidationResult(
      name: 'Audio Formats',
      description: hasNonWav
          ? 'Recommend WAV for best quality (found: MP3=$mp3Count, OGG=$oggCount)'
          : 'WAV format recommended for lossless quality',
      passed: !hasNonWav || wavCount > (mp3Count + oggCount + otherCount),
      value: 'WAV:$wavCount MP3:$mp3Count OGG:$oggCount',
      severity: _ValidationSeverity.info,
    ));

    // Check 9: Win tiers configured (NEW)
    final winConfig = projectProvider.winConfiguration;
    final hasCustomWinConfig = winConfig.regularWins.tiers.isNotEmpty;
    results.add(_ValidationResult(
      name: 'Win Tiers',
      description: 'Win tier configuration for proper rollup audio',
      passed: hasCustomWinConfig,
      value: hasCustomWinConfig
          ? '${winConfig.regularWins.tiers.length} regular + ${winConfig.bigWins.tiers.length} big'
          : 'Using defaults',
      severity: _ValidationSeverity.info,
    ));

    // Check 10: Contexts defined (NEW)
    final contextCount = projectProvider.contexts.length;
    results.add(_ValidationResult(
      name: 'Game Contexts',
      description: 'Contexts for feature-specific audio (Base, FS, Bonus...)',
      passed: contextCount >= 2,
      value: '$contextCount contexts',
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
    return Consumer<SlotLabProjectProvider>(
      builder: (context, provider, _) {
        final currentNotes = provider.projectNotes;

        // Sync controller with provider when not editing
        if (!_notesEditing && _notesController.text != currentNotes) {
          _notesController.text = currentNotes;
        }

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildSectionHeader('Project Notes', Icons.notes),
                  const Spacer(),
                  if (currentNotes.isNotEmpty && !_notesEditing)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.save, size: 12, color: FluxForgeTheme.accentGreen),
                          const SizedBox(width: 4),
                          Text(
                            'Saved',
                            style: FluxForgeTheme.bodySmall.copyWith(
                              color: FluxForgeTheme.accentGreen,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    icon: Icon(
                      _notesEditing ? Icons.check : Icons.edit,
                      size: 16,
                    ),
                    label: Text(_notesEditing ? 'Save' : 'Edit'),
                    onPressed: () {
                      setState(() {
                        if (_notesEditing) {
                          // Save to provider (persists to project file)
                          provider.setProjectNotes(_notesController.text);
                        }
                        _notesEditing = !_notesEditing;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Add notes about your project, requirements, or delivery instructions. Notes are saved with your project.',
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
                      : currentNotes.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.notes, size: 48, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.3)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No notes yet',
                                    style: FluxForgeTheme.body.copyWith(
                                      color: FluxForgeTheme.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Click Edit to add project notes',
                                    style: FluxForgeTheme.bodySmall.copyWith(
                                      color: FluxForgeTheme.textTertiary.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SingleChildScrollView(
                              child: Text(
                                currentNotes,
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
      },
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

  Future<void> _exportReport() async {
    final projectProvider = context.read<SlotLabProjectProvider>();
    final middlewareProvider = context.read<MiddlewareProvider>();

    // Generate markdown report
    final report = _generateMarkdownReport(projectProvider, middlewareProvider);

    // Pick save location
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Project Report',
      fileName: 'slotlab_project_report.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
    );

    if (result != null) {
      try {
        await File(result).writeAsString(report);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Report saved to $result')),
                ],
              ),
              backgroundColor: FluxForgeTheme.accentGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save report: $e'),
              backgroundColor: FluxForgeTheme.accentRed,
            ),
          );
        }
      }
    }
  }

  String _generateMarkdownReport(
    SlotLabProjectProvider projectProvider,
    MiddlewareProvider middlewareProvider,
  ) {
    final gdd = projectProvider.importedGdd;
    final coverageData = projectProvider.getCoverageBySection();
    final sectionInfo = SlotLabProjectProvider.getSectionInfo();
    final validations = _runValidations(projectProvider, middlewareProvider);
    final counts = projectProvider.getAudioAssignmentCounts();
    final totalAssigned = (counts['symbol_total'] ?? 0) + (counts['music_total'] ?? 0);

    final buffer = StringBuffer();

    // Header
    buffer.writeln('# SlotLab Project Report');
    buffer.writeln();
    buffer.writeln('**Generated:** ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    // Project Summary
    buffer.writeln('## Project Summary');
    buffer.writeln();
    buffer.writeln('| Property | Value |');
    buffer.writeln('|----------|-------|');
    buffer.writeln('| Game | ${gdd?.name ?? "Untitled Project"} |');
    buffer.writeln('| Grid | ${gdd != null ? "${gdd.grid.columns}×${gdd.grid.rows}" : "5×3"} |');
    buffer.writeln('| Symbols | ${projectProvider.symbols.length} |');
    buffer.writeln('| Contexts | ${projectProvider.contexts.length} |');
    buffer.writeln('| Events | ${middlewareProvider.compositeEvents.length} |');
    buffer.writeln('| Total Audio Assigned | $totalAssigned / 341 |');
    buffer.writeln();

    // Coverage by Section
    buffer.writeln('## Coverage by Section');
    buffer.writeln();
    buffer.writeln('| Section | Assigned | Total | Progress |');
    buffer.writeln('|---------|----------|-------|----------|');
    for (final (id, name, total) in sectionInfo) {
      final data = coverageData[id] ?? {'assigned': 0, 'percent': 0};
      final assigned = data['assigned'] ?? 0;
      final percent = data['percent'] ?? 0;
      final progressBar = _generateProgressBar(percent);
      buffer.writeln('| $name | $assigned | $total | $progressBar $percent% |');
    }
    buffer.writeln();

    // Validation Results
    buffer.writeln('## Validation Results');
    buffer.writeln();
    final passed = validations.where((v) => v.passed).length;
    buffer.writeln('**Status:** $passed / ${validations.length} checks passed');
    buffer.writeln();
    buffer.writeln('| Check | Status | Value |');
    buffer.writeln('|-------|--------|-------|');
    for (final v in validations) {
      final status = v.passed ? '✅ PASS' : '❌ FAIL';
      buffer.writeln('| ${v.name} | $status | ${v.value} |');
    }
    buffer.writeln();

    // Events List
    buffer.writeln('## Events (${middlewareProvider.compositeEvents.length})');
    buffer.writeln();
    if (middlewareProvider.compositeEvents.isEmpty) {
      buffer.writeln('*No events created yet.*');
    } else {
      buffer.writeln('| Event Name | Layers | Trigger Stages |');
      buffer.writeln('|------------|--------|----------------|');
      for (final event in middlewareProvider.compositeEvents.take(50)) {
        final stages = event.triggerStages.take(3).join(', ');
        final suffix = event.triggerStages.length > 3 ? '...' : '';
        buffer.writeln('| ${event.name} | ${event.layers.length} | $stages$suffix |');
      }
      if (middlewareProvider.compositeEvents.length > 50) {
        buffer.writeln();
        buffer.writeln('*... and ${middlewareProvider.compositeEvents.length - 50} more events*');
      }
    }
    buffer.writeln();

    // Project Notes
    if (projectProvider.projectNotes.isNotEmpty) {
      buffer.writeln('## Project Notes');
      buffer.writeln();
      buffer.writeln(projectProvider.projectNotes);
      buffer.writeln();
    }

    // Footer
    buffer.writeln('---');
    buffer.writeln('*Report generated by FluxForge SlotLab*');

    return buffer.toString();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PAYTABLE TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPaytableTab() {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, projectProvider, _) {
        final gddSymbols = projectProvider.gddSymbols;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Paytable', Icons.table_chart),
              const SizedBox(height: 16),

              // Column headers
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 120, child: Text('Symbol', style: TextStyle(color: FluxForgeTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                    const SizedBox(width: 60, child: Text('×3', textAlign: TextAlign.center, style: TextStyle(color: FluxForgeTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                    const SizedBox(width: 60, child: Text('×4', textAlign: TextAlign.center, style: TextStyle(color: FluxForgeTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                    const SizedBox(width: 60, child: Text('×5', textAlign: TextAlign.center, style: TextStyle(color: FluxForgeTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                    const SizedBox(width: 80, child: Text('Type', textAlign: TextAlign.center, style: TextStyle(color: FluxForgeTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Symbol rows
              if (gddSymbols.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  child: const Center(
                    child: Text(
                      'No GDD imported. Import a Game Design Document to see paytable.',
                      style: TextStyle(color: FluxForgeTheme.textMuted),
                    ),
                  ),
                )
              else
                ...gddSymbols.map((symbol) => _buildPaytableRow(symbol)),

              const SizedBox(height: 24),
              _buildSectionHeader('Special Symbols', Icons.star),
              const SizedBox(height: 16),

              // Special symbols
              if (gddSymbols.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: const Text(
                    'Import GDD to see special symbols.',
                    style: TextStyle(color: FluxForgeTheme.textMuted),
                  ),
                )
              else
                ...gddSymbols
                    .where((s) => s.isWild || s.isScatter || s.isBonus ||
                        s.tier == SymbolTier.wild || s.tier == SymbolTier.scatter || s.tier == SymbolTier.bonus)
                    .map((symbol) => _buildSpecialSymbolCard(symbol)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaytableRow(GddSymbol symbol) {
    final isHighPay = symbol.tier == SymbolTier.premium || symbol.tier == SymbolTier.high;
    final color = isHighPay ? const Color(0xFFFFD700) : FluxForgeTheme.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: FluxForgeTheme.bgSurface)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Row(
              children: [
                Text(_getSymbolEmoji(symbol), style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    symbol.name,
                    style: TextStyle(color: color, fontWeight: isHighPay ? FontWeight.bold : FontWeight.normal, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 60, child: Text('${(symbol.payouts[3] ?? 0).toStringAsFixed(0)}', textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 12))),
          SizedBox(width: 60, child: Text('${(symbol.payouts[4] ?? 0).toStringAsFixed(0)}', textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 12))),
          SizedBox(width: 60, child: Text('${(symbol.payouts[5] ?? 0).toStringAsFixed(0)}', textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 12))),
          SizedBox(width: 80, child: Text(_tierLabel(symbol.tier), textAlign: TextAlign.center, style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildSpecialSymbolCard(GddSymbol symbol) {
    final color = symbol.isWild || symbol.tier == SymbolTier.wild
        ? const Color(0xFFFFD700)
        : (symbol.isScatter || symbol.tier == SymbolTier.scatter
            ? FluxForgeTheme.accentCyan
            : FluxForgeTheme.accentOrange);

    final description = symbol.isWild || symbol.tier == SymbolTier.wild
        ? 'Substitutes for all symbols except Scatter'
        : (symbol.isScatter || symbol.tier == SymbolTier.scatter
            ? '3+ anywhere triggers Free Spins'
            : '3+ triggers Bonus Game');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(_getSymbolEmoji(symbol), style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(symbol.name, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          if (symbol.payouts.isNotEmpty && symbol.payouts.values.any((p) => p > 0))
            Text(
              '×5: ${(symbol.payouts[5] ?? 0).toStringAsFixed(0)}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
        ],
      ),
    );
  }

  String _getSymbolEmoji(GddSymbol gdd) {
    final name = gdd.name.toLowerCase();
    if (name.contains('zeus') || name.contains('thunder')) return '⚡';
    if (name.contains('dragon')) return '🐉';
    if (name.contains('phoenix') || name.contains('fire')) return '🔥';
    if (name.contains('crown') || name.contains('king')) return '👑';
    if (name.contains('diamond')) return '💎';
    if (name.contains('gold') || name.contains('coin')) return '🪙';
    if (name.contains('star')) return '⭐';
    switch (gdd.tier) {
      case SymbolTier.premium: return '👑';
      case SymbolTier.high: return '💎';
      case SymbolTier.mid: return '🎲';
      case SymbolTier.low: return '🃏';
      case SymbolTier.wild: return '★';
      case SymbolTier.scatter: return '◆';
      case SymbolTier.bonus: return '♦';
      case SymbolTier.special: return '✦';
    }
  }

  String _tierLabel(SymbolTier tier) {
    return switch (tier) {
      SymbolTier.premium => 'Premium',
      SymbolTier.high => 'High Pay',
      SymbolTier.mid => 'Mid Pay',
      SymbolTier.low => 'Low Pay',
      SymbolTier.wild => 'Wild',
      SymbolTier.scatter => 'Scatter',
      SymbolTier.bonus => 'Bonus',
      SymbolTier.special => 'Special',
    };
  }

  // ════════════════════════════════════════════════════════════════════════════
  // RULES TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildRulesTab() {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, projectProvider, _) {
        final gdd = projectProvider.importedGdd;

        if (gdd == null) {
          return const Center(
            child: Text(
              'No GDD imported. Import a Game Design Document to see game rules.',
              style: TextStyle(color: FluxForgeTheme.textMuted),
            ),
          );
        }

        final grid = gdd.grid;
        final features = gdd.features;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Game Info Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [FluxForgeTheme.accentCyan.withOpacity(0.2), FluxForgeTheme.accentBlue.withOpacity(0.1)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: FluxForgeTheme.accentCyan.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sports_esports, color: FluxForgeTheme.accentCyan, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(gdd.name, style: const TextStyle(color: FluxForgeTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
                          Text('v${gdd.version}', style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionHeader('Grid Configuration', Icons.grid_on),
              const SizedBox(height: 12),
              _buildRuleRow('Grid Size', '${grid.columns}×${grid.rows} (${grid.columns * grid.rows} positions)'),
              _buildRuleRow('Mechanic', grid.mechanic.toUpperCase()),
              if (grid.paylines != null) _buildRuleRow('Paylines', '${grid.paylines} fixed, wins pay left to right'),
              if (grid.ways != null) _buildRuleRow('Ways', '${grid.ways} ways to win'),

              const SizedBox(height: 24),
              _buildSectionHeader('Features', Icons.auto_awesome),
              const SizedBox(height: 12),
              _buildRuleRow('Wild', 'Substitutes for all symbols except Scatter'),
              _buildRuleRow('Scatter', '3+ anywhere triggers Free Spins'),
              for (final feature in features)
                _buildRuleRow(feature.name, feature.triggerCondition ?? 'Feature enabled'),

              const SizedBox(height: 24),
              _buildSectionHeader('Math Model', Icons.calculate),
              const SizedBox(height: 12),
              _buildRuleRow('Target RTP', '${(gdd.math.rtp * 100).toStringAsFixed(2)}%'),
              _buildRuleRow('Volatility', gdd.math.volatility),
              _buildRuleRow('Hit Frequency', '${(gdd.math.hitFrequency * 100).toStringAsFixed(1)}%'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRuleRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(title, style: const TextStyle(color: FluxForgeTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // STATS TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildStatsTab() {
    return Consumer2<SlotLabProjectProvider, MiddlewareProvider>(
      builder: (context, projectProvider, middlewareProvider, _) {
        // Use available data from providers
        final symbols = projectProvider.symbols.length;
        final contexts = projectProvider.contexts.length;
        final events = middlewareProvider.compositeEvents.length;
        final counts = projectProvider.getAudioAssignmentCounts();
        final symbolAudio = counts['symbol_total'] ?? 0;
        final musicAudio = counts['music_total'] ?? 0;

        // Get SlotLabProvider for session data
        final slotLabProvider = context.watch<SlotLabProvider>();
        final spinCount = slotLabProvider.spinCount;
        final hitRate = slotLabProvider.hitRate;
        final lastWinAmount = slotLabProvider.lastWinAmount;
        final lastWinRatio = slotLabProvider.lastWinRatio;
        final betAmount = slotLabProvider.betAmount;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Project Statistics', Icons.bar_chart),
              const SizedBox(height: 16),

              // Stats Grid
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildStatCard('Symbols', '$symbols', Icons.category, FluxForgeTheme.accentPurple),
                  _buildStatCard('Contexts', '$contexts', Icons.layers, FluxForgeTheme.accentCyan),
                  _buildStatCard('Events', '$events', Icons.event, FluxForgeTheme.accentOrange),
                  _buildStatCard('Symbol Audio', '$symbolAudio', Icons.music_note, FluxForgeTheme.accentBlue),
                  _buildStatCard('Music Audio', '$musicAudio', Icons.audiotrack, FluxForgeTheme.accentGreen),
                  _buildStatCard('Total Audio', '${symbolAudio + musicAudio}', Icons.library_music, FluxForgeTheme.textPrimary),
                ],
              ),

              const SizedBox(height: 32),
              _buildSectionHeader('Current Session', Icons.analytics),
              const SizedBox(height: 16),

              // Session stats from SlotLabProvider
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildStatCard('Spins', '$spinCount', Icons.refresh, FluxForgeTheme.accentBlue),
                  _buildStatCard('Hit Rate', '${(hitRate * 100).toStringAsFixed(1)}%', Icons.check_circle, FluxForgeTheme.accentGreen),
                  _buildStatCard('Bet', '\$${betAmount.toStringAsFixed(2)}', Icons.attach_money, FluxForgeTheme.accentOrange),
                  _buildStatCard(
                    'Last Win',
                    lastWinAmount > 0 ? '\$${lastWinAmount.toStringAsFixed(2)}' : '-',
                    Icons.star,
                    lastWinAmount > 0 ? FluxForgeTheme.accentYellow : FluxForgeTheme.textTertiary,
                  ),
                  _buildStatCard(
                    'Win Ratio',
                    lastWinRatio > 0 ? '${lastWinRatio.toStringAsFixed(1)}x' : '-',
                    Icons.trending_up,
                    lastWinRatio >= 5 ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary,
                  ),
                ],
              ),

              const SizedBox(height: 32),
              _buildSectionHeader('Container Usage', Icons.inventory_2),
              const SizedBox(height: 16),

              // Container stats
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildStatCard('Blend', '${middlewareProvider.blendContainers.length}', Icons.tune, FluxForgeTheme.accentPurple),
                  _buildStatCard('Random', '${middlewareProvider.randomContainers.length}', Icons.shuffle, FluxForgeTheme.accentOrange),
                  _buildStatCard('Sequence', '${middlewareProvider.sequenceContainers.length}', Icons.view_timeline, FluxForgeTheme.accentCyan),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  String _generateProgressBar(int percent) {
    const total = 10;
    final filled = (percent / 10).round().clamp(0, total);
    final empty = total - filled;
    return '[${"█" * filled}${"░" * empty}]';
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
