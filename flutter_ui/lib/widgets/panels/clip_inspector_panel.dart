/// Clip Inspector Panel
///
/// Professional DAW-style clip inspector with:
/// - Clip properties (name, color, position, duration)
/// - Gain/fade controls
/// - FX chain integration
/// - Time stretch controls
/// - Source file info
///
/// Design: Cubase/Logic Pro style inspector sidebar

import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';
import '../../theme/fluxforge_theme.dart';
import '../timeline/stretch_overlay.dart';

/// Professional clip inspector panel
class ClipInspectorPanel extends StatefulWidget {
  /// Selected clip (null if nothing selected)
  final TimelineClip? clip;

  /// Track containing the clip
  final TimelineTrack? track;

  /// Callback when clip is modified
  final ValueChanged<TimelineClip>? onClipChanged;

  /// Callback to open FX editor in modal
  final VoidCallback? onOpenFxEditor;

  /// Panel width
  final double width;

  const ClipInspectorPanel({
    super.key,
    this.clip,
    this.track,
    this.onClipChanged,
    this.onOpenFxEditor,
    this.width = 280,
  });

  @override
  State<ClipInspectorPanel> createState() => _ClipInspectorPanelState();
}

class _ClipInspectorPanelState extends State<ClipInspectorPanel> {
  bool _propertiesExpanded = true;
  bool _gainsExpanded = true;
  bool _fxExpanded = true;
  bool _stretchExpanded = false;
  bool _sourceExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      color: FluxForgeTheme.bgSurface,
      child: widget.clip == null
          ? _buildEmptyState()
          : _buildInspector(widget.clip!),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 48,
            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No Clip Selected',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a clip to inspect',
            style: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspector(TimelineClip clip) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        // Header with clip name and color
        _buildHeader(clip),
        const SizedBox(height: 8),

        // Properties section
        _buildSection(
          title: 'Properties',
          icon: Icons.info_outline,
          expanded: _propertiesExpanded,
          onToggle: () => setState(() => _propertiesExpanded = !_propertiesExpanded),
          child: _buildPropertiesSection(clip),
        ),

        // Gain & Fades section
        _buildSection(
          title: 'Gain & Fades',
          icon: Icons.tune,
          expanded: _gainsExpanded,
          onToggle: () => setState(() => _gainsExpanded = !_gainsExpanded),
          child: _buildGainsFadesSection(clip),
        ),

        // FX Chain section
        _buildSection(
          title: 'Clip FX',
          icon: Icons.auto_fix_high,
          expanded: _fxExpanded,
          onToggle: () => setState(() => _fxExpanded = !_fxExpanded),
          badge: clip.hasFx ? '${clip.fxChain.activeSlots.length}' : null,
          badgeColor: clip.hasFx ? FluxForgeTheme.accentBlue : null,
          child: _buildFxSection(clip),
        ),

        // Time Stretch section
        _buildSection(
          title: 'Time Stretch',
          icon: Icons.timer,
          expanded: _stretchExpanded,
          onToggle: () => setState(() => _stretchExpanded = !_stretchExpanded),
          child: _buildStretchSection(clip),
        ),

        // Source Info section
        _buildSection(
          title: 'Source',
          icon: Icons.audiotrack,
          expanded: _sourceExpanded,
          onToggle: () => setState(() => _sourceExpanded = !_sourceExpanded),
          child: _buildSourceSection(clip),
        ),
      ],
    );
  }

  Widget _buildHeader(TimelineClip clip) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          // Color indicator
          GestureDetector(
            onTap: () => _showColorPicker(clip),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: clip.color ?? const Color(0xFF3A6EA5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name (editable)
          Expanded(
            child: GestureDetector(
              onDoubleTap: () => _editClipName(clip),
              child: Text(
                clip.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Mute button
          IconButton(
            icon: Icon(
              clip.muted ? Icons.volume_off : Icons.volume_up,
              size: 18,
            ),
            color: clip.muted ? FluxForgeTheme.accentRed : FluxForgeTheme.textSecondary,
            onPressed: () {
              widget.onClipChanged?.call(clip.copyWith(muted: !clip.muted));
            },
            tooltip: clip.muted ? 'Unmute' : 'Mute',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
    String? badge,
    Color? badgeColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: FluxForgeTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textPrimary,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor ?? FluxForgeTheme.accentBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: FluxForgeTheme.textTertiary,
                  ),
                ],
              ),
            ),
          ),

          // Content
          if (expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: child,
            ),
        ],
      ),
    );
  }

  Widget _buildPropertiesSection(TimelineClip clip) {
    return Column(
      children: [
        _buildPropertyRow('Position', _formatTime(clip.startTime)),
        _buildPropertyRow('Duration', _formatTime(clip.duration)),
        _buildPropertyRow('End', _formatTime(clip.startTime + clip.duration)),
        if (widget.track != null)
          _buildPropertyRow('Track', widget.track!.name),
      ],
    );
  }

  Widget _buildGainsFadesSection(TimelineClip clip) {
    return Column(
      children: [
        // Gain slider
        _buildSliderRow(
          label: 'Gain',
          value: clip.gain,
          min: 0,
          max: 2,
          displayValue: _formatGain(clip.gain),
          onChanged: (value) {
            widget.onClipChanged?.call(clip.copyWith(gain: value));
          },
          onReset: () {
            widget.onClipChanged?.call(clip.copyWith(gain: 1.0));
          },
        ),

        const Divider(height: 16, color: FluxForgeTheme.borderSubtle),

        // Fade In
        _buildSliderRow(
          label: 'Fade In',
          value: clip.fadeIn,
          min: 0,
          max: clip.duration * 0.5,
          displayValue: _formatTime(clip.fadeIn),
          onChanged: (value) {
            widget.onClipChanged?.call(clip.copyWith(fadeIn: value));
          },
          onReset: () {
            widget.onClipChanged?.call(clip.copyWith(fadeIn: 0));
          },
        ),

        // Fade Out
        _buildSliderRow(
          label: 'Fade Out',
          value: clip.fadeOut,
          min: 0,
          max: clip.duration * 0.5,
          displayValue: _formatTime(clip.fadeOut),
          onChanged: (value) {
            widget.onClipChanged?.call(clip.copyWith(fadeOut: value));
          },
          onReset: () {
            widget.onClipChanged?.call(clip.copyWith(fadeOut: 0));
          },
        ),
      ],
    );
  }

  Widget _buildFxSection(TimelineClip clip) {
    final chain = clip.fxChain;

    if (chain.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'No effects applied',
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          _buildAddFxButton(clip),
        ],
      );
    }

    return Column(
      children: [
        // FX slots summary
        for (final slot in chain.slots.take(3))
          _buildFxSlotSummary(clip, slot),

        if (chain.slots.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+${chain.slots.length - 3} more...',
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ),

        const SizedBox(height: 8),

        // Open FX Editor button
        Row(
          children: [
            Expanded(child: _buildAddFxButton(clip)),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Edit', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: FluxForgeTheme.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: widget.onOpenFxEditor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFxSlotSummary(TimelineClip clip, ClipFxSlot slot) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: slot.bypass
            ? FluxForgeTheme.bgDeepest.withValues(alpha: 0.5)
            : FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            clipFxTypeIcon(slot.type),
            size: 14,
            color: slot.bypass
                ? FluxForgeTheme.textTertiary
                : clipFxTypeColor(slot.type),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              slot.displayName,
              style: TextStyle(
                fontSize: 11,
                color: slot.bypass
                    ? FluxForgeTheme.textTertiary
                    : FluxForgeTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Bypass toggle
          GestureDetector(
            onTap: () {
              final updatedChain = clip.fxChain.updateSlot(
                slot.id,
                (s) => s.copyWith(bypass: !s.bypass),
              );
              widget.onClipChanged?.call(clip.copyWith(fxChain: updatedChain));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: slot.bypass
                    ? FluxForgeTheme.accentOrange.withValues(alpha: 0.2)
                    : FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                slot.bypass ? 'OFF' : 'ON',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: slot.bypass
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.accentGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddFxButton(TimelineClip clip) {
    return PopupMenuButton<ClipFxType>(
      onSelected: (type) {
        final newSlot = ClipFxSlot.create(type);
        final updatedChain = clip.fxChain.addSlot(newSlot);
        widget.onClipChanged?.call(clip.copyWith(fxChain: updatedChain));
      },
      itemBuilder: (context) => [
        for (final type in [
          ClipFxType.gain,
          ClipFxType.compressor,
          ClipFxType.limiter,
          ClipFxType.gate,
          ClipFxType.saturation,
          ClipFxType.proEq,
        ])
          PopupMenuItem(
            value: type,
            child: Row(
              children: [
                Icon(clipFxTypeIcon(type), size: 16, color: clipFxTypeColor(type)),
                const SizedBox(width: 8),
                Text(clipFxTypeName(type), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 14, color: FluxForgeTheme.accentBlue),
            SizedBox(width: 4),
            Text(
              'Add FX',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: FluxForgeTheme.accentBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStretchSection(TimelineClip clip) {
    // Placeholder for time stretch controls
    return Column(
      children: [
        _buildPropertyRow('Algorithm', 'Élastique Pro'),
        _buildPropertyRow('Stretch Mode', 'Polyphonic'),

        const SizedBox(height: 8),

        // Stretch indicator
        // Check if any FX slot is a time stretch type
        if (clip.fxChain.slots.any((s) => s.type == ClipFxType.timeStretch))
          StretchIndicatorBadge(
            stretchRatio: 1.0, // Would come from actual stretch data
            onTap: () {
              // Open stretch editor
            },
          )
        else
          Text(
            'No time stretch applied',
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
      ],
    );
  }

  Widget _buildSourceSection(TimelineClip clip) {
    return Column(
      children: [
        _buildPropertyRow('Offset', _formatTime(clip.sourceOffset)),
        if (clip.sourceDuration != null)
          _buildPropertyRow('Source Length', _formatTime(clip.sourceDuration!)),
        _buildPropertyRow('Channels', clip.waveform != null ? 'Stereo' : 'Unknown'),
      ],
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    VoidCallback? onReset,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onDoubleTap: onReset,
                child: Text(
                  displayValue,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              activeColor: FluxForgeTheme.accentBlue,
              inactiveColor: FluxForgeTheme.borderSubtle,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(double seconds) {
    if (seconds < 1) {
      return '${(seconds * 1000).toStringAsFixed(0)}ms';
    } else if (seconds < 60) {
      return '${seconds.toStringAsFixed(2)}s';
    } else {
      final mins = (seconds / 60).floor();
      final secs = seconds % 60;
      return '$mins:${secs.toStringAsFixed(2).padLeft(5, '0')}';
    }
  }

  String _formatGain(double gain) {
    if (gain <= 0) return '-∞ dB';
    final db = 20 * _log10(gain);
    if (db <= -60) return '-∞ dB';
    return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
  }

  double _log10(double x) => x > 0 ? (logE(x) / logE(10)) : double.negativeInfinity;
  double logE(double x) => x > 0 ? _ln(x) : double.negativeInfinity;
  double _ln(double x) {
    // Simple natural log approximation
    if (x <= 0) return double.negativeInfinity;
    double result = 0;
    while (x > 2) {
      x /= 2.718281828;
      result++;
    }
    while (x < 0.5) {
      x *= 2.718281828;
      result--;
    }
    x -= 1;
    double term = x;
    double sum = x;
    for (int i = 2; i <= 10; i++) {
      term *= -x;
      sum += term / i;
    }
    return result + sum;
  }

  void _showColorPicker(TimelineClip clip) {
    final colors = [
      const Color(0xFF3A6EA5), // Blue
      const Color(0xFF2E7D32), // Green
      const Color(0xFFC62828), // Red
      const Color(0xFF7B1FA2), // Purple
      const Color(0xFFEF6C00), // Orange
      const Color(0xFF00838F), // Cyan
      const Color(0xFF5D4037), // Brown
      const Color(0xFF455A64), // Blue Grey
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clip Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in colors)
              GestureDetector(
                onTap: () {
                  widget.onClipChanged?.call(clip.copyWith(color: color));
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: clip.color == color
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _editClipName(TimelineClip clip) {
    final controller = TextEditingController(text: clip.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Clip'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Clip name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              widget.onClipChanged?.call(clip.copyWith(name: value.trim()));
            }
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                widget.onClipChanged?.call(clip.copyWith(name: value));
              }
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
