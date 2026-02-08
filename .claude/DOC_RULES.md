# .claude/ Documentation Rules

**Status:** AKTIVNO — Obavezno za sve buduće sesije

---

## PRAVILO 1: Zabrana Session Report Spam-a

**NIKADA ne kreiraj ove tipove fajlova u .claude/:**

| Zabranjeno | Primer | Razlog |
|------------|--------|--------|
| Session summaries | `SESSION_2026_02_08_*.md` | Jednokratni, nikad se ne čitaju |
| Progress reports | `PROGRESS_REPORT_*.md` | Zastariju za 1 dan |
| Final status files | `*_FINAL_STATUS.md` | Redundantno sa MASTER_TODO |
| Changelog files | `CHANGELOG_*.md` | Git log postoji za to |
| Sprint summaries | `SPRINT_*_SUMMARY.md` | Jednokratni |
| Completion reports | `*_COMPLETE.md`, `*_100_PERCENT.md` | Redundantno |

**Umesto toga:**
- Ažuriraj POSTOJEĆE fajlove (MASTER_TODO.md, README.md)
- Koristi git commit poruke za promene
- Session kontekst čuvaj u Claude memory, ne u fajlovima

---

## PRAVILO 2: Struktura .claude/ Direktorijuma

**Dozvoljeni folderi:**

| Folder | Svrha | Max fajlova |
|--------|-------|-------------|
| `analysis/` | Duboke tehničke analize (samo ako se referenciraju) | 15 |
| `architecture/` | Arhitekturna dokumentacija | 30 |
| `audits/` | Sigurnosni/kvalitet auditi | 5 |
| `docs/` | Korisničke i tehničke reference | 10 |
| `domains/` | Domenski fajlovi (audio-dsp, engine-arch) | 5 |
| `guides/` | Kratke referentne kartice | 5 |
| `performance/` | Optimizacioni vodiči | 3 |
| `project/` | Projektna specifikacija | 3 |
| `reviews/` | Sistemske recenzije | 5 |
| `roadmap/` | Planovi razvoja | 3 |
| `specs/` | Tehničke specifikacije | 10 |
| `tasks/` | Aktivni task trackeri | 10 |
| `verification/` | Verifikacioni izveštaji | 5 |

**Zabranjeni folderi (ne kreiraj):**
- `sessions/` — session spam
- `reports/` — jednokratni izveštaji
- `features/` — koristiti tasks/ umesto toga
- `research/` — koristiti analysis/ umesto toga
- `synthesis/` — nepotrebno
- `mockups/` — nepotrebno
- `implementation/` — koristiti tasks/ umesto toga
- `reference/` — koristiti docs/ umesto toga

---

## PRAVILO 3: Pre Kreiranja Novog Fajla

**Obavezni koraci:**

1. **Proveri da li već postoji** — Grep po .claude/ za slične fajlove
2. **Proveri da li može biti ažuriranje** — Edituj postojeći umesto novog
3. **Proveri da li je referencirano** — Fajl MORA biti referenciran iz CLAUDE.md ili drugog authority dokumenta
4. **Proveri max broj** — Ne prelazi limite iz tabele iznad

**Ako fajl ne prolazi sva 4 provere → NE KREIRAJ GA.**

---

## PRAVILO 4: Imenovanje Fajlova

**Format:** `NAZIV_VELIKI_SLOVA_DATUM.md`

**Datum je opcion** — koristiti samo za fajlove koji zastarevaju (analize, auditi).

**Zabranjeni prefiksi:**
- `FINAL_` — ništa nije final
- `ULTIMATE_` — subjektivno
- `MASTER_` — samo za MASTER_TODO.md
- `COMPLETE_` — koristiti status oznake umesto toga

---

## PRAVILO 5: Root Level .claude/ Fajlovi

**Dozvoljeni root fajlovi (max 15):**
- `00_AUTHORITY.md` — Hijerarhija izvora istine
- `00_MODEL_USAGE_POLICY.md` — Pravila za Opus/Sonnet/Haiku
- `01_BUILD_MATRIX.md` — Build matrica
- `02_DOD_MILESTONES.md` — Definition of Done
- `03_SAFETY_GUARDRAILS.md` — Sigurnosna pravila
- `MASTER_TODO.md` — Glavni task tracker
- `REVIEW_MODE.md` — Review procedura
- `CLEANUP_TODO.md` — Cleanup tracker (privremeno)
- `DOC_RULES.md` — Ovaj fajl

**NIKADA ne dodavaj nove root fajlove bez eksplicitne dozvole korisnika.**

---

## PRAVILO 6: Periodično Čišćenje

**Na svakih ~10 sesija:**
1. Proveri .claude/ za fajlove koji nisu referencirani
2. Proveri veličinu foldera (`du -sh .claude/`)
3. Predloži brisanje zastarelih fajlova

**Target:** .claude/ ne sme prerasti 20MB ili 100 fajlova.
