// SPEC-08 / FLUX_MASTER_TODO 2B.2 P3 — MONITOR 20→5 grupa.
//
// `SlotLabMonitorGroup` je single source of truth za:
//   * group rangove (start..=end indeksi u `SlotLabMonitorSubTab.values`)
//   * group labele ("LIVE | AI | MATH | DEBUG | EXPORT")
//   * separator indekse koje context bar koristi za vertical liniju
//
// Ovi testovi pinuju invariants koje bi tihi enum reorder lako pokvario:
//   - Group rangovi pokrivaju SVE sub-tabs bez preklapanja i bez rupa.
//   - Labels/shortcuts/tooltips arrays su iste dužine kao enum (forsira
//     da reorder ažurira sve tri arrays simetrično).
//   - `separatorIndices()` se uvek slaže sa group.range.start.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/widgets/lower_zone/lower_zone_types.dart';

void main() {
  group('SlotLabMonitorGroup — partition invariant', () {
    test('5 grupa pokriva sve 21 sub-tab bez preklapanja', () {
      // Bez ovoga, jedan sub-tab može pasti u 2 grupe ili u 0 grupa.
      // Posle reorder-a `forSubTab` bi mogao da vrati pogrešnu grupu
      // i context bar bi nacrtao label u pogrešnoj poziciji.
      final covered = <int>{};
      for (final g in SlotLabMonitorGroup.values) {
        final (s, e) = g.range;
        for (var i = s; i <= e; i++) {
          expect(covered.add(i), isTrue,
              reason: 'index $i pripada VIŠE grupa (overlap u ${g.name})');
        }
      }
      // Svi sub-tab indeksi (0..21) moraju biti pokriveni.
      for (var i = 0; i < SlotLabMonitorSubTab.values.length; i++) {
        expect(covered.contains(i), isTrue,
            reason: 'sub-tab index $i nije ni u jednoj grupi (rupa u rangovima)');
      }
      // Total coverage je tačno 21 (cardinality enum-a).
      expect(covered.length, SlotLabMonitorSubTab.values.length);
    });

    test('5 grupa, tačno 21 sub-tab, broj po SPEC-08', () {
      // Pin cardinality. Ako neko doda novi sub-tab bez ažuriranja
      // grupa, ovaj test pukne pre nego što UI zarazi pogrešnim
      // separator-ima.
      expect(SlotLabMonitorGroup.values.length, 5);
      expect(SlotLabMonitorSubTab.values.length, 21);
    });

    test('forSubTab vraća očekivanu grupu za reprezentativne tab-ove', () {
      expect(SlotLabMonitorGroup.forSubTab(SlotLabMonitorSubTab.timeline),
          SlotLabMonitorGroup.live);
      expect(SlotLabMonitorGroup.forSubTab(SlotLabMonitorSubTab.aiCopilot),
          SlotLabMonitorGroup.ai);
      expect(SlotLabMonitorGroup.forSubTab(SlotLabMonitorSubTab.mathBridge),
          SlotLabMonitorGroup.math);
      expect(SlotLabMonitorGroup.forSubTab(SlotLabMonitorSubTab.debug),
          SlotLabMonitorGroup.debug);
      expect(SlotLabMonitorGroup.forSubTab(SlotLabMonitorSubTab.voiceStats),
          SlotLabMonitorGroup.export);
    });
  });

  group('SlotLabMonitorGroup — separator indices', () {
    test('separatorIndices() = lista start indeksa svih grupa osim prve', () {
      // Prva grupa (LIVE) počinje na 0 → ne treba separator pre sebe
      // (separator se renderuje IZMEĐU grupa). Sve ostale grupe imaju
      // start > 0 i moraju biti u listi.
      final seps = SlotLabMonitorGroup.separatorIndices();
      expect(seps, [4, 8, 11, 15],
          reason: 'separator indeksi moraju biti start-ovi AI/MATH/DEBUG/EXPORT');
    });

    test('separatorIndices() ne sadrži 0', () {
      // Defensive: regex za "start druge grupe" je `> 0` filter; ako
      // neko slučajno doda LIVE grupu sa range (0, 0) → (0, 3) shape,
      // separator pre prvog tab-a bi se pojavio (nema smisla).
      expect(SlotLabMonitorGroup.separatorIndices(), isNot(contains(0)));
    });
  });

  group('SlotLabMonitorSubTab — array length parity', () {
    test('label/shortcut/tooltip svi moraju imati 21 entry', () {
      // Const arrays u extension-u su fragilni — reorder enum-a bez
      // ažuriranja arrays daje OOB ili wrong label. Test forsira
      // `[index]` lookup za svaki value pa će svaka rupa kraknuti.
      for (final t in SlotLabMonitorSubTab.values) {
        expect(t.label, isNotEmpty);
        expect(t.shortcut, isNotEmpty);
        expect(t.tooltip, isNotEmpty);
      }
    });

    test('labels su jedinstvene u nizu (no dupes)', () {
      final labels = SlotLabMonitorSubTab.values.map((t) => t.label).toSet();
      expect(labels.length, SlotLabMonitorSubTab.values.length,
          reason: 'duplikat label u nizu — context bar bi imao 2 button-a sa istim tekstom');
    });

    test('shortcuts su jedinstveni — keyboard nav ne sme imati ambiguity', () {
      final shortcuts = SlotLabMonitorSubTab.values.map((t) => t.shortcut).toSet();
      expect(shortcuts.length, SlotLabMonitorSubTab.values.length,
          reason: 'duplikat shortcut → 2 sub-taba bi se borila za isti tipke');
    });

    test('group getter mapira na isti rezultat kao SlotLabMonitorGroup.forSubTab', () {
      // Cross-check: dva path-a do iste grupe moraju dati isti rezultat.
      for (final t in SlotLabMonitorSubTab.values) {
        expect(t.group, SlotLabMonitorGroup.forSubTab(t),
            reason: 'extension getter divergira od static helper-a za $t');
      }
    });
  });

  group('SlotLabMonitorGroup — labels', () {
    test('5 različitih, čitljivih labela', () {
      final labels = SlotLabMonitorGroup.values.map((g) => g.label).toSet();
      expect(labels, {'LIVE', 'AI', 'MATH', 'DEBUG', 'EXPORT'});
    });
  });
}
