/// Clip FX Editor Widget
///
/// Editor for clip-based FX chains. Shows FX slots in a chain
/// with controls for each processor.

import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';
import '../../src/rust/engine_api.dart';
import '../../theme/reelforge_theme.dart';

/// Full clip FX editor panel
class ClipFxEditor extends StatefulWidget {
  final TimelineClip clip;
  final Function(TimelineClip) onClipChanged;

  const ClipFxEditor({
    super.key,
    required this.clip,
    required this.onClipChanged,
  });

  @override
  State<ClipFxEditor> createState() => _ClipFxEditorState();
}

class _ClipFxEditorState extends State<ClipFxEditor> {
  @override
  Widget build(BuildContext context) {
    final chain = widget.clip.fxChain;

    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(chain),
          const Divider(height: 1, color: ReelForgeTheme.border),

          // Chain gain controls
          _buildChainGains(chain),
          const Divider(height: 1, color: ReelForgeTheme.border),

          // FX slots
          Expanded(
            child: chain.isEmpty
                ? _buildEmptyState()
                : _buildSlotsList(chain),
          ),

          // Add FX button
          _buildAddFxButton(),
        ],
      ),
    );
  }

  Widget _buildHeader(ClipFxChain chain) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.auto_fix_high,
            size: 18,
            color: chain.hasActiveProcessing
                ? ReelForgeTheme.accent
                : ReelForgeTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Clip FX: ${widget.clip.name}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ReelForgeTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Bypass toggle
          _BypassButton(
            bypassed: chain.bypass,
            onChanged: (bypass) {
              engine.setClipFxChainBypass(widget.clip.id, bypass);
              widget.onClipChanged(
                widget.clip.copyWith(fxChain: chain.copyWith(bypass: bypass)),
              );
            },
          ),
          const SizedBox(width: 8),
          // Clear all
          IconButton(
            icon: const Icon(Icons.delete_sweep, size: 18),
            color: ReelForgeTheme.textMuted,
            tooltip: 'Clear all FX',
            onPressed: chain.isEmpty
                ? null
                : () {
                    engine.clearClipFx(widget.clip.id);
                    widget.onClipChanged(
                      widget.clip.copyWith(fxChain: const ClipFxChain()),
                    );
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildChainGains(ClipFxChain chain) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Input gain
          Expanded(
            child: _GainControl(
              label: 'Input',
              value: chain.inputGainDb,
              onChanged: (value) {
                engine.setClipFxInputGain(widget.clip.id, value);
                widget.onClipChanged(
                  widget.clip.copyWith(
                    fxChain: chain.copyWith(inputGainDb: value),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          // Output gain
          Expanded(
            child: _GainControl(
              label: 'Output',
              value: chain.outputGainDb,
              onChanged: (value) {
                engine.setClipFxOutputGain(widget.clip.id, value);
                widget.onClipChanged(
                  widget.clip.copyWith(
                    fxChain: chain.copyWith(outputGainDb: value),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 48,
            color: ReelForgeTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No FX in chain',
            style: TextStyle(
              fontSize: 13,
              color: ReelForgeTheme.textMuted.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Click + to add effects',
            style: TextStyle(
              fontSize: 11,
              color: ReelForgeTheme.textMuted.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotsList(ClipFxChain chain) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: chain.slots.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        final slot = chain.slots[oldIndex];
        engine.moveClipFx(widget.clip.id, slot.id, newIndex);
        widget.onClipChanged(
          widget.clip.copyWith(fxChain: chain.moveSlot(slot.id, newIndex)),
        );
      },
      itemBuilder: (context, index) {
        final slot = chain.slots[index];
        return _FxSlotCard(
          key: ValueKey(slot.id),
          slot: slot,
          clipId: widget.clip.id,
          onChanged: (updatedSlot) {
            widget.onClipChanged(
              widget.clip.copyWith(
                fxChain: chain.updateSlot(slot.id, (_) => updatedSlot),
              ),
            );
          },
          onRemove: () {
            engine.removeClipFx(widget.clip.id, slot.id);
            widget.onClipChanged(
              widget.clip.copyWith(fxChain: chain.removeSlot(slot.id)),
            );
          },
        );
      },
    );
  }

  Widget _buildAddFxButton() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: PopupMenuButton<ClipFxType>(
        onSelected: (type) {
          final newSlot = ClipFxSlot.create(type);
          final slotId = engine.addClipFx(widget.clip.id, type.index);
          if (slotId != null) {
            final slot = newSlot.copyWith(id: slotId);
            widget.onClipChanged(
              widget.clip.copyWith(fxChain: widget.clip.fxChain.addSlot(slot)),
            );
          }
        },
        itemBuilder: (context) => [
          _buildFxMenuItem(ClipFxType.gain, 'Dynamics'),
          _buildFxMenuItem(ClipFxType.compressor, 'Dynamics'),
          _buildFxMenuItem(ClipFxType.limiter, 'Dynamics'),
          _buildFxMenuItem(ClipFxType.gate, 'Dynamics'),
          const PopupMenuDivider(),
          _buildFxMenuItem(ClipFxType.saturation, 'Color'),
          const PopupMenuDivider(),
          _buildFxMenuItem(ClipFxType.proEq, 'EQ'),
          _buildFxMenuItem(ClipFxType.pultec, 'EQ'),
          _buildFxMenuItem(ClipFxType.api550, 'EQ'),
          _buildFxMenuItem(ClipFxType.neve1073, 'EQ'),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: ReelForgeTheme.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: ReelForgeTheme.accent.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: ReelForgeTheme.accent),
              SizedBox(width: 6),
              Text(
                'Add FX',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ReelForgeTheme.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<ClipFxType> _buildFxMenuItem(ClipFxType type, String category) {
    return PopupMenuItem(
      value: type,
      child: Row(
        children: [
          Icon(clipFxTypeIcon(type), size: 18, color: clipFxTypeColor(type)),
          const SizedBox(width: 8),
          Text(clipFxTypeName(type)),
        ],
      ),
    );
  }
}

/// Single FX slot card
class _FxSlotCard extends StatelessWidget {
  final ClipFxSlot slot;
  final String clipId;
  final Function(ClipFxSlot) onChanged;
  final VoidCallback onRemove;

  const _FxSlotCard({
    super.key,
    required this.slot,
    required this.clipId,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: slot.bypass
          ? ReelForgeTheme.surfaceDark.withOpacity(0.5)
          : ReelForgeTheme.surface,
      child: ExpansionTile(
        leading: Icon(
          clipFxTypeIcon(slot.type),
          color: slot.bypass
              ? ReelForgeTheme.textMuted
              : clipFxTypeColor(slot.type),
          size: 20,
        ),
        title: Text(
          slot.displayName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: slot.bypass
                ? ReelForgeTheme.textMuted
                : ReelForgeTheme.textPrimary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BypassButton(
              bypassed: slot.bypass,
              onChanged: (bypass) {
                engine.setClipFxBypass(clipId, slot.id, bypass);
                onChanged(slot.copyWith(bypass: bypass));
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: ReelForgeTheme.textMuted,
              onPressed: onRemove,
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildParamsEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildParamsEditor() {
    switch (slot.type) {
      case ClipFxType.gain:
        return _GainParamsEditor(slot: slot, clipId: clipId, onChanged: onChanged);
      case ClipFxType.compressor:
        return _CompressorParamsEditor(slot: slot, clipId: clipId, onChanged: onChanged);
      case ClipFxType.limiter:
        return _LimiterParamsEditor(slot: slot, clipId: clipId, onChanged: onChanged);
      case ClipFxType.gate:
        return _GateParamsEditor(slot: slot, clipId: clipId, onChanged: onChanged);
      case ClipFxType.saturation:
        return _SaturationParamsEditor(slot: slot, clipId: clipId, onChanged: onChanged);
      default:
        return _DefaultParamsEditor(slot: slot, clipId: clipId, onChanged: onChanged);
    }
  }
}

/// Gain parameters editor
class _GainParamsEditor extends StatelessWidget {
  final ClipFxSlot slot;
  final String clipId;
  final Function(ClipFxSlot) onChanged;

  const _GainParamsEditor({
    required this.slot,
    required this.clipId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final params = slot.gainParams ?? const GainFxParams();
    return Column(
      children: [
        _ParamSlider(
          label: 'Gain',
          value: params.db,
          min: -24,
          max: 24,
          suffix: 'dB',
          onChanged: (value) {
            engine.setClipFxGainParams(clipId, slot.id, value, params.pan);
            onChanged(slot.copyWith(gainParams: params.copyWith(db: value)));
          },
        ),
        _ParamSlider(
          label: 'Pan',
          value: params.pan,
          min: -1,
          max: 1,
          onChanged: (value) {
            engine.setClipFxGainParams(clipId, slot.id, params.db, value);
            onChanged(slot.copyWith(gainParams: params.copyWith(pan: value)));
          },
        ),
      ],
    );
  }
}

/// Compressor parameters editor
class _CompressorParamsEditor extends StatelessWidget {
  final ClipFxSlot slot;
  final String clipId;
  final Function(ClipFxSlot) onChanged;

  const _CompressorParamsEditor({
    required this.slot,
    required this.clipId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final params = slot.compressorParams ?? const CompressorFxParams();
    return Column(
      children: [
        _ParamSlider(
          label: 'Threshold',
          value: params.thresholdDb,
          min: -60,
          max: 0,
          suffix: 'dB',
          onChanged: (value) {
            final newParams = params.copyWith(thresholdDb: value);
            engine.setClipFxCompressorParams(
              clipId,
              slot.id,
              ratio: newParams.ratio,
              thresholdDb: newParams.thresholdDb,
              attackMs: newParams.attackMs,
              releaseMs: newParams.releaseMs,
            );
            onChanged(slot.copyWith(compressorParams: newParams));
          },
        ),
        _ParamSlider(
          label: 'Ratio',
          value: params.ratio,
          min: 1,
          max: 20,
          suffix: ':1',
          onChanged: (value) {
            final newParams = params.copyWith(ratio: value);
            engine.setClipFxCompressorParams(
              clipId,
              slot.id,
              ratio: newParams.ratio,
              thresholdDb: newParams.thresholdDb,
              attackMs: newParams.attackMs,
              releaseMs: newParams.releaseMs,
            );
            onChanged(slot.copyWith(compressorParams: newParams));
          },
        ),
        _ParamSlider(
          label: 'Attack',
          value: params.attackMs,
          min: 0.1,
          max: 100,
          suffix: 'ms',
          onChanged: (value) {
            final newParams = params.copyWith(attackMs: value);
            engine.setClipFxCompressorParams(
              clipId,
              slot.id,
              ratio: newParams.ratio,
              thresholdDb: newParams.thresholdDb,
              attackMs: newParams.attackMs,
              releaseMs: newParams.releaseMs,
            );
            onChanged(slot.copyWith(compressorParams: newParams));
          },
        ),
        _ParamSlider(
          label: 'Release',
          value: params.releaseMs,
          min: 10,
          max: 1000,
          suffix: 'ms',
          onChanged: (value) {
            final newParams = params.copyWith(releaseMs: value);
            engine.setClipFxCompressorParams(
              clipId,
              slot.id,
              ratio: newParams.ratio,
              thresholdDb: newParams.thresholdDb,
              attackMs: newParams.attackMs,
              releaseMs: newParams.releaseMs,
            );
            onChanged(slot.copyWith(compressorParams: newParams));
          },
        ),
      ],
    );
  }
}

/// Limiter parameters editor
class _LimiterParamsEditor extends StatelessWidget {
  final ClipFxSlot slot;
  final String clipId;
  final Function(ClipFxSlot) onChanged;

  const _LimiterParamsEditor({
    required this.slot,
    required this.clipId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final params = slot.limiterParams ?? const LimiterFxParams();
    return _ParamSlider(
      label: 'Ceiling',
      value: params.ceilingDb,
      min: -12,
      max: 0,
      suffix: 'dB',
      onChanged: (value) {
        engine.setClipFxLimiterParams(clipId, slot.id, value);
        onChanged(slot.copyWith(limiterParams: params.copyWith(ceilingDb: value)));
      },
    );
  }
}

/// Gate parameters editor
class _GateParamsEditor extends StatelessWidget {
  final ClipFxSlot slot;
  final String clipId;
  final Function(ClipFxSlot) onChanged;

  const _GateParamsEditor({
    required this.slot,
    required this.clipId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final params = slot.gateParams ?? const GateFxParams();
    return Column(
      children: [
        _ParamSlider(
          label: 'Threshold',
          value: params.thresholdDb,
          min: -80,
          max: 0,
          suffix: 'dB',
          onChanged: (value) {
            final newParams = params.copyWith(thresholdDb: value);
            engine.setClipFxGateParams(
              clipId,
              slot.id,
              thresholdDb: newParams.thresholdDb,
              attackMs: newParams.attackMs,
              releaseMs: newParams.releaseMs,
            );
            onChanged(slot.copyWith(gateParams: newParams));
          },
        ),
        _ParamSlider(
          label: 'Attack',
          value: params.attackMs,
          min: 0.1,
          max: 50,
          suffix: 'ms',
          onChanged: (value) {
            final newParams = params.copyWith(attackMs: value);
            engine.setClipFxGateParams(
              clipId,
              slot.id,
              thresholdDb: newParams.thresholdDb,
              attackMs: newParams.attackMs,
              releaseMs: newParams.releaseMs,
            );
            onChanged(slot.copyWith(gateParams: newParams));
          },
        ),
        _ParamSlider(
          label: 'Release',
          value: params.releaseMs,
          min: 5,
          max: 500,
          suffix: 'ms',
          onChanged: (value) {
            final newParams = params.copyWith(releaseMs: value);
            engine.setClipFxGateParams(
              clipId,
              slot.id,
              thresholdDb: newParams.thresholdDb,
              attackMs: newParams.attackMs,
              releaseMs: newParams.releaseMs,
            );
            onChanged(slot.copyWith(gateParams: newParams));
          },
        ),
      ],
    );
  }
}

/// Saturation parameters editor
class _SaturationParamsEditor extends StatelessWidget {
  final ClipFxSlot slot;
  final String clipId;
  final Function(ClipFxSlot) onChanged;

  const _SaturationParamsEditor({
    required this.slot,
    required this.clipId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final params = slot.saturationParams ?? const SaturationFxParams();
    return Column(
      children: [
        _ParamSlider(
          label: 'Drive',
          value: params.drive,
          min: 0,
          max: 1,
          onChanged: (value) {
            engine.setClipFxSaturationParams(
              clipId,
              slot.id,
              drive: value,
              mix: params.mix,
            );
            onChanged(slot.copyWith(saturationParams: params.copyWith(drive: value)));
          },
        ),
        _ParamSlider(
          label: 'Mix',
          value: params.mix,
          min: 0,
          max: 1,
          onChanged: (value) {
            engine.setClipFxSaturationParams(
              clipId,
              slot.id,
              drive: params.drive,
              mix: value,
            );
            onChanged(slot.copyWith(saturationParams: params.copyWith(mix: value)));
          },
        ),
      ],
    );
  }
}

/// Default parameters editor (wet/dry only)
class _DefaultParamsEditor extends StatelessWidget {
  final ClipFxSlot slot;
  final String clipId;
  final Function(ClipFxSlot) onChanged;

  const _DefaultParamsEditor({
    required this.slot,
    required this.clipId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _ParamSlider(
      label: 'Mix',
      value: slot.wetDry,
      min: 0,
      max: 1,
      onChanged: (value) {
        engine.setClipFxWetDry(clipId, slot.id, value);
        onChanged(slot.copyWith(wetDry: value));
      },
    );
  }
}

/// Bypass button
class _BypassButton extends StatelessWidget {
  final bool bypassed;
  final Function(bool) onChanged;

  const _BypassButton({
    required this.bypassed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!bypassed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bypassed
              ? ReelForgeTheme.warning.withOpacity(0.2)
              : ReelForgeTheme.success.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          bypassed ? 'OFF' : 'ON',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: bypassed ? ReelForgeTheme.warning : ReelForgeTheme.success,
          ),
        ),
      ),
    );
  }
}

/// Gain control for chain input/output
class _GainControl extends StatelessWidget {
  final String label;
  final double value;
  final Function(double) onChanged;

  const _GainControl({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: ReelForgeTheme.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              min: -24,
              max: 12,
              onChanged: onChanged,
              activeColor: ReelForgeTheme.accent,
              inactiveColor: ReelForgeTheme.border,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            '${value.toStringAsFixed(1)} dB',
            style: const TextStyle(
              fontSize: 10,
              color: ReelForgeTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Parameter slider
class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String? suffix;
  final Function(double) onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: ReelForgeTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                activeColor: ReelForgeTheme.accent,
                inactiveColor: ReelForgeTheme.border,
              ),
            ),
          ),
          SizedBox(
            width: 55,
            child: Text(
              '${value.toStringAsFixed(1)}${suffix != null ? ' $suffix' : ''}',
              style: const TextStyle(
                fontSize: 10,
                color: ReelForgeTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact FX indicator badge for clip widget
class ClipFxBadge extends StatelessWidget {
  final ClipFxChain fxChain;
  final VoidCallback? onTap;

  const ClipFxBadge({
    super.key,
    required this.fxChain,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (fxChain.isEmpty) return const SizedBox.shrink();

    final activeCount = fxChain.activeSlots.length;
    final totalCount = fxChain.length;
    final hasActive = fxChain.hasActiveProcessing;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: hasActive
              ? ReelForgeTheme.accent.withOpacity(0.8)
              : ReelForgeTheme.textMuted.withOpacity(0.5),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_fix_high,
              size: 10,
              color: Colors.white.withOpacity(0.9),
            ),
            const SizedBox(width: 2),
            Text(
              hasActive ? '$activeCount' : '$totalCount',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
