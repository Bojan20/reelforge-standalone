/// Cloud Project Sync Service Tests — P2-DAW-2
///
/// Tests for cloud project synchronization and version history.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/cloud_project_sync_service.dart';

void main() {
  group('ProjectVersion', () {
    test('creates version with required fields', () {
      final version = ProjectVersion(
        id: 'v1',
        projectId: 'project1',
        versionNumber: 1,
        timestamp: DateTime(2026, 1, 15),
        contentHash: 'abc123',
        sizeBytes: 1024,
      );

      expect(version.id, 'v1');
      expect(version.projectId, 'project1');
      expect(version.versionNumber, 1);
      expect(version.sizeBytes, 1024);
      expect(version.isAutoSave, false);
    });

    test('toJson and fromJson roundtrip preserves data', () {
      final version = ProjectVersion(
        id: 'v1',
        projectId: 'project1',
        versionNumber: 5,
        timestamp: DateTime(2026, 2, 1, 12, 30),
        contentHash: 'hash123',
        sizeBytes: 2048,
        comment: 'Test version',
        author: 'user@test.com',
        isAutoSave: true,
        metadata: {'key': 'value'},
      );

      final json = version.toJson();
      final restored = ProjectVersion.fromJson(json);

      expect(restored.id, version.id);
      expect(restored.projectId, version.projectId);
      expect(restored.versionNumber, version.versionNumber);
      expect(restored.contentHash, version.contentHash);
      expect(restored.sizeBytes, version.sizeBytes);
      expect(restored.comment, version.comment);
      expect(restored.author, version.author);
      expect(restored.isAutoSave, version.isAutoSave);
      expect(restored.metadata['key'], 'value');
    });

    test('label returns correct format', () {
      final manualVersion = ProjectVersion(
        id: 'v1',
        projectId: 'p1',
        versionNumber: 3,
        timestamp: DateTime.now(),
        contentHash: 'hash',
        sizeBytes: 100,
        isAutoSave: false,
      );

      final autoVersion = ProjectVersion(
        id: 'v2',
        projectId: 'p1',
        versionNumber: 4,
        timestamp: DateTime.now(),
        contentHash: 'hash',
        sizeBytes: 100,
        isAutoSave: true,
      );

      expect(manualVersion.label, 'v3');
      expect(autoVersion.label, 'Auto-save v4');
    });

    test('ageFormatted returns human-readable string', () {
      final recentVersion = ProjectVersion(
        id: 'v1',
        projectId: 'p1',
        versionNumber: 1,
        timestamp: DateTime.now().subtract(const Duration(seconds: 30)),
        contentHash: 'hash',
        sizeBytes: 100,
      );

      final hourOldVersion = ProjectVersion(
        id: 'v2',
        projectId: 'p1',
        versionNumber: 2,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        contentHash: 'hash',
        sizeBytes: 100,
      );

      final dayOldVersion = ProjectVersion(
        id: 'v3',
        projectId: 'p1',
        versionNumber: 3,
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
        contentHash: 'hash',
        sizeBytes: 100,
      );

      expect(recentVersion.ageFormatted, 'Just now');
      expect(hourOldVersion.ageFormatted, '2h ago');
      expect(dayOldVersion.ageFormatted, '3d ago');
    });
  });

  group('SyncConflict', () {
    test('newerVersion returns correct version', () {
      final localVersion = ProjectVersion(
        id: 'local',
        projectId: 'p1',
        versionNumber: 1,
        timestamp: DateTime(2026, 1, 15, 12, 0),
        contentHash: 'hash1',
        sizeBytes: 100,
      );

      final remoteVersion = ProjectVersion(
        id: 'remote',
        projectId: 'p1',
        versionNumber: 2,
        timestamp: DateTime(2026, 1, 15, 14, 0), // 2 hours later
        contentHash: 'hash2',
        sizeBytes: 150,
      );

      final conflict = SyncConflict(
        projectId: 'p1',
        localVersion: localVersion,
        remoteVersion: remoteVersion,
        type: ConflictType.bothModified,
      );

      expect(conflict.newerVersion, remoteVersion);
    });
  });

  group('ProjectSyncStatus', () {
    test('displayName returns correct strings', () {
      expect(ProjectSyncStatus.synced.displayName, 'Synced');
      expect(ProjectSyncStatus.pendingUpload.displayName, 'Pending Upload');
      expect(ProjectSyncStatus.pendingDownload.displayName, 'Pending Download');
      expect(ProjectSyncStatus.syncing.displayName, 'Syncing...');
      expect(ProjectSyncStatus.conflict.displayName, 'Conflict');
      expect(ProjectSyncStatus.error.displayName, 'Error');
      expect(ProjectSyncStatus.localOnly.displayName, 'Local Only');
    });

    test('needsAttention returns true for conflict and error', () {
      expect(ProjectSyncStatus.synced.needsAttention, false);
      expect(ProjectSyncStatus.conflict.needsAttention, true);
      expect(ProjectSyncStatus.error.needsAttention, true);
      expect(ProjectSyncStatus.pendingUpload.needsAttention, false);
    });
  });

  group('ConflictType', () {
    test('all conflict types are defined', () {
      expect(ConflictType.values.length, 3);
      expect(ConflictType.values, contains(ConflictType.bothModified));
      expect(ConflictType.values, contains(ConflictType.localDeletedRemoteModified));
      expect(ConflictType.values, contains(ConflictType.localModifiedRemoteDeleted));
    });
  });

  group('ConflictResolution', () {
    test('all resolution strategies are defined', () {
      expect(ConflictResolution.values.length, 5);
      expect(ConflictResolution.values, contains(ConflictResolution.keepLocal));
      expect(ConflictResolution.values, contains(ConflictResolution.keepRemote));
      expect(ConflictResolution.values, contains(ConflictResolution.keepNewer));
      expect(ConflictResolution.values, contains(ConflictResolution.keepBoth));
      expect(ConflictResolution.values, contains(ConflictResolution.manual));
    });
  });
}
