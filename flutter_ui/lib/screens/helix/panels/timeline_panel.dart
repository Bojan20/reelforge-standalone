// HELIX dock — TIMELINE panel (Sprint 15 Faza 4.C split #10).
//
// Stage sequence playback + replay + jump-to-stage + scrubber.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _TimelinePanel(State) — root widget + scrubber state machine

part of '../../helix_screen.dart';// ── TIMELINE Panel ───────────────────────────────────────────────────────────

class _TimelinePanel extends StatefulWidget {
  const _TimelinePanel();

  @override
  State<_TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<_TimelinePanel> {
  // T1: drag state
  String? _draggingEventId;
  double _dragStartMs = 0;
  double _dragStartX = 0;

  // Zoom & scroll state
  double _zoomLevel = 1.0; // 1.0 = fit all, higher = zoomed in
  double _scrollOffsetMs = 0.0; // horizontal scroll in ms
  static const double _minZoom = 0.5;
  static const double _maxZoom = 8.0;
  // Snap grid interval in ms (0 = off, 250 = quarter-second, 500 = half, 1000 = 1s)
  double _snapGridMs = 0;

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when MiddlewareProvider changes
    return ListenableBuilder(
      listenable: GetIt.instance<MiddlewareProvider>(),
      builder: (context, _) => _buildContent(context),
    );
  }

  double _snapToGrid(double ms) {
    if (_snapGridMs <= 0) return ms;
    return (ms / _snapGridMs).round() * _snapGridMs;
  }

  Widget _buildContent(BuildContext context) {
    final mw = GetIt.instance<MiddlewareProvider>();
    final engine = GetIt.instance<EngineProvider>();
    final events = mw.compositeEvents;

    // Access playhead from parent
    final helixState = context.findAncestorStateOfType<_HelixScreenState>();
    final playheadSec = helixState?._playheadSeconds ?? 0.0;

    // Group events by trackIndex, build real timeline tracks
    final trackMap = <int, List<SlotCompositeEvent>>{};
    for (final e in events) {
      trackMap.putIfAbsent(e.trackIndex, () => []).add(e);
    }

    // Find timeline extent (max position + reasonable width)
    double totalMs = 8000; // 8 second default view
    for (final e in events) {
      final end = e.timelinePositionMs + 1000;
      if (end > totalMs) totalMs = end;
    }

    // Visible window based on zoom
    final visibleMs = totalMs / _zoomLevel;
    final maxScrollMs = (totalMs - visibleMs).clamp(0.0, double.infinity);
    final scrollMs = _scrollOffsetMs.clamp(0.0, maxScrollMs);

    // Playhead fraction within visible window
    final playheadMs = playheadSec * 1000;
    final playheadFrac = visibleMs > 0
        ? ((playheadMs - scrollMs) / visibleMs).clamp(0.0, 1.0)
        : 0.0;

    // Build track list from real data
    final sortedTracks = trackMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    // Ruler marks — adaptive based on zoom
    final rulerIntervalMs = _rulerInterval(visibleMs);
    final firstMark = (scrollMs / rulerIntervalMs).ceil() * rulerIntervalMs;
    final rulerMarks = <double>[];
    for (var ms = firstMark; ms <= scrollMs + visibleMs; ms += rulerIntervalMs) {
      rulerMarks.add(ms);
    }

    return _DockCard(
      accent: FluxForgeTheme.accentOrange,
      child: Column(
        children: [
          // Toolbar — zoom controls + snap
          Row(children: [
            _DockLabel('TIMELINE', color: FluxForgeTheme.accentOrange),
            const Spacer(),
            // Snap grid selector
            GestureDetector(
              onTap: () => setState(() {
                _snapGridMs = switch (_snapGridMs) {
                  0 => 250,
                  250 => 500,
                  500 => 1000,
                  _ => 0,
                };
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _snapGridMs > 0 ? FluxForgeTheme.accentCyan.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _snapGridMs > 0 ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle)),
                child: Text(_snapGridMs > 0 ? 'SNAP ${_snapGridMs.toInt()}ms' : 'SNAP OFF',
                  style: FluxForgeTheme.dockMono(size: 7,
                    color: _snapGridMs > 0 ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                    weight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            // Zoom controls
            GestureDetector(
              onTap: () => setState(() {
                _zoomLevel = (_zoomLevel / 1.5).clamp(_minZoom, _maxZoom);
              }),
              child: const Icon(Icons.zoom_out_rounded, size: 14, color: FluxForgeTheme.textSecondary),
            ),
            const SizedBox(width: 4),
            Text('${_zoomLevel.toStringAsFixed(1)}x',
              style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() {
                _zoomLevel = (_zoomLevel * 1.5).clamp(_minZoom, _maxZoom);
              }),
              child: const Icon(Icons.zoom_in_rounded, size: 14, color: FluxForgeTheme.textSecondary),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() { _zoomLevel = 1.0; _scrollOffsetMs = 0; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(3)),
                child: Text('FIT', style: FluxForgeTheme.dockMono(size: 7,
                  color: FluxForgeTheme.textTertiary, weight: FontWeight.w600)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          // FAZA 3.6.B + 3.6.C + 3.6.D — Timeline Intelligence Bar.
          // Tri slot-native indikatora iznad Stage Flow Strip-a:
          //   ⚔ Audio Clash Detector — pairwise (stage, layer) overlap
          //     na istom busId-u tokom poslednjeg spina; tooltip lista
          //     do 8 najgorih clash-ova sortiranih po duration.
          //   ⏱ Time Budget Compliance — total spin duration vs
          //     jurisdiction cap (3500ms UKGC default), per-stage soft
          //     caps iz industrijske matrice (`_kStageBudgets`).
          //   🔥 Anticipation Density Meter — % poslednjih 50 spinova
          //     koji su trigger-ovali ANTICIPATION_TENSION_*; sweet spot
          //     15–30% (color tier: <5 red, 5–15 orange, 15–30 green,
          //     >30 yellow).
          const TimelineIntelligenceBar(),
          const SizedBox(height: 4),
          // FAZA 3.6.A — Stage Flow Strip (slot-native composition view).
          // Painta horizontalnu traku sa chunk-om za svaki stage iz
          // SlotLabCoordinator.stageProvider.lastStages, kategorije
          // bojom-kodirane (spin/win/feature/...).  Klik na chunk
          // = audition kroz EventRegistry.triggerStage(), isti put
          // koji TIMELINE JUMP quick-action koristi.
          const StageFlowStrip(height: 56),
          const SizedBox(height: 4),
          // FAZA 3.6.E — Session Recorder + Best Win Detector.
          // Compact footer: [N spins] [REC] dugmad pokreću batch spin
          // sequence kroz SlotLabCoordinator; snapshots (stages +
          // result) idu u in-memory ring buffer.  Posle završetka,
          // panel pokazuje session stats (count, hit, RTP, anti) +
          // Best Win badge sa replay handle-om.
          //
          // Audio bounce u MasterRingBuffer ostaje za 3.6.F (Marketing
          // Clip Export) — Rust crate change `expandTo60s()` je future
          // work; replay već radi kroz stage re-fire.
          const SessionRecorderPanel(),
          const SizedBox(height: 4),
          // FAZA 3.6.G — Stress Test Panel.
          // Batch simulation (rf-ab-sim) — runs 10K/100K/1M spins in
          // background Rust threads, streams progress via polling,
          // shows RTP delta, voice budget, event heatmap, warnings.
          const StressTestPanel(),
          const SizedBox(height: 4),
          // Ruler — clickable to seek (T3), with scroll
          GestureDetector(
            onTapDown: (d) {
              final rulerWidth = (context.size?.width ?? 400) - 80 - 24;
              final frac = ((d.localPosition.dx - 80) / rulerWidth).clamp(0.0, 1.0);
              final seekMs = scrollMs + frac * visibleMs;
              final seekSec = seekMs / 1000.0;
              engine.seek(seekSec);
              helixState?.setPlayhead(seekSec);
            },
            onHorizontalDragUpdate: (d) {
              setState(() {
                final rulerWidth = (context.size?.width ?? 400) - 80 - 24;
                final msDelta = -(d.delta.dx / rulerWidth) * visibleMs;
                _scrollOffsetMs = (_scrollOffsetMs + msDelta).clamp(0.0, maxScrollMs);
              });
            },
            child: SizedBox(
              height: 18,
              child: LayoutBuilder(builder: (_, constraints) {
                final rulerWidth = constraints.maxWidth - 80;
                return Stack(
                  children: [
                    const Positioned(left: 0, top: 0, bottom: 0, child: SizedBox(width: 80)),
                    ...rulerMarks.map((ms) {
                      final frac = (ms - scrollMs) / visibleMs;
                      if (frac < 0 || frac > 1) return const SizedBox.shrink();
                      final sec = ms / 1000;
                      final label = sec < 60
                          ? '${sec.toStringAsFixed(sec == sec.truncateToDouble() ? 0 : 1)}s'
                          : '${(sec / 60).floor()}:${(sec % 60).floor().toString().padLeft(2, '0')}';
                      return Positioned(
                        left: 80 + frac * rulerWidth,
                        top: 2,
                        child: Text(label, style: FluxForgeTheme.dockMono(
                          size: 9,
                          color: FluxForgeTheme.textTertiary)),
                      );
                    }),
                    // Snap grid lines
                    if (_snapGridMs > 0)
                      ...List.generate(
                        ((visibleMs / _snapGridMs) + 1).ceil(),
                        (i) {
                          final gridMs = ((scrollMs / _snapGridMs).floor() + i) * _snapGridMs;
                          final frac = (gridMs - scrollMs) / visibleMs;
                          if (frac < 0 || frac > 1) return const SizedBox.shrink();
                          return Positioned(
                            left: 80 + frac * rulerWidth,
                            top: 14, bottom: 0,
                            child: Container(width: 0.5, color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
                          );
                        },
                      ),
                  ],
                );
              }),
            ),
          ),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          const SizedBox(height: 2),
          // Tracks with playhead overlay — scrollable + zoomable
          Expanded(
            child: Listener(
              // Scroll wheel for horizontal scroll, Ctrl+wheel for zoom
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    final isZoom = HardwareKeyboard.instance.isMetaPressed ||
                        HardwareKeyboard.instance.isControlPressed;
                    if (isZoom) {
                      final factor = event.scrollDelta.dy > 0 ? 0.85 : 1.18;
                      _zoomLevel = (_zoomLevel * factor).clamp(_minZoom, _maxZoom);
                    } else {
                      final scrollDelta = event.scrollDelta.dy * (visibleMs / 600);
                      _scrollOffsetMs = (_scrollOffsetMs + scrollDelta).clamp(0.0, maxScrollMs);
                    }
                  });
                }
              },
              child: sortedTracks.isEmpty
                ? Center(child: Text('No events on timeline.\nAssign composite events in SlotLab.',
                    textAlign: TextAlign.center,
                    style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textTertiary, height: 1.5)))
                : LayoutBuilder(builder: (_, constraints) {
                    final trackAreaWidth = constraints.maxWidth - 80;
                    return Stack(
                      children: [
                        // Snap grid vertical lines
                        if (_snapGridMs > 0)
                          ...List.generate(
                            ((visibleMs / _snapGridMs) + 1).ceil(),
                            (i) {
                              final gridMs = ((scrollMs / _snapGridMs).floor() + i) * _snapGridMs;
                              final frac = (gridMs - scrollMs) / visibleMs;
                              if (frac < 0 || frac > 1) return const SizedBox.shrink();
                              return Positioned(
                                left: 80 + frac * trackAreaWidth,
                                top: 0, bottom: 0,
                                child: Container(width: 0.5, color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.15)),
                              );
                            },
                          ),
                        // Tracks
                        Column(
                          children: sortedTracks.map((entry) {
                            final trackEvents = entry.value;
                            final trackName = trackEvents.first.name.length > 10
                                ? trackEvents.first.name.substring(0, 10) : trackEvents.first.name;
                            final color = trackEvents.first.color;
                            // Filter events visible in current scroll window
                            final visibleEvents = trackEvents.where((e) {
                              final eventEnd = e.timelinePositionMs + 1000;
                              return eventEnd >= scrollMs && e.timelinePositionMs <= scrollMs + visibleMs;
                            }).toList();
                            return Expanded(child: _TlTrackInteractive(
                              name: trackName,
                              color: color,
                              events: visibleEvents,
                              maxMs: visibleMs,
                              scrollOffsetMs: scrollMs,
                              trackAreaWidth: trackAreaWidth,
                              middleware: mw,
                              snapGridMs: _snapGridMs,
                            ));
                          }).toList(),
                        ),
                        // T4: Playhead line
                        if (playheadMs >= scrollMs && playheadMs <= scrollMs + visibleMs)
                          Positioned(
                            left: 80 + (playheadFrac * trackAreaWidth),
                            top: 0, bottom: 0,
                            child: Container(
                              width: 2,
                              color: FluxForgeTheme.accentRed.withValues(alpha: 0.8),
                            ),
                          ),
                        // Playhead triangle at top
                        if (playheadMs >= scrollMs && playheadMs <= scrollMs + visibleMs)
                          Positioned(
                            left: 80 + (playheadFrac * trackAreaWidth) - 4,
                            top: 0,
                            child: CustomPaint(
                              size: const Size(8, 6),
                              painter: _PlayheadTrianglePainter(
                                color: FluxForgeTheme.accentRed),
                            ),
                          ),
                      ],
                    );
                  }),
            ),
          ),
        ],
      ),
    );
  }

  /// Compute adaptive ruler interval based on visible window
  double _rulerInterval(double visibleMs) {
    if (visibleMs > 20000) return 5000;
    if (visibleMs > 10000) return 2000;
    if (visibleMs > 4000) return 1000;
    if (visibleMs > 2000) return 500;
    if (visibleMs > 800) return 250;
    return 100;
  }
}
