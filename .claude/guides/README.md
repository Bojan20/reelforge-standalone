# FluxForge Studio — Guides Index

**Purpose:** Quick navigation to all development guides
**Created:** 2026-01-26

---

## 🎯 Model Selection (CRITICAL — Read First)

**Primary Document:**
- [00_MODEL_USAGE_POLICY.md](../.claude/00_MODEL_USAGE_POLICY.md) — **Ultimate policy (no gaps)**

**Quick References:**
- [MODEL_SELECTION_CHEAT_SHEET.md](MODEL_SELECTION_CHEAT_SHEET.md) — 3-second decision guide
- [MODEL_DECISION_FLOWCHART.md](MODEL_DECISION_FLOWCHART.md) — ASCII flowcharts

**TL;DR:**
- **Opus** = Architecture/vision (10% of work)
- **Sonnet** = Implementation/analysis (90% of work)
- **Default:** When uncertain → Sonnet

---

## 📚 Development Guides

### Code Patterns
- [PROVIDER_ACCESS_PATTERN.md](PROVIDER_ACCESS_PATTERN.md) — Standard Provider usage ✅

### Build & Deploy
- [BUILD_PROCEDURES.md](../../CLAUDE.md#kritično-full-build-procedura) — See CLAUDE.md

### Testing
- (Planned: TESTING_GUIDE.md)

### Architecture
- See `.claude/architecture/` folder

---

## 🔗 External Resources

**Root Documents:**
- [CLAUDE.md](../../CLAUDE.md) — Main project instructions
- [.claude/00_AUTHORITY.md](../.claude/00_AUTHORITY.md) — Truth hierarchy

**Architecture Docs:**
- `.claude/architecture/` — All system designs

**Analysis Reports:**
- `.claude/analysis/` — Code analysis outputs

**Task Tracking:**
- `.claude/tasks/` — TODO lists and task docs

---

## 🆘 Quick Help

**"Which model should I use?"**
→ [MODEL_SELECTION_CHEAT_SHEET.md](MODEL_SELECTION_CHEAT_SHEET.md)

**"How do I build the project?"**
→ [CLAUDE.md — Build Procedures](../../CLAUDE.md#kritično-full-build-procedura)

**"What takes priority when docs conflict?"**
→ [00_AUTHORITY.md](../.claude/00_AUTHORITY.md)

**"What are the current tasks?"**
→ `.claude/tasks/DAW_LOWER_ZONE_TODO_2026_01_26.md` (P0 ✅, P1 ✅, P2/P3 ⏳)

**"How do I use the Command Palette?"**
→ Press **Cmd+K** (Mac) or **Ctrl+K** (Windows/Linux) to open

---

**Last Updated:** 2026-01-29

### Recent Completions

| Date | Feature | Location |
|------|---------|----------|
| 2026-01-29 | P1.2 Command Palette (Cmd+K) | `widgets/common/command_palette.dart` |
| 2026-01-29 | P0.1 Dead code cleanup (62% reduction) | `daw_lower_zone_widget.dart` |
| 2026-01-29 | P0.2-P0.8 Critical fixes | Various DAW files |
