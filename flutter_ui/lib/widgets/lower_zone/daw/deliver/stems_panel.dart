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
import '../../../../src/rust/native_ffi.dart';
import '../../../../services/native_file_picker.dart';
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

  void _handleExport() async {
    final provider = context.read<StemRoutingProvider>();
    final config = provider.getExportConfiguration();

    if (config.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No stems configured. Assign tracks to stems first.'),
          backgroundColor: LowerZoneColors.warning,
        ),
      );
      return;
    }

    // Pick output directory
    final outputDir = await NativeFilePicker.pickDirectory(
      title: 'Select Stems Export Directory',
    );
    if (outputDir == null || !mounted) return;

    // Show progress
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting ${config.length} stem groups...'),
        backgroundColor: LowerZoneColors.dawAccent,
        duration: const Duration(seconds: 2),
      ),
    );

    // Export each stem group via FFI
    int totalExported = 0;
    for (final entry in config.entries) {
      final stemLabel = entry.key.label;
      final result = NativeFFI.instance.exportStems(
        outputDir,
        0,     // WAV format
        48000, // 48kHz
        0.0,   // start from beginning
        -1.0,  // -1 = entire project
        true,  // normalize
        true,  // include buses
        stemLabel,
      );
      if (result > 0) totalExported += result;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported $totalExported stems to $outputDir'),
        backgroundColor: LowerZoneColors.success,
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
