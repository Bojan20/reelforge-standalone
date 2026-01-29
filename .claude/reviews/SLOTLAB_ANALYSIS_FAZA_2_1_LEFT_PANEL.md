# SlotLab Analysis — FAZA 2.1: Left Panel (UltimateAudioPanel + SymbolStrip)

**Date:** 2026-01-29
**Status:** ✅ COMPLETE
**LOC:** 2,749 total (UltimateAudioPanel 2,136 + SymbolStrip 613)

---

## 📐 PANEL ARHITEKTURA

### Dva widgeta u jednom panelu

```
┌─────────────────────────────────────┐
│ LEVI PANEL (220px širina)           │
├─────────────────────────────────────┤
│ [SYMBOL STRIP MODE]                 │  ← SymbolStripWidget (613 LOC)
│ ├── SYMBOLS section                 │
│ │   ├── Symbol 1 (win/land/expand)  │
│ │   └── Symbol 2 ...                │
│ ├── MUSIC LAYERS section            │
│ │   ├── Base (L1-L5)                │
│ │   └── FreeSpins (L1-L5) ...       │
│                                      │
│ [ULTIMATE AUDIO PANEL MODE]         │  ← UltimateAudioPanel (2,136 LOC)
│ ├── 1. Base Game Loop [Primary]     │     41 slots
│ ├── 2. Symbols & Lands [Primary]    │     46 slots
│ ├── 3. Win Presentation [Primary]   │     41 slots
│ ├── 4. Cascading Mechanics [2nd]    │     24 slots
│ ├── 5. Multipliers [2nd]            │     18 slots
│ ├── 6. Free Spins [Feature]         │     24 slots
│ ├── 7. Bonus Games [Feature]        │     32 slots
│ ├── 8. Hold & Win [Feature]         │     24 slots
│ ├── 9. Jackpots [Premium 🏆]        │     26 slots
│ ├── 10. Gamble [Optional]           │     16 slots
│ ├── 11. Music & Ambience [Bg]       │     27 slots
│ └── 12. UI & System [Utility]       │     22 slots
│                                      │
│ TOTAL: 341 audio slots              │
└─────────────────────────────────────┘
```

**Switch Mode:** User toggles between Symbol Strip (symbol/music assignments) and Ultimate Audio Panel (stage-based audio).

---

## 🔌 DATA FLOW

### UltimateAudioPanel Flow

```
Audio File (Browser/Dock)
    ↓ (drag)
Audio Slot (one of 341)
    ↓ (drop)
onAudioAssign(stage, audioPath) callback
    ↓
slot_lab_screen.dart:2298-2364
    ↓
projectProvider.setAudioAssignment(stage, audioPath)  ← Persistence
    ↓
AudioEvent creation with stage binding
    ↓
EventRegistry.registerEvent(audioEvent)  ← Playback ready
    ↓
MiddlewareProvider.addCompositeEvent(...)  ← Events panel sync
```

**Key Callbacks (from slot_lab_screen.dart):**

| Callback | Purpose | Destination |
|----------|---------|-------------|
| `onAudioAssign(stage, path)` | Single audio drop | projectProvider + EventRegistry + MiddlewareProvider |
| `onAudioClear(stage)` | Remove audio | projectProvider + EventRegistry |
| `onBatchDistribute(matched, unmatched)` | Folder drop auto-match | Batch import with fuzzy matching |
| `onClearSection(sectionId)` | Reset section | Remove all audio in section |
| `onSectionToggle(sectionId)` | Expand/collapse | projectProvider (persistence) |
| `onGroupToggle(groupId)` | Expand/collapse | projectProvider (persistence) |

### SymbolStripWidget Flow

```
Audio File (Browser/Dock)
    ↓ (drag)
Symbol Context Slot (win/land/expand) OR Music Layer Slot (L1-L5)
    ↓ (drop)
onSymbolAudioDrop(symbolId, context, audioPath) OR onMusicLayerDrop(contextId, layer, audioPath)
    ↓
slot_lab_screen.dart
    ↓
projectProvider.assignSymbolAudio(...) / assignMusicLayer(...)  ← Persistence
    ↓
Auto-sync to EventRegistry (symbol audio)
    ↓
OR ALE Provider (music layers)
```

---

## 🎯 COMPONENT BREAKDOWN

### UltimateAudioPanel Components

**12 Sekcija (341 slots total):**

| Section | Tier | Slots | Grouped | Pooled | Validation |
|---------|------|-------|---------|--------|------------|
| 1. Base Game Loop | Primary | 41 | 5 groups (Idle, Spin Controls, Reel Stops, Animation, Anticipation) | 5 (REEL_STOP_*) | Critical |
| 2. Symbols & Lands | Primary | 46 | 5 groups (Special, High Pay, Medium Pay, Low Pay, Wild Expanded) | 10+ (SYMBOL_LAND_*) | Critical |
| 3. Win Presentation | Primary | 41 | 6 groups (Eval, Lines, Tiers, Rollup, Celebration, Voice) | 3 (ROLLUP_TICK_*) | Critical |
| 4. Cascading Mechanics | Secondary | 24 | 3 groups (Basic, Chain, Cluster) | 2 (CASCADE_STEP) | Optional |
| 5. Multipliers | Secondary | 18 | 3 groups (Win, Progressive, Random) | 0 | Optional |
| 6. Free Spins | Feature | 24 | 3 groups (Trigger, Loop, Summary) | 0 | Feature-specific |
| 7. Bonus Games | Feature | 32 | 4 groups (Pick, Wheel, Trail, Generic) | 2 (WHEEL_TICK) | Feature-specific |
| 8. Hold & Win | Feature | 24 | 3 groups (Trigger, Respins, Summary) | 1 (HOLD_SYMBOL_LOCK) | Feature-specific |
| 9. Jackpots | Premium | 26 | 3 groups (Trigger, Reveal, Tiers) | 0 | **Regulatory** 🏆 |
| 10. Gamble | Optional | 16 | 3 groups (Entry, Flip, Result) | 0 | Optional |
| 11. Music & Ambience | Background | 27 | 6 groups (Base, Attract, Tension, Features, Stingers, Ambient) | 0 | Background |
| 12. UI & System | Utility | 22 | 4 groups (Buttons, Navigation, System, Feedback) | 2 (UI_BUTTON_*) | Low priority |

**Total Groups:** 48
**Total Pooled Events:** ~25 (marked with ⚡ icon)

### SymbolStripWidget Components

**2 Sekcije:**

| Section | Items | Slots per Item | Total Slots |
|---------|-------|----------------|-------------|
| SYMBOLS | 10-20 symbols (dynamic) | 3-5 contexts each (win/land/expand/lock/transform) | ~30-100 |
| MUSIC LAYERS | 5-10 contexts (dynamic) | 5 layers each (L1-L5) | ~25-50 |

**Example:**
```
Symbol: Wild
├── Win context → audio path
├── Land context → audio path
└── Expand context → audio path

Context: Base Game
├── L1 (Calm) → audio path
├── L2 (Rising) → audio path
├── L3 (Tense) → audio path
├── L4 (Exciting) → audio path
└── L5 (Epic) → audio path
```

---

## 📊 FEATURE MATRIX

### UltimateAudioPanel Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| **Drag-drop audio assignment** | ✅ Complete | DragTarget per slot → onAudioAssign callback |
| **Single file drop** | ✅ Complete | Drops on specific stage slot |
| **Folder drop (batch)** | ✅ Complete | Drops on section/group → auto-distribution via StageGroupService |
| **Clear audio** | ✅ Complete | X button per slot → onAudioClear callback |
| **Clear section** | ✅ Complete | Reset button in section header → onClearSection callback |
| **Section expand/collapse** | ✅ Complete | Click header → state persisted via projectProvider |
| **Group expand/collapse** | ✅ Complete | Click group header → state persisted |
| **Audio count badges** | ✅ Complete | Shows assigned count per section/group |
| **Pooled event markers** | ✅ Complete | ⚡ icon for rapid-fire events |
| **Tier color coding** | ✅ Complete | Primary=blue, Secondary=purple, Feature=green, Premium=gold, etc. |
| **Validation badges** | ✅ Complete | 🏆 for jackpots (regulatory) |
| **Filename display** | ✅ Complete | Shows last segment of path on assigned slots |
| **Waveform preview** | ❌ Missing | No waveform display in slot (only in browser) |
| **Audio playback test** | ❌ Missing | No play button per slot |
| **Batch validation** | ⚠️ Partial | onBatchDistribute callback exists, UI feedback missing |
| **Search/filter** | ❌ Missing | No search across 341 slots |
| **Keyboard shortcuts** | ❌ Missing | No keyboard navigation |

### SymbolStripWidget Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| **Symbol audio assignment** | ✅ Complete | 3-5 contexts per symbol (win/land/expand) |
| **Music layer assignment** | ✅ Complete | L1-L5 per context |
| **Add symbol** | ✅ Complete | onAddSymbol callback → GDD import or manual |
| **Add context** | ✅ Complete | onAddContext callback → manual creation |
| **Reset per context** | ✅ Complete | onResetSymbolAudioForContext, onResetMusicLayersForContext |
| **Reset all** | ✅ Complete | onResetAllSymbolAudio, onResetAllMusicLayers |
| **Audio count badges** | ✅ Complete | Shows count per section |
| **Expand/collapse** | ✅ Complete | Per symbol, per context |
| **Drag-drop** | ✅ Complete | DragTarget per slot |
| **Audio preview** | ❌ Missing | No play button |
| **Stage name display** | ⚠️ Hidden | Stage names auto-generated but not visible in UI |
| **ALE sync indicator** | ❌ Missing | No visual feedback that music layers sync to ALE |

---

## 👥 ROLE-BASED ANALYSIS

### 1. Chief Audio Architect (Primary User)

**What they do:**
- Organize 341 audio slots by game flow
- Assign audio files to stages
- Batch import folders with auto-distribution
- Review audio completeness

**What works well:**
- ✅ Game flow organization (matches mental model)
- ✅ Tier system (Primary/Secondary/Feature) helps prioritization
- ✅ Audio count badges show progress
- ✅ Batch distribution saves time

**Pain points:**
- ❌ **No waveform preview in slot** — must remember file by name
- ❌ **No audio playback test** — must trigger full spin to hear sound
- ❌ **No search/filter** — hard to find specific stage in 341 slots
- ⚠️ **Batch distribution feedback unclear** — no visual report of matched/unmatched

**Gaps (prioritized):**
1. **P0:** Audio preview playback button per slot
2. **P1:** Waveform thumbnail in assigned slots
3. **P1:** Search/filter across all sections
4. **P2:** Batch distribution results dialog (matched/unmatched list)

---

### 2. Audio Designer / Composer (Primary User)

**What they do:**
- Drop audio files from browser/dock
- Listen to audio in context
- Adjust assignments based on feedback
- Create variants (different takes)

**What works well:**
- ✅ Drag-drop workflow is intuitive
- ✅ Clear visual feedback (filename display)
- ✅ Easy to replace audio (drop again)
- ✅ Section organization helps find right slot

**Pain points:**
- ❌ **No A/B comparison** — can't compare two audio files for same stage
- ❌ **No variant management** — if they have spin_01.wav, spin_02.wav, spin_03.wav, can only assign one
- ❌ **No audio trimming** — can't adjust start/end offset
- ⚠️ **No visual waveform** — relies on memory

**Gaps (prioritized):**
1. **P1:** Variant slots (multiple audio files per stage with random/sequence selection)
2. **P1:** A/B comparison mode (play current vs new audio)
3. **P2:** Trim/fade controls per slot
4. **P2:** Waveform thumbnail display

---

### 3. Slot Game Designer (Primary User)

**What they do:**
- Map game features to audio stages
- Validate audio completeness (all features have sound)
- Test feature flows (Free Spins, Bonus, Hold & Win)
- Verify regulatory audio (Jackpots)

**What works well:**
- ✅ 12 sections match game flow (natural mapping)
- ✅ Feature sections isolated (FS, Bonus, Hold & Win)
- ✅ Jackpot validation badge 🏆
- ✅ Audio count shows coverage

**Pain points:**
- ❌ **No completeness indicator** — which sections are 100% assigned?
- ❌ **No feature flow preview** — can't play full FS sequence from panel
- ❌ **No missing audio report** — which stages have no audio?
- ⚠️ **Unclear pooled vs non-pooled** — ⚡ marker not explained

**Gaps (prioritized):**
1. **P0:** Section completeness percentage (e.g., "Base Game Loop 85%")
2. **P1:** Missing audio report (list of unassigned stages)
3. **P1:** Feature flow preview button (play FS sequence end-to-end)
4. **P2:** Validation rules per section (e.g., Jackpots require all tiers)

---

### 4. UI/UX Expert (Secondary User)

**What they do:**
- Review panel organization
- Test drag-drop usability
- Validate discoverability
- Suggest UX improvements

**What works well:**
- ✅ Clear visual hierarchy (tiers, colors, icons)
- ✅ Collapsible sections reduce overwhelm
- ✅ Audio count badges provide feedback
- ✅ Game flow order is logical

**Pain points:**
- ❌ **No onboarding** — 341 slots overwhelming for new users
- ❌ **No keyboard shortcuts** — mouse-only workflow
- ⚠️ **Section names technical** — "Cascading Mechanics" unclear to beginners
- ⚠️ **No quick actions** — must scroll to find slot

**Gaps (prioritized):**
1. **P1:** Keyboard shortcuts (Cmd+F search, arrow keys navigate, Space play)
2. **P2:** Onboarding tutorial overlay (highlight key sections)
3. **P2:** Quick jump menu (Cmd+K style palette)
4. **P3:** Rename sections for clarity (e.g., "Cascading Mechanics" → "Cascade Wins")

---

### 5. Producer / Product Owner (Secondary User)

**What they do:**
- Review audio content completeness
- Estimate time to complete audio
- Approve final audio package
- Export for client review

**What works well:**
- ✅ Overall count badge (341 assigned / total)
- ✅ Section badges show progress
- ✅ Clear visual organization

**Pain points:**
- ❌ **No progress dashboard** — which sections are done?
- ❌ **No export preview** — can't review all assigned audio at once
- ❌ **No completion estimate** — how many hours left?
- ⚠️ **No quality metrics** — are files correct format/length/quality?

**Gaps (prioritized):**
1. **P1:** Progress dashboard (donut chart: 85% complete, 52/341 assigned)
2. **P2:** Audio quality report (file format, sample rate, bit depth, duration)
3. **P2:** Export preview (list all assigned files with metadata)
4. **P3:** Time estimate (based on average assignment rate)

---

## 🔍 TECHNICAL ANALYSIS

### State Management

**Persistence Layer:**
```dart
SlotLabProjectProvider
├── audioAssignments: Map<String, String>  ← stage → audioPath
├── symbolAudio: List<SymbolAudioAssignment>
├── musicLayers: List<MusicLayerAssignment>
├── expandedSections: Set<String>
└── expandedGroups: Set<String>
```

**Sync Targets:**
- EventRegistry — For playback (stage → AudioEvent)
- MiddlewareProvider — For Events panel display
- ALE Provider — For music layer adaptive logic (L1-L5)

**Persistence:** ✅ All state saved to SlotLabProjectProvider (survives section switching)

### Audio Assignment Storage

**UltimateAudioPanel:**
- Simple Map<String, String> — one audio per stage
- No variants support
- No metadata (duration, format, quality)

**SymbolStripWidget:**
- SymbolAudioAssignment model — symbolId + context + audioPath + stageName
- MusicLayerAssignment model — contextId + layer + audioPath
- Auto-generates stage names (WIN_SYMBOL_HIGHLIGHT_HP1, SYMBOL_LAND_WILD)

### Batch Distribution (Folder Drop)

**Service:** `StageGroupService.instance.matchFilesToGroup()`

**Algorithm:**
1. User drops folder on section/group
2. StageGroupService scans all files
3. Fuzzy match filename to stage name (keyword matching)
4. Returns: List<StageMatch> (matched) + List<UnmatchedFile>
5. Callback: `onBatchDistribute(matched, unmatched)`
6. **Problem:** No UI for unmatched files — silently ignored

**Coverage:**
- ✅ Works for common naming (reel_stop_1.wav → REEL_STOP_0)
- ✅ Handles both 0-indexed and 1-indexed files
- ⚠️ Unmatched files not reported to user

---

## 🔴 GAPS BY PRIORITY

### P0 — CRITICAL (Blocks Workflow)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| P0.1 | **No audio preview playback** | Audio designers can't audition sounds without full spin | 2 days |
| P0.2 | **No section completeness indicator** | Designers don't know which sections are done | 1 day |
| P0.3 | **Batch distribution no UI feedback** | Unmatched files silently ignored → incomplete audio | 1 day |

### P1 — HIGH (Missing Pro Features)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| P1.1 | **No waveform thumbnail** | Visual identification of audio files | 3 days |
| P1.2 | **No search/filter** | Hard to find specific stage in 341 slots | 2 days |
| P1.3 | **No keyboard shortcuts** | Mouse-only workflow (slow) | 2 days |
| P1.4 | **No variant management** | Can't assign multiple takes per stage | 1 week |
| P1.5 | **No missing audio report** | Don't know which stages need audio | 1 day |
| P1.6 | **No A/B comparison** | Can't compare two audio files | 3 days |

### P2 — MEDIUM (Quality of Life)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| P2.1 | **No trim/fade controls** | Can't adjust audio timing | 1 week |
| P2.2 | **No audio quality report** | Don't know if files are correct format | 2 days |
| P2.3 | **No onboarding tutorial** | New users overwhelmed by 341 slots | 3 days |
| P2.4 | **No quick jump palette** | Must scroll to find section | 2 days |
| P2.5 | **No ALE sync indicator** | Music layers don't show ALE connection | 1 day |

### P3 — LOW (Nice to Have)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| P3.1 | **No export preview** | Can't review all assigned audio at once | 2 days |
| P3.2 | **No progress dashboard** | No visual summary of completion | 3 days |
| P3.3 | **No file metadata display** | No duration, format, sample rate shown | 1 day |

---

## 🎯 ACTIONABLE ITEMS (For MASTER_TODO.md)

### P0.1: Add Audio Preview Playback

**Problem:** Audio designers can't audition sounds without triggering full slot spin
**Impact:** Slows down workflow, requires full simulation to hear audio
**Effort:** 2 days
**Assigned To:** Audio Designer, Tooling Developer

**Files to Modify:**
- `ultimate_audio_panel.dart:300-400` — Add play button per slot

**Implementation:**
```dart
// In _buildAudioSlot():
Row(
  children: [
    // Existing: filename display
    Expanded(child: Text(filename)),

    // NEW: Play button
    IconButton(
      icon: Icon(_playingStage == stage ? Icons.stop : Icons.play_arrow, size: 14),
      onPressed: () => _togglePreview(stage, audioPath),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: 20, height: 20),
    ),

    // Existing: Clear button
    IconButton(icon: Icon(Icons.close), onPressed: onClear),
  ],
)

// NEW: State tracking
String? _playingStage;

void _togglePreview(String stage, String audioPath) {
  if (_playingStage == stage) {
    AudioPlaybackService.instance.stopAll();
    setState(() => _playingStage = null);
  } else {
    AudioPlaybackService.instance.previewFile(
      audioPath,
      source: PlaybackSource.browser,
    );
    setState(() => _playingStage = stage);
  }
}
```

**Definition of Done:**
- [ ] Play button appears on assigned slots
- [ ] Click plays audio via AudioPlaybackService
- [ ] Icon toggles play/stop
- [ ] Stops previous audio when clicking another slot
- [ ] Uses isolated Browser engine (doesn't interfere with SlotLab playback)

---

### P0.2: Add Section Completeness Indicator

**Problem:** Designers don't know which sections are 100% assigned
**Impact:** Can't track progress, might miss required stages
**Effort:** 1 day
**Assigned To:** Slot Game Designer, UI/UX Expert

**Files to Modify:**
- `ultimate_audio_panel.dart:235-300` — Enhance section header

**Implementation:**
```dart
Widget _buildSection(_SectionConfig config) {
  final totalSlots = config.groups.fold<int>(
    0, (sum, g) => sum + g.slots.length,
  );
  final assignedCount = _countAssignedInSection(config);
  final percentage = (assignedCount / totalSlots * 100).toInt();
  final isComplete = percentage == 100;

  return Column(
    children: [
      // Section header with percentage
      Container(
        child: Row(
          children: [
            // Existing: icon, title, count badge
            Icon(...),
            Text(config.title),
            Spacer(),

            // NEW: Percentage badge
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getPercentageColor(percentage).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Text('$percentage%', style: ...),
                  if (isComplete) Icon(Icons.check_circle, size: 12),
                ],
              ),
            ),
          ],
        ),
      ),
      // NEW: Optional progress bar
      if (isExpanded && percentage < 100)
        LinearProgressIndicator(
          value: percentage / 100,
          backgroundColor: Colors.white10,
          color: config.color,
          minHeight: 2,
        ),
    ],
  );
}

Color _getPercentageColor(int percentage) {
  if (percentage == 100) return Colors.green;
  if (percentage >= 75) return Colors.blue;
  if (percentage >= 50) return Colors.orange;
  return Colors.red;
}
```

**Definition of Done:**
- [ ] Percentage badge shows completion (0-100%)
- [ ] Color-coded: red<50%, orange 50-75%, blue 75-99%, green 100%
- [ ] Check icon appears at 100%
- [ ] Optional progress bar below section header
- [ ] Updates in real-time as audio assigned

---

### P0.3: Add Batch Distribution Results Dialog

**Problem:** Unmatched files silently ignored, user doesn't know which files failed
**Impact:** Incomplete audio packages, missing sounds
**Effort:** 1 day
**Assigned To:** Tooling Developer, UX Expert

**Files to Create:**
- `flutter_ui/lib/widgets/slot_lab/batch_distribution_dialog.dart` (~300 LOC)

**Files to Modify:**
- `slot_lab_screen.dart:2382-2384` — Show dialog instead of debugPrint

**Implementation:**
```dart
// NEW: batch_distribution_dialog.dart
class BatchDistributionDialog extends StatelessWidget {
  final List<StageMatch> matched;
  final List<UnmatchedFile> unmatched;

  static Future<void> show(BuildContext context, {
    required List<StageMatch> matched,
    required List<UnmatchedFile> unmatched,
  }) {
    return showDialog(
      context: context,
      builder: (_) => BatchDistributionDialog(matched, unmatched),
    );
  }

  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.folder_open, color: Colors.blue),
          SizedBox(width: 8),
          Text('Batch Import Results'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            // Summary
            _buildSummary(),
            SizedBox(height: 16),
            // Tabs: Matched | Unmatched
            DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(tabs: [
                    Tab(text: 'Matched (${matched.length})'),
                    Tab(text: 'Unmatched (${unmatched.length})'),
                  ]),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildMatchedList(),
                        _buildUnmatchedList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (unmatched.isNotEmpty)
          TextButton(
            child: Text('Manual Assign Unmatched'),
            onPressed: () => _showManualAssignment(context),
          ),
        TextButton(
          child: Text('Close'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final total = matched.length + unmatched.length;
    final successRate = (matched.length / total * 100).toInt();

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('Total Files', total.toString(), Colors.white),
          _buildStat('Matched', matched.length.toString(), Colors.green),
          _buildStat('Unmatched', unmatched.length.toString(), Colors.orange),
          _buildStat('Success Rate', '$successRate%',
            successRate == 100 ? Colors.green : Colors.orange),
        ],
      ),
    );
  }
}

// In slot_lab_screen.dart, replace debugPrint:
onBatchDistribute: (matched, unmatched) async {
  await BatchDistributionDialog.show(
    context,
    matched: matched,
    unmatched: unmatched,
  );
},
```

**Definition of Done:**
- [ ] Dialog shows after folder drop
- [ ] Summary: Total, Matched, Unmatched, Success Rate
- [ ] Matched tab: file → stage list with green checkmarks
- [ ] Unmatched tab: file list with reasons (no keywords matched)
- [ ] Manual assign button for unmatched files
- [ ] Close button

---

## 📊 SUMMARY

### Strengths
- ✅ **341 audio slots** — comprehensive coverage
- ✅ **12 sections** — logical game flow organization
- ✅ **Tier system** — helps prioritization
- ✅ **Batch distribution** — saves time with folder drop
- ✅ **Persistence** — all state saved to projectProvider
- ✅ **Callbacks** — clean separation of concerns

### Critical Weaknesses
- ❌ **No audio preview** — can't test sounds in panel
- ❌ **No completeness tracking** — no progress visibility
- ❌ **No batch feedback** — unmatched files hidden

### Missing Features (Top 10)
1. Audio preview playback button (P0)
2. Section completeness percentage (P0)
3. Batch distribution results dialog (P0)
4. Waveform thumbnail display (P1)
5. Search/filter functionality (P1)
6. Keyboard shortcuts (P1)
7. Variant management (P1)
8. Missing audio report (P1)
9. A/B comparison mode (P1)
10. Audio quality report (P2)

### Provider Connections

| Provider | Connection | Purpose |
|----------|------------|---------|
| SlotLabProjectProvider | ✅ Full | Persistence (audioAssignments, symbolAudio, musicLayers, expand state) |
| EventRegistry | ✅ Via callback | Audio playback (stage → AudioEvent) |
| MiddlewareProvider | ✅ Via callback | Events panel sync (composite events) |
| ALE Provider | ✅ Via callback | Music layer adaptive logic |
| AudioAssetManager | ⚠️ Indirect | Via browser (no direct panel integration) |
| StageConfigurationService | ✅ Full | Stage definitions, pooled detection, priority, bus routing |

---

## ✅ FAZA 2.1 COMPLETE

**Next Step:** Await approval, then proceed to FAZA 2.2 (Desni Panel)

**Deliverables Created:**
- Panel architecture diagram
- Component breakdown (12 sections, 341 slots)
- Data flow documentation
- Role-based gap analysis (5 roles × gaps)
- 13 actionable items for MASTER_TODO (3 P0, 6 P1, 3 P2, 1 P3)

---

**Created:** 2026-01-29
**Version:** 1.0
**LOC Analyzed:** 2,749
