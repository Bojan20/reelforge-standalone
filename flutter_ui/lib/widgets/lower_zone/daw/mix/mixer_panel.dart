/// DAW Mixer Panel (P0.1 Extracted)
///
/// Full mixer console with LUFS metering header:
/// - Channel strips (audio, bus, aux, VCA, master)
/// - Volume faders & pan controls
/// - Mute/Solo/Arm buttons
/// - Send routing
/// - Input controls
/// - Real-time metering
///
/// Wrapper for UltimateMixer widget with MixerProvider integration.
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1099-1298 (~200 LOC)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/mixer_provider.dart';
import '../../../mixer/ultimate_mixer.dart' as ultimate;
import '../../../mixer/io_selector_popup.dart' show IoRoute, IoRouteType;
import '../../../meters/lufs_meter_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MIXER PANEL
// ═══════════════════════════════════════════════════════════════════════════

class MixerPanel extends StatelessWidget {
  const MixerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // UltimateMixer requires MixerProvider
    // Select channel/bus/aux/vca counts + master volume to limit rebuilds
    final MixerProvider mixerProvider;
    try {
      context.select<MixerProvider, (int, int, int, int, double)>(
        (m) => (m.channels.length, m.buses.length, m.auxes.length, m.vcas.length, m.master.volume),
      );
      mixerProvider = context.read<MixerProvider>();
    } catch (_) {
      return _buildNoProviderPanel();
    }

    // Convert MixerProvider channels to UltimateMixerChannel format
    // Helper: convert MixerProvider route tuples → IoRoute objects
    List<IoRoute> routesForChannel(String channelId) {
      return mixerProvider.getAvailableOutputRoutes(channelId).map((r) {
        final routeType = switch (r.type) {
          'master' => IoRouteType.master,
          'bus' => IoRouteType.bus,
          'aux' => IoRouteType.aux,
          _ => IoRouteType.bus,
        };
        return IoRoute(id: r.id, name: r.name, type: routeType);
      }).toList();
    }

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
        lufsShort: ch.lufsShort,
        lufsIntegrated: ch.lufsIntegrated,
        outputBus: ch.outputBus ?? 'master',
        availableOutputRoutes: routesForChannel(ch.id),
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
        panRight: bus.panRight,
        isStereo: bus.isStereo,
        muted: bus.muted,
        soloed: bus.soloed,
        peakL: bus.peakL,
        peakR: bus.peakR,
        rmsL: bus.rmsL,
        rmsR: bus.rmsR,
        lufsShort: bus.lufsShort,
        lufsIntegrated: bus.lufsIntegrated,
        outputBus: bus.outputBus ?? 'master',
        availableOutputRoutes: routesForChannel(bus.id),
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
        outputBus: aux.outputBus ?? 'master',
        availableOutputRoutes: routesForChannel(aux.id),
      );
    }).toList();

    // Convert VCAs
    final vcas = mixerProvider.vcas.map((vca) {
      return ultimate.UltimateMixerChannel(
        id: vca.id,
        name: vca.name,
        type: ultimate.ChannelType.vca,
        color: vca.color,
        volume: vca.level,
        muted: vca.muted,
        soloed: vca.soloed,
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
      lufsShort: mixerProvider.master.lufsShort,
      lufsIntegrated: mixerProvider.master.lufsIntegrated,
    );

    // Mixer with LUFS meter header
    return Column(
      children: [
        // LUFS Meter Header (master bus loudness)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A20),
            border: Border(
              bottom: BorderSide(color: Color(0xFF242430), width: 1),
            ),
          ),
          child: const Row(
            children: [
              Text(
                'MASTER LOUDNESS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF909090),
                  letterSpacing: 0.5,
                ),
              ),
              Spacer(),
              LufsBadge(fontSize: 10, showIcon: true),
            ],
          ),
        ),
        // Mixer console
        Expanded(
          child: ultimate.UltimateMixer(
            channels: channels,
            buses: buses,
            auxes: auxes,
            vcas: vcas,
            master: master,
            compact: true,
            showInserts: true,
            showSends: true,
            // === VOLUME / PAN / MUTE / SOLO / ARM ===
            onVolumeChange: (id, volume) {
              // Check if it's a VCA
              if (mixerProvider.vcas.any((v) => v.id == id)) {
                mixerProvider.setVcaLevelWithUndo(id, volume);
              } else if (id == mixerProvider.master.id) {
                mixerProvider.setMasterVolumeWithUndo(volume);
              } else {
                mixerProvider.setChannelVolumeWithUndo(id, volume);
              }
            },
            onPanChange: (id, pan) => mixerProvider.setChannelPan(id, pan),
            onPanChangeEnd: (id, pan) => mixerProvider.setChannelPanWithUndo(id, pan),
            onPanRightChange: (id, pan) => mixerProvider.setChannelPanRight(id, pan),
            onMuteToggle: (id) {
              if (mixerProvider.vcas.any((v) => v.id == id)) {
                mixerProvider.toggleVcaMute(id);
              } else {
                mixerProvider.toggleChannelMuteWithUndo(id);
              }
            },
            onSoloToggle: (id) => mixerProvider.toggleChannelSoloWithUndo(id),
            onArmToggle: (id) => mixerProvider.toggleChannelArm(id),
            // === SENDS ===
            onSendLevelChange: (channelId, sendIndex, level) {
              final ch = mixerProvider.channels.firstWhere(
                (c) => c.id == channelId,
                orElse: () => mixerProvider.channels.first,
              );
              if (sendIndex < ch.sends.length) {
                final auxId = ch.sends[sendIndex].auxId;
                mixerProvider.setAuxSendLevelWithUndo(channelId, auxId, level);
              }
            },
            onSendMuteToggle: (channelId, sendIndex, muted) {
              final ch = mixerProvider.channels.firstWhere(
                (c) => c.id == channelId,
                orElse: () => mixerProvider.channels.first,
              );
              if (sendIndex < ch.sends.length) {
                final auxId = ch.sends[sendIndex].auxId;
                mixerProvider.toggleAuxSendEnabled(channelId, auxId);
              }
            },
            onSendPreFaderToggle: (channelId, sendIndex, preFader) {
              final ch = mixerProvider.channels.firstWhere(
                (c) => c.id == channelId,
                orElse: () => mixerProvider.channels.first,
              );
              if (sendIndex < ch.sends.length) {
                final auxId = ch.sends[sendIndex].auxId;
                mixerProvider.toggleAuxSendPreFader(channelId, auxId);
              }
            },
            onSendDestChange: (channelId, sendIndex, newDestination) {
              if (newDestination != null) {
                mixerProvider.setAuxSendDestination(channelId, sendIndex, newDestination);
              }
            },
            // === ROUTING ===
            onOutputChange: (channelId, busId) {
              mixerProvider.setChannelOutput(channelId, busId);
            },
            // === INPUT SECTION ===
            onPhaseToggle: (channelId) {
              mixerProvider.togglePhaseInvert(channelId);
            },
            onGainChange: (channelId, gain) {
              mixerProvider.setInputGain(channelId, gain);
            },
            // === STEREO WIDTH ===
            onWidthChange: (channelId, width) {
              mixerProvider.setStereoWidth(channelId, width);
            },
            // === STRUCTURE ===
            onAddBus: () {
              mixerProvider.createBus(name: 'Bus ${mixerProvider.buses.length + 1}');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNoProviderPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber, size: 48, color: LowerZoneColors.warning),
            SizedBox(height: 12),
            Text(
              'MixerProvider not available',
              style: TextStyle(fontSize: 14, color: LowerZoneColors.textPrimary),
            ),
            SizedBox(height: 4),
            Text(
              'Add MixerProvider to widget tree',
              style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
