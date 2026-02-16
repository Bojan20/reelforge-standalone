/// DAW Sidechain Panel (P0.5)
///
/// Sidechain routing panel for selected track's dynamics processors.
/// Provides key input source selection, filter controls, and monitoring.
///
/// Created: 2026-01-29
library;

import 'package:flutter/material.dart';
import '../../../dsp/sidechain_panel.dart' as dsp;

class SidechainPanel extends StatelessWidget {
  final int? selectedTrackId;

  /// Available sidechain sources (tracks, buses, externals)
  final List<SidechainSourceOption>? availableSources;

  /// Callback when sidechain settings change
  final VoidCallback? onSettingsChanged;

  const SidechainPanel({
    super.key,
    this.selectedTrackId,
    this.availableSources,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final trackId = selectedTrackId ?? 0;

    // Convert available sources to DSP panel format
    final sources = availableSources
            ?.map((s) => dsp.SidechainSourceInfo(
                  id: s.id,
                  name: s.name,
                  type: _convertSourceType(s.type),
                ))
            .toList() ??
        _buildDefaultSources(trackId);

    return dsp.SidechainPanel(
      processorId: trackId,
      availableSources: sources,
      onSettingsChanged: onSettingsChanged,
    );
  }

  /// Convert our source type to DSP panel source type
  dsp.SidechainSource _convertSourceType(SidechainSourceType type) {
    return switch (type) {
      SidechainSourceType.internal => dsp.SidechainSource.internal,
      SidechainSourceType.track => dsp.SidechainSource.track,
      SidechainSourceType.bus => dsp.SidechainSource.bus,
      SidechainSourceType.external => dsp.SidechainSource.external,
      SidechainSourceType.mid => dsp.SidechainSource.mid,
      SidechainSourceType.side => dsp.SidechainSource.side,
    };
  }

  /// Build default sources when none provided (common tracks/buses)
  List<dsp.SidechainSourceInfo> _buildDefaultSources(int currentTrackId) {
    final sources = <dsp.SidechainSourceInfo>[];

    // Add tracks (excluding current track)
    for (int i = 0; i < 8; i++) {
      if (i != currentTrackId) {
        sources.add(dsp.SidechainSourceInfo(
          id: i,
          name: 'Track ${i + 1}',
          type: dsp.SidechainSource.track,
        ));
      }
    }

    // Add buses
    final busNames = ['Master', 'Music', 'SFX', 'Voice', 'Ambience', 'Aux'];
    for (int i = 0; i < busNames.length; i++) {
      sources.add(dsp.SidechainSourceInfo(
        id: i + 100, // Offset to avoid conflict with track IDs
        name: busNames[i],
        type: dsp.SidechainSource.bus,
      ));
    }

    return sources;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SIDECHAIN SOURCE OPTION MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Source type for sidechain routing
enum SidechainSourceType {
  internal,
  track,
  bus,
  external,
  mid,
  side,
}

/// Option for sidechain source selection
class SidechainSourceOption {
  final int id;
  final String name;
  final SidechainSourceType type;

  const SidechainSourceOption({
    required this.id,
    required this.name,
    required this.type,
  });
}
