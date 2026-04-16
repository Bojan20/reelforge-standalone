# HELIX Screen — Master QA TODO
> Generated: 2026-04-16 | Branch: feature/slotlab-ultimate-mockup

## ✅ COMPLETED — QA Pass

### Bug Fixes
| # | Issue | Fix | Status |
|---|-------|-----|--------|
| 1 | FocusNode created inline in build() — memory leak | Moved to `_focusNode` in `initState()` + `dispose()` | ✅ |
| 2 | Double underscore `__` in 6 Consumer builders — analyzer warnings | Replaced with `child` parameter name | ✅ |
| 3 | Container used instead of SizedBox for resize handle (deprecated child usage) | Changed to SizedBox wrapper | ✅ |
| 4 | Unused import `helix_screen.dart` in engine_connected_layout.dart | Removed | ✅ |
| 5 | Project name hardcoded "Untitled Project" in Omnibar | Wired to `SlotLabProjectProvider.projectName` | ✅ |
| 6 | RTP info chip hardcoded "96.2%" | Wired to `SlotLabProjectProvider.sessionStats.rtp` | ✅ |

### Panel Wiring — Dock Tabs (ZERO hardcoded data)
| Tab | Before | After | Source |
|-----|--------|-------|--------|
| FLOW | ✅ Already wired to GameFlowProvider | No change needed | GameFlowProvider |
| AUDIO – Master meters | Hardcoded L:0.72 R:0.68 -4.2dBFS | Real arousal/engagement from NeuroAudio + VOL/CMP indicators | NeuroAudioProvider |
| AUDIO – Channels | Hardcoded 5 fake channel strips | Real composite events with real colors, names, masterVolume | MiddlewareProvider |
| MATH – RTP | Already wired | No change | SlotLabProjectProvider |
| MATH – Volatility | Hardcoded "HIGH" 7.4/10 | Real from NeuroAudio riskTolerance × 10 | NeuroAudioProvider |
| MATH – Hit Freq | Hardcoded "1:4.2" 24% | Real from recentWins.length / totalSpins | SlotLabProjectProvider |
| MATH – Max Win | Hardcoded "5000×" | Real from max(recentWins.amount) / avgBet | SlotLabProjectProvider |
| MATH – Bonus Freq | Hardcoded "1:82" | Real from bonus/free wins count / totalSpins | SlotLabProjectProvider |
| TIMELINE | 5 hardcoded static tracks | Real tracks from compositeEvents grouped by trackIndex | MiddlewareProvider |
| INTEL – CoPilot | Hardcoded "High-intensity base loop" text | Real from RGAI remediations + NeuroAudio state | RgaiProvider + NeuroAudioProvider |
| INTEL – RGAI compliance | Partially wired (Session pacing was hardcoded) | Risk level from real NeuroAudio + near-miss from real RGAI | RgaiProvider + NeuroAudioProvider |
| INTEL – Engagement | Valence-based score | Engagement-based score (×10, 0–10 scale) | NeuroAudioProvider |
| INTEL – Mini metrics | Hardcoded 94% retention, 7.2s dwell, 1.8× bet, 0.12 fatigue | Real: retention from churnPrediction, session duration, loss streak, fatigue | NeuroAudioProvider |
| EXPORT | ✅ Already wired to SlotExportProvider | No change needed | SlotExportProvider |

### Spine Overlay Panels (were ALL empty placeholders)
| Panel | Before | After | Source |
|-------|--------|-------|--------|
| AUDIO ASSIGN | "Content coming soon" | Real composite events list with colors, layer counts | MiddlewareProvider |
| GAME CONFIG | "Content coming soon" | Real game state, session stats, recent wins | GameFlowProvider + SlotLabProjectProvider |
| AI / INTEL | "Content coming soon" | Full 8D emotional state vector bars + risk level | NeuroAudioProvider |
| SETTINGS | "Content coming soon" | Real engine transport (tempo, time sig, position, loop) + neuro params | EngineProvider + NeuroAudioProvider |
| ANALYTICS | "Content coming soon" | Real session analytics + audio system metrics (RTPC, switch, action counts) | SlotLabProjectProvider + NeuroAudioProvider + MiddlewareProvider |

### Canvas Improvements
| Item | Before | After |
|------|--------|-------|
| PremiumSlotPreview | No params (default 3×3, not fullscreen) | 5 reels × 3 rows, isFullscreen=true, projectProvider wired |

## QA Results
- `flutter analyze`: **0 errors, 0 warnings**, 192 info (all in generated code)
- `cargo test --workspace`: **ALL passed, 0 failed**
- Zero hardcoded values in any dock panel
- All 5 spine overlay panels have real content
- All 6 dock tabs wired to real providers

## Provider Dependency Map (helix_screen.dart)
```
EngineProvider ─────── Omnibar transport, BPM, Settings spine
GameFlowProvider ───── Canvas glow, Stage strip, FLOW tab, Game Config spine
MiddlewareProvider ─── AUDIO tab channels, TIMELINE tab tracks, Audio Assign spine, Analytics spine
SlotLabProjectProvider─ Omnibar project name, RTP chip, MATH tab, Game Config spine, Analytics spine
NeuroAudioProvider ─── AUDIO tab meters, MATH volatility, INTEL tab (copilot + metrics), AI/Intel spine, Settings spine
RgaiProvider ───────── INTEL tab compliance, INTEL copilot suggestions
SlotExportProvider ─── EXPORT tab
```

## Remaining Items (NOT bugs — feature enhancements)
| Priority | Item | Notes |
|----------|------|-------|
| LOW | GRID info chip hardcoded "5×3" | Need reel/row config from project provider (currently 5×3 default) |
| LOW | Timeline maxMs heuristic | Assumes ~1s per event for visual width — works fine for now |
| LOW | Export tab could show progress/results | Currently fires-and-forgets via SlotExportProvider |
| NONE | 192 analyzer info items | All in generated code (native_ffi.dart, bridge_generated.dart) — not actionable |
