// SPEC-13 — Quick Assign Hotbar
//
// 5 pinned audio slots positioned between Omnibar and Neural Canvas in HELIX.
// Active only in ASSIGN mode, hidden otherwise.
//
// Interactions:
//   • Drag audio from event pool → drop onto slot → bound immediately (no dialog)
//   • Tap bound slot → audition (preview)
//   • Long-press bound slot → unbind
//   • × button → quick unbind
//   • Drag-over highlights drop target with brandGold outline
//
// Persistence: SlotLabProjectProvider.hotbarBindings (5 nullable strings).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/slot_lab_project_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
import '../common/flux_tooltip.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Hotbar of 5 pinned audio drop-targets for HELIX ASSIGN mode.
class QuickAssignHotbar extends StatefulWidget {
  /// Whether the bar should be visible (true only in ASSIGN mode).
  final bool visible;

  /// Optional callback invoked after a successful bind/unbind change.
  final VoidCallback? onChanged;

  const QuickAssignHotbar({
    super.key,
    required this.visible,
    this.onChanged,
  });

  @override
  State<QuickAssignHotbar> createState() => _QuickAssignHotbarState();
}

class _QuickAssignHotbarState extends State<QuickAssignHotbar> {
  late final SlotLabProjectProvider _project;

  @override
  void initState() {
    super.initState();
    _project = GetIt.instance<SlotLabProjectProvider>();
    _project.addListener(_onProjectChanged);
  }

  @override
  void dispose() {
    _project.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: widget.visible ? 56 : 0,
      child: widget.visible
          ? _buildBar()
          : const SizedBox.shrink(),
    );
  }

  Widget _buildBar() {
    final bindings = _project.hotbarBindings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0F14),
        border: Border(
          bottom: BorderSide(
            color: FluxForgeTheme.brandGold.withAlpha(48),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _HotbarLabel(),
          const SizedBox(width: 12),
          for (var i = 0; i < bindings.length; i++) ...[
            _HotbarSlot(
              index: i,
              audioPath: bindings[i],
              onBind: (path) {
                _project.bindHotbarSlot(i, path);
                widget.onChanged?.call();
              },
              onUnbind: () {
                _project.unbindHotbarSlot(i);
                widget.onChanged?.call();
              },
            ),
            if (i < bindings.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LABEL
// ═══════════════════════════════════════════════════════════════════════════

class _HotbarLabel extends StatelessWidget {
  const _HotbarLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.brandGold.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: FluxForgeTheme.brandGold.withAlpha(64),
          width: 1,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 12, color: FluxForgeTheme.brandGold),
          SizedBox(width: 4),
          Text(
            'HOTBAR',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: FluxForgeTheme.brandGold,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT
// ═══════════════════════════════════════════════════════════════════════════

class _HotbarSlot extends StatefulWidget {
  final int index;
  final String? audioPath;
  final ValueChanged<String> onBind;
  final VoidCallback onUnbind;

  const _HotbarSlot({
    required this.index,
    required this.audioPath,
    required this.onBind,
    required this.onUnbind,
  });

  @override
  State<_HotbarSlot> createState() => _HotbarSlotState();
}

class _HotbarSlotState extends State<_HotbarSlot> {
  bool _hovering = false;
  bool _dragOver = false;
  bool _auditioning = false;

  String? get _displayLabel {
    final p = widget.audioPath;
    if (p == null) return null;
    final base = p.split(Platform.pathSeparator).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  Future<void> _audition() async {
    final path = widget.audioPath;
    if (path == null) return;
    if (_auditioning) return;
    setState(() => _auditioning = true);
    try {
      // Best-effort preview through native FFI; ignore failures (unavailable in test).
      try {
        GetIt.instance<NativeFFI>().previewAudioFile(path);
      } catch (_) {}
      // Auto-clear visual highlight after 600ms
      await Future<void>.delayed(const Duration(milliseconds: 600));
    } finally {
      if (mounted) setState(() => _auditioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bound = widget.audioPath != null;
    final highlight = _dragOver || _auditioning;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        setState(() => _dragOver = true);
        return details.data.isNotEmpty;
      },
      onLeave: (_) => setState(() => _dragOver = false),
      onAcceptWithDetails: (details) {
        setState(() => _dragOver = false);
        if (details.data.isNotEmpty) {
          widget.onBind(details.data);
        }
      },
      builder: (context, candidate, rejected) {
        final w = MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            onTap: bound ? _audition : null,
            onLongPress: bound ? widget.onUnbind : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: 110,
              height: 44,
              decoration: BoxDecoration(
                color: bound
                    ? FluxForgeTheme.brandGold.withAlpha(_hovering ? 36 : 22)
                    : Colors.white.withAlpha(_hovering ? 14 : 8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: highlight
                      ? FluxForgeTheme.brandGoldBright
                      : bound
                          ? FluxForgeTheme.brandGold.withAlpha(96)
                          : Colors.white.withAlpha(48),
                  width: highlight ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: bound
                  ? _buildBound(context)
                  : _buildEmpty(),
            ),
          ),
        );
        return FluxTooltip(
          message: bound
              ? 'Slot ${widget.index + 1}: $_displayLabel\nTap = audition\nLong-press = unbind'
              : 'Slot ${widget.index + 1} (empty)\nDrag audio here to bind',
          child: w,
        );
      },
    );
  }

  Widget _buildBound(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Slot index pill
        Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FluxForgeTheme.brandGold.withAlpha(48),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '${widget.index + 1}',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: FluxForgeTheme.brandGold,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Label (truncated)
        Expanded(
          child: Text(
            _displayLabel ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFE8E8EA),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Unbind X
        InkWell(
          onTap: widget.onUnbind,
          borderRadius: BorderRadius.circular(2),
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: Icon(Icons.close, size: 12, color: Color(0xFF999A9F)),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '${widget.index + 1}',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF707080),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'empty',
          style: TextStyle(
            fontSize: 10,
            color: const Color(0xFF707080).withAlpha(180),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
