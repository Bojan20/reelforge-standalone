/// DAW FX Chain Panel - FULL (P0.1)
/// Updated: 2026-01-29 - Added per-processor CPU meters (P3.2)
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/dsp_chain_provider.dart';
import '../shared/processor_cpu_meter.dart';

class FxChainPanel extends StatelessWidget {
  final int? selectedTrackId;
  final void Function(DawProcessSubTab)? onNavigateToSubTab;

  const FxChainPanel({super.key, this.selectedTrackId, this.onNavigateToSubTab});

  @override
  Widget build(BuildContext context) {
    final trackId = selectedTrackId;
    if (trackId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.link, size: 48, color: LowerZoneColors.textMuted),
            SizedBox(height: 12),
            Text('No Track Selected', style: TextStyle(fontSize: 14, color: LowerZoneColors.textPrimary)),
            SizedBox(height: 4),
            Text('Select a track to view FX chain', style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted)),
          ],
        ),
      );
    }

    return ListenableBuilder(
      listenable: DspChainProvider.instance,
      builder: (context, _) {
        final provider = DspChainProvider.instance;
        
        if (!provider.hasChain(trackId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.initializeChain(trackId);
          });
        }

        final chain = provider.getChain(trackId);
        final sortedNodes = chain.sortedNodes;

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.link, size: 16, color: LowerZoneColors.dawAccent),
                  const SizedBox(width: 8),
                  Text('FX CHAIN — Track $trackId', 
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: LowerZoneColors.dawAccent, letterSpacing: 1.0)),
                  const SizedBox(width: 12),
                  _buildChainBypassToggle(trackId, chain.bypass),
                  const SizedBox(width: 12),
                  // CPU usage badge (P3.2)
                  ProcessorCpuBadge(trackId: trackId),
                  const Spacer(),
                  _buildAddProcessorButton(trackId, provider),
                  const SizedBox(width: 8),
                  _buildChainActionButton(Icons.copy, 'Copy', () => provider.copyChain(trackId)),
                  if (provider.hasClipboard) ...[
                    const SizedBox(width: 4),
                    _buildChainActionButton(Icons.paste, 'Paste', () => provider.pasteChain(trackId)),
                  ],
                  const SizedBox(width: 8),
                  _buildChainActionButton(Icons.clear_all, 'Clear', () => provider.clearChain(trackId)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChainNode('INPUT', Icons.input, isEndpoint: true),
                      _buildChainConnector(),
                      if (sortedNodes.isEmpty)
                        _buildEmptyChainPlaceholder(trackId, provider)
                      else
                        ...sortedNodes.expand((node) => [
                          _buildDraggableProcessor(trackId, node, provider),
                          _buildChainConnector(),
                        ]),
                      _buildChainNode('OUTPUT', Icons.output, isEndpoint: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChainBypassToggle(int trackId, bool bypassed) {
    return GestureDetector(
      onTap: () => DspChainProvider.instance.toggleChainBypass(trackId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bypassed ? Colors.orange.withValues(alpha: 0.2) : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: bypassed ? Colors.orange : LowerZoneColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(bypassed ? Icons.power_off : Icons.power, size: 12, 
              color: bypassed ? Colors.orange : LowerZoneColors.textSecondary),
            const SizedBox(width: 4),
            Text(bypassed ? 'BYPASSED' : 'ACTIVE',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, 
                color: bypassed ? Colors.orange : LowerZoneColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildAddProcessorButton(int trackId, DspChainProvider provider) {
    return PopupMenuButton<DspNodeType>(
      tooltip: 'Add Processor',
      offset: const Offset(0, 30),
      color: LowerZoneColors.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), 
        side: const BorderSide(color: LowerZoneColors.border)),
      onSelected: (type) => provider.addNode(trackId, type),
      itemBuilder: (context) => DspNodeType.values.map((type) => PopupMenuItem(
        value: type,
        child: Row(
          children: [
            Icon(_nodeTypeIcon(type), size: 14, color: LowerZoneColors.dawAccent),
            const SizedBox(width: 8),
            Text(type.fullName, style: const TextStyle(fontSize: 11, color: LowerZoneColors.textPrimary)),
          ],
        ),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: LowerZoneColors.dawAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.dawAccent.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 12, color: LowerZoneColors.dawAccent),
            SizedBox(width: 4),
            Text('Add', style: TextStyle(fontSize: 10, color: LowerZoneColors.dawAccent, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChainPlaceholder(int trackId, DspChainProvider provider) {
    return DragTarget<DspNodeType>(
      onAcceptWithDetails: (details) => provider.addNode(trackId, details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          width: 150, height: 85,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isHovering ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHovering ? LowerZoneColors.dawAccent : LowerZoneColors.border,
              width: 2, style: BorderStyle.solid),
          ),
          child: const Center(
            child: Text('Drop here\nor click Add', 
              style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted), textAlign: TextAlign.center),
          ),
        );
      },
    );
  }

  Widget _buildDraggableProcessor(int trackId, DspNode node, DspChainProvider provider) {
    return Draggable<String>(
      data: node.id,
      feedback: Material(color: Colors.transparent, child: _buildProcessorCard(node, isDragging: true)),
      childWhenDragging: Opacity(opacity: 0.3, child: _buildProcessorCard(node)),
      child: DragTarget<String>(
        onAcceptWithDetails: (details) {
          if (details.data != node.id) {
            provider.swapNodes(trackId, details.data, node.id);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return _buildProcessorCard(node, isDropTarget: candidateData.isNotEmpty, trackId: trackId);
        },
      ),
    );
  }

  Widget _buildProcessorCard(DspNode node, {bool isDragging = false, bool isDropTarget = false, int? trackId}) {
    final isActive = !node.bypass;
    return GestureDetector(
      onTap: trackId != null ? () => _navigateToProcessor(node.type) : null,
      child: Container(
        width: 100, height: 85, // Increased height to accommodate CPU meter
        decoration: BoxDecoration(
          color: isDropTarget ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
            : isActive ? LowerZoneColors.dawAccent.withValues(alpha: 0.15) : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDropTarget ? LowerZoneColors.dawAccent : isActive ? LowerZoneColors.dawAccent : LowerZoneColors.border,
            width: isDropTarget ? 2 : 1),
          boxShadow: isDragging ? [BoxShadow(color: LowerZoneColors.dawAccent.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : null,
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_nodeTypeIcon(node.type), size: 18, color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted),
                const SizedBox(height: 2),
                Text(node.type.shortName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                  color: isActive ? LowerZoneColors.textPrimary : LowerZoneColors.textMuted)),
                if (node.wetDry < 1.0)
                  Text('${(node.wetDry * 100).toInt()}%', style: const TextStyle(fontSize: 8, color: LowerZoneColors.textTertiary)),
                const SizedBox(height: 4),
                // CPU meter (P3.2)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ProcessorCpuMeterInline(
                    processorType: node.type,
                    isBypassed: node.bypass,
                    width: 70,
                    height: 6,
                  ),
                ),
              ],
            ),
            if (trackId != null) Positioned(
              top: 4, right: 4,
              child: GestureDetector(
                onTap: () => DspChainProvider.instance.toggleNodeBypass(trackId, node.id),
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    color: node.bypass ? Colors.orange.withValues(alpha: 0.3) : LowerZoneColors.bgDeepest,
                    shape: BoxShape.circle,
                    border: Border.all(color: node.bypass ? Colors.orange : LowerZoneColors.border)),
                  child: Icon(node.bypass ? Icons.power_off : Icons.power, size: 9,
                    color: node.bypass ? Colors.orange : LowerZoneColors.textSecondary),
                ),
              ),
            ),
            if (trackId != null) Positioned(
              top: 4, left: 4,
              child: GestureDetector(
                onTap: () => DspChainProvider.instance.removeNode(trackId, node.id),
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(color: LowerZoneColors.bgDeepest, shape: BoxShape.circle,
                    border: Border.all(color: LowerZoneColors.border)),
                  child: const Icon(Icons.close, size: 9, color: LowerZoneColors.textMuted),
                ),
              ),
            ),
            const Positioned(
              bottom: 3, left: 0, right: 0,
              child: Center(child: Icon(Icons.drag_indicator, size: 10, color: LowerZoneColors.textTertiary)),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToProcessor(DspNodeType type) {
    final subTab = switch (type) {
      DspNodeType.eq => DawProcessSubTab.eq,
      DspNodeType.compressor => DawProcessSubTab.comp,
      DspNodeType.limiter => DawProcessSubTab.limiter,
      DspNodeType.reverb => DawProcessSubTab.reverb,
      DspNodeType.gate => DawProcessSubTab.gate,
      _ => null,
    };
    if (subTab != null) onNavigateToSubTab?.call(subTab);
  }

  IconData _nodeTypeIcon(DspNodeType type) {
    return switch (type) {
      DspNodeType.eq => Icons.equalizer,
      DspNodeType.compressor => Icons.compress,
      DspNodeType.limiter => Icons.volume_up,
      DspNodeType.gate => Icons.door_front_door,
      DspNodeType.expander => Icons.expand,
      DspNodeType.reverb => Icons.waves,
      DspNodeType.delay => Icons.timer,
      DspNodeType.saturation => Icons.whatshot,
      DspNodeType.deEsser => Icons.record_voice_over,
    };
  }

  Widget _buildChainActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: LowerZoneColors.bgSurface, borderRadius: BorderRadius.circular(4), 
          border: Border.all(color: LowerZoneColors.border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: LowerZoneColors.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildChainNode(String label, IconData icon, {bool isEndpoint = false}) {
    return Container(
      width: 80, height: 85,
      decoration: BoxDecoration(
        color: isEndpoint ? LowerZoneColors.bgDeepest : LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isEndpoint ? LowerZoneColors.border : LowerZoneColors.dawAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: isEndpoint ? LowerZoneColors.textMuted : LowerZoneColors.dawAccent),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, 
            color: isEndpoint ? LowerZoneColors.textMuted : LowerZoneColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildChainConnector() {
    return Container(
      width: 30, height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LowerZoneColors.dawAccent.withValues(alpha: 0.3),
            LowerZoneColors.dawAccent.withValues(alpha: 0.6),
            LowerZoneColors.dawAccent.withValues(alpha: 0.3),
          ],
        ),
      ),
    );
  }
}
