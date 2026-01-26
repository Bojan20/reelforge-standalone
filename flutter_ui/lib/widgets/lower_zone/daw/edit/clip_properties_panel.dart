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

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/timeline_playback_provider.dart' show TimelineClipData;
import '../../../editors/crossfade_editor.dart';

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
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const ClipPropertiesPanel({
    super.key,
    this.selectedClip,
    this.onClipGainChanged,
    this.onClipFadeInChanged,
    this.onClipFadeOutChanged,
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
      gain: clip.trackVolume, // Use track volume as clip gain
      fadeIn: 0.0, // TODO: Add fadeIn to TimelineClipData
      fadeOut: 0.0, // TODO: Add fadeOut to TimelineClipData
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
  final ValueChanged<double>? onGainChanged;
  final ValueChanged<double>? onFadeInChanged;
  final ValueChanged<double>? onFadeOutChanged;

  const EditableClipPanel({
    super.key,
    required this.clipName,
    required this.startTime,
    required this.duration,
    required this.gain,
    required this.fadeIn,
    required this.fadeOut,
    this.onGainChanged,
    this.onFadeInChanged,
    this.onFadeOutChanged,
  });

  @override
  State<EditableClipPanel> createState() => _EditableClipPanelState();
}

class _EditableClipPanelState extends State<EditableClipPanel> {
  late double _gain;
  late double _fadeIn;
  late double _fadeOut;

  @override
  void initState() {
    super.initState();
    _gain = widget.gain;
    _fadeIn = widget.fadeIn;
    _fadeOut = widget.fadeOut;
  }

  @override
  void didUpdateWidget(EditableClipPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gain != widget.gain) _gain = widget.gain;
    if (oldWidget.fadeIn != widget.fadeIn) _fadeIn = widget.fadeIn;
    if (oldWidget.fadeOut != widget.fadeOut) _fadeOut = widget.fadeOut;
  }

  // ─── Utilities ─────────────────────────────────────────────────────────────

  String _gainToDb(double gain) {
    if (gain <= 0) return '-∞ dB';
    final db = 20 * (math.log(gain) / math.ln10);
    return '${db.toStringAsFixed(1)} dB';
  }

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
}
