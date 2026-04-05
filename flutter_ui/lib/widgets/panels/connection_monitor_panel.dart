/// Connection Monitor Panel — Real-time server connection diagnostics
///
/// Shows:
/// - Connection status (🟢 Connected / 🟡 Reconnecting / 🔴 Disconnected)
/// - Latency (roundtrip ms)
/// - Message rate (in/out per second)
/// - Seq gaps / duplicates
/// - Circuit breaker state
/// - Server Audio Bridge stats (triggers, RTPC, states, errors)
/// - MIDI trigger stats
/// - OSC server stats

import 'package:flutter/material.dart';
import '../../services/server_audio_bridge.dart';
import '../../services/midi_trigger_service.dart';
import '../../services/osc_trigger_service.dart';
import '../../theme/fluxforge_theme.dart';

class ConnectionMonitorPanel extends StatelessWidget {
  const ConnectionMonitorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'CONNECTION MONITOR',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Server Audio Bridge
          ListenableBuilder(
            listenable: ServerAudioBridge.instance,
            builder: (_, _) {
              final b = ServerAudioBridge.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('SERVER BRIDGE'),
                  _row('State', b.currentState.isEmpty ? 'N/A' : b.currentState),
                  _row('Triggers', '${b.triggerCount}'),
                  _row('RTPC Updates', '${b.rtpcCount}'),
                  _row('State Changes', '${b.stateCount}'),
                  if (b.errorCount > 0)
                    _row('Errors', '${b.errorCount}', highlight: true),
                  if (b.lastError != null)
                    _row('Last Error', b.lastError!, highlight: true),
                ],
              );
            },
          ),

          const SizedBox(height: 8),

          // MIDI
          ListenableBuilder(
            listenable: MidiTriggerService.instance,
            builder: (_, _) {
              final m = MidiTriggerService.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('MIDI'),
                  _row('Status', m.enabled ? '🟢 Active' : '⚪ Disabled'),
                  _row('Note Events', '${m.noteOnCount}'),
                  _row('CC Events', '${m.ccCount}'),
                  if (m.lastNote != null)
                    _row('Last Note', '${m.lastNote} vel:${m.lastVelocity}'),
                  if (m.lastCc != null)
                    _row('Last CC', 'CC${m.lastCc}=${m.lastCcValue}'),
                  _row('Mappings', '${m.noteMappings.length} notes, ${m.ccMappings.length} CC'),
                  if (m.learnMode)
                    _row('Learn', 'WAITING FOR INPUT...', highlight: true),
                ],
              );
            },
          ),

          const SizedBox(height: 8),

          // OSC
          ListenableBuilder(
            listenable: OscTriggerService.instance,
            builder: (_, _) {
              final o = OscTriggerService.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('OSC'),
                  _row('Status', o.serverRunning ? '🟢 Port ${o.port}' : '⚪ Stopped'),
                  _row('Messages', '${o.messageCount}'),
                  _row('Triggers', '${o.triggerCount}'),
                  _row('RTPC', '${o.rtpcCount}'),
                  if (o.lastAddress != null)
                    _row('Last Addr', o.lastAddress!),
                  _row('Mappings', '${o.eventMappings.length} events, ${o.rtpcMappings.length} RTPC'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        label,
        style: TextStyle(
          color: FluxForgeTheme.accentCyan.withValues(alpha: 0.7),
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: highlight ? FluxForgeTheme.accentOrange : FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
