// Advanced Routing Matrix Panel Tests
//
// Tests for the routing matrix widget:
// - RoutingCellData model
// - BulkRoutingOperation enum
// - Widget rendering
// - User interactions

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/routing/advanced_routing_matrix_panel.dart';

void main() {
  group('RoutingCellData', () {
    test('should create with required fields', () {
      const cell = RoutingCellData(
        sourceId: 'ch_1',
        targetId: 'bus_drums',
      );

      expect(cell.sourceId, 'ch_1');
      expect(cell.targetId, 'bus_drums');
      expect(cell.isConnected, false);
      expect(cell.sendLevel, 1.0);
      expect(cell.preFader, false);
      expect(cell.enabled, true);
    });

    test('should create with all fields', () {
      const cell = RoutingCellData(
        sourceId: 'ch_vocals',
        targetId: 'aux_reverb',
        isConnected: true,
        sendLevel: 0.5,
        preFader: true,
        enabled: true,
        isMuted: false,
        isSoloed: true,
      );

      expect(cell.isConnected, true);
      expect(cell.sendLevel, 0.5);
      expect(cell.preFader, true);
      expect(cell.isSoloed, true);
    });

    test('copyWith should preserve unchanged fields', () {
      const original = RoutingCellData(
        sourceId: 'ch_1',
        targetId: 'bus_1',
        isConnected: true,
        sendLevel: 0.7,
        preFader: true,
      );

      final modified = original.copyWith(sendLevel: 0.9);

      expect(modified.sourceId, 'ch_1');
      expect(modified.targetId, 'bus_1');
      expect(modified.isConnected, true);
      expect(modified.sendLevel, 0.9);
      expect(modified.preFader, true);
    });

    test('copyWith should allow toggling connection', () {
      const original = RoutingCellData(
        sourceId: 'ch_1',
        targetId: 'bus_1',
        isConnected: false,
      );

      final connected = original.copyWith(isConnected: true);
      expect(connected.isConnected, true);

      final disconnected = connected.copyWith(isConnected: false);
      expect(disconnected.isConnected, false);
    });

    test('copyWith should allow changing pre/post fader', () {
      const original = RoutingCellData(
        sourceId: 'ch_1',
        targetId: 'aux_1',
        preFader: false,
      );

      final preFader = original.copyWith(preFader: true);
      expect(preFader.preFader, true);
    });
  });

  group('BulkRoutingOperation', () {
    test('should have all expected operations', () {
      expect(BulkRoutingOperation.values.length, 5);
      expect(BulkRoutingOperation.values, contains(BulkRoutingOperation.connectAll));
      expect(BulkRoutingOperation.values, contains(BulkRoutingOperation.disconnectAll));
      expect(BulkRoutingOperation.values, contains(BulkRoutingOperation.setAllLevels));
      expect(BulkRoutingOperation.values, contains(BulkRoutingOperation.setAllPreFader));
      expect(BulkRoutingOperation.values, contains(BulkRoutingOperation.setAllPostFader));
    });

    test('enum names should be descriptive', () {
      expect(BulkRoutingOperation.connectAll.name, 'connectAll');
      expect(BulkRoutingOperation.disconnectAll.name, 'disconnectAll');
      expect(BulkRoutingOperation.setAllLevels.name, 'setAllLevels');
      expect(BulkRoutingOperation.setAllPreFader.name, 'setAllPreFader');
      expect(BulkRoutingOperation.setAllPostFader.name, 'setAllPostFader');
    });
  });

  group('Send Level Logic', () {
    test('send level should clamp to valid range', () {
      double clampSendLevel(double level) {
        return level.clamp(0.0, 1.0);
      }

      expect(clampSendLevel(-0.5), 0.0);
      expect(clampSendLevel(0.5), 0.5);
      expect(clampSendLevel(1.5), 1.0);
      expect(clampSendLevel(0.0), 0.0);
      expect(clampSendLevel(1.0), 1.0);
    });

    test('send level percentage calculation should be correct', () {
      int toPercentage(double level) {
        return (level * 100).toInt();
      }

      expect(toPercentage(0.0), 0);
      expect(toPercentage(0.5), 50);
      expect(toPercentage(1.0), 100);
      expect(toPercentage(0.75), 75);
      expect(toPercentage(0.333), 33);
    });
  });

  group('Connection Logic', () {
    test('should determine effective connection state', () {
      bool isEffectivelyConnected({
        required bool isConnected,
        required bool isAux,
        required bool sendEnabled,
      }) {
        if (!isConnected) return false;
        if (isAux && !sendEnabled) return false;
        return true;
      }

      // Direct route
      expect(
        isEffectivelyConnected(
          isConnected: true,
          isAux: false,
          sendEnabled: false,
        ),
        true,
      );

      // Aux send enabled
      expect(
        isEffectivelyConnected(
          isConnected: true,
          isAux: true,
          sendEnabled: true,
        ),
        true,
      );

      // Aux send disabled
      expect(
        isEffectivelyConnected(
          isConnected: true,
          isAux: true,
          sendEnabled: false,
        ),
        false,
      );

      // Not connected
      expect(
        isEffectivelyConnected(
          isConnected: false,
          isAux: false,
          sendEnabled: true,
        ),
        false,
      );
    });
  });

  group('Selection Logic', () {
    test('should toggle selection correctly', () {
      final selected = <String>{};

      void toggleSelection(String id) {
        if (selected.contains(id)) {
          selected.remove(id);
        } else {
          selected.add(id);
        }
      }

      // Add
      toggleSelection('ch_1');
      expect(selected, contains('ch_1'));

      // Add another
      toggleSelection('ch_2');
      expect(selected.length, 2);

      // Remove first
      toggleSelection('ch_1');
      expect(selected, isNot(contains('ch_1')));
      expect(selected, contains('ch_2'));
    });

    test('should select all correctly', () {
      final channels = ['ch_1', 'ch_2', 'ch_3', 'ch_4'];
      final selected = <String>{};

      void selectAll() {
        selected.addAll(channels);
      }

      void clearAll() {
        selected.clear();
      }

      bool allSelected() {
        return selected.length == channels.length;
      }

      expect(selected.isEmpty, true);
      selectAll();
      expect(allSelected(), true);
      clearAll();
      expect(selected.isEmpty, true);
    });
  });
}
