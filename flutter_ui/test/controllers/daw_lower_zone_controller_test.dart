/// DawLowerZoneController Tests (P0.4)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/lower_zone/daw_lower_zone_controller.dart';
import 'package:fluxforge_ui/widgets/lower_zone/lower_zone_types.dart';

void main() {
  group('DawLowerZoneController', () {
    late DawLowerZoneController controller;

    setUp(() {
      controller = DawLowerZoneController();
    });

    test('initializes with default state', () {
      expect(controller.superTab, DawSuperTab.edit); // Default changed from browse to edit
      expect(controller.isExpanded, true);
      expect(controller.height, kLowerZoneDefaultHeight);
    });

    test('setSuperTab changes tab', () {
      controller.setSuperTab(DawSuperTab.mix);

      expect(controller.superTab, DawSuperTab.mix);
    });

    test('toggle changes expand state', () {
      expect(controller.isExpanded, true);

      controller.toggle();
      expect(controller.isExpanded, false);

      controller.toggle();
      expect(controller.isExpanded, true);
    });

    test('setHeight clamps to min/max', () {
      controller.setHeight(100.0); // Below min
      expect(controller.height, kLowerZoneMinHeight);

      controller.setHeight(1000.0); // Above max
      expect(controller.height, kLowerZoneMaxHeight);

      controller.setHeight(300.0); // Valid
      expect(controller.height, 300.0);
    });

    test('setBrowseSubTab changes sub-tab', () {
      controller.setSuperTab(DawSuperTab.browse);
      controller.setBrowseSubTab(DawBrowseSubTab.presets);

      expect(controller.state.browseSubTab, DawBrowseSubTab.presets);
    });

    test('setMixSubTab changes sub-tab', () {
      controller.setSuperTab(DawSuperTab.mix);
      controller.setMixSubTab(DawMixSubTab.sends);

      expect(controller.state.mixSubTab, DawMixSubTab.sends);
    });

    test('toJson serializes state', () {
      controller.setSuperTab(DawSuperTab.process);
      controller.setHeight(400.0);

      final json = controller.toJson();

      expect(json['superTab'], 3); // DawSuperTab.process.index
      expect(json['height'], 400.0);
      expect(json['isExpanded'], true);
    });

    test('fromJson deserializes state', () {
      final json = {
        'superTab': 2, // DawSuperTab.mix
        'height': 350.0,
        'isExpanded': false,
      };

      controller.fromJson(json);

      expect(controller.superTab, DawSuperTab.mix);
      expect(controller.height, 350.0);
      expect(controller.isExpanded, false);
    });
  });
}
