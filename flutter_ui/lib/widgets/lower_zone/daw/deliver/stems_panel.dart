/// DAW Stems Panel (P10.1.2 — Stem Routing Matrix)
///
/// Enhanced stems export panel with visual routing matrix.
/// Replaces simple list-based selection with full matrix view.
///
/// Created: 2026-02-02 (Updated from P0.1)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/stem_routing_provider.dart';
import '../../../../providers/mixer_provider.dart';
import '../../../routing/stem_routing_matrix.dart';
import '../../lower_zone_types.dart';

/// Enhanced stems panel with visual routing matrix.
class StemsPanel extends StatelessWidget {
  const StemsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // Provide StemRoutingProvider if not already available
    return ChangeNotifierProvider<StemRoutingProvider>(
      create: (_) => StemRoutingProvider(),
      child: const _StematrixContent(),
    );
  }
}

class _StematrixContent extends StatefulWidget {
  const _StematrixContent();

  @override
  State<_StematrixContent> createState() => _StematrixContentState();
}

class _StematrixContentState extends State<_StematrixContent> {
  @override
  void initState() {
    super.initState();
    // Sync tracks from MixerProvider on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTracksFromMixer();
    });
  }

  void _syncTracksFromMixer() {
    final mixer = context.read<MixerProvider>();
    final stemRouting = context.read<StemRoutingProvider>();

    // Register tracks and buses from mixer
    final tracks = <({String id, String name, bool isTrack})>[];

    for (final channel in mixer.channels) {
      tracks.add((
        id: channel.id,
        name: channel.name,
        isTrack: channel.type == ChannelType.audio ||
            channel.type == ChannelType.instrument,
      ));
    }

    // Also add buses
    for (final bus in mixer.buses) {
      tracks.add((
        id: bus.id,
        name: bus.name,
        isTrack: false,
      ));
    }

    if (tracks.isNotEmpty) {
      stemRouting.registerTracks(tracks);
    }
  }

  void _handleExport() {
    final provider = context.read<StemRoutingProvider>();
    final config = provider.getExportConfiguration();

    if (config.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No stems configured. Assign tracks to stems first.'),
          backgroundColor: LowerZoneColors.warning,
        ),
      );
      return;
    }

    // TODO: Integrate with existing export service
    // For now, show success message with configuration summary
    final stemSummary = config.entries
        .map((e) => '${e.key.label}: ${e.value.length} tracks')
        .join(', ');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ready to export: $stemSummary'),
        backgroundColor: LowerZoneColors.success,
        action: SnackBarAction(
          label: 'EXPORT',
          textColor: Colors.black,
          onPressed: () {
            // TODO: Call actual export service
            debugPrint('[StemsPanel] Export stems: $config');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StemRoutingMatrix(
      accentColor: LowerZoneColors.dawAccent,
      onExport: _handleExport,
    );
  }
}
