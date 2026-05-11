// HELIX dock — AI Generation panel (Sprint 15 Faza 4.C split #5).
//
// Prompt-based audio generation: backend selector (stub/local/cloud),
// full pipeline (parse → classify → generate → post-process), pipeline
// log, result display.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _AiGenerationPanel(State) — root widget + generation orchestrator

part of '../../helix_screen.dart';// ── 3.5 AI Generation Panel ─────────────────────────────────────────────────

class _AiGenerationPanel extends StatefulWidget {
  const _AiGenerationPanel();
  @override
  State<_AiGenerationPanel> createState() => _AiGenerationPanelState();
}

class _AiGenerationPanelState extends State<_AiGenerationPanel> {
  final _promptController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _voiceIdController = TextEditingController();
  bool _isGenerating = false;
  String? _lastResultText;
  String? _lastOutputPath;
  String _selectedBackend = 'stub';  // 'stub' | 'elevenlabs_sfx' | 'elevenlabs_tts'
  bool _showSettings = false;
  bool _obscureKey = true;
  final List<String> _pipelineLog = [];

  late final AiGenerationService _aiService;

  @override
  void initState() {
    super.initState();
    _aiService = GetIt.instance<AiGenerationService>();
    _aiService.addListener(_onAiChanged);
    _aiService.loadAvailableBackends();
    // Load persisted ElevenLabs config into controllers after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _apiKeyController.text = _aiService.elApiKey;
        _voiceIdController.text = _aiService.elVoiceId;
      }
    });
  }

  @override
  void dispose() {
    _aiService.removeListener(_onAiChanged);
    _promptController.dispose();
    _apiKeyController.dispose();
    _voiceIdController.dispose();
    super.dispose();
  }

  void _onAiChanged() {
    if (mounted) {
      // Sync controllers if config was loaded from prefs
      if (_apiKeyController.text != _aiService.elApiKey) {
        _apiKeyController.text = _aiService.elApiKey;
      }
      if (_voiceIdController.text != _aiService.elVoiceId) {
        _voiceIdController.text = _aiService.elVoiceId;
      }
      setState(() {});
    }
  }

  Future<void> _saveElConfig() async {
    await _aiService.saveElConfig(
      apiKey: _apiKeyController.text.trim(),
      voiceId: _voiceIdController.text.trim(),
    );
    if (mounted) setState(() => _showSettings = false);
  }

  void _runGeneration() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _isGenerating = true;
      _pipelineLog.clear();
      _lastResultText = null;
      _lastOutputPath = null;
    });

    try {
      // ── ElevenLabs SFX path ────────────────────────────────────────────
      if (_selectedBackend == 'elevenlabs_sfx') {
        setState(() => _pipelineLog.add('ElevenLabs: Parsing duration from prompt...'));

        // Parse optional duration from prompt ("2 seconds", "3s", etc.)
        double? durationSec;
        final durMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:second|sec|s)\b', caseSensitive: false)
            .firstMatch(prompt);
        if (durMatch != null) {
          durationSec = double.tryParse(durMatch.group(1) ?? '');
        }

        setState(() => _pipelineLog.add(
          'ElevenLabs SFX: prompt=${prompt.length}ch, duration=${durationSec?.toStringAsFixed(1) ?? "auto"}s'));
        setState(() => _pipelineLog.add('Calling ElevenLabs /v1/sound-generation...'));

        final result = await _aiService.generateElSfx(
          prompt: prompt,
          durationSeconds: durationSec,
        );

        if (result != null) {
          setState(() {
            _pipelineLog.add('✓ Generated: ${result.filename}');
            _pipelineLog.add('Saved: ${result.outputPath}');
            _pipelineLog.add('DONE');
            _lastResultText = 'ElevenLabs SFX generated — ${result.filename}';
            _lastOutputPath = result.outputPath;
            _isGenerating = false;
          });
        }
        return;
      }

      // ── ElevenLabs TTS path ────────────────────────────────────────────
      if (_selectedBackend == 'elevenlabs_tts') {
        if (_aiService.elVoiceId.isEmpty) {
          setState(() {
            _pipelineLog.add('ERROR: No voice selected — open ⚙️ settings, enter Voice ID');
            _isGenerating = false;
          });
          return;
        }
        setState(() => _pipelineLog.add(
          'ElevenLabs TTS: voice=${_aiService.elVoiceId.substring(0, 8)}...'));
        setState(() => _pipelineLog.add('Calling ElevenLabs /v1/text-to-speech...'));

        final result = await _aiService.generateElTts(text: prompt);

        if (result != null) {
          setState(() {
            _pipelineLog.add('✓ Generated: ${result.filename}');
            _pipelineLog.add('Saved: ${result.outputPath}');
            _pipelineLog.add('DONE');
            _lastResultText = 'ElevenLabs TTS generated — ${result.filename}';
            _lastOutputPath = result.outputPath;
            _isGenerating = false;
          });
        }
        return;
      }

      // ── Stub path (offline, no API key needed) ─────────────────────────
      setState(() => _pipelineLog.add('Parsing prompt...'));
      final descriptor = await _aiService.parsePrompt(prompt);
      if (descriptor == null) {
        setState(() { _pipelineLog.add('ERROR: Failed to parse prompt'); _isGenerating = false; });
        return;
      }
      setState(() => _pipelineLog.add('Parsed: ${descriptor.category} / ${descriptor.tier}'));

      setState(() => _pipelineLog.add('Classifying (FFNC)...'));
      final classification = await _aiService.classify(descriptor);
      if (classification != null) {
        setState(() => _pipelineLog.add(
          'Class: ${classification.ffncCode} ${classification.displayName} (${(classification.confidence * 100).toStringAsFixed(0)}%)'));
      }

      setState(() => _pipelineLog.add('Generating audio (stub)...'));
      final result = await _aiService.generateWithStub(prompt: prompt);
      if (result != null) {
        setState(() {
          _pipelineLog.add('Generated: ${result.actualDurationMs}ms → ${result.suggestedFilename}');
          _lastResultText = 'Stub: ${result.actualDurationMs}ms / ${result.generationTimeMs}ms gen';
        });
      }

      setState(() => _pipelineLog.add('Post-processing config...'));
      final ppConfig = await _aiService.getPostProcessingConfig(descriptor);
      if (ppConfig != null) {
        setState(() => _pipelineLog.add(
          'PP: ${ppConfig.loudnessLufs} LUFS, trim=${ppConfig.trimSilence}'));
      }

      setState(() { _pipelineLog.add('DONE'); _isGenerating = false; });
    } catch (e) {
      setState(() { _pipelineLog.add('ERROR: $e'); _isGenerating = false; });
    }
  }

  // ── Backend tab chip ───────────────────────────────────────────────────
  Widget _backendChip(String id, String label, {bool isLive = false}) {
    final selected = _selectedBackend == id;
    final accent = isLive ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentPurple;
    return GestureDetector(
      onTap: () => setState(() => _selectedBackend = id),
      child: AnimatedContainer(
        duration: FluxMotion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle,
            width: selected ? 1.2 : 1.0,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (isLive) ...[
            Container(width: 5, height: 5,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 4),
          ],
          Text(label,
            style: FluxForgeTheme.dockMono(size: 8, weight: FontWeight.w600,
              color: selected ? accent : FluxForgeTheme.textTertiary)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isElBackend = _selectedBackend.startsWith('elevenlabs');
    final elConfigured = _aiService.elIsConfigured;

    return Row(
      children: [
        // ── Left: Prompt + controls ─────────────────────────────────────
        Expanded(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(children: [
                  _DockLabel('AI AUDIO GENERATION', color: FluxForgeTheme.accentPurple),
                  const Spacer(),
                  // Settings button — opens API key dialog
                  GestureDetector(
                    onTap: () => setState(() => _showSettings = !_showSettings),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _showSettings
                          ? FluxForgeTheme.accentPurple.withValues(alpha: 0.15)
                          : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.settings_rounded, size: 13,
                        color: _showSettings
                          ? FluxForgeTheme.accentPurple
                          : FluxForgeTheme.textTertiary),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                // ── Settings panel (inline, slides in) ─────────────────
                AnimatedCrossFade(
                  duration: FluxMotion.brisk,
                  crossFadeState: _showSettings
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildSettingsPanel(),
                ),

                if (!_showSettings) ...[
                  // Backend selector
                  Row(children: [
                    Text('Backend: ', style: FluxForgeTheme.dockMono(
                      size: 9, color: FluxForgeTheme.textTertiary)),
                    _backendChip('stub', 'STUB'),
                    _backendChip('elevenlabs_sfx', '11 SFX', isLive: true),
                    _backendChip('elevenlabs_tts', '11 TTS', isLive: true),
                    if (isElBackend && !elConfigured)
                      Text('  ⚠ no key',
                        style: FluxForgeTheme.dockMono(size: 8,
                          color: FluxForgeTheme.accentYellow)),
                  ]),
                  const SizedBox(height: 8),

                  // Prompt input
                  Text(
                    _selectedBackend == 'elevenlabs_tts'
                      ? 'Voiceover text (e.g. "Big Win!", "Jackpot activated!"):'
                      : 'Describe the sound (e.g. "epic win fanfare, 2 seconds"):',
                    style: FluxForgeTheme.dockMono(size: 9,
                      color: FluxForgeTheme.textSecondary)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 72,
                    child: TextField(
                      controller: _promptController,
                      maxLines: 4,
                      style: FluxForgeTheme.dockMono(size: 11,
                        color: FluxForgeTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: _selectedBackend == 'elevenlabs_tts'
                          ? '"BIG WIN! You\'ve hit the jackpot!"'
                          : '"slot machine jackpot sound, coins, 3 seconds, triumphant"',
                        hintStyle: FluxForgeTheme.dockMono(size: 9,
                          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.45)),
                        filled: true,
                        fillColor: FluxForgeTheme.bgSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: FluxForgeTheme.accentPurple)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Quick prompts for slot audio
                  if (_selectedBackend == 'elevenlabs_sfx') ...[
                    Wrap(spacing: 4, runSpacing: 4,
                      children: [
                        'slot win coins 2s', 'jackpot fanfare brass 3s',
                        'reel spin mechanical', 'bonus round activated',
                        'near miss tension 1s', 'ambient casino loop',
                      ].map((p) => GestureDetector(
                        onTap: () => _promptController.text = p,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgSurface,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: FluxForgeTheme.borderSubtle)),
                          child: Text(p, style: FluxForgeTheme.dockMono(
                            size: 7.5,
                            color: FluxForgeTheme.textTertiary)),
                        ),
                      )).toList()),
                    const SizedBox(height: 8),
                  ],
                  if (_selectedBackend == 'elevenlabs_tts') ...[
                    Wrap(spacing: 4, runSpacing: 4,
                      children: [
                        'BIG WIN!', 'Jackpot!', 'Free Spins activated!',
                        'Bonus round begins!', 'Super Win!', 'Mega Win!',
                      ].map((p) => GestureDetector(
                        onTap: () => _promptController.text = p,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgSurface,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: FluxForgeTheme.borderSubtle)),
                          child: Text(p, style: FluxForgeTheme.dockMono(
                            size: 7.5,
                            color: FluxForgeTheme.textTertiary)),
                        ),
                      )).toList()),
                    const SizedBox(height: 8),
                  ],

                  // Generate button
                  Row(children: [
                    const Spacer(),
                    GestureDetector(
                      onTap: _isGenerating ? null : _runGeneration,
                      child: AnimatedContainer(
                        duration: FluxMotion.quick,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: _isGenerating
                            ? FluxForgeTheme.textTertiary.withValues(alpha: 0.08)
                            : (isElBackend && elConfigured)
                              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.15)
                              : FluxForgeTheme.accentPurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _isGenerating
                              ? FluxForgeTheme.textTertiary
                              : (isElBackend && elConfigured)
                                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
                                : FluxForgeTheme.accentPurple.withValues(alpha: 0.5)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_isGenerating)
                            SizedBox(width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2,
                                color: isElBackend
                                  ? FluxForgeTheme.accentGreen
                                  : FluxForgeTheme.accentPurple))
                          else
                            Icon(isElBackend ? Icons.graphic_eq_rounded : Icons.auto_awesome_rounded,
                              size: 13,
                              color: (isElBackend && elConfigured)
                                ? FluxForgeTheme.accentGreen
                                : FluxForgeTheme.accentPurple),
                          const SizedBox(width: 6),
                          Text(_isGenerating ? 'GENERATING...' : 'GENERATE',
                            style: FluxForgeTheme.dockMono(size: 10,
                              weight: FontWeight.w600,
                              color: (isElBackend && elConfigured)
                                ? FluxForgeTheme.accentGreen
                                : FluxForgeTheme.accentPurple)),
                        ]),
                      ),
                    ),
                  ]),

                  // Result row
                  if (_lastResultText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.check_circle_rounded, size: 13,
                            color: FluxForgeTheme.accentGreen),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_lastResultText!,
                            style: FluxForgeTheme.dockMono(size: 9,
                              color: FluxForgeTheme.accentGreen))),
                        ]),
                        if (_lastOutputPath != null) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.folder_open_rounded, size: 11,
                              color: FluxForgeTheme.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(child: Text(_lastOutputPath!,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: FluxForgeTheme.dockMono(size: 7.5,
                                color: FluxForgeTheme.textTertiary))),
                          ]),
                        ],
                      ]),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // ── Right: Pipeline log + Voice list ────────────────────────────
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pipeline log
                _DockLabel('PIPELINE LOG', color: FluxForgeTheme.accentPurple),
                const SizedBox(height: 6),
                Expanded(
                  child: _pipelineLog.isEmpty
                    ? Center(child: Text('Run generation to see log',
                        style: FluxForgeTheme.dockMono(size: 9,
                          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4))))
                    : ListView(
                        children: _pipelineLog.asMap().entries.map((e) {
                          final isError = e.value.startsWith('ERROR');
                          final isDone = e.value == 'DONE';
                          final isOk = e.value.startsWith('✓');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${e.key + 1}. ',
                                style: FluxForgeTheme.dockMono(size: 7.5,
                                  color: FluxForgeTheme.textTertiary)),
                              Expanded(child: Text(e.value,
                                style: FluxForgeTheme.dockMono(size: 7.5,
                                  color: isError ? FluxForgeTheme.accentPink
                                    : isDone || isOk ? FluxForgeTheme.accentGreen
                                    : FluxForgeTheme.textSecondary))),
                            ]),
                          );
                        }).toList(),
                      ),
                ),

                // ElevenLabs voice selector (TTS mode only)
                if (_selectedBackend == 'elevenlabs_tts') ...[
                  const Divider(color: FluxForgeTheme.borderSubtle, height: 16),
                  Row(children: [
                    _DockLabel('VOICES', color: FluxForgeTheme.accentGreen),
                    const Spacer(),
                    GestureDetector(
                      onTap: _aiService.elIsConfigured ? _aiService.fetchElVoices : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4)),
                        child: Text('FETCH',
                          style: FluxForgeTheme.dockMono(size: 7.5,
                            color: _aiService.elIsConfigured
                              ? FluxForgeTheme.accentGreen
                              : FluxForgeTheme.textTertiary)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  if (_aiService.elVoices.isEmpty)
                    Text('No voices loaded. Enter API key in ⚙️ and tap FETCH.',
                      style: FluxForgeTheme.dockMono(size: 8,
                        color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5)))
                  else
                    SizedBox(
                      height: 100,
                      child: ListView(
                        children: _aiService.elVoices.map((v) {
                          final selected = _aiService.elVoiceId == v.voiceId;
                          return GestureDetector(
                            onTap: () => _aiService.selectElVoice(v.voiceId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: selected
                                  ? FluxForgeTheme.accentGreen.withValues(alpha: 0.12)
                                  : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: selected
                                    ? FluxForgeTheme.accentGreen.withValues(alpha: 0.4)
                                    : Colors.transparent)),
                              child: Row(children: [
                                Icon(selected ? Icons.mic_rounded : Icons.mic_none_rounded,
                                  size: 11,
                                  color: selected
                                    ? FluxForgeTheme.accentGreen
                                    : FluxForgeTheme.textTertiary),
                                const SizedBox(width: 5),
                                Expanded(child: Text(v.name,
                                  style: FluxForgeTheme.dockMono(size: 9,
                                    color: selected
                                      ? FluxForgeTheme.accentGreen
                                      : FluxForgeTheme.textSecondary))),
                                if (v.category != null)
                                  Text(v.category!,
                                    style: FluxForgeTheme.dockMono(size: 7,
                                      color: FluxForgeTheme.textTertiary)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.key_rounded, size: 12, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 6),
          Text('ELEVENLABS CREDENTIALS',
            style: FluxForgeTheme.dockMono(size: 10,
              weight: FontWeight.w700, color: FluxForgeTheme.accentGreen)),
        ]),
        const SizedBox(height: 2),
        Text('API key stored locally in SharedPreferences — never in code or cloud.',
          style: FluxForgeTheme.dockMono(size: 7.5,
            color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 10),

        // API key field
        Text('API KEY', style: FluxForgeTheme.dockMono(size: 8,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            style: FluxForgeTheme.dockMono(size: 10,
              color: FluxForgeTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'sk_...',
              hintStyle: FluxForgeTheme.dockMono(size: 9,
                color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4)),
              filled: true,
              fillColor: FluxForgeTheme.bgDeepest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: const BorderSide(color: FluxForgeTheme.accentGreen)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          )),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _obscureKey = !_obscureKey),
            child: Icon(_obscureKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 16, color: FluxForgeTheme.textTertiary)),
        ]),
        const SizedBox(height: 8),

        // Voice ID field (for TTS)
        Text('VOICE ID  (for TTS — leave blank to select from list)',
          style: FluxForgeTheme.dockMono(size: 8,
            color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 4),
        TextField(
          controller: _voiceIdController,
          style: FluxForgeTheme.dockMono(size: 10,
            color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. 21m00Tcm4TlvDq8ikWAM',
            hintStyle: FluxForgeTheme.dockMono(size: 9,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4)),
            filled: true,
            fillColor: FluxForgeTheme.bgDeepest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: FluxForgeTheme.accentGreen)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
        const SizedBox(height: 10),

        Row(children: [
          GestureDetector(
            onTap: () => setState(() => _showSettings = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: FluxForgeTheme.borderSubtle)),
              child: Text('CANCEL',
                style: FluxForgeTheme.dockMono(size: 9,
                  color: FluxForgeTheme.textTertiary)),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _saveElConfig,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5))),
              child: Text('SAVE',
                style: FluxForgeTheme.dockMono(size: 9,
                  weight: FontWeight.w700, color: FluxForgeTheme.accentGreen)),
            ),
          ),
        ]),
      ]),
    );
  }
}
