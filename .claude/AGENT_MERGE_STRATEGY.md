# Agent Merge Strategy — 2026-01-30

**Situation:** 4 agents implementing overlapping P1 tasks
**Challenge:** Merge results without conflicts
**Approach:** Systematic conflict resolution

---

## Agent Coverage Map

| Task | a412900 | ad3ea72 | a97bcb5 | a564b14 | Conflict? |
|------|---------|---------|---------|---------|-----------|
| P1-01 Audio Variants | ✓ | ✓ | — | — | ⚠️ YES |
| P1-02 LUFS Preview | ✓ | ✓ | — | — | ⚠️ YES |
| P1-03 Waveform Zoom | ✓ | ✓ | — | — | ⚠️ YES |
| P1-04 Undo History | ✓ | — | — | ✓ | ⚠️ YES |
| P1-05 Container Smoothing | ✅ DONE | — | — | — | ✅ NO |
| P1-06 Dependency Graph | ✓ | — | — | ✓ | ⚠️ YES |
| P1-07 Container Metering | ✓ | — | — | — | ✅ NO |
| P1-08 E2E Latency | ✓ | — | ✓ | — | ⚠️ YES |
| P1-09 Voice Steal | ✓ | — | ✓ | — | ⚠️ YES |
| P1-10 Stage Trace | ✓ | — | ✓ | — | ⚠️ YES |
| P1-11 DSP Attribution | ✓ | — | ✓ | — | ⚠️ YES |
| P1-12 Feature Templates | ✓ | — | — | — | ✅ NO |
| P1-13 Volatility Calc | ✓ | — | — | — | ✅ NO |
| P1-14 Scripting API | ✓ | — | — | — | ✅ NO |
| P1-15 Hook System | ✓ | — | — | — | ✅ NO |
| P1-16 Test Combinator | ✓ | — | — | — | ✅ NO |
| P1-17 Timing Validation | ✓ | — | — | — | ✅ NO |
| P1-18 Freq Response | ✓ | — | — | — | ✅ NO |
| P1-19 Timeline Persist | ✓ | — | — | ✓ | ⚠️ YES |
| P1-20 Container Logging | ✓ | — | — | ✓ | ⚠️ YES |
| P1-21 Plugin PDC | ✓ | — | — | — | ✅ NO |
| P1-22 Cross-Section Val | ✓ | — | — | — | ✅ NO |
| P1-23 FFI Audit | ✓ | — | — | — | ✅ NO |
| UX-01 Onboarding | ✓ | — | — | — | ✅ NO |
| UX-02 One-Step | ✅ DONE | — | — | — | ✅ NO |
| UX-03 Readable Names | ✅ DONE | — | — | — | ✅ NO |
| UX-04 Smart Tabs | ✓ | — | — | ✓ | ⚠️ YES |
| UX-05 Drag Feedback | ✓ | — | — | ✓ | ⚠️ YES |
| UX-06 Shortcuts | ✅ DONE | — | — | — | ✅ NO |

**Conflicts:** 14 taskova sa overlap
**No Conflict:** 15 taskova (samo a412900)

---

## Merge Priority Rules

### Rule 1: Specific Agent Wins Over Generic
If specialized agent (ad3ea72, a97bcb5, a564b14) AND generic (a412900) both implemented:
- **Use specialized version** (more domain expertise)
- Example: Audio Designer agent's variant UI > generic implementation

### Rule 2: Better Architecture Wins
Compare both implementations:
- Which follows Flutter best practices?
- Which has better error handling?
- Which is more maintainable?

### Rule 3: Most Complete Wins
If one has more features:
- Choose more complete implementation
- Cherry-pick missing features from other

---

## Step-by-Step Merge Process

### Step 1: Extract All Agent Outputs
```bash
# Copy outputs to workspace
cp /private/tmp/.../a412900.output /tmp/agent1.txt
cp /private/tmp/.../ad3ea72.output /tmp/agent2.txt
cp /private/tmp/.../a97bcb5.output /tmp/agent3.txt
cp /private/tmp/.../a564b14.output /tmp/agent4.txt
```

### Step 2: Identify Conflicts
For each conflict task, compare implementations:
```bash
# Example: P1-01 Audio Variants
# Agent a412900 created: audio_variant_group.dart
# Agent ad3ea72 created: audio_variant_group.dart

diff flutter_ui/lib/models/audio_variant_group.dart \
     [agent_output_path]/audio_variant_group.dart
```

### Step 3: Resolution Strategy

**For each conflict:**
1. Read both implementations
2. Score on:
   - Completeness (1-10)
   - Code quality (1-10)
   - Documentation (1-10)
3. Choose higher score
4. Document decision in AGENT_MERGE_REPORT

### Step 4: Apply Winning Implementation
```bash
# If ad3ea72 wins for audio_variant_group.dart:
cp [ad3ea72_output]/audio_variant_group.dart \
   flutter_ui/lib/models/

# Log decision
echo "P1-01: Used ad3ea72 (Audio Designer specialist)" >> merge.log
```

### Step 5: Verify No Duplicates
```bash
# Check for duplicate imports, classes, functions
flutter analyze
# Must show 0 errors
```

### Step 6: Final Integration Test
- Import both specialized and generic implementations
- Test overlapping features
- Ensure no runtime conflicts

---

## Expected File Conflicts

**High Probability (implement twice):**
- `undo_history_panel.dart` (a412900 vs a564b14)
- `event_dependency_analyzer.dart` (a412900 vs a564b14)
- `audio_variant_service.dart` (a412900 vs ad3ea72)
- `latency_profiler.dart` (a412900 vs a97bcb5)

**Medium Probability:**
- Panel widgets for profiling tools
- DAW timeline modifications

**Low Probability:**
- Model files (should be identical or very similar)

---

## Fallback: If Merge Too Complex

**Plan B:**
1. Accept ONLY a412900 output (discard others)
2. Verify it covers all 25 tasks
3. If gaps exist, manually implement from specialized agents
4. **Time Saved:** No merge conflicts

**Plan C:**
1. Cherry-pick only NON-conflicting implementations
2. For conflicts, choose one agent arbitrarily
3. Test, fix errors as they appear

---

## Timeline Estimate

| Step | Time |
|------|------|
| Extract outputs | 5 min |
| Identify conflicts | 10 min |
| Resolve 14 conflicts | 30-60 min |
| Verify + test | 20 min |
| Commit | 10 min |
| **TOTAL** | **1-2 hours** |

---

**Status:** ⏳ **Ready to Merge When Agents Complete**

**Next:** Wait for all 4 agents → Execute merge strategy

---

*Created: 2026-01-30*
*Purpose: Systematic conflict resolution*
