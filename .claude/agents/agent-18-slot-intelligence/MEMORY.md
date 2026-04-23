# Agent 18: SlotIntelligence — Memory

## Accumulated Knowledge
- AUREXIS: deterministic audio intelligence, parameter mapping, safety envelopes
- ALE: dynamic music layer transitions, signal-driven adaptation
- FluxMacro: casino-grade automation, QA simulation, manifest building
- rf-stage: universal slot phases (IDLE, SPINNING, ANTICIPATION, REVEAL)
- rf-ingest: adapters for any external slot engine
- Synthetic engine: complete slot simulation without hardware

## Patterns
- Determinism: FNV-1a seed → SHA-256 verification
- FP normalization: (sub_seed >> 1) as f64 / ((1u64 << 63) as f64)
- ALE transitions: guaranteed "default" profile in registry

## Gotchas
- ALE transitions.rs:551 had nested unwrap on empty registry
- AUREXIS hash normalization had FP bias with u64::MAX
- Ingest SystemTime can fail behind UNIX_EPOCH — unwrap_or_default()
- FluxMacro only checked cancellation at loop start — now per-step
