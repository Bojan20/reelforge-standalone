// file: flutter_ui/lib/widgets/cortex/brain_chat.dart
/// Brain Chat — Ultimativni futuristički Claude-style chat.
///
/// Preuzima Claude chat strukturu (user/asisstent bubble, markdown,
/// copy/regenerate, suggested prompts, slash hint, scroll-to-bottom)
/// i podiže je preko Claude nivoa:
///   - Holografski gradijenti, glassmorphism (BackdropFilter)
///   - Neuralna particle pozadina (CustomPainter, lazy frame loop)
///   - Breathing glow oko aktivnog stream bubble-a
///   - Inline markdown lite (headers, code blocks, inline code, bold/italic, list)
///   - Per-message copy, regenerate-last, export-thread
///   - Floating scroll-to-bottom kad korisnik skroluje gore
///   - Slash-command palette (/clear /regen /export)
///   - Cmd+K fokus na input, Esc cancel, Cmd+L clear, Shift+Enter newline
///   - Char counter + token estimate, latency/cost live tracker
///
/// Bez novih dependency-ja — sve self-contained.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../providers/brain_provider.dart';
import '../../services/service_locator.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PALETA — FluxForge futuristic
// ═══════════════════════════════════════════════════════════════════════════════

class _Palette {
  static const Color bg = Color(0xFF06060A);
  static const Color bgElev1 = Color(0xFF0B0B12);
  static const Color bgElev2 = Color(0xFF12121C);
  static const Color border = Color(0x1AFFFFFF);
  static const Color borderActive = Color(0x4D7C5CFF);

  static const Color text = Color(0xFFE6E6F0);
  static const Color textMuted = Color(0xFF8A8AA0);
  static const Color textFaint = Color(0xFF52526A);

  // Holografska gama
  static const Color neonCyan = Color(0xFF22D3EE);
  static const Color neonViolet = Color(0xFF7C5CFF);
  static const Color neonMagenta = Color(0xFFE879F9);
  static const Color neonMint = Color(0xFF4EC9B0);
  static const Color neonRed = Color(0xFFF87171);
  static const Color neonAmber = Color(0xFFFBBF24);

  // Bubble bg
  static const Color userBubble = Color(0x331A6FE0);
  static const Color brainBubble = Color(0x1AFFFFFF);
  static const Color codeBlockBg = Color(0xCC0A0A12);

  /// Per-language accent dot za code-block header.
  static Color langColor(String lang) {
    switch (lang.toLowerCase().trim()) {
      case 'rust':
      case 'rs':
        return const Color(0xFFFF7A45);
      case 'dart':
      case 'flutter':
        return const Color(0xFF22D3EE);
      case 'python':
      case 'py':
        return const Color(0xFFFBBF24);
      case 'js':
      case 'javascript':
      case 'ts':
      case 'typescript':
        return const Color(0xFF5BD68F);
      case 'json':
        return const Color(0xFFE879F9);
      case 'yaml':
      case 'yml':
      case 'toml':
        return const Color(0xFFA0AEC0);
      case 'sh':
      case 'bash':
      case 'shell':
      case 'zsh':
        return const Color(0xFF4EC9B0);
      case 'sql':
        return const Color(0xFFF0B27A);
      case 'cpp':
      case 'c++':
      case 'c':
        return const Color(0xFF61DAFB);
      case 'go':
        return const Color(0xFF7DDFFF);
      case 'swift':
        return const Color(0xFFFF7A45);
      default:
        return neonViolet;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// JAVNI ENTRY WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class BrainChat extends StatefulWidget {
  const BrainChat({super.key});

  @override
  State<BrainChat> createState() => _BrainChatState();
}

class _BrainChatState extends State<BrainChat> with TickerProviderStateMixin {
  late final BrainProvider _brain;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _shortcutFocus = FocusNode();

  bool _atBottom = true;
  bool _showSlashPalette = false;
  String _lastQueryForRegen = '';

  // Session telemetry (futuristic dashboard layer above Claude.ai parity).
  final List<int> _latencyHistory = <int>[];
  double _sessionCostUsd = 0.0;
  int _accountedHistoryLen = 0;
  double _tps = 0.0;
  DateTime? _streamStartedAt;
  int _streamCharsAtStart = 0;
  Timer? _tpsTimer;

  late final AnimationController _ambientPulse;

  @override
  void initState() {
    super.initState();
    _brain = sl.get<BrainProvider>();
    _brain.addListener(_onBrainChanged);
    _brain.checkDaemon();

    _scrollController.addListener(_onScroll);
    _inputController.addListener(_onInputChanged);

    _ambientPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _tpsTimer?.cancel();
    _brain.removeListener(_onBrainChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _shortcutFocus.dispose();
    _ambientPulse.dispose();
    super.dispose();
  }

  /// Pull cost/latency from each newly-finalised history entry so the header
  /// telemetry (sparkline + session-cost pill) reflects the whole session,
  /// not just the most recent call. Idempotent — only counts entries we
  /// haven't accounted for yet.
  void _accrueSessionTelemetry() {
    while (_accountedHistoryLen < _brain.history.length) {
      final e = _brain.history[_accountedHistoryLen];
      if (!e.isError) {
        _sessionCostUsd += e.costUsd;
        if (e.latencyMs > 0) {
          _latencyHistory.add(e.latencyMs);
          if (_latencyHistory.length > 20) _latencyHistory.removeAt(0);
        }
      }
      _accountedHistoryLen++;
    }
  }

  /// Manage the live tokens-per-sec gauge that runs only while a stream is
  /// active. The token count is approximated as ~4 chars per token —
  /// purely cosmetic; this is a UI gauge, not a billing meter.
  void _syncTpsGauge() {
    if (_brain.isStreaming) {
      if (_tpsTimer != null) return;
      _streamStartedAt    = DateTime.now();
      _streamCharsAtStart = _brain.streamingText.length;
      _tps                = 0.0;
      _tpsTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        final started = _streamStartedAt;
        if (started == null) return;
        final dt = DateTime.now().difference(started).inMilliseconds / 1000.0;
        if (dt <= 0) return;
        final dChars = _brain.streamingText.length - _streamCharsAtStart;
        final tokens = dChars / 4.0;
        setState(() => _tps = tokens / dt);
      });
    } else if (_tpsTimer != null) {
      _tpsTimer!.cancel();
      _tpsTimer        = null;
      _tps             = 0.0;
      _streamStartedAt = null;
    }
  }

  void _onBrainChanged() {
    if (!mounted) return;
    _accrueSessionTelemetry();
    _syncTpsGauge();
    setState(() {});
    if (_brain.isStreaming || _brain.state == BrainQueryState.complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_atBottom && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final near = pos.pixels >= pos.maxScrollExtent - 40;
    if (near != _atBottom) {
      setState(() => _atBottom = near);
    }
  }

  void _onInputChanged() {
    final text = _inputController.text;
    final showSlash = text.startsWith('/') && !text.contains(' ');
    if (showSlash != _showSlashPalette) {
      setState(() => _showSlashPalette = showSlash);
    } else {
      setState(() {}); // refresh char counter
    }
  }

  void _submitQuery() {
    final raw = _inputController.text.trim();
    if (raw.isEmpty) return;

    // Slash commands
    if (raw.startsWith('/')) {
      final cmd = raw.split(' ').first.toLowerCase();
      switch (cmd) {
        case '/clear':
          _brain.clearHistory();
          _resetSessionTelemetry();
          _inputController.clear();
          return;
        case '/regen':
          _inputController.clear();
          _regenerateLast();
          return;
        case '/export':
          _inputController.clear();
          _exportThread();
          return;
        case '/cancel':
          _brain.cancelQuery();
          _inputController.clear();
          return;
      }
    }

    _lastQueryForRegen = raw;
    _brain.streamQuery(raw);
    _inputController.clear();
    _atBottom = true;
  }

  void _regenerateLast() {
    final hist = _brain.history;
    final query = hist.isNotEmpty ? hist.last.query : _lastQueryForRegen;
    if (query.isEmpty) return;
    _brain.streamQuery(query);
  }

  void _editIntoInput(String query) {
    _inputController.text = query;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
    _inputFocus.requestFocus();
  }

  void _exportThread() {
    final buf = StringBuffer();
    for (final e in _brain.history) {
      buf.writeln('### USER');
      buf.writeln(e.query);
      buf.writeln();
      buf.writeln('### BRAIN${e.isError ? " (error)" : ""}');
      buf.writeln(e.response);
      buf.writeln();
      if (e.model.isNotEmpty) {
        buf.writeln('_${e.model} · ${e.latencyMs}ms · \$${e.costUsd.toStringAsFixed(4)}_');
      }
      buf.writeln('---');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    _flashToast('Thread copied to clipboard');
  }

  void _flashToast(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
        backgroundColor: _Palette.bgElev2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final hk = HardwareKeyboard.instance;
    final cmd = hk.isMetaPressed || hk.isControlPressed;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_brain.isStreaming) {
        _brain.cancelQuery();
        return KeyEventResult.handled;
      }
    }
    if (cmd && event.logicalKey == LogicalKeyboardKey.keyK) {
      _inputFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (cmd && event.logicalKey == LogicalKeyboardKey.keyL) {
      _brain.clearHistory();
      _resetSessionTelemetry();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _shortcutFocus,
      onKeyEvent: _onKeyEvent,
      autofocus: true,
      child: ColoredBox(
        color: _Palette.bg,
        child: Stack(
          children: [
            // ─── Sloj 0: aurora oblaci (najdalji) ───────────────────────
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ambientPulse,
                  builder: (context, child) => CustomPaint(
                    painter: _AuroraPainter(t: _ambientPulse.value),
                  ),
                ),
              ),
            ),
            // ─── Sloj 1: neuralna mreža (srednji) ───────────────────────
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ambientPulse,
                  builder: (context, child) => CustomPaint(
                    painter: _NeuralFieldPainter(t: _ambientPulse.value),
                  ),
                ),
              ),
            ),
            // ─── Glavni layout ──────────────────────────────────────────
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Stack(
                    children: [
                      _buildChatArea(),
                      if (!_atBottom) _buildScrollToBottomFab(),
                    ],
                  ),
                ),
                _buildInputArea(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER — holografski glass bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final connected = _brain.isDaemonConnected;
    final hasHistory = _brain.history.isNotEmpty;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _Palette.bgElev1.withValues(alpha: 0.85),
                _Palette.bgElev2.withValues(alpha: 0.85),
              ],
            ),
            border: const Border(
              bottom: BorderSide(color: _Palette.border),
            ),
          ),
          child: Row(
            children: [
              _PulsingStatusDot(connected: connected),
              const SizedBox(width: 8),
              const _HoloBrainMark(),
              const SizedBox(width: 8),
              Text(
                connected ? 'BRAIN ONLINE' : 'BRAIN OFFLINE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                  color: connected ? _Palette.text : _Palette.textMuted,
                ),
              ),
              const Spacer(),
              // Live tokens-per-sec gauge — only while a stream is active.
              if (_brain.isStreaming && _tps > 0) ...[
                _MetaPill(
                  label: '${_tps.toStringAsFixed(1)} tok/s',
                  color: _Palette.neonAmber,
                ),
                const SizedBox(width: 6),
              ],
              // Latency sparkline (last 20 finalised turns).
              if (_latencyHistory.isNotEmpty) ...[
                _LatencySparkline(values: _latencyHistory),
                const SizedBox(width: 6),
              ],
              if (_brain.lastModel.isNotEmpty) ...[
                _MetaPill(label: _brain.lastModel, color: _Palette.neonViolet),
                const SizedBox(width: 6),
              ],
              if (_brain.lastLatencyMs > 0) ...[
                _MetaPill(
                  label: '${_brain.lastLatencyMs}ms',
                  color: _Palette.neonCyan,
                ),
                const SizedBox(width: 6),
              ],
              if (_brain.lastCostUsd > 0) ...[
                _MetaPill(
                  label: '\$${_brain.lastCostUsd.toStringAsFixed(4)}',
                  color: _Palette.neonAmber,
                ),
                const SizedBox(width: 6),
              ],
              // Session cost — running total across all turns since last clear.
              if (_sessionCostUsd > 0) ...[
                _MetaPill(
                  label: 'Σ \$${_sessionCostUsd.toStringAsFixed(4)}',
                  color: _Palette.neonMint,
                ),
                const SizedBox(width: 6),
              ],
              _IconChip(
                icon: Icons.refresh_rounded,
                tooltip: 'Regenerate last (also: /regen)',
                enabled: hasHistory && !_brain.isStreaming,
                onTap: _regenerateLast,
              ),
              const SizedBox(width: 4),
              _IconChip(
                icon: Icons.copy_all_rounded,
                tooltip: 'Export thread (also: /export)',
                enabled: hasHistory,
                onTap: _exportThread,
              ),
              const SizedBox(width: 4),
              _IconChip(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Clear history (Cmd+L · /clear)',
                enabled: hasHistory,
                onTap: () {
                  _brain.clearHistory();
                  _resetSessionTelemetry();
                },
              ),
              if (_brain.isStreaming) ...[
                const SizedBox(width: 4),
                _IconChip(
                  icon: Icons.stop_circle_outlined,
                  tooltip: 'Cancel (Esc · /cancel)',
                  enabled: true,
                  color: _Palette.neonRed,
                  onTap: _brain.cancelQuery,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHAT AREA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChatArea() {
    final history = _brain.history;
    final hasStreaming = (_brain.isStreaming || _brain.state == BrainQueryState.connecting) &&
        _brain.currentQuery.isNotEmpty;

    if (history.isEmpty && !hasStreaming) {
      return _buildEmptyState();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimelineRail(count: history.length, streaming: hasStreaming),
        Expanded(
          child: ScrollConfiguration(
            behavior: const _NoGlowScrollBehavior(),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
              itemCount: history.length + (hasStreaming ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < history.length) {
                  final isLast =
                      index == history.length - 1 && !hasStreaming;
                  return _buildMessagePair(history[index], isLast: isLast);
                }
                return _buildStreamingPair();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final prompts = [
      'Analiziraj trenutni audio graph i nadji bottleneck.',
      'Generisi blueprint slot igre po Aristocrat patternu.',
      'Objasni kako CORTEX healing loop radi.',
      'Predlozi DSP filter chain za vocal de-esser.',
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _HoloBrainMark(size: 56),
              const SizedBox(height: 16),
              const _HoloHeadline(text: 'BRAIN'),
              const SizedBox(height: 6),
              Text(
                'Ask anything. Stream live. Built for FluxForge.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: _Palette.textMuted,
                  letterSpacing: 0.4,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in prompts)
                    _PromptChip(
                      text: p,
                      onTap: () {
                        _inputController.text = p;
                        _inputFocus.requestFocus();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 32),
              const _ShortcutLegend(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagePair(BrainConversationEntry e, {required bool isLast}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UserBubble(
            text: e.query,
            onEdit: () => _editIntoInput(e.query),
            onCopy: () {
              Clipboard.setData(ClipboardData(text: e.query));
              _flashToast('Query copied');
            },
          ),
          const SizedBox(height: 10),
          _BrainBubble(
            text: e.response,
            isError: e.isError,
            isStreaming: false,
            timestamp: e.timestamp,
            model: e.model,
            latencyMs: e.latencyMs,
            costUsd: e.costUsd,
            isLast: isLast,
            onRegenerate: isLast ? _regenerateLast : null,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: e.response));
              _flashToast('Response copied');
            },
            ambient: _ambientPulse,
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingPair() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UserBubble(
            text: _brain.currentQuery,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: _brain.currentQuery));
              _flashToast('Query copied');
            },
          ),
          const SizedBox(height: 10),
          _BrainBubble(
            text: _brain.streamingText.isEmpty
                ? '...'
                : _brain.streamingText,
            isError: _brain.state == BrainQueryState.error,
            isStreaming: true,
            timestamp: DateTime.now(),
            model: '',
            latencyMs: 0,
            costUsd: 0,
            isLast: true,
            onRegenerate: null,
            onCopy: null,
            ambient: _ambientPulse,
          ),
        ],
      ),
    );
  }

  Widget _buildScrollToBottomFab() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
              );
            }
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_Palette.neonViolet, _Palette.neonCyan],
              ),
              boxShadow: [
                BoxShadow(
                  color: _Palette.neonViolet.withValues(alpha: 0.5),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_downward_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.06, 1.06),
              duration: 1400.ms,
              curve: Curves.easeInOut,
            ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INPUT AREA — glass + neon focus + slash palette
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildInputArea() {
    final isStreaming = _brain.isStreaming;
    final canSend = _inputController.text.trim().isNotEmpty;
    final charCount = _inputController.text.length;

    return Column(
      children: [
        if (_showSlashPalette) _buildSlashPalette(),
        ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: _Palette.bgElev1.withValues(alpha: 0.85),
                border: const Border(
                  top: BorderSide(color: _Palette.border),
                ),
              ),
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_inputFocus, _ambientPulse]),
                    builder: (context, child) {
                      final focused = _inputFocus.hasFocus;
                      final glow = focused
                          ? 0.45 + 0.15 * math.sin(_ambientPulse.value * math.pi * 2)
                          : 0.0;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: focused
                                ? [
                                    _Palette.neonViolet.withValues(alpha: 0.10),
                                    _Palette.neonCyan.withValues(alpha: 0.10),
                                  ]
                                : [
                                    _Palette.bgElev2.withValues(alpha: 0.6),
                                    _Palette.bgElev2.withValues(alpha: 0.6),
                                  ],
                          ),
                          border: Border.all(
                            color: focused
                                ? _Palette.borderActive
                                : _Palette.border,
                          ),
                          boxShadow: focused
                              ? [
                                  BoxShadow(
                                    color: _Palette.neonViolet
                                        .withValues(alpha: glow),
                                    blurRadius: 22,
                                    spreadRadius: 0,
                                  ),
                                ]
                              : null,
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Focus(
                                onKeyEvent: (node, event) {
                                  if (event is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  // Enter (no shift) — send.
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.enter &&
                                      !HardwareKeyboard
                                          .instance.isShiftPressed) {
                                    _submitQuery();
                                    return KeyEventResult.handled;
                                  }
                                  // Up-arrow on empty input — recall last
                                  // submitted query (Claude.ai parity).
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.arrowUp &&
                                      _inputController.text.isEmpty &&
                                      _lastQueryForRegen.isNotEmpty) {
                                    _inputController.text =
                                        _lastQueryForRegen;
                                    _inputController.selection =
                                        TextSelection.collapsed(
                                      offset: _lastQueryForRegen.length,
                                    );
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: TextField(
                                  controller: _inputController,
                                  focusNode: _inputFocus,
                                  cursorColor: _Palette.neonCyan,
                                  cursorWidth: 2,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: _Palette.text,
                                    height: 1.5,
                                  ),
                                  maxLines: 6,
                                  minLines: 1,
                                  decoration: InputDecoration(
                                    hintText: _brain.isDaemonConnected
                                        ? 'Ask the Brain...   (Enter to send · Shift+Enter for newline · / for commands)'
                                        : 'Daemon offline — start cortex-daemon',
                                    hintStyle: const TextStyle(
                                      fontSize: 12,
                                      color: _Palette.textFaint,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _SendButton(
                              isStreaming: isStreaming,
                              canSend: canSend,
                              ambient: _ambientPulse,
                              onSend: _submitQuery,
                              onCancel: _brain.cancelQuery,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        size: 11,
                        color: _Palette.textFaint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_estimateTokens(_inputController.text)} tokens',
                        style: const TextStyle(
                          fontSize: 10,
                          color: _Palette.textFaint,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$charCount chars',
                        style: const TextStyle(
                          fontSize: 10,
                          color: _Palette.textFaint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlashPalette() {
    final entries = const [
      ('/clear', 'Clear conversation history'),
      ('/regen', 'Regenerate last response'),
      ('/export', 'Copy thread to clipboard'),
      ('/cancel', 'Cancel current stream'),
    ];
    final filter = _inputController.text.toLowerCase();
    final matches = entries.where((e) => e.$1.startsWith(filter)).toList();
    if (matches.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: _Palette.bgElev2.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _Palette.border),
            boxShadow: [
              BoxShadow(
                color: _Palette.neonViolet.withValues(alpha: 0.18),
                blurRadius: 24,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in matches)
                InkWell(
                  onTap: () {
                    _inputController.text = m.$1;
                    _inputController.selection = TextSelection.fromPosition(
                      TextPosition(offset: m.$1.length),
                    );
                    _inputFocus.requestFocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _Palette.neonCyan,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          m.$1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _Palette.text,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            m.$2,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _Palette.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }

  void _resetSessionTelemetry() {
    setState(() {
      _accountedHistoryLen = 0;
      _sessionCostUsd      = 0.0;
      _latencyHistory.clear();
    });
  }

  /// Pretty relative time: "sada", "12s", "5m", "2h", "3d" — used in the
  /// brain bubble footer so a user catching up with old replies can see
  /// roughly when they came in without dragging in a date-formatting dep.
  static String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 5)  return 'sada';
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24)   return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// USER BUBBLE — desno, neon-cyan glass
// ═══════════════════════════════════════════════════════════════════════════════

class _UserBubble extends StatefulWidget {
  const _UserBubble({required this.text, this.onEdit, this.onCopy});
  final String text;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _Palette.neonCyan.withValues(alpha: 0.18),
                              _Palette.neonViolet.withValues(alpha: 0.18),
                            ],
                          ),
                          border: Border.all(color: _Palette.borderActive),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _Palette.neonCyan.withValues(alpha: 0.18),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: SelectableText(
                          widget.text,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _Palette.text,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: _hover ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onEdit != null)
                          _MiniAction(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit message → input',
                            onTap: widget.onEdit!,
                          ),
                        if (widget.onCopy != null) ...[
                          const SizedBox(width: 4),
                          _MiniAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'Copy message',
                            onTap: widget.onCopy!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _UserAvatar(),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [_Palette.neonCyan, _Palette.neonViolet],
        ),
        boxShadow: [
          BoxShadow(
            color: _Palette.neonCyan.withValues(alpha: 0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: const Icon(Icons.person_rounded, size: 16, color: Colors.white),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BRAIN BUBBLE — levo, holografski avatar, markdown-lite
// ═══════════════════════════════════════════════════════════════════════════════

class _BrainBubble extends StatefulWidget {
  const _BrainBubble({
    required this.text,
    required this.isError,
    required this.isStreaming,
    required this.timestamp,
    required this.model,
    required this.latencyMs,
    required this.costUsd,
    required this.isLast,
    required this.onRegenerate,
    required this.onCopy,
    required this.ambient,
  });

  final String text;
  final bool isError;
  final bool isStreaming;
  final DateTime timestamp;
  final String model;
  final int latencyMs;
  final double costUsd;
  final bool isLast;
  final VoidCallback? onRegenerate;
  final VoidCallback? onCopy;
  final AnimationController ambient;

  @override
  State<_BrainBubble> createState() => _BrainBubbleState();
}

class _BrainBubbleState extends State<_BrainBubble> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HoloBrainMark(),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedBuilder(
              animation: widget.ambient,
              builder: (context, child) {
                final glow = widget.isStreaming
                    ? 0.35 +
                        0.20 *
                            math.sin(widget.ambient.value * math.pi * 2)
                    : 0.0;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: _Palette.brainBubble,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: widget.isError
                                ? _Palette.neonRed.withValues(alpha: 0.5)
                                : widget.isStreaming
                                    ? _Palette.neonViolet.withValues(alpha: 0.6)
                                    : _Palette.border,
                          ),
                          boxShadow: widget.isStreaming
                              ? [
                                  BoxShadow(
                                    color: _Palette.neonViolet
                                        .withValues(alpha: glow),
                                    blurRadius: 24,
                                  ),
                                  BoxShadow(
                                    color: _Palette.neonMagenta
                                        .withValues(alpha: glow * 0.6),
                                    blurRadius: 36,
                                  ),
                                ]
                              : null,
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MarkdownLite(
                              text: widget.text,
                              isError: widget.isError,
                              isStreaming: widget.isStreaming,
                            ),
                            if (widget.isStreaming)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: _StreamingCursor(),
                              ),
                            const SizedBox(height: 8),
                            _buildFooter(),
                          ],
                        ),
                      ),
                      if (widget.isStreaming)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _QuantumScanPainter(
                                t: widget.ambient.value,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final showActions = _hover && !widget.isStreaming && widget.text.isNotEmpty;
    final showTimestamp = !widget.isStreaming && widget.text.isNotEmpty;
    return Row(
      children: [
        if (showTimestamp) ...[
          Text(
            _BrainChatState._relativeTime(widget.timestamp),
            style: const TextStyle(fontSize: 9.5, color: _Palette.textFaint),
          ),
          const SizedBox(width: 8),
        ],
        if (widget.model.isNotEmpty)
          Text(
            widget.model,
            style: const TextStyle(fontSize: 9.5, color: _Palette.textFaint),
          ),
        if (widget.latencyMs > 0) ...[
          const SizedBox(width: 8),
          Text(
            '${widget.latencyMs}ms',
            style: const TextStyle(fontSize: 9.5, color: _Palette.textFaint),
          ),
        ],
        if (widget.costUsd > 0) ...[
          const SizedBox(width: 8),
          Text(
            '\$${widget.costUsd.toStringAsFixed(4)}',
            style: const TextStyle(fontSize: 9.5, color: _Palette.textFaint),
          ),
        ],
        const Spacer(),
        AnimatedOpacity(
          opacity: showActions ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 140),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onCopy != null)
                _MiniAction(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy response',
                  onTap: widget.onCopy!,
                ),
              if (widget.isLast && widget.onRegenerate != null) ...[
                const SizedBox(width: 4),
                _MiniAction(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Regenerate',
                  onTap: widget.onRegenerate!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARKDOWN-LITE RENDERER — headers, code blocks, inline code, bold/italic, lists
// ═══════════════════════════════════════════════════════════════════════════════

class _MarkdownLite extends StatelessWidget {
  const _MarkdownLite({
    required this.text,
    required this.isError,
    required this.isStreaming,
  });

  final String text;
  final bool isError;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final blocks = _splitBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < blocks.length; i++) ...[
          _renderBlock(context, blocks[i]),
          if (i < blocks.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _renderBlock(BuildContext context, _MdBlock b) {
    final baseColor = isError ? _Palette.neonRed : _Palette.text;

    switch (b.kind) {
      case _MdKind.code:
        return _CodeBlock(language: b.lang, content: b.content);
      case _MdKind.h1:
        return _heading(b.content, fontSize: 17, weight: FontWeight.w700);
      case _MdKind.h2:
        return _heading(b.content, fontSize: 15, weight: FontWeight.w700);
      case _MdKind.h3:
        return _heading(b.content, fontSize: 13.5, weight: FontWeight.w700);
      case _MdKind.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in b.content.split('\n'))
              if (line.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 8),
                        child: Icon(
                          Icons.circle,
                          size: 4,
                          color: _Palette.neonCyan,
                        ),
                      ),
                      Expanded(
                        child: _inlineText(
                          line.replaceFirst(RegExp(r'^\s*[-*]\s*'), ''),
                          baseColor,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );
      case _MdKind.paragraph:
        return _inlineText(b.content, baseColor);
    }
  }

  Widget _heading(String text, {required double fontSize, required FontWeight weight}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [_Palette.neonCyan, _Palette.neonViolet, _Palette.neonMagenta],
        ).createShader(rect),
        child: Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: weight,
            color: Colors.white,
            letterSpacing: 0.2,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _inlineText(String raw, Color base) {
    final spans = _parseInline(raw, base);
    return SelectableText.rich(
      TextSpan(children: spans),
      style: TextStyle(
        fontSize: 13,
        color: base,
        height: 1.5,
      ),
    );
  }

  // ─── Block split ─────────────────────────────────────────────────────────
  List<_MdBlock> _splitBlocks(String text) {
    final out = <_MdBlock>[];
    final lines = text.split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // code fence
      if (line.trimLeft().startsWith('```')) {
        final lang = line.trimLeft().substring(3).trim();
        final buf = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          if (buf.isNotEmpty) buf.writeln();
          buf.write(lines[i]);
          i++;
        }
        i++; // skip closing fence (or EOF)
        out.add(_MdBlock(_MdKind.code, buf.toString(), lang: lang));
        continue;
      }

      // headings
      if (line.startsWith('### ')) {
        out.add(_MdBlock(_MdKind.h3, line.substring(4)));
        i++;
        continue;
      }
      if (line.startsWith('## ')) {
        out.add(_MdBlock(_MdKind.h2, line.substring(3)));
        i++;
        continue;
      }
      if (line.startsWith('# ')) {
        out.add(_MdBlock(_MdKind.h1, line.substring(2)));
        i++;
        continue;
      }

      // bullet list
      if (RegExp(r'^\s*[-*]\s').hasMatch(line)) {
        final buf = StringBuffer(line);
        i++;
        while (i < lines.length && RegExp(r'^\s*[-*]\s').hasMatch(lines[i])) {
          buf.writeln();
          buf.write(lines[i]);
          i++;
        }
        out.add(_MdBlock(_MdKind.list, buf.toString()));
        continue;
      }

      // paragraph (greedy until blank line / heading / fence / list)
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      final buf = StringBuffer(line);
      i++;
      while (i < lines.length) {
        final l = lines[i];
        if (l.trim().isEmpty) break;
        if (l.trimLeft().startsWith('```')) break;
        if (l.startsWith('#')) break;
        if (RegExp(r'^\s*[-*]\s').hasMatch(l)) break;
        buf.writeln();
        buf.write(l);
        i++;
      }
      out.add(_MdBlock(_MdKind.paragraph, buf.toString()));
    }
    return out;
  }

  // ─── Inline parser: **bold**, *italic*, `code` ───────────────────────────
  List<InlineSpan> _parseInline(String text, Color base) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*)');
    int last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final t = m.group(0)!;
      if (t.startsWith('**')) {
        spans.add(TextSpan(
          text: t.substring(2, t.length - 2),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: _Palette.text,
          ),
        ));
      } else if (t.startsWith('`')) {
        spans.add(TextSpan(
          text: t.substring(1, t.length - 1),
          style: const TextStyle(
            fontFamily: 'monospace',
            backgroundColor: Color(0xCC1A1A24),
            color: _Palette.neonCyan,
          ),
        ));
      } else if (t.startsWith('*')) {
        spans.add(TextSpan(
          text: t.substring(1, t.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
  }
}

enum _MdKind { paragraph, h1, h2, h3, list, code }

class _MdBlock {
  _MdBlock(this.kind, this.content, {this.lang = ''});
  final _MdKind kind;
  final String content;
  final String lang;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CODE BLOCK — header sa lang + copy button
// ═══════════════════════════════════════════════════════════════════════════════

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.language, required this.content});
  final String language;
  final String content;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _Palette.codeBlockBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _Palette.bgElev2.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              border: const Border(
                bottom: BorderSide(color: _Palette.border),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _Palette.langColor(widget.language),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _Palette.langColor(widget.language)
                            .withValues(alpha: 0.7),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.language.isEmpty ? 'code' : widget.language,
                  style: TextStyle(
                    fontSize: 10,
                    color: _Palette.langColor(widget.language)
                        .withValues(alpha: 0.85),
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _copy,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 12,
                          color: _copied
                              ? _Palette.neonMint
                              : _Palette.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: TextStyle(
                            fontSize: 10,
                            color: _copied
                                ? _Palette.neonMint
                                : _Palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SelectableText(
              widget.content,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: _Palette.text,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SITNI WIDGETI: avatar, status dot, pills, chips, send, particle field
// ═══════════════════════════════════════════════════════════════════════════════

class _HoloBrainMark extends StatelessWidget {
  const _HoloBrainMark({this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Palette.neonViolet,
            _Palette.neonMagenta,
            _Palette.neonCyan,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _Palette.neonViolet.withValues(alpha: 0.5),
            blurRadius: 14,
          ),
        ],
      ),
      child: Icon(Icons.auto_awesome_rounded, size: size * 0.55, color: Colors.white),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 3200.ms,
          color: Colors.white.withValues(alpha: 0.35),
        );
  }
}

class _HoloHeadline extends StatelessWidget {
  const _HoloHeadline({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [
          _Palette.neonCyan,
          _Palette.neonViolet,
          _Palette.neonMagenta,
        ],
      ).createShader(rect),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 8,
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 4200.ms,
          color: Colors.white.withValues(alpha: 0.45),
        );
  }
}

class _PulsingStatusDot extends StatefulWidget {
  const _PulsingStatusDot({required this.connected});
  final bool connected;

  @override
  State<_PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<_PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected ? _Palette.neonMint : _Palette.textFaint;
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.connected)
            AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final v = _c.value;
                return Container(
                  width: 6 + 8 * v,
                  height: 6 + 8 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: (1 - v) * 0.8),
                      width: 1.2,
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: widget.connected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.7),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.color = _Palette.textMuted,
  });
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 14,
              color: enabled ? color : _Palette.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptChip extends StatefulWidget {
  const _PromptChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  State<_PromptChip> createState() => _PromptChipState();
}

class _PromptChipState extends State<_PromptChip> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hover
                ? _Palette.neonViolet.withValues(alpha: 0.15)
                : _Palette.bgElev2.withValues(alpha: 0.6),
            border: Border.all(
              color: _hover ? _Palette.borderActive : _Palette.border,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: _Palette.neonViolet.withValues(alpha: 0.25),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 12,
                color: _Palette.neonCyan,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  widget.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _Palette.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutLegend extends StatelessWidget {
  const _ShortcutLegend();
  @override
  Widget build(BuildContext context) {
    Widget kbd(String s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _Palette.bgElev2,
            border: Border.all(color: _Palette.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            s,
            style: const TextStyle(
              fontSize: 10,
              color: _Palette.textMuted,
              fontFamily: 'monospace',
            ),
          ),
        );

    Widget row(String label, List<String> keys) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < keys.length; i++) ...[
                kbd(keys[i]),
                if (i < keys.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      '+',
                      style: TextStyle(
                        fontSize: 10,
                        color: _Palette.textFaint,
                      ),
                    ),
                  ),
              ],
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: _Palette.textMuted,
                ),
              ),
            ],
          ),
        );

    return Column(
      children: [
        row('Focus input', ['⌘', 'K']),
        row('Cancel stream', ['Esc']),
        row('Clear history', ['⌘', 'L']),
        row('Newline', ['Shift', 'Enter']),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isStreaming,
    required this.canSend,
    required this.ambient,
    required this.onSend,
    required this.onCancel,
  });
  final bool isStreaming;
  final bool canSend;
  final AnimationController ambient;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final active = isStreaming || canSend;
    return AnimatedBuilder(
      animation: ambient,
      builder: (context, child) {
        final glow = 0.3 + 0.25 * math.sin(ambient.value * math.pi * 2);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: isStreaming ? onCancel : (canSend ? onSend : null),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: active
                    ? LinearGradient(
                        colors: isStreaming
                            ? const [_Palette.neonRed, _Palette.neonAmber]
                            : const [_Palette.neonViolet, _Palette.neonCyan],
                      )
                    : null,
                color: active ? null : _Palette.bgElev2,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: (isStreaming
                                  ? _Palette.neonRed
                                  : _Palette.neonViolet)
                              .withValues(alpha: glow),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isStreaming ? Icons.stop_rounded : Icons.send_rounded,
                size: 16,
                color: active ? Colors.white : _Palette.textFaint,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 12, color: _Palette.textMuted),
          ),
        ),
      ),
    );
  }
}

/// Particle trail kursor — pulsirajući neon vertikal.
class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor();

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value;
        final pulse = 0.4 + 0.6 * (math.sin(v * math.pi * 2) * 0.5 + 0.5);
        return Row(
          children: List.generate(3, (i) {
            final delayed = (v + i * 0.18) % 1.0;
            final p = 0.3 + 0.7 * (math.sin(delayed * math.pi * 2) * 0.5 + 0.5);
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i.isEven
                      ? _Palette.neonViolet.withValues(alpha: p)
                      : _Palette.neonCyan.withValues(alpha: p),
                  boxShadow: [
                    BoxShadow(
                      color: _Palette.neonViolet.withValues(alpha: pulse * 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Neuralna pozadina — animirane tackice + tanke linije.
class _NeuralFieldPainter extends CustomPainter {
  _NeuralFieldPainter({required this.t});
  final double t;

  static const int _nodeCount = 28;
  static const double _connectDist = 160;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // gradijent ambient overlay
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.4),
        radius: 1.4,
        colors: [
          _Palette.neonViolet.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final positions = <Offset>[];
    final rng = math.Random(42);
    for (int i = 0; i < _nodeCount; i++) {
      final ax = rng.nextDouble();
      final ay = rng.nextDouble();
      final phase = rng.nextDouble() * math.pi * 2;
      final dx = math.sin(t * math.pi * 2 + phase) * 12;
      final dy = math.cos(t * math.pi * 2 + phase * 0.7) * 12;
      positions.add(Offset(ax * size.width + dx, ay * size.height + dy));
    }

    final linePaint = Paint()
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d < _connectDist) {
          final alpha = (1 - d / _connectDist) * 0.10;
          linePaint.color = _Palette.neonViolet.withValues(alpha: alpha);
          canvas.drawLine(positions[i], positions[j], linePaint);
        }
      }
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < positions.length; i++) {
      final pulse = 0.4 + 0.6 *
          (math.sin(t * math.pi * 2 + i * 0.4) * 0.5 + 0.5);
      dotPaint.color = (i % 3 == 0
              ? _Palette.neonCyan
              : i % 3 == 1
                  ? _Palette.neonViolet
                  : _Palette.neonMagenta)
          .withValues(alpha: 0.18 * pulse);
      canvas.drawCircle(positions[i], 1.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralFieldPainter oldDelegate) =>
      oldDelegate.t != t;
}

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

// ═══════════════════════════════════════════════════════════════════════════════
// AURORA POZADINA — ploveći obojeni oblaci ispod neuralne mreže.
// Render: nekoliko velikih radial gradient krugova koji sporo plove
// po canvasu. Sporiji, dublji sloj — daje osećaj prostora ispred mreže.
// ═══════════════════════════════════════════════════════════════════════════════

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.t});
  final double t;

  static const _palette = <Color>[
    _Palette.neonViolet,
    _Palette.neonCyan,
    _Palette.neonMagenta,
    _Palette.neonMint,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Bazna postavka ispod aurora
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_Palette.bg, _Palette.bgElev1, _Palette.bg],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, base);

    canvas.saveLayer(Offset.zero & size, Paint());

    final w = size.width;
    final h = size.height;
    for (int i = 0; i < 4; i++) {
      final phase = i * 0.25;
      final cx = w * (0.2 + 0.6 * (math.sin(t * math.pi * 2 + phase * 4) * 0.5 + 0.5));
      final cy = h * (0.2 + 0.6 * (math.cos(t * math.pi * 2 + phase * 3) * 0.5 + 0.5));
      final radius = (math.min(w, h) * 0.55) +
          math.sin(t * math.pi * 2 + i) * 30;
      final color = _palette[i % _palette.length].withValues(alpha: 0.10);
      final p = Paint()
        ..shader = RadialGradient(
          colors: [color, Colors.transparent],
        ).createShader(Rect.fromCircle(
          center: Offset(cx, cy),
          radius: radius,
        ));
      canvas.drawCircle(Offset(cx, cy), radius, p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

// ═══════════════════════════════════════════════════════════════════════════════
// QUANTUM SCAN — horizontalna pruga svetlosti koja se klizi po streaming
// bubble-u dok Brain generiše odgovor. Daje 3D-skener osećaj.
// ═══════════════════════════════════════════════════════════════════════════════

class _QuantumScanPainter extends CustomPainter {
  _QuantumScanPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Pozicija pruge — period 3s vertikalno
    final period = (t * 1.6) % 1.0;
    final y = size.height * period;
    final bandH = size.height * 0.18;

    final p = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          _Palette.neonCyan.withValues(alpha: 0.10),
          _Palette.neonViolet.withValues(alpha: 0.16),
          _Palette.neonCyan.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, y - bandH / 2, size.width, bandH));
    canvas.drawRect(
      Rect.fromLTWH(0, y - bandH / 2, size.width, bandH),
      p,
    );

    // Tanka beam linija u centru
    final line = Paint()
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          _Palette.neonCyan.withValues(alpha: 0.55),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2));
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _QuantumScanPainter old) => old.t != t;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONVERSATION TIMELINE RAIL — vertikalna linija sa tačkom za svaki par
// poruka, pozicionirana levo od chat liste. Daje osećaj toka konverzacije.
// (Decorativno, IgnorePointer; ne presreće mouse.)
// ═══════════════════════════════════════════════════════════════════════════════

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({required this.count, required this.streaming});
  final int count;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    if (count == 0 && !streaming) return const SizedBox.shrink();
    final dots = count + (streaming ? 1 : 0);
    return IgnorePointer(
      child: SizedBox(
        width: 14,
        child: CustomPaint(
          painter: _TimelinePainter(
            count: dots,
            streamingActive: streaming,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.count, required this.streamingActive});
  final int count;
  final bool streamingActive;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || count == 0) return;
    final cx = size.width / 2;

    // vertikalna linija
    final line = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          _Palette.neonViolet.withValues(alpha: 0.45),
          _Palette.neonCyan.withValues(alpha: 0.45),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(cx - 0.4, 0, 0.8, size.height))
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(cx, 8),
      Offset(cx, size.height - 8),
      line,
    );

    // tačke
    if (count == 1) {
      final c = Offset(cx, size.height / 2);
      final p = Paint()..color = _Palette.neonCyan;
      canvas.drawCircle(c, streamingActive ? 4 : 3, p);
      return;
    }
    final usable = (size.height - 24).clamp(0.0, double.infinity);
    final step = count > 1 ? usable / (count - 1) : 0.0;
    for (int i = 0; i < count; i++) {
      final y = 12 + i * step;
      final c = Offset(cx, y);
      final isLast = i == count - 1;
      final col = (isLast && streamingActive)
          ? _Palette.neonCyan
          : (i.isEven ? _Palette.neonViolet : _Palette.neonMagenta);
      canvas.drawCircle(
        c,
        (isLast && streamingActive) ? 3.6 : 2.6,
        Paint()..color = col.withValues(alpha: 0.85),
      );
      if (isLast && streamingActive) {
        canvas.drawCircle(
          c,
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = _Palette.neonCyan.withValues(alpha: 0.5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.count != count || old.streamingActive != streamingActive;
}

// ═══════════════════════════════════════════════════════════════════════════════
// LATENCY SPARKLINE — kondenzovani trend latencije poslednjih 20 odgovora.
// Header telemetry koja Claude.ai nema; daje brzi pulse-check da li sistem
// usporava ili ubrzava kako se konverzacija razvija.
// ═══════════════════════════════════════════════════════════════════════════════

class _LatencySparkline extends StatelessWidget {
  const _LatencySparkline({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final last = values.isNotEmpty ? values.last : 0;
    final avg = values.isEmpty
        ? 0
        : (values.reduce((a, b) => a + b) / values.length).round();
    return Tooltip(
      message: 'Latencija (poslednjih ${values.length}): '
          'last ${last}ms · avg ${avg}ms',
      child: SizedBox(
        width: 56,
        height: 18,
        child: CustomPaint(painter: _SparkPainter(values: values)),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values});
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final maxV = values.reduce(math.max).toDouble();
    final minV = values.reduce(math.min).toDouble();
    final range = (maxV - minV).clamp(1.0, double.infinity);

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : (i / (values.length - 1)) * size.width;
      final y = size.height -
          ((values[i] - minV) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Fill below the line — soft gradient down to invisible.
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _Palette.neonCyan.withValues(alpha: 0.30),
          _Palette.neonCyan.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fill);

    // Stroke with violet→cyan gradient.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [_Palette.neonViolet, _Palette.neonCyan],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, stroke);

    // Glowing dot at the latest sample.
    final lastX = values.length == 1
        ? size.width / 2
        : ((values.length - 1) / (values.length - 1)) * size.width;
    final lastY = size.height -
        ((values.last - minV) / range) * size.height;
    canvas.drawCircle(
      Offset(lastX, lastY),
      2.4,
      Paint()
        ..color = _Palette.neonCyan
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );
    canvas.drawCircle(
      Offset(lastX, lastY),
      1.6,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      !identical(old.values, values) || old.values.length != values.length;
}
