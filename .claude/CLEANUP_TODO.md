# CLEANUP TODO — .claude/ & Project-Wide

**Kreiran:** 2026-02-08
**Status:** PROVERA U TOKU — NE BRISATI BEZ POTVRDE

---

## KATEGORIJA 1: CLAUDE.md BROKEN REFERENCES (9 phantom fajlova)

CLAUDE.md referencira 9 fajlova koji NE POSTOJE. Opcije: popraviti reference ili obrisati sekcije.

| # | Referenca u CLAUDE.md | Status | Preporuka |
|---|----------------------|--------|-----------|
| 1 | `.claude/tasks/CONTAINER_P0_INTEGRATION.md` | ❌ Ne postoji | Obriši referencu — task P0 je davno završen |
| 2 | `.claude/tasks/CONTAINER_P1_UI_INTEGRATION.md` | ❌ Ne postoji | Obriši referencu — task P1 je davno završen |
| 3 | `.claude/tasks/CONTAINER_P2_RUST_FFI.md` | ❌ Ne postoji | Obriši referencu — task P2 je davno završen |
| 4 | `.claude/tasks/CONTAINER_P3_ADVANCED.md` | ❌ Ne postoji | Obriši referencu — task P3 je davno završen |
| 5 | `.claude/tasks/DAW_LOWER_ZONE_TODO_2026_01_26.md` | ❌ Ne postoji | Obriši referencu — DAW LZ TODO završen |
| 6 | `.claude/tasks/SLOTLAB_V6_IMPLEMENTATION.md` | ❌ Ne postoji | Obriši referencu — V6 je implementiran |
| 7 | `.claude/tasks/INDUSTRY_STANDARD_FIXES_PLAN.md` | ❌ Ne postoji | Obriši referencu — fixes završeni |
| 8 | `.claude/architecture/MIDDLEWARE_TODO_M3_2026_01_23.md` | ❌ Ne postoji | Obriši referencu (3 mesta u CLAUDE.md) |
| 9 | `.claude/analysis/COMPOSITE_EVENT_PROVIDER_ANALYSIS_2026_01_24.md` | ❌ Ne postoji | Obriši referencu — fajl se zvao drugačije |

**Odluka:** ⏳ ČEKA POTVRDU

---

## KATEGORIJA 2: KONFLIKTI U STATUSU (Root fajlovi se ne slažu)

4 fajla tvrde različite procente završenosti projekta:

| Fajl | Tvrdi | Datum |
|------|-------|-------|
| `MASTER_TODO.md` | **100% COMPLETE** (362/362) | 2026-02-02 04:30 |
| `MASTER_TODO_ULTIMATE_2026_02_02.md` | **81.4%** (296/362) | 2026-02-02 01:40 |
| `MVP_SHIP_READY.txt` | **65%** (241/374) | 2026-02-01 |
| `PHASE_A_100_PERCENT_COMPLETE.md` | **100% Phase A** (369 total tasks) | 2026-02-01 |

**Problem:** `MASTER_TODO.md` tvrdi 100% ali i 95.6% u istom fajlu (linija 19 vs linija 104).

**Preporuka:**
- Utvrditi tačan procenat
- Zadržati JEDAN master TODO (verovatno `MASTER_TODO.md`)
- Obrisati `MASTER_TODO_ULTIMATE_2026_02_02.md` AKO je zastareo
- Obrisati `MVP_SHIP_READY.txt` AKO je zastareo
- Obrisati `PHASE_A_100_PERCENT_COMPLETE.md` AKO je zastareo

**Odluka:** ⏳ ČEKA POTVRDU — koji je tačan status?

---

## KATEGORIJA 3: INDEX.md BROKEN LINKS

`INDEX.md` (datum: 2026-01-26) ima zastarele reference:

| # | Broken link | Problem |
|---|-------------|---------|
| 1 | `MASTER_TODO_2026_01_22.md` | Ne postoji — treba `MASTER_TODO.md` |
| 2 | `SESSION_SUMMARY_2026_01_26.md` | Ne postoji — obrisano u cleanup-u |
| 3 | Tvrdi `analysis/` ima 15 docs | Ima 13 |
| 4 | Tvrdi `architecture/` ima 35 docs | Ima 24 |
| 5 | Tvrdi `audits/` ima 8 docs | Ima 1 |
| 6 | Tvrdi `tasks/` ima 25 docs | Ima 6 |

**Preporuka:** Ažurirati INDEX.md sa ispravnim brojevima i linkovima.

**Odluka:** ⏳ ČEKA POTVRDU

---

## KATEGORIJA 4: README.md BROKEN LINKS

`README.md` (datum: 2026-02-02) ima:

| # | Problem |
|---|---------|
| 1 | Referencira `MASTER_TODO_ULTIMATE_2026_02_01.md` — ne postoji (obrisano, treba `_02_02`) |
| 2 | Referencira `SESSION_2026_02_01_FINAL_SUMMARY.md` u sessions/ — ne postoji (obrisano) |

**Preporuka:** Ažurirati README.md linkove.

**Odluka:** ⏳ ČEKA POTVRDU

---

## KATEGORIJA 5: ROOT FAJLOVI — DA LI SU SVI POTREBNI?

Od 15 preostalih root fajlova, ovi su potencijalno redundantni:

| Fajl | Veličina | Potencijalni problem |
|------|----------|---------------------|
| `MASTER_TODO_ULTIMATE_2026_02_02.md` | 16KB | Duplikat MASTER_TODO.md? Ili detaljnija verzija? |
| `MVP_SHIP_READY.txt` | 13KB | Zastareo (tvrdi 65% dok je projekat 100%?) |
| `PHASE_A_100_PERCENT_COMPLETE.md` | 23KB | Jednokratni milestone — da li treba? |
| `SYSTEM_AUDIT_2026_01_21.md` | 13KB | Star (3 nedelje), referenciran iz CLAUDE.md |
| `merge_agents.sh` | 7KB | Shell script — da li se još koristi? |
| `INDEX.md` | 10KB | Zastareo (2026-01-26), duplikat README.md? |

**Preporuka:** Proveriti svaki i odlučiti da li treba.

**Odluka:** ⏳ ČEKA POTVRDU

---

## KATEGORIJA 6: APPLE DOUBLE FAJLOVI — CELI PROJEKAT (291+ fajlova, ~34MB)

`.claude/` je očišćen, ali ostatak projekta ima 291 `._*` fajlova:

| Lokacija | Broj | Veličina |
|----------|------|----------|
| `flutter_ui/lib/services/` | 56 | ~23MB (lib ukupno) |
| `flutter_ui/test/services/` | 29 | ~8.9MB (test ukupno) |
| `flutter_ui/lib/widgets/slot_lab/` | 27 | (uključeno gore) |
| `flutter_ui/lib/models/` | 13 | |
| `flutter_ui/macos/` | 13 | ~2MB |
| `crates/` (Rust source) | 18 | ~2.3MB |
| Root (`._CLAUDE.md`, `._Cargo.toml`, `._Cargo.lock`) | 3 | ~384KB |
| `target/` | **Nepoznato** | **Potencijalno ogromno** (find timeout) |
| **UKUPNO (bez target/)** | **291** | **~34MB** |

**Rizik:**
- `flutter_ui/macos/` — može uzrokovati **codesign greške** pri build-u
- `crates/` — Rust compiler ih ignoriše ali zauzimaju prostor
- `target/` — potencijalno hiljade fajlova

**Preporuka:** Obrisati SVE `._*` fajlove iz celog projekta.
**Build procedura već briše iz Pods:** `find Pods -name '._*' -type f -delete`
— ali to NE pokriva ostale direktorijume.

**Odluka:** ⏳ ČEKA POTVRDU

---

## KATEGORIJA 7: SUBDIREKTORI — POTENCIJALNO NEPOTREBNI

Ovi direktorijumi imaju samo 1 fajl — da li ih zadržati kao foldere?

| Dir | Fajl | Referenciran? |
|-----|------|---------------|
| `audits/` | `FFI_UNWRAP_AUDIT_2026_01_21.md` | NE iz CLAUDE.md |
| `performance/` | `OPTIMIZATION_GUIDE.md` | DA |
| `project/` | `fluxforge-studio.md` | DA |
| `reviews/` | `ULTIMATE_SYSTEM_ANALYSIS_2026_01_23.md` | DA |
| `roadmap/` | `SLOTLAB_ROADMAP.md` | NE iz CLAUDE.md |
| `verification/` | `P13_FEATURE_BUILDER_VERIFICATION_2026_02_01.md` | NE iz CLAUDE.md |

**Preporuka:** Prebaciti nereferencirane u parent folder ili obrisati.

**Odluka:** ⏳ ČEKA POTVRDU

---

## PRIORITETI

| Prioritet | Kategorija | Akcija |
|-----------|------------|--------|
| **P0** | Kat. 6 | Obrisati `._*` iz celog projekta (codesign rizik) |
| **P1** | Kat. 1 | Popraviti 9 broken referenci u CLAUDE.md |
| **P1** | Kat. 2 | Utvrditi tačan status projekta |
| **P2** | Kat. 3-4 | Ažurirati INDEX.md i README.md |
| **P3** | Kat. 5 | Odlučiti o redundantnim root fajlovima |
| **P3** | Kat. 7 | Konsolidovati single-file direktorijume |

---

## UKUPNA PROCENA

| Metrika | Vrednost |
|---------|----------|
| Broken referenci u CLAUDE.md | 9 |
| Konfliktni status fajlovi | 4 |
| Broken linkovi u INDEX/README | 8 |
| AppleDouble fajlovi (ceo projekat) | 291+ (~34MB+) |
| Potencijalno nepotrebni root fajlovi | 6 |
| Potencijalno nepotrebni subdirektori | 3 |

**Posle čišćenja .claude/ ostalo:** 86 fajlova, 13MB (sa 729 / 95MB)
**Potencijalna dodatna ušteda:** ~34MB+ (AppleDouble iz celog projekta)
