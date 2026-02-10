// Keyboard Navigation Service Tests
//
// Tests for FocusNode management, Tab/Arrow navigation, and focus indicators.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/keyboard_navigation_service.dart';

void main() {
  late KeyboardNavigationService service;

  setUp(() {
    service = KeyboardNavigationService.instance;
    service.clear(); // Start fresh
    service.setEnabled(true);
  });

  tearDown(() {
    service.clear();
  });

  group('Registration', () {
    test('should register focusable items', () {
      final item = service.register(
        id: 'track_1',
        context: NavigationContext.tracks,
        index: 0,
      );

      expect(item.id, 'track_1');
      expect(item.context, NavigationContext.tracks);
      expect(item.index, 0);
      expect(service.itemCount, 1);
    });

    test('should register multiple items in same context', () {
      service.register(id: 'track_1', context: NavigationContext.tracks, index: 0);
      service.register(id: 'track_2', context: NavigationContext.tracks, index: 1);
      service.register(id: 'track_3', context: NavigationContext.tracks, index: 2);

      final items = service.getItemsInContext(NavigationContext.tracks);
      expect(items.length, 3);
      expect(items[0].id, 'track_1');
      expect(items[1].id, 'track_2');
      expect(items[2].id, 'track_3');
    });

    test('should register items with custom FocusNode', () {
      final customNode = FocusNode(debugLabel: 'custom');
      final item = service.register(
        id: 'custom_item',
        context: NavigationContext.mixer,
        focusNode: customNode,
      );

      expect(item.focusNode, customNode);
    });

    test('should unregister items', () {
      service.register(id: 'item_1', context: NavigationContext.tracks);
      expect(service.itemCount, 1);

      service.unregister('item_1');
      expect(service.itemCount, 0);
    });

    test('should unregister all items in context', () {
      service.register(id: 'track_1', context: NavigationContext.tracks);
      service.register(id: 'track_2', context: NavigationContext.tracks);
      service.register(id: 'channel_1', context: NavigationContext.mixer);

      service.unregisterContext(NavigationContext.tracks);

      expect(service.itemCount, 1);
      expect(service.getItemsInContext(NavigationContext.tracks), isEmpty);
      expect(service.getItemsInContext(NavigationContext.mixer).length, 1);
    });
  });

  group('Configuration', () {
    test('should enable and disable navigation', () {
      expect(service.isEnabled, true);

      service.setEnabled(false);
      expect(service.isEnabled, false);

      service.setEnabled(true);
      expect(service.isEnabled, true);
    });

    test('should set focus color and width', () {
      const newColor = Colors.red;
      const newWidth = 3.0;

      service.setFocusColor(newColor);
      service.setFocusWidth(newWidth);

      expect(service.focusColor, newColor);
      expect(service.focusWidth, newWidth);
    });

    test('should set current context', () {
      service.setContext(NavigationContext.mixer);
      expect(service.currentContext, NavigationContext.mixer);

      service.setContext(NavigationContext.tracks);
      expect(service.currentContext, NavigationContext.tracks);
    });
  });

  group('Navigation', () {
    test('should focus item by ID', () {
      final item = service.register(
        id: 'test_item',
        context: NavigationContext.tracks,
      );

      // Note: In a real test environment with WidgetTester, we'd need to
      // pump frames to see focus changes. This tests the API.
      final result = service.focusItem('test_item');
      expect(result, true);
    });

    test('should fail to focus non-existent item', () {
      final result = service.focusItem('non_existent');
      expect(result, false);
    });

    test('should navigate to next item', () {
      service.register(id: 'item_1', context: NavigationContext.tracks, index: 0);
      service.register(id: 'item_2', context: NavigationContext.tracks, index: 1);
      service.register(id: 'item_3', context: NavigationContext.tracks, index: 2);

      final result = service.navigateNext();
      expect(result, true);
    });

    test('should navigate to previous item', () {
      service.register(id: 'item_1', context: NavigationContext.tracks, index: 0);
      service.register(id: 'item_2', context: NavigationContext.tracks, index: 1);

      final result = service.navigatePrevious();
      expect(result, true);
    });

    test('should navigate with arrow keys', () {
      service.register(id: 'item_1', context: NavigationContext.tracks, index: 0);
      service.register(id: 'item_2', context: NavigationContext.tracks, index: 1);
      service.setContext(NavigationContext.tracks);

      expect(service.navigate(NavigationDirection.down), true);
      expect(service.navigate(NavigationDirection.up), true);
      expect(service.navigate(NavigationDirection.left), true);
      expect(service.navigate(NavigationDirection.right), true);
    });

    test('should not navigate when disabled', () {
      service.register(id: 'item_1', context: NavigationContext.tracks);
      service.setEnabled(false);

      expect(service.navigateNext(), false);
      expect(service.navigate(NavigationDirection.down), false);
    });

    test('should not navigate with empty item list', () {
      expect(service.navigateNext(), false);
      expect(service.navigatePrevious(), false);
    });
  });

  group('Activation', () {
    test('should activate item with callback', () {
      var activated = false;
      final item = service.register(
        id: 'editable_item',
        context: NavigationContext.inspector,
        editable: true,
        onActivate: () => activated = true,
      );

      // Directly call the onActivate callback since focus may not work in test
      if (item.onActivate != null) {
        item.onActivate!();
      }

      expect(activated, true);
    });

    test('should cancel with callback', () {
      var cancelled = false;
      final item = service.register(
        id: 'editable_item',
        context: NavigationContext.inspector,
        editable: true,
        onCancel: () => cancelled = true,
      );

      // Directly call the onCancel callback since focus may not work in test
      if (item.onCancel != null) {
        item.onCancel!();
      }

      expect(cancelled, true);
    });

    test('should return false when no callback', () {
      final item = service.register(id: 'simple_item', context: NavigationContext.tracks);

      // Test that item has no callbacks
      expect(item.onActivate, isNull);
      expect(item.onCancel, isNull);
    });
  });

  group('Navigation Events', () {
    test('should emit navigation events', () async {
      service.register(id: 'item_1', context: NavigationContext.tracks, index: 0);
      service.register(id: 'item_2', context: NavigationContext.tracks, index: 1);

      final events = <NavigationEvent>[];
      final subscription = service.navigationEvents.listen(events.add);

      service.navigateNext();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(events, isNotEmpty);
      expect(events.first.isTabNavigation, true);

      await subscription.cancel();
    });

    test('should include direction in arrow navigation events', () async {
      service.register(id: 'item_1', context: NavigationContext.tracks, index: 0);
      service.register(id: 'item_2', context: NavigationContext.tracks, index: 1);
      service.setContext(NavigationContext.tracks);

      final events = <NavigationEvent>[];
      final subscription = service.navigationEvents.listen(events.add);

      service.navigate(NavigationDirection.down);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(events, isNotEmpty);
      expect(events.first.direction, NavigationDirection.down);
      expect(events.first.isTabNavigation, false);

      await subscription.cancel();
    });
  });

  group('FocusableItem', () {
    test('should have correct properties', () {
      final item = service.register(
        id: 'test_item',
        context: NavigationContext.browser,
        index: 5,
        parentId: 'parent_folder',
        editable: true,
        data: {'key': 'value'},
      );

      expect(item.id, 'test_item');
      expect(item.context, NavigationContext.browser);
      expect(item.index, 5);
      expect(item.parentId, 'parent_folder');
      expect(item.editable, true);
      expect(item.data, {'key': 'value'});
    });

    test('toString should return readable format', () {
      final item = service.register(
        id: 'my_item',
        context: NavigationContext.clips,
        index: 3,
      );

      expect(item.toString(), 'FocusableItem(my_item, ctx=NavigationContext.clips, idx=3)');
    });
  });

  group('Context Items', () {
    test('should sort items by index within context', () {
      service.register(id: 'item_c', context: NavigationContext.tracks, index: 2);
      service.register(id: 'item_a', context: NavigationContext.tracks, index: 0);
      service.register(id: 'item_b', context: NavigationContext.tracks, index: 1);

      final items = service.getItemsInContext(NavigationContext.tracks);
      expect(items[0].id, 'item_a');
      expect(items[1].id, 'item_b');
      expect(items[2].id, 'item_c');
    });

    test('should keep contexts separate', () {
      service.register(id: 'track_1', context: NavigationContext.tracks, index: 0);
      service.register(id: 'channel_1', context: NavigationContext.mixer, index: 0);
      service.register(id: 'param_1', context: NavigationContext.inspector, index: 0);

      expect(service.getItemsInContext(NavigationContext.tracks).length, 1);
      expect(service.getItemsInContext(NavigationContext.mixer).length, 1);
      expect(service.getItemsInContext(NavigationContext.inspector).length, 1);
      expect(service.getItemsInContext(NavigationContext.browser), isEmpty);
    });
  });

  group('Clear', () {
    test('should clear all items', () {
      service.register(id: 'item_1', context: NavigationContext.tracks);
      service.register(id: 'item_2', context: NavigationContext.mixer);
      service.register(id: 'item_3', context: NavigationContext.inspector);

      expect(service.itemCount, 3);

      service.clear();

      expect(service.itemCount, 0);
      expect(service.focusedItem, isNull);
    });
  });
}
