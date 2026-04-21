# Agent 0: Orchestrator — Memory

## Accumulated Knowledge
- Total codebase: 500+ source files, 34 Rust crates, 57 widget directories
- 84/84 QA bugs tracked and fixed (as of 2026-04-21)
- Build: NEVER flutter run — only xcodebuild + open .app
- ExFAT external disk causes codesign failures — DerivedData must be on HOME

## Cross-Domain Dependencies
- Mixer inserts depend on both MixerArchitect(2) and PluginArchitect(17)
- Clip operations span TimelineEngine(12) and MediaTimeline(19)
- SlotLab audio pipeline: Events(4) → Audio(5) → SlotIntelligence(18, Rust)
- Plugin MIDI: PluginArchitect(17) + AudioEngine(1) for process() routing

## Decisions
- GetIt DI for all providers (70+ registered, no circular deps)
- Rust for all audio-critical code, Flutter for UI only
- Lock-free audio thread design (rtrb::RingBuffer)
- Casino-grade determinism: FNV-1a + SHA-256
