/// SlotLab MONITOR Tab — UCP Monitoring Zones
///
/// Timeline, Energy, Voice, Spectral, Fatigue,
/// AIL, Debug, Export

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/subsystems/event_profiler_provider.dart';
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
import '../ucp/neuro_audio_monitor.dart';
import '../ucp/math_audio_bridge_panel.dart';
import '../ucp/rgai_compliance_panel.dart';
import '../ucp/debug_monitor_zone.dart';
import '../ucp/export_zone.dart';
import '../ucp/ucp_export_panel.dart';
import '../ucp/ab_test_panel.dart';

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
      SlotLabMonitorSubTab.neuro => const NeuroAudioMonitor(),
      SlotLabMonitorSubTab.mathBridge => const MathAudioBridgePanel(),
      SlotLabMonitorSubTab.rgai => const RgaiCompliancePanel(),
      SlotLabMonitorSubTab.debug => const DebugMonitorZone(),
      SlotLabMonitorSubTab.export => const ExportZone(),
      SlotLabMonitorSubTab.ucpExport => const UcpExportPanel(),
      SlotLabMonitorSubTab.abTest => const AbTestPanel(),
      SlotLabMonitorSubTab.profiler => const EventProfilerPanel(),
      SlotLabMonitorSubTab.profilerAdv => const _ProfilerAdvancedWrapper(),
      SlotLabMonitorSubTab.evtDebug => const EventDebuggerPanel(),
      SlotLabMonitorSubTab.resource => const ResourceDashboardPanel(),
      SlotLabMonitorSubTab.voiceStats => const VoicePoolStatsPanel(),
    };
  }
}

/// Wraps EventProfilerAdvanced with real data from EventProfilerProvider
class _ProfilerAdvancedWrapper extends StatelessWidget {
  const _ProfilerAdvancedWrapper();

  @override
  Widget build(BuildContext context) {
    final profiler = GetIt.instance<EventProfilerProvider>();
    return ListenableBuilder(
      listenable: profiler,
      builder: (context, _) {
        final events = profiler.getRecentEvents(count: 500);
        // Group by description and aggregate
        final grouped = <String, List<int>>{};
        for (final e in events) {
          grouped.putIfAbsent(e.description, () => []).add(e.latencyUs);
        }
        final entries = grouped.entries.map((g) {
          final latencies = g.value;
          final total = latencies.fold<int>(0, (s, v) => s + v);
          return ProfilerEntry(
            eventId: g.key,
            latencyUs: latencies.last,
            callCount: latencies.length,
            avgLatencyUs: latencies.isNotEmpty ? total / latencies.length : 0,
          );
        }).toList();
        return EventProfilerAdvanced(entries: entries);
      },
    );
  }
}
