// state_machine_graph_widget.dart — Visual State Machine
import 'package:flutter/material.dart';

class StateMachineNode {
  final String id;
  final String label;
  final Offset position;
  final bool isCurrent;
  const StateMachineNode({required this.id, required this.label, required this.position, this.isCurrent = false});
}

class StateMachineEdge {
  final String from;
  final String to;
  final String? condition;
  const StateMachineEdge({required this.from, required this.to, this.condition});
}

class StateMachineGraphWidget extends StatelessWidget {
  final List<StateMachineNode> nodes;
  final List<StateMachineEdge> edges;
  final void Function(String nodeId)? onNodeTap;
  
  const StateMachineGraphWidget({super.key, required this.nodes, required this.edges, this.onNodeTap});
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StateMachinePainter(nodes: nodes, edges: edges),
      child: GestureDetector(
        onTapDown: (details) {
          for (final node in nodes) {
            final rect = Rect.fromCenter(center: node.position, width: 100, height: 50);
            if (rect.contains(details.localPosition)) {
              onNodeTap?.call(node.id);
              break;
            }
          }
        },
      ),
    );
  }
}

class _StateMachinePainter extends CustomPainter {
  final List<StateMachineNode> nodes;
  final List<StateMachineEdge> edges;
  _StateMachinePainter({required this.nodes, required this.edges});
  
  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final from = nodes.firstWhere((n) => n.id == edge.from, orElse: () => nodes.first);
      final to = nodes.firstWhere((n) => n.id == edge.to, orElse: () => nodes.first);
      canvas.drawLine(from.position, to.position, Paint()..color = Colors.white54..strokeWidth = 2);
    }
    for (final node in nodes) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: node.position, width: 100, height: 50), const Radius.circular(8)), Paint()..color = node.isCurrent ? const Color(0xFF4A9EFF) : const Color(0xFF242430));
      final textPainter = TextPainter(text: TextSpan(text: node.label, style: const TextStyle(color: Colors.white, fontSize: 12)), textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, node.position - Offset(textPainter.width / 2, textPainter.height / 2));
    }
  }
  
  @override
  bool shouldRepaint(_StateMachinePainter old) => nodes != old.nodes || edges != old.edges;
}
