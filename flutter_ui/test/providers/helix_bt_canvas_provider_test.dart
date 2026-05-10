// Tests for `HelixBtCanvasProvider` (Sprint 14 Faza 4.D.2).
//
// Audit-flagged 0-test-coverage for the Behavior Tree canvas provider
// (cycle detection, connection guards, persistence).  Coverage pokriva:
//   • node CRUD (add / move / delete cascades edges + selection clear)
//   • edge CRUD (self-loop reject, duplicate reject, cycle reject)
//   • selection state
//   • bulk operations (clear)
//   • JSON serialization roundtrip (toJsonString / loadFromJson)
//   • notifyListeners semantics (changed → notify, no-op → silent)

import 'package:flutter/material.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/slot_lab/helix_bt_canvas_provider.dart';

void main() {
  group('HelixBtCanvasProvider — node CRUD', () {
    test('addNode assigns monotonic ids and increments nodeCount', () {
      final p = HelixBtCanvasProvider();
      final a = p.addNode('Composite', 'Selector');
      final b = p.addNode('Action', 'Play');
      expect(a, 'bt_node_0');
      expect(b, 'bt_node_1');
      expect(p.nodeCount, 2);
      expect(p.isDirty, true);
    });

    test('addNode at custom position stores it verbatim', () {
      final p = HelixBtCanvasProvider();
      final id = p.addNode('Action', 'Play', position: const Offset(42, 99));
      expect(p.nodes.firstWhere((n) => n.id == id).position,
          const Offset(42, 99));
    });

    test('addNode without position auto-arranges in 5-column grid', () {
      final p = HelixBtCanvasProvider();
      final ids = <String>[];
      for (var i = 0; i < 7; i++) {
        ids.add(p.addNode('A', 'n$i'));
      }
      // Read positions AFTER all adds so test isn't sensitive to internal
      // ordering nuances of `firstWhere` on a mutating List.
      final positions = ids.map((id) =>
          p.nodes.firstWhere((n) => n.id == id).position).toList();
      // 5 per row; 6th node wraps to row 2 (y = 80 + 90)
      expect(positions[0].dy, 80.0);
      expect(positions[4].dy, 80.0);
      expect(positions[5].dy, 170.0);
      expect(positions[6].dy, 170.0);
    });

    test('moveNode shifts position by delta', () {
      final p = HelixBtCanvasProvider();
      final id = p.addNode('A', 'n', position: const Offset(10, 10));
      p.moveNode(id, const Offset(5, -3));
      expect(p.nodes.first.position, const Offset(15, 7));
    });

    test('moveNode on unknown id is a no-op', () {
      final p = HelixBtCanvasProvider();
      p.addNode('A', 'n', position: const Offset(10, 10));
      p.moveNode('nonexistent', const Offset(1, 1));
      expect(p.nodes.first.position, const Offset(10, 10));
    });

    test('deleteNode cascades edges that touch the node', () {
      final p = HelixBtCanvasProvider();
      final a = p.addNode('A', 'a');
      final b = p.addNode('A', 'b');
      final c = p.addNode('A', 'c');
      p.connect(a, b);
      p.connect(b, c);
      expect(p.edgeCount, 2);

      p.deleteNode(b);
      expect(p.nodeCount, 2);
      expect(p.edgeCount, 0,
          reason: 'all edges touching deleted node must be cascaded');
    });

    test('deleteNode clears selection if deleted node was selected', () {
      final p = HelixBtCanvasProvider();
      final id = p.addNode('A', 'n');
      p.selectNode(id);
      expect(p.selectedNodeId, id);
      p.deleteNode(id);
      expect(p.selectedNodeId, isNull);
    });
  });

  group('HelixBtCanvasProvider — edge CRUD', () {
    test('connect rejects self-loop', () {
      final p = HelixBtCanvasProvider();
      final a = p.addNode('A', 'a');
      expect(p.connect(a, a), isFalse);
      expect(p.edgeCount, 0);
    });

    test('connect rejects duplicate edge', () {
      final p = HelixBtCanvasProvider();
      final a = p.addNode('A', 'a');
      final b = p.addNode('A', 'b');
      expect(p.connect(a, b), isTrue);
      expect(p.connect(a, b), isFalse);
      expect(p.edgeCount, 1);
    });

    test('connect rejects edge that would create a cycle', () {
      final p = HelixBtCanvasProvider();
      final a = p.addNode('A', 'a');
      final b = p.addNode('A', 'b');
      final c = p.addNode('A', 'c');
      expect(p.connect(a, b), isTrue);
      expect(p.connect(b, c), isTrue);
      // c → a would close a → b → c → a cycle
      expect(p.connect(c, a), isFalse,
          reason: 'BFS cycle detector must reject closing edge');
      expect(p.edgeCount, 2);
    });

    test('connect allows multi-parent (DAG, not tree)', () {
      // Two distinct sources both flowing into c: a → c, b → c.
      // This is NOT a cycle; cycle detector must allow it.
      final p = HelixBtCanvasProvider();
      final a = p.addNode('A', 'a');
      final b = p.addNode('A', 'b');
      final c = p.addNode('A', 'c');
      expect(p.connect(a, c), isTrue);
      expect(p.connect(b, c), isTrue);
      expect(p.edgeCount, 2);
    });

    test('disconnect removes the edge', () {
      final p = HelixBtCanvasProvider();
      final a = p.addNode('A', 'a');
      final b = p.addNode('A', 'b');
      p.connect(a, b);
      p.disconnect(a, b);
      expect(p.edgeCount, 0);
    });
  });

  group('HelixBtCanvasProvider — selection', () {
    test('selectNode sets selected id', () {
      final p = HelixBtCanvasProvider();
      final id = p.addNode('A', 'n');
      p.selectNode(id);
      expect(p.selectedNodeId, id);
    });

    test('selectNode(null) deselects', () {
      final p = HelixBtCanvasProvider();
      final id = p.addNode('A', 'n');
      p.selectNode(id);
      p.selectNode(null);
      expect(p.selectedNodeId, isNull);
    });

    test('selectNode same id is a no-op (no notify)', () {
      final p = HelixBtCanvasProvider();
      final id = p.addNode('A', 'n');
      p.selectNode(id);

      int notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.selectNode(id); // same id — should NOT notify
      expect(notifyCount, 0);
    });
  });

  group('HelixBtCanvasProvider — bulk ops + notify semantics', () {
    test('clear empties nodes and edges', () {
      final p = HelixBtCanvasProvider();
      final a = p.addNode('A', 'a');
      final b = p.addNode('A', 'b');
      p.connect(a, b);
      p.selectNode(a);
      expect(p.nodeCount, 2);

      p.clear();
      expect(p.nodeCount, 0);
      expect(p.edgeCount, 0);
      expect(p.selectedNodeId, isNull);
    });

    test('addNode triggers notifyListeners', () {
      final p = HelixBtCanvasProvider();
      int notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.addNode('A', 'n');
      expect(notifyCount, 1);
    });

    test('failed connect does NOT notify', () {
      final p = HelixBtCanvasProvider();
      final a = p.addNode('A', 'a');
      int notifyCount = 0;
      p.addListener(() => notifyCount++);
      p.connect(a, a); // self-loop → rejected
      expect(notifyCount, 0,
          reason: 'rejected operations should not fire change notification');
    });
  });

  group('HelixBtCanvasProvider — JSON roundtrip', () {
    test('toJsonString → loadFromJson preserves nodes + edges', () {
      final p1 = HelixBtCanvasProvider();
      final a = p1.addNode('Composite', 'Selector',
          position: const Offset(50, 60));
      final b = p1.addNode('Action', 'Play',
          position: const Offset(150, 60));
      p1.connect(a, b);

      final json = p1.toJsonString();
      final p2 = HelixBtCanvasProvider();
      p2.loadFromJson(json);

      expect(p2.nodeCount, 2);
      expect(p2.edgeCount, 1);
      expect(p2.nodes.map((n) => n.name).toList(), ['Selector', 'Play']);
      // Position roundtrip — Offset.fromJson decodes to (50, 60) and (150, 60)
      final loadedA = p2.nodes.firstWhere((n) => n.name == 'Selector');
      expect(loadedA.position, const Offset(50, 60));
    });

    test('loadFromJson clears existing state', () {
      final p = HelixBtCanvasProvider();
      p.addNode('A', 'stale');
      // Fresh, minimal valid JSON
      p.loadFromJson('{"nodes": [], "edges": []}');
      expect(p.nodeCount, 0);
    });

    test('loadFromJson on malformed input is a safe no-op', () {
      final p = HelixBtCanvasProvider();
      p.addNode('A', 'existing');
      // Intentional garbage — provider should not crash
      p.loadFromJson('}}}NOT VALID{{{');
      // State unchanged (or cleared — both are acceptable; key is no panic)
      expect(p.nodes.isEmpty || p.nodes.first.name == 'existing', isTrue);
    });
  });
}
