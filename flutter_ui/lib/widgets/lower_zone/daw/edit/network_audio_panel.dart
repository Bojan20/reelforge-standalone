/// Network Audio Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #29: ReaStream-style host-to-host audio/MIDI streaming on LAN.
///
/// Features:
/// - Send/receive stream list with status indicators
/// - Stream configuration (IP, port, channels, sample rate, buffer)
/// - Peer discovery with auto-connect
/// - Per-stream level metering and latency display
/// - Network statistics (packets sent/received/lost)
library;

import 'package:flutter/material.dart';
import '../../../../services/network_audio_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class NetworkAudioPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const NetworkAudioPanel({super.key, this.onAction});

  @override
  State<NetworkAudioPanel> createState() => _NetworkAudioPanelState();
}

class _NetworkAudioPanelState extends State<NetworkAudioPanel> {
  final _service = NetworkAudioService.instance;
  String? _selectedStreamId;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 240, child: _buildStreamList()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 2, child: _buildStreamDetails()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 200, child: _buildNetworkInfo()),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Stream List
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildStreamList() {
    final sends = _service.sendStreams;
    final receives = _service.receiveStreams;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Send streams
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(children: [
            FabSectionLabel('SEND STREAMS'),
            const Spacer(),
            _iconBtn(Icons.add, 'New send stream', () {
              _service.createSendStream('Send ${sends.length + 1}');
            }),
          ]),
        ),
        Expanded(
          child: sends.isEmpty
              ? Center(child: Text('No send streams',
                  style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: sends.length,
                  itemBuilder: (_, i) => _buildStreamItem(sends[i]),
                ),
        ),
        const Divider(height: 1, color: FabFilterColors.border),
        // Receive streams
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          child: Row(children: [
            FabSectionLabel('RECEIVE STREAMS'),
            const Spacer(),
            _iconBtn(Icons.add, 'New receive stream', () {
              _service.createReceiveStream('Receive ${receives.length + 1}');
            }),
          ]),
        ),
        Expanded(
          child: receives.isEmpty
              ? Center(child: Text('No receive streams',
                  style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: receives.length,
                  itemBuilder: (_, i) => _buildStreamItem(receives[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildStreamItem(NetworkStream stream) {
    final selected = stream.id == _selectedStreamId;
    final statusColor = switch (stream.status) {
      StreamStatus.connected => FabFilterColors.green,
      StreamStatus.connecting => FabFilterColors.orange,
      StreamStatus.error => FabFilterColors.red,
      StreamStatus.disconnected => FabFilterColors.textDisabled,
    };

    return InkWell(
      onTap: () => setState(() => _selectedStreamId = stream.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? FabFilterColors.cyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(children: [
          // Status indicator
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 6),
          // Direction icon
          Icon(
            stream.isSend ? Icons.upload : Icons.download,
            size: 12,
            color: stream.isSend ? FabFilterColors.orange : FabFilterColors.cyan,
          ),
          const SizedBox(width: 4),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stream.name, style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: FabFilterColors.textPrimary,
                ), overflow: TextOverflow.ellipsis),
                Text('${stream.channelCount}ch ${stream.dataType.name}',
                  style: TextStyle(fontSize: 9, color: FabFilterColors.textTertiary)),
              ],
            ),
          ),
          // Level meter (simple bar)
          if (stream.isConnected)
            Container(
              width: 3, height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: FabFilterColors.bgMid,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: stream.peakLevel.clamp(0, 1),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      color: stream.peakLevel > 0.9
                          ? FabFilterColors.red
                          : FabFilterColors.green,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          // Connect/disconnect toggle
          GestureDetector(
            onTap: () => _service.toggleStream(stream.id),
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: stream.isConnected
                    ? FabFilterColors.green.withValues(alpha: 0.3)
                    : FabFilterColors.bgMid,
                border: Border.all(
                  color: stream.isConnected ? FabFilterColors.green : FabFilterColors.border),
              ),
              child: stream.isConnected
                  ? const Icon(Icons.check, size: 10, color: FabFilterColors.green)
                  : null,
            ),
          ),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Stream Details
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildStreamDetails() {
    final stream = _selectedStreamId != null
        ? _service.getStream(_selectedStreamId!)
        : null;

    if (stream == null) {
      return Center(child: Text(
        'Select a stream to view details',
        style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 12),
      ));
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(stream.isSend ? Icons.upload : Icons.download, size: 16,
              color: stream.isSend ? FabFilterColors.orange : FabFilterColors.cyan),
            const SizedBox(width: 6),
            Text(stream.name, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: FabFilterColors.textPrimary)),
            const Spacer(),
            _statusBadge(stream),
          ]),
          const SizedBox(height: 12),

          // Network config
          FabSectionLabel('NETWORK'),
          const SizedBox(height: 6),
          _configRow('Target IP', stream.targetIp),
          _configRow('Port', '${stream.port}'),
          _configRow('Broadcast', stream.broadcast ? 'ON' : 'OFF'),
          const SizedBox(height: 8),

          // Audio config
          FabSectionLabel('AUDIO'),
          const SizedBox(height: 6),
          _configRow('Channels', '${stream.channelCount}'),
          _configRow('Sample Rate', '${stream.sampleRate} Hz'),
          _configRow('Buffer', '${stream.bufferSize} samples'),
          _configRow('Data Type', stream.dataType.name.toUpperCase()),
          const SizedBox(height: 8),

          // Direction selector
          FabSectionLabel('DIRECTION'),
          const SizedBox(height: 6),
          Row(children: [
            _directionChip('Send', StreamDirection.send, stream),
            const SizedBox(width: 4),
            _directionChip('Receive', StreamDirection.receive, stream),
          ]),
          const SizedBox(height: 8),

          // Data type selector
          FabSectionLabel('DATA TYPE'),
          const SizedBox(height: 6),
          Row(children: [
            _dataTypeChip('Audio', StreamDataType.audio, stream),
            const SizedBox(width: 4),
            _dataTypeChip('MIDI', StreamDataType.midi, stream),
            const SizedBox(width: 4),
            _dataTypeChip('Both', StreamDataType.audioAndMidi, stream),
          ]),
          const SizedBox(height: 8),

          // Channel count selector
          FabSectionLabel('CHANNELS'),
          const SizedBox(height: 6),
          Row(children: [
            for (final ch in [1, 2, 4, 8, 16, 32]) ...[
              _channelChip(ch, stream),
              if (ch != 32) const SizedBox(width: 3),
            ],
          ]),

          const Spacer(),
          // Actions
          Row(children: [
            Expanded(child: _actionButton(
              stream.isConnected ? Icons.stop : Icons.play_arrow,
              stream.isConnected ? 'Disconnect' : 'Connect',
              () => _service.toggleStream(stream.id),
            )),
            const SizedBox(width: 4),
            Expanded(child: _actionButton(
              Icons.delete_outline, 'Remove', () {
                _service.removeStream(stream.id);
                setState(() => _selectedStreamId = null);
              },
            )),
          ]),
        ],
      ),
    );
  }

  Widget _configRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        SizedBox(width: 80, child: Text('$label:', style: const TextStyle(
          fontSize: 10, color: FabFilterColors.textTertiary))),
        Text(value, style: const TextStyle(
          fontSize: 10, color: FabFilterColors.textSecondary)),
      ]),
    );
  }

  Widget _statusBadge(NetworkStream stream) {
    final color = switch (stream.status) {
      StreamStatus.connected => FabFilterColors.green,
      StreamStatus.connecting => FabFilterColors.orange,
      StreamStatus.error => FabFilterColors.red,
      StreamStatus.disconnected => FabFilterColors.textDisabled,
    };
    final label = stream.status.name.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 8, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _directionChip(String label, StreamDirection dir, NetworkStream stream) {
    final active = stream.direction == dir;
    return GestureDetector(
      onTap: () => _service.updateStream(stream.id, direction: dir),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FabFilterColors.cyan.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? FabFilterColors.cyan : FabFilterColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 10, color: active ? FabFilterColors.cyan : FabFilterColors.textTertiary)),
      ),
    );
  }

  Widget _dataTypeChip(String label, StreamDataType type, NetworkStream stream) {
    final active = stream.dataType == type;
    return GestureDetector(
      onTap: () => _service.updateStream(stream.id, dataType: type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FabFilterColors.orange.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? FabFilterColors.orange : FabFilterColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 10, color: active ? FabFilterColors.orange : FabFilterColors.textTertiary)),
      ),
    );
  }

  Widget _channelChip(int count, NetworkStream stream) {
    final active = stream.channelCount == count;
    return GestureDetector(
      onTap: () => _service.updateStream(stream.id, channelCount: count),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FabFilterColors.green.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? FabFilterColors.green : FabFilterColors.border),
        ),
        child: Text('$count', style: TextStyle(
          fontSize: 10, color: active ? FabFilterColors.green : FabFilterColors.textTertiary)),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Network Info & Peers
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildNetworkInfo() {
    final selected = _selectedStreamId != null
        ? _service.getStream(_selectedStreamId!)
        : null;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status overview
          FabSectionLabel('STATUS'),
          const SizedBox(height: 4),
          Text('Total streams: ${_service.streamCount}',
            style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
          Text('Connected: ${_service.connectedCount}',
            style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
          Text('Host: ${_service.localHostname}',
            style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
          const SizedBox(height: 8),

          // Selected stream stats
          if (selected != null && selected.isConnected) ...[
            FabSectionLabel('STATISTICS'),
            const SizedBox(height: 4),
            Text('Latency: ${selected.latencyMs.toStringAsFixed(1)} ms',
              style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            Text('Peak: ${(selected.peakLevel * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            Text('RMS: ${(selected.rmsLevel * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            if (selected.isSend)
              Text('Sent: ${selected.packetsSent}',
                style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            if (selected.isReceive)
              Text('Received: ${selected.packetsReceived}',
                style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            Text('Lost: ${selected.packetsLost}',
              style: TextStyle(fontSize: 10,
                color: selected.packetsLost > 0 ? FabFilterColors.red : FabFilterColors.textTertiary)),
            const SizedBox(height: 8),
          ],

          // Peers
          FabSectionLabel('PEERS'),
          const SizedBox(height: 4),
          Row(children: [
            Text('Discovery: ', style: const TextStyle(
              fontSize: 10, color: FabFilterColors.textTertiary)),
            GestureDetector(
              onTap: () => _service.toggleDiscovery(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _service.discoveryActive
                      ? FabFilterColors.green.withValues(alpha: 0.2)
                      : FabFilterColors.bgMid,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _service.discoveryActive ? FabFilterColors.green : FabFilterColors.border),
                ),
                child: Text(_service.discoveryActive ? 'ON' : 'OFF', style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w600,
                  color: _service.discoveryActive ? FabFilterColors.green : FabFilterColors.textTertiary,
                )),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Expanded(
            child: _service.activePeers.isEmpty
                ? Center(child: Text(
                    'No peers found.\n\nEnable discovery to\nfind hosts on LAN.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary),
                  ))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _service.activePeers.length,
                    itemBuilder: (_, i) {
                      final peer = _service.activePeers[i];
                      return _buildPeerItem(peer);
                    },
                  ),
          ),
          const SizedBox(height: 4),
          // Disconnect all
          _actionButton(Icons.stop_circle_outlined, 'Disconnect All', () {
            _service.disconnectAll();
          }),
        ],
      ),
    );
  }

  Widget _buildPeerItem(NetworkPeer peer) {
    return InkWell(
      onTap: () => _service.connectToPeer(peer),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: FabFilterColors.bgMid,
        ),
        child: Row(children: [
          const Icon(Icons.computer, size: 12, color: FabFilterColors.cyan),
          const SizedBox(width: 4),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(peer.hostname, style: const TextStyle(
                fontSize: 10, color: FabFilterColors.textPrimary),
                overflow: TextOverflow.ellipsis),
              Text('${peer.ipAddress}:${peer.port}', style: const TextStyle(
                fontSize: 8, color: FabFilterColors.textTertiary)),
            ],
          )),
          if (peer.availableStreams.isNotEmpty)
            Text('${peer.availableStreams.length}', style: const TextStyle(
              fontSize: 9, color: FabFilterColors.cyan)),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: FabFilterColors.textSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return SizedBox(
      height: 28,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? FabFilterColors.bgMid : FabFilterColors.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FabFilterColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14,
                color: enabled ? FabFilterColors.textSecondary : FabFilterColors.textDisabled),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11,
                color: enabled ? FabFilterColors.textSecondary : FabFilterColors.textDisabled)),
            ],
          ),
        ),
      ),
    );
  }
}
