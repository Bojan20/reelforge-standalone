/// RecentProjectsProvider Tests
///
/// Tests project list management, add/remove, max cap, and model.
@Tags(['provider'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/recent_projects_provider.dart';

void main() {
  group('RecentProject model', () {
    test('fromPath extracts name from path', () {
      final project = RecentProject.fromPath('/Users/test/MyProject.rfp');
      expect(project.name, 'MyProject');
      expect(project.path, '/Users/test/MyProject.rfp');
    });

    test('fromPath strips .json extension', () {
      final project = RecentProject.fromPath('/path/to/project.json');
      expect(project.name, 'project');
    });

    test('exists returns false for non-existent file', () {
      final project = RecentProject.fromPath('/definitely/not/a/real/file.rfp');
      expect(project.exists, false);
    });

    test('constructor preserves fields', () {
      final now = DateTime.now();
      final project = RecentProject(
        path: '/test/path.rfp',
        name: 'TestProject',
        lastOpened: now,
      );
      expect(project.path, '/test/path.rfp');
      expect(project.name, 'TestProject');
      expect(project.lastOpened, now);
    });
  });

  group('RecentProjectsProvider — basic state', () {
    late RecentProjectsProvider provider;

    setUp(() {
      provider = RecentProjectsProvider();
    });

    test('starts empty', () {
      expect(provider.projects, isEmpty);
      expect(provider.count, 0);
      expect(provider.isEmpty, true);
      expect(provider.isNotEmpty, false);
    });

    test('addProject adds to list', () {
      // Will add even if file doesn't exist (local list update)
      provider.addProject('/test/project1.rfp');
      expect(provider.count, 1);
      expect(provider.isEmpty, false);
      expect(provider.isNotEmpty, true);
    });

    test('addProject moves duplicate to front', () {
      provider.addProject('/test/first.rfp');
      provider.addProject('/test/second.rfp');
      provider.addProject('/test/first.rfp');
      expect(provider.count, 2);
      expect(provider.projects.first.path, '/test/first.rfp');
    });

    test('addProject caps at 20', () {
      for (int i = 0; i < 25; i++) {
        provider.addProject('/test/project_$i.rfp');
      }
      expect(provider.count, 20);
    });

    test('removeProject removes from list', () {
      provider.addProject('/test/to_remove.rfp');
      expect(provider.count, 1);
      provider.removeProject('/test/to_remove.rfp');
      expect(provider.count, 0);
    });

    test('removeProject does nothing for unknown path', () {
      provider.addProject('/test/keep.rfp');
      provider.removeProject('/test/unknown.rfp');
      expect(provider.count, 1);
    });

    test('clearAll empties the list', () {
      provider.addProject('/test/a.rfp');
      provider.addProject('/test/b.rfp');
      provider.clearAll();
      expect(provider.count, 0);
      expect(provider.isEmpty, true);
    });

    test('getAt returns correct project', () {
      provider.addProject('/test/a.rfp');
      provider.addProject('/test/b.rfp');
      final project = provider.getAt(0);
      expect(project, isNotNull);
      expect(project!.path, '/test/b.rfp'); // b is most recent (added last, moved to front)
    });

    test('getAt returns null for out of bounds', () {
      expect(provider.getAt(-1), isNull);
      expect(provider.getAt(100), isNull);
    });
  });

  group('RecentProjectsProvider — notifications', () {
    late RecentProjectsProvider provider;

    setUp(() {
      provider = RecentProjectsProvider();
    });

    test('addProject notifies listeners', () {
      int count = 0;
      provider.addListener(() => count++);
      provider.addProject('/test/notify.rfp');
      expect(count, greaterThan(0));
    });

    test('removeProject notifies listeners', () {
      provider.addProject('/test/x.rfp');
      int count = 0;
      provider.addListener(() => count++);
      provider.removeProject('/test/x.rfp');
      expect(count, greaterThan(0));
    });

    test('clearAll notifies listeners', () {
      provider.addProject('/test/x.rfp');
      int count = 0;
      provider.addListener(() => count++);
      provider.clearAll();
      expect(count, greaterThan(0));
    });
  });
}
