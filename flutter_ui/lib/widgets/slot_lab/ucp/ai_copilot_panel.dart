import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/ai_copilot_provider.dart' as stub;
import '../../../services/ai_copilot_service.dart' as live;
import '../../../services/math_audio_bridge_service.dart';
import '../../../theme/fluxforge_theme.dart';

/// UCP-16: AI Co-Pilot™ Panel — Slot Audio AI Assistant (4.1.1 / 4.1.4)
///
/// Two modes:
///  - DEMO  → `AiCopilotProvider` (stub, style-driven, always available)
///  - LIVE  → `AiCopilotService` (real Rust FFI engine, requires PAR)
///
/// Auto-applicable live suggestions have an "Auto-fix" button that calls
/// `copilot_apply_action` FFI (4.1.1) and re-analyzes automatically.
class AiCopilotPanel extends StatefulWidget {
  const AiCopilotPanel({super.key});

  @override
  State<AiCopilotPanel> createState() => _AiCopilotPanelState();
}

enum _CopilotMode { demo, live }

class _AiCopilotPanelState extends State<AiCopilotPanel> {
  stub.AiCopilotProvider?   _provider;
  live.AiCopilotService?    _realSvc;
  MathAudioBridgeService?   _mathSvc;

  _CopilotMode _mode = _CopilotMode.demo;

  /// Rule IDs that have been successfully applied this session
  final Set<String> _appliedIds = {};

  final _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<stub.AiCopilotProvider>();
      _provider?.addListener(_onUpdate);
    } catch (_) {}
    try {
      _realSvc = GetIt.instance<live.AiCopilotService>();
      _realSvc?.addListener(_onUpdate);
    } catch (_) {}
    try {
      _mathSvc = GetIt.instance<MathAudioBridgeService>();
    } catch (_) {}
  }

  @override
  void dispose() {
    _provider?.removeListener(_onUpdate);
    _realSvc?.removeListener(_onUpdate);
    _chatController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  bool get _parAvailable  => _mathSvc?.lastMap != null;
  bool get _liveAnalyzed  => _realSvc?.lastReport != null;
  bool get _liveAnalyzing => _realSvc?.isAnalyzing ?? false;

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _runLiveAnalysis() async {
    final svc = _realSvc;
    final map = _mathSvc?.lastMap;
    if (svc == null || map == null) return;
    await svc.analyze(audioMap: map, par: map.source);
    if (mounted) setState(() {});
  }

  Future<void> _applyAction(String ruleId) async {
    final svc = _realSvc;
    if (svc == null || svc.lastProjectJson == null) return;

    // Re-analyze after action so report reflects the change
    final report = await svc.applyActionAndReanalyze(ruleId);
    if (!mounted) return;
    setState(() {
      if (report != null) _appliedIds.add(ruleId);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          report != null
              ? '✓ Auto-fix applied — project re-analyzed'
              : '✗ Auto-fix failed for $ruleId',
          style: FluxForgeTheme.dockSans(size: 11, color: Colors.white),
        ),
        backgroundColor: report != null
            ? const Color(0xFF0D2010)
            : const Color(0xFF2E0D0D),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _applyAllAutoActions() async {
    final report = _realSvc?.lastReport;
    if (report == null) return;
    final pending = report.autoApplicable
        .map((s) => s.ruleId)
        .where((id) => !_appliedIds.contains(id))
        .toList();
    for (final id in pending) {
      await _applyAction(id);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return Center(child: Text('AI Co-Pilot not available',
          style: FluxForgeTheme.dockSans(size: 12, color: Colors.grey)));
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 200, child: _buildScorePanel(p)),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: _buildSuggestionsPanel(p)),
        const SizedBox(width: 8),
        SizedBox(width: 220, child: _buildChatPanel(p)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCORE + LEFT PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildScorePanel(stub.AiCopilotProvider p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildHeader(p),
      const SizedBox(height: 8),
      if (_mode == _CopilotMode.demo) ...[
        if (p.qualityScore != null) ...[
          _buildDemoCircle(p.qualityScore!),
          const SizedBox(height: 8),
          _buildSubScore('Timing',        p.qualityScore!.timing),
          _buildSubScore('Loudness',      p.qualityScore!.loudness),
          _buildSubScore('Consistency',   p.qualityScore!.consistency),
          _buildSubScore('Best Practice', p.qualityScore!.bestPractice),
          _buildSubScore('Regulatory',    p.qualityScore!.regulatory),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _countBadge('${p.qualityScore!.criticalCount}',      'Critical', const Color(0xFFCC4444)),
            _countBadge('${p.qualityScore!.warningCount}',       'Warning',  const Color(0xFFCC8844)),
            _countBadge('${p.qualityScore!.totalSuggestions}',   'Total',    const Color(0xFF888888)),
          ]),
        ] else
          Center(child: Text('Click ▶ to analyze',
              style: FluxForgeTheme.dockSans(size: 9, color: const Color(0xFF555577)))),
        const SizedBox(height: 8),
        Text('Target Style', style: FluxForgeTheme.dockSans(
            size: 9, weight: FontWeight.w600, color: const Color(0xFF888888))),
        const SizedBox(height: 2),
        Expanded(child: SingleChildScrollView(
          child: Column(children: stub.SlotAudioStyle.values
              .map((s) => _styleOption(p, s)).toList()),
        )),
      ] else ...[
        // LIVE mode
        if (_liveAnalyzed) ...[
          _buildLiveCircle(_realSvc!.lastReport!.qualityScore),
          const SizedBox(height: 8),
          _buildLiveMetrics(),
          const SizedBox(height: 8),
          Expanded(child: _buildLiveSummary()),
        ] else
          _buildLiveWaiting(),
      ],
    ]);
  }

  Widget _buildHeader(stub.AiCopilotProvider p) {
    final analyzing = _mode == _CopilotMode.demo
        ? p.isAnalyzing
        : _liveAnalyzing;

    return Row(children: [
      const Icon(Icons.psychology, color: Color(0xFFCC44CC), size: 14),
      const SizedBox(width: 4),
      Text('AI Co-Pilot', style: FluxForgeTheme.dockSans(
          size: 10, weight: FontWeight.w600, color: const Color(0xFFCCCCCC))),
      const Spacer(),
      _modeToggle(),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: analyzing ? null : () {
          if (_mode == _CopilotMode.demo) {
            p.analyzeProject();
          } else {
            _runLiveAnalysis();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFCC44CC).withAlpha(20),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFFCC44CC).withAlpha(60), width: 0.5),
          ),
          child: Text(analyzing ? '…' : '▶',
              style: FluxForgeTheme.dockSans(size: 9, color: const Color(0xFFCC44CC))),
        ),
      ),
    ]);
  }

  Widget _modeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _modeTile('DEMO', _CopilotMode.demo, const Color(0xFFCC44CC)),
        _modeTile('LIVE', _CopilotMode.live, const Color(0xFF44CC88)),
      ]),
    );
  }

  Widget _modeTile(String label, _CopilotMode mode, Color activeColor) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: active ? activeColor.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(label, style: FluxForgeTheme.dockSans(
            size: 7, weight: FontWeight.w700,
            color: active ? activeColor : const Color(0xFF555577))),
      ),
    );
  }

  Widget _buildDemoCircle(stub.QualityScore score) {
    return Center(child: Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _scoreColor(score.overall).withAlpha(120), width: 2),
        color: _scoreColor(score.overall).withAlpha(20),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(score.grade, style: FluxForgeTheme.dockSans(
            size: 18, weight: FontWeight.w800, color: _scoreColor(score.overall))),
        Text('${score.overall.toStringAsFixed(0)}',
            style: FluxForgeTheme.dockMono(size: 9, color: _scoreColor(score.overall))),
      ]),
    ));
  }

  Widget _buildLiveCircle(int score) {
    final c = Color(live.AiCopilotService.qualityScoreColor(score));
    return Center(child: Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.withAlpha(120), width: 2),
        color: c.withAlpha(20),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('$score', style: FluxForgeTheme.dockMono(
            size: 18, weight: FontWeight.w800, color: c)),
        Text('/100', style: FluxForgeTheme.dockMono(size: 8, color: c)),
      ]),
    ));
  }

  Widget _buildLiveMetrics() {
    final r = _realSvc!.lastReport!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _metricRow('Reference',  r.closestReference, const Color(0xFF8866FF)),
      _metricRow('Match',      '${r.industryMatchPct}%', const Color(0xFF44AACC)),
      _metricRow('Critical',   '${r.criticals.length}',
          r.hasCriticals ? const Color(0xFFCC4444) : const Color(0xFF444466)),
      _metricRow('Warnings',   '${r.warnings.length}',
          r.warnings.isNotEmpty ? const Color(0xFFDD8822) : const Color(0xFF444466)),
      _metricRow('Auto-fix',   '${r.autoApplicable.length}',
          r.autoApplicable.isNotEmpty ? const Color(0xFF44CC88) : const Color(0xFF444466)),
    ]);
  }

  Widget _metricRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        SizedBox(width: 58, child: Text(label,
            style: FluxForgeTheme.dockSans(size: 8, color: const Color(0xFF888888)))),
        Text(value, style: FluxForgeTheme.dockMono(size: 9, color: color)),
      ]),
    );
  }

  Widget _buildLiveSummary() {
    final summary = _realSvc?.lastReport?.summary ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Summary', style: FluxForgeTheme.dockSans(
          size: 8, weight: FontWeight.w600, color: const Color(0xFF888888))),
      const SizedBox(height: 4),
      Text(summary, style: FluxForgeTheme.dockSans(
          size: 8, color: const Color(0xFFAAAAAA)).copyWith(height: 1.4)),
    ]);
  }

  Widget _buildLiveWaiting() {
    if (_liveAnalyzing) {
      return const Center(child: SizedBox(
        width: 24, height: 24,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF44CC88)),
      ));
    }
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(
        _parAvailable ? Icons.play_circle_outline : Icons.upload_file,
        size: 28, color: const Color(0xFF555577),
      ),
      const SizedBox(height: 6),
      Text(
        _parAvailable ? 'Click ▶ to analyze' : 'Import PAR first',
        style: FluxForgeTheme.dockSans(size: 9, color: const Color(0xFF555577)),
      ),
    ]));
  }

  // ─── Score sub-components ─────────────────────────────────────────────────

  Widget _buildSubScore(String label, double score) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        SizedBox(width: 70, child: Text(label,
            style: FluxForgeTheme.dockSans(size: 9, color: const Color(0xFF888888)))),
        Expanded(child: Container(
          height: 6,
          decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A), borderRadius: BorderRadius.circular(3)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (score / 100).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                  color: _scoreColor(score), borderRadius: BorderRadius.circular(3)),
            ),
          ),
        )),
        const SizedBox(width: 4),
        SizedBox(width: 22, child: Text('${score.toStringAsFixed(0)}',
            textAlign: TextAlign.right,
            style: FluxForgeTheme.dockMono(size: 8, color: _scoreColor(score)))),
      ]),
    );
  }

  Widget _countBadge(String count, String label, Color color) {
    return Column(children: [
      Text(count, style: FluxForgeTheme.dockMono(
          size: 14, weight: FontWeight.w700, color: color)),
      Text(label, style: FluxForgeTheme.dockSans(size: 7, color: const Color(0xFF888888))),
    ]);
  }

  Color _scoreColor(double score) {
    if (score >= 80) return const Color(0xFF44CC44);
    if (score >= 60) return const Color(0xFFCCCC44);
    if (score >= 40) return const Color(0xFFCC8844);
    return const Color(0xFFCC4444);
  }

  Widget _styleOption(stub.AiCopilotProvider p, stub.SlotAudioStyle s) {
    final active = p.targetStyle == s;
    return GestureDetector(
      onTap: () => p.setTargetStyle(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2A2A4E) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(children: [
          Icon(active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 10,
              color: active ? const Color(0xFFCC44CC) : const Color(0xFF555577)),
          const SizedBox(width: 4),
          Text(s.displayName, style: FluxForgeTheme.dockSans(
              size: 9,
              color: active ? const Color(0xFFCCCCCC) : const Color(0xFF888888))),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUGGESTIONS PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSuggestionsPanel(stub.AiCopilotProvider p) {
    if (_mode == _CopilotMode.live) return _buildLiveSuggestionsPanel();
    return _buildDemoSuggestionsPanel(p);
  }

  // ─── Demo ─────────────────────────────────────────────────────────────────

  Widget _buildDemoSuggestionsPanel(stub.AiCopilotProvider p) {
    final active = p.activeSuggestions;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.lightbulb_outline, color: Color(0xFF888888), size: 14),
        const SizedBox(width: 6),
        Text('Suggestions (${active.length})',
            style: FluxForgeTheme.dockSans(size: 11,
                weight: FontWeight.w600, color: const Color(0xFFCCCCCC))),
        const Spacer(),
        if (p.suggestions.any((s) => s.dismissed))
          GestureDetector(
            onTap: () => p.clearDismissed(),
            child: Text('Clear dismissed',
                style: FluxForgeTheme.dockSans(size: 8, color: const Color(0xFF555577))),
          ),
      ]),
      const SizedBox(height: 4),
      Expanded(
        child: active.isEmpty
            ? Center(child: Text(
                p.qualityScore != null
                    ? 'All suggestions resolved!'
                    : 'Run analysis to get suggestions',
                style: FluxForgeTheme.dockSans(size: 10, color: const Color(0xFF555577))))
            : ListView.builder(
                itemCount: active.length,
                itemBuilder: (_, i) => _buildDemoCard(p, active[i]),
              ),
      ),
    ]);
  }

  Widget _buildDemoCard(stub.AiCopilotProvider p, stub.CopilotSuggestion s) {
    final severityColor = switch (s.severity) {
      stub.SuggestionSeverity.info       => const Color(0xFF4488CC),
      stub.SuggestionSeverity.suggestion => const Color(0xFF44CC88),
      stub.SuggestionSeverity.warning    => const Color(0xFFCC8844),
      stub.SuggestionSeverity.critical   => const Color(0xFFCC4444),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: severityColor.withAlpha(40), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _badge(s.severity.displayName, severityColor),
          const SizedBox(width: 4),
          _badge(s.category.displayName, Color(s.category.colorValue)),
          if (s.affectedStage != null) ...[
            const SizedBox(width: 4),
            Text(s.affectedStage!,
                style: FluxForgeTheme.dockMono(size: 7, color: const Color(0xFF555577))),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () => p.applySuggestion(s.id),
            child: _badge('Apply', const Color(0xFF44CC44)),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => p.dismissSuggestion(s.id),
            child: const Icon(Icons.close, size: 10, color: Color(0xFF555577)),
          ),
        ]),
        const SizedBox(height: 3),
        Text(s.title, style: FluxForgeTheme.dockSans(
            size: 10, weight: FontWeight.w600, color: const Color(0xFFCCCCCC))),
        const SizedBox(height: 2),
        Text(s.description, style: FluxForgeTheme.dockSans(
            size: 9, color: const Color(0xFF999999)).copyWith(height: 1.3)),
      ]),
    );
  }

  // ─── Live ─────────────────────────────────────────────────────────────────

  Widget _buildLiveSuggestionsPanel() {
    final report = _realSvc?.lastReport;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.auto_awesome, color: Color(0xFF44CC88), size: 14),
        const SizedBox(width: 6),
        Text(
          report != null
              ? 'Live Analysis (${report.suggestions.length})'
              : 'Live Analysis',
          style: FluxForgeTheme.dockSans(size: 11,
              weight: FontWeight.w600, color: const Color(0xFFCCCCCC)),
        ),
        const Spacer(),
        if (report != null && report.autoApplicable.isNotEmpty) ...[
          GestureDetector(
            onTap: _applyAllAutoActions,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF44CC88).withAlpha(20),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF44CC88).withAlpha(60), width: 0.5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_fix_high, size: 9, color: Color(0xFF44CC88)),
                const SizedBox(width: 3),
                Text('Fix all (${report.autoApplicable.length})',
                    style: FluxForgeTheme.dockSans(size: 8, color: const Color(0xFF44CC88))),
              ]),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 4),
      Expanded(child: _buildLiveSuggestionList(report)),
    ]);
  }

  Widget _buildLiveSuggestionList(live.CopilotReport? report) {
    if (report == null) {
      if (_liveAnalyzing) {
        return const Center(child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF44CC88)),
        ));
      }
      return Center(child: Text(
        _parAvailable
            ? 'Click ▶ to run live analysis'
            : 'Import a PAR document to enable live analysis',
        textAlign: TextAlign.center,
        style: FluxForgeTheme.dockSans(size: 10, color: const Color(0xFF555577)),
      ));
    }
    if (report.suggestions.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_outline, size: 32, color: Color(0xFF44CC44)),
        const SizedBox(height: 6),
        Text('No issues found!',
            style: FluxForgeTheme.dockSans(size: 11, color: const Color(0xFF44CC44))),
        Text('Quality score: ${report.qualityScore}/100',
            style: FluxForgeTheme.dockSans(size: 9, color: const Color(0xFF888888))),
      ]));
    }
    return ListView.builder(
      itemCount: report.suggestions.length,
      itemBuilder: (_, i) => _buildLiveCard(report.suggestions[i]),
    );
  }

  Widget _buildLiveCard(live.CopilotSuggestion s) {
    final applied = _appliedIds.contains(s.ruleId);
    final sevColor = Color(s.severity.colorValue);
    final catColor = Color(s.category.colorValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: applied ? const Color(0xFF0E1E0E) : const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: applied
              ? const Color(0xFF44CC44).withAlpha(60)
              : sevColor.withAlpha(50),
          width: 0.5,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Row 1: badges + rule ID + action button
        Row(children: [
          _badge(s.severity.displayName, sevColor),
          const SizedBox(width: 4),
          _badge(s.category.displayName, catColor),
          const SizedBox(width: 4),
          _badge(s.ruleId, const Color(0xFF555577), bg: const Color(0xFF0D0D1A)),
          const Spacer(),
          if (applied)
            _badge('✓ Applied', const Color(0xFF44CC44))
          else if (s.autoApplicable)
            GestureDetector(
              onTap: () => _applyAction(s.ruleId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF44CC88).withAlpha(25),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                      color: const Color(0xFF44CC88).withAlpha(80), width: 0.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_fix_high, size: 9, color: Color(0xFF44CC88)),
                  const SizedBox(width: 3),
                  Text('Auto-fix', style: FluxForgeTheme.dockSans(
                      size: 7, weight: FontWeight.w700, color: const Color(0xFF44CC88))),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(s.title, style: FluxForgeTheme.dockSans(
            size: 10, weight: FontWeight.w600, color: const Color(0xFFCCCCCC))),
        const SizedBox(height: 2),
        Text(s.description, style: FluxForgeTheme.dockSans(
            size: 9, color: const Color(0xFF999999)).copyWith(height: 1.35)),
        const SizedBox(height: 4),
        // Action hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(children: [
            const Icon(Icons.chevron_right, size: 10, color: Color(0xFF555577)),
            const SizedBox(width: 3),
            Expanded(child: Text(s.action, style: FluxForgeTheme.dockSans(
                size: 8, color: const Color(0xFF888888)).copyWith(height: 1.3))),
            if (s.benchmarkValue != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: catColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(s.benchmarkValue!,
                    style: FluxForgeTheme.dockMono(size: 7, color: catColor)),
              ),
            ],
          ]),
        ),
        if (s.affectedEvent != null) ...[
          const SizedBox(height: 2),
          Text('Event: ${s.affectedEvent}',
              style: FluxForgeTheme.dockMono(size: 7, color: const Color(0xFF555577))),
        ],
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAT PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChatPanel(stub.AiCopilotProvider p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.chat_bubble_outline, color: Color(0xFF888888), size: 14),
        const SizedBox(width: 6),
        Text('Ask Co-Pilot', style: FluxForgeTheme.dockSans(
            size: 11, weight: FontWeight.w600, color: const Color(0xFFCCCCCC))),
        const Spacer(),
        if (p.chatHistory.isNotEmpty)
          GestureDetector(
            onTap: () => p.clearChat(),
            child: const Icon(Icons.delete_outline, size: 12, color: Color(0xFF555577)),
          ),
      ]),
      const SizedBox(height: 4),
      Expanded(child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF2A2A4C), width: 0.5),
        ),
        child: p.chatHistory.isEmpty
            ? Center(child: Text(
                'Ask about:\n• Win sound design\n• Near-miss compliance\n'
                '• Export formats\n• Loop/ambient creation',
                textAlign: TextAlign.center,
                style: FluxForgeTheme.dockSans(size: 9, color: const Color(0xFF555577))))
            : ListView.builder(
                itemCount: p.chatHistory.length,
                itemBuilder: (_, i) {
                  final msg    = p.chatHistory[i];
                  final isUser = msg.startsWith('You:');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(msg,
                        style: FluxForgeTheme.dockSans(size: 9,
                            color: isUser
                                ? const Color(0xFF44AACC)
                                : const Color(0xFFCC44CC))
                            .copyWith(height: 1.3)),
                  );
                },
              ),
      )),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: SizedBox(
          height: 24,
          child: TextField(
            controller: _chatController,
            style: FluxForgeTheme.dockSans(size: 10, color: const Color(0xFFCCCCCC)),
            decoration: InputDecoration(
              hintText: 'Ask a question...',
              hintStyle: FluxForgeTheme.dockSans(size: 10, color: const Color(0xFF555577)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              filled: true,
              fillColor: const Color(0xFF0D0D1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: Color(0xFF2A2A4C), width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: Color(0xFF2A2A4C), width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: Color(0xFFCC44CC), width: 0.5),
              ),
            ),
            onSubmitted: (text) {
              if (text.trim().isNotEmpty) {
                p.askCopilot(text.trim());
                _chatController.clear();
              }
            },
          ),
        )),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () {
            final text = _chatController.text.trim();
            if (text.isNotEmpty) {
              p.askCopilot(text);
              _chatController.clear();
            }
          },
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFFCC44CC).withAlpha(30),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Icon(Icons.send, size: 12, color: Color(0xFFCC44CC)),
          ),
        ),
      ]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _badge(String label, Color color, {Color? bg}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: bg ?? color.withAlpha(30),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Text(label, style: FluxForgeTheme.dockSans(
        size: 7, weight: FontWeight.w700, color: color)),
  );
}
