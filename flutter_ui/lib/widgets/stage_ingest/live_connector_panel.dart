// ═══════════════════════════════════════════════════════════════════════════════
// LIVE CONNECTOR PANEL — Real-time engine connection UI
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import '../../providers/stage_ingest_provider.dart';

/// Panel for managing live engine connections
class LiveConnectorPanel extends StatefulWidget {
  final StageIngestProvider provider;
  final Function(IngestStageEvent)? onEvent;

  const LiveConnectorPanel({
    super.key,
    required this.provider,
    this.onEvent,
  });

  @override
  State<LiveConnectorPanel> createState() => _LiveConnectorPanelState();
}

class _LiveConnectorPanelState extends State<LiveConnectorPanel> {
  final _urlController = TextEditingController();
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '9000');
  ConnectorProtocol _protocol = ConnectorProtocol.websocket;
  ConnectorHandle? _activeConnector;
  StreamSubscription<IngestStageEvent>? _eventSubscription;
  final List<IngestStageEvent> _recentEvents = [];
  static const int _maxEvents = 50;

  @override
  void initState() {
    super.initState();
    _urlController.text = 'ws://localhost:8080';
    _eventSubscription = widget.provider.liveEvents.listen(_onEvent);
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _urlController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onEvent(IngestStageEvent event) {
    setState(() {
      _recentEvents.insert(0, event);
      if (_recentEvents.length > _maxEvents) {
        _recentEvents.removeLast();
      }
    });
    widget.onEvent?.call(event);
  }

  void _connect() {
    ConnectorHandle? handle;
    if (_protocol == ConnectorProtocol.websocket) {
      handle = widget.provider.createWebSocketConnector(_urlController.text);
    } else {
      final port = int.tryParse(_portController.text) ?? 9000;
      handle = widget.provider.createTcpConnector(_hostController.text, port);
    }

    if (handle != null) {
      widget.provider.connect(handle.connectorId);
      widget.provider.startEventPolling(handle.connectorId);
      setState(() => _activeConnector = handle);
    }
  }

  void _disconnect() {
    if (_activeConnector != null) {
      widget.provider.stopEventPolling(_activeConnector!.connectorId);
      widget.provider.disconnect(_activeConnector!.connectorId);
      widget.provider.destroyConnector(_activeConnector!.connectorId);
      setState(() => _activeConnector = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildConnectionForm(),
                const SizedBox(height: 12),
                _buildStatus(),
              ],
            ),
          ),
          const Divider(color: Color(0xFF3a3a44), height: 1),
          Expanded(child: _buildEventLog()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(
            _activeConnector != null && widget.provider.isConnected(_activeConnector!.connectorId)
                ? Icons.wifi
                : Icons.wifi_off,
            color: _activeConnector != null && widget.provider.isConnected(_activeConnector!.connectorId)
                ? const Color(0xFF40ff90)
                : Colors.white.withOpacity(0.5),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'Live Connection',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (_activeConnector != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getStateColor().withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _getStateText(),
                style: TextStyle(
                  color: _getStateColor(),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionForm() {
    final isConnected = _activeConnector != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Protocol selector
        Row(
          children: [
            Expanded(
              child: _buildProtocolButton(
                ConnectorProtocol.websocket,
                'WebSocket',
                Icons.public,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildProtocolButton(
                ConnectorProtocol.tcp,
                'TCP',
                Icons.cable,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Connection details
        if (_protocol == ConnectorProtocol.websocket)
          _buildTextField(
            controller: _urlController,
            label: 'WebSocket URL',
            hint: 'ws://localhost:8080',
            enabled: !isConnected,
          )
        else
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: _hostController,
                  label: 'Host',
                  hint: '127.0.0.1',
                  enabled: !isConnected,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTextField(
                  controller: _portController,
                  label: 'Port',
                  hint: '9000',
                  enabled: !isConnected,
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),

        // Connect/Disconnect button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isConnected ? _disconnect : _connect,
            icon: Icon(isConnected ? Icons.link_off : Icons.link, size: 16),
            label: Text(isConnected ? 'Disconnect' : 'Connect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isConnected
                  ? const Color(0xFFff4040)
                  : const Color(0xFF40ff90),
              foregroundColor: isConnected ? Colors.white : Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProtocolButton(ConnectorProtocol protocol, String label, IconData icon) {
    final isSelected = _protocol == protocol;
    final isConnected = _activeConnector != null;

    return GestureDetector(
      onTap: isConnected ? null : () => setState(() => _protocol = protocol),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4a9eff).withOpacity(0.2)
              : const Color(0xFF242430),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4a9eff)
                : const Color(0xFF3a3a44),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? const Color(0xFF4a9eff)
                  : Colors.white.withOpacity(isConnected ? 0.3 : 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF4a9eff)
                    : Colors.white.withOpacity(isConnected ? 0.3 : 0.7),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3a3a44)),
          ),
          child: TextField(
            controller: controller,
            enabled: enabled,
            style: TextStyle(
              color: Colors.white.withOpacity(enabled ? 1 : 0.5),
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatus() {
    if (_activeConnector == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF242430),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.white.withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(
              'Not connected',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF242430),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getStateColor(),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _activeConnector!.address,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_recentEvents.length} events',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventLog() {
    if (_recentEvents.isEmpty) {
      return Center(
        child: Text(
          'No events received yet',
          style: TextStyle(color: Colors.white.withOpacity(0.4)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _recentEvents.length,
      itemBuilder: (context, index) {
        final event = _recentEvents[index];
        return _buildEventRow(event);
      },
    );
  }

  Widget _buildEventRow(IngestStageEvent event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF242430),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _getStageColor(event.stage),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.stage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Text(
            '${event.timestampMs.toStringAsFixed(0)}ms',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _getStateColor() {
    if (_activeConnector == null) return Colors.grey;
    if (widget.provider.isConnected(_activeConnector!.connectorId)) {
      return const Color(0xFF40ff90);
    }
    switch (_activeConnector!.state) {
      case ConnectorState.connecting:
      case ConnectorState.reconnecting:
        return const Color(0xFFffff40);
      case ConnectorState.error:
        return const Color(0xFFff4040);
      default:
        return Colors.grey;
    }
  }

  String _getStateText() {
    if (_activeConnector == null) return 'Disconnected';
    if (widget.provider.isConnected(_activeConnector!.connectorId)) {
      return 'Connected';
    }
    switch (_activeConnector!.state) {
      case ConnectorState.connecting:
        return 'Connecting...';
      case ConnectorState.reconnecting:
        return 'Reconnecting...';
      case ConnectorState.error:
        return 'Error';
      default:
        return 'Disconnected';
    }
  }

  Color _getStageColor(String stage) {
    final upper = stage.toUpperCase();
    if (upper.contains('SPIN_START')) return const Color(0xFF40ff90);
    if (upper.contains('SPIN_END')) return const Color(0xFF40c8ff);
    if (upper.contains('REEL')) return const Color(0xFF4a9eff);
    if (upper.contains('WIN')) return const Color(0xFFffff40);
    if (upper.contains('JACKPOT')) return const Color(0xFFff4040);
    if (upper.contains('FEATURE')) return const Color(0xFFff9040);
    return const Color(0xFF888888);
  }
}
