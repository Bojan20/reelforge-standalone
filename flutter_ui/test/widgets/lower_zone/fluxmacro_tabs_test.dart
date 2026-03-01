/// FluxMacro Lower Zone Tab Registration Tests — FM-46
///
/// Tests that FluxMacro tabs are properly registered in BAKE super-tab
/// and that menu integration works.
@Tags(['widget'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/slot_lab/lower_zone/lower_zone_types.dart';

void main() {
  group('BAKE Sub-Tab Registration', () {
    test('BAKE has 8 sub-tabs (3 original + 5 FluxMacro)', () {
      expect(kBakeSubTabs.length, 8);
    });

    test('original sub-tabs preserved at indices 0-2', () {
      expect(kBakeSubTabs[0].id, 'batchExport');
      expect(kBakeSubTabs[1].id, 'validation');
      expect(kBakeSubTabs[2].id, 'package');
    });

    test('FluxMacro sub-tabs at indices 3-7', () {
      expect(kBakeSubTabs[3].id, 'macro');
      expect(kBakeSubTabs[4].id, 'monitor');
      expect(kBakeSubTabs[5].id, 'reports');
      expect(kBakeSubTabs[6].id, 'config');
      expect(kBakeSubTabs[7].id, 'history');
    });

    test('FluxMacro sub-tabs have correct labels', () {
      expect(kBakeSubTabs[3].label, 'Macro');
      expect(kBakeSubTabs[4].label, 'Monitor');
      expect(kBakeSubTabs[5].label, 'Reports');
      expect(kBakeSubTabs[6].label, 'Config');
      expect(kBakeSubTabs[7].label, 'History');
    });

    test('FluxMacro sub-tabs have shortcut keys 4-8', () {
      expect(kBakeSubTabs[3].shortcutKey, '4');
      expect(kBakeSubTabs[4].shortcutKey, '5');
      expect(kBakeSubTabs[5].shortcutKey, '6');
      expect(kBakeSubTabs[6].shortcutKey, '7');
      expect(kBakeSubTabs[7].shortcutKey, '8');
    });

    test('all sub-tabs have unique IDs', () {
      final ids = kBakeSubTabs.map((t) => t.id).toSet();
      expect(ids.length, kBakeSubTabs.length, reason: 'All IDs must be unique');
    });

    test('all sub-tabs have non-empty descriptions', () {
      for (final tab in kBakeSubTabs) {
        expect(tab.description, isNotEmpty, reason: '${tab.id} should have a description');
      }
    });
  });

  group('BakeSubTab Enum', () {
    test('has 8 values', () {
      expect(BakeSubTab.values.length, 8);
    });

    test('FluxMacro enum values exist', () {
      expect(BakeSubTab.values, containsAll([
        BakeSubTab.macro,
        BakeSubTab.monitor,
        BakeSubTab.reports,
        BakeSubTab.config,
        BakeSubTab.history,
      ]));
    });
  });

  group('Menu Items', () {
    test('FluxMacro entry exists in menu', () {
      final fluxmacroItem = kMenuItems.where((m) => m.id == 'fluxmacro');
      expect(fluxmacroItem.length, 1);
    });

    test('FluxMacro menu item has correct properties', () {
      final item = kMenuItems.firstWhere((m) => m.id == 'fluxmacro');
      expect(item.label, 'FluxMacro');
      expect(item.description, isNotEmpty);
    });

    test('menu items have 5 entries (4 original + FluxMacro)', () {
      expect(kMenuItems.length, 5);
    });

    test('all menu items have unique IDs', () {
      final ids = kMenuItems.map((m) => m.id).toSet();
      expect(ids.length, kMenuItems.length, reason: 'All menu IDs must be unique');
    });
  });

  group('getSubTabsForSuperTab', () {
    test('BAKE returns all 8 sub-tabs', () {
      final tabs = getSubTabsForSuperTab(SuperTab.bake);
      expect(tabs.length, 8);
    });

    test('BAKE tabs include FluxMacro panels', () {
      final tabs = getSubTabsForSuperTab(SuperTab.bake);
      final ids = tabs.map((t) => t.id).toList();
      expect(ids, contains('macro'));
      expect(ids, contains('monitor'));
      expect(ids, contains('reports'));
      expect(ids, contains('config'));
      expect(ids, contains('history'));
    });
  });
}
