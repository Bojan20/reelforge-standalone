# RF-Bridge Upgrade — Type-Safe Codegen (BACKLOG)

Trenutni Flutter ↔ Rust bridge radi, ali koristi ručni JSON/CString FFI. Upgrade plan:

- [ ] **Type-safe codegen** — flutter_rust_bridge v2 codegen umesto ručnih CString/JSON konverzija
- [ ] **Streaming API** — Server-sent events pattern za metering/status umesto polling
- [ ] **Error propagation** — Strukturirane greške (FFIError) kroz bridge umesto string poruka
- [ ] **Zero-copy metering** — Shared memory ring buffer za peak/RMS podatke
- [ ] **Batch commands** — Grupišu se DSP komande u jedan FFI poziv umesto pojedinačnih
- [ ] **Bridge health monitoring** — Latency tracking, dropped message detection

**Fajlovi:** `crates/rf-bridge/src/api*.rs`, `crates/rf-bridge/src/stage_ffi.rs`
**Prioritet:** Posle Flux nadogradnje — staviti u plan kad se stabilizuje GPT bridge
