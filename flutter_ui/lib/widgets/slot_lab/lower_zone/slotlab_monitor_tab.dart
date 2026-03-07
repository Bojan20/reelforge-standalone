/// SlotLab MONITOR Tab — UCP Monitoring Zones
///
/// Timeline, Energy, Voice, Spectral, Fatigue,
/// AIL, Debug, Export

import 'package:flutter/material.dart';
import '../../../services/event_registry.dart';
import '../../lower_zone/lower_zone_types.dart';
import '../../middleware/event_profiler_panel.dart';
import '../../middleware/event_profiler_advanced.dart';
import '../../middleware/event_debugger_panel.dart';
import '../../middleware/resource_dashboard_panel.dart';
import '../../middleware/voice_pool_stats_panel.dart';
import '../ucp/event_timeline_zone.dart';
import '../ucp/energy_emotional_monitor.dart';
import '../ucp/voice_priority_monitor.dart';
import '../ucp/spectral_heatmap.dart';
import '../ucp/fatigue_stability_dashboard.dart';
import '../ucp/ail_panel_zone.dart';
import '../ucp/debug_monitor_zone.dart';
import '../ucp/export_zone.dart';

class SlotLabMonitorTabContent extends StatelessWidget {
  final SlotLabMonitorSubTab subTab;

  const SlotLabMonitorTabContent({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return switch (subTab) {
      SlotLabMonitorSubTab.timeline => const EventTimelineZone(),
      SlotLabMonitorSubTab.energy => const EnergyEmotionalMonitor(),
      SlotLabMonitorSubTab.voice => const VoicePriorityMonitor(),
      SlotLabMonitorSubTab.spectral => const SpectralHeatmap(),
      SlotLabMonitorSubTab.fatigue => const FatigueStabilityDashboard(),
      SlotLabMonitorSubTab.ail => const AilPanelZone(),
      SlotLabMonitorSubTab.debug => const DebugMonitorZone(),
      SlotLabMonitorSubTab.export => const ExportZone(),
      SlotLabMonitorSubTab.profiler => const EventProfilerPanel(),
      SlotLabMonitorSubTab.profilerAdv => const _ProfilerAdvancedWrapper(),
      SlotLabMonitorSubTab.evtDebug => const EventDebuggerPanel(),
      SlotLabMonitorSubTab.resource => const ResourceDashboardPanel(),
      SlotLabMonitorSubTab.voiceStats => const VoicePoolStatsPanel(),
    };
  }
}

/// Wraps EventProfilerAdvanced with real data from EventRegistry
class _ProfilerAdvancedWrapper extends StatelessWidget {
  const _ProfilerAdvancedWrapper();

  @override
  Widget build(BuildContext context) {
    final registry = EventRegistry.instance;
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final events = registry.allEvents;
        final entries = events.map((e) {
          final layerCount = e.layers.length;
          final durationUs = (e.duration * 1000000).round();
          return ProfilerEntry(
            eventId: e.id,
            latencyUs: durationUs,
            callCount: layerCount,
            avgLatencyUs: layerCount > 0 ? durationUs / layerCount : 0,
          );
        }).toList();
        return EventProfilerAdvanced(entries: entries);
      },
    );
  }
}
