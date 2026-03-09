# AUREXIS Unified Intelligence Panel — Architecture

## FluxForge Studio — SlotLab Layout Consolidation

---

# 1. PROBLEM & PHILOSOPHY

**Problem:** 11 nezavisnih audio intelligence sistema, 1000+ parametara, 20+ panela. Dizajner mora manualno da konfigurise sve i razmislja o interakcijama.

**AUREXIS resenje:** Jedan koherentan intelligence layer koji automatski orkestrira SVE sisteme. "Set the vibe, not the parameters."

**Core principi:**
- **Profile-Driven** — izaberi profil, sve radi automatski
- **Emergent Intelligence** — jedan slider kontrolise PONASANJE kroz vise sistema (npr. TENSION 0.3→0.8 menja ALE layer, stereo width, LPF cutoff, ducking, rollup speed, container blend)
- **Zero-Config Default** — inteligentni defaulti, sav tweaking opcioni
- **Jurisdiction-Aware** — regulatorni zahtevi per trziste (UK/UKGC, Australia, Malta, Nevada, Ontario)
- **Production Pipeline** — re-theme wizard, memory budget, coverage heatmap, compliance report

---

# 2. PANEL LAYOUT

AUREXIS panel zamenjuje UltimateAudioPanel (levo, 280px). Lower Zone se smanjuje sa 5×4=20 panela na 3 taba.

**AUREXIS Panel — 4 sekcije (kolapsibilne):**
1. **PROFILE** — profil selekcija, jurisdiction, intensity, quick dials, memory budget
2. **BEHAVIOR** — 4 grupe × 3 apstraktna slidera (12 ukupno)
3. **TWEAK** — per-system override (8 kompaktnih editora)
4. **SCOPE** — real-time vizualizacija (6 modova)

**Mode toggle u headeru:** Intel (intelligence) | Audio (408 slotova, UltimateAudioPanel sadrzaj). `Tab` shortcut.

**Lower Zone (novi):**
- TIMELINE: StageTrace | EventTimeline | EventLog
- MIX: BusMixer | AuxSends | BusMeters
- EXPORT: Validate | Package | Stems | Report | Re-Theme | Batch

---

# 3. PROFILE SYSTEM

## AurexisProfile Model

```dart
class AurexisProfile {
  final String id;
  final String name;
  final String description;
  final AurexisCategory category;
  final double intensity;        // 0.0-1.0 master intensity
  final AurexisBehaviorConfig behavior;
  // Per-system configs (auto-generated from behavior):
  final AleProfileConfig ale;
  final AutoSpatialProfileConfig spatial;
  final RtpcProfileConfig rtpc;
  final DuckingProfileConfig ducking;
  final WinTierProfileConfig winTiers;
  final ContainerProfileConfig containers;
  final FatigueProfileConfig fatigue;
  final MicroVariationConfig variation;
  final CollisionConfig collision;
  final PlatformProfileConfig platform;
}
```

## Built-in Profiles (12)

| # | Profile | Category | Intensity | Use Case |
|---|---------|----------|-----------|----------|
| 1 | Calm Classic | classic | 0.3 | Low volatility, gentle transitions |
| 2 | Standard Video | video | 0.5 | Standard video slot |
| 3 | High Volatility Thriller | highVol | 0.8 | Aggressive escalation, wide stereo |
| 4 | Megaways Chaos | megaways | 0.9 | Maximum variation, fast transitions |
| 5 | Hold & Win Tension | holdWin | 0.7 | Building suspense, locking focus |
| 6 | Jackpot Hunter | jackpot | 0.85 | Progressive buildup, epic payoff |
| 7 | Cascade Flow | cascade | 0.6 | Escalating pitch/width per cascade step |
| 8 | Asian Premium | themed | 0.5 | Cultural audio conventions |
| 9 | Mobile Optimized | platform | 0.4 | Compressed stereo, reduced fatigue |
| 10 | Headphone Spatial | platform | 0.6 | Exaggerated width, HRTF hints |
| 11 | Cabinet Mono-Safe | platform | 0.3 | Mono-compatible, bass managed |
| 12 | Silent Mode | utility | 0.0 | All intelligence OFF (manual only) |

**Profile UI:** Dropdown (built-in + custom), Jurisdiction dropdown, Intensity master slider, 3 Quick Dials (Volatility/Tension/Energy), A/B compare, Save As/Reset, Memory Budget bar.

**GDD Auto-Detection:** GDD import → score each profile against volatility/mechanic/features → auto-select best match + derive intensity and quick dials.

---

# 4. BEHAVIOR — Meta-Controls

Behavior parametri su APSTRAKTNI — opisuju PONASANJE, ne implementaciju. Svaki mapira na VISE underlying sistema.

## 4 Behavior Groups (12 params total)

**SPATIAL:** `width` (stereo sirina), `depth` (reverb/distance), `movement` (pan drift/motion)

**DYNAMICS:** `escalation` (intensity ramp aggressiveness), `ducking` (duck amount/timing), `fatigue` (HF attenuation/transient smoothing)

**MUSIC:** `reactivity` (ALE response speed), `layerBias` (default energy level), `transition` (crossfade duration)

**VARIATION:** `panDrift` (micro pan oscillation), `widthVar` (micro width oscillation), `timingVar` (micro timing variation). All deterministic via seed.

## Key Behavior → System Mappings

| Behavior Param | Affected Systems |
|---|---|
| spatial.width | AutoSpatial.globalWidthScale, ALE context layer width, Container blend range |
| spatial.movement | AutoSpatial.smoothingTauMs (inv), MicroVariation.panDriftRange |
| dynamics.escalation | WinTier audio intensity, RTPC curve steepness, ALE rule thresholds, Cascade pitch step |
| dynamics.ducking | DuckingRule amount/attack/release, Bus priority |
| dynamics.fatigue | HF attenuation onset, Transient smoothing rate, Width compression |
| music.reactivity | ALE stability.cooldownMs (inv), ALE eval frequency, Layer transition speed |
| music.transition | ALE transition profile (beat/bar/phrase), Crossfade duration |
| variation.* | MicroVariation amplitudes per dimension |

## Mapping Function Examples

```dart
double aleRuleThresholdFromEscalation(double escalation) => lerp(0.9, 0.2, escalation);
double duckAmountFromDucking(double ducking) => lerp(-2.0, -18.0, ducking);
double widthScaleFromSpatialWidth(double width) => lerp(0.15, 1.0, width);
int cooldownFromReactivity(double reactivity) => lerp(5000.0, 50.0, pow(1 - reactivity, 2)).round();
```

## Lock System

```dart
class AurexisBehaviorLocks {
  bool spatialLocked = false;
  bool dynamicsLocked = false;
  bool musicLocked = false;
  bool variationLocked = false;
  final Set<String> lockedSystems = {};
}
```

Locked groups are not affected by profile changes or other group slider changes.

---

# 5. TWEAK — Per-System Override

8 sistema sa kompaktnim inline editorima: ALE, Spatial, RTPC, Ducking, WinTiers, Containers, Fatigue, Variation.

Svaki editor prikazuje samo kljucne kontrole + "Full Editor" link koji otvara full panel u Lower Zone.

**Key compact editors:**
- **ALE:** Context selector, Level radio, Quick Rules (top 3), Stability params
- **Spatial:** Global Width/Pan, Bus overrides (SFX/Music/UI multipliers)
- **RTPC:** Active RTPCs with live values, Quick Bind (parameter → target + curve)
- **Ducking:** Active rules list (source → target, amount, attack/release)
- **Win Tiers:** Preset, Big Win threshold, Audio Intensity/Rollup Speed sliders
- **Containers:** Blend/Random/Sequence counts, Global Smoothing, Deterministic toggle
- **Fatigue:** Session time, HF exposure, Onset time, Max reduction, Transient smooth
- **Variation:** Seed mode, Pan/Width/Timing/Harmonic ranges, Preview button

---

# 6. SCOPE — Real-Time Visualization (6 Modes)

1. **Stereo Field** (default) — 2D voice plot, X=pan, Y=depth, size=volume, color=bus, collision zones
2. **Energy Density** — Frequency band horizontal bars, energy distribution
3. **Signal Monitor** — Sparklines for top 4 ALE signals, threshold lines
4. **Voice Cluster** — Pie chart per bus, collision counter, priority stack
5. **Coverage Heatmap** — Grid overlay showing assigned/fallback/missing audio per stage, per-section percentages, "Show Missing" navigation
6. **Cabinet Sim** — Speaker profile simulation (9 built-in), ambient noise overlay, frequency response display, monitoring-only

---

# 7. RESOLUTION ENGINE

## Pipeline (on any behavior change)

1. Start with profile base values
2. Apply behavior multipliers
3. Apply per-system tweak overrides
4. Apply lock constraints
5. Clamp to valid ranges
6. Push to providers/FFI (debounced 50ms)

```dart
// Push targets:
AleProvider.updateFromAurexis(config)
AutoSpatialProvider.updateFromAurexis(config)
RtpcSystemProvider.updateFromAurexis(config)
DuckingSystemProvider.updateFromAurexis(config)
WinTierConfig.updateFromAurexis(config)
ContainerService.updateFromAurexis(config)
```

---

# 8. JURISDICTION ENGINE

## JurisdictionProfile Model

```dart
class JurisdictionProfile {
  final String id;              // 'uk_ukgc', 'au_victoria', 'us_nevada'
  final String name;
  final String regulatoryBody;
  final JurisdictionRules rules;
}

class JurisdictionRules {
  final bool suppressLdwCelebration;
  final LdwBehavior ldwBehavior;           // silence | reducedSfx | neutralTone | standard
  final int? maxCelebrationDurationMs;
  final int? maxRollupDurationMs;
  final double? minSpinDurationSec;
  final bool allowLoopingWinAudio;
  final bool allowEscalatingPitch;
  final double? maxWinAudioDb;
  final bool requireFatigueMitigation;
  final int? mandatoryFatigueOnsetMinutes;
  final bool requireAudioMuteOption;
  final List<String> requiredDocumentation;
  final String? auditStandard;             // 'GLI-11', 'BMM-100'
}
```

## Built-in Jurisdictions (9)

| Jurisdiction | ID | Key Rules |
|---|---|---|
| UK (UKGC) | `uk_ukgc` | LDW suppression, 2.5s min spin, 8s max celebration |
| Malta (MGA) | `mt_mga` | Standard EU, fatigue recommended |
| Nevada (NGC) | `us_nevada` | GLI-11 compliance |
| New Jersey (DGE) | `us_nj` | GLI-11 + NJ-specific |
| Ontario (AGCO) | `ca_ontario` | LDW awareness, RG features |
| Victoria (VCGLR) | `au_victoria` | LDW suppression, strict limits |
| NSW (L&GNSW) | `au_nsw` | Similar to Victoria |
| Isle of Man (GSC) | `im_gsc` | UK-adjacent rules |
| Curacao (GCB) | `cw_gcb` | Minimal restrictions |

## LDW Detection

```dart
class LdwDetector {
  static bool isLdw(double winAmount, double betAmount) => winAmount > 0 && winAmount < betAmount;
  static AudioBehavior getAudioBehavior({required double winAmount, required double betAmount, required JurisdictionRules rules});
}
```

Integration: EVALUATE_WINS → LdwDetector → suppress WIN_PRESENT_*/ROLLUP_*/BIG_WIN_* → replace with WIN_PRESENT_NEUTRAL.

## CelebrationLimiter

Schedules fade-out 500ms before jurisdiction max duration. `CelebrationLimiter.startCelebration(tierDurationMs)`.

## Multi-Jurisdiction Export

Jedan projekat → checkbox lista jurisdikcija → odvojeni paketi per jurisdikcija sa manifest-om.

---

# 9. MEMORY BUDGET BAR

16px traka na dnu AUREXIS panela — uvek vidljiva.

```dart
class MemoryBudgetCalculator {
  static MemoryBreakdown calculate(List<AudioAssignment> assignments);
}
```

**Platform budgets:** Mobile 6MB, Mobile Light 3MB, Web 4MB, Desktop 24MB, Cabinet 16MB.

**Visual states:** 0-60% green, 60-80% yellow, 80-95% orange, 95-100% red.

**Click → Breakdown popup:** Per-section usage + actionable suggestions (e.g., "Convert music to 22kHz mono → -1.2 MB") with "Apply All" button.

---

# 10. COVERAGE HEATMAP (SCOPE Mode 5)

Grid overlay na slot mockup: zeleno (dedicated audio), zuto (fallback), crveno (missing), sivo (N/A).

Per-section percentages. "Show Missing" filtrira Audio mode na nedodeljene slotove.

```dart
class CoverageSuggestion {
  final String missingStage;
  final String? suggestedAudio;
  final String reason;
  final double confidence;
}
```

Klik na crvenu zonu → skok na slot u Audio mode + suggestion popup.

---

# 11. CABINET SIM (SCOPE Mode 6)

Monitoring-only — zero impact on export. EQ filter simulating speaker response + pink noise for ambient.

**9 speaker profiles:** IGT CrystalDual 27/43, Aristocrat MarsX/Arc, Generic 2.1, Headphone Reference, Mobile Phone, Tablet, Custom.

**Ambient noise profiles:** Casino Floor (85/90 dBA), Quiet Room (40 dBA), Mobile Outdoor/Transit (70/80 dBA), None.

---

# 12. COMPLIANCE REPORT

One-click in EXPORT tab. 8-section report: Audio Manifest, LDW Compliance, Celebration Durations, Loudness Analysis, Fatigue Mitigation, Determinism Verification, Responsible Gaming, Change Log.

**Export formats:** PDF, JSON, CSV, HTML.

```dart
class ComplianceReport {
  static ComplianceDiff generateDiff(ComplianceReport previous, ComplianceReport current);
}
```

---

# 13. RE-THEME WIZARD

3-step flow: Source project → Target theme folder → Review & Apply.

**Match strategies:** `namePattern`, `stageMapping`, `folderStructure`, `manual`. Fuzzy matching with configurable threshold.

Output: Novi projekat sa istim stage mapping-om, gap report, mapping JSON (bidirectional). AUREXIS profil ostaje isti.

---

# 14. AUDIT TRAIL

Automatic background change logging. Zero UI surface osim "Export Audit Trail" u EXPORT tabu.

```dart
class AuditLogEntry {
  final DateTime timestamp;
  final String userId;
  final AuditAction action;
  final String targetStage;
  final String? oldValue;
  final String? newValue;
  final String? reason;
  final String projectVersion;
}

enum AuditAction {
  audioAssigned, audioRemoved, audioReplaced, volumeChanged, panChanged,
  profileChanged, jurisdictionChanged, behaviorChanged, tweakChanged,
  projectLocked, projectUnlocked, exportGenerated, reportGenerated,
}
```

Ring buffer (10,000 entries), async persistence to .ffaudit file. `AuditTrailService` singleton.

**ProjectLock:** Freeze project for submission — all audio controls disabled, unlock requires reason. Hooks into MiddlewareProvider, SlotLabProjectProvider, AurexisProvider, UltimateAudioPanel, DropTargetWrapper.

---

# 15. PROFILE JSON FORMAT

```json
{
  "id": "megaways_chaos",
  "name": "Megaways Chaos",
  "version": 2,
  "category": "megaways",
  "intensity": 0.9,
  "jurisdiction": "uk_ukgc",
  "quickDials": { "volatility": 0.95, "tension": 0.8, "energy": 0.6 },
  "behavior": {
    "spatial": { "width": 0.85, "depth": 0.7, "movement": 0.65 },
    "dynamics": { "escalation": 0.9, "ducking": 0.7, "fatigue": 0.5 },
    "music": { "reactivity": 0.8, "layerBias": 0.5, "transition": 0.4 },
    "variation": { "panDrift": 0.4, "widthVar": 0.3, "timingVar": 0.5 }
  },
  "systemOverrides": { "ale": {}, "ducking": {}, "winTiers": {} },
  "jurisdictionOverrides": { "au_victoria": { "behavior": {} } },
  "platformOverrides": { "mobile": { "behavior": {} } }
}
```

---

# 16. VISUAL IDENTITY & SHORTCUTS

**AUREXIS Accent:** #8B5CF6 (Violet). Gradient: #8B5CF6 → #6366F1. Panel bg: #0F0A1A.

**Key shortcuts:** `Tab` Intel/Audio toggle, `1-4` Behavior group, `P` Profile, `J` Jurisdiction, `T` Tweak, `S` Scope, `A` A/B compare, `R` Reset group, `L` Lock group, `M` Memory breakdown, `Ctrl+Z` Undo.

---

# 17. IMPLEMENTATION PLAN

| Phase | Scope | LOC |
|---|---|---|
| 1. Provider + Models | AurexisProvider, AurexisProfile, AurexisBehaviorConfig, AurexisResolver, 12 JSON profiles | ~800 |
| 2. Panel Widget | aurexis_panel.dart + 4 section widgets, mode toggle, collapsible sections | ~1,200 |
| 3. Resolver Engine | Mapping functions (12 behaviors → 11 systems), lock system, A/B morph, debounced push | ~500 |
| 4. System Integration | `+updateFromAurexis()` on 6 providers (ALE, AutoSpatial, RTPC, Ducking, WinTier, Container) | ~600 |
| 5. Lower Zone Consolidation | 3 tabs (Timeline/Mix/Export) replacing 5×4 layout | ~400 (-600 removed) |
| 6. Jurisdiction Engine | JurisdictionProfile, JurisdictionService, LdwDetector, CelebrationLimiter | ~650 |
| 7. Budget + Coverage | MemoryBudgetCalculator, budget bar widget, CoverageHeatmap, CoverageSuggestion | ~500 |
| 8. Cabinet + Report | CabinetSimService (9 speaker profiles), ComplianceReportService (4 formats) | ~550 |
| 9. Re-Theme + Audit | ReThemeWizard (4 match strategies), AuditTrailService, ProjectLock | ~650 |
| 10. Dead Code Cleanup | Remove _buildBottomPanel, _buildRightPanel, _BottomPanelTab | -800 |
| **TOTAL** | | **~4,050 net** |

**File locations:**
- `flutter_ui/lib/providers/aurexis_provider.dart`
- `flutter_ui/lib/models/aurexis_models.dart`
- `flutter_ui/lib/services/aurexis_resolver.dart`
- `flutter_ui/lib/services/jurisdiction_service.dart`
- `flutter_ui/lib/services/memory_budget_service.dart`
- `flutter_ui/lib/services/cabinet_sim_service.dart`
- `flutter_ui/lib/services/compliance_report_service.dart`
- `flutter_ui/lib/services/audit_trail_service.dart`
- `flutter_ui/lib/widgets/aurexis/` (panel + section widgets)
- `flutter_ui/lib/data/aurexis_profiles/` (12 JSON profiles)

---

# 18. MIGRATION PATH

1. Dodaj AUREXIS panel PORED UltimateAudioPanel (paralelno, zero breaking changes)
2. AUREXIS postaje default, UltimateAudioPanel kao fallback
3. UltimateAudioPanel uklonjen, Audio mode u AUREXIS-u ga zamenjuje

Lower Zone analogno: novi tabovi pored starih → "Legacy" opcija → uklonjeni.

---

# 19. SUMMARY

AUREXIS transformise SlotLab od 11 sistema × 10+ UI povrsina × 1000+ parametara u 1 panel × 12 behavior slidera + profili + jurisdiction intelligence + production pipeline.

**7 unique features:** Jurisdiction Engine, Compliance Report, Memory Budget Bar, Coverage Heatmap, Cabinet Sim, Re-Theme Wizard, Audit Trail.
