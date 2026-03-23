// SlotLab Voice Mixer — Per-layer mixer for SlotLab Lower Zone MIX tab
//
// Every audio layer assigned to a composite event has a permanent fader strip.
// Channels auto-create on audio assignment, auto-remove on layer deletion.
// Metering activates when the corresponding voice plays.
//
// Layout:
//   [Scrollable channels grouped by bus] | [Fixed Master strip]
//
// CRITICAL: SLOTLAB-ONLY — does NOT use MixerProvider (DAW mixer).
// Uses: SlotVoiceMixerProvider + MixerDSPProvider (bus-level only) + SharedMeterReader.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/slot_audio_events.dart';
import '../../providers/mixer_dsp_provider.dart';
import '../../providers/slot_lab/slot_voice_mixer_provider.dart';
import '../../services/shared_meter_reader.dart';
import '../../theme/fluxforge_theme.dart';
import '../../utils/audio_math.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BUS COLORS — consistent with slotlab_bus_mixer.dart
// ═══════════════════════════════════════════════════════════════════════════

Color _busColor(int busId) {
  return switch (busId) {
    SlotBusIds.sfx => const Color(0xFFFF9850),
    SlotBusIds.reels => const Color(0xFFFF9850),
    SlotBusIds.wins => const Color(0xFFFF9850),
    SlotBusIds.anticipation => const Color(0xFFFF9850),
    SlotBusIds.music => const Color(0xFF5AA8FF),
    SlotBusIds.voice => const Color(0xFF50FF98),
    SlotBusIds.ui => const Color(0xFF808088),
    SlotBusIds.master => const Color(0xFFF0F0F4),
    _ => const Color(0xFFFF9850),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class SlotVoiceMixer extends StatefulWidget {
  const SlotVoiceMixer({super.key});

  @override
  State<SlotVoiceMixer> createState() => _SlotVoiceMixerState();
}

class _SlotVoiceMixerState extends State<SlotVoiceMixer>
    with SingleTickerProviderStateMixin {
  // Drag-drop state
  int? _draggedIndex;
  int? _dropTargetIndex;

  @override
  void initState() {
    super.initState();
    // Start metering ticker on the provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SlotVoiceMixerProvider>().startMetering(this);
      }
    });
  }

  @override
  void dispose() {
    // Provider lifecycle is managed by GetIt, but stop our ticker
    try {
      context.read<SlotVoiceMixerProvider>().stopMetering();
    } catch (_) {
      // Provider may already be disposed
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SlotVoiceMixerProvider, MixerDSPProvider>(
      builder: (context, voiceMixer, busMixer, _) {
        final channelsByBus = voiceMixer.channelsByBus;
        final hasSolo = voiceMixer.hasSoloActive;

        return Container(
          color: FluxForgeTheme.bgDeepest,
          child: Column(
            children: [
              // Toolbar
              _buildToolbar(voiceMixer),
              // Mixer area: scrollable channels + fixed master
              Expanded(
                child: Row(
                  children: [
                    // Scrollable voice channels
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: 3, top: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildChannelStrips(
                            voiceMixer, channelsByBus, hasSolo,
                          ),
                        ),
                      ),
                    ),
                    // Fixed master separator + strip
                    _buildFixedMaster(busMixer),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Toolbar ─────────────────────────────────────────────────────────────

  Widget _buildToolbar(SlotVoiceMixerProvider mixer) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [FluxForgeTheme.bgMid, FluxForgeTheme.bgDeep],
        ),
        border: const Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            'VOICE MIXER',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: FluxForgeTheme.accentCyan,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 14, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 12),
          Text('Ch ', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary)),
          Text('${mixer.channelCount}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: FluxForgeTheme.textSecondary)),
          const SizedBox(width: 12),
          Container(width: 1, height: 14, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 12),
          Text('Live ', style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary)),
          Text('${mixer.playingCount}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
            color: mixer.playingCount > 0 ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary)),
          const Spacer(),
          // Search filter
          SizedBox(
            width: 140,
            height: 20,
            child: TextField(
              style: TextStyle(fontSize: 9, color: FluxForgeTheme.textSecondary, fontFamily: FluxForgeTheme.fontFamily),
              decoration: InputDecoration(
                hintText: 'Filter...',
                hintStyle: TextStyle(fontSize: 9, color: FluxForgeTheme.textDisabled),
                prefixIcon: Icon(Icons.search, size: 12, color: FluxForgeTheme.textDisabled),
                prefixIconConstraints: const BoxConstraints(minWidth: 24),
                filled: true,
                fillColor: FluxForgeTheme.bgDeepest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: FluxForgeTheme.accentBlue)),
              ),
              onChanged: mixer.setFilter,
            ),
          ),
          const SizedBox(width: 8),
          // Narrow/Regular toggle
          GestureDetector(
            onTap: mixer.toggleCompact,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                border: Border.all(color: FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                mixer.isCompact ? 'N' : 'R',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5,
                  color: FluxForgeTheme.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Channel Strips ──────────────────────────────────────────────────────

  List<Widget> _buildChannelStrips(
    SlotVoiceMixerProvider mixer,
    Map<int, List<SlotMixerChannel>> channelsByBus,
    bool hasSolo,
  ) {
    final widgets = <Widget>[];
    bool first = true;

    for (final busId in SlotVoiceMixerProvider.busDisplayOrder) {
      final channels = channelsByBus[busId];
      if (channels == null || channels.isEmpty) continue;

      // Bus separator (except before first group)
      if (!first) {
        final color = _busColor(busId);
        widgets.add(_BusSeparator(busName: busIdToName(busId), color: color));
      }
      first = false;

      // Channel strips with drag-drop reorder
      for (final ch in channels) {
        final globalIdx = mixer.channels.indexOf(ch);
        final isDragging = _draggedIndex == globalIdx;
        final isDropTarget = _dropTargetIndex == globalIdx;

        widgets.add(
          DragTarget<int>(
            onWillAcceptWithDetails: (details) {
              if (details.data == globalIdx) return false;
              setState(() => _dropTargetIndex = globalIdx);
              return true;
            },
            onLeave: (_) => setState(() => _dropTargetIndex = null),
            onAcceptWithDetails: (details) {
              mixer.reorderChannel(details.data, globalIdx);
              setState(() { _draggedIndex = null; _dropTargetIndex = null; });
            },
            builder: (context, candidateData, rejectedData) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDropTarget)
                    Container(
                      width: 3, height: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue,
                        borderRadius: BorderRadius.circular(1.5),
                        boxShadow: [BoxShadow(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5), blurRadius: 4)],
                      ),
                    ),
                  LongPressDraggable<int>(
                    data: globalIdx,
                    axis: Axis.horizontal,
                    delay: const Duration(milliseconds: 150),
                    onDragStarted: () => setState(() => _draggedIndex = globalIdx),
                    onDragEnd: (_) => setState(() { _draggedIndex = null; _dropTargetIndex = null; }),
                    onDraggableCanceled: (velocity, offset) => setState(() { _draggedIndex = null; _dropTargetIndex = null; }),
                    feedback: Material(
                      elevation: 8,
                      shadowColor: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                      child: Opacity(
                        opacity: 0.9,
                        child: SizedBox(
                          width: mixer.isCompact ? 56.0 : 68.0,
                          height: 300,
                          child: _VoiceStrip(
                            channel: ch,
                            hasSoloActive: hasSolo,
                            isSelected: false,
                            compact: mixer.isCompact,
                            provider: mixer,
                          ),
                        ),
                      ),
                    ),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 100),
                      opacity: isDragging ? 0.3 : 1.0,
                      child: _VoiceStrip(
                        key: ValueKey('vs_${ch.layerId}'),
                        channel: ch,
                        hasSoloActive: hasSolo,
                        isSelected: mixer.selectedChannelId == ch.layerId,
                        compact: mixer.isCompact,
                        provider: mixer,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    }

    return widgets;
  }

  // ─── Fixed Master ────────────────────────────────────────────────────────

  Widget _buildFixedMaster(MixerDSPProvider busMixer) {
    if (busMixer.getBus('master') == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Row(
        children: [
          // Orange separator line
          Container(
            width: 3,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  FluxForgeTheme.accentOrange,
                  FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          // Master strip
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 3),
            child: _MasterStrip(busMixer: busMixer),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUS SEPARATOR
// ═══════════════════════════════════════════════════════════════════════════

class _BusSeparator extends StatelessWidget {
  final String busName;
  final Color color;

  const _BusSeparator({required this.busName, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Gradient line (centered)
          Positioned(
            left: 3, width: 2, top: 0, bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.4), Colors.transparent],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          // Label (centered horizontally with overflow allowed)
          Positioned(
            top: 3,
            left: -16,
            right: -16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                ),
                child: Text(
                  busName.toUpperCase(),
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VOICE STRIP — single channel
// ═══════════════════════════════════════════════════════════════════════════

class _VoiceStrip extends StatefulWidget {
  final SlotMixerChannel channel;
  final bool hasSoloActive;
  final bool isSelected;
  final bool compact;
  final SlotVoiceMixerProvider provider;

  const _VoiceStrip({
    super.key,
    required this.channel,
    required this.hasSoloActive,
    this.isSelected = false,
    this.compact = false,
    required this.provider,
  });

  @override
  State<_VoiceStrip> createState() => _VoiceStripState();
}

class _VoiceStripState extends State<_VoiceStrip> {
  bool _faderDragging = false;
  DateTime _lastFaderTap = DateTime(0);

  SlotMixerChannel get ch => widget.channel;
  Color get busColor => _busColor(ch.busId);

  @override
  Widget build(BuildContext context) {
    final isDimmed = widget.hasSoloActive && !ch.soloed;
    final stripWidth = widget.compact ? 56.0 : 68.0;

    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 1 && HardwareKeyboard.instance.isMetaPressed) {
          // Ctrl/Cmd+Click = multi-select
          widget.provider.toggleMultiSelect(ch.layerId);
        }
      },
      child: GestureDetector(
      onTap: () {
        if (!HardwareKeyboard.instance.isMetaPressed) {
          widget.provider.selectChannel(ch.layerId);
        }
      },
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: isDimmed ? 0.3 : 1.0,
        child: Container(
          width: stripWidth,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            border: Border(
              left: BorderSide(
                color: (widget.isSelected || widget.provider.multiSelectedIds.contains(ch.layerId))
                    ? busColor.withValues(alpha: 0.6)
                    : FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
                width: (widget.isSelected || widget.provider.multiSelectedIds.contains(ch.layerId)) ? 2 : 1,
              ),
              right: BorderSide(color: FluxForgeTheme.bgVoid.withValues(alpha: 0.5)),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildInputSection(),
              _buildInserts(),
              _buildPanKnob(),
              _buildWidthControl(),
              Expanded(child: _buildFaderSection()),
              _buildDbReadout(),
              _buildButtons(),
              _buildOutputSelector(),
            ],
          ),
        ),
      ),
    ),
    );
  }

  // ─── Context Menu ────────────────────────────────────────────────────

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: FluxForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: FluxForgeTheme.borderMedium),
      ),
      items: [
        PopupMenuItem(value: 'audition', height: 28, child: Row(children: [
          Icon(Icons.play_arrow, size: 12, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 6),
          Text('Audition', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
        ])),
        PopupMenuItem(value: 'reset_pan', height: 28, child: Row(children: [
          Icon(Icons.center_focus_strong, size: 12, color: FluxForgeTheme.textTertiary),
          const SizedBox(width: 6),
          Text('Reset Pan', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
        ])),
        PopupMenuItem(value: 'reset_volume', height: 28, child: Row(children: [
          Icon(Icons.straighten, size: 12, color: FluxForgeTheme.textTertiary),
          const SizedBox(width: 6),
          Text('Reset Volume (0 dB)', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
        ])),
        const PopupMenuDivider(height: 4),
        PopupMenuItem(value: 'phase', height: 28, child: Row(children: [
          Text('Ø', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
            color: ch.phaseInvert ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary)),
          const SizedBox(width: 6),
          Text(ch.phaseInvert ? 'Phase: Inverted' : 'Invert Phase', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
        ])),
        const PopupMenuDivider(height: 4),
        PopupMenuItem(value: 'remove', height: 28, child: Row(children: [
          Icon(Icons.delete_outline, size: 12, color: FluxForgeTheme.accentRed),
          const SizedBox(width: 6),
          Text('Remove from Event', style: TextStyle(fontSize: 10, color: FluxForgeTheme.accentRed)),
        ])),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'audition':
          widget.provider.auditionChannel(ch.layerId);
        case 'reset_pan':
          widget.provider.setChannelPanFinal(ch.layerId, -1.0);
          widget.provider.setChannelPanRightFinal(ch.layerId, 1.0);
        case 'reset_volume':
          widget.provider.setChannelVolumeFinal(ch.layerId, 1.0);
        case 'phase':
          widget.provider.togglePhaseInvert(ch.layerId);
        case 'remove':
          widget.provider.removeChannel(ch.layerId);
      }
    });
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    // Alt+Click = audition (preview sound once). Plain click does nothing.
    // Prevents accidental playback from casual clicks.
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 1 && // Left click
            (HardwareKeyboard.instance.isAltPressed)) {
          widget.provider.auditionChannel(ch.layerId);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: ch.isPlaying
              ? FluxForgeTheme.bgMid.withValues(alpha: 0.95)
              : FluxForgeTheme.bgMid,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Color bar
            Container(height: 4, color: busColor),
            // Name row
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 3, 5, 1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ch.displayName,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: FluxForgeTheme.textPrimary,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (ch.isPlaying)
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Info row: stage + bus tag + loop
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 0, 5, 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ch.stageName,
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w500,
                        color: FluxForgeTheme.textTertiary,
                        fontFamily: FluxForgeTheme.monoFontFamily,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (ch.isLooping)
                    Container(
                      margin: const EdgeInsets.only(left: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgDeep,
                        border: Border.all(color: FluxForgeTheme.borderSubtle),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        'LOOP',
                        style: TextStyle(
                          fontSize: 6,
                          fontWeight: FontWeight.w700,
                          color: FluxForgeTheme.textDisabled,
                          letterSpacing: 0.3,
                          height: 1.5,
                        ),
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.only(left: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: busColor.withValues(alpha: 0.13),
                      border: Border.all(color: busColor.withValues(alpha: 0.27)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      busIdToName(ch.busId),
                      style: TextStyle(
                        fontSize: 6,
                        fontWeight: FontWeight.w700,
                        color: busColor,
                        letterSpacing: 0.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Input Section (Gain + Phase) ─────────────────────────────────────

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Phase Invert button (Ø)
          GestureDetector(
            onTap: () => widget.provider.togglePhaseInvert(ch.layerId),
            child: Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: ch.phaseInvert
                    ? FluxForgeTheme.accentOrange.withValues(alpha: 0.8)
                    : FluxForgeTheme.bgVoid.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: ch.phaseInvert ? FluxForgeTheme.accentOrange : FluxForgeTheme.borderSubtle,
                  width: 0.5,
                ),
              ),
              child: Center(
                child: Text('Ø', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold,
                  color: ch.phaseInvert ? Colors.white : FluxForgeTheme.textTertiary,
                )),
              ),
            ),
          ),
          // Gain display
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('GAIN', style: TextStyle(fontSize: 6, fontWeight: FontWeight.w600, color: FluxForgeTheme.textDisabled, letterSpacing: 0.5)),
              Text(
                '${ch.inputGain >= 0 ? '+' : ''}${ch.inputGain.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: FluxForgeTheme.monoFontFamily,
                  fontWeight: FontWeight.w600,
                  color: ch.inputGain.abs() > 0.1 ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Inserts ─────────────────────────────────────────────────────────────

  Widget _buildInserts() {
    final inserts = ch.dspInserts;
    // Show actual inserts + 1 empty slot (max 4 visible)
    final slotCount = (inserts.length + 1).clamp(1, 4);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 3),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          Text(
            'INSERTS',
            style: TextStyle(
              fontSize: 6.5,
              fontWeight: FontWeight.w700,
              color: FluxForgeTheme.textDisabled,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 1),
          for (int i = 0; i < slotCount; i++)
            _buildInsertSlot(i, i < inserts.length ? inserts[i] : null),
        ],
      ),
    );
  }

  Widget _buildInsertSlot(int index, ({String id, String name, bool bypass})? insert) {
    final hasInsert = insert != null;
    final isBypassed = insert?.bypass ?? false;

    return Container(
      height: 14,
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: hasInsert && !isBypassed
            ? FluxForgeTheme.accentCyan.withValues(alpha: 0.08)
            : FluxForgeTheme.bgDeep,
        border: Border.all(
          color: hasInsert && !isBypassed
              ? FluxForgeTheme.accentCyan.withValues(alpha: 0.2)
              : FluxForgeTheme.borderSubtle,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Text(
            '${index + 1}',
            style: TextStyle(fontSize: 6, color: FluxForgeTheme.textDisabled),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              hasInsert ? insert.name : '\u2014',
              style: TextStyle(
                fontSize: 7,
                color: hasInsert && !isBypassed
                    ? FluxForgeTheme.textTertiary
                    : FluxForgeTheme.textDisabled,
                decoration: isBypassed ? TextDecoration.lineThrough : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Pan — Pro Tools style (matches DAW UltimateMixer) ───────────────

  Widget _buildPanKnob() {
    if (ch.isStereo) {
      // Stereo: dual pan knobs L/R — same pattern as DAW _StereoPanKnob
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _SlotPanKnob(
              label: 'L',
              value: ch.pan,
              size: 22,
              onChanged: (v) => widget.provider.setChannelPan(ch.layerId, v),
              onChangeEnd: (v) => widget.provider.setChannelPanFinal(ch.layerId, v),
              defaultValue: -1.0,
            ),
            _SlotPanKnob(
              label: 'R',
              value: ch.panRight,
              size: 22,
              onChanged: (v) => widget.provider.setChannelPanRight(ch.layerId, v),
              onChangeEnd: (v) => widget.provider.setChannelPanRightFinal(ch.layerId, v),
              defaultValue: 1.0,
            ),
          ],
        ),
      );
    }

    // Mono: single pan knob
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: _SlotPanKnob(
        label: '',
        value: ch.pan,
        size: 26,
        onChanged: (v) => widget.provider.setChannelPan(ch.layerId, v),
        onChangeEnd: (v) => widget.provider.setChannelPanFinal(ch.layerId, v),
        defaultValue: 0.0,
      ),
    );
  }

  // ─── Stereo Width Control ──────────────────────────────────────────────

  Widget _buildWidthControl() {
    final width = ch.stereoWidth;
    final isMono = width <= 0.01;
    final isWide = width > 1.01;
    final color = isMono
        ? FluxForgeTheme.accentOrange
        : isWide ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary;
    final label = isMono ? 'M' : '${(width * 100).round()}%';

    return GestureDetector(
      onDoubleTap: () {
        widget.provider.setChannelWidth(ch.layerId, 1.0);
        widget.provider.setChannelWidthFinal(ch.layerId, 1.0);
      },
      onHorizontalDragUpdate: (details) {
        final delta = details.delta.dx * 0.02;
        widget.provider.setChannelWidth(ch.layerId, (ch.stereoWidth + delta).clamp(0.0, 2.0));
      },
      onHorizontalDragEnd: (_) {
        widget.provider.setChannelWidthFinal(ch.layerId, ch.stereoWidth);
      },
      child: Container(
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.borderSubtle, width: 0.5),
        ),
        child: Row(
          children: [
            Text('W', style: TextStyle(fontSize: 6, fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.7))),
            const SizedBox(width: 3),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  final center = maxW / 2;
                  final fillWidth = ((width - 1.0).abs() / 1.0 * center).clamp(0.0, center);
                  final fillLeft = width >= 1.0 ? center : center - fillWidth;
                  return Stack(
                    children: [
                      // Center line
                      Positioned(left: center - 0.5, top: 3, bottom: 3, width: 1,
                        child: Container(color: FluxForgeTheme.borderSubtle)),
                      // Fill
                      Positioned(left: fillLeft, top: 4, bottom: 4, width: fillWidth,
                        child: Container(decoration: BoxDecoration(color: color.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(1)))),
                      // Thumb
                      Positioned(
                        left: (center + (width - 1.0) * center).clamp(0.0, maxW - 3),
                        top: 2, bottom: 2, width: 3,
                        child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 6, fontWeight: FontWeight.w600,
              fontFamily: FluxForgeTheme.monoFontFamily, color: color)),
          ],
        ),
      ),
    );
  }

  // ─── Fader Section ──────────────────────────────────────────────────────

  Widget _buildFaderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Row(
        children: [
          // Stereo meter
          SizedBox(
            width: 12,
            child: _StereoMeter(
              peakL: ch.peakL,
              peakR: ch.peakR,
              peakHoldL: ch.peakHoldL,
              peakHoldR: ch.peakHoldR,
              busColor: busColor,
            ),
          ),
          const SizedBox(width: 3),
          // Fader
          Expanded(child: _buildFader()),
        ],
      ),
    );
  }

  // SlotLab volume range: 0.0-1.0 (0dB max). Use maxLinear:1.0 everywhere.
  static const double _maxLinear = 1.0;

  Widget _buildFader() {
    final faderPos = FaderCurve.linearToPosition(ch.volume, maxLinear: _maxLinear);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final capHeight = 28.0;
        final trackHeight = height - capHeight;
        final capTop = trackHeight * (1 - faderPos);

        return Listener(
          onPointerDown: (_) {},
          onPointerUp: (_) {
            if (!_faderDragging) {
              final now = DateTime.now();
              if (now.difference(_lastFaderTap).inMilliseconds < 300) {
                widget.provider.setChannelVolume(ch.layerId, 1.0);
                widget.provider.setChannelVolumeFinal(ch.layerId, 1.0);
                _lastFaderTap = DateTime(0);
              } else {
                _lastFaderTap = now;
              }
            }
            _faderDragging = false;
          },
          child: GestureDetector(
            onVerticalDragStart: (details) {
              _faderDragging = true;
              final clickPos = 1.0 - (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
              final newVol = FaderCurve.positionToLinear(clickPos, maxLinear: _maxLinear);
              widget.provider.setChannelVolume(ch.layerId, newVol);
            },
            onVerticalDragUpdate: (details) {
              final currentPos = FaderCurve.linearToPosition(ch.volume, maxLinear: _maxLinear);
              final delta = -details.delta.dy / trackHeight;
              final newPos = (currentPos + delta).clamp(0.0, 1.0);
              final newVol = FaderCurve.positionToLinear(newPos, maxLinear: _maxLinear);
              widget.provider.setChannelVolume(ch.layerId, newVol);
            },
            onVerticalDragEnd: (_) {
              widget.provider.setChannelVolumeFinal(ch.layerId, ch.volume);
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [FluxForgeTheme.bgDeep, FluxForgeTheme.bgVoid,
                           FluxForgeTheme.bgVoid, FluxForgeTheme.bgDeep],
                  stops: const [0, 0.15, 0.85, 1],
                ),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.4),
                ),
              ),
              child: Stack(
                children: [
                  // Rail groove
                  Positioned(
                    left: 0, right: 0, top: 6, bottom: 6,
                    child: Center(
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgVoid,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  // Unity (0dB) line — at top of travel for 0-1.0 range
                  Positioned(
                    left: 4, right: 4,
                    top: 0, // 0dB = max = top of fader
                    child: Container(
                      height: 1.5,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  // dB markers
                  ..._buildDbMarkers(trackHeight),
                  // Fader cap
                  Positioned(
                    left: 3, right: 3,
                    top: capTop,
                    height: capHeight,
                    child: _buildFaderCap(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildDbMarkers(double trackHeight) {
    // maxDb: 0.0 because SlotLab fader range is 0.0-1.0 linear (0dB max)
    const marks = [
      (0.0, '0'), (-6.0, '-6'),
      (-12.0, '-12'), (-24.0, '-24'), (-48.0, '-48'),
    ];
    final widgets = <Widget>[];

    for (final (db, label) in marks) {
      final pos = 1.0 - FaderCurve.dbToPosition(db, minDb: -60.0, maxDb: 0.0);
      final y = trackHeight * pos;

      // Tick line
      widgets.add(Positioned(
        left: 3, right: 3, top: y,
        child: Container(height: 0.5, color: Colors.white.withValues(alpha: 0.06)),
      ));
      // Label
      widgets.add(Positioned(
        right: 2, top: y - 3,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 6.5,
            fontFamily: FluxForgeTheme.monoFontFamily,
            color: db == 0
                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.6)
                : FluxForgeTheme.textDisabled.withValues(alpha: 0.35),
            fontWeight: db == 0 ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildFaderCap() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF606070), Color(0xFF4A4A58), Color(0xFF3A3A46),
            Color(0xFF2A2A36), Color(0xFF222230), Color(0xFF2A2A36),
            Color(0xFF3A3A46), Color(0xFF4A4A58), Color(0xFF555565),
          ],
          stops: [0, 0.08, 0.15, 0.35, 0.5, 0.65, 0.85, 0.92, 1],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF555555)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.05),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Grip lines (5 alternating light/dark)
          for (int i = 0; i < 5; i++)
            Container(
              width: double.infinity,
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: 5, vertical: i == 2 ? 1 : 0.5),
              color: i.isEven
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.25),
            ),
          // Colored center line
          Container(
            width: double.infinity,
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: busColor.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  // ─── dB Readout ─────────────────────────────────────────────────────────

  Widget _buildDbReadout() {
    final db = FaderCurve.linearToDbString(ch.volume);
    final isHot = ch.volume > 0.95;

    return Container(
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        border: Border.all(
          color: isHot
              ? FluxForgeTheme.accentRed.withValues(alpha: 0.5)
              : FluxForgeTheme.borderSubtle,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.center,
      child: Text(
        db,
        style: TextStyle(
          fontSize: 9,
          fontFamily: FluxForgeTheme.monoFontFamily,
          fontWeight: FontWeight.w600,
          color: isHot ? FluxForgeTheme.accentRed : FluxForgeTheme.textSecondary,
        ),
      ),
    );
  }

  // ─── M/S Buttons ────────────────────────────────────────────────────────

  Widget _buildButtons() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: _buildMSButton(
              'M', ch.muted, FluxForgeTheme.accentRed,
              () => widget.provider.toggleMute(ch.layerId),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _buildMSButton(
              'S', ch.soloed, FluxForgeTheme.accentYellow,
              () => widget.provider.toggleSolo(ch.layerId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMSButton(String label, bool active, Color activeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: active ? activeColor : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.borderSubtle,
          ),
          boxShadow: active
              ? [BoxShadow(color: activeColor.withValues(alpha: 0.35), blurRadius: 8)]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: active ? FluxForgeTheme.bgVoid : FluxForgeTheme.textDisabled,
          ),
        ),
      ),
    );
  }

  // ─── Output Selector (Bus routing dropdown) ─────────────────────────────

  Widget _buildOutputSelector() {
    return GestureDetector(
      onTap: () => _showBusDropdown(context),
      child: Container(
        height: 20,
        margin: const EdgeInsets.fromLTRB(3, 2, 3, 3),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          border: Border.all(color: FluxForgeTheme.borderSubtle),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 4, height: 4,
              decoration: BoxDecoration(color: busColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 3),
            Text(
              busIdToName(ch.busId),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: FluxForgeTheme.textTertiary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '\u25BE',
              style: TextStyle(fontSize: 6, color: FluxForgeTheme.textDisabled),
            ),
          ],
        ),
      ),
    );
  }

  void _showBusDropdown(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final stripWidth = renderBox.size.width;

    final buses = [
      (SlotBusIds.sfx, 'SFX'),
      (SlotBusIds.music, 'Music'),
      (SlotBusIds.voice, 'Voice'),
      (SlotBusIds.ui, 'UI'),
      (SlotBusIds.reels, 'Reels'),
      (SlotBusIds.wins, 'Wins'),
      (SlotBusIds.anticipation, 'Anticipation'),
    ];

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy - (buses.length * 32), // above strip
        position.dx + stripWidth, position.dy,
      ),
      color: FluxForgeTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: FluxForgeTheme.borderMedium),
      ),
      items: buses.map((bus) {
        final (id, name) = bus;
        final isActive = id == ch.busId;
        return PopupMenuItem<int>(
          value: id,
          height: 28,
          child: Row(
            children: [
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  color: _busColor(id),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null && value != ch.busId) {
        widget.provider.setChannelBus(ch.layerId, value);
      }
    });
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  static String _panString(double pan) {
    if (pan.abs() < 0.02) return 'C';
    final pct = (pan.abs() * 100).round();
    return pan < 0 ? 'L$pct' : 'R$pct';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAN KNOB — exact copy from DAW UltimateMixer _StereoPanKnob
// (private class can't be imported, so duplicated here verbatim)
// ═══════════════════════════════════════════════════════════════════════════

class _SlotPanKnob extends StatefulWidget {
  final String label; // 'L' or 'R' or '' for mono
  final double value;
  final double size;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double defaultValue;

  const _SlotPanKnob({
    required this.label,
    required this.value,
    this.size = 22,
    this.onChanged,
    this.onChangeEnd,
    this.defaultValue = 0.0,
  });

  @override
  State<_SlotPanKnob> createState() => _SlotPanKnobState();
}

class _SlotPanKnobState extends State<_SlotPanKnob> {
  double _localValue = 0;
  bool _isDragging = false;

  /// Format pan Pro Tools style: <100 for hard left, C for center, 100> for hard right
  String _formatPan(double v) {
    final percent = (v.abs() * 100).round();
    if (percent < 2) return 'C';
    return v < 0 ? '<$percent' : '$percent>';
  }

  double get _displayValue => _isDragging ? _localValue : widget.value;

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _localValue = widget.value;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.onChanged == null) return;
    final delta = -details.delta.dy * 0.007;
    _localValue = (_localValue + delta).clamp(-1.0, 1.0);
    setState(() {});
    widget.onChanged!(_localValue);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
    widget.onChangeEnd?.call(_localValue);
  }

  @override
  Widget build(BuildContext context) {
    final rotation = _displayValue * 135 * (math.pi / 180);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        if (widget.label.isNotEmpty)
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.accentCyan,
            ),
          ),
        if (widget.label.isNotEmpty) const SizedBox(height: 2),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _handleDragStart,
          onVerticalDragUpdate: _handleDragUpdate,
          onVerticalDragEnd: _handleDragEnd,
          onDoubleTap: () => widget.onChanged?.call(widget.defaultValue),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                colors: [
                  FluxForgeTheme.bgMid.withValues(alpha: 0.8),
                  FluxForgeTheme.bgDeep.withValues(alpha: 0.9),
                ],
              ),
              boxShadow: _isDragging
                  ? [BoxShadow(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.5), blurRadius: 8)]
                  : null,
            ),
            child: Stack(
              children: [
                // Pan arc indicator
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _SlotPanArcPainter(value: _displayValue),
                ),
                // Knob pointer
                Center(
                  child: Transform.rotate(
                    angle: rotation,
                    child: Container(
                      width: 2.5,
                      height: widget.size * 0.38,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentCyan,
                        borderRadius: BorderRadius.circular(1.5),
                        boxShadow: [
                          BoxShadow(
                            color: FluxForgeTheme.accentCyan.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        // Value readout
        Text(
          _formatPan(_displayValue),
          style: TextStyle(
            fontSize: 7,
            fontFamily: FluxForgeTheme.monoFontFamily,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Pan arc painter — bidirectional cyan arc (same as DAW _StereoPanKnobPainter)
class _SlotPanArcPainter extends CustomPainter {
  final double value;
  _SlotPanArcPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Value arc from center (top) — bidirectional cyan
    if (value.abs() > 0.01) {
      final valuePaint = Paint()
        ..color = FluxForgeTheme.accentCyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2; // Top (center position)
      final sweepAngle = value * (math.pi * 0.75); // 135° max

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle, false, valuePaint,
      );
    }

    // Small center marker at top (0 position)
    canvas.drawCircle(
      Offset(center.dx, center.dy - radius),
      1.5,
      Paint()..color = FluxForgeTheme.textTertiary,
    );
  }

  @override
  bool shouldRepaint(_SlotPanArcPainter old) => old.value != value;
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO METER
// ═══════════════════════════════════════════════════════════════════════════

class _StereoMeter extends StatelessWidget {
  final double peakL, peakR, peakHoldL, peakHoldR;
  final Color busColor;

  const _StereoMeter({
    required this.peakL, required this.peakR,
    required this.peakHoldL, required this.peakHoldR,
    required this.busColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildBar(peakL, peakHoldL)),
        const SizedBox(width: 1),
        Expanded(child: _buildBar(peakR, peakHoldR)),
      ],
    );
  }

  Widget _buildBar(double peak, double hold) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // Convert linear peak to log-scale for natural response
        final peakDb = peak > 0 ? 20 * math.log(peak) / math.ln10 : -60.0;
        final normPeak = ((peakDb + 60) / 60).clamp(0.0, 1.0);
        final peakH = normPeak * h;

        final holdDb = hold > 0 ? 20 * math.log(hold) / math.ln10 : -60.0;
        final normHold = ((holdDb + 60) / 60).clamp(0.0, 1.0);

        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgVoid,
            borderRadius: BorderRadius.circular(1),
            border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // FluxForge meter gradient: Cyan → Green → Yellow → Orange → Red
              if (peakH > 0)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: peakH,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: FluxForgeTheme.meterGradient,
                        stops: FluxForgeTheme.meterStops,
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              // Peak hold
              if (hold > 0.01)
                Positioned(
                  bottom: normHold * h - 1,
                  left: 0, right: 0,
                  child: Container(
                    height: 2,
                    color: hold > 0.9 ? FluxForgeTheme.clipIndicator : Colors.white,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MASTER STRIP — reads from MixerDSPProvider (bus-level), NOT DAW mixer
// ═══════════════════════════════════════════════════════════════════════════

class _MasterStrip extends StatefulWidget {
  final MixerDSPProvider busMixer;

  const _MasterStrip({required this.busMixer});

  @override
  State<_MasterStrip> createState() => _MasterStripState();
}

class _MasterStripState extends State<_MasterStrip> {
  // Master metering from SharedMeterReader
  double _peakL = 0, _peakR = 0;
  double _peakHoldL = 0, _peakHoldR = 0;
  int _holdTimeL = 0, _holdTimeR = 0;

  // Read fresh bus state from provider on every build (not stale widget param)
  MixerBus get bus => widget.busMixer.getBus('master') ??
      const MixerBus(id: 'master', name: 'Master', volume: 1.0);

  @override
  Widget build(BuildContext context) {
    // Read master meters + update peak hold
    final now = DateTime.now().millisecondsSinceEpoch;
    if (SharedMeterReader.instance.hasChanged) {
      final snap = SharedMeterReader.instance.readMeters();
      _peakL = snap.masterPeakL.clamp(0.0, 1.0);
      _peakR = snap.masterPeakR.clamp(0.0, 1.0);
      if (_peakL >= _peakHoldL) { _peakHoldL = _peakL; _holdTimeL = now; }
      if (_peakR >= _peakHoldR) { _peakHoldR = _peakR; _holdTimeR = now; }
    }
    // Peak hold decay
    if (now - _holdTimeL > 1500 && _peakHoldL > 0) {
      _peakHoldL = (_peakHoldL - 0.02).clamp(0.0, 1.0);
    }
    if (now - _holdTimeR > 1500 && _peakHoldR > 0) {
      _peakHoldR = (_peakHoldR - 0.02).clamp(0.0, 1.0);
    }

    return Container(
      width: 82,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(
          left: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(color: FluxForgeTheme.bgMid),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 4, color: const Color(0xFFF0F0F4)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(5, 3, 5, 1),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Master',
                          style: TextStyle(
                            fontSize: 9.5, fontWeight: FontWeight.w700,
                            color: FluxForgeTheme.textPrimary, height: 1.2,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentGreen,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(5, 0, 5, 3),
                  child: Text(
                    'STEREO OUT',
                    style: TextStyle(
                      fontSize: 7, fontWeight: FontWeight.w500,
                      color: FluxForgeTheme.textTertiary,
                      fontFamily: FluxForgeTheme.monoFontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Inserts
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 3),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: Column(
              children: [
                Text('INSERTS', style: TextStyle(
                  fontSize: 6.5, fontWeight: FontWeight.w700,
                  color: FluxForgeTheme.textDisabled, letterSpacing: 0.6,
                )),
                const SizedBox(height: 1),
                for (final name in ['Limiter', 'True Peak'])
                  Container(
                    height: 14, margin: const EdgeInsets.only(top: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentCyan.withValues(alpha: 0.08),
                      border: Border.all(
                        color: FluxForgeTheme.accentCyan.withValues(alpha: 0.2), width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(children: [
                      Text('${name == 'Limiter' ? '1' : '2'}',
                        style: TextStyle(fontSize: 6, color: FluxForgeTheme.textDisabled)),
                      const SizedBox(width: 2),
                      Text(name, style: TextStyle(fontSize: 7, color: FluxForgeTheme.textTertiary)),
                    ]),
                  ),
              ],
            ),
          ),
          // Pan (stereo dual-knob — always L=-1, R=+1 for master)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SlotPanKnob(
                  label: 'L',
                  value: bus.pan,
                  size: 22,
                  onChanged: (v) => widget.busMixer.setBusPan('master', v),
                  onChangeEnd: (_) {},
                  defaultValue: -1.0,
                ),
                _SlotPanKnob(
                  label: 'R',
                  value: 1.0, // Master R always hard right
                  size: 22,
                  onChanged: null, // Master R is fixed at +1.0 (stereo output)
                  onChangeEnd: null,
                  defaultValue: 1.0,
                ),
              ],
            ),
          ),
          // Fader + Meter
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: _StereoMeter(
                      peakL: _peakL, peakR: _peakR,
                      peakHoldL: _peakHoldL, peakHoldR: _peakHoldR,
                      busColor: const Color(0xFFF0F0F4),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(child: _buildMasterFader()),
                ],
              ),
            ),
          ),
          // dB
          Container(
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgVoid,
              border: Border.all(color: FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.center,
            child: Text(
              FaderCurve.linearToDbString(bus.volume),
              style: TextStyle(
                fontSize: 9, fontFamily: FluxForgeTheme.monoFontFamily,
                fontWeight: FontWeight.w600, color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          // M/S
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: Row(
              children: [
                Expanded(child: GestureDetector(
                  onTap: () => widget.busMixer.toggleMute('master'),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bus.muted ? FluxForgeTheme.accentRed : FluxForgeTheme.bgDeep,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: bus.muted ? FluxForgeTheme.accentRed : FluxForgeTheme.borderSubtle),
                    ),
                    alignment: Alignment.center,
                    child: Text('M', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: bus.muted ? FluxForgeTheme.bgVoid : FluxForgeTheme.textDisabled)),
                  ),
                )),
                const SizedBox(width: 2),
                Expanded(child: GestureDetector(
                  onTap: () => widget.busMixer.toggleSolo('master'),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bus.solo ? FluxForgeTheme.accentYellow : FluxForgeTheme.bgDeep,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: bus.solo ? FluxForgeTheme.accentYellow : FluxForgeTheme.borderSubtle),
                    ),
                    alignment: Alignment.center,
                    child: Text('S', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: bus.solo ? FluxForgeTheme.bgVoid : FluxForgeTheme.textDisabled)),
                  ),
                )),
              ],
            ),
          ),
          // Output
          Container(
            height: 20,
            margin: const EdgeInsets.fromLTRB(3, 2, 3, 3),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              border: Border.all(color: FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.center,
            child: Text('OUT 1-2', style: TextStyle(
              fontSize: 8, fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textTertiary, letterSpacing: 0.3)),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterFader() {
    final faderPos = FaderCurve.linearToPosition(bus.volume);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final capHeight = 28.0;
        final trackHeight = height - capHeight;
        final capTop = trackHeight * (1 - faderPos);

        return GestureDetector(
          onVerticalDragStart: (details) {
            final clickPos = 1.0 - (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
            widget.busMixer.setBusVolume('master', FaderCurve.positionToLinear(clickPos));
          },
          onVerticalDragUpdate: (details) {
            final currentPos = FaderCurve.linearToPosition(bus.volume);
            final delta = -details.delta.dy / trackHeight;
            final newPos = (currentPos + delta).clamp(0.0, 1.0);
            widget.busMixer.setBusVolume('master', FaderCurve.positionToLinear(newPos));
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [FluxForgeTheme.bgDeep, FluxForgeTheme.bgVoid,
                         FluxForgeTheme.bgVoid, FluxForgeTheme.bgDeep],
                stops: const [0, 0.15, 0.85, 1],
              ),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.4)),
            ),
            child: Stack(
              children: [
                Positioned(left: 0, right: 0, top: 6, bottom: 6,
                  child: Center(child: Container(width: 4,
                    decoration: BoxDecoration(color: FluxForgeTheme.bgVoid, borderRadius: BorderRadius.circular(2))))),
                Positioned(left: 4, right: 4, top: trackHeight * 0.15,
                  child: Container(height: 1.5,
                    decoration: BoxDecoration(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(1)))),
                Positioned(left: 3, right: 3, top: capTop, height: capHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Color(0xFF606070), Color(0xFF4A4A58), Color(0xFF3A3A46),
                                 Color(0xFF2A2A36), Color(0xFF222230), Color(0xFF2A2A36),
                                 Color(0xFF3A3A46), Color(0xFF4A4A58), Color(0xFF555565)],
                        stops: [0, 0.08, 0.15, 0.35, 0.5, 0.65, 0.85, 0.92, 1]),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF555555)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < 5; i++)
                          Container(width: double.infinity, height: 1,
                            margin: EdgeInsets.symmetric(horizontal: 5, vertical: i == 2 ? 1 : 0.5),
                            color: i.isEven ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.25)),
                        Container(width: double.infinity, height: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0F4).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(1))),
                      ],
                    ),
                  )),
              ],
            ),
          ),
        );
      },
    );
  }
}
