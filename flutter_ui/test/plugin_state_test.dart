// Plugin State System Unit Tests
//
// Tests for PluginManifest, PluginReference, PluginUid serialization
// These tests do NOT require FFI - they test pure Dart models

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/plugin_manifest.dart';

void main() {
  group('PluginFormat', () {
    test('should have correct format values', () {
      expect(PluginFormat.vst3.name, 'vst3');
      expect(PluginFormat.au.name, 'au');
      expect(PluginFormat.clap.name, 'clap');
      expect(PluginFormat.aax.name, 'aax');
      expect(PluginFormat.lv2.name, 'lv2');
    });

    test('should have display names', () {
      expect(PluginFormat.vst3.displayName, 'VST3');
      expect(PluginFormat.au.displayName, 'Audio Units');
      expect(PluginFormat.clap.displayName, 'CLAP');
    });

    test('fromExtension should parse valid extensions', () {
      expect(PluginFormat.fromExtension('vst3'), PluginFormat.vst3);
      expect(PluginFormat.fromExtension('component'), PluginFormat.au);
      expect(PluginFormat.fromExtension('clap'), PluginFormat.clap);
      expect(PluginFormat.fromExtension('.vst3'), PluginFormat.vst3);
      expect(PluginFormat.fromExtension('.COMPONENT'), PluginFormat.au);
    });

    test('fromExtension should return null for unknown extensions', () {
      expect(PluginFormat.fromExtension('unknown'), isNull);
      expect(PluginFormat.fromExtension(''), isNull);
    });
  });

  group('PluginUid', () {
    test('VST3 UID should serialize and deserialize correctly', () {
      final uid = PluginUid(
        format: PluginFormat.vst3,
        uid: 'ABCD1234EFGH5678IJKL90MN',
      );

      final json = uid.toJson();
      expect(json['format'], 'vst3');
      expect(json['uid'], 'ABCD1234EFGH5678IJKL90MN');

      final restored = PluginUid.fromJson(json);
      expect(restored.format, PluginFormat.vst3);
      expect(restored.uid, 'ABCD1234EFGH5678IJKL90MN');
    });

    test('AU Component ID should serialize correctly', () {
      final uid = PluginUid(
        format: PluginFormat.au,
        uid: 'aufx:prQ3:FabF',
      );

      final json = uid.toJson();
      expect(json['format'], 'au');
      expect(json['uid'], 'aufx:prQ3:FabF');
    });

    test('CLAP string ID should serialize correctly', () {
      final uid = PluginUid(
        format: PluginFormat.clap,
        uid: 'com.fabfilter.pro-q-3',
      );

      final json = uid.toJson();
      expect(json['format'], 'clap');
      expect(json['uid'], 'com.fabfilter.pro-q-3');
    });

    test('factory constructors should work', () {
      final vst3 = PluginUid.vst3('ABCD1234EFGH5678IJKL90MNOPQRSTUV');
      expect(vst3.format, PluginFormat.vst3);

      final au = PluginUid.au(type: 'aufx', subtype: 'prQ3', manufacturer: 'FabF');
      expect(au.format, PluginFormat.au);
      expect(au.uid, 'aufx:prQ3:FabF');

      final clap = PluginUid.clap('com.example.plugin');
      expect(clap.format, PluginFormat.clap);
    });

    test('auComponents should extract AU components', () {
      final au = PluginUid.au(type: 'aufx', subtype: 'prQ3', manufacturer: 'FabF');
      final components = au.auComponents;
      expect(components?.type, 'aufx');
      expect(components?.subtype, 'prQ3');
      expect(components?.manufacturer, 'FabF');

      final vst3 = PluginUid.vst3('ABCD1234EFGH5678IJKL90MNOPQRSTUV');
      expect(vst3.auComponents, isNull);
    });

    test('equality should work correctly', () {
      final uid1 = PluginUid(format: PluginFormat.vst3, uid: 'ABC123');
      final uid2 = PluginUid(format: PluginFormat.vst3, uid: 'ABC123');
      final uid3 = PluginUid(format: PluginFormat.au, uid: 'ABC123');

      expect(uid1, equals(uid2));
      expect(uid1, isNot(equals(uid3)));
      expect(uid1.hashCode, uid2.hashCode);
    });
  });

  group('PluginReference', () {
    test('should serialize and deserialize correctly', () {
      final ref = PluginReference(
        uid: PluginUid(format: PluginFormat.vst3, uid: 'VST3_UID_12345'),
        name: 'Pro-Q 3',
        vendor: 'FabFilter',
        version: '3.15.0',
      );

      final json = ref.toJson();
      expect(json['name'], 'Pro-Q 3');
      expect(json['vendor'], 'FabFilter');
      expect(json['version'], '3.15.0');
      expect(json['uid'], isA<Map>());

      final restored = PluginReference.fromJson(json);
      expect(restored.name, 'Pro-Q 3');
      expect(restored.vendor, 'FabFilter');
      expect(restored.version, '3.15.0');
      expect(restored.uid.format, PluginFormat.vst3);
    });

    test('copyWith should create modified copy', () {
      final ref = PluginReference(
        uid: PluginUid(format: PluginFormat.vst3, uid: 'ABC'),
        name: 'Original',
        vendor: 'Vendor',
        version: '1.0',
      );

      final modified = ref.copyWith(name: 'Modified', version: '2.0');
      expect(modified.name, 'Modified');
      expect(modified.version, '2.0');
      expect(modified.vendor, 'Vendor'); // unchanged
      expect(ref.name, 'Original'); // original unchanged
    });
  });

  group('PluginSlotState', () {
    test('should serialize and deserialize correctly', () {
      final state = PluginSlotState(
        trackId: 1,
        slotIndex: 0,
        plugin: PluginReference(
          uid: PluginUid(format: PluginFormat.vst3, uid: 'ABC123'),
          name: 'Compressor',
          vendor: 'Test',
          version: '1.0',
        ),
        presetName: 'Default',
        stateFilePath: '/path/to/state.ffstate',
        freezeAudioPath: '/path/to/freeze.wav',
      );

      final json = state.toJson();
      expect(json['trackId'], 1);
      expect(json['slotIndex'], 0);
      expect(json['presetName'], 'Default');
      expect(json['stateFilePath'], '/path/to/state.ffstate');
      expect(json['freezeAudioPath'], '/path/to/freeze.wav');

      final restored = PluginSlotState.fromJson(json);
      expect(restored.trackId, 1);
      expect(restored.slotIndex, 0);
      expect(restored.plugin.name, 'Compressor');
      expect(restored.presetName, 'Default');
      expect(restored.stateFilePath, '/path/to/state.ffstate');
      expect(restored.freezeAudioPath, '/path/to/freeze.wav');
    });

    test('optional fields should handle null correctly', () {
      final state = PluginSlotState(
        trackId: 0,
        slotIndex: 0,
        plugin: PluginReference(
          uid: PluginUid(format: PluginFormat.au, uid: 'XYZ'),
          name: 'Test',
          vendor: 'V',
          version: '1',
        ),
      );

      expect(state.presetName, isNull);
      expect(state.stateFilePath, isNull);
      expect(state.freezeAudioPath, isNull);

      final json = state.toJson();
      final restored = PluginSlotState.fromJson(json);
      expect(restored.presetName, isNull);
      expect(restored.stateFilePath, isNull);
      expect(restored.freezeAudioPath, isNull);
    });
  });

  group('PluginManifest', () {
    test('should create empty manifest', () {
      final manifest = PluginManifest(projectName: 'Test Project');

      expect(manifest.projectName, 'Test Project');
      expect(manifest.plugins, isEmpty);
      expect(manifest.slotStates, isEmpty);
      expect(manifest.version, PluginManifest.currentVersion);
    });

    test('should serialize and deserialize with plugins', () {
      final manifest = PluginManifest(
        projectName: 'My Song',
        version: 1,
      );

      // Add plugin using addPlugin method
      manifest.addPlugin(PluginReference(
        uid: PluginUid(format: PluginFormat.vst3, uid: 'ABC123'),
        name: 'EQ',
        vendor: 'FabFilter',
        version: '3.0',
      ));

      // Add slot state
      manifest.addSlotState(PluginSlotState(
        trackId: 0,
        slotIndex: 0,
        plugin: PluginReference(
          uid: PluginUid(format: PluginFormat.vst3, uid: 'ABC123'),
          name: 'EQ',
          vendor: 'FabFilter',
          version: '3.0',
        ),
        presetName: 'Vocal EQ',
      ));

      final json = manifest.toJson();
      expect(json['projectName'], 'My Song');
      expect(json['version'], 1);
      expect(json['plugins'], isA<Map>());
      expect(json['slotStates'], isA<List>());
      expect((json['plugins'] as Map).length, 1);
      expect((json['slotStates'] as List).length, 1);

      final restored = PluginManifest.fromJson(json);
      expect(restored.projectName, 'My Song');
      expect(restored.version, 1);
      expect(restored.plugins.length, 1);
      expect(restored.slotStates.length, 1);
      expect(restored.slotStates[0].presetName, 'Vocal EQ');
    });

    test('addPlugin should add plugin correctly', () {
      final manifest = PluginManifest(projectName: 'Test');
      final ref = PluginReference(
        uid: PluginUid(format: PluginFormat.clap, uid: 'test.plugin'),
        name: 'Test Plugin',
        vendor: 'Test',
        version: '1.0',
      );

      manifest.addPlugin(ref);
      expect(manifest.plugins.length, 1);
      expect(manifest.getPlugin(ref.uid)?.name, 'Test Plugin');
    });

    test('addSlotState should add and replace existing', () {
      final manifest = PluginManifest(projectName: 'Test');
      final plugin = PluginReference(
        uid: PluginUid(format: PluginFormat.vst3, uid: 'ABC'),
        name: 'P',
        vendor: 'V',
        version: '1',
      );

      // Add first state
      manifest.addSlotState(PluginSlotState(
        trackId: 0,
        slotIndex: 0,
        plugin: plugin,
        presetName: 'First',
      ));
      expect(manifest.slotStates.length, 1);
      expect(manifest.slotStates[0].presetName, 'First');

      // Add state for same slot (should replace)
      manifest.addSlotState(PluginSlotState(
        trackId: 0,
        slotIndex: 0,
        plugin: plugin,
        presetName: 'Second',
      ));
      expect(manifest.slotStates.length, 1);
      expect(manifest.slotStates[0].presetName, 'Second');

      // Add state for different slot
      manifest.addSlotState(PluginSlotState(
        trackId: 0,
        slotIndex: 1,
        plugin: plugin,
      ));
      expect(manifest.slotStates.length, 2);
    });

    test('getTrackSlots should find slots for track', () {
      final manifest = PluginManifest(projectName: 'Test');
      final plugin = PluginReference(
        uid: PluginUid(format: PluginFormat.vst3, uid: 'A'),
        name: 'P1',
        vendor: 'V',
        version: '1',
      );

      manifest.addSlotState(PluginSlotState(trackId: 0, slotIndex: 0, plugin: plugin));
      manifest.addSlotState(PluginSlotState(trackId: 0, slotIndex: 2, plugin: plugin));
      manifest.addSlotState(PluginSlotState(trackId: 1, slotIndex: 0, plugin: plugin));

      final track0Slots = manifest.getTrackSlots(0);
      expect(track0Slots.length, 2);
      expect(track0Slots[0].slotIndex, 0);
      expect(track0Slots[1].slotIndex, 2);

      final track1Slots = manifest.getTrackSlots(1);
      expect(track1Slots.length, 1);

      final track5Slots = manifest.getTrackSlots(5);
      expect(track5Slots, isEmpty);
    });

    test('copyWith should create modified copy', () {
      final manifest = PluginManifest(projectName: 'Original');
      final copy = manifest.copyWith(projectName: 'Copy');

      expect(manifest.projectName, 'Original');
      expect(copy.projectName, 'Copy');
    });

    test('vendors getter should return unique vendors', () {
      final manifest = PluginManifest(projectName: 'Test');
      manifest.addPlugin(PluginReference(
        uid: PluginUid(format: PluginFormat.vst3, uid: 'A'),
        name: 'P1',
        vendor: 'FabFilter',
        version: '1',
      ));
      manifest.addPlugin(PluginReference(
        uid: PluginUid(format: PluginFormat.vst3, uid: 'B'),
        name: 'P2',
        vendor: 'FabFilter',
        version: '1',
      ));
      manifest.addPlugin(PluginReference(
        uid: PluginUid(format: PluginFormat.vst3, uid: 'C'),
        name: 'P3',
        vendor: 'iZotope',
        version: '1',
      ));

      expect(manifest.vendors, {'FabFilter', 'iZotope'});
    });
  });

  group('PluginStateChunk', () {
    test('should serialize to bytes and back', () {
      final chunk = PluginStateChunk(
        pluginUid: PluginUid(format: PluginFormat.vst3, uid: 'ABCD1234EFGH5678IJKL90MNOPQRSTUV'),
        stateData: Uint8List.fromList([1, 2, 3, 4, 5]),
        capturedAt: DateTime(2026, 1, 24),
        presetName: 'My Preset',
      );

      expect(chunk.sizeBytes, 5);
      expect(chunk.presetName, 'My Preset');

      // Test toBytes produces valid data
      final bytes = chunk.toBytes();
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(chunk.sizeBytes));
    });

    test('sizeBytes should return correct size', () {
      final chunk = PluginStateChunk(
        pluginUid: PluginUid(format: PluginFormat.vst3, uid: 'TESTUID'),
        stateData: Uint8List.fromList(List.generate(100, (i) => i % 256)),
        capturedAt: DateTime.now(),
      );

      expect(chunk.sizeBytes, 100);
    });
  });

  group('PluginLocation', () {
    test('should serialize and deserialize correctly', () {
      final location = PluginLocation(
        path: '/Library/Audio/Plug-Ins/Components/ProQ3.component',
        bundleId: 'com.fabfilter.AudioUnits.ProQ3',
        modifiedAt: DateTime(2026, 1, 1, 12, 0),
        sizeBytes: 5242880,
      );

      final json = location.toJson();
      expect(json['path'], contains('ProQ3'));
      expect(json['bundleId'], 'com.fabfilter.AudioUnits.ProQ3');
      expect(json['sizeBytes'], 5242880);

      final restored = PluginLocation.fromJson(json);
      expect(restored.path, location.path);
      expect(restored.bundleId, location.bundleId);
      expect(restored.sizeBytes, 5242880);
    });

    test('optional fields should be nullable', () {
      final location = PluginLocation(path: '/path/to/plugin');

      expect(location.bundleId, isNull);
      expect(location.modifiedAt, isNull);
      expect(location.sizeBytes, isNull);

      final json = location.toJson();
      expect(json.containsKey('bundleId'), isFalse);
      expect(json.containsKey('sizeBytes'), isFalse);
    });
  });
}
