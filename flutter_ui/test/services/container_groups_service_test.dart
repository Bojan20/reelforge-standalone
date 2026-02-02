import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ui/services/container_groups_service.dart';

void main() {
  group('ContainerGroupChild', () {
    test('creates with default values', () {
      const child = ContainerGroupChild(
        id: 'child_1',
        type: ContainerChildType.blend,
        containerId: 1,
      );

      expect(child.id, 'child_1');
      expect(child.type, ContainerChildType.blend);
      expect(child.containerId, 1);
      expect(child.priority, 50);
      expect(child.weight, 1.0);
      expect(child.enabled, true);
      expect(child.condition, isNull);
    });

    test('serializes to JSON and back', () {
      const child = ContainerGroupChild(
        id: 'child_1',
        type: ContainerChildType.random,
        containerId: 42,
        priority: 75,
        weight: 2.5,
        enabled: false,
        condition: 'win > 10',
      );

      final json = child.toJson();
      final restored = ContainerGroupChild.fromJson(json);

      expect(restored.id, child.id);
      expect(restored.type, child.type);
      expect(restored.containerId, child.containerId);
      expect(restored.priority, child.priority);
      expect(restored.weight, child.weight);
      expect(restored.enabled, child.enabled);
      expect(restored.condition, child.condition);
    });

    test('copyWith creates modified copy', () {
      const original = ContainerGroupChild(
        id: 'child_1',
        type: ContainerChildType.blend,
        containerId: 1,
      );

      final modified = original.copyWith(
        priority: 90,
        weight: 3.0,
      );

      expect(modified.id, original.id);
      expect(modified.priority, 90);
      expect(modified.weight, 3.0);
      expect(modified.containerId, original.containerId);
    });
  });

  group('ContainerGroup', () {
    test('creates with default values', () {
      const group = ContainerGroup(
        id: 1,
        name: 'Test Group',
      );

      expect(group.id, 1);
      expect(group.name, 'Test Group');
      expect(group.description, '');
      expect(group.mode, GroupEvaluationMode.all);
      expect(group.children, isEmpty);
      expect(group.enabled, true);
    });

    test('serializes to JSON and back', () {
      const group = ContainerGroup(
        id: 1,
        name: 'Test Group',
        description: 'A test group',
        mode: GroupEvaluationMode.weightedRandom,
        children: [
          ContainerGroupChild(
            id: 'c1',
            type: ContainerChildType.sequence,
            containerId: 10,
          ),
        ],
        enabled: true,
      );

      final json = group.toJson();
      final restored = ContainerGroup.fromJson(json);

      expect(restored.id, group.id);
      expect(restored.name, group.name);
      expect(restored.description, group.description);
      expect(restored.mode, group.mode);
      expect(restored.children.length, 1);
      expect(restored.children.first.id, 'c1');
    });
  });

  group('GroupEvaluationResult', () {
    test('creates with selected containers', () {
      const result = GroupEvaluationResult(
        groupId: 1,
        selectedContainerIds: [10, 20, 30],
        containerVolumes: {10: 1.0, 20: 0.5},
        reason: 'Test reason',
      );

      expect(result.groupId, 1);
      expect(result.selectedContainerIds, [10, 20, 30]);
      expect(result.containerVolumes[10], 1.0);
      expect(result.reason, 'Test reason');
    });
  });

  group('GroupEvaluationMode', () {
    test('has correct display names', () {
      expect(GroupEvaluationMode.all.displayName, 'All');
      expect(GroupEvaluationMode.firstMatch.displayName, 'First Match');
      expect(GroupEvaluationMode.priority.displayName, 'Priority');
      expect(GroupEvaluationMode.random.displayName, 'Random');
      expect(GroupEvaluationMode.weightedRandom.displayName, 'Weighted Random');
    });
  });

  group('ContainerGroupsService', () {
    test('evaluateGroup returns empty for non-existent group', () {
      final service = ContainerGroupsService.instance;
      final result = service.evaluateGroup(999);

      expect(result.selectedContainerIds, isEmpty);
      expect(result.reason, contains('not found'));
    });
  });
}
