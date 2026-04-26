// SPEC-04 — Adaptive Toolbar
//
// Standalone toolbar strip that subscribes to SelectionProvider and renders
// a contextual action set based on what is selected.
//
// Layout: [Transport always] | [Contextual animated] | [Global always]
//
// Contextual sections:
//   • TrackSection      — Arm/Solo/Mute/Color/Rename
//   • AudioClipSection  — Fade In/Out/Normalize/Reverse/Pitch/Warp
//   • MidiClipSection   — Quantize/Velocity/CC/PianoRoll
//   • MarkerSection     — Tempo Change/TimeSig/Color
//   • PluginSection     — Bypass/Open Editor/Replace/Remove
//   • SlotStageSection  — Trigger/Audition/Edit Envelope
//   • SlotReelSection   — Spin/Stop/Bind Audio
//   • OverviewSection   — Project metrics shortcuts
//
// Animated tab transitions: AnimatedSwitcher with Fade + Slide-Y 8px.
//
// Standalone widget — does NOT touch existing toolbars; embed where needed.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/selection_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../common/flux_tooltip.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Adaptive toolbar that re-renders contextual section based on SelectionProvider.
class AdaptiveToolbar extends StatefulWidget {
  /// Optional callback that receives action ids ('fade_in', 'normalize', etc.)
  /// so the host screen can wire them up.
  final ValueChanged<String>? onAction;

  /// Optional override for transport callbacks (play/stop/record).
  final ValueChanged<String>? onTransport;

  /// Optional override for global callbacks (undo/redo/save).
  final ValueChanged<String>? onGlobal;

  /// Compact mode (32px height instead of 40px).
  final bool compact;

  const AdaptiveToolbar({
    super.key,
    this.onAction,
    this.onTransport,
    this.onGlobal,
    this.compact = false,
  });

  @override
  State<AdaptiveToolbar> createState() => _AdaptiveToolbarState();
}

class _AdaptiveToolbarState extends State<AdaptiveToolbar> {
  late final SelectionProvider _selection;

  @override
  void initState() {
    super.initState();
    _selection = GetIt.instance<SelectionProvider>();
    _selection.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.compact ? 32.0 : 40.0;
    final sel = _selection.selection;

    return Container(
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0F14),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withAlpha(16),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Transport (always)
          _TransportSection(onTransport: widget.onTransport),
          _Divider(),

          // Contextual (animated)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: anim,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(sel.type),
                child: _ContextualSection(
                  selection: sel,
                  onAction: widget.onAction,
                ),
              ),
            ),
          ),
          _Divider(),

          // Global (always)
          _GlobalSection(onGlobal: widget.onGlobal),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION — TRANSPORT
// ═══════════════════════════════════════════════════════════════════════════

class _TransportSection extends StatelessWidget {
  final ValueChanged<String>? onTransport;
  const _TransportSection({this.onTransport});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToolbarBtn(icon: Icons.skip_previous, tooltip: 'Rewind', onTap: () => onTransport?.call('rewind')),
        _ToolbarBtn(icon: Icons.play_arrow_rounded, tooltip: 'Play (Space)', onTap: () => onTransport?.call('play')),
        _ToolbarBtn(icon: Icons.stop_rounded, tooltip: 'Stop', onTap: () => onTransport?.call('stop')),
        _ToolbarBtn(icon: Icons.fiber_manual_record_rounded, tooltip: 'Record (R)', color: Colors.red.shade400, onTap: () => onTransport?.call('record')),
        _ToolbarBtn(icon: Icons.loop_rounded, tooltip: 'Loop', onTap: () => onTransport?.call('loop')),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION — GLOBAL (always)
// ═══════════════════════════════════════════════════════════════════════════

class _GlobalSection extends StatelessWidget {
  final ValueChanged<String>? onGlobal;
  const _GlobalSection({this.onGlobal});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToolbarBtn(icon: Icons.undo_rounded, tooltip: 'Undo (⌘Z)', onTap: () => onGlobal?.call('undo')),
        _ToolbarBtn(icon: Icons.redo_rounded, tooltip: 'Redo (⌘⇧Z)', onTap: () => onGlobal?.call('redo')),
        _ToolbarBtn(icon: Icons.save_rounded, tooltip: 'Save (⌘S)', onTap: () => onGlobal?.call('save')),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION — CONTEXTUAL DISPATCHER
// ═══════════════════════════════════════════════════════════════════════════

class _ContextualSection extends StatelessWidget {
  final Selection selection;
  final ValueChanged<String>? onAction;

  const _ContextualSection({required this.selection, this.onAction});

  @override
  Widget build(BuildContext context) {
    return switch (selection.type) {
      SelectionType.audioClip => _AudioClipSection(onAction: onAction),
      SelectionType.midiClip => _MidiClipSection(onAction: onAction),
      SelectionType.track => _TrackSection(onAction: onAction),
      SelectionType.marker => _MarkerSection(onAction: onAction),
      SelectionType.plugin => _PluginSection(onAction: onAction),
      SelectionType.slotStage => _SlotStageSection(onAction: onAction),
      SelectionType.slotReel => _SlotReelSection(onAction: onAction),
      SelectionType.none => _OverviewSection(onAction: onAction),
    };
  }
}

class _AudioClipSection extends StatelessWidget {
  final ValueChanged<String>? onAction;
  const _AudioClipSection({this.onAction});

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: 'Audio Clip',
      color: FluxForgeTheme.accentCyan,
      actions: const [
        ('fade_in', Icons.trending_up, 'Fade In'),
        ('fade_out', Icons.trending_down, 'Fade Out'),
        ('normalize', Icons.equalizer, 'Normalize'),
        ('reverse', Icons.swap_horiz, 'Reverse'),
        ('pitch', Icons.tune, 'Pitch'),
        ('warp', Icons.transform, 'Warp'),
        ('strip_silence', Icons.content_cut, 'Strip Silence'),
      ],
      onAction: onAction,
    );
  }
}

class _MidiClipSection extends StatelessWidget {
  final ValueChanged<String>? onAction;
  const _MidiClipSection({this.onAction});

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: 'MIDI Clip',
      color: FluxForgeTheme.brandGold,
      actions: const [
        ('quantize', Icons.grid_4x4, 'Quantize'),
        ('velocity', Icons.bar_chart, 'Velocity'),
        ('cc', Icons.speed, 'CC Lane'),
        ('piano_roll', Icons.piano, 'Piano Roll'),
        ('humanize', Icons.shuffle, 'Humanize'),
      ],
      onAction: onAction,
    );
  }
}

class _TrackSection extends StatelessWidget {
  final ValueChanged<String>? onAction;
  const _TrackSection({this.onAction});

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: 'Track',
      color: FluxForgeTheme.brandGold,
      actions: const [
        ('arm', Icons.fiber_manual_record_rounded, 'Arm'),
        ('solo', Icons.volume_off, 'Solo'),
        ('mute', Icons.volume_mute, 'Mute'),
        ('color', Icons.palette, 'Color'),
        ('rename', Icons.edit, 'Rename'),
        ('freeze', Icons.ac_unit, 'Freeze'),
        ('group', Icons.folder, 'Group'),
      ],
      onAction: onAction,
    );
  }
}

class _MarkerSection extends StatelessWidget {
  final ValueChanged<String>? onAction;
  const _MarkerSection({this.onAction});

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: 'Marker',
      color: FluxForgeTheme.accentCyan,
      actions: const [
        ('tempo_change', Icons.speed, 'Tempo Change'),
        ('time_sig', Icons.calendar_view_week, 'Time Signature'),
        ('color', Icons.palette, 'Color'),
        ('rename', Icons.edit, 'Rename'),
      ],
      onAction: onAction,
    );
  }
}

class _PluginSection extends StatelessWidget {
  final ValueChanged<String>? onAction;
  const _PluginSection({this.onAction});

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: 'Plugin',
      color: FluxForgeTheme.accentPurple,
      actions: const [
        ('bypass', Icons.power_settings_new, 'Bypass'),
        ('open', Icons.open_in_new, 'Open Editor'),
        ('replace', Icons.swap_vert, 'Replace'),
        ('remove', Icons.delete_outline, 'Remove'),
      ],
      onAction: onAction,
    );
  }
}

class _SlotStageSection extends StatelessWidget {
  final ValueChanged<String>? onAction;
  const _SlotStageSection({this.onAction});

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: 'Slot Stage',
      color: FluxForgeTheme.accentCyan,
      actions: const [
        ('trigger', Icons.play_arrow_rounded, 'Trigger'),
        ('audition', Icons.headphones, 'Audition'),
        ('envelope', Icons.show_chart, 'Edit Envelope'),
        ('clear', Icons.layers_clear, 'Clear Audio'),
      ],
      onAction: onAction,
    );
  }
}

class _SlotReelSection extends StatelessWidget {
  final ValueChanged<String>? onAction;
  const _SlotReelSection({this.onAction});

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: 'Reel',
      color: FluxForgeTheme.brandGold,
      actions: const [
        ('spin', Icons.refresh, 'Spin'),
        ('stop', Icons.stop_rounded, 'Stop'),
        ('bind', Icons.link, 'Bind Audio'),
        ('clear', Icons.layers_clear, 'Clear'),
      ],
      onAction: onAction,
    );
  }
}

class _OverviewSection extends StatelessWidget {
  final ValueChanged<String>? onAction;
  const _OverviewSection({this.onAction});

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      label: 'Overview',
      color: const Color(0xFF8B8C92),
      actions: const [
        ('save_session', Icons.save_alt, 'Save Session'),
        ('export', Icons.download, 'Export'),
        ('mixdown', Icons.merge, 'Mixdown'),
        ('archive', Icons.archive, 'Archive'),
      ],
      onAction: onAction,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

class _ActionRow extends StatelessWidget {
  final String label;
  final Color color;
  final List<(String, IconData, String)> actions;
  final ValueChanged<String>? onAction;

  const _ActionRow({
    required this.label,
    required this.color,
    required this.actions,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(28),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withAlpha(64), width: 1),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 1.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Action buttons (scrollable if too many)
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in actions)
                  _ToolbarBtn(
                    icon: a.$2,
                    tooltip: a.$3,
                    onTap: () => onAction?.call(a.$1),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolbarBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  const _ToolbarBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
  });

  @override
  State<_ToolbarBtn> createState() => _ToolbarBtnState();
}

class _ToolbarBtnState extends State<_ToolbarBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? const Color(0xFFB5B6BC);
    return FluxTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _hover ? c.withAlpha(26) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(widget.icon, size: 16, color: c),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withAlpha(20),
    );
  }
}
