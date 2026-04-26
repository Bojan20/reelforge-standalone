// SPEC-03 — Contextual Inspector
//
// Listens to SelectionProvider and routes to the right sub-inspector
// based on what is currently selected. Single widget that adapts to context.
//
// Sub-inspectors:
//   • TrackInspector             — name, color, routing, pre-gain, lock, freeze
//   • ClipAudioInspector         — start/end, gain, pitch, warp, fades
//   • ClipMidiInspector          — channel, key, velocity, length, quantize
//   • MarkerInspector            — type, position, label, color
//   • PluginQuickInspector       — 8 most-used params + Open Full
//   • SlotStageInspector         — stage id, audio path, envelope
//   • SlotReelInspector          — reel index, bound audio, repeat policy
//   • ProjectOverviewInspector   — fallback (nothing selected)
//
// All sub-inspectors are compact, inline-editable where possible,
// and emit change callbacks via on*Changed for the host to wire up.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/selection_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Right-panel inspector that adapts to current selection.
class ContextualInspector extends StatefulWidget {
  /// Optional change callback — fired when any sub-inspector emits a value.
  /// Format: ('field_name', dynamic_new_value)
  final void Function(String field, dynamic value)? onChanged;

  /// Action callback — fired when sub-inspector requests an action
  /// (e.g. 'open_plugin_editor', 'jump_to_marker').
  final ValueChanged<String>? onAction;

  const ContextualInspector({
    super.key,
    this.onChanged,
    this.onAction,
  });

  @override
  State<ContextualInspector> createState() => _ContextualInspectorState();
}

class _ContextualInspectorState extends State<ContextualInspector> {
  late final SelectionProvider _selection;

  @override
  void initState() {
    super.initState();
    _selection = GetIt.instance<SelectionProvider>();
    _selection.addListener(_onChanged);
  }

  @override
  void dispose() {
    _selection.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selection.selection;
    return Container(
      color: FluxForgeTheme.bgVoid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(sel),
          const Divider(height: 1, color: Color(0xFF1F2028)),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: anim,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(sel.toString()),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: _buildBody(sel),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Selection sel) {
    final (label, color) = _headerOf(sel.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withAlpha(120), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          if (sel.hasSelection)
            Text(
              _idLabel(sel),
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF707080),
                fontFamily: 'JetBrainsMono, monospace',
              ),
            ),
        ],
      ),
    );
  }

  String _idLabel(Selection sel) {
    if (sel.clipId != null) return sel.clipId!;
    if (sel.trackId != null) return 'track ${sel.trackId}';
    if (sel.markerId != null) return sel.markerId!;
    if (sel.pluginId != null) return sel.pluginId!;
    if (sel.stageId != null) return sel.stageId!;
    if (sel.reelIndex != null) return 'reel ${sel.reelIndex}';
    return '';
  }

  (String, Color) _headerOf(SelectionType t) => switch (t) {
        SelectionType.track => ('Track', FluxForgeTheme.brandGold),
        SelectionType.audioClip => ('Audio Clip', FluxForgeTheme.accentCyan),
        SelectionType.midiClip => ('MIDI Clip', FluxForgeTheme.brandGold),
        SelectionType.marker => ('Marker', FluxForgeTheme.accentCyan),
        SelectionType.plugin => ('Plugin', FluxForgeTheme.accentPurple),
        SelectionType.slotStage => ('Slot Stage', FluxForgeTheme.accentCyan),
        SelectionType.slotReel => ('Slot Reel', FluxForgeTheme.brandGold),
        SelectionType.none => ('Project', Color(0xFF8B8C92)),
      };

  Widget _buildBody(Selection sel) {
    return switch (sel.type) {
      SelectionType.track =>
        TrackInspector(trackId: sel.trackId ?? 0, onChanged: widget.onChanged),
      SelectionType.audioClip => ClipAudioInspector(
          clipId: sel.clipId ?? '', onChanged: widget.onChanged),
      SelectionType.midiClip => ClipMidiInspector(
          clipId: sel.clipId ?? '', onChanged: widget.onChanged),
      SelectionType.marker => MarkerInspector(
          markerId: sel.markerId ?? '', onChanged: widget.onChanged),
      SelectionType.plugin => PluginQuickInspector(
          pluginId: sel.pluginId ?? '',
          onChanged: widget.onChanged,
          onAction: widget.onAction,
        ),
      SelectionType.slotStage => SlotStageInspector(
          stageId: sel.stageId ?? '', onChanged: widget.onChanged),
      SelectionType.slotReel => SlotReelInspector(
          reelIndex: sel.reelIndex ?? 0, onChanged: widget.onChanged),
      SelectionType.none => const ProjectOverviewInspector(),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-INSPECTOR: TRACK
// ═══════════════════════════════════════════════════════════════════════════

class TrackInspector extends StatelessWidget {
  final int trackId;
  final void Function(String, dynamic)? onChanged;

  const TrackInspector({super.key, required this.trackId, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InspectorField.text(
          label: 'Name',
          initial: 'Track $trackId',
          onChanged: (v) => onChanged?.call('track.name', v),
        ),
        _InspectorField.color(
          label: 'Color',
          initial: FluxForgeTheme.brandGold,
          onChanged: (v) => onChanged?.call('track.color', v),
        ),
        _InspectorField.dropdown(
          label: 'Routing',
          initial: 'Master',
          options: const ['Master', 'Bus 1', 'Bus 2', 'Aux 1', 'Aux 2'],
          onChanged: (v) => onChanged?.call('track.routing', v),
        ),
        _InspectorField.slider(
          label: 'Pre-gain',
          initial: 0.0,
          min: -24,
          max: 24,
          unit: 'dB',
          onChanged: (v) => onChanged?.call('track.pregain', v),
        ),
        _InspectorField.toggle(
          label: 'Lock',
          initial: false,
          onChanged: (v) => onChanged?.call('track.lock', v),
        ),
        _InspectorField.toggle(
          label: 'Freeze',
          initial: false,
          onChanged: (v) => onChanged?.call('track.freeze', v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-INSPECTOR: AUDIO CLIP
// ═══════════════════════════════════════════════════════════════════════════

class ClipAudioInspector extends StatelessWidget {
  final String clipId;
  final void Function(String, dynamic)? onChanged;

  const ClipAudioInspector({super.key, required this.clipId, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InspectorField.text(
          label: 'Start',
          initial: '0:00.000',
          onChanged: (v) => onChanged?.call('clip.start', v),
        ),
        _InspectorField.text(
          label: 'End',
          initial: '0:00.000',
          onChanged: (v) => onChanged?.call('clip.end', v),
        ),
        _InspectorField.slider(
          label: 'Gain',
          initial: 0.0,
          min: -24,
          max: 24,
          unit: 'dB',
          onChanged: (v) => onChanged?.call('clip.gain', v),
        ),
        _InspectorField.slider(
          label: 'Pitch',
          initial: 0.0,
          min: -12,
          max: 12,
          unit: 'st',
          onChanged: (v) => onChanged?.call('clip.pitch', v),
        ),
        _InspectorField.dropdown(
          label: 'Warp',
          initial: 'Beats',
          options: const ['Off', 'Beats', 'Tones', 'Texture', 'Re-Pitch', 'Complex'],
          onChanged: (v) => onChanged?.call('clip.warp', v),
        ),
        _InspectorField.slider(
          label: 'Fade In',
          initial: 0,
          min: 0,
          max: 5000,
          unit: 'ms',
          onChanged: (v) => onChanged?.call('clip.fade_in', v),
        ),
        _InspectorField.slider(
          label: 'Fade Out',
          initial: 0,
          min: 0,
          max: 5000,
          unit: 'ms',
          onChanged: (v) => onChanged?.call('clip.fade_out', v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-INSPECTOR: MIDI CLIP
// ═══════════════════════════════════════════════════════════════════════════

class ClipMidiInspector extends StatelessWidget {
  final String clipId;
  final void Function(String, dynamic)? onChanged;

  const ClipMidiInspector({super.key, required this.clipId, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InspectorField.dropdown(
          label: 'MIDI Ch',
          initial: '1',
          options: List.generate(16, (i) => '${i + 1}'),
          onChanged: (v) => onChanged?.call('midi.channel', v),
        ),
        _InspectorField.slider(
          label: 'Velocity',
          initial: 100,
          min: 0,
          max: 127,
          unit: '',
          onChanged: (v) => onChanged?.call('midi.velocity', v),
        ),
        _InspectorField.slider(
          label: 'Length',
          initial: 1.0,
          min: 0.1,
          max: 16.0,
          unit: 'beats',
          onChanged: (v) => onChanged?.call('midi.length', v),
        ),
        _InspectorField.dropdown(
          label: 'Quantize',
          initial: '1/16',
          options: const ['Off', '1/4', '1/8', '1/16', '1/32', 'Triplet 1/8'],
          onChanged: (v) => onChanged?.call('midi.quantize', v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-INSPECTOR: MARKER
// ═══════════════════════════════════════════════════════════════════════════

class MarkerInspector extends StatelessWidget {
  final String markerId;
  final void Function(String, dynamic)? onChanged;

  const MarkerInspector({super.key, required this.markerId, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InspectorField.dropdown(
          label: 'Type',
          initial: 'Marker',
          options: const ['Marker', 'Tempo', 'Time Sig', 'Section', 'Loop'],
          onChanged: (v) => onChanged?.call('marker.type', v),
        ),
        _InspectorField.text(
          label: 'Position',
          initial: '0:00.000',
          onChanged: (v) => onChanged?.call('marker.position', v),
        ),
        _InspectorField.text(
          label: 'Label',
          initial: 'New Marker',
          onChanged: (v) => onChanged?.call('marker.label', v),
        ),
        _InspectorField.color(
          label: 'Color',
          initial: FluxForgeTheme.accentCyan,
          onChanged: (v) => onChanged?.call('marker.color', v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-INSPECTOR: PLUGIN
// ═══════════════════════════════════════════════════════════════════════════

class PluginQuickInspector extends StatelessWidget {
  final String pluginId;
  final void Function(String, dynamic)? onChanged;
  final ValueChanged<String>? onAction;

  const PluginQuickInspector({
    super.key,
    required this.pluginId,
    this.onChanged,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    // 8 most-used params (placeholder values until host wires real plugin state).
    final params = const [
      ('Drive', 0.0),
      ('Mix', 50.0),
      ('Tone', 0.5),
      ('Output', 0.0),
      ('Attack', 10.0),
      ('Release', 100.0),
      ('Threshold', -10.0),
      ('Ratio', 4.0),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 4×2 grid of mini-knobs
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          childAspectRatio: 1.0,
          children: [
            for (final p in params) _MiniKnob(label: p.$1, value: p.$2),
          ],
        ),
        const SizedBox(height: 12),
        // Open full editor button
        ElevatedButton.icon(
          icon: const Icon(Icons.open_in_new, size: 14),
          label: const Text('Open Full Editor'),
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentPurple.withAlpha(48),
            foregroundColor: FluxForgeTheme.accentPurple,
            padding: const EdgeInsets.symmetric(vertical: 10),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          onPressed: () => onAction?.call('plugin.open_editor'),
        ),
      ],
    );
  }
}

class _MiniKnob extends StatelessWidget {
  final String label;
  final double value;

  const _MiniKnob({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: FluxForgeTheme.accentPurple.withAlpha(120),
              width: 2,
            ),
          ),
          child: const Icon(Icons.adjust, size: 12, color: FluxForgeTheme.accentPurple),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Color(0xFFB5B6BC)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-INSPECTOR: SLOT STAGE
// ═══════════════════════════════════════════════════════════════════════════

class SlotStageInspector extends StatelessWidget {
  final String stageId;
  final void Function(String, dynamic)? onChanged;

  const SlotStageInspector({super.key, required this.stageId, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InspectorField.text(
          label: 'Stage ID',
          initial: stageId,
          readOnly: true,
        ),
        _InspectorField.text(
          label: 'Audio',
          initial: '(unbound)',
          onChanged: (v) => onChanged?.call('stage.audio', v),
        ),
        _InspectorField.slider(
          label: 'Volume',
          initial: 0.0,
          min: -24,
          max: 12,
          unit: 'dB',
          onChanged: (v) => onChanged?.call('stage.volume', v),
        ),
        _InspectorField.dropdown(
          label: 'Envelope',
          initial: 'Default',
          options: const ['Default', 'Fast', 'Slow', 'Custom'],
          onChanged: (v) => onChanged?.call('stage.envelope', v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-INSPECTOR: SLOT REEL
// ═══════════════════════════════════════════════════════════════════════════

class SlotReelInspector extends StatelessWidget {
  final int reelIndex;
  final void Function(String, dynamic)? onChanged;

  const SlotReelInspector({super.key, required this.reelIndex, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InspectorField.text(
          label: 'Reel',
          initial: 'Reel ${reelIndex + 1}',
          readOnly: true,
        ),
        _InspectorField.text(
          label: 'Bound Audio',
          initial: '(none)',
          onChanged: (v) => onChanged?.call('reel.audio', v),
        ),
        _InspectorField.dropdown(
          label: 'Repeat',
          initial: 'Loop',
          options: const ['One-shot', 'Loop', 'Ping-pong'],
          onChanged: (v) => onChanged?.call('reel.repeat', v),
        ),
        _InspectorField.slider(
          label: 'Spin Speed',
          initial: 1.0,
          min: 0.25,
          max: 4.0,
          unit: '×',
          onChanged: (v) => onChanged?.call('reel.speed', v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-INSPECTOR: PROJECT OVERVIEW (fallback)
// ═══════════════════════════════════════════════════════════════════════════

class ProjectOverviewInspector extends StatelessWidget {
  const ProjectOverviewInspector({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OverviewMetric(label: 'Tracks', value: '—', icon: Icons.audiotrack),
        const _OverviewMetric(label: 'Clips', value: '—', icon: Icons.album),
        const _OverviewMetric(label: 'Markers', value: '—', icon: Icons.flag),
        const _OverviewMetric(label: 'Plugins', value: '—', icon: Icons.extension),
        const _OverviewMetric(label: 'Length', value: '—', icon: Icons.access_time),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF8B8C92).withAlpha(20),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF8B8C92).withAlpha(48)),
          ),
          child: const Text(
            'Select a track, clip, marker, plugin or slot stage to see contextual properties here.',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFB5B6BC),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _OverviewMetric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF8B8C92)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFFB5B6BC)),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFE8E8EA),
              fontFamily: 'JetBrainsMono, monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FIELD HELPERS
// ═══════════════════════════════════════════════════════════════════════════

class _InspectorField extends StatelessWidget {
  final String label;
  final Widget child;

  const _InspectorField({required this.label, required this.child});

  static Widget text({
    required String label,
    required String initial,
    bool readOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    return _InspectorField(
      label: label,
      child: TextFormField(
        initialValue: initial,
        readOnly: readOnly,
        style: const TextStyle(fontSize: 12, color: Color(0xFFE8E8EA)),
        decoration: _decoration(),
        onChanged: onChanged,
      ),
    );
  }

  static Widget dropdown({
    required String label,
    required String initial,
    required List<String> options,
    ValueChanged<String?>? onChanged,
  }) {
    return _InspectorField(
      label: label,
      child: DropdownButtonFormField<String>(
        initialValue: initial,
        isDense: true,
        style: const TextStyle(fontSize: 12, color: Color(0xFFE8E8EA)),
        dropdownColor: FluxForgeTheme.bgVoid,
        decoration: _decoration(),
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  static Widget slider({
    required String label,
    required double initial,
    required double min,
    required double max,
    required String unit,
    ValueChanged<double>? onChanged,
  }) {
    return _SliderField(
      label: label,
      initial: initial,
      min: min,
      max: max,
      unit: unit,
      onChanged: onChanged,
    );
  }

  static Widget toggle({
    required String label,
    required bool initial,
    ValueChanged<bool>? onChanged,
  }) {
    return _ToggleField(
      label: label,
      initial: initial,
      onChanged: onChanged,
    );
  }

  static Widget color({
    required String label,
    required Color initial,
    ValueChanged<Color>? onChanged,
  }) {
    return _ColorField(
      label: label,
      initial: initial,
      onChanged: onChanged,
    );
  }

  static InputDecoration _decoration() => const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF1F2028))),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF1F2028))),
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: FluxForgeTheme.brandGold, width: 1)),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF8B8C92),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SliderField extends StatefulWidget {
  final String label;
  final double initial;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double>? onChanged;

  const _SliderField({
    required this.label,
    required this.initial,
    required this.min,
    required this.max,
    required this.unit,
    this.onChanged,
  });

  @override
  State<_SliderField> createState() => _SliderFieldState();
}

class _SliderFieldState extends State<_SliderField> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial.clamp(widget.min, widget.max);
  }

  @override
  Widget build(BuildContext context) {
    return _InspectorField(
      label: widget.label,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: FluxForgeTheme.brandGold,
                inactiveTrackColor: const Color(0xFF1F2028),
                thumbColor: FluxForgeTheme.brandGoldBright,
              ),
              child: Slider(
                value: _value,
                min: widget.min,
                max: widget.max,
                onChanged: (v) {
                  setState(() => _value = v);
                  widget.onChanged?.call(v);
                },
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${_value.toStringAsFixed(_value.abs() >= 100 ? 0 : 1)} ${widget.unit}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFE8E8EA),
                fontFamily: 'JetBrainsMono, monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleField extends StatefulWidget {
  final String label;
  final bool initial;
  final ValueChanged<bool>? onChanged;

  const _ToggleField({required this.label, required this.initial, this.onChanged});

  @override
  State<_ToggleField> createState() => _ToggleFieldState();
}

class _ToggleFieldState extends State<_ToggleField> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return _InspectorField(
      label: widget.label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Switch(
          value: _value,
          activeThumbColor: FluxForgeTheme.brandGold,
          onChanged: (v) {
            setState(() => _value = v);
            widget.onChanged?.call(v);
          },
        ),
      ),
    );
  }
}

class _ColorField extends StatefulWidget {
  final String label;
  final Color initial;
  final ValueChanged<Color>? onChanged;

  const _ColorField({required this.label, required this.initial, this.onChanged});

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late Color _value;
  static const _swatches = [
    FluxForgeTheme.brandGold,
    FluxForgeTheme.accentCyan,
    FluxForgeTheme.accentBlue,
    FluxForgeTheme.accentGreen,
    FluxForgeTheme.accentOrange,
    FluxForgeTheme.accentRed,
    FluxForgeTheme.accentPurple,
    FluxForgeTheme.accentPink,
  ];

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return _InspectorField(
      label: widget.label,
      child: Wrap(
        spacing: 4,
        children: [
          for (final s in _swatches)
            GestureDetector(
              onTap: () {
                setState(() => _value = s);
                widget.onChanged?.call(s);
              },
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: s,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: s == _value ? Colors.white : Colors.transparent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
