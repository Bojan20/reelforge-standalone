/// AutoBind Dialog v2 — ultimativni UI za audio→stage binding.
///
/// Arhitektura:
/// - Koristi AutoBindEngine.analyze() za čistu analizu (nema side-effecta)
/// - Koristi AutoBindEngine.apply() za atomski apply sa rollback-om
/// - Prikazuje confidence score, match metod, i FFNC rename preview
/// - Virtual scrolling za 5000+ fajlova
/// - Manual override sa search + Levenshtein sugestijama
/// - Undo-safe: snapshot → apply, ne clearAll+loop
library auto_bind_dialog_v2;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

import '../../providers/slot_lab_project_provider.dart';
import '../../services/auto_bind/auto_bind_engine.dart';
import '../../services/auto_bind/binding_result.dart';
import '../../services/ffnc/ffnc_renamer.dart' hide StageSuggestion;
import '../../services/native_file_picker.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

// ──────────────────────────────────────────────────────────────────────────────
// RESULT
// ──────────────────────────────────────────────────────────────────────────────

class AutoBindV2Result {
  final String folderPath;
  final BindingAnalysis analysis;
  final bool didRename;
  final Map<int, double> busVolumes;

  const AutoBindV2Result({
    required this.folderPath,
    required this.analysis,
    required this.didRename,
    required this.busVolumes,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// DIALOG
// ──────────────────────────────────────────────────────────────────────────────

class AutoBindDialogV2 extends StatefulWidget {
  const AutoBindDialogV2({super.key});

  @override
  State<AutoBindDialogV2> createState() => _AutoBindDialogV2State();
}

class _AutoBindDialogV2State extends State<AutoBindDialogV2>
    with SingleTickerProviderStateMixin {

  // ── STATE ──────────────────────────────────────────────────────────────────
  String? _folderPath;
  BindingAnalysis? _analysis;
  bool _analyzing = false;
  bool _applying = false;

  // Options
  bool _doRename = true;
  final Map<int, double> _busVolumes = {0: 1.0, 1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0};

  // Tab controller: Matched | Unmatched | Warnings
  late TabController _tabController;

  // Search/filter
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Renamer (for FFNC name generation)
  FFNCRenamer? _renamer;

  // ── CONSTANTS ──────────────────────────────────────────────────────────────
  static const _busNames  = ['Master', 'Music', 'SFX', 'Voice', 'Ambience'];
  static const _busColors = [
    Color(0xFFFFFFFF), // Master
    Color(0xFF50D8FF), // Music
    Color(0xFF50FF98), // SFX
    Color(0xFFFF9850), // Voice
    Color(0xFF9080FF), // Ambience
  ];

  // ── LIFECYCLE ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });

    final knownStages = StageConfigurationService.instance
        .getAllStages().map((s) => s.name).toSet();
    _renamer = FFNCRenamer(knownStages: knownStages);

    // Open folder picker immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickFolder());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── FOLDER OPERATIONS ─────────────────────────────────────────────────────

  Future<void> _pickFolder() async {
    final path = await NativeFilePicker.pickDirectory(
      title: 'Select Sound Folder for Auto-Bind',
    );
    if (!mounted) return;
    if (path == null) { Navigator.of(context).pop(null); return; }
    setState(() { _folderPath = path; _analysis = null; });
    _runAnalysis(path);
  }

  Future<void> _changeFolderPath() async {
    final path = await NativeFilePicker.pickDirectory(
      title: 'Change Sound Folder',
    );
    if (path == null || !mounted) return;
    setState(() { _folderPath = path; _analysis = null; });
    _runAnalysis(path);
  }

  // ── ANALYSIS ──────────────────────────────────────────────────────────────

  void _runAnalysis(String folder) {
    setState(() => _analyzing = true);
    // Run in microtask so spinner renders first
    scheduleMicrotask(() {
      if (!mounted) return;
      final analysis = AutoBindEngine.analyze(folder);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _analyzing = false;
      });
    });
  }

  // ── MANUAL OVERRIDE ───────────────────────────────────────────────────────

  void _showOverridePicker(UnmatchedFile file) {
    final allStages = StageConfigurationService.instance
        .getAllStages().map((s) => s.name).toList()..sort();
    final searchCtl = TextEditingController();

    showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) {
          final q = searchCtl.text.toUpperCase();
          final filtered = q.isEmpty
              ? allStages.take(40).toList()
              : allStages.where((s) => s.contains(q)).take(40).toList();

          return AlertDialog(
            backgroundColor: FluxForgeTheme.bgMid,
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Assign: ${file.fileName}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                // Levenshtein suggestions
                if (file.suggestions.isNotEmpty) ...[
                  const Text('Suggested:', style: TextStyle(color: FluxForgeTheme.accentCyan, fontSize: 10)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4, runSpacing: 4,
                    children: file.suggestions.map((s) => GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(s.stage),
                      child: _SuggestionChip(suggestion: s),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: searchCtl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'Search stages...',
                    hintStyle: TextStyle(color: Colors.white24),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: FluxForgeTheme.accentCyan)),
                  ),
                  onChanged: (_) => setDs(() {}),
                ),
              ],
            ),
            content: SizedBox(
              width: 300, height: 280,
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => InkWell(
                  onTap: () => Navigator.of(ctx).pop(filtered[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    child: Text(
                      filtered[i],
                      style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
              ),
            ],
          );
        },
      ),
    ).then((stage) {
      if (stage == null || !mounted || _analysis == null) return;
      final ffncName = _renamer?.generateFFNCName(
        stage,
        _renamer!.categorizeStage(stage),
        p.extension(file.fileName),
      );
      setState(() {
        _analysis = _analysis!.withManualOverride(file, stage, ffncName: ffncName);
        // Switch to Matched tab
        if (_tabController.index == 1) _tabController.animateTo(0);
      });
    });
  }

  // ── APPLY ─────────────────────────────────────────────────────────────────

  Future<void> _apply() async {
    if (_analysis == null || _folderPath == null) return;
    setState(() => _applying = true);

    try {
      String effectivePath = _folderPath!;
      bool didRename = false;

      // Step 1: Rename to FFNC if requested
      if (_doRename && _renamer != null) {
        final matched = _analysis!.matched;
        if (matched.isNotEmpty) {
          final folderName = p.basename(_folderPath!);
          final parentDir = p.dirname(_folderPath!);
          final outputDir = p.join(parentDir, '${folderName}_ffnc');

          // Build FFNCRenameResult list from BindingMatch
          final renameResults = matched.map((m) {
            final category = _renamer!.categorizeStage(m.stage);
            final ffncName = m.ffncName ?? _renamer!.generateFFNCName(m.stage, category, p.extension(m.fileName));
            return FFNCRenameResult(
              originalPath: m.filePath,
              originalName: m.fileName,
              ffncName: ffncName,
              stage: m.stage,
              category: category,
              isExactMatch: true,
            );
          }).toList();

          // Copy unmatched as-is
          final unmatchedRenameResults = _analysis!.unmatched.map((u) =>
            FFNCRenameResult(originalPath: u.filePath, originalName: u.fileName),
          ).toList();

          final dir = Directory(outputDir);
          if (!dir.existsSync()) dir.createSync(recursive: true);
          await _renamer!.copyRenamed(renameResults, outputDir);
          for (final u in unmatchedRenameResults) {
            final src = File(u.originalPath);
            final dst = File(p.join(outputDir, u.originalName));
            if (src.existsSync() && !dst.existsSync()) await src.copy(dst.path);
          }

          effectivePath = outputDir;
          didRename = true;
        }
      }

      // Step 2: Re-analyze from effective path (renamed folder) if renamed
      BindingAnalysis finalAnalysis = _analysis!;
      if (didRename) {
        finalAnalysis = AutoBindEngine.analyze(effectivePath);
      }

      // Step 3: Transactional apply
      final provider = GetIt.instance<SlotLabProjectProvider>();
      AutoBindEngine.apply(finalAnalysis, provider);

      if (mounted) {
        setState(() => _applying = false);
        Navigator.of(context).pop(AutoBindV2Result(
          folderPath: effectivePath,
          analysis: finalAnalysis,
          didRename: didRename,
          busVolumes: Map.from(_busVolumes),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-Bind failed: $e'),
            backgroundColor: const Color(0xFF442222),
          ),
        );
      }
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Waiting for folder picker
    if (_folderPath == null) return _buildLoading('Select folder...');

    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildBusVolumes(),
            _buildTabBar(),
            Expanded(child: _analyzing ? _buildAnalyzing() : _buildTabContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final a = _analysis;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_fix_high, color: FluxForgeTheme.accentGreen, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Auto-Bind',
                style: TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (a != null) ...[
                _StatChip(
                  label: '${a.uniqueStageCount} stages',
                  color: FluxForgeTheme.accentGreen,
                ),
                const SizedBox(width: 6),
                _StatChip(
                  label: '${(a.matchRate * 100).round()}%',
                  color: a.matchRate > 0.8
                      ? FluxForgeTheme.accentGreen
                      : a.matchRate > 0.5
                          ? Colors.orange
                          : Colors.red,
                ),
                const SizedBox(width: 6),
                if (a.unmatchedCount > 0)
                  _StatChip(label: '${a.unmatchedCount} unmatched', color: Colors.orange),
              ],
              const SizedBox(width: 8),
              _buildCheckbox('Rename to FFNC', _doRename, (v) => setState(() => _doRename = v)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _folderPath ?? '',
                  style: const TextStyle(color: Colors.white24, fontSize: 9, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _changeFolderPath,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
                child: const Text('Change', style: TextStyle(color: FluxForgeTheme.accentCyan, fontSize: 9)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── BUS VOLUMES ───────────────────────────────────────────────────────────

  Widget _buildBusVolumes() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
      ),
      child: Row(
        children: List.generate(_busNames.length, (i) {
          final vol = _busVolumes[i] ?? 1.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _busNames[i],
                    style: TextStyle(color: _busColors[i].withValues(alpha: 0.6), fontSize: 8),
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                      activeTrackColor: _busColors[i],
                      thumbColor: _busColors[i],
                      inactiveTrackColor: Colors.white10,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: vol,
                      min: 0, max: 1,
                      onChanged: (v) => setState(() => _busVolumes[i] = v),
                    ),
                  ),
                  Text(
                    '${(vol * 100).round()}%',
                    style: TextStyle(color: _busColors[i].withValues(alpha: 0.4), fontSize: 8, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── TAB BAR ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    final a = _analysis;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tabController,
              indicatorColor: FluxForgeTheme.accentGreen,
              indicatorWeight: 1,
              labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 10),
              tabs: [
                Tab(text: a == null ? 'Matched' : 'Matched (${a.matchedCount})'),
                Tab(text: a == null ? 'Unmatched' : 'Unmatched (${a.unmatchedCount})'),
                Tab(text: a == null ? 'Warnings' : 'Warnings (${a.warnings.length})'),
              ],
            ),
          ),
          // Search box
          SizedBox(
            width: 160,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Filter...',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  prefixIcon: const Icon(Icons.search, size: 12, color: Colors.white24),
                  prefixIconConstraints: const BoxConstraints(minWidth: 24),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white12),
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: FluxForgeTheme.accentCyan),
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB CONTENT ───────────────────────────────────────────────────────────

  Widget _buildTabContent() {
    if (_analysis == null) return const SizedBox();
    return TabBarView(
      controller: _tabController,
      children: [
        _buildMatchedList(),
        _buildUnmatchedList(),
        _buildWarningsList(),
      ],
    );
  }

  Widget _buildMatchedList() {
    final a = _analysis!;
    // Group by stage, filter by search
    final entries = a.stageGroups.entries
        .where((e) => _searchQuery.isEmpty ||
            e.key.toLowerCase().contains(_searchQuery) ||
            e.value.any((m) => m.fileName.toLowerCase().contains(_searchQuery)))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (entries.isEmpty) {
      return const Center(child: Text('No matched files', style: TextStyle(color: Colors.white24, fontSize: 12)));
    }

    return ListView.builder(
      itemCount: entries.length,
      itemExtent: 36,
      itemBuilder: (_, i) {
        final entry = entries[i];
        final stage = entry.key;
        final group = entry.value;
        final primary = group.firstWhere((m) => !m.isVariant, orElse: () => group.first);
        final variantCount = group.where((m) => m.isVariant).length;

        return _MatchedRow(
          stage: stage,
          primary: primary,
          variantCount: variantCount,
          doRename: _doRename,
        );
      },
    );
  }

  Widget _buildUnmatchedList() {
    final unmatched = _analysis!.unmatched
        .where((u) => _searchQuery.isEmpty || u.fileName.toLowerCase().contains(_searchQuery))
        .toList();

    if (unmatched.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: FluxForgeTheme.accentGreen, size: 32),
            SizedBox(height: 8),
            Text('All files matched!', style: TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: unmatched.length,
      itemExtent: 38,
      itemBuilder: (_, i) {
        final u = unmatched[i];
        return _UnmatchedRow(
          file: u,
          onAssign: () => _showOverridePicker(u),
        );
      },
    );
  }

  Widget _buildWarningsList() {
    final warnings = _analysis!.warnings;
    if (warnings.isEmpty) {
      return const Center(
        child: Text('No warnings', style: TextStyle(color: Colors.white24, fontSize: 12)),
      );
    }
    return ListView.builder(
      itemCount: warnings.length,
      itemExtent: 40,
      itemBuilder: (_, i) {
        final w = warnings[i];
        final color = w.severity == WarningSeverity.error
            ? Colors.red
            : w.severity == WarningSeverity.warning
                ? Colors.orange
                : Colors.white54;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                w.severity == WarningSeverity.error ? Icons.error : Icons.warning,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(w.message, style: TextStyle(color: color, fontSize: 10)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalyzing() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: FluxForgeTheme.accentGreen)),
          SizedBox(height: 12),
          Text('Analyzing...', style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildLoading(String message) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 80),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(message, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ── FOOTER ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final a = _analysis;
    final canApply = a != null && !_applying && !_analyzing && a.matchedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          if (a != null)
            Text(
              '${a.uniqueStageCount} stages bound · ${a.totalFiles} total files',
              style: const TextStyle(color: Colors.white24, fontSize: 9),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: canApply ? _apply : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
              disabledBackgroundColor: Colors.white10,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            icon: _applying
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: FluxForgeTheme.accentGreen))
                : const Icon(Icons.auto_fix_high, size: 14, color: FluxForgeTheme.accentGreen),
            label: Text(
              _applying ? 'Applying...' : 'Auto-Bind & Apply',
              style: const TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            value ? Icons.check_box : Icons.check_box_outline_blank,
            size: 14,
            color: value ? FluxForgeTheme.accentGreen : Colors.white24,
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ──────────────────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final StageSuggestion suggestion;
  const _SuggestionChip({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final confidence = suggestion.score;
    final color = confidence > 70 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentCyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${suggestion.stage} ($confidence%)',
        style: TextStyle(color: color, fontSize: 9, fontFamily: 'monospace'),
      ),
    );
  }
}

class _MatchedRow extends StatelessWidget {
  final String stage;
  final BindingMatch primary;
  final int variantCount;
  final bool doRename;

  const _MatchedRow({
    required this.stage,
    required this.primary,
    required this.variantCount,
    required this.doRename,
  });

  @override
  Widget build(BuildContext context) {
    final methodColor = Color(primary.methodColor);
    final confidenceColor = primary.score >= 90
        ? const Color(0xFF50FF98)
        : primary.score >= 75
            ? const Color(0xFF50D8FF)
            : const Color(0xFFFF9850);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          // Stage name
          SizedBox(
            width: 168,
            child: Text(
              stage,
              style: const TextStyle(
                color: FluxForgeTheme.accentGreen,
                fontSize: 9,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Match method badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: methodColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: methodColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              primary.methodLabel,
              style: TextStyle(color: methodColor, fontSize: 7, fontWeight: FontWeight.w700),
            ),
          ),
          // Confidence score
          SizedBox(
            width: 28,
            child: Text(
              '${primary.score}',
              style: TextStyle(color: confidenceColor, fontSize: 9, fontFamily: 'monospace'),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          // Filename
          Expanded(
            child: Text(
              primary.fileName,
              style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // FFNC rename arrow
          if (doRename && primary.ffncName != null) ...[
            const Text(' → ', style: TextStyle(color: Colors.white12, fontSize: 8)),
            SizedBox(
              width: 130,
              child: Text(
                primary.ffncName!,
                style: const TextStyle(color: FluxForgeTheme.accentCyan, fontSize: 8, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          // Variant badge
          if (variantCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '+$variantCount',
                style: const TextStyle(color: Colors.white38, fontSize: 7),
              ),
            ),
          // Layer badge
          if (primary.layer != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF50D8FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF50D8FF).withValues(alpha: 0.3)),
              ),
              child: Text(
                'L${primary.layer}',
                style: const TextStyle(color: Color(0xFF50D8FF), fontSize: 7),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnmatchedRow extends StatelessWidget {
  final UnmatchedFile file;
  final VoidCallback onAssign;

  const _UnmatchedRow({required this.file, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 10, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              file.fileName,
              style: const TextStyle(color: Colors.white54, fontSize: 9, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Top suggestion
          if (file.suggestions.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              'Maybe: ${file.suggestions.first.stage}',
              style: const TextStyle(color: Colors.white24, fontSize: 8, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 4),
          ],
          // Assign button
          SizedBox(
            height: 20,
            child: TextButton(
              onPressed: onAssign,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: Colors.orange.withValues(alpha: 0.08),
              ),
              child: const Text(
                'Assign ▾',
                style: TextStyle(color: Colors.orange, fontSize: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RE-EXPORT COMPAT (keeps old callers working)
// ──────────────────────────────────────────────────────────────────────────────

// Old callers use EnhancedAutoBindResult — provide a compatible adapter.
// New code should use AutoBindV2Result directly.
class EnhancedAutoBindResultCompat {
  final String folderPath;
  final Map<String, String> bindings;
  final List<String> unmapped;
  final bool didRename;
  final Map<int, double> busVolumes;

  EnhancedAutoBindResultCompat.fromV2(AutoBindV2Result r)
      : folderPath = r.folderPath,
        bindings = {for (final e in r.analysis.stageGroups.entries)
          e.key: e.value.first.filePath},
        unmapped = r.analysis.unmatched.map((u) => u.fileName).toList(),
        didRename = r.didRename,
        busVolumes = r.busVolumes;
}
