// FAZA 5.1.4 — SlotLab MUSIC > GEN sub-tab.
//
// First-party UI for the local generative audio layer. Wires the pure-Dart
// `EmotionalArcEditor` (5.1.5) and the `GenerativeAudioService` (5.1.3) FFI
// bindings into a single panel the slot designer can drive without leaving
// the lower zone:
//
//   1. Pick stage hint (drives `SlotStageHint` on the request).
//   2. Type a prompt + duration.
//   3. Sculpt the emotional arc.
//   4. Optionally pin a seed for deterministic regeneration.
//   5. Hit GENERATE — service returns PCM + provenance metadata.
//
// The output card shows the full provenance manifest (5.1.8 compliance
// surface) and a downsampled RMS sparkline so the designer can sanity-check
// the shape against the arc before listening.
//
// Test seam: callers can inject `generator` to stub the FFI in widget tests.
// The default delegates to `GenerativeAudioService.instance.generate`, which
// only works inside the running app (needs `librf_bridge.dylib`).
//
// Audio playback is intentionally out of scope here — the GEN panel produces
// a `Float32List`; routing into the slot's audio graph happens in 5.1.6/5.1.7
// (style transfer + variation generation) where the slot context is known.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/generative_audio_service.dart';
import '../../../theme/fluxforge_theme.dart';
import '../../generative/emotional_arc_editor.dart';

/// Function signature for the underlying generation call. Exposed so widget
/// tests can swap the live FFI for a deterministic stub.
typedef GenerateFn = Future<GenerationResult> Function(GenerationRequest);

/// Function signature for the variation batch call (FAZA 5.1.7). Same test
/// seam pattern as `GenerateFn` — tests inject deterministic stubs without
/// touching `GenerativeAudioService.instance`.
typedef GenerateVariationsFn = Future<List<GenerationResult>> Function(
  GenerationRequest request,
  int count,
);

/// How many alternates the "× N" button produces. 5 matches FAZA 5.1.7 spec
/// ("5 alternate BIG_WIN stings") and stays under the service's clamp of 10.
const int _kDefaultVariationCount = 5;

class SlotLabMusicGenPanel extends StatefulWidget {
  /// Override the generator used by the panel (defaults to the live FFI
  /// singleton). Tests pass a stub here.
  final GenerateFn? generator;

  /// Override the variation batch generator (defaults to the live FFI
  /// singleton's `generateVariations`). Tests pass a stub here.
  final GenerateVariationsFn? variationsGenerator;

  /// Initial prompt — useful for restoring panel state across rebuilds and
  /// for screenshot/integration tests.
  final String initialPrompt;

  /// Initial duration in seconds (1.0 .. 30.0).
  final double initialDurationSeconds;

  /// Initial stage hint (null = unspecified → backend picks a neutral preset).
  final SlotStageHint? initialStageHint;

  const SlotLabMusicGenPanel({
    super.key,
    this.generator,
    this.variationsGenerator,
    this.initialPrompt =
        'warm electromechanical reel idle, low rumble, gentle gold shimmer',
    this.initialDurationSeconds = 6.0,
    this.initialStageHint = SlotStageHint.idle,
  });

  @override
  State<SlotLabMusicGenPanel> createState() => _SlotLabMusicGenPanelState();
}

class _SlotLabMusicGenPanelState extends State<SlotLabMusicGenPanel> {
  late final TextEditingController _promptCtrl;
  late final TextEditingController _seedCtrl;
  late double _duration;
  SlotStageHint? _stageHint;
  EmotionalArc _arc = EmotionalArcPreset.flat.build();
  bool _busy = false;
  GenerationResult? _last;
  String? _error;
  Duration? _wallClock;

  /// FAZA 5.1.7 — populated by "× N variations" action. When non-null the
  /// output card shows a strip of mini-cards on top; `_last` mirrors the
  /// currently selected variation so the existing waveform/provenance
  /// sub-widgets keep working without conditionals.
  List<GenerationResult>? _variations;
  int _selectedVariationIndex = 0;

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController(text: widget.initialPrompt);
    _seedCtrl = TextEditingController();
    _duration = widget.initialDurationSeconds.clamp(1.0, 30.0);
    _stageHint = widget.initialStageHint;
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _seedCtrl.dispose();
    super.dispose();
  }

  GenerateFn get _generate =>
      widget.generator ?? GenerativeAudioService.instance.generate;

  GenerateVariationsFn get _generateVariations =>
      widget.variationsGenerator ??
      GenerativeAudioService.instance.generateVariations;

  int? _parsedSeed() {
    final raw = _seedCtrl.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Future<void> _runGenerate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Prompt is required');
      return;
    }
    if (_busy) return;

    final req = GenerationRequest(
      prompt: prompt,
      durationSeconds: _duration,
      seed: _parsedSeed(),
      style: GenerationStyle(
        stageHint: _stageHint,
        emotionalArc: _arc,
      ),
    );

    setState(() {
      _busy = true;
      _error = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final result = await _generate(req);
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _last = result;
        // Single GENERATE drops the variation strip — the output area
        // shouldn't keep five stale alternates when the user asked for one.
        _variations = null;
        _selectedVariationIndex = 0;
        _wallClock = stopwatch.elapsed;
        _busy = false;
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
        _wallClock = stopwatch.elapsed;
      });
    }
  }

  /// FAZA 5.1.7 — fan out a single request across N seed-stepped variations.
  Future<void> _runVariations() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Prompt is required');
      return;
    }
    if (_busy) return;

    final req = GenerationRequest(
      prompt: prompt,
      durationSeconds: _duration,
      seed: _parsedSeed(),
      style: GenerationStyle(
        stageHint: _stageHint,
        emotionalArc: _arc,
      ),
    );

    setState(() {
      _busy = true;
      _error = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final variations =
          await _generateVariations(req, _kDefaultVariationCount);
      stopwatch.stop();
      if (!mounted) return;
      if (variations.isEmpty) {
        // Service contract clamps min to 1 so this is defensive only.
        setState(() {
          _error = 'Backend returned zero variations';
          _busy = false;
          _wallClock = stopwatch.elapsed;
        });
        return;
      }
      setState(() {
        _variations = variations;
        _selectedVariationIndex = 0;
        _last = variations.first;
        _wallClock = stopwatch.elapsed;
        _busy = false;
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
        _wallClock = stopwatch.elapsed;
      });
    }
  }

  void _selectVariation(int index) {
    final list = _variations;
    if (list == null || index < 0 || index >= list.length) return;
    if (index == _selectedVariationIndex) return;
    setState(() {
      _selectedVariationIndex = index;
      _last = list[index];
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final controls = _buildControls();
        final output = _buildOutput();

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(child: controls),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(child: output),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [controls, const SizedBox(height: 12), output],
          ),
        );
      },
    );
  }

  // ───────────────────── Controls (left column) ─────────────────────

  Widget _buildControls() {
    return _glassCard(
      title: 'GENERATE',
      icon: Icons.auto_awesome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Prompt'),
          TextField(
            controller: _promptCtrl,
            maxLines: 2,
            minLines: 2,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: _inputDecoration(
              hint: 'warm electromechanical idle, low rumble…',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel('Duration  •  ${_duration.toStringAsFixed(1)} s'),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: FluxForgeTheme.brandGold,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: FluxForgeTheme.brandGoldBright,
                        overlayColor: FluxForgeTheme.brandGold.withValues(alpha: 0.2),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _duration,
                        min: 1.0,
                        max: 30.0,
                        divisions: 58, // 0.5s steps
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _duration = v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel('Seed (optional)'),
                    TextField(
                      key: const Key('gen_panel_seed_field'),
                      controller: _seedCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: _inputDecoration(hint: 'auto'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionLabel('Stage hint'),
          _stageHintDropdown(),
          const SizedBox(height: 12),
          _sectionLabel('Emotional arc'),
          EmotionalArcEditor(
            initial: _arc,
            height: 140,
            onChanged: (a) => _arc = a,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  key: const Key('gen_panel_generate_button'),
                  onPressed: _busy ? null : _runGenerate,
                  style: FilledButton.styleFrom(
                    backgroundColor: FluxForgeTheme.brandGold,
                    foregroundColor: const Color(0xFF1A1208),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Color(0xFF1A1208)),
                          ),
                        )
                      : const Icon(Icons.bolt, size: 18),
                  label: Text(
                    _busy ? 'Generating…' : 'GENERATE',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  key: const Key('gen_panel_variations_button'),
                  onPressed: _busy ? null : _runVariations,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FluxForgeTheme.brandGoldBright,
                    side: BorderSide(
                      color: FluxForgeTheme.brandGold.withValues(alpha: 0.65),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_motion, size: 16),
                  label: Text(
                    '× $_kDefaultVariationCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _errorBanner(_error!),
          ],
        ],
      ),
    );
  }

  Widget _stageHintDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButton<SlotStageHint?>(
        value: _stageHint,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: const Color(0xFF13131A),
        iconEnabledColor: FluxForgeTheme.brandGold,
        style: const TextStyle(fontSize: 13, color: Colors.white),
        items: [
          const DropdownMenuItem<SlotStageHint?>(
            value: null,
            child: Text('— unspecified —'),
          ),
          ...SlotStageHint.values.map(
            (s) => DropdownMenuItem(value: s, child: Text(s.wireName)),
          ),
        ],
        onChanged: _busy ? null : (v) => setState(() => _stageHint = v),
      ),
    );
  }

  // ───────────────────── Output (right column) ─────────────────────

  Widget _buildOutput() {
    final r = _last;
    final vars = _variations;
    return _glassCard(
      title: 'OUTPUT',
      icon: Icons.graphic_eq,
      child: r == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _busy
                      ? 'Calling rf-generative…'
                      : 'No clip yet — press GENERATE.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (vars != null) ...[
                  _variationStrip(vars),
                  const SizedBox(height: 12),
                ],
                _waveformCard(r),
                const SizedBox(height: 12),
                _provenanceCard(r),
              ],
            ),
    );
  }

  /// FAZA 5.1.7 — horizontal strip of N mini-cards, one per variation.
  /// Each card: index badge + seed + sparkline. Tap selects.
  Widget _variationStrip(List<GenerationResult> variations) {
    return Container(
      key: const Key('gen_panel_variation_strip'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_motion,
                    size: 12, color: FluxForgeTheme.brandGold),
                const SizedBox(width: 4),
                Text(
                  'VARIATIONS  ·  ${variations.length}',
                  style: TextStyle(
                    color: FluxForgeTheme.brandGold,
                    fontSize: 9,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: variations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final v = variations[i];
                final selected = i == _selectedVariationIndex;
                return _VariationCard(
                  index: i,
                  result: v,
                  selected: selected,
                  onTap: () => _selectVariation(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _waveformCard(GenerationResult r) {
    final peak = _peakAbs(r);
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SparklinePainter(r),
              ),
            ),
            Positioned(
              left: 8,
              top: 6,
              child: Text(
                'PEAK ${peak.toStringAsFixed(3)}',
                style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: FluxForgeTheme.accentCyan
                        .withValues(alpha: 0.85)),
              ),
            ),
            Positioned(
              right: 8,
              top: 6,
              child: Text(
                '${r.frameCount} frames @ ${r.sampleRateHz} Hz × ${r.channels}',
                style: FluxForgeTheme.dockMono(
                    size: 9, color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _provenanceCard(GenerationResult r) {
    final m = r.metadata;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fingerprint,
                  size: 14, color: FluxForgeTheme.brandGold),
              const SizedBox(width: 6),
              Text(
                'PROVENANCE',
                style: TextStyle(
                  color: FluxForgeTheme.brandGold,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kv('backend', m.backendId),
          _kv('model', m.modelId),
          _kv(
            'seed',
            m.seed?.toString() ?? '(auto)',
            valueKey: const Key('gen_panel_provenance_seed_value'),
          ),
          _kv('duration', '${m.durationSeconds.toStringAsFixed(2)} s'),
          _kv('latency', '${r.latencyMs} ms'),
          if (_wallClock != null)
            _kv('wall-clock', '${_wallClock!.inMilliseconds} ms'),
          _kv('generated', m.generatedAtUtc.isEmpty ? '—' : m.generatedAtUtc),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Key? valueKey}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              k,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              key: valueKey,
              style: FluxForgeTheme.dockMono(
                  size: 11, color: Colors.white.withValues(alpha: 0.9)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── Theme helpers ─────────────────────

  Widget _glassCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A10).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: FluxForgeTheme.brandGold),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: FluxForgeTheme.brandGold,
                  fontSize: 11,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 2),
        child: Text(
          s,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 12,
        ),
        filled: true,
        fillColor: const Color(0xFF13131A),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: FluxForgeTheme.brandGold.withValues(alpha: 0.8),
          ),
        ),
      );

  Widget _errorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1414),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFF6060).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFFF8080)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                color: Color(0xFFFFA0A0),
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _peakAbs(GenerationResult r) {
    if (r.pcm.isEmpty) return 0.0;
    var peak = 0.0;
    for (final s in r.pcm) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    return peak;
  }
}

// ──────────────────────────────────────────────────────────────────────
// Sparkline painter — downsamples PCM into N min/max bars so the user can
// see clip shape even on a wide aspect ratio. Interleaved channels collapse
// into a single envelope.
// ──────────────────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final GenerationResult result;
  const _SparklinePainter(this.result);

  @override
  void paint(Canvas canvas, Size size) {
    final pcm = result.pcm;
    if (pcm.isEmpty) return;

    // Background grid (subtle)
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), grid);

    final bars = math.max(1, (size.width / 2).floor());
    final samplesPerBar = math.max(1, pcm.length ~/ bars);

    final paint = Paint()
      ..color = FluxForgeTheme.brandGold
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < bars; i++) {
      final start = i * samplesPerBar;
      final end = math.min(pcm.length, start + samplesPerBar);
      if (start >= end) break;
      var lo = pcm[start];
      var hi = lo;
      for (var k = start + 1; k < end; k++) {
        final v = pcm[k];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      final x = (i / (bars - 1).clamp(1, bars)) * size.width;
      final yHi = mid - hi * mid * 0.95;
      final yLo = mid - lo * mid * 0.95;
      canvas.drawLine(Offset(x, yLo), Offset(x, yHi), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      !identical(old.result, result);
}

// ──────────────────────────────────────────────────────────────────────
// Variation mini-card — one tile inside the 5.1.7 variation strip.
// Compact (~96px wide) so 5–10 fit comfortably in the output column,
// even on the narrow stacked layout. Tap promotes that variation to
// the main waveform/provenance view.
// ──────────────────────────────────────────────────────────────────────

class _VariationCard extends StatelessWidget {
  final int index;
  final GenerationResult result;
  final bool selected;
  final VoidCallback onTap;

  const _VariationCard({
    required this.index,
    required this.result,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected
        ? FluxForgeTheme.brandGoldBright
        : Colors.white.withValues(alpha: 0.4);
    final bg = selected
        ? FluxForgeTheme.brandGold.withValues(alpha: 0.12)
        : const Color(0xFF13131A);
    final seed = result.metadata.seed?.toString() ?? '—';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('gen_panel_variation_card_$index'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
              color: selected
                  ? FluxForgeTheme.brandGoldBright
                  : Colors.white12,
              width: selected ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '#${index + 1}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      seed,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: FluxForgeTheme.dockMono(
                        size: 8.5,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Expanded(
                child: CustomPaint(
                  painter: _SparklinePainter(result),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
