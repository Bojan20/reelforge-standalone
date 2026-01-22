/// Glass Mixer Widget
///
/// Theme-aware mixer using UltimateMixer with glass mode support.
/// UltimateMixer has built-in glass mode rendering.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/mixer_provider.dart';
import '../mixer/ultimate_mixer.dart' as ultimate;

/// Theme-aware mixer that uses UltimateMixer
/// UltimateMixer automatically handles Glass/Classic mode via ThemeModeProvider
class ThemeAwareMixer extends StatelessWidget {
  final bool compact;
  final VoidCallback? onAddBus;
  final VoidCallback? onAddAux;
  final VoidCallback? onAddVca;

  const ThemeAwareMixer({
    super.key,
    this.compact = false,
    this.onAddBus,
    this.onAddAux,
    this.onAddVca,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerProvider>(
      builder: (context, mixerProvider, _) {
        final channels = mixerProvider.channels.map((ch) {
          return ultimate.UltimateMixerChannel(
            id: ch.id,
            name: ch.name,
            type: ultimate.ChannelType.audio,
            color: ch.color,
            volume: ch.volume,
            pan: ch.pan,
            panRight: ch.panRight,
            isStereo: ch.isStereo,
            muted: ch.muted,
            soloed: ch.soloed,
            armed: ch.armed,
            peakL: ch.peakL,
            peakR: ch.peakR,
            rmsL: ch.rmsL,
            rmsR: ch.rmsR,
          );
        }).toList();

        final buses = mixerProvider.buses.map((bus) {
          return ultimate.UltimateMixerChannel(
            id: bus.id,
            name: bus.name,
            type: ultimate.ChannelType.bus,
            color: bus.color,
            volume: bus.volume,
            pan: bus.pan,
            muted: bus.muted,
            soloed: bus.soloed,
            peakL: bus.peakL,
            peakR: bus.peakR,
          );
        }).toList();

        final auxes = mixerProvider.auxes.map((aux) {
          return ultimate.UltimateMixerChannel(
            id: aux.id,
            name: aux.name,
            type: ultimate.ChannelType.aux,
            color: aux.color,
            volume: aux.volume,
            pan: aux.pan,
            muted: aux.muted,
            soloed: aux.soloed,
            peakL: aux.peakL,
            peakR: aux.peakR,
          );
        }).toList();

        final master = ultimate.UltimateMixerChannel(
          id: mixerProvider.master.id,
          name: 'Master',
          type: ultimate.ChannelType.master,
          color: const Color(0xFFFF9040),
          volume: mixerProvider.master.volume,
          peakL: mixerProvider.master.peakL,
          peakR: mixerProvider.master.peakR,
        );

        return ultimate.UltimateMixer(
          channels: channels,
          buses: buses,
          auxes: auxes,
          vcas: const [],
          master: master,
          compact: compact,
          showInserts: true,
          showSends: true,
          onVolumeChange: (id, volume) => mixerProvider.setChannelVolume(id, volume),
          onPanChange: (id, pan) => mixerProvider.setChannelPan(id, pan),
          onPanRightChange: (id, pan) => mixerProvider.setChannelPanRight(id, pan),
          onMuteToggle: (id) => mixerProvider.toggleChannelMute(id),
          onSoloToggle: (id) => mixerProvider.toggleChannelSolo(id),
          onArmToggle: (id) => mixerProvider.toggleChannelArm(id),
          onAddBus: onAddBus,
        );
      },
    );
  }
}

// Legacy alias - GlassMixer now just uses ThemeAwareMixer
// UltimateMixer handles glass mode internally
typedef GlassMixer = ThemeAwareMixer;
