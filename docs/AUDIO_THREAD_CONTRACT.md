# Audio Thread Contract

This document defines hard real-time guarantees.

## Entry Point
fn process(&mut self, buffer: &mut AudioBuffer)

## Forbidden Operations
- Vec::push
- Vec::resize
- HashMap::get / insert
- String allocation
- format!
- Arc::clone
- Mutex::lock
- RwLock::read/write
- Blocking IPC
- Heap allocation of any kind

## Allowed Operations
- Index-based array access
- Pre-allocated buffers
- Atomic loads
- SIMD math
- Linear loops
- Block-level automation interpolation

## Determinism
process() must:
- Have bounded execution time
- Avoid recursion
- Avoid dynamic dispatch in hot path
- Avoid unbounded loops

## Metering
- Block peak detection
- EMA smoothing
- Atomic write to UI
- No buffer duplication
