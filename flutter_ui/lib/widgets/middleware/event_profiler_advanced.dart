// event_profiler_advanced.dart — Advanced Event Profiling
import 'package:flutter/material.dart';

class EventProfilerAdvanced extends StatelessWidget {
  final List<ProfilerEntry> entries;
  const EventProfilerAdvanced({super.key, required this.entries});
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e = entries[i];
        return ListTile(
          title: Text(e.eventId, style: const TextStyle(color: Colors.white)),
          subtitle: Text('Latency: ${e.latencyUs}μs, Calls: ${e.callCount}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          trailing: Text('${e.avgLatencyUs.toStringAsFixed(1)}μs avg', style: const TextStyle(color: Color(0xFF40FF90), fontSize: 11)),
        );
      },
    );
  }
}

class ProfilerEntry {
  final String eventId;
  final int latencyUs;
  final int callCount;
  final double avgLatencyUs;
  const ProfilerEntry({required this.eventId, required this.latencyUs, required this.callCount, required this.avgLatencyUs});
}
