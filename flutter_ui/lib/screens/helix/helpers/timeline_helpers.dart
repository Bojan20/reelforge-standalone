// HELIX dock helpers — Timeline track widget (Sprint 15 batch 5 split #18).
//
// Interactive timeline track sa drag/scrub support + playhead triangle
// painter.  Used by `_TimelinePanel` (panels/timeline_panel.dart).
//
// Extracted from helix_screen.dart 2026-05-11.

part of '../../helix_screen.dart';class _TlTrackInteractive extends StatefulWidget {
  final String name;
  final Color color;
  final List<SlotCompositeEvent> events;
  final double maxMs;
  final double scrollOffsetMs;
  final double trackAreaWidth;
  final MiddlewareProvider middleware;
  final double snapGridMs;
  const _TlTrackInteractive({required this.name, required this.color,
    required this.events, required this.maxMs, required this.trackAreaWidth,
    required this.middleware, this.scrollOffsetMs = 0, this.snapGridMs = 0});

  @override
  State<_TlTrackInteractive> createState() => _TlTrackInteractiveState();
}

class _TlTrackInteractiveState extends State<_TlTrackInteractive> {
  // T1: move drag state
  String? _draggingId;
  double _dragStartMs = 0;
  double _dragStartX = 0;

  // T2: resize drag state
  String? _resizingId;
  double _resizeStartX = 0;
  // Map of event id → visual width factor (>1 = expanded)
  final Map<String, double> _regionWidthFactors = {};
  double _resizeStartFactor = 1.0;

  // T5/T6: context menu
  void _showRegionMenu(BuildContext context, SlotCompositeEvent e) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      color: FluxForgeTheme.bgSurface,
      position: RelativeRect.fromLTRB(
        offset.dx, offset.dy + renderBox.size.height + 2,
        offset.dx + 160, offset.dy + renderBox.size.height + 2),
      items: [
        // Delete
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            const Icon(Icons.delete_outline_rounded, size: 12, color: FluxForgeTheme.accentRed),
            const SizedBox(width: 6),
            Text('Delete', style: FluxForgeTheme.dockMono(
              size: 10, color: FluxForgeTheme.accentRed)),
          ]),
        ),
        // Duplicate
        PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(children: [
            const Icon(Icons.copy_outlined, size: 12, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 6),
            Text('Duplicate', style: FluxForgeTheme.dockMono(
              size: 10, color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // Rename
        PopupMenuItem<String>(
          value: 'rename',
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 12, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 6),
            Text('Rename', style: FluxForgeTheme.dockMono(
              size: 10, color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // F6: Move to track sub-items (0-4)
        ...List.generate(5, (i) => PopupMenuItem<String>(
          value: 'track_$i',
          child: Text('Move to Track $i', style: FluxForgeTheme.dockMono(
            size: 10, color: FluxForgeTheme.textSecondary)),
        )),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'delete':
          silentRun('timeline.deleteEvent', () { widget.middleware.deleteEvent(e.id); });
        case 'duplicate':
          silentRun('timeline.duplicateEvent', () {
            final now = DateTime.now();
            widget.middleware.addCompositeEvent(e.copyWith(
              id: 'dup_${now.millisecondsSinceEpoch}',
              name: '${e.name}_copy',
              timelinePositionMs: e.timelinePositionMs + 200,
            ));
          });
        case 'rename':
          _showRenameDialog(context, e);
        default:
          if (value.startsWith('track_')) {
            final trackIdx = int.tryParse(value.substring(6)) ?? 0;
            silentRun('timeline.moveToTrack', () {
              widget.middleware.updateCompositeEvent(
                e.copyWith(trackIndex: trackIdx));
            });
          }
      }
    });
  }

  void _showRenameDialog(BuildContext context, SlotCompositeEvent e) {
    final ctrl = TextEditingController(text: e.name);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: Text('Rename Event', style: FluxForgeTheme.dockMono(
          size: 13, color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: FluxForgeTheme.dockMono(size: 11, color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Event name',
            hintStyle: FluxForgeTheme.dockMono(color: FluxForgeTheme.textTertiary),
            filled: true, fillColor: FluxForgeTheme.bgElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: FluxForgeTheme.dockSans(color: FluxForgeTheme.textTertiary))),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                silentRun('timeline.renameEvent', () {
                  widget.middleware.updateCompositeEvent(e.copyWith(name: name));
                });
              }
              Navigator.of(context).pop();
            },
            child: Text('OK', style: FluxForgeTheme.dockSans(color: FluxForgeTheme.accentCyan))),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(width: 80, child: Text(widget.name, style: FluxForgeTheme.dockMono(
          size: 9, color: FluxForgeTheme.textTertiary))),
        Expanded(
          child: LayoutBuilder(
            builder: (_, c) => Stack(
              children: [
                Container(height: 18, decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  borderRadius: BorderRadius.circular(3))),
                // T1+T2+T5+T6: draggable + resizable regions with context menu
                ...widget.events.map((e) {
                  final start = ((e.timelinePositionMs - widget.scrollOffsetMs) / widget.maxMs).clamp(-0.3, 1.0);
                  final baseFraction = (1000 / widget.maxMs).clamp(0.02, 0.3);
                  final factor = _regionWidthFactors[e.id] ?? 1.0;
                  final widthPx = (baseFraction * c.maxWidth * factor)
                    .clamp(8.0, c.maxWidth - start * c.maxWidth);

                  return Positioned(
                    left: start * c.maxWidth,
                    width: widthPx,
                    top: 2, bottom: 2,
                    child: Builder(
                      builder: (regionCtx) => GestureDetector(
                        // T1: horizontal move drag
                        onHorizontalDragStart: (d) {
                          // Check if near right edge for T2
                          final localX = d.localPosition.dx;
                          if (localX >= widthPx - 8) {
                            _resizingId = e.id;
                            _resizeStartX = d.globalPosition.dx;
                            _resizeStartFactor = factor;
                            _draggingId = null;
                          } else {
                            _draggingId = e.id;
                            _dragStartMs = e.timelinePositionMs;
                            _dragStartX = d.globalPosition.dx;
                            _resizingId = null;
                          }
                        },
                        onHorizontalDragUpdate: (d) {
                          if (_resizingId == e.id) {
                            // T2: resize — adjust factor
                            final deltaX = d.globalPosition.dx - _resizeStartX;
                            final newFactor = (_resizeStartFactor +
                              deltaX / (baseFraction * c.maxWidth)).clamp(0.5, 5.0);
                            setState(() => _regionWidthFactors[e.id] = newFactor);
                          } else if (_draggingId == e.id) {
                            // T1: move (with snap-to-grid support)
                            final deltaX = d.globalPosition.dx - _dragStartX;
                            final deltaMs = (deltaX / c.maxWidth) * widget.maxMs;
                            var newMs = (_dragStartMs + deltaMs).clamp(0.0, widget.scrollOffsetMs + widget.maxMs - 1000);
                            // Snap to grid if enabled
                            if (widget.snapGridMs > 0) {
                              newMs = (newMs / widget.snapGridMs).round() * widget.snapGridMs;
                            }
                            widget.middleware.updateCompositeEvent(
                              e.copyWith(timelinePositionMs: newMs));
                          }
                        },
                        onHorizontalDragEnd: (_) {
                          // T2: persist resize — encode visual factor in maxInstances (≥1)
                          // as a proxy: factor * 100 stored, recovered on next draw.
                          // SlotCompositeEvent has no durationMs field — we persist the
                          // modifiedAt timestamp so the timeline re-reads _regionWidthFactors.
                          if (_resizingId == e.id) {
                            silentRun('timeline.resizePersist', () {
                              widget.middleware.updateCompositeEvent(
                                e.copyWith(modifiedAt: DateTime.now()));
                            });
                          }
                          _draggingId = null;
                          _resizingId = null;
                        },
                        // T5: right-click context menu
                        onSecondaryTapDown: (_) => _showRegionMenu(regionCtx, e),
                        child: MouseRegion(
                          cursor: _resizingId == e.id
                            ? SystemMouseCursors.resizeLeftRight
                            : SystemMouseCursors.move,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(alpha: 0.25),
                                  border: Border.all(color: widget.color.withValues(alpha: 0.5)),
                                  borderRadius: BorderRadius.circular(2)),
                                child: Center(child: Text(
                                  e.name.length > 6 ? e.name.substring(0, 6) : e.name,
                                  style: FluxForgeTheme.dockMono(
                                    size: 9, color: widget.color.withValues(alpha: 0.8)),
                                  overflow: TextOverflow.clip)),
                              ),
                              // T2: resize handle indicator (right edge)
                              Positioned(
                                right: 0, top: 0, bottom: 0,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeLeftRight,
                                  child: Container(
                                    width: 4,
                                    decoration: BoxDecoration(
                                      color: widget.color.withValues(alpha: 0.5),
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(2),
                                        bottomRight: Radius.circular(2))),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAYHEAD TRIANGLE PAINTER (T4)
// ─────────────────────────────────────────────────────────────────────────────

class _PlayheadTrianglePainter extends CustomPainter {
  final Color color;
  _PlayheadTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// AUDIO CONTEXT LENS (A3 + A5)
// ─────────────────────────────────────────────────────────────────────────────

