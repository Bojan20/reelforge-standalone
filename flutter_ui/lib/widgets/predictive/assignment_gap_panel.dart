/// FAZA 4.4.3 — Assignment Gap Detector Panel
///
/// Prikazuje per-unbound-stage top-3 audio kandidate iz pool-a sortirane
/// po confidence-u. Korisnik može da klikne "Apply" da odmah assign-uje,
/// ili "Skip" da log-uje rejection (feedback loop 4.4.5).
///
/// Layout:
///
/// ```
///  ╭─ 🎯 GAP DETECTOR ─────────────────────────┬─ [↻] ─╮
///  │ 13 unbound stages · 7 sa suggestion-ima    │       │
///  ├────────────────────────────────────────────┴───────┤
///  │ ── REEL_STOP_3 (spin) ──                            │
///  │   ▸ reel_stop_metallic_03.wav   🎯 92%   [Apply]    │
///  │   ▸ reel_thud_v2.wav            👍 71%   [Apply]    │
///  │   ▸ stop_click.wav              🤔 48%   [Apply]    │
///  │                                                     │
///  │ ── WIN_BIG (win) ──                                 │
///  │   ▸ win_orch_swell.wav          🎯 87%   [Apply]    │
///  │   …                                                 │
///  ├─────────────────────────────────────────────────────┤
///  │ [ ⚡ AUTO-FILL ALL ≥75% (5 stages) ]                 │
///  ╰─────────────────────────────────────────────────────╯
/// ```
///
/// Reactive: listenuje na `SlotLabProjectProvider` (assignments) +
/// `AudioAssetManager` (pool); rebuild kad bilo koji promeni stanje.
///
/// Heavy lifting: `PredictiveAnalyzer.detectGapSuggestions()` — cache-uje
/// per-file FFI rezultate, tako da re-runs su jeftini (<1ms za 100 fajlova).
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/slot_lab_project_provider.dart';
import '../../services/audio_asset_manager.dart';
import '../../services/predictive/predictive_analyzer.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

class AssignmentGapPanel extends StatefulWidget {
  /// Opcionalni `topN` (default 3) — koliko suggestions po stage-u.
  final int topN;

  /// Min confidence threshold za uključivanje suggestiona (default 0.40).
  final double minConfidence;

  const AssignmentGapPanel({
    super.key,
    this.topN = 3,
    this.minConfidence = 0.40,
  });

  @override
  State<AssignmentGapPanel> createState() => _AssignmentGapPanelState();
}

class _AssignmentGapPanelState extends State<AssignmentGapPanel> {
  late final SlotLabProjectProvider _proj;
  late final AudioAssetManager _pool;
  late final StageConfigurationService _stages;
  late final PredictiveAnalyzer _analyzer;

  Map<String, List<({String path, double confidence})>> _suggestions = {};
  bool _isAnalyzing = false;
  DateTime? _lastAnalyzedAt;

  @override
  void initState() {
    super.initState();
    _proj = GetIt.instance<SlotLabProjectProvider>();
    _pool = AudioAssetManager.instance;
    _stages = StageConfigurationService.instance;
    _analyzer = GetIt.instance<PredictiveAnalyzer>();

    _proj.addListener(_onProjectChanged);
    _pool.addListener(_onPoolChanged);

    // Initial scan posle prvog frame-a (da ne block-uje initState).
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAnalysis());
  }

  @override
  void dispose() {
    _proj.removeListener(_onProjectChanged);
    _pool.removeListener(_onPoolChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (!mounted) return;
    // Re-run analyze kad se assignments promene (neki stage postao bound).
    // Light debounce: tek posle 250ms inactive.
    _scheduleReanalyze();
  }

  void _onPoolChanged() {
    if (!mounted) return;
    _scheduleReanalyze();
  }

  // Simple debounce — coalesce-uje brze promene.
  int _reanalyzeToken = 0;
  void _scheduleReanalyze() {
    _reanalyzeToken++;
    final token = _reanalyzeToken;
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || token != _reanalyzeToken) return;
      _runAnalysis();
    });
  }

  Future<void> _runAnalysis() async {
    if (!mounted) return;
    setState(() => _isAnalyzing = true);

    final bound = _proj.audioAssignments.keys.toSet();
    final all = _stages.allStages.map((s) => s.name).toSet();
    final unbound = all.difference(bound);

    final poolPaths = _pool.assets.map((a) => a.path).toList(growable: false);

    final result = await _analyzer.detectGapSuggestions(
      unboundStages: unbound,
      audioPoolPaths: poolPaths,
      topN: widget.topN,
      minConfidence: widget.minConfidence,
    );

    if (!mounted) return;
    setState(() {
      _suggestions = result;
      _isAnalyzing = false;
      _lastAnalyzedAt = DateTime.now();
    });
  }

  void _applySuggestion(String stage, String path, double confidence) {
    _proj.setAudioAssignment(stage, path);
    _analyzer.recordFeedback(
      audioPath: path,
      suggestedStage: stage,
      suggestedConfidence: confidence,
      actualStage: stage,
      accepted: true,
    );
  }

  void _skipSuggestion(String stage, String path, double confidence) {
    _analyzer.recordFeedback(
      audioPath: path,
      suggestedStage: stage,
      suggestedConfidence: confidence,
      actualStage: null,
      accepted: false,
    );
    // Lokalno ukloni suggestion da ne pravi shum (next refresh ga vraća
    // ako i dalje match-uje — ali se feedback log koristi za learning).
    setState(() {
      final list = _suggestions[stage];
      if (list == null) return;
      final filtered = list.where((s) => s.path != path).toList();
      if (filtered.isEmpty) {
        _suggestions.remove(stage);
      } else {
        _suggestions[stage] = filtered;
      }
    });
  }

  void _autoFillHigh() {
    final applied = <String>[];
    for (final entry in _suggestions.entries) {
      final stage = entry.key;
      if (entry.value.isEmpty) continue;
      final top = entry.value.first;
      if (top.confidence >= 0.75) {
        _applySuggestion(stage, top.path, top.confidence);
        applied.add(stage);
      }
    }
    if (mounted && applied.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-filled ${applied.length} stages (≥75% confidence)'),
          backgroundColor: FluxForgeTheme.accentGreen,
        ),
      );
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final highCount = _suggestions.values
        .where((list) => list.isNotEmpty && list.first.confidence >= 0.75)
        .length;

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.glassFill,
        border: Border.all(color: FluxForgeTheme.glassBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.glassBorder),
          Flexible(child: _buildBody()),
          if (highCount > 0) ...[
            const Divider(height: 1, color: FluxForgeTheme.glassBorder),
            _buildAutoFillFooter(highCount),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final unboundTotal =
        _stages.allStages.length - _proj.audioAssignments.length;
    final withSuggestions = _suggestions.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Text(
            '🎯 GAP DETECTOR',
            style: FluxForgeTheme.dockSans(
              size: 11,
              weight: FontWeight.w700,
              color: FluxForgeTheme.brandGold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$unboundTotal unbound · $withSuggestions sa suggestion-ima',
              style: FluxForgeTheme.dockSans(
                size: 10,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ),
          if (_isAnalyzing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: FluxForgeTheme.brandGold,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              tooltip: 'Re-skenira pool',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: FluxForgeTheme.textSecondary,
              onPressed: _runAnalysis,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isAnalyzing && _suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Analiziram audio pool…',
            style: FluxForgeTheme.dockSans(
              size: 11,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ),
      );
    }
    if (_suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _lastAnalyzedAt == null ? '—' : '✓ Nema unbound stage-ova',
                style: FluxForgeTheme.dockSans(
                  size: 12,
                  color: FluxForgeTheme.accentGreen,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _lastAnalyzedAt == null
                    ? 'Klikni ↻ da pokreneš analizu'
                    : 'Svi stage-ovi su bound (ili nema match-eva u pool-u)',
                style: FluxForgeTheme.dockSans(
                  size: 10,
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Sort stages by best confidence desc.
    final sortedEntries = _suggestions.entries.toList()
      ..sort((a, b) {
        final aBest = a.value.isEmpty ? 0.0 : a.value.first.confidence;
        final bBest = b.value.isEmpty ? 0.0 : b.value.first.confidence;
        return bBest.compareTo(aBest);
      });

    return ListView.builder(
      shrinkWrap: true,
      itemCount: sortedEntries.length,
      itemBuilder: (ctx, i) {
        final entry = sortedEntries[i];
        return _StageGapTile(
          stage: entry.key,
          suggestions: entry.value,
          stages: _stages,
          onApply: (path, conf) => _applySuggestion(entry.key, path, conf),
          onSkip: (path, conf) => _skipSuggestion(entry.key, path, conf),
        );
      },
    );
  }

  Widget _buildAutoFillFooter(int highCount) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          icon: const Icon(Icons.bolt, size: 14, color: FluxForgeTheme.brandGold),
          label: Text(
            'AUTO-FILL ALL ≥75% ($highCount stages)',
            style: FluxForgeTheme.dockSans(
              size: 10,
              weight: FontWeight.w700,
              color: FluxForgeTheme.brandGold,
              letterSpacing: 0.4,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: FluxForgeTheme.brandGold.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(
                color: FluxForgeTheme.brandGold.withValues(alpha: 0.4),
              ),
            ),
          ),
          onPressed: _autoFillHigh,
        ),
      ),
    );
  }
}

class _StageGapTile extends StatelessWidget {
  final String stage;
  final List<({String path, double confidence})> suggestions;
  final StageConfigurationService stages;
  final void Function(String path, double confidence) onApply;
  final void Function(String path, double confidence) onSkip;

  const _StageGapTile({
    required this.stage,
    required this.suggestions,
    required this.stages,
    required this.onApply,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final def = stages.allStages.where((s) => s.name == stage).firstOrNull;
    final categoryLabel = def == null ? '' : def.category.label;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                stage.toLowerCase(),
                style: FluxForgeTheme.dockSans(
                  size: 11,
                  weight: FontWeight.w700,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              if (categoryLabel.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    categoryLabel,
                    style: FluxForgeTheme.dockSans(
                      size: 8,
                      color: FluxForgeTheme.accentBlue,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          ...suggestions.map((s) => _SuggestionRow(
                path: s.path,
                confidence: s.confidence,
                onApply: () => onApply(s.path, s.confidence),
                onSkip: () => onSkip(s.path, s.confidence),
              )),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final String path;
  final double confidence;
  final VoidCallback onApply;
  final VoidCallback onSkip;

  const _SuggestionRow({
    required this.path,
    required this.confidence,
    required this.onApply,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final tier = confidenceTierOf(confidence);
    final (color, icon) = _tierStyle(tier);
    final basename = path.split('/').last;
    final pct = (confidence * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        children: [
          Text(icon, style: TextStyle(fontSize: 10, color: color)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              basename,
              overflow: TextOverflow.ellipsis,
              style: FluxForgeTheme.dockSans(
                size: 10,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: color, width: 1),
            ),
            child: Text(
              '$pct%',
              style: FluxForgeTheme.dockMono(
                size: 9,
                weight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _PillButton(
            label: 'Apply',
            color: FluxForgeTheme.accentGreen,
            onPressed: onApply,
          ),
          const SizedBox(width: 2),
          _PillButton(
            label: '✕',
            color: FluxForgeTheme.textTertiary,
            onPressed: onSkip,
            tooltip: 'Skip — log as rejected',
          ),
        ],
      ),
    );
  }

  (Color, String) _tierStyle(ConfidenceTier tier) {
    switch (tier) {
      case ConfidenceTier.high:
        return (FluxForgeTheme.accentGreen, '🎯');
      case ConfidenceTier.mid:
        return (FluxForgeTheme.accentYellow, '👍');
      case ConfidenceTier.low:
        return (FluxForgeTheme.accentOrange, '🤔');
      case ConfidenceTier.unclassified:
        return (FluxForgeTheme.textTertiary, '?');
    }
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final String? tooltip;

  const _PillButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          style: FluxForgeTheme.dockSans(
            size: 9,
            weight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );

    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
