import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/cortex_vision_service.dart';

/// Tests that CORTEX Vision regions produce usable RepaintBoundary keys
/// that can be wired into widget trees for visual capture.
void main() {
  group('CortexVision Wiring', () {
    late CortexVisionService vision;

    setUp(() {
      vision = CortexVisionService.instance;
      // Register the 5 standard regions
      for (final name in ['timeline', 'mixer', 'slot_lab', 'lower_zone', 'transport']) {
        vision.registerRegion(name: name, description: '$name region');
      }
    });

    tearDown(() {
      for (final name in ['timeline', 'mixer', 'slot_lab', 'lower_zone', 'transport']) {
        vision.unregisterRegion(name);
      }
    });

    testWidgets('RepaintBoundary wired with vision key renders correctly', (tester) async {
      final region = vision.getRegion('timeline')!;

      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: region.boundaryKey,
            child: const Scaffold(
              body: Center(child: Text('Timeline Content')),
            ),
          ),
        ),
      );

      // Verify RepaintBoundary is in the tree
      expect(find.byType(RepaintBoundary), findsWidgets);

      // Verify the key is accessible via context
      final context = region.boundaryKey.currentContext;
      expect(context, isNotNull, reason: 'Vision key must find its context in widget tree');

      // Verify we can find the RenderRepaintBoundary (what capture uses)
      final renderObject = context!.findRenderObject();
      expect(renderObject, isA<RenderRepaintBoundary>(),
          reason: 'Must find RenderRepaintBoundary for screenshot capture');
    });

    testWidgets('all 5 regions can be wired simultaneously', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final name in ['timeline', 'mixer', 'slot_lab', 'lower_zone', 'transport'])
                  RepaintBoundary(
                    key: vision.getRegion(name)!.boundaryKey,
                    child: SizedBox(height: 50, child: Text(name)),
                  ),
              ],
            ),
          ),
        ),
      );

      // All 5 regions should have valid render objects
      for (final name in ['timeline', 'mixer', 'slot_lab', 'lower_zone', 'transport']) {
        final region = vision.getRegion(name)!;
        final context = region.boundaryKey.currentContext;
        expect(context, isNotNull, reason: '$name region must be in widget tree');

        final render = context!.findRenderObject();
        expect(render, isA<RenderRepaintBoundary>(),
            reason: '$name must have RenderRepaintBoundary');
      }
    });

    testWidgets('root boundary key works alongside region keys', (tester) async {
      final timelineRegion = vision.getRegion('timeline')!;

      await tester.pumpWidget(
        RepaintBoundary(
          key: vision.rootBoundaryKey,
          child: MaterialApp(
            home: RepaintBoundary(
              key: timelineRegion.boundaryKey,
              child: const Scaffold(body: Text('Nested')),
            ),
          ),
        ),
      );

      // Both root and region should be accessible
      expect(vision.rootBoundaryKey.currentContext, isNotNull);
      expect(timelineRegion.boundaryKey.currentContext, isNotNull);

      // Both should yield RenderRepaintBoundary
      expect(
        vision.rootBoundaryKey.currentContext!.findRenderObject(),
        isA<RenderRepaintBoundary>(),
      );
      expect(
        timelineRegion.boundaryKey.currentContext!.findRenderObject(),
        isA<RenderRepaintBoundary>(),
      );
    });

    test('unregistered region returns null key gracefully', () {
      final key = vision.getRegion('nonexistent')?.boundaryKey;
      expect(key, isNull);
    });

    testWidgets('capture returns null when boundary not in tree', (tester) async {
      // Region registered but NOT in widget tree
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      // capture should gracefully return null (not crash)
      final snapshot = await vision.capture('timeline');
      expect(snapshot, isNull);
    });
  });
}
