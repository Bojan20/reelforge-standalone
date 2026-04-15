import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/ai_copilot_provider.dart';

/// UCP-16: AI Co-Pilot Panel — Slot Audio AI Assistant
///
/// Quality score dashboard, suggestion list with dismiss/apply,
/// style reference selector, and chat interface.
class AiCopilotPanel extends StatefulWidget {
  const AiCopilotPanel({super.key});

  @override
  State<AiCopilotPanel> createState() => _AiCopilotPanelState();
}

class _AiCopilotPanelState extends State<AiCopilotPanel> {
  AiCopilotProvider? _provider;
  final _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<AiCopilotProvider>();
      _provider?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _provider?.removeListener(_onUpdate);
    _chatController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return const Center(
        child: Text('AI Co-Pilot not available',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Left: Quality score + config ──────────────────────
          SizedBox(width: 200, child: _buildScorePanel(p)),
          const SizedBox(width: 8),
          // ─── Center: Suggestions ───────────────────────────────
          Expanded(flex: 3, child: _buildSuggestionsPanel(p)),
          const SizedBox(width: 8),
          // ─── Right: Chat ───────────────────────────────────────
          SizedBox(width: 220, child: _buildChatPanel(p)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCORE PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildScorePanel(AiCopilotProvider p) {
    final score = p.qualityScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + Analyze button
        Row(
          children: [
            const Icon(Icons.psychology, color: Color(0xFFCC44CC), size: 14),
            const SizedBox(width: 6),
            const Text('AI Co-Pilot',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: p.isAnalyzing ? null : () => p.analyzeProject(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFCC44CC).withAlpha(20),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: const Color(0xFFCC44CC).withAlpha(60),
                      width: 0.5),
                ),
                child: Text(
                  p.isAnalyzing ? 'Analyzing...' : 'Analyze',
                  style: const TextStyle(
                      color: Color(0xFFCC44CC), fontSize: 9),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Quality grade
        if (score != null) ...[
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _scoreColor(score.overall).withAlpha(120), width: 2),
                color: _scoreColor(score.overall).withAlpha(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(score.grade,
                      style: TextStyle(
                          color: _scoreColor(score.overall),
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text('${score.overall.toStringAsFixed(0)}',
                      style: TextStyle(
                          color: _scoreColor(score.overall),
                          fontSize: 9,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Sub-scores
          _buildSubScore('Timing', score.timing),
          _buildSubScore('Loudness', score.loudness),
          _buildSubScore('Consistency', score.consistency),
          _buildSubScore('Best Practice', score.bestPractice),
          _buildSubScore('Regulatory', score.regulatory),
          const SizedBox(height: 6),

          // Counts
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCountBadge('${score.criticalCount}', 'Critical',
                  const Color(0xFFCC4444)),
              _buildCountBadge('${score.warningCount}', 'Warning',
                  const Color(0xFFCC8844)),
              _buildCountBadge('${score.totalSuggestions}', 'Total',
                  const Color(0xFF888888)),
            ],
          ),
        ] else
          const Center(
            child: Text('Click Analyze to scan project',
                style: TextStyle(color: Color(0xFF555577), fontSize: 9)),
          ),

        const SizedBox(height: 8),

        // Style selector
        const Text('Target Style',
            style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final s in SlotAudioStyle.values)
                  _buildStyleOption(p, s),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubScore(String label, double score) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 9)),
          ),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (score / 100).clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    color: _scoreColor(score),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 22,
            child: Text('${score.toStringAsFixed(0)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: _scoreColor(score),
                    fontSize: 8,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(String count, String label, Color color) {
    return Column(
      children: [
        Text(count,
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 7)),
      ],
    );
  }

  Color _scoreColor(double score) {
    if (score >= 80) return const Color(0xFF44CC44);
    if (score >= 60) return const Color(0xFFCCCC44);
    if (score >= 40) return const Color(0xFFCC8844);
    return const Color(0xFFCC4444);
  }

  Widget _buildStyleOption(AiCopilotProvider p, SlotAudioStyle s) {
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
        child: Row(
          children: [
            Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 10,
              color: active
                  ? const Color(0xFFCC44CC)
                  : const Color(0xFF555577),
            ),
            const SizedBox(width: 4),
            Text(s.displayName,
                style: TextStyle(
                    color: active
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF888888),
                    fontSize: 9)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUGGESTIONS PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSuggestionsPanel(AiCopilotProvider p) {
    final active = p.activeSuggestions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.lightbulb_outline,
                color: Color(0xFF888888), size: 14),
            const SizedBox(width: 6),
            Text('Suggestions (${active.length})',
                style: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (p.suggestions.any((s) => s.dismissed))
              GestureDetector(
                onTap: () => p.clearDismissed(),
                child: const Text('Clear dismissed',
                    style: TextStyle(color: Color(0xFF555577), fontSize: 8)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: active.isEmpty
              ? Center(
                  child: Text(
                    p.qualityScore != null
                        ? 'All suggestions resolved!'
                        : 'Run analysis to get suggestions',
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 10),
                  ),
                )
              : ListView.builder(
                  itemCount: active.length,
                  itemBuilder: (_, i) => _buildSuggestionCard(p, active[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildSuggestionCard(AiCopilotProvider p, CopilotSuggestion s) {
    final severityColor = switch (s.severity) {
      SuggestionSeverity.info => const Color(0xFF4488CC),
      SuggestionSeverity.suggestion => const Color(0xFF44CC88),
      SuggestionSeverity.warning => const Color(0xFFCC8844),
      SuggestionSeverity.critical => const Color(0xFFCC4444),
    };

    final catColor = Color(s.category.colorValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: severityColor.withAlpha(40), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: severity + category + actions
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: severityColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(s.severity.displayName,
                    style: TextStyle(
                        color: severityColor,
                        fontSize: 7,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: catColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(s.category.displayName,
                    style: TextStyle(color: catColor, fontSize: 7)),
              ),
              if (s.affectedStage != null) ...[
                const SizedBox(width: 4),
                Text(s.affectedStage!,
                    style: const TextStyle(
                        color: Color(0xFF555577),
                        fontSize: 7,
                        fontFamily: 'monospace')),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () => p.applySuggestion(s.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF44CC44).withAlpha(20),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text('Apply',
                      style: TextStyle(
                          color: Color(0xFF44CC44), fontSize: 7)),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => p.dismissSuggestion(s.id),
                child: const Icon(Icons.close,
                    size: 10, color: Color(0xFF555577)),
              ),
            ],
          ),
          const SizedBox(height: 3),

          // Title
          Text(s.title,
              style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),

          // Description
          Text(s.description,
              style: const TextStyle(
                  color: Color(0xFF999999), fontSize: 9, height: 1.3)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAT PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildChatPanel(AiCopilotProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.chat_bubble_outline,
                color: Color(0xFF888888), size: 14),
            const SizedBox(width: 6),
            const Text('Ask Co-Pilot',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (p.chatHistory.isNotEmpty)
              GestureDetector(
                onTap: () => p.clearChat(),
                child: const Icon(Icons.delete_outline,
                    size: 12, color: Color(0xFF555577)),
              ),
          ],
        ),
        const SizedBox(height: 4),

        // Chat messages
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: const Color(0xFF2A2A4C), width: 0.5),
            ),
            child: p.chatHistory.isEmpty
                ? const Center(
                    child: Text(
                      'Ask about:\n• Win sound design\n• Near-miss compliance\n'
                      '• Export formats\n• Loop/ambient creation',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF555577), fontSize: 9),
                    ),
                  )
                : ListView.builder(
                    itemCount: p.chatHistory.length,
                    itemBuilder: (_, i) {
                      final msg = p.chatHistory[i];
                      final isUser = msg.startsWith('You:');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          msg,
                          style: TextStyle(
                            color: isUser
                                ? const Color(0xFF44AACC)
                                : const Color(0xFFCC44CC),
                            fontSize: 9,
                            height: 1.3,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 4),

        // Input
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 24,
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(
                      color: Color(0xFFCCCCCC), fontSize: 10),
                  decoration: InputDecoration(
                    hintText: 'Ask a question...',
                    hintStyle: const TextStyle(
                        color: Color(0xFF555577), fontSize: 10),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    filled: true,
                    fillColor: const Color(0xFF0D0D1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: const BorderSide(
                          color: Color(0xFF2A2A4C), width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: const BorderSide(
                          color: Color(0xFF2A2A4C), width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: const BorderSide(
                          color: Color(0xFFCC44CC), width: 0.5),
                    ),
                  ),
                  onSubmitted: (text) {
                    if (text.trim().isNotEmpty) {
                      p.askCopilot(text.trim());
                      _chatController.clear();
                    }
                  },
                ),
              ),
            ),
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
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFFCC44CC).withAlpha(30),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(Icons.send,
                    size: 12, color: Color(0xFFCC44CC)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
