// SPEC-2B.3.2 — PanelLayoutProvider: per-project smart panel memory
//
// Contract:
//   * restore() returns null for unknown projectIds
//   * restoreOrDefaults() returns PanelLayoutMemory.defaults() for unknown ids
//   * save() stores memory and returns same data on restore()
//   * patch() only updates provided fields; unchanged fields keep prior values
//   * patch() is a no-op (no persist call) when nothing changes
//   * switchProject() updates activeProjectId and returns persisted memory (or null)
//   * LRU eviction fires when map exceeds kMaxEntries (oldest entry removed)
//   * PanelLayoutMemory.fromJson / toJson round-trips losslessly

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/providers/panel_layout_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Provide a mock SharedPreferences so init/persist don't hit disk
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PanelLayoutMemory — model
  // ═══════════════════════════════════════════════════════════════════════════

  group('PanelLayoutMemory.defaults', () {
    test('has all panels visible', () {
      final m = PanelLayoutMemory.defaults();
      expect(m.leftVisible, isTrue);
      expect(m.rightVisible, isTrue);
      expect(m.lowerVisible, isTrue);
    });

    test('all optional tab fields are null', () {
      final m = PanelLayoutMemory.defaults();
      expect(m.activeHelixDockTab, isNull);
      expect(m.activeDawLowerTab, isNull);
      expect(m.slotLabLeftTab, isNull);
      expect(m.slotLabRightTab, isNull);
      expect(m.slotLabLowerSuperTab, isNull);
    });
  });

  group('PanelLayoutMemory — JSON round-trip', () {
    test('all non-null fields survive toJson/fromJson', () {
      final original = PanelLayoutMemory(
        activeHelixDockTab: '3',
        activeDawLowerTab: 'browse',
        slotLabLeftTab: 1,
        slotLabRightTab: 0,
        slotLabLowerSuperTab: 2,
        leftVisible: false,
        rightVisible: true,
        lowerVisible: false,
        savedAt: DateTime(2024, 1, 15, 10, 30),
      );
      final json = original.toJson();
      final restored = PanelLayoutMemory.fromJson(json);

      expect(restored.activeHelixDockTab, '3');
      expect(restored.activeDawLowerTab, 'browse');
      expect(restored.slotLabLeftTab, 1);
      expect(restored.slotLabRightTab, 0);
      expect(restored.slotLabLowerSuperTab, 2);
      expect(restored.leftVisible, isFalse);
      expect(restored.rightVisible, isTrue);
      expect(restored.lowerVisible, isFalse);
      expect(restored.savedAt, DateTime(2024, 1, 15, 10, 30));
    });

    test('null fields are omitted from toJson output', () {
      final m = PanelLayoutMemory.defaults();
      final json = m.toJson();
      expect(json.containsKey('activeHelixDockTab'), isFalse);
      expect(json.containsKey('activeDawLowerTab'), isFalse);
      expect(json.containsKey('slotLabLeftTab'), isFalse);
    });

    test('fromJson with missing optional fields defaults gracefully', () {
      final json = {
        'leftVisible': true,
        'rightVisible': false,
        'lowerVisible': true,
        'savedAt': '2024-01-01T00:00:00.000',
      };
      final m = PanelLayoutMemory.fromJson(json);
      expect(m.activeHelixDockTab, isNull);
      expect(m.rightVisible, isFalse);
    });

    test('fromJson with corrupt savedAt falls back to now (no throw)', () {
      final json = {
        'leftVisible': true,
        'rightVisible': true,
        'lowerVisible': true,
        'savedAt': 'not-a-date',
      };
      expect(() => PanelLayoutMemory.fromJson(json), returnsNormally);
    });
  });

  group('PanelLayoutMemory.copyWith', () {
    test('only updates specified fields', () {
      final original = PanelLayoutMemory(
        activeHelixDockTab: '0',
        slotLabLeftTab: 0,
        leftVisible: true,
        rightVisible: true,
        lowerVisible: true,
        savedAt: DateTime(2024),
      );
      final updated = original.copyWith(slotLabLeftTab: 2, lowerVisible: false);
      expect(updated.activeHelixDockTab, '0'); // unchanged
      expect(updated.slotLabLeftTab, 2);       // updated
      expect(updated.lowerVisible, isFalse);   // updated
      expect(updated.leftVisible, isTrue);     // unchanged
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PanelLayoutProvider — restore / save
  // ═══════════════════════════════════════════════════════════════════════════

  group('PanelLayoutProvider.restore', () {
    test('returns null for unknown projectId', () {
      final p = PanelLayoutProvider();
      expect(p.restore('path/to/unknown.flx'), isNull);
    });

    test('restoreOrDefaults returns defaults for unknown projectId', () {
      final p = PanelLayoutProvider();
      final m = p.restoreOrDefaults('unknown');
      expect(m.leftVisible, isTrue);
      expect(m.rightVisible, isTrue);
    });
  });

  group('PanelLayoutProvider.save', () {
    test('saved memory is retrievable via restore()', () async {
      final p = PanelLayoutProvider();
      const id = '/projects/my_game.flx';
      final mem = PanelLayoutMemory(
        activeHelixDockTab: '5',
        leftVisible: false,
        rightVisible: true,
        lowerVisible: true,
        savedAt: DateTime.now(),
      );
      await p.save(projectId: id, memory: mem);
      final restored = p.restore(id);
      expect(restored, isNotNull);
      expect(restored!.activeHelixDockTab, '5');
      expect(restored.leftVisible, isFalse);
    });

    test('save overwrites previous entry for the same id', () async {
      final p = PanelLayoutProvider();
      const id = '/projects/a.flx';
      await p.save(
        projectId: id,
        memory: PanelLayoutMemory(
          activeHelixDockTab: '0',
          leftVisible: true,
          rightVisible: true,
          lowerVisible: true,
          savedAt: DateTime.now(),
        ),
      );
      await p.save(
        projectId: id,
        memory: PanelLayoutMemory(
          activeHelixDockTab: '7',
          leftVisible: false,
          rightVisible: false,
          lowerVisible: false,
          savedAt: DateTime.now(),
        ),
      );
      final m = p.restore(id)!;
      expect(m.activeHelixDockTab, '7');
      expect(m.leftVisible, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PanelLayoutProvider.patch
  // ═══════════════════════════════════════════════════════════════════════════

  group('PanelLayoutProvider.patch', () {
    test('patch creates entry from defaults when none exists', () async {
      final p = PanelLayoutProvider();
      const id = 'new_project';
      await p.patch(projectId: id, slotLabLeftTab: 2);
      final m = p.restore(id)!;
      expect(m.slotLabLeftTab, 2);
      expect(m.leftVisible, isTrue); // defaulted
    });

    test('patch only mutates specified fields', () async {
      final p = PanelLayoutProvider();
      const id = '/path/game.flx';
      await p.save(
        projectId: id,
        memory: PanelLayoutMemory(
          activeHelixDockTab: '3',
          slotLabLeftTab: 1,
          leftVisible: true,
          rightVisible: true,
          lowerVisible: true,
          savedAt: DateTime.now(),
        ),
      );
      await p.patch(projectId: id, slotLabLeftTab: 2);
      final m = p.restore(id)!;
      expect(m.activeHelixDockTab, '3'); // untouched
      expect(m.slotLabLeftTab, 2);       // updated
    });

    test('patch on identical values does not call persist (no-op guard)', () async {
      // We test this by checking the state hasn't changed structurally.
      // Since we can't intercept _persist directly, we verify the stored
      // value is unchanged after a no-op patch.
      final p = PanelLayoutProvider();
      const id = 'idempotent';
      final mem = PanelLayoutMemory(
        slotLabLeftTab: 0,
        leftVisible: true,
        rightVisible: true,
        lowerVisible: true,
        savedAt: DateTime(2024),
      );
      await p.save(projectId: id, memory: mem);
      final before = p.restore(id)!.slotLabLeftTab;
      // Patching same value — should be a no-op
      await p.patch(projectId: id, slotLabLeftTab: 0);
      final after = p.restore(id)!.slotLabLeftTab;
      expect(after, before);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PanelLayoutProvider.switchProject
  // ═══════════════════════════════════════════════════════════════════════════

  group('PanelLayoutProvider.switchProject', () {
    test('returns null for a project with no saved memory', () {
      final p = PanelLayoutProvider();
      final result = p.switchProject('never_saved');
      expect(result, isNull);
    });

    test('returns saved memory for a known project', () async {
      final p = PanelLayoutProvider();
      const id = '/projects/known.flx';
      await p.save(
        projectId: id,
        memory: PanelLayoutMemory(
          activeHelixDockTab: '2',
          leftVisible: false,
          rightVisible: true,
          lowerVisible: true,
          savedAt: DateTime.now(),
        ),
      );
      final result = p.switchProject(id);
      expect(result, isNotNull);
      expect(result!.activeHelixDockTab, '2');
      expect(result.leftVisible, isFalse);
    });

    test('updates activeProjectId', () {
      final p = PanelLayoutProvider();
      expect(p.activeProjectId, isNull);
      p.switchProject('myProject');
      expect(p.activeProjectId, 'myProject');
    });

    test('fires notifyListeners on switchProject', () {
      final p = PanelLayoutProvider();
      var count = 0;
      p.addListener(() => count++);
      p.switchProject('proj');
      expect(count, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PanelLayoutProvider — LRU eviction
  // ═══════════════════════════════════════════════════════════════════════════

  group('PanelLayoutProvider — LRU eviction', () {
    test('evicts oldest entry when kMaxEntries is exceeded', () async {
      final p = PanelLayoutProvider();
      // Fill up to kMaxEntries entries
      for (var i = 0; i < PanelLayoutProvider.kMaxEntries; i++) {
        await p.save(
          projectId: 'proj_$i',
          memory: PanelLayoutMemory(
            leftVisible: true,
            rightVisible: true,
            lowerVisible: true,
            savedAt: DateTime(2024, 1, i + 1), // ascending dates
          ),
        );
      }
      // Adding one more should evict the oldest (proj_0, savedAt Jan 1)
      await p.save(
        projectId: 'proj_overflow',
        memory: PanelLayoutMemory(
          leftVisible: false,
          rightVisible: false,
          lowerVisible: false,
          savedAt: DateTime.now(),
        ),
      );
      // The oldest (proj_0) should be gone
      expect(p.restore('proj_0'), isNull);
      // The new one should be present
      expect(p.restore('proj_overflow'), isNotNull);
      // Total entries must not exceed kMaxEntries
      // We can't directly access the internal map size, but we verify
      // that the overflow entry is present and the oldest is evicted.
    });
  });
}
