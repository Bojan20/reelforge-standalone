import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/aurexis_audit.dart';

void main() {
  group('AuditEntry', () {
    test('JSON round-trip preserves all fields', () {
      final entry = AuditEntry(
        id: 42,
        timestamp: DateTime(2026, 2, 28, 14, 30, 0),
        action: AuditActionType.profileChange,
        severity: AuditSeverity.info,
        description: 'Profile changed to Calm Classic',
        previousValue: 'Standard',
        newValue: 'Calm Classic',
        metadata: {'reason': 'user_selection'},
        deterministicSeed: 12345,
      );
      final json = entry.toJson();
      final restored = AuditEntry.fromJson(json);

      expect(restored.id, 42);
      expect(restored.action, AuditActionType.profileChange);
      expect(restored.severity, AuditSeverity.info);
      expect(restored.description, contains('Calm Classic'));
      expect(restored.previousValue, 'Standard');
      expect(restored.newValue, 'Calm Classic');
      expect(restored.deterministicSeed, 12345);
    });
  });

  group('AuditActionType', () {
    test('all types have labels and icons', () {
      for (final type in AuditActionType.values) {
        expect(type.label, isNotEmpty);
        expect(type.icon, isNotEmpty);
      }
    });
  });

  group('AuditSession', () {
    test('record adds entries sequentially', () {
      final session = AuditSession(sessionId: 'test');
      session.record(
        action: AuditActionType.sessionMarker,
        description: 'Start',
      );
      session.record(
        action: AuditActionType.profileChange,
        description: 'Changed to A',
      );
      session.record(
        action: AuditActionType.behaviorChange,
        description: 'Width set to 0.8',
      );

      expect(session.length, 3);
      expect(session.entries[0].id, 0);
      expect(session.entries[1].id, 1);
      expect(session.entries[2].id, 2);
    });

    test('byType filters correctly', () {
      final session = AuditSession(sessionId: 'test');
      session.record(
        action: AuditActionType.profileChange,
        description: 'A',
      );
      session.record(
        action: AuditActionType.behaviorChange,
        description: 'B',
      );
      session.record(
        action: AuditActionType.profileChange,
        description: 'C',
      );

      final profiles = session.byType(AuditActionType.profileChange);
      expect(profiles.length, 2);
    });

    test('bySeverity filters correctly', () {
      final session = AuditSession(sessionId: 'test');
      session.record(
        action: AuditActionType.profileChange,
        description: 'Normal',
        severity: AuditSeverity.info,
      );
      session.record(
        action: AuditActionType.jurisdictionChange,
        description: 'Critical',
        severity: AuditSeverity.critical,
      );

      expect(session.criticalCount, 1);
      expect(session.warningCount, 0);
    });

    test('JSON export works', () {
      final session = AuditSession(
        sessionId: 'test_session',
        projectName: 'FluxForge',
      );
      session.record(
        action: AuditActionType.sessionMarker,
        description: 'Start',
      );

      final json = session.toJsonString();
      expect(json, contains('test_session'));
      expect(json, contains('FluxForge'));
      expect(json, contains('entries'));
    });

    test('JSON import works', () {
      final session = AuditSession(
        sessionId: 'import_test',
        projectName: 'Test',
      );
      session.record(
        action: AuditActionType.profileChange,
        description: 'Test entry',
      );

      final jsonStr = session.toJsonString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = AuditSession.fromJson(json);

      expect(restored.sessionId, 'import_test');
      expect(restored.entries.length, 1);
    });

    test('inRange filters by time', () {
      final session = AuditSession(sessionId: 'test');
      session.record(
        action: AuditActionType.sessionMarker,
        description: 'Test',
      );

      final now = DateTime.now();
      final results = session.inRange(
        now.subtract(const Duration(seconds: 5)),
        now.add(const Duration(seconds: 5)),
      );
      expect(results.length, 1);
    });
  });
}
