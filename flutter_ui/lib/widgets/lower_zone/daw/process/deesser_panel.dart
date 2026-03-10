/// DAW De-Esser Panel
///
/// FF-E de-esser wrapper with bypass/wet-dry controls.
/// Displays FabFilterDeEsserPanel for selected track.
/// Auto-loads de-esser processor if not already in chain.
library;

import 'package:flutter/material.dart';
import '../../../../providers/dsp_chain_provider.dart';
import '../../../fabfilter/fabfilter_deesser_panel.dart';
import '../../lower_zone_types.dart';

class DeEsserPanel extends StatefulWidget {
  final int? selectedTrackId;

  const DeEsserPanel({super.key, this.selectedTrackId});

  @override
  State<DeEsserPanel> createState() => _DeEsserPanelState();
}

class _DeEsserPanelState extends State<DeEsserPanel> {
  bool _autoLoaded = false;
  String? _nodeId;

  @override
  void initState() {
    super.initState();
    _ensureProcessorLoaded();
    DspChainProvider.instance.addListener(_onChainChanged);
  }

  @override
  void dispose() {
    DspChainProvider.instance.removeListener(_onChainChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(DeEsserPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTrackId != widget.selectedTrackId) {
      _autoLoaded = false;
      _ensureProcessorLoaded();
    }
  }

  void _onChainChanged() {
    if (mounted) setState(() {});
  }

  void _ensureProcessorLoaded() {
    if (_autoLoaded) return;
    final trackId = widget.selectedTrackId ?? 0;
    final chain = DspChainProvider.instance.getChain(trackId);
    final node = chain.nodes.where((n) => n.type == DspNodeType.deEsser).firstOrNull;
    if (node != null) {
      _nodeId = node.id;
    } else {
      DspChainProvider.instance.addNode(trackId, DspNodeType.deEsser);
      final updated = DspChainProvider.instance.getChain(trackId);
      _nodeId = updated.nodes.where((n) => n.type == DspNodeType.deEsser).firstOrNull?.id;
    }
    _autoLoaded = true;
  }

  DspNode? get _node {
    final trackId = widget.selectedTrackId ?? 0;
    final chain = DspChainProvider.instance.getChain(trackId);
    return _nodeId != null
        ? chain.nodes.where((n) => n.id == _nodeId).firstOrNull
        : chain.nodes.where((n) => n.type == DspNodeType.deEsser).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final trackId = widget.selectedTrackId ?? 0;
    final node = _node;

    return Column(
      children: [
        _buildProcessorHeader(trackId, node),
        Expanded(child: FabFilterDeEsserPanel(trackId: trackId)),
      ],
    );
  }

  Widget _buildProcessorHeader(int trackId, DspNode? node) {
    final bypassed = node?.bypass ?? false;
    final wetDry = node?.wetDry ?? 1.0;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        border: Border(bottom: BorderSide(color: LowerZoneColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_nodeId != null) {
                DspChainProvider.instance.toggleNodeBypass(trackId, _nodeId!);
              }
            },
            child: Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: bypassed
                    ? Colors.red.withValues(alpha: 0.2)
                    : LowerZoneColors.dawAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: bypassed ? Colors.red : LowerZoneColors.dawAccent,
                ),
              ),
              child: Icon(
                bypassed ? Icons.power_off : Icons.power,
                size: 12,
                color: bypassed ? Colors.red : LowerZoneColors.dawAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'FF-E DE-ESSER',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: bypassed ? LowerZoneColors.textMuted : LowerZoneColors.dawAccent,
              letterSpacing: 0.5,
            ),
          ),
          if (bypassed)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text('BYPASS',
                style: TextStyle(fontSize: 7, color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          const Spacer(),
          const Text('WET ', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          SizedBox(
            width: 80,
            child: Slider(
              value: wetDry,
              min: 0, max: 1,
              activeColor: LowerZoneColors.dawAccent,
              onChanged: (v) {
                if (_nodeId != null) {
                  DspChainProvider.instance.setNodeWetDry(trackId, _nodeId!, v);
                }
              },
            ),
          ),
          Text('${(wetDry * 100).toInt()}%',
            style: const TextStyle(fontSize: 8, color: LowerZoneColors.textSecondary, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
