/// MixerDSPProvider Tests
///
/// Tests bus management, insert chain operations,
/// plugin catalog, and model behavior.
/// Note: FFI calls will fail in test environment — we test pure Dart logic.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/mixer_dsp_provider.dart';

void main() {
  group('MixerInsert model', () {
    test('constructor preserves fields', () {
      const insert = MixerInsert(
        id: 'ins_1',
        pluginId: 'rf-eq',
        name: 'Studio EQ',
        bypassed: true,
        params: {'lowGain': 3.0},
      );
      expect(insert.id, 'ins_1');
      expect(insert.pluginId, 'rf-eq');
      expect(insert.name, 'Studio EQ');
      expect(insert.bypassed, true);
      expect(insert.params['lowGain'], 3.0);
    });

    test('defaults bypassed to false', () {
      const insert = MixerInsert(
        id: 'ins_1',
        pluginId: 'rf-eq',
        name: 'EQ',
      );
      expect(insert.bypassed, false);
      expect(insert.params, isEmpty);
    });

    test('copyWith preserves unmodified fields', () {
      const insert = MixerInsert(
        id: 'ins_1',
        pluginId: 'rf-eq',
        name: 'EQ',
        params: {'lowGain': 2.0},
      );
      final copied = insert.copyWith(bypassed: true);
      expect(copied.id, 'ins_1');
      expect(copied.pluginId, 'rf-eq');
      expect(copied.name, 'EQ');
      expect(copied.bypassed, true);
      expect(copied.params['lowGain'], 2.0);
    });

    test('copyWith replaces specified fields', () {
      const insert = MixerInsert(
        id: 'ins_1',
        pluginId: 'rf-eq',
        name: 'EQ',
      );
      final copied = insert.copyWith(
        name: 'Updated EQ',
        params: {'highGain': 5.0},
      );
      expect(copied.name, 'Updated EQ');
      expect(copied.params['highGain'], 5.0);
    });
  });

  group('MixerBus model', () {
    test('constructor preserves fields', () {
      const bus = MixerBus(
        id: 'sfx',
        name: 'SFX',
        volume: 0.9,
        pan: -0.5,
        muted: true,
        solo: true,
      );
      expect(bus.id, 'sfx');
      expect(bus.name, 'SFX');
      expect(bus.volume, 0.9);
      expect(bus.pan, -0.5);
      expect(bus.muted, true);
      expect(bus.solo, true);
    });

    test('defaults', () {
      const bus = MixerBus(id: 'test', name: 'Test');
      expect(bus.volume, 0.85);
      expect(bus.pan, 0);
      expect(bus.muted, false);
      expect(bus.solo, false);
      expect(bus.inserts, isEmpty);
    });

    test('copyWith preserves unmodified fields', () {
      const bus = MixerBus(id: 'test', name: 'Test', volume: 0.5);
      final copied = bus.copyWith(muted: true);
      expect(copied.id, 'test');
      expect(copied.name, 'Test');
      expect(copied.volume, 0.5);
      expect(copied.muted, true);
    });

    test('copyWith with inserts', () {
      const bus = MixerBus(id: 'test', name: 'Test');
      final copied = bus.copyWith(inserts: [
        const MixerInsert(id: 'i1', pluginId: 'rf-eq', name: 'EQ'),
      ]);
      expect(copied.inserts.length, 1);
      expect(copied.inserts.first.name, 'EQ');
    });
  });

  group('PluginInfo model', () {
    test('constructor preserves fields', () {
      const plugin = PluginInfo(
        id: 'rf-eq',
        name: 'Studio EQ',
        category: 'EQ',
        icon: '📊',
        description: 'A great EQ',
      );
      expect(plugin.id, 'rf-eq');
      expect(plugin.name, 'Studio EQ');
      expect(plugin.category, 'EQ');
      expect(plugin.icon, '📊');
      expect(plugin.description, 'A great EQ');
    });

    test('defaults icon and description', () {
      const plugin = PluginInfo(
        id: 'test',
        name: 'Test',
        category: 'Test',
      );
      expect(plugin.icon, '🔌');
      expect(plugin.description, '');
    });
  });

  group('kDefaultBuses', () {
    test('has 5 default buses', () {
      expect(kDefaultBuses.length, 5);
    });

    test('master bus exists', () {
      final master = kDefaultBuses.firstWhere((b) => b.id == 'master');
      expect(master.name, 'Master');
    });

    test('all buses have ids and names', () {
      for (final bus in kDefaultBuses) {
        expect(bus.id, isNotEmpty);
        expect(bus.name, isNotEmpty);
      }
    });

    test('default bus IDs are unique', () {
      final ids = kDefaultBuses.map((b) => b.id).toSet();
      expect(ids.length, kDefaultBuses.length);
    });
  });

  group('kAvailablePlugins', () {
    test('has 11+ available plugins', () {
      expect(kAvailablePlugins.length, greaterThanOrEqualTo(11));
    });

    test('all plugins have unique ids', () {
      final ids = kAvailablePlugins.map((p) => p.id).toSet();
      expect(ids.length, kAvailablePlugins.length);
    });

    test('all plugins have category', () {
      for (final plugin in kAvailablePlugins) {
        expect(plugin.category, isNotEmpty);
      }
    });

    test('categories include EQ, Dynamics, Time, Distortion', () {
      final categories = kAvailablePlugins.map((p) => p.category).toSet();
      expect(categories.contains('EQ'), true);
      expect(categories.contains('Dynamics'), true);
      expect(categories.contains('Time'), true);
      expect(categories.contains('Distortion'), true);
    });
  });

  group('Utility functions', () {
    test('linearToDb converts correctly', () {
      expect(linearToDb(1.0), closeTo(0.0, 0.01));
      expect(linearToDb(0.5), closeTo(-6.02, 0.1));
      expect(linearToDb(0.0), double.negativeInfinity);
    });

    test('dbToLinear converts correctly', () {
      expect(dbToLinear(0.0), closeTo(1.0, 0.01));
      expect(dbToLinear(-6.0), closeTo(0.501, 0.01));
      expect(dbToLinear(-120), 0);
      expect(dbToLinear(-200), 0);
    });

    test('linearToDb and dbToLinear are inverse', () {
      for (final db in [-60.0, -20.0, -6.0, 0.0, 6.0]) {
        final linear = dbToLinear(db);
        final backToDb = linearToDb(linear);
        if (db > -120) {
          expect(backToDb, closeTo(db, 0.01));
        }
      }
    });
  });

  // NOTE: MixerDSPProvider constructor calls NativeFFI.instance which
  // may fail in test environment. We test the pure-Dart aspects above.
  // The following tests are guarded with try/catch for FFI init failure.

  group('MixerDSPProvider — basic state (if FFI available)', () {
    MixerDSPProvider? provider;

    setUp(() {
      try {
        provider = MixerDSPProvider();
      } catch (_) {
        provider = null;
      }
    });

    test('buses start with defaults', () {
      if (provider == null) return; // Skip if FFI unavailable
      expect(provider!.buses.length, 5);
      expect(provider!.isConnected, false);
      expect(provider!.error, isNull);
    });

    test('getBus returns correct bus', () {
      if (provider == null) return;
      final master = provider!.getBus('master');
      expect(master, isNotNull);
      expect(master!.name, 'Master');
    });

    test('getBus returns null for unknown', () {
      if (provider == null) return;
      expect(provider!.getBus('nonexistent'), isNull);
    });

    test('availablePlugins returns catalog', () {
      if (provider == null) return;
      expect(provider!.availablePlugins, isNotEmpty);
    });

    test('reset restores default buses', () {
      if (provider == null) return;
      provider!.reset();
      expect(provider!.buses.length, 5);
    });
  });
}
