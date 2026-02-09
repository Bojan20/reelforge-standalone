// Lower Zone Controller Unit Tests
//
// Tests for LowerZoneController functionality:
// - Tab switching (switchTo, setTab)
// - Expand/collapse states
// - Height management (setHeight, adjustHeight)
// - Category management (M3 Sprint features)
// - Keyboard shortcuts
// - Serialization (toJson/fromJson)
//
// P1.20: Controller unit tests for SlotLab Lower Zone

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/controllers/slot_lab/lower_zone_controller.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // P1.20: LOWER ZONE CATEGORY ENUM TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('LowerZoneCategory', () {
    test('should have expected categories', () {
      expect(LowerZoneCategory.values.length, 4);
      expect(LowerZoneCategory.audio, isNotNull);
      expect(LowerZoneCategory.routing, isNotNull);
      expect(LowerZoneCategory.debug, isNotNull);
      expect(LowerZoneCategory.advanced, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.20: LOWER ZONE TAB ENUM TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('LowerZoneTab', () {
    test('should have expected tabs', () {
      expect(LowerZoneTab.values.length, 8);
      expect(LowerZoneTab.timeline, isNotNull);
      expect(LowerZoneTab.commandBuilder, isNotNull);
      expect(LowerZoneTab.eventList, isNotNull);
      expect(LowerZoneTab.meters, isNotNull);
      expect(LowerZoneTab.dspCompressor, isNotNull);
      expect(LowerZoneTab.dspLimiter, isNotNull);
      expect(LowerZoneTab.dspGate, isNotNull);
      expect(LowerZoneTab.dspReverb, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.20: TAB CONFIG TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('LowerZoneTabConfig', () {
    test('should have configs for all tabs', () {
      for (final tab in LowerZoneTab.values) {
        final config = kLowerZoneTabConfigs[tab];
        expect(config, isNotNull, reason: 'Missing config for $tab');
        expect(config!.label, isNotEmpty);
        expect(config.shortcutKey, isNotEmpty);
      }
    });

    test('should have unique shortcut keys', () {
      final keys = kLowerZoneTabConfigs.values.map((c) => c.shortcutKey).toSet();
      expect(
        keys.length,
        kLowerZoneTabConfigs.length,
        reason: 'Duplicate shortcut keys found',
      );
    });

    test('should have category assigned to each tab', () {
      for (final config in kLowerZoneTabConfigs.values) {
        expect(LowerZoneCategory.values.contains(config.category), true);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.20: CATEGORY CONFIG TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('LowerZoneCategoryConfig', () {
    test('should have configs for all categories', () {
      for (final category in LowerZoneCategory.values) {
        final config = kLowerZoneCategoryConfigs[category];
        expect(config, isNotNull, reason: 'Missing config for $category');
        expect(config!.label, isNotEmpty);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.20: CATEGORY HELPER FUNCTIONS TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Category Helper Functions', () {
    test('getTabsInCategory should return tabs for audio category', () {
      final audioTabs = getTabsInCategory(LowerZoneCategory.audio);
      expect(audioTabs, isNotEmpty);
      for (final config in audioTabs) {
        expect(config.category, LowerZoneCategory.audio);
      }
    });

    test('getTabsInCategory should return tabs for debug category', () {
      final debugTabs = getTabsInCategory(LowerZoneCategory.debug);
      expect(debugTabs, isNotEmpty);
      expect(debugTabs.any((t) => t.tab == LowerZoneTab.timeline), true);
    });

    test('getTabsByCategory should group all tabs', () {
      final grouped = getTabsByCategory();
      expect(grouped.keys.length, LowerZoneCategory.values.length);

      int totalTabs = 0;
      for (final tabs in grouped.values) {
        totalTabs += tabs.length;
      }
      expect(totalTabs, kLowerZoneTabConfigs.length);
    });

    test('getCategoryForTab should return correct category', () {
      expect(
        getCategoryForTab(LowerZoneTab.timeline),
        LowerZoneCategory.debug,
      );
      expect(
        getCategoryForTab(LowerZoneTab.meters),
        LowerZoneCategory.audio,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.20: CONSTANTS TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Constants', () {
    test('should have valid height constraints', () {
      expect(kLowerZoneMinHeight, greaterThan(0));
      expect(kLowerZoneMaxHeight, greaterThan(kLowerZoneMinHeight));
      expect(kLowerZoneDefaultHeight, greaterThanOrEqualTo(kLowerZoneMinHeight));
      expect(kLowerZoneDefaultHeight, lessThanOrEqualTo(kLowerZoneMaxHeight));
    });

    test('header height should be positive', () {
      expect(kLowerZoneHeaderHeight, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.20: LOWER ZONE CONTROLLER TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('LowerZoneController', () {
    late LowerZoneController controller;

    setUp(() {
      controller = LowerZoneController();
    });

    tearDown(() {
      controller.dispose();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Initialization tests
    // ─────────────────────────────────────────────────────────────────────────

    group('Initialization', () {
      test('should have default values', () {
        expect(controller.activeTab, LowerZoneTab.timeline);
        expect(controller.isExpanded, true);
        expect(controller.height, kLowerZoneDefaultHeight);
      });

      test('should accept custom initial values', () {
        final custom = LowerZoneController(
          initialTab: LowerZoneTab.meters,
          initialExpanded: false,
          initialHeight: 300,
        );

        expect(custom.activeTab, LowerZoneTab.meters);
        expect(custom.isExpanded, false);
        expect(custom.height, 300);

        custom.dispose();
      });

      test('should clamp initial height', () {
        final tooSmall = LowerZoneController(initialHeight: 10);
        expect(tooSmall.height, kLowerZoneMinHeight);
        tooSmall.dispose();

        final tooLarge = LowerZoneController(initialHeight: 1000);
        expect(tooLarge.height, kLowerZoneMaxHeight);
        tooLarge.dispose();
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Tab switching tests
    // ─────────────────────────────────────────────────────────────────────────

    group('Tab Switching', () {
      test('switchTo should change active tab', () {
        controller.switchTo(LowerZoneTab.meters);
        expect(controller.activeTab, LowerZoneTab.meters);
      });

      test('switchTo same tab when expanded should collapse', () {
        expect(controller.isExpanded, true);
        controller.switchTo(LowerZoneTab.timeline); // Same as default
        expect(controller.isExpanded, false);
      });

      test('switchTo should expand if collapsed', () {
        controller.collapse();
        expect(controller.isExpanded, false);

        controller.switchTo(LowerZoneTab.meters);
        expect(controller.isExpanded, true);
        expect(controller.activeTab, LowerZoneTab.meters);
      });

      test('setTab should change tab without toggle', () {
        expect(controller.activeTab, LowerZoneTab.timeline);
        expect(controller.isExpanded, true);

        controller.setTab(LowerZoneTab.timeline); // Same tab
        expect(controller.isExpanded, true); // Should NOT collapse

        controller.setTab(LowerZoneTab.meters);
        expect(controller.activeTab, LowerZoneTab.meters);
      });

      test('isTabActive should return correct state', () {
        expect(controller.isTabActive(LowerZoneTab.timeline), true);
        expect(controller.isTabActive(LowerZoneTab.meters), false);

        controller.switchTo(LowerZoneTab.meters);
        expect(controller.isTabActive(LowerZoneTab.timeline), false);
        expect(controller.isTabActive(LowerZoneTab.meters), true);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Expand/Collapse tests
    // ─────────────────────────────────────────────────────────────────────────

    group('Expand/Collapse', () {
      test('toggle should switch state', () {
        expect(controller.isExpanded, true);
        controller.toggle();
        expect(controller.isExpanded, false);
        controller.toggle();
        expect(controller.isExpanded, true);
      });

      test('expand should set expanded state', () {
        controller.collapse();
        expect(controller.isExpanded, false);
        controller.expand();
        expect(controller.isExpanded, true);
      });

      test('expand when already expanded should be no-op', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.expand();
        expect(notified, false); // No change, no notification
      });

      test('collapse should set collapsed state', () {
        expect(controller.isExpanded, true);
        controller.collapse();
        expect(controller.isExpanded, false);
      });

      test('collapse when already collapsed should be no-op', () {
        controller.collapse();

        var notified = false;
        controller.addListener(() => notified = true);

        controller.collapse();
        expect(notified, false); // No change, no notification
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Height management tests
    // ─────────────────────────────────────────────────────────────────────────

    group('Height Management', () {
      test('setHeight should update height', () {
        controller.setHeight(300);
        expect(controller.height, 300);
      });

      test('setHeight should clamp to min', () {
        controller.setHeight(10);
        expect(controller.height, kLowerZoneMinHeight);
      });

      test('setHeight should clamp to max', () {
        controller.setHeight(1000);
        expect(controller.height, kLowerZoneMaxHeight);
      });

      test('setHeight same value should be no-op', () {
        controller.setHeight(300);

        var notified = false;
        controller.addListener(() => notified = true);

        controller.setHeight(300);
        expect(notified, false);
      });

      test('adjustHeight should add delta', () {
        final initial = controller.height;
        controller.adjustHeight(50);
        expect(controller.height, initial + 50);
      });

      test('adjustHeight should respect limits', () {
        controller.setHeight(kLowerZoneMaxHeight);
        controller.adjustHeight(100);
        expect(controller.height, kLowerZoneMaxHeight);

        controller.setHeight(kLowerZoneMinHeight);
        controller.adjustHeight(-100);
        expect(controller.height, kLowerZoneMinHeight);
      });

      test('totalHeight should include header when expanded', () {
        // totalHeight = content height + header (36) + sub-tab row (28)
        expect(
          controller.totalHeight,
          controller.height + kLowerZoneHeaderHeight + 28,
        );
      });

      test('totalHeight should be header only when collapsed', () {
        controller.collapse();
        expect(controller.totalHeight, kLowerZoneHeaderHeight);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Tab config getters tests
    // ─────────────────────────────────────────────────────────────────────────

    group('Tab Config Getters', () {
      test('activeTabConfig should return config for active tab', () {
        expect(controller.activeTabConfig.tab, LowerZoneTab.timeline);

        controller.switchTo(LowerZoneTab.dspCompressor);
        expect(controller.activeTabConfig.tab, LowerZoneTab.dspCompressor);
      });

      test('tabs should return all tab configs', () {
        expect(controller.tabs.length, LowerZoneTab.values.length);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Category management tests (M3 Sprint - P1)
    // ─────────────────────────────────────────────────────────────────────────

    group('Category Management', () {
      test('should have advanced collapsed by default', () {
        expect(controller.isCategoryCollapsed(LowerZoneCategory.advanced), true);
        expect(controller.isCategoryCollapsed(LowerZoneCategory.audio), false);
      });

      test('categoryCollapseStates should return all states', () {
        final states = controller.categoryCollapseStates;
        expect(states.length, LowerZoneCategory.values.length);
        expect(states[LowerZoneCategory.advanced], true);
      });

      test('tabsInCategory should return tabs', () {
        final audioTabs = controller.tabsInCategory(LowerZoneCategory.audio);
        expect(audioTabs, isNotEmpty);
      });

      test('categoryConfigs should return all configs', () {
        expect(
          controller.categoryConfigs.length,
          LowerZoneCategory.values.length,
        );
      });

      test('getCategoryConfig should return correct config', () {
        final config = controller.getCategoryConfig(LowerZoneCategory.audio);
        expect(config.category, LowerZoneCategory.audio);
        expect(config.label, 'Audio');
      });

      test('activeTabCategory should return category for active tab', () {
        controller.switchTo(LowerZoneTab.timeline);
        expect(controller.activeTabCategory, LowerZoneCategory.debug);

        controller.switchTo(LowerZoneTab.meters);
        expect(controller.activeTabCategory, LowerZoneCategory.audio);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Notification tests
    // ─────────────────────────────────────────────────────────────────────────

    group('Notifications', () {
      test('should notify on switchTo', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.switchTo(LowerZoneTab.meters);
        expect(notified, true);
      });

      test('should notify on toggle', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.toggle();
        expect(notified, true);
      });

      test('should notify on setHeight change', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.setHeight(300);
        expect(notified, true);
      });
    });
  });
}
