/// DAW Clip Properties Panel (P0.1 Extracted)
///
/// Editable clip properties for selected timeline clip:
/// - Name, start time, duration (read-only)
/// - Gain control (-∞ to +6 dB)
/// - Fade in/out controls
/// - Reset button
///
/// Also includes Crossfade Editor wrapper (EDIT → Fades tab).
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1718-1850 + 4973-5293 (~452 LOC total)
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/timeline_playback_provider.dart' show TimelineClipData;
import '../../../../models/timeline_models.dart' show ClipChannelMode;
import '../../../editors/crossfade_editor.dart';
import '../../../../utils/audio_math.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CLIP PROPERTIES PANEL
// ═══════════════════════════════════════════════════════════════════════════

class ClipPropertiesPanel extends StatelessWidget {
  /// Selected clip data (from timeline)
  final TimelineClipData? selectedClip;

  /// Callbacks for clip edits
  final void Function(String clipId, double gain)? onClipGainChanged;
  final void Function(String clipId, double fadeIn)? onClipFadeInChanged;
  final void Function(String clipId, double fadeOut)? onClipFadeOutChanged;
  final void Function(String clipId, double snapOffset)? onClipSnapOffsetChanged;
  final void Function(String clipId, ClipChannelMode mode)? onClipChannelModeChanged;
  final void Function(String clipId, String notes)? onClipNotesChanged;
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const ClipPropertiesPanel({
    super.key,
    this.selectedClip,
    this.onClipGainChanged,
    this.onClipFadeInChanged,
    this.onClipFadeOutChanged,
    this.onClipSnapOffsetChanged,
    this.onClipChannelModeChanged,
    this.onClipNotesChanged,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final clip = selectedClip;

    // No clip selected — show placeholder
    if (clip == null) {
      return _buildNoClipSelected();
    }

    // Show editable controls for selected clip
    return EditableClipPanel(
      clipName: clip.name,
      startTime: clip.startTime,
      duration: clip.duration,
      gain: clip.trackVolume,
      fadeIn: clip.fadeIn,
      fadeOut: clip.fadeOut,
      snapOffset: clip.snapOffset,
      channelMode: clip.channelMode,
      notes: clip.notes,
      onGainChanged: (value) {
        onClipGainChanged?.call(clip.id, value);
        onAction?.call('clip_gain', {'clipId': clip.id, 'gain': value});
      },
      onFadeInChanged: (value) {
        onClipFadeInChanged?.call(clip.id, value);
        onAction?.call('clip_fade_in', {'clipId': clip.id, 'duration': value});
      },
      onFadeOutChanged: (value) {
        onClipFadeOutChanged?.call(clip.id, value);
        onAction?.call('clip_fade_out', {'clipId': clip.id, 'duration': value});
      },
      onSnapOffsetChanged: (value) {
        onClipSnapOffsetChanged?.call(clip.id, value);
        onAction?.call('clip_snap_offset', {'clipId': clip.id, 'snapOffset': value});
      },
      onChannelModeChanged: (mode) {
        onClipChannelModeChanged?.call(clip.id, mode);
        onAction?.call('clip_channel_mode', {'clipId': clip.id, 'mode': mode.index});
      },
      onNotesChanged: (text) {
        onClipNotesChanged?.call(clip.id, text);
        onAction?.call('clip_notes', {'clipId': clip.id, 'notes': text});
      },
    );
  }

  Widget _buildNoClipSelected() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.content_cut, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text(
                'CLIP PROPERTIES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app,
                    size: 48,
                    color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No Clip Selected',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: LowerZoneColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select a clip on the timeline to edit',
                    style: TextStyle(
                      fontSize: 10,
                      color: LowerZoneColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CROSSFADE EDITOR PANEL (EDIT → Fades tab)
// ═══════════════════════════════════════════════════════════════════════════

class FadesPanel extends StatelessWidget {
  const FadesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // Wrapper for CrossfadeEditor widget (already exists)
    return const CrossfadeEditor(
      initialConfig: CrossfadeConfig(
        fadeOut: FadeCurveConfig(preset: CrossfadePreset.equalPower),
        fadeIn: FadeCurveConfig(preset: CrossfadePreset.equalPower),
        duration: 0.5,
        linked: true,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EDITABLE CLIP PANEL (Internal Widget)
// ═══════════════════════════════════════════════════════════════════════════

class EditableClipPanel extends StatefulWidget {
  final String clipName;
  final double startTime;
  final double duration;
  final double gain; // 0-2, 1 = unity (0 dB)
  final double fadeIn; // seconds
  final double fadeOut; // seconds
  final double snapOffset; // seconds
  final ClipChannelMode channelMode;
  final String notes;
  final ValueChanged<double>? onGainChanged;
  final ValueChanged<double>? onFadeInChanged;
  final ValueChanged<double>? onFadeOutChanged;
  final ValueChanged<double>? onSnapOffsetChanged;
  final ValueChanged<ClipChannelMode>? onChannelModeChanged;
  final ValueChanged<String>? onNotesChanged;

  const EditableClipPanel({
    super.key,
    required this.clipName,
    required this.startTime,
    required this.duration,
    required this.gain,
    required this.fadeIn,
    required this.fadeOut,
    this.snapOffset = 0,
    this.channelMode = ClipChannelMode.normal,
    this.notes = '',
    this.onGainChanged,
    this.onFadeInChanged,
    this.onFadeOutChanged,
    this.onSnapOffsetChanged,
    this.onChannelModeChanged,
    this.onNotesChanged,
  });

  @override
  State<EditableClipPanel> createState() => _EditableClipPanelState();
}

class _EditableClipPanelState extends State<EditableClipPanel> {
  late double _gain;
  late double _fadeIn;
  late double _fadeOut;
  late double _snapOffset;
  late ClipChannelMode _channelMode;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _gain = widget.gain;
    _fadeIn = widget.fadeIn;
    _fadeOut = widget.fadeOut;
    _snapOffset = widget.snapOffset;
    _channelMode = widget.channelMode;
    _notesController = TextEditingController(text: widget.notes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(EditableClipPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gain != widget.gain) _gain = widget.gain;
    if (oldWidget.fadeIn != widget.fadeIn) _fadeIn = widget.fadeIn;
    if (oldWidget.fadeOut != widget.fadeOut) _fadeOut = widget.fadeOut;
    if (oldWidget.snapOffset != widget.snapOffset) _snapOffset = widget.snapOffset;
    if (oldWidget.channelMode != widget.channelMode) _channelMode = widget.channelMode;
    if (oldWidget.notes != widget.notes && widget.notes != _notesController.text) {
      _notesController.text = widget.notes;
    }
  }

  // ─── Utilities ─────────────────────────────────────────────────────────────

  String _gainToDb(double gain) => '${FaderCurve.linearToDbString(gain)} dB';

  String _formatTime(double seconds) {
    if (seconds < 0.001) return '0 ms';
    if (seconds < 1) return '${(seconds * 1000).round()} ms';
    return '${seconds.toStringAsFixed(2)} s';
  }

  String _formatTimecode(double seconds) {
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    final s = (seconds % 60).floor();
    final ms = ((seconds * 1000) % 1000).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Read-only info
                  _buildInfoRow('Name', widget.clipName, Icons.audio_file),
                  _buildInfoRow('Start', _formatTimecode(widget.startTime), Icons.start),
                  _buildInfoRow('Duration', _formatTime(widget.duration), Icons.timer),

                  const SizedBox(height: 12),
                  const Divider(color: LowerZoneColors.border, height: 1),
                  const SizedBox(height: 12),

                  // Editable: Gain
                  _buildGainControl(),
                  const SizedBox(height: 12),

                  // Editable: Fade In
                  _buildFadeControl(
                    label: 'Fade In',
                    value: _fadeIn,
                    maxValue: widget.duration / 2,
                    icon: Icons.trending_up,
                    onChanged: (v) {
                      setState(() => _fadeIn = v);
                      widget.onFadeInChanged?.call(v);
                    },
                  ),
                  const SizedBox(height: 8),

                  // Editable: Fade Out
                  _buildFadeControl(
                    label: 'Fade Out',
                    value: _fadeOut,
                    maxValue: widget.duration / 2,
                    icon: Icons.trending_down,
                    onChanged: (v) {
                      setState(() => _fadeOut = v);
                      widget.onFadeOutChanged?.call(v);
                    },
                  ),

                  const SizedBox(height: 12),
                  const Divider(color: LowerZoneColors.border, height: 1),
                  const SizedBox(height: 12),

                  // Snap Offset
                  _buildSnapOffsetControl(),
                  const SizedBox(height: 12),

                  // Channel Mode
                  _buildChannelModeSelector(),
                  const SizedBox(height: 12),

                  // Notes
                  _buildNotesField(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.content_cut, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        const Text(
          'CLIP PROPERTIES',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        // Reset button
        GestureDetector(
          onTap: () {
            setState(() {
              _gain = 1.0;
              _fadeIn = 0.0;
              _fadeOut = 0.0;
            });
            widget.onGainChanged?.call(1.0);
            widget.onFadeInChanged?.call(0.0);
            widget.onFadeOutChanged?.call(0.0);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: const Text(
              'RESET',
              style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: LowerZoneColors.textMuted),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGainControl() {
    final gainDb = _gainToDb(_gain);
    final isBoost = _gain > 1.0;
    final isCut = _gain < 1.0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text(
                'Gain',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
              ),
              const Spacer(),
              Text(
                gainDb,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isBoost
                      ? LowerZoneColors.warning
                      : isCut
                          ? const Color(0xFF40C8FF) // Cyan for cut
                          : LowerZoneColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: _gain,
            min: 0.0,
            max: 2.0,
            divisions: 200,
            activeColor: isBoost ? LowerZoneColors.warning : LowerZoneColors.dawAccent,
            onChanged: (v) {
              setState(() => _gain = v);
              widget.onGainChanged?.call(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFadeControl({
    required String label,
    required double value,
    required double maxValue,
    required IconData icon,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
              ),
              const Spacer(),
              Text(
                _formatTime(value),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: LowerZoneColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: 0.0,
            max: maxValue.clamp(0.01, 5.0),
            divisions: 100,
            activeColor: LowerZoneColors.dawAccent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSnapOffsetControl() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.adjust, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text('Snap Offset',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
              const Spacer(),
              Text(_formatTime(_snapOffset),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: LowerZoneColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Point within clip that aligns to grid (e.g. downbeat)',
            style: TextStyle(fontSize: 8, color: LowerZoneColors.textTertiary)),
          const SizedBox(height: 8),
          Slider(
            value: _snapOffset,
            min: 0.0,
            max: widget.duration.clamp(0.01, 60.0),
            divisions: 200,
            activeColor: LowerZoneColors.dawAccent,
            onChanged: (v) {
              setState(() => _snapOffset = v);
              widget.onSnapOffsetChanged?.call(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChannelModeSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.surround_sound, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text('Channel Mode',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: ClipChannelMode.values.map((mode) {
              final isActive = _channelMode == mode;
              return GestureDetector(
                onTap: () {
                  setState(() => _channelMode = mode);
                  widget.onChannelModeChanged?.call(mode);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
                        : LowerZoneColors.bgSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isActive
                          ? LowerZoneColors.dawAccent
                          : LowerZoneColors.border,
                    ),
                  ),
                  child: Text(
                    _channelModeLabel(mode),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive
                          ? LowerZoneColors.dawAccent
                          : LowerZoneColors.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _channelModeLabel(ClipChannelMode mode) {
    return switch (mode) {
      ClipChannelMode.normal => 'Normal',
      ClipChannelMode.monoSum => 'Mono',
      ClipChannelMode.leftOnly => 'Left',
      ClipChannelMode.rightOnly => 'Right',
      ClipChannelMode.midSide => 'M/S',
      ClipChannelMode.swapLR => 'Swap L/R',
    };
  }

  Widget _buildNotesField() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notes, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              const Text('Notes',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
              const Spacer(),
              if (_notesController.text.isNotEmpty)
                Text('${_notesController.text.length} chars',
                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontSize: 10, color: LowerZoneColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Add notes, annotations, or cues...',
              hintStyle: TextStyle(
                fontSize: 10,
                color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
              ),
              filled: true,
              fillColor: LowerZoneColors.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: LowerZoneColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: LowerZoneColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: LowerZoneColors.dawAccent),
              ),
              contentPadding: const EdgeInsets.all(8),
              isDense: true,
            ),
            onChanged: (text) => widget.onNotesChanged?.call(text),
          ),
        ],
      ),
    );
  }
}
