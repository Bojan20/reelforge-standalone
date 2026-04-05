/// AutoSaveProvider Tests
///
/// Tests autosave data models, config, and status management.
/// FFI calls are tested via integration tests (requires native lib).
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/auto_save_provider.dart';

void main() {
  group('AutoSaveConfig', () {
    test('default values are correct', () {
      const config = AutoSaveConfig();
      expect(config.enabled, true);
      expect(config.intervalMs, 60000);
      expect(config.maxSnapshots, 5);
      expect(config.compressData, false);
    });

    test('custom values work', () {
      const config = AutoSaveConfig(
        enabled: false,
        intervalMs: 30000,
        maxSnapshots: 10,
        compressData: true,
      );
      expect(config.enabled, false);
      expect(config.intervalMs, 30000);
      expect(config.maxSnapshots, 10);
      expect(config.compressData, true);
    });
  });

  group('AutoSaveStatus', () {
    test('default values are correct', () {
      const status = AutoSaveStatus();
      expect(status.enabled, true);
      expect(status.isDirty, false);
      expect(status.lastSave, isNull);
      expect(status.lastSaveTime, isNull);
      expect(status.isSaving, false);
      expect(status.hasRecovery, false);
      expect(status.recoveryEntries, isEmpty);
    });

    test('copyWith preserves unchanged values', () {
      const status = AutoSaveStatus(
        enabled: true,
        isDirty: true,
        isSaving: false,
        hasRecovery: true,
      );
      final updated = status.copyWith(isDirty: false);
      expect(updated.isDirty, false);
      expect(updated.enabled, true);
      expect(updated.hasRecovery, true);
      expect(updated.isSaving, false);
    });

    test('copyWith changes multiple fields', () {
      const status = AutoSaveStatus();
      final updated = status.copyWith(
        isDirty: true,
        isSaving: true,
        lastSaveTime: '2026-04-05 19:00',
      );
      expect(updated.isDirty, true);
      expect(updated.isSaving, true);
      expect(updated.lastSaveTime, '2026-04-05 19:00');
    });
  });

  group('AutoSaveEntry', () {
    test('creates entry with all fields', () {
      final entry = AutoSaveEntry(
        id: 'auto_001',
        projectName: 'Test Project',
        data: '{"tracks":[]}',
        timestamp: DateTime(2026, 4, 5, 19, 0),
        sizeBytes: 1024,
      );
      expect(entry.id, 'auto_001');
      expect(entry.projectName, 'Test Project');
      expect(entry.data, '{"tracks":[]}');
      expect(entry.sizeBytes, 1024);
    });
  });

  group('AutoSaveProvider', () {
    test('initial status is default', () {
      final provider = AutoSaveProvider();
      expect(provider.status.enabled, true);
      expect(provider.status.isDirty, false);
      expect(provider.status.isSaving, false);
    });

    test('config can be set', () {
      final provider = AutoSaveProvider();
      provider.setConfig(const AutoSaveConfig(
        enabled: false,
        intervalMs: 120000,
        maxSnapshots: 3,
      ));
      expect(provider.config.enabled, false);
      expect(provider.config.intervalMs, 120000);
      expect(provider.config.maxSnapshots, 3);
      expect(provider.status.enabled, false);
    });

    test('markDirty updates status', () {
      final provider = AutoSaveProvider();
      expect(provider.status.isDirty, false);
      provider.markDirty();
      expect(provider.status.isDirty, true);
    });
  });
}
