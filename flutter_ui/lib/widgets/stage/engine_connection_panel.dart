/// Engine Connection Panel — Live Mode for Universal Stage Ingest
///
/// Real-time connection to game engines:
/// - WebSocket/TCP configuration
/// - Connection state display
/// - Live event stream viewer
/// - Engine command controls (Play, Pause, Seek, etc.)
/// - Bidirectional communication
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/stage_models.dart';
import '../../providers/stage_provider.dart';

/// Engine Connection Panel widget
class EngineConnectionPanel extends StatelessWidget {
  const EngineConnectionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => EngineConnectionProvider(
        context.read<StageProvider>(),
      ),
      child: const _ConnectionContent(),
    );
  }
}

class _ConnectionContent extends StatelessWidget {
  const _ConnectionContent();

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<EngineConnectionProvider>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2a2a35)),
      ),
      child: Column(
        children: [
          // Header with connection status
          _ConnectionHeader(connection: connection),

          // Main content area
          Expanded(
            child: connection.isConnected
                ? _LiveModeView(connection: connection)
                : _ConnectionForm(connection: connection),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _ConnectionHeader extends StatelessWidget {
  final EngineConnectionProvider connection;

  const _ConnectionHeader({required this.connection});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2a2a35))),
      ),
      child: Row(
        children: [
          _StatusIndicator(state: connection.connectionState),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Engine Connection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 12,
                    color: _getStatusColor(),
                  ),
                ),
              ],
            ),
          ),
          if (connection.isConnected) ...[
            IconButton(
              onPressed: () => connection.disconnect(),
              icon: const Icon(Icons.power_settings_new),
              color: const Color(0xFFff4040),
              tooltip: 'Disconnect',
            ),
          ],
        ],
      ),
    );
  }

  String _getStatusText() => switch (connection.connectionState) {
        EngineConnectionState.disconnected => 'Not connected',
        EngineConnectionState.connecting => 'Connecting...',
        EngineConnectionState.connected => 'Connected to ${connection.url}',
        EngineConnectionState.disconnecting => 'Disconnecting...',
        EngineConnectionState.error => 'Connection error',
      };

  Color _getStatusColor() => switch (connection.connectionState) {
        EngineConnectionState.connected => const Color(0xFF40ff90),
        EngineConnectionState.connecting ||
        EngineConnectionState.disconnecting =>
          const Color(0xFFffff40),
        EngineConnectionState.error => const Color(0xFFff4040),
        _ => const Color(0xFF808090),
      };
}

class _StatusIndicator extends StatelessWidget {
  final EngineConnectionState state;

  const _StatusIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      EngineConnectionState.connected => const Color(0xFF40ff90),
      EngineConnectionState.connecting || EngineConnectionState.disconnecting =>
        const Color(0xFFffff40),
      EngineConnectionState.error => const Color(0xFFff4040),
      _ => const Color(0xFF606070),
    };

    final isAnimating =
        state == EngineConnectionState.connecting ||
        state == EngineConnectionState.disconnecting;

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: isAnimating
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONNECTION FORM
// ═══════════════════════════════════════════════════════════════════════════

class _ConnectionForm extends StatefulWidget {
  final EngineConnectionProvider connection;

  const _ConnectionForm({required this.connection});

  @override
  State<_ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<_ConnectionForm> {
  late TextEditingController _urlController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _adapterController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.connection.url);
    _hostController = TextEditingController(text: widget.connection.host);
    _portController = TextEditingController(text: widget.connection.port.toString());
    _adapterController = TextEditingController(text: widget.connection.adapterId);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _adapterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Protocol selector
          _buildSectionTitle('Protocol'),
          const SizedBox(height: 8),
          _ProtocolSelector(
            selected: widget.connection.protocol,
            onChanged: widget.connection.setProtocol,
          ),

          const SizedBox(height: 24),

          // Connection details
          if (widget.connection.protocol == ConnectionProtocol.webSocket)
            _buildWebSocketFields()
          else
            _buildTcpFields(),

          const SizedBox(height: 24),

          // Adapter selection
          _buildSectionTitle('Adapter'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _adapterController,
            label: 'Adapter ID',
            hint: 'generic',
            onChanged: widget.connection.setAdapterId,
          ),

          const SizedBox(height: 24),

          // Recent connections
          if (widget.connection.recentConnections.isNotEmpty) ...[
            _buildSectionTitle('Recent Connections'),
            const SizedBox(height: 8),
            ...widget.connection.recentConnections.take(5).map(
                  (config) => _RecentConnectionTile(
                    config: config,
                    onTap: () => widget.connection.connectWith(config),
                  ),
                ),
            const SizedBox(height: 24),
          ],

          // Connect button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _canConnect() ? _connect : null,
              icon: const Icon(Icons.power),
              label: const Text('Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4a9eff),
                disabledBackgroundColor: const Color(0xFF2a2a35),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }

  Widget _buildWebSocketFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('WebSocket URL'),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _urlController,
          label: 'URL',
          hint: 'ws://localhost:8080',
          onChanged: widget.connection.setUrl,
          prefixIcon: Icons.link,
        ),
      ],
    );
  }

  Widget _buildTcpFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('TCP Connection'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildTextField(
                controller: _hostController,
                label: 'Host',
                hint: 'localhost',
                onChanged: widget.connection.setHost,
                prefixIcon: Icons.computer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _portController,
                label: 'Port',
                hint: '8080',
                onChanged: (v) => widget.connection.setPort(int.tryParse(v) ?? 8080),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onChanged,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF808090)),
        hintStyle: const TextStyle(color: Color(0xFF505060)),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: const Color(0xFF606070), size: 20)
            : null,
        filled: true,
        fillColor: const Color(0xFF121216),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2a2a35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2a2a35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4a9eff)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  bool _canConnect() {
    if (widget.connection.protocol == ConnectionProtocol.webSocket) {
      return _urlController.text.isNotEmpty;
    } else {
      return _hostController.text.isNotEmpty && _portController.text.isNotEmpty;
    }
  }

  void _connect() {
    widget.connection.connect();
  }
}

class _ProtocolSelector extends StatelessWidget {
  final ConnectionProtocol selected;
  final ValueChanged<ConnectionProtocol> onChanged;

  const _ProtocolSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ConnectionProtocol.values.map((protocol) {
        final isSelected = protocol == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(protocol),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              margin: EdgeInsets.only(
                right: protocol == ConnectionProtocol.webSocket ? 8 : 0,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF4a9eff).withValues(alpha: 0.2)
                    : const Color(0xFF121216),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4a9eff)
                      : const Color(0xFF2a2a35),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    protocol == ConnectionProtocol.webSocket
                        ? Icons.web
                        : Icons.cable,
                    color: isSelected
                        ? const Color(0xFF4a9eff)
                        : const Color(0xFF606070),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    protocol.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? Colors.white : const Color(0xFF808090),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RecentConnectionTile extends StatelessWidget {
  final ConnectionConfig config;
  final VoidCallback onTap;

  const _RecentConnectionTile({
    required this.config,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF121216),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2a2a35)),
        ),
        child: Row(
          children: [
            Icon(
              config.protocol == ConnectionProtocol.webSocket
                  ? Icons.web
                  : Icons.cable,
              color: const Color(0xFF606070),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.displayUrl,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Adapter: ${config.adapterId}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF606070),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Color(0xFF606070),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LIVE MODE VIEW
// ═══════════════════════════════════════════════════════════════════════════

class _LiveModeView extends StatelessWidget {
  final EngineConnectionProvider connection;

  const _LiveModeView({required this.connection});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Engine controls
        _EngineControls(connection: connection),

        // Divider
        Container(height: 1, color: const Color(0xFF2a2a35)),

        // Live event stream
        Expanded(
          child: _EventStreamView(connection: connection),
        ),
      ],
    );
  }
}

class _EngineControls extends StatelessWidget {
  final EngineConnectionProvider connection;

  const _EngineControls({required this.connection});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
      ),
      child: Column(
        children: [
          // Transport controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlButton(
                icon: Icons.stop,
                tooltip: 'Stop',
                onPressed: () => connection.sendCommand(EngineCommand.stop()),
              ),
              const SizedBox(width: 8),
              _ControlButton(
                icon: Icons.play_arrow,
                tooltip: 'Play',
                isAccent: true,
                onPressed: () => connection.sendCommand(EngineCommand.resume()),
              ),
              const SizedBox(width: 8),
              _ControlButton(
                icon: Icons.pause,
                tooltip: 'Pause',
                onPressed: () => connection.sendCommand(EngineCommand.pause()),
              ),
              const SizedBox(width: 24),
              // Recording button
              _RecordButton(connection: connection),
              const SizedBox(width: 8),
              _ControlButton(
                icon: Icons.skip_previous,
                tooltip: 'Previous Spin',
                onPressed: () => connection.sendCommand(EngineCommand.seek(0)),
              ),
              const SizedBox(width: 8),
              _ControlButton(
                icon: Icons.skip_next,
                tooltip: 'Next Spin',
                onPressed: () => connection.sendCommand(
                  EngineCommand(
                    type: EngineCommandType.custom,
                    params: {'action': 'next_spin'},
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Timing profile selector
          Row(
            children: [
              const Text(
                'Timing:',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF808090),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: TimingProfile.values.map((profile) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TimingChip(
                          profile: profile,
                          isSelected: connection.timingProfile == profile,
                          onTap: () => connection.sendCommand(
                            EngineCommand.setTimingProfile(profile),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Recording button with visual feedback
class _RecordButton extends StatelessWidget {
  final EngineConnectionProvider connection;

  const _RecordButton({required this.connection});

  @override
  Widget build(BuildContext context) {
    final isRecording = connection.isRecording;

    return Tooltip(
      message: isRecording ? 'Stop Recording' : 'Start Recording',
      child: Material(
        color: isRecording
            ? const Color(0xFFff4040)
            : const Color(0xFF2a2a35),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            if (isRecording) {
              final events = connection.stopRecording();
              _showRecordingDialog(context, events.length);
            } else {
              connection.startRecording();
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(
              isRecording ? Icons.stop : Icons.fiber_manual_record,
              color: isRecording ? Colors.white : const Color(0xFFff4040),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  void _showRecordingDialog(BuildContext context, int eventCount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF40ff90), size: 24),
            const SizedBox(width: 12),
            const Text(
              'Recording Saved',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Captured $eventCount stage events.',
              style: const TextStyle(color: Color(0xFF808090)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF4a9eff), size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Export to use for offline preview or share with team.',
                      style: TextStyle(color: Color(0xFF606070), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Discard', style: TextStyle(color: Color(0xFF808090))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final json = connection.exportRecordingJson();
              Navigator.pop(ctx);
              _copyToClipboard(context, json);
            },
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text('Copy JSON'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a9eff),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String json) {
    // Copy to clipboard would require services package
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Exported ${json.length} bytes'),
          ],
        ),
        backgroundColor: const Color(0xFF40ff90).withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isAccent;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isAccent
            ? const Color(0xFF4a9eff)
            : const Color(0xFF2a2a35),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: isAccent ? Colors.white : const Color(0xFF808090),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimingChip extends StatelessWidget {
  final TimingProfile profile;
  final bool isSelected;
  final VoidCallback onTap;

  const _TimingChip({
    required this.profile,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4a9eff).withValues(alpha: 0.2)
              : const Color(0xFF2a2a35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4a9eff)
                : const Color(0xFF2a2a35),
          ),
        ),
        child: Text(
          profile.displayName,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? const Color(0xFF4a9eff) : const Color(0xFF808090),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT STREAM VIEW
// ═══════════════════════════════════════════════════════════════════════════

class _EventStreamView extends StatelessWidget {
  final EngineConnectionProvider connection;

  const _EventStreamView({required this.connection});

  @override
  Widget build(BuildContext context) {
    final events = connection.liveEvents;

    return Column(
      children: [
        // Stream header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2a2a35))),
          ),
          child: Row(
            children: [
              const Icon(Icons.timeline, color: Color(0xFF4a9eff), size: 16),
              const SizedBox(width: 8),
              Text(
                'Live Events (${events.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: connection.clearEvents,
                icon: const Icon(Icons.clear_all, size: 18),
                color: const Color(0xFF606070),
                tooltip: 'Clear Events',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),

        // Event list
        Expanded(
          child: events.isEmpty
              ? _buildEmptyState()
              : _EventList(events: events),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.radio_button_unchecked,
            color: Color(0xFF606070),
            size: 48,
          ),
          SizedBox(height: 16),
          Text(
            'Waiting for events...',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF606070),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start a spin in the game engine',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF505060),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  final List<StageEvent> events;

  const _EventList({required this.events});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: events.length,
      itemBuilder: (context, index) {
        // Show newest first
        final event = events[events.length - 1 - index];
        return _EventTile(event: event, index: events.length - index);
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  final StageEvent event;
  final int index;

  const _EventTile({required this.event, required this.index});

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor(event.stage.category);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Index badge
          Container(
            width: 32,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF2a2a35),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '#$index',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF606070),
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Category indicator
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: categoryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),

          // Event details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      event.stage.typeName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.stage.category.displayName,
                        style: TextStyle(
                          fontSize: 9,
                          color: categoryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _getEventDescription(event),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF808090),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Timestamp
          Text(
            '${event.timestampMs.toStringAsFixed(0)}ms',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF606070),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(StageCategory category) => switch (category) {
        StageCategory.spinLifecycle => const Color(0xFF4a9eff),
        StageCategory.anticipation => const Color(0xFFff9040),
        StageCategory.winLifecycle => const Color(0xFF40ff90),
        StageCategory.feature => const Color(0xFFff40ff),
        StageCategory.cascade => const Color(0xFF40c8ff),
        StageCategory.bonus => const Color(0xFFffff40),
        StageCategory.gamble => const Color(0xFFff4040),
        StageCategory.jackpot => const Color(0xFFffd700),
        StageCategory.ui => const Color(0xFF808090),
        StageCategory.special => const Color(0xFFc040ff),
      };

  String _getEventDescription(StageEvent event) {
    final stage = event.stage;
    return switch (stage) {
      ReelStop(reelIndex: final idx, symbols: final sym) =>
        'Reel $idx stopped: ${sym.take(3).join(", ")}${sym.length > 3 ? "..." : ""}',
      ReelSpinning(reelIndex: final idx) => 'Reel $idx spinning',
      WinPresent(winAmount: final amt, lineCount: final lines) =>
        'Win: ${amt.toStringAsFixed(2)} on $lines lines',
      BigWinTierStage(tier: final t, amount: final amt) =>
        '${t.displayName}: ${amt.toStringAsFixed(2)}',
      FeatureEnter(featureType: final ft, totalSteps: final steps) =>
        '${ft.displayName} triggered${steps != null ? " ($steps spins)" : ""}',
      FeatureStep(stepIndex: final idx, stepsRemaining: final rem) =>
        'Step ${idx + 1}${rem != null ? " ($rem remaining)" : ""}',
      CascadeStep(stepIndex: final idx, multiplier: final mult) =>
        'Cascade ${idx + 1} (${mult}x)',
      JackpotTrigger(tier: final t) => '${t.displayName} jackpot triggered!',
      JackpotPresent(tier: final t, amount: final amt) =>
        '${t.displayName}: ${amt.toStringAsFixed(2)}',
      AnticipationOn(reelIndex: final idx, reason: final r) =>
        'Reel $idx${r != null ? " ($r)" : ""}',
      GambleResultStage(result: final r, newAmount: final amt) =>
        '${r.name.toUpperCase()}: ${amt.toStringAsFixed(2)}',
      RollupStart(targetAmount: final target) =>
        'Rolling up to ${target.toStringAsFixed(2)}',
      RollupEnd(finalAmount: final amt) =>
        'Rollup complete: ${amt.toStringAsFixed(2)}',
      _ => event.sourceEvent ?? event.stage.typeName,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════════════════════

/// Create a collapsible panel version
class EngineConnectionPanelCollapsible extends StatefulWidget {
  const EngineConnectionPanelCollapsible({super.key});

  @override
  State<EngineConnectionPanelCollapsible> createState() =>
      _EngineConnectionPanelCollapsibleState();
}

class _EngineConnectionPanelCollapsibleState
    extends State<EngineConnectionPanelCollapsible> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _isExpanded ? 400 : 48,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2a2a35)),
        ),
        child: Column(
          children: [
            // Collapse header
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lan,
                      color: Color(0xFF4a9eff),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Engine Connection',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: const Color(0xFF606070),
                    ),
                  ],
                ),
              ),
            ),

            // Content
            if (_isExpanded)
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFF2a2a35)),
                    ),
                  ),
                  child: const EngineConnectionPanel(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
