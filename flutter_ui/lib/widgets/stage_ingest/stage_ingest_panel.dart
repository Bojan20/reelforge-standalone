// ═══════════════════════════════════════════════════════════════════════════════
// STAGE INGEST PANEL — Main panel combining all ingest features
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/stage_ingest_provider.dart';
import 'adapter_wizard_panel.dart';
import 'live_connector_panel.dart';
import 'mock_engine_panel.dart';
import 'network_diagnostics_panel.dart';
import 'stage_trace_viewer.dart';

/// Main panel for Stage Ingest System
class StageIngestPanel extends StatefulWidget {
  final Function(int traceHandle)? onTraceSelected;
  final Function(IngestStageEvent)? onLiveEvent;

  const StageIngestPanel({
    super.key,
    this.onTraceSelected,
    this.onLiveEvent,
  });

  @override
  State<StageIngestPanel> createState() => _StageIngestPanelState();
}

class _StageIngestPanelState extends State<StageIngestPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int? _selectedTraceHandle;
  int? _activeConnectorId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StageIngestProvider>(
      builder: (context, provider, _) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0a0a0c),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _buildHeader(provider),
              _buildTabBar(provider),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildTracesTab(provider),
                    _buildWizardTab(provider),
                    _buildLiveTab(provider),
                    _buildStagingTab(provider),
                    _buildDiagnosticsTab(provider),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(StageIngestProvider provider) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers, color: Color(0xFF4a9eff), size: 20),
          const SizedBox(width: 10),
          const Text(
            'Stage Ingest',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Staging mode badge
          if (provider.isStagingMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'STAGING',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          // Stats
          _buildStatBadge(Icons.extension, '${provider.adapterCount}', 'Adapters'),
          const SizedBox(width: 12),
          _buildStatBadge(Icons.timeline, '${provider.traceCount}', 'Traces'),
          const SizedBox(width: 12),
          _buildStatBadge(Icons.wifi, '${provider.connectorCount}', 'Connections'),
        ],
      ),
    );
  }

  Widget _buildStatBadge(IconData icon, String value, String label) {
    return Tooltip(
      message: label,
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white.withOpacity(0.5)),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(StageIngestProvider provider) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFF1a1a20),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3a3a44)),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF4a9eff),
        indicatorWeight: 2,
        labelColor: const Color(0xFF4a9eff),
        unselectedLabelColor: Colors.white.withOpacity(0.5),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        tabs: [
          const Tab(text: 'Traces'),
          const Tab(text: 'Wizard'),
          const Tab(text: 'Live'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Staging'),
                if (provider.isStagingMode)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
          ),
          const Tab(text: 'Diagnostics'),
        ],
      ),
    );
  }

  Widget _buildTracesTab(StageIngestProvider provider) {
    final traces = provider.traces;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Actions
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _showImportDialog(context, provider),
                icon: const Icon(Icons.file_upload, size: 16),
                label: const Text('Import JSON'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4a9eff),
                  side: const BorderSide(color: Color(0xFF4a9eff)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _createNewTrace(provider),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Trace'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF40ff90),
                  side: const BorderSide(color: Color(0xFF40ff90)),
                ),
              ),
              const Spacer(),
              // Timing profile
              DropdownButton<TimingProfile>(
                value: provider.timingProfile,
                dropdownColor: const Color(0xFF242430),
                underline: const SizedBox(),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: TimingProfile.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(_profileName(p)),
                  );
                }).toList(),
                onChanged: (p) {
                  if (p != null) provider.setTimingProfile(p);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Trace list
          Expanded(
            child: traces.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timeline, size: 48, color: Colors.white.withOpacity(0.2)),
                        const SizedBox(height: 12),
                        Text(
                          'No traces loaded',
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Import JSON or create a new trace',
                          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Trace list
                      Expanded(
                        flex: 1,
                        child: ListView.builder(
                          itemCount: traces.length,
                          itemBuilder: (context, index) {
                            final trace = traces[index];
                            return _buildTraceItem(trace, provider);
                          },
                        ),
                      ),
                      // Selected trace viewer
                      if (_selectedTraceHandle != null) ...[
                        const SizedBox(height: 12),
                        Expanded(
                          flex: 2,
                          child: StageTraceViewer(
                            provider: provider,
                            traceHandle: _selectedTraceHandle!,
                            onEventTap: (event) {
                              // Handle event tap
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTraceItem(StageTraceHandle trace, StageIngestProvider provider) {
    final isSelected = trace.handle == _selectedTraceHandle;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedTraceHandle = trace.handle);
        widget.onTraceSelected?.call(trace.handle);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4a9eff).withOpacity(0.1)
              : const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4a9eff)
                : const Color(0xFF3a3a44),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.timeline,
              size: 16,
              color: isSelected
                  ? const Color(0xFF4a9eff)
                  : Colors.white.withOpacity(0.5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trace.traceId,
                    style: TextStyle(
                      color: Colors.white.withOpacity(isSelected ? 1 : 0.8),
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${trace.eventCount} events | ${_formatDuration(trace.durationMs)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            // Has feature/jackpot badges
            if (provider.traceHasFeature(trace.handle))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFff9040).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Feature',
                  style: TextStyle(
                    color: Color(0xFFff9040),
                    fontSize: 9,
                  ),
                ),
              ),
            if (provider.traceHasJackpot(trace.handle))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFff4040).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Jackpot',
                  style: TextStyle(
                    color: Color(0xFFff4040),
                    fontSize: 9,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.delete, size: 16, color: Colors.white.withOpacity(0.4)),
              onPressed: () {
                provider.destroyTrace(trace.handle);
                if (_selectedTraceHandle == trace.handle) {
                  setState(() => _selectedTraceHandle = null);
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(maxWidth: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWizardTab(StageIngestProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: AdapterWizardPanel(
        provider: provider,
        onConfigGenerated: (configId) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Config generated (ID: $configId)'),
              backgroundColor: const Color(0xFF40ff90),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLiveTab(StageIngestProvider provider) {
    // Track the active connector from Live tab
    final connectors = provider.connectors;
    if (connectors.isNotEmpty && _activeConnectorId == null) {
      _activeConnectorId = connectors.first.connectorId;
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: LiveConnectorPanel(
        provider: provider,
        onEvent: (event) {
          widget.onLiveEvent?.call(event);
          // Update active connector when events come in
          final activeConnector = connectors.where((c) => provider.isConnected(c.connectorId)).firstOrNull;
          if (activeConnector != null && _activeConnectorId != activeConnector.connectorId) {
            setState(() => _activeConnectorId = activeConnector.connectorId);
          }
        },
      ),
    );
  }

  Widget _buildStagingTab(StageIngestProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Staging mode header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: provider.isStagingMode
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: provider.isStagingMode
                    ? Colors.green.withOpacity(0.5)
                    : Colors.grey.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  provider.isStagingMode ? Icons.developer_mode : Icons.developer_board_off,
                  size: 20,
                  color: provider.isStagingMode ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.isStagingMode ? 'Staging Mode Active' : 'Staging Mode Disabled',
                        style: TextStyle(
                          color: provider.isStagingMode ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        provider.isStagingMode
                            ? 'Mock engine events are being forwarded to audio system'
                            : 'Enable to test audio without connecting to a real engine',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: provider.isStagingMode,
                  onChanged: (value) {
                    provider.toggleStagingMode();
                  },
                  activeColor: Colors.green,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Mock engine panel
          Expanded(
            child: MockEnginePanel(
              onStageEvent: (event) {
                // Forward mock events to parent callback
                widget.onLiveEvent?.call(IngestStageEvent(
                  stage: event.stage,
                  timestampMs: event.timestampMs,
                  data: event.data,
                ));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsTab(StageIngestProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: NetworkDiagnosticsPanel(
        provider: provider,
        connectorId: _activeConnectorId,
      ),
    );
  }

  void _showImportDialog(BuildContext context, StageIngestProvider provider) {
    showDialog(
      context: context,
      builder: (context) => _ImportJsonDialog(provider: provider),
    );
  }

  void _createNewTrace(StageIngestProvider provider) {
    final traceId = 'trace-${DateTime.now().millisecondsSinceEpoch}';
    final trace = provider.createTrace(traceId, 'manual');
    if (trace != null) {
      setState(() => _selectedTraceHandle = trace.handle);
    }
  }

  String _formatDuration(double ms) {
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds ~/ 60;
    final secs = (seconds % 60).toStringAsFixed(0);
    return '$minutes:${secs.padLeft(2, '0')}';
  }

  String _profileName(TimingProfile profile) {
    switch (profile) {
      case TimingProfile.normal: return 'Normal';
      case TimingProfile.turbo: return 'Turbo';
      case TimingProfile.mobile: return 'Mobile';
      case TimingProfile.instant: return 'Instant';
      case TimingProfile.studio: return 'Studio';
    }
  }
}

/// Dialog for importing JSON trace data
class _ImportJsonDialog extends StatefulWidget {
  final StageIngestProvider provider;

  const _ImportJsonDialog({required this.provider});

  @override
  State<_ImportJsonDialog> createState() => _ImportJsonDialogState();
}

class _ImportJsonDialogState extends State<_ImportJsonDialog> {
  final _controller = TextEditingController();
  String _error = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _import() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste JSON data first');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    // Try to load as trace
    final trace = widget.provider.loadTraceFromJson(text);
    if (trace != null) {
      Navigator.of(context).pop(trace.handle);
      return;
    }

    // Try to ingest with auto-detection
    final autoTrace = widget.provider.ingestJsonAuto(text);
    if (autoTrace != null) {
      Navigator.of(context).pop(autoTrace.handle);
      return;
    }

    setState(() {
      _isLoading = false;
      _error = 'Failed to parse JSON. Try using the Wizard tab for auto-configuration.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a20),
      title: Row(
        children: [
          const Icon(Icons.file_upload, color: Color(0xFF4a9eff)),
          const SizedBox(width: 8),
          const Text(
            'Import JSON Trace',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste JSON from your slot engine:',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _error.isNotEmpty
                      ? const Color(0xFFff4040)
                      : const Color(0xFF3a3a44),
                ),
              ),
              child: TextField(
                controller: _controller,
                maxLines: null,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: '{"events": [...], "game_id": "..."}',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(8),
                ),
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error,
                  style: const TextStyle(color: Color(0xFFff4040), fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _import,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4a9eff),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Import'),
        ),
      ],
    );
  }
}
