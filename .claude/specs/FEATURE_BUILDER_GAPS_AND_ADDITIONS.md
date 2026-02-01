# 🔍 FEATURE BUILDER — Gap Analysis & Additional Features

**Version:** 1.0.0
**Created:** 2026-02-01
**Status:** ANALYSIS COMPLETE

---

## 1. GAPS IDENTIFIED IN ORIGINAL SPEC

Tokom analize codebase-a i pisanja ultimate specifikacije, identifikovao sam sledeće praznine u originalnoj ideji koje sam dopunio:

### 1.1 Nedostajuće iz originala → Dodato

| Gap | Original | Dodato u Ultimate Spec |
|-----|----------|------------------------|
| **Rust engine sync** | Nije pomenuto | Full FFI integracija (sekcija 5.3) |
| **Validation system** | Nije pomenuto | 15+ pravila, auto-fix (sekcija 10) |
| **Stage generation** | Implicitno | Eksplicitni stage katalog (sekcija 16) |
| **Audio integration** | "audio hookovi" | Detaljna UltimateAudioPanel integracija (sekcija 9) |
| **P5 Win Tier** | "Win tiers" generički | Puna P5 integracija sa svim tier-ima |
| **ALE integration** | "Music states" | Context switching, signal mapping |
| **Dependency graph** | Tekstualni opis | Vizualni dijagram + matrix |
| **Block options detail** | Checkboxi | Kompletne opcije po bloku |
| **Preset file format** | Nije pomenuto | JSON schema v1.0.0 |
| **Implementation phases** | Nije pomenuto | 9 faza, 24 dana, ~10,900 LOC |
| **Visual Transitions** | "tranzicije" generički | Kompletna sekcija 5.2.5 + 5.4 sa TransitionDefinition, AnimationStep, Element Mapping |
| **Mockup Integration** | Nije eksplicitno | Sekcija 5.4 detaljno opisuje workflow Ručni Mockup → Feature Builder → Sinhronizovane tranzicije |
| **Industry Game Flow** | Implicitno | Nova sekcija 5.5 — kompletni flow patterns od Big Time Gaming, NetEnt, Pragmatic Play, Aristocrat, IGT |
| **Cascade Multiplier Escalation** | Pomenuto | Sekcija 5.5.2.A — detaljan per-step multiplier sistem sa pitch/volume eskalacijom |
| **Hold & Win Respin Reset** | Nije pomenuto | Sekcija 5.5.2.B — ključna mehanika: novi coin = reset respins na 3 |
| **Anticipation Tension Levels** | Osnovni | Sekcija 5.5.3 — L1-L4 tension sistem po reelu sa stage formatom `ANTICIPATION_TENSION_R{X}_L{Y}` |
| **Creation-Escalation-Resolution** | Nije pomenuto | Sekcija 5.5.2.A — Play'n GO dizajn filozofija dokumentovana |
| **Retrigger Math Table** | Samo pomenuto | Sekcija 5.5.2.C — eksplicitna tabela scatter→spin mapiranja |
| **Feature Music Context Switch** | Implicitno | Sekcija 5.5.2.C — FS_MUSIC_LOOP kao eksplicitan stage |
| **Multi-Level Bonus** | Nije pokriveno | Sekcija 5.5.2.D — Trail/Level bonus pattern dokumentovan |
| **TRANSITIONS Block** | Implicitno u vizualima | **NOVA SEKCIJA 3.3.3** — Kompletan konfiguracioni blok sa 11 predefinisanih tranzicija, per-transition opcijama, visual type library, audio sync points, industry reference stilovi |
| **Industry Transition Research** | Surface-level | **SEKCIJE F.1-F.9** — Spine 2D kao industry standard, detaljni phase breakdown za FS/HNW/Cascade/BigWin tranzicije, timing matrix, easing reference, Spine integration architecture |
| **Free Spins Transition Phases** | Jedan stage | Sekcija F.2 — 3-fazni breakdown (Trigger→Logo Reveal→Counter Setup) sa NetEnt i Pragmatic stilovima |
| **Hold & Win Lightning Pattern** | Generički | Sekcija F.3 — Aristocrat Lightning Link pattern sa Reel Lock, Electric VFX, Respin Reset mehanikom |
| **Cascade/Tumble Transition** | Samo CASCADE_STEP | Sekcija F.4 — 4-fazni BTG Megaways pattern (Eval→Destruction→Gravity Fall→Settle) sa pitch/volume escalation per step |
| **Big Win Celebration System** | Win tiers | Sekcija F.5 — Universal pattern sa 4 faza (Impact→Rollup→Celebration→Exit), tier-specific rollup timing |
| **Anticipation Technical Spec** | L1-L4 mentioned | Sekcija F.6 — Per-reel tension levels sa visual elements, audio stages, resolution branches |
| **Animation Easing Reference** | Implicitno | Sekcija F.7 — 6 industry-standard curves sa CSS equivalents + Spine blend modes |
| **Transition Timing Matrix** | Hardcoded | Sekcija F.8 — Min/Optimal/Max/SkipAfter timing za 11 tranzicija (estimated industry ranges) |
| **Spine Integration Architecture** | Nije pokriveno | Sekcija F.9 — Full pipeline diagram: Spine Editor → Flutter Runtime → Audio Stage Triggers |

### 1.2 Arhitekturne odluke koje sam doneo

| Odluka | Alternativa | Zašto izabrano |
|--------|-------------|----------------|
| **Dockable panel** | Modal, Tab | Side-by-side rad sa mockupom |
| **Provider pattern** | BLoC, Riverpod | Konzistentnost sa ostatkom projekta |
| **JSON presets** | Binary, YAML | Čitljivost, debuggability, verzioniranje |
| **Block registry** | Hardcoded lista | Plugin extensibility |
| **Slide-out settings** | Inline expand | Više prostora za opcije |

---

## 2. DODATNI FEATURE-I KOJE PREDLAŽEM

### 2.1 BLOCK: ANTICIPATION (Nedostaje u originalu)

**Zašto je potreban:**
- Anticipation je KLJUČNI audio moment u slot igrama
- Već postoji u Rust engine-u (AnticipationConfig sa Tip A/B)
- Dizajner treba da konfiguriše kada i kako se trigeruje

**Predlog opcija:**

| Option | Values | Default |
|--------|--------|---------|
| **Pattern** | Tip A (all reels), Tip B (0,2,4 only) | Tip A |
| **Trigger Symbol** | Scatter, Bonus, Any Special | Scatter |
| **Min Count** | 2, 3 | 2 |
| **Tension Escalation** | None, Linear, Exponential | Linear |
| **Audio Per Reel** | Single, Per-reel variants | Per-reel |

**Generated Stages:**
```
ANTICIPATION_ON
ANTICIPATION_TENSION_R1_L1, R1_L2, R1_L3, R1_L4
ANTICIPATION_TENSION_R2_L1, R2_L2, R2_L3, R2_L4
... (per reel, per level)
ANTICIPATION_OFF
```

### 2.2 BLOCK: GAMBLE (Pomenuto u Rust-u, nedostaje u spec-u)

**Zašto je potreban:**
- Gamble feature postoji u rf-slot-lab (`gamble.rs`, 383 LOC)
- Popularan u Evropskim tržištima
- Audio je specifičan (tenzija, dobitak/gubitak)

**Predlog opcija:**

| Option | Values | Default |
|--------|--------|---------|
| **Gamble Type** | Card Color, Card Suit, Coin Flip | Card Color |
| **Max Attempts** | 1, 3, 5, Unlimited | 5 |
| **Max Win Limit** | None, 2x, 5x, 10x original | 5x |
| **Auto-Collect** | None, After 3 wins, At limit | At limit |

**Generated Stages:**
```
GAMBLE_OFFER        → Win achieved, gamble offered
GAMBLE_ENTER        → Player accepts gamble
GAMBLE_CHOICE       → Waiting for player choice
GAMBLE_REVEAL       → Card/coin revealed
GAMBLE_WIN          → Gamble won
GAMBLE_LOSE         → Gamble lost, original win forfeit
GAMBLE_COLLECT      → Player collects winnings
GAMBLE_EXIT         → Return to base game
```

### 2.3 BLOCK: JACKPOT (Standalone, ne samo u H&W)

**Zašto je potreban:**
- Jackpot može biti nezavisan od Hold & Win
- Random trigger, meter trigger, symbol trigger
- 4-tier sistem (Mini, Minor, Major, Grand) je standard

**Predlog opcija:**

| Option | Values | Default |
|--------|--------|---------|
| **Trigger Mode** | Random, Meter, Symbol Combo | Random |
| **Tiers** | Mini only, Mini+Minor, All 4 | All 4 |
| **Progressive** | Yes, No | Yes |
| **Contribution** | 0.5%, 1%, 2% of bet | 1% |
| **Seed Values** | Configurable per tier | 10/25/100/500 |
| **Display** | Always visible, On trigger only | Always |

**Generated Stages:**
```
JACKPOT_CONTRIBUTION    → Bet contributes to pool
JACKPOT_NEAR_TRIGGER    → Close to triggering (meter)
JACKPOT_TRIGGER         → Jackpot triggered
JACKPOT_REVEAL_TIER     → Which tier won
JACKPOT_MINI_WIN        → Mini jackpot awarded
JACKPOT_MINOR_WIN       → Minor jackpot awarded
JACKPOT_MAJOR_WIN       → Major jackpot awarded
JACKPOT_GRAND_WIN       → Grand jackpot awarded
JACKPOT_CELEBRATION     → Celebration sequence
JACKPOT_END             → Return to game
```

### 2.4 BLOCK: BONUS GAME (Generički)

**Zašto je potreban:**
- Pick bonus, Wheel bonus, Trail bonus
- Različiti od Free Spins
- Već postoji `pick_bonus.rs` (603 LOC)

**Predlog opcija:**

| Option | Values | Default |
|--------|--------|---------|
| **Bonus Type** | Pick, Wheel, Trail, Custom | Pick |
| **Trigger** | Scatter, Bonus Symbol, Random | Bonus Symbol |
| **Picks/Spins** | 3, 5, Until Collect | 3 |
| **Reveal Style** | Instant, One-by-one, All at once | One-by-one |
| **Multiplier** | None, Fixed, Random | Random |

**Generated Stages:**
```
BONUS_TRIGGER           → Bonus game triggered
BONUS_INTRO             → Transition animation
BONUS_PICK_PROMPT       → Waiting for pick
BONUS_PICK_REVEAL       → Reveal picked item
BONUS_PRIZE_AWARD       → Prize awarded
BONUS_COLLECT           → Collect trigger hit
BONUS_TOTAL_WIN         → Final total shown
BONUS_OUTRO             → Return to base game
```

### 2.5 BLOCK: MULTIPLIER SYSTEM (Standalone)

**Zašto je potreban:**
- Multiplieri nisu samo u Cascades
- Random multipliers, Win multipliers, Feature multipliers
- Kritični za audio (eskalacija)

**Predlog opcija:**

| Option | Values | Default |
|--------|--------|---------|
| **Multiplier Source** | Random, Win-based, Cascade, Symbol | Random |
| **Base Value** | 1x, 2x | 1x |
| **Max Value** | 5x, 10x, 100x, Unlimited | 10x |
| **Step** | +1x, ×2, Random | +1x |
| **Persistence** | Per spin, Per feature, Sticky | Per spin |
| **Visual** | Meter, Number, Symbol | Number |

**Generated Stages:**
```
MULTIPLIER_ACTIVE       → Multiplier in play
MULTIPLIER_INCREASE     → Multiplier goes up
MULTIPLIER_DECREASE     → Multiplier goes down
MULTIPLIER_MAX          → Maximum reached
MULTIPLIER_APPLY        → Multiplier applied to win
MULTIPLIER_RESET        → Multiplier resets
```

### 2.6 BLOCK: WILD FEATURES (Expanded)

**Zašto je potreban:**
- Wild behavior ima mnogo varijanti
- Expanding, Sticky, Walking, Multiplier, Stacked
- Svaki ima specifične audio momente

**Predlog opcija:**

| Option | Values | Default |
|--------|--------|---------|
| **Wild Type** | Standard, Expanding, Sticky, Walking, Multiplier, Stacked | Standard |
| **Expand Direction** | Vertical, Horizontal, Both, Full reel | Vertical |
| **Sticky Duration** | 1 spin, Feature, Until win | Feature |
| **Walk Direction** | Left, Right, Random | Left |
| **Multiplier Value** | 2x, 3x, Random 2-5x | 2x |
| **Stack Size** | 2, 3, Full reel | 3 |

**Generated Stages:**
```
WILD_LAND               → Wild symbol lands
WILD_EXPAND_START       → Expansion begins
WILD_EXPAND_STEP        → Each cell expansion
WILD_EXPAND_COMPLETE    → Full expansion done
WILD_STICK              → Wild becomes sticky
WILD_WALK               → Wild moves position
WILD_MULTIPLIER_APPLY   → Multiplier applied
WILD_TRANSFORM          → Symbol transforms to wild
WILD_REMOVE             → Sticky wild removed
```

---

## 3. PROŠIRENA DEPENDENCY MATRICA

Sa novim blokovima:

| Block | Enables | Requires | Modifies | Conflicts |
|-------|---------|----------|----------|-----------|
| **Game Core** | All | None | None | None |
| **Grid** | None | Game Core | None | None |
| **Symbol Set** | None | Game Core | None | None |
| **Free Spins** | Respin (in FS) | Scatter symbol | Win Presentation | None |
| **Respin** | None | None | Spin flow | Hold & Win |
| **Hold & Win** | Collector, Jackpot | Coin symbol | Disables spin | Respin |
| **Cascades** | Multiplier | None | Win Presentation | None |
| **Collector** | None | Special symbol | None | None |
| **Win Presentation** | None | None | None | None |
| **Music States** | None | None | All audio | None |
| **Anticipation** | None | Scatter/Bonus | Reel timing | None |
| **Gamble** | None | None | Win flow | None |
| **Jackpot** | None | None | Win Presentation | None |
| **Bonus Game** | None | Bonus symbol | Game flow | None |
| **Multiplier** | None | None | Win calculation | None |
| **Wild Features** | None | Wild symbol | Win evaluation | None |

---

## 4. STAGE CATEGORIZATION ZA ULTIMATE AUDIO PANEL

### Predlog nove organizacije sekcija:

| # | Section | Blocks | Stages | Color |
|---|---------|--------|--------|-------|
| 1 | Base Game | Core | 15 | #4A9EFF |
| 2 | Symbols | Symbols, Wild | 20 | #9370DB |
| 3 | Win Presentation | Win Pres | 25 | #FFD700 |
| 4 | Cascading | Cascades | 10 | #FF6B6B |
| 5 | Multipliers | Multiplier | 8 | #FF9040 |
| 6 | Free Spins | Free Spins | 10 | #40FF90 |
| 7 | Bonus Games | Bonus | 12 | #9370DB |
| 8 | Hold & Win | H&W | 15 | #40C8FF |
| 9 | Jackpots | Jackpot | 12 | #FFD700 |
| 10 | Gamble | Gamble | 10 | #FF6B6B |
| 11 | Anticipation | Anticipation | 20 | #FFA500 |
| 12 | Music & Ambient | Music | 15 | #40C8FF |
| 13 | UI & System | Core | 10 | #808080 |

**Total: ~180 stages** (sa dinamičkim dodavanjem)

---

## 5. VALIDATION RULES CATALOG

### 5.1 Error Rules (blokiraju Apply)

| ID | Rule | Message |
|----|------|---------|
| E001 | Scatter required for FS scatter trigger | "Enable Scatter in Symbol Set" |
| E002 | Bonus symbol required for Bonus game | "Enable Bonus symbol in Symbol Set" |
| E003 | Coin symbol required for Hold & Win | "Enable special symbol (Coin) in Symbol Set" |
| E004 | Wild required for Wild Features | "Enable Wild in Symbol Set" |
| E005 | Grid too small for feature | "Increase grid size for Hold & Win (min 5x3)" |

### 5.2 Warning Rules (dozvoljavaju Apply)

| ID | Rule | Message |
|----|------|---------|
| W001 | Cascades + FS = long sequences | "Consider limiting cascades during FS" |
| W002 | Multiple jackpot sources | "Both H&W and standalone Jackpot enabled" |
| W003 | High volatility + low hit rate | "May result in extended dry spells" |
| W004 | Too many features | "5+ features may confuse players" |
| W005 | No win presentation | "Players won't see win feedback" |

### 5.3 Info Rules (informativne)

| ID | Rule | Message |
|----|------|---------|
| I001 | New stages need audio | "12 new stages registered" |
| I002 | Feature not common | "Gamble feature uncommon in US market" |
| I003 | Testing recommended | "Complex config, thorough testing advised" |

---

## 6. PRESET CATEGORIES

### 6.1 By Game Style

| Category | Description | Example Presets |
|----------|-------------|-----------------|
| **classic** | Traditional slots | 3x3 Fruit, 5x3 Lines |
| **video** | Modern video slots | Ways 243, Cascades |
| **megaways** | Dynamic reels | Megaways 117649 |
| **cluster** | Cluster pays | 7x7 Cluster |
| **holdwin** | Hold & Win style | Lightning Link style |
| **jackpot** | Jackpot focused | Progressive 4-tier |

### 6.2 By Complexity

| Level | Features | Target |
|-------|----------|--------|
| **Simple** | Core + Win | Beginners |
| **Standard** | + FS | Most games |
| **Advanced** | + Cascades/HNW | Experienced |
| **Complex** | All features | Testing/Demo |

### 6.3 By Market

| Market | Common Features | Avoid |
|--------|-----------------|-------|
| **US Social** | FS, Cascades, Jackpot | Gamble |
| **Europe** | FS, Gamble, Bonus | — |
| **Asia** | H&W, Jackpot, FS | — |
| **LatAm** | Jackpot, Gamble | — |

---

## 7. KEYBOARD SHORTCUTS

### 7.1 Panel Navigation

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+F` | Toggle Feature Builder panel |
| `Escape` | Close settings sheet / panel |
| `Tab` | Navigate between blocks |
| `Space` | Toggle selected block |
| `Enter` | Open block settings |

### 7.2 Quick Actions

| Shortcut | Action |
|----------|--------|
| `Ctrl+Enter` | Apply configuration |
| `Ctrl+R` | Reset to defaults |
| `Ctrl+S` | Save current as preset |
| `Ctrl+O` | Load preset |
| `Ctrl+Z` | Undo last change |

### 7.3 Block Quick Enable

| Shortcut | Block |
|----------|-------|
| `1` | Free Spins |
| `2` | Respin |
| `3` | Hold & Win |
| `4` | Cascades |
| `5` | Collector |
| `6` | Anticipation |
| `7` | Gamble |
| `8` | Jackpot |
| `9` | Bonus Game |
| `0` | Multiplier |

---

## 8. TELEMETRY & ANALYTICS HOOKS

### 8.1 Configuration Events

```dart
// Track what features are most used
AnalyticsEvent.featureEnabled(blockId: 'freeSpins');
AnalyticsEvent.presetLoaded(presetId: 'classic-5x3');
AnalyticsEvent.configurationApplied(blockCount: 6);
```

### 8.2 Usage Patterns

| Metric | Purpose |
|--------|---------|
| Most enabled blocks | Feature popularity |
| Most used presets | Starting point preference |
| Validation errors | Common mistakes |
| Time in panel | UX friction indicator |
| Apply frequency | Iteration speed |

---

## 9. ACCESSIBILITY REQUIREMENTS

### 9.1 Screen Reader Support

- All blocks have `semanticsLabel`
- Dependency warnings announced
- Validation results read aloud
- Apply confirmation spoken

### 9.2 Keyboard Navigation

- Full panel usable without mouse
- Focus indicators visible
- Tab order logical
- Escape closes overlays

### 9.3 Color Considerations

- Dependency warnings not color-only (icon + text)
- Validation severity with shapes (❌ ⚠️ ℹ️)
- High contrast mode support

---

## 10. LOCALIZATION CONSIDERATIONS

### 10.1 Translatable Strings

| Category | Example | Notes |
|----------|---------|-------|
| Block names | "Free Spins" | Must be clear |
| Option labels | "Trigger Type" | Consistent terminology |
| Descriptions | "Scatter lands..." | Can be longer |
| Validation | "Enable Scatter" | Actionable |
| Presets | "Classic 5x3" | May vary by market |

### 10.2 RTL Support

- Panel layout mirrors for RTL
- Checkbox alignment adjusts
- Slide-out from left in RTL

---

## 11. TESTING STRATEGY

### 11.1 Unit Tests (per block)

```dart
group('FreeSpinsBlock', () {
  test('generates correct stages', () {
    final block = FreeSpinsBlock();
    final stages = block.generateStages();
    expect(stages.length, 8);
    expect(stages.map((s) => s.name), contains('FS_TRIGGER'));
  });

  test('validates scatter requirement', () {
    final block = FreeSpinsBlock();
    final result = block.validate({'triggerType': 'scatterCount'}, noScatter);
    expect(result.isError, true);
  });
});
```

### 11.2 Integration Tests

```dart
testWidgets('Apply configuration updates SlotLab', (tester) async {
  await tester.pumpWidget(SlotLabApp());

  // Open Feature Builder
  await tester.tap(find.byIcon(Icons.build));
  await tester.pumpAndSettle();

  // Enable Free Spins
  await tester.tap(find.text('Free Spins'));
  await tester.pumpAndSettle();

  // Apply
  await tester.tap(find.text('Apply Configuration'));
  await tester.pumpAndSettle();

  // Verify stages registered
  final stageService = sl<StageConfigurationService>();
  expect(stageService.hasStage('FS_TRIGGER'), true);
});
```

### 11.3 Rust FFI Tests

```rust
#[test]
fn test_apply_feature_config() {
    let json = r#"{
        "blocks": ["gameCore", "freeSpins"],
        "options": {
            "freeSpins": {"triggerType": "scatterCount", "spinCount": 10}
        }
    }"#;

    let result = apply_feature_config(json);
    assert!(result.is_ok());

    let engine = get_engine();
    assert!(engine.config.features.free_spins);
    assert_eq!(engine.config.features.free_spins_range, (10, 10));
}
```

---

## 12. MIGRATION PATH

### 12.1 Existing Projects

Kada korisnik otvori projekat kreiran pre Feature Builder-a:

1. **Detect legacy** → Proveri da li postoji `featureBuilderConfig` u projektu
2. **Offer migration** → "This project was created before Feature Builder. Would you like to configure features?"
3. **Preserve audio** → Postojeće audio assignments se čuvaju
4. **Infer config** → Pokušaj da detektuješ koje feature-e projekat koristi

### 12.2 Version Compatibility

| Schema Version | Supported | Notes |
|----------------|-----------|-------|
| 1.0.0 | ✅ Current | Initial release |
| 1.1.0 | Future | New blocks |
| 2.0.0 | Future | Breaking changes |

**Migration kod:**
```dart
if (config.schemaVersion == '1.0.0') {
  // Direct load
} else if (config.schemaVersion.startsWith('1.')) {
  // Compatible, may have new fields
  config = migrateFrom1x(config);
} else {
  // Major version change
  throw IncompatibleVersionException(config.schemaVersion);
}
```

---

## 13. FINAL RECOMMENDATION

### Implementirati u V1:

1. ✅ 3 Core blocks (Game Core, Grid, Symbol Set)
2. ✅ 5 Feature blocks (Free Spins, Respin, Hold & Win, Cascades, Collector)
3. ✅ 2 Presentation blocks (Win Presentation, Music States)
4. ➕ **Anticipation block** (kritično za audio)
5. ➕ **Jackpot block** (standalone, ne samo H&W)
6. ➕ **Wild Features block** (previše audio momenata da se ignoriše)

### Odložiti za V1.1:

- Gamble block (market-specific)
- Bonus Game block (kompleksno)
- Multiplier block (može se simulirati kroz Cascades)

### Total za V1:

| Category | Blocks | New vs Original |
|----------|--------|-----------------|
| Core | 3 | Same |
| Feature | 6 | +1 (Anticipation) |
| Presentation | 2 | Same |
| Bonus | 2 | +2 (Jackpot, Wild) |
| **Total** | **13** | **+3 blocks** |

**Estimated additional LOC:** +1,500 (3 new blocks)
**Estimated additional days:** +3 days

**Final estimate: 27 days, ~12,400 LOC**

---

**END OF GAP ANALYSIS**
