import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/ucp_export_provider.dart';

/// UCP-12: UCP Export™ Panel — Universal Casino Protocol Export Engine
///
/// Multi-target export dashboard: select casino platforms, preview output,
/// batch export, and view export history.
class UcpExportPanel extends StatefulWidget {
  const UcpExportPanel({super.key});

  @override
  State<UcpExportPanel> createState() => _UcpExportPanelState();
}

class _UcpExportPanelState extends State<UcpExportPanel> {
  UcpExportProvider? _provider;
  String? _previewOutput;
  CasinoExportTarget? _previewTarget;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<UcpExportProvider>();
      _provider?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _provider?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return const Center(
        child: Text('UCP Export not available',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Left: Target selector ──────────────────────────────
          SizedBox(
            width: 260,
            child: _buildTargetSelector(p),
          ),
          const SizedBox(width: 8),
          // ─── Center: Preview + Actions ──────────────────────────
          Expanded(
            flex: 3,
            child: _buildPreviewArea(p),
          ),
          const SizedBox(width: 8),
          // ─── Right: History ─────────────────────────────────────
          SizedBox(
            width: 200,
            child: _buildHistoryPanel(p),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TARGET SELECTOR — grouped by category
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTargetSelector(UcpExportProvider p) {
    // Group targets by category
    final grouped = <String, List<CasinoExportTarget>>{};
    for (final t in CasinoExportTarget.values) {
      grouped.putIfAbsent(t.category, () => []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.rocket_launch, color: Color(0xFFFFCC00), size: 14),
            const SizedBox(width: 6),
            const Text('Export Targets',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            // Select all / none
            _miniButton('All', () {
              for (final t in CasinoExportTarget.values) {
                if (!p.selectedTargets.contains(t)) p.toggleTarget(t);
              }
            }),
            const SizedBox(width: 4),
            _miniButton('None', () {
              for (final t in p.selectedTargets.toList()) {
                p.toggleTarget(t);
              }
            }),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text(entry.key,
                        style: TextStyle(
                            color: Color(entry.value.first.colorValue),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                  ),
                  for (final t in entry.value)
                    _buildTargetTile(p, t),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetTile(UcpExportProvider p, CasinoExportTarget t) {
    final selected = p.selectedTargets.contains(t);
    final isActive = p.target == t;

    return GestureDetector(
      onTap: () {
        p.setTarget(t);
        _generatePreview(p, t);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF2A2A4E)
              : const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(3),
          border: isActive
              ? Border.all(color: Color(t.colorValue).withAlpha(120), width: 0.5)
              : null,
        ),
        child: Row(
          children: [
            // Checkbox for batch
            GestureDetector(
              onTap: () => p.toggleTarget(t),
              child: Icon(
                selected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 12,
                color: selected
                    ? Color(t.colorValue)
                    : const Color(0xFF555577),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t.displayName,
                  style: TextStyle(
                      color: isActive
                          ? const Color(0xFFEEEEEE)
                          : const Color(0xFF999999),
                      fontSize: 10)),
            ),
            Text(t.fileExtension,
                style: const TextStyle(
                    color: Color(0xFF555577), fontSize: 8)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PREVIEW AREA
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPreviewArea(UcpExportProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action bar
        Row(
          children: [
            const Icon(Icons.preview, color: Color(0xFF888888), size: 14),
            const SizedBox(width: 6),
            Text(
              _previewTarget != null
                  ? 'Preview: ${_previewTarget!.displayName}'
                  : 'Select a target to preview',
              style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_previewOutput != null) ...[
              _actionButton(Icons.copy, 'Copy', () {
                Clipboard.setData(ClipboardData(text: _previewOutput!));
              }),
              const SizedBox(width: 4),
            ],
            _actionButton(
              Icons.play_arrow,
              p.isExporting ? 'Exporting...' : 'Export Selected (${p.selectedTargets.length})',
              p.isExporting ? null : () => _batchExport(p),
              color: const Color(0xFF44CC44),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Preview content
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                  color: const Color(0xFF2A2A4C), width: 0.5),
            ),
            child: _previewOutput != null
                ? SingleChildScrollView(
                    child: SelectableText(
                      _previewOutput!,
                      style: const TextStyle(
                        color: Color(0xFF88CC88),
                        fontSize: 10,
                        fontFamily: 'monospace',
                        height: 1.3,
                      ),
                    ),
                  )
                : const Center(
                    child: Text(
                      'Click a target to preview export format.\n'
                      'Check targets for batch export.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF555577), fontSize: 10),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HISTORY PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHistoryPanel(UcpExportProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.history, color: Color(0xFF888888), size: 14),
            SizedBox(width: 6),
            Text('Export History',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: p.exportHistory.isEmpty
              ? const Center(
                  child: Text('No exports yet',
                      style: TextStyle(
                          color: Color(0xFF555577), fontSize: 10)),
                )
              : ListView.builder(
                  itemCount: p.exportHistory.length,
                  itemBuilder: (context, i) {
                    final (target, info, time) = p.exportHistory[i];
                    final ago = DateTime.now().difference(time);
                    final agoStr = ago.inMinutes < 1
                        ? 'just now'
                        : ago.inMinutes < 60
                            ? '${ago.inMinutes}m ago'
                            : '${ago.inHours}h ago';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16162A),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Color(target.colorValue),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(target.displayName,
                                    style: const TextStyle(
                                        color: Color(0xFFCCCCCC),
                                        fontSize: 9)),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(info,
                                  style: const TextStyle(
                                      color: Color(0xFF888888),
                                      fontSize: 8)),
                              Text(agoStr,
                                  style: const TextStyle(
                                      color: Color(0xFF555577),
                                      fontSize: 8)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _generatePreview(UcpExportProvider p, CasinoExportTarget target) {
    // Generate preview with demo events
    final demoEvents = _buildDemoEvents();
    try {
      final output = p.exportTo(target,
          gameName: 'DemoSlot',
          events: demoEvents,
          projectConfig: {'rtp': 96.5, 'volatility': 'medium'});
      setState(() {
        _previewOutput = output;
        _previewTarget = target;
      });
    } catch (e) {
      setState(() {
        _previewOutput = 'Error: $e';
        _previewTarget = target;
      });
    }
  }

  void _batchExport(UcpExportProvider p) {
    if (p.selectedTargets.isEmpty) return;
    final demoEvents = _buildDemoEvents();
    try {
      final results = p.exportBatch(
        gameName: 'DemoSlot',
        events: demoEvents,
        projectConfig: {'rtp': 96.5, 'volatility': 'medium'},
      );
      setState(() {
        _previewOutput =
            '// Batch export complete: ${results.length} targets\n\n'
            '${results.entries.map((e) => '// ═══ ${e.key.displayName} ═══\n${e.value}').join('\n\n')}';
        _previewTarget = null;
      });
    } catch (e) {
      setState(() {
        _previewOutput = 'Batch export error: $e';
      });
    }
  }

  List<SlotAudioExportEvent> _buildDemoEvents() {
    return const [
      SlotAudioExportEvent(
          id: 'reel_spin_start',
          displayName: 'Reel Spin Start',
          category: 'reel',
          stage: 'REEL_START',
          assetPath: 'sfx/reel_spin.wav',
          durationMs: 2500,
          loop: true,
          priority: 2),
      SlotAudioExportEvent(
          id: 'reel_stop_1',
          displayName: 'Reel Stop 1',
          category: 'reel',
          stage: 'REEL_STOP',
          assetPath: 'sfx/reel_stop_1.wav',
          durationMs: 350),
      SlotAudioExportEvent(
          id: 'win_small',
          displayName: 'Small Win',
          category: 'win',
          stage: 'WIN_CELEBRATION',
          assetPath: 'sfx/win_small.wav',
          durationMs: 1200,
          volumeDb: -3.0,
          priority: 3),
      SlotAudioExportEvent(
          id: 'win_big',
          displayName: 'Big Win',
          category: 'win',
          stage: 'WIN_CELEBRATION',
          assetPath: 'sfx/win_big.wav',
          durationMs: 8000,
          priority: 1),
      SlotAudioExportEvent(
          id: 'feature_trigger',
          displayName: 'Feature Trigger',
          category: 'feature',
          stage: 'FEATURE_TRIGGER',
          assetPath: 'sfx/feature_trigger.wav',
          durationMs: 3200,
          priority: 1),
      SlotAudioExportEvent(
          id: 'ambient_base',
          displayName: 'Base Game Ambient',
          category: 'ambient',
          stage: 'IDLE',
          assetPath: 'music/base_ambient.wav',
          durationMs: 30000,
          loop: true,
          volumeDb: -12.0,
          priority: 8),
      SlotAudioExportEvent(
          id: 'ui_click',
          displayName: 'UI Click',
          category: 'ui',
          stage: 'UI',
          assetPath: 'sfx/ui_click.wav',
          durationMs: 80,
          volumeDb: -6.0,
          priority: 5),
    ];
  }

  Widget _miniButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A4E),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF8888AA), fontSize: 9)),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onTap,
      {Color color = const Color(0xFF8888AA)}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: onTap != null
              ? color.withAlpha(30)
              : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
              color: onTap != null
                  ? color.withAlpha(80)
                  : const Color(0xFF2A2A4C),
              width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(color: color, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}
