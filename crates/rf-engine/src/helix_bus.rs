// ═══════════════════════════════════════════════════════════════════════════════
// HELIX BUS — Unified Lock-Free Reactive Message Bus
// ═══════════════════════════════════════════════════════════════════════════════
#![allow(clippy::field_reassign_with_default)]
//
// The nervous system of SlotLab. Every subsystem (AUREXIS, ALE, RTPC, Stage,
// Compliance, NeuroAudio, Spatial, FluxMacro) publishes and subscribes through
// this single bus. No more manual wiring between 15 Flutter providers.
//
// DESIGN PRINCIPLES:
//   1. Zero allocations on audio thread (pre-allocated message pool)
//   2. Lock-free publish from ANY thread (UI, audio, worker)
//   3. Sample-accurate timestamps on every message
//   4. Channel-based routing with wildcard subscriptions
//   5. Deterministic replay — messages are ordered and reproducible
//   6. Bounded buffer — never blocks, oldest messages evicted on overflow
//   7. Thread-safe fan-out to multiple subscribers
//
// ARCHITECTURE:
//   Publisher (any thread) → HxBus → Subscribers (audio thread reads per-block)
//
//   The bus uses a fixed-size ring buffer per subscriber. Publishers write to a
//   shared staging area (lock-free MPSC). The bus router drains staging into
//   per-subscriber ring buffers at the start of each audio block (single drain
//   point = deterministic ordering).
//
// CHANNEL TAXONOMY:
//   stage.*        — Game stage events (40+ types from rf-stage)
//   math.*         — RTP, volatility, win ratio, bet level, hit frequency
//   emotion.*      — Arousal, valence, fatigue, engagement, session age
//   voice.*        — Voice lifecycle (spawn, kill, duck, priority change)
//   audio.*        — Playback commands (play, stop, fade, seek)
//   compliance.*   — RGAI flags, LDW warnings, jurisdiction checks
//   neuro.*        — Player behavior signals (click velocity, pause patterns)
//   spatial.*      — 3D position updates, HRTF changes, room config
//   macro.*        — FluxMacro pipeline events, QA results
//   transport.*    — Play/stop/seek/loop, BPM changes
//   system.*       — Bus lifecycle, error reports, diagnostics
//
// ═══════════════════════════════════════════════════════════════════════════════

use std::cell::UnsafeCell;
use std::sync::atomic::{AtomicU64, AtomicU32, AtomicBool, Ordering};
use std::sync::Arc;

// ─────────────────────────────────────────────────────────────────────────────
// Sprint 15 Faza 4.F.2 — Lock-Free Slot Store (centralized unsafe surface)
// ─────────────────────────────────────────────────────────────────────────────
//
// Both `HxRingBuffer` (SPSC) and `HxStagingArea` (MPSC) need a slab of
// pre-allocated message slots that are mutably shared across threads.  The
// pre-refactor design slapped `unsafe impl Sync for HxRingBuffer {}` and
// `unsafe impl Sync for HxStagingArea {}` directly on the host structs and
// scattered raw `Box<[UnsafeCell<HxMessage>]>` access throughout `push()`,
// `pop()`, `publish()`, `drain_into()`.  Auditing was painful — `unsafe`
// surface area equaled the union of every method touching the buffer.
//
// This newtype consolidates the unsafe contract into ONE place.  The host
// structs no longer need their own `unsafe impl Sync` — they compose
// `LockFreeSlotStore<HxMessage>`, which is the only type in this module
// that carries the unsafe Sync claim.
//
// Reviewing thread-safety now means reviewing exactly two methods:
// `write_at` and `read_at`.  The host's atomic write/read positions enforce
// the SPSC/MPSC discipline that makes the unsafe `Sync` claim sound; the
// newtype encodes the invariant in the type system as "you must only call
// write_at/read_at from inside a sync protocol you have already proved
// correct".

/// Fixed-capacity slab of `UnsafeCell<T>` slots, shared across threads via
/// `Arc`/`&` for use as the backing storage of lock-free SPSC or MPSC
/// queues.
///
/// # Safety contract
///
/// `LockFreeSlotStore<T>` implements `Sync` unconditionally (when
/// `T: Send`).  The implementation is sound ONLY because every public
/// mutation API is marked `unsafe` and documented to require the caller
/// to enforce mutual exclusion at the slot level through some external
/// synchronization primitive (atomic write/read cursors in this module).
///
/// In practice the bus owns two host types that wrap a `LockFreeSlotStore`:
///
/// * `HxRingBuffer` (SPSC) — single producer claims slot via `write_pos`
///   atomic, single consumer claims slot via `read_pos` atomic.
/// * `HxStagingArea` (MPSC) — multi-producer claim slot via CAS on
///   `write_cursor`, single consumer drains via `read_fence`.
///
/// Both protocols guarantee that at any moment, each slot index has at
/// most one thread writing AND no thread reading, OR at most one thread
/// reading AND no thread writing.  Under that discipline the unsafe
/// `write_at`/`read_at` calls are race-free.
#[repr(transparent)]
pub(crate) struct LockFreeSlotStore<T> {
    slots: Box<[UnsafeCell<T>]>,
}

impl<T> LockFreeSlotStore<T> {
    /// Construct a slot store of exactly `capacity` slots, each initialized
    /// by invoking `init()` once.  Allocation happens here at construction
    /// time only — the audio thread NEVER allocates through this type.
    pub fn new_with<F: FnMut() -> T>(capacity: usize, mut init: F) -> Self {
        let slots = (0..capacity)
            .map(|_| UnsafeCell::new(init()))
            .collect::<Vec<_>>()
            .into_boxed_slice();
        Self { slots }
    }

    /// Number of slots in the store (fixed at construction).
    #[inline]
    #[allow(dead_code)] // public-API future-proofing; host structs track their own capacity
    pub fn capacity(&self) -> usize {
        self.slots.len()
    }

    /// Write `value` into the slot at `idx`, overwriting any previous
    /// contents without dropping them (matches `std::ptr::write` semantics).
    ///
    /// # Safety
    ///
    /// Caller MUST guarantee:
    /// 1. `idx < self.capacity()`.
    /// 2. No other thread is concurrently reading from slot `idx`.
    /// 3. No other thread is concurrently writing to slot `idx`.
    ///
    /// The host queue is responsible for upholding all three via its
    /// atomic position cursors and protocol.  Violating any of them is
    /// undefined behavior.
    #[inline(always)]
    pub unsafe fn write_at(&self, idx: usize, value: T) {
        // Rust 2024 `unsafe_op_in_unsafe_fn` lint requires an explicit
        // `unsafe { }` block even inside an `unsafe fn`.  The outer fn's
        // `unsafe` keyword documents what the caller must guarantee;
        // this inner block scopes the actual UB-capable operation.
        unsafe { std::ptr::write(self.slots[idx].get(), value); }
    }

    /// Read (move out) the value at slot `idx` via bitwise copy.  Matches
    /// `std::ptr::read` semantics — the slot's previous contents are
    /// logically "moved out" without running `Drop`.
    ///
    /// # Safety
    ///
    /// Caller MUST guarantee:
    /// 1. `idx < self.capacity()`.
    /// 2. Slot `idx` has been previously written by `write_at`.
    /// 3. No other thread is concurrently reading from or writing to
    ///    slot `idx`.
    /// 4. The caller will not call `read_at(idx)` again until the slot
    ///    has been re-written (otherwise you'd be reading a logically
    ///    moved-out value, which is UB for non-`Copy` types).
    ///
    /// For `T: Copy` (like `HxMessage`) condition (4) is trivially
    /// satisfied — `read_at` is effectively `Clone` for those types.
    #[inline(always)]
    pub unsafe fn read_at(&self, idx: usize) -> T {
        // See `write_at` for why the inner `unsafe { }` is needed.
        unsafe { std::ptr::read(self.slots[idx].get()) }
    }
}

// Safety: see the `LockFreeSlotStore` type-level docs.  This is the ONLY
// place in `helix_bus.rs` that carries an `unsafe impl Sync` — both
// `HxRingBuffer` and `HxStagingArea` derive Sync compositionally because
// every one of their fields (atomics + this newtype) is itself Sync.
//
// `T: Send` is required because moving a value across thread boundaries
// (which is what SPSC/MPSC effectively does) requires `Send`.  We do NOT
// require `T: Sync` — slots are accessed mutably only by one thread at a
// time under the host's synchronization protocol.
unsafe impl<T: Send> Sync for LockFreeSlotStore<T> {}

// ─────────────────────────────────────────────────────────────────────────────
// Channel System
// ─────────────────────────────────────────────────────────────────────────────

/// Top-level channel domains. Each domain can have sub-channels via the
/// `sub_channel` field in `HxMessage`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum HxChannel {
    /// Game stage events: spin press, reel stop, win present, feature enter, etc.
    Stage       = 0,
    /// Math model data: RTP, volatility, win ratio, bet level, hit frequency
    Math        = 1,
    /// Emotional state: arousal, valence, fatigue, engagement, session duration
    Emotion     = 2,
    /// Voice lifecycle: spawn, kill, duck, priority change, collision
    Voice       = 3,
    /// Playback commands: play, stop, fade, seek, loop control
    Audio       = 4,
    /// Regulatory compliance: LDW flag, near-miss guard, jurisdiction check
    Compliance  = 5,
    /// Player behavior signals: click velocity, pause duration, bet changes
    Neuro       = 6,
    /// 3D spatial: position update, HRTF change, room config, listener move
    Spatial     = 7,
    /// FluxMacro pipeline: step complete, QA result, build progress
    Macro       = 8,
    /// Transport: play, stop, seek, loop, BPM change, time signature
    Transport   = 9,
    /// System: bus lifecycle, errors, diagnostics, heartbeat
    System      = 10,
}

impl HxChannel {
    pub const COUNT: usize = 11;

    /// Convert from raw u8 (for FFI/serialization)
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Stage),
            1 => Some(Self::Math),
            2 => Some(Self::Emotion),
            3 => Some(Self::Voice),
            4 => Some(Self::Audio),
            5 => Some(Self::Compliance),
            6 => Some(Self::Neuro),
            7 => Some(Self::Spatial),
            8 => Some(Self::Macro),
            9 => Some(Self::Transport),
            10 => Some(Self::System),
            _ => None,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message Payload — Typed union covering every scenario
// ─────────────────────────────────────────────────────────────────────────────

/// Sub-channel identifiers for Stage domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum StageSubChannel {
    SpinPress       = 0,
    ReelSpinStart   = 1,
    ReelSpinning    = 2,
    ReelStop        = 3,
    EvaluateWins    = 4,
    WinPresent      = 5,
    WinLineShow     = 6,
    RollupStart     = 7,
    RollupTick      = 8,
    RollupEnd       = 9,
    BigWinTier      = 10,
    FeatureEnter    = 11,
    FeatureStep     = 12,
    FeatureRetrigger = 13,
    FeatureExit     = 14,
    CascadeStart    = 15,
    CascadeStep     = 16,
    CascadeEnd      = 17,
    JackpotTrigger  = 18,
    JackpotPresent  = 19,
    GambleStart     = 20,
    GambleResult    = 21,
    AnticipationOn  = 22,
    AnticipationOff = 23,
    IdleStart       = 24,
    IdleTick        = 25,
    SpinEnd         = 26,
    Custom          = 255,
}

/// Sub-channel identifiers for Math domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum MathSubChannel {
    RtpUpdate          = 0,
    VolatilityChange   = 1,
    WinRatio           = 2,
    BetLevel           = 3,
    HitFrequency       = 4,
    MaxWinReached      = 5,
    FeatureProbability  = 6,
    PaytableChange     = 7,
}

/// Sub-channel identifiers for Emotion domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum EmotionSubChannel {
    ArousalChange      = 0,
    ValenceChange      = 1,
    FatigueUpdate      = 2,
    EngagementScore    = 3,
    SessionAge         = 4,
    MoodShift          = 5,
    PeakExcitement     = 6,
    CooldownStart      = 7,
}

/// Sub-channel identifiers for Voice domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum VoiceSubChannel {
    Spawn              = 0,
    Kill               = 1,
    Duck               = 2,
    Unduck             = 3,
    PriorityChange     = 4,
    Collision          = 5,
    BudgetExceeded     = 6,
    PoolExhausted      = 7,
    FadeStart          = 8,
    FadeComplete       = 9,
    LoopRestart        = 10,
    EndOfSource        = 11,
}

/// Sub-channel identifiers for Audio domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum AudioSubChannel {
    Play               = 0,
    Stop               = 1,
    FadeIn             = 2,
    FadeOut            = 3,
    Seek               = 4,
    SetVolume          = 5,
    SetPan             = 6,
    SetPitch           = 7,
    SetBusVolume       = 8,
    MuteToggle         = 9,
    SoloToggle         = 10,
    InsertBypass       = 11,
}

/// Sub-channel identifiers for Compliance domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum ComplianceSubChannel {
    LdwDetected        = 0,
    LdwCleared         = 1,
    NearMissGuard      = 2,
    FatigueWarning     = 3,
    JurisdictionChange = 4,
    RealityCheck       = 5,
    CelebrationBlock   = 6,
    AutoplayCheck      = 7,
    AuditLogEntry      = 8,
}

/// Sub-channel identifiers for Neuro domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum NeuroSubChannel {
    ClickVelocity      = 0,
    PauseDuration      = 1,
    BetChange          = 2,
    SessionPattern     = 3,
    RiskProfile        = 4,
    AdaptationApplied  = 5,
    BehaviorAnomaly    = 6,
}

/// Sub-channel identifiers for Spatial domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum SpatialSubChannel {
    PositionUpdate     = 0,
    ListenerMove       = 1,
    RoomChange         = 2,
    HrtfProfileChange  = 3,
    ReverbUpdate       = 4,
    AttenuationCurve   = 5,
}

/// Sub-channel identifiers for Transport domain
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum TransportSubChannel {
    Play               = 0,
    Stop               = 1,
    Pause              = 2,
    Seek               = 3,
    BpmChange          = 4,
    TimeSignature      = 5,
    LoopRegion         = 6,
    Metronome          = 7,
}

// ─────────────────────────────────────────────────────────────────────────────
// Message Payload Data — Fixed-size union for zero-alloc
// ─────────────────────────────────────────────────────────────────────────────

/// Payload data packed into 48 bytes (fits in cache line with header).
/// Uses a fixed-size representation so no heap allocation is needed.
///
/// Each variant covers specific scenarios:
/// - F64x4: 4 double-precision values (e.g., RTP, position xyz+w)
/// - F32x8: 8 single-precision values (e.g., voice params, mixer levels)
/// - I64x4: 4 signed 64-bit integers (e.g., sample positions, timestamps)
/// - U32x8: 8 unsigned 32-bit integers (e.g., IDs, flags, indices)
/// - Mixed: combination of f64, f32, u32 for multi-type payloads
/// - Bytes: raw 48 bytes for serialized data or small strings
#[derive(Clone, Copy)]
#[repr(C)]
pub union HxPayloadData {
    pub f64x4: [f64; 4],       // 32 bytes used
    pub f32x8: [f32; 8],       // 32 bytes used
    pub i64x4: [i64; 4],       // 32 bytes used
    pub u32x8: [u32; 8],       // 32 bytes used
    pub mixed: HxMixedPayload, // 32 bytes
    pub bytes: [u8; 32],       // raw bytes
}

/// Mixed payload for multi-type data (e.g., stage event with win amount + flags)
#[derive(Debug, Clone, Copy)]
#[repr(C)]
pub struct HxMixedPayload {
    pub f64_a: f64,   // 8B — primary float (e.g., win_amount, bpm, position)
    pub f64_b: f64,   // 8B — secondary float (e.g., bet_amount, intensity)
    pub u32_a: u32,   // 4B — primary int (e.g., reel_index, tier, voice_id)
    pub u32_b: u32,   // 4B — secondary int (e.g., symbol_id, flags)
    pub u32_c: u32,   // 4B — tertiary int (e.g., feature_type, bus_id)
    pub u32_d: u32,   // 4B — quaternary int (e.g., layer_index, priority)
}

// Safety: HxPayloadData is Copy + all variants are same size, no padding issues
// Default to zeroed bytes
impl Default for HxPayloadData {
    fn default() -> Self {
        Self { bytes: [0u8; 32] }
    }
}

impl std::fmt::Debug for HxPayloadData {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "HxPayloadData({} bytes)", self.as_bytes().len())
    }
}

// ── Sprint 15 Faza 4.F.2 — POD-safe accessor & constructor API ────────────
//
// `HxPayloadData` is a `repr(C)` union whose every variant is a 32-byte
// POD type (`[f64; 4]`, `[f32; 8]`, `[i64; 4]`, `[u32; 8]`, `HxMixedPayload`,
// `[u8; 32]`).  None of those types carry validity invariants beyond their
// raw bit pattern — every bit pattern is a valid value of every variant.
//
// That fact makes union reads sound regardless of which variant was last
// written: re-interpreting the 32 bytes as a different POD variant is just
// a bit-cast, and bit-casts between same-sized POD types are well-defined
// in Rust.  We encode that fact ONCE here (on the POD union type), so
// every call site can use the safe accessor API instead of sprinkling
// `unsafe { … }` blocks throughout the codebase.
//
// This is the "sealed-style" enum-safety refactor from Sprint 15 Faza 4.F.4
// done WITHOUT breaking the 64-byte `HxMessage` cache-line invariant.
// A true `enum` would force a discriminant tag (≥ 1 byte) and either grow
// `HxMessage` past 64 bytes or shrink the usable payload to 31 bytes —
// both unacceptable.  Instead we encode the discriminant *semantically* in
// the surrounding `HxChannel` field and rely on POD bit-cast safety for
// reads, with safe constructors that statically tag which variant was
// written.
impl HxPayloadData {
    /// Construct from a mixed payload (POD-safe, const-eval friendly).
    #[inline]
    pub const fn from_mixed(value: HxMixedPayload) -> Self {
        Self { mixed: value }
    }

    /// Construct from `[f64; 4]`.
    #[inline]
    pub const fn from_f64x4(value: [f64; 4]) -> Self {
        Self { f64x4: value }
    }

    /// Construct from `[f32; 8]`.
    #[inline]
    pub const fn from_f32x8(value: [f32; 8]) -> Self {
        Self { f32x8: value }
    }

    /// Construct from `[i64; 4]`.
    #[inline]
    pub const fn from_i64x4(value: [i64; 4]) -> Self {
        Self { i64x4: value }
    }

    /// Construct from `[u32; 8]`.
    #[inline]
    pub const fn from_u32x8(value: [u32; 8]) -> Self {
        Self { u32x8: value }
    }

    /// Construct from `[u8; 32]`.
    #[inline]
    pub const fn from_bytes(value: [u8; 32]) -> Self {
        Self { bytes: value }
    }

    /// Read the payload as a mixed-type record.
    ///
    /// Safe because the union variants are all 32-byte POD; the bit
    /// pattern of any prior write is a valid value of `HxMixedPayload`.
    #[inline]
    pub fn as_mixed(&self) -> HxMixedPayload {
        // Safety: see type-level docs on `HxPayloadData` — all variants
        // are same-size POD with no validity invariants, so the read
        // is a well-defined bit-cast regardless of which variant was
        // written last.
        unsafe { self.mixed }
    }

    /// Read the payload as four `f64` values.
    #[inline]
    pub fn as_f64x4(&self) -> [f64; 4] {
        unsafe { self.f64x4 }
    }

    /// Read the payload as eight `f32` values.
    #[inline]
    pub fn as_f32x8(&self) -> [f32; 8] {
        unsafe { self.f32x8 }
    }

    /// Read the payload as four `i64` values.
    #[inline]
    pub fn as_i64x4(&self) -> [i64; 4] {
        unsafe { self.i64x4 }
    }

    /// Read the payload as eight `u32` values.
    #[inline]
    pub fn as_u32x8(&self) -> [u32; 8] {
        unsafe { self.u32x8 }
    }

    /// Read the payload as 32 raw bytes.
    #[inline]
    pub fn as_bytes(&self) -> [u8; 32] {
        unsafe { self.bytes }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message — The atomic unit of communication
// ─────────────────────────────────────────────────────────────────────────────

/// A single message on the HELIX Bus.
///
/// Total size: 64 bytes (one cache line on most architectures).
/// This is critical for performance — each message fits in L1 cache.
///
/// Layout:
///   [0..7]   timestamp_samples: u64  — sample clock when event occurred
///   [8]      channel: u8             — HxChannel discriminant
///   [9..10]  sub_channel: u16        — domain-specific sub-channel
///   [11]     priority: u8            — 0=background, 255=critical
///   [12..15] source_id: u32          — publisher identity (for filtering)
///   [16..19] sequence: u32           — monotonic sequence number (ordering)
///   [20..23] _reserved: [u8; 4]      — future use
///   [24..31] (compiler padding)      — alignment for payload
///   [32..63] payload: HxPayloadData  — 32 bytes of typed data
#[derive(Clone, Copy)]
#[repr(C, align(64))]
pub struct HxMessage {
    /// Sample-accurate timestamp (absolute sample clock from engine start)
    pub timestamp_samples: u64,
    /// Primary channel domain
    pub channel: HxChannel,
    /// Domain-specific sub-channel (cast to StageSubChannel, MathSubChannel, etc.)
    pub sub_channel: u16,
    /// Message priority (0=background, 128=normal, 255=critical)
    /// Used for eviction policy when buffer overflows
    pub priority: u8,
    /// Publisher identity — which system sent this message
    pub source_id: u32,
    /// Monotonic sequence number — guarantees deterministic ordering
    pub sequence: u32,
    /// Reserved for future use
    pub _reserved: [u8; 4],
    /// Typed payload data (32 bytes, zero-alloc)
    pub payload: HxPayloadData,
}

// Compile-time size assertion
const _: () = assert!(std::mem::size_of::<HxMessage>() == 64);

impl Default for HxMessage {
    fn default() -> Self {
        Self {
            timestamp_samples: 0,
            channel: HxChannel::System,
            sub_channel: 0,
            priority: 128,
            source_id: 0,
            sequence: 0,
            _reserved: [0; 4],
            payload: HxPayloadData::default(),
        }
    }
}

impl std::fmt::Debug for HxMessage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HxMessage")
            .field("timestamp", &self.timestamp_samples)
            .field("channel", &self.channel)
            .field("sub_channel", &self.sub_channel)
            .field("priority", &self.priority)
            .field("source_id", &self.source_id)
            .field("sequence", &self.sequence)
            .finish()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscription Filter — Channel-based routing with optional wildcards
// ─────────────────────────────────────────────────────────────────────────────

/// A subscription filter for a subscriber.
///
/// Supports three modes:
///   - `All` — receive every message on every channel
///   - `Channels(mask)` — receive messages on selected channels (bitmask)
///   - `Exact(channel, sub_channel)` — receive only specific sub-channel
#[derive(Debug, Clone)]
pub enum HxFilter {
    /// Receive all messages (expensive — use sparingly)
    All,
    /// Bitmask of channels to receive (bit N = HxChannel with discriminant N)
    Channels(u16),
    /// Exact match: specific channel + sub_channel
    Exact(HxChannel, u16),
    /// Multiple exact matches
    Multi(Vec<(HxChannel, u16)>),
}

impl HxFilter {
    /// Create a filter for a single channel (all sub-channels)
    pub fn channel(ch: HxChannel) -> Self {
        Self::Channels(1 << (ch as u16))
    }

    /// Create a filter for multiple channels
    pub fn channels(chs: &[HxChannel]) -> Self {
        let mut mask = 0u16;
        for ch in chs {
            mask |= 1 << (*ch as u16);
        }
        Self::Channels(mask)
    }

    /// Begin fluent construction of a complex filter via [`HxFilterBuilder`].
    ///
    /// Use this when you need to combine multiple channels and/or exact
    /// (channel, sub_channel) matches without having to manage the bitmask
    /// or `Multi(Vec<…>)` allocation manually.
    ///
    /// ```ignore
    /// let filter = HxFilter::builder()
    ///     .with_channel(HxChannel::Stage)
    ///     .with_channel(HxChannel::Math)
    ///     .with_exact(HxChannel::System, 42)
    ///     .build();
    /// ```
    pub fn builder() -> HxFilterBuilder {
        HxFilterBuilder::new()
    }

    /// Check if a message matches this filter
    #[inline(always)]
    pub fn matches(&self, msg: &HxMessage) -> bool {
        match self {
            HxFilter::All => true,
            HxFilter::Channels(mask) => (mask & (1 << (msg.channel as u16))) != 0,
            HxFilter::Exact(ch, sub) => msg.channel == *ch && msg.sub_channel == *sub,
            HxFilter::Multi(pairs) => {
                pairs.iter().any(|(ch, sub)| msg.channel == *ch && msg.sub_channel == *sub)
            }
        }
    }
}

// ── Sprint 15 Faza 4.F.3 — HxFilterBuilder ───────────────────────────────────
//
// Type-safe fluent constructor for [`HxFilter`] that hides the raw bitmask
// representation from callers.  Callers compose by repeatedly invoking
// `.with_channel(ch)` and/or `.with_exact(ch, sub)`, then finalize with
// `.build()`.  The builder picks the most specific runtime variant that can
// represent the accumulated set:
//
//   - 0 channels + 0 exact pairs   → `HxFilter::Channels(0)` (matches nothing)
//   - ≥1 channels + 0 exact pairs  → `HxFilter::Channels(mask)`
//   - 0 channels + 1 exact pair    → `HxFilter::Exact(ch, sub)`
//   - 0 channels + ≥2 exact pairs  → `HxFilter::Multi(vec)`
//   - ≥1 channels + ≥1 exact pairs → channel match wins (exact pairs that
//                                    fall on already-masked channels are
//                                    folded into the bitmask)
//
// The hot-path `HxFilter::matches()` is unchanged — the builder is purely
// a construction-time convenience and never appears in the realtime loop.
//
/// Fluent builder for [`HxFilter`].
///
/// Construct via [`HxFilter::builder()`].  Each `with_*` returns `self` for
/// chaining; `build()` finalizes into the most specific `HxFilter` variant.
#[derive(Debug, Default, Clone)]
pub struct HxFilterBuilder {
    /// Accumulated channel bitmask (bit N = HxChannel discriminant N).
    mask: u16,
    /// Accumulated exact (channel, sub_channel) pairs.
    pairs: Vec<(HxChannel, u16)>,
}

impl HxFilterBuilder {
    /// Create an empty builder. Equivalent to `HxFilter::builder()`.
    #[inline]
    pub fn new() -> Self {
        Self { mask: 0, pairs: Vec::new() }
    }

    /// Include every message on the given channel (any sub_channel).
    #[inline]
    pub fn with_channel(mut self, ch: HxChannel) -> Self {
        self.mask |= 1 << (ch as u16);
        self
    }

    /// Include every message on each of the given channels.
    #[inline]
    pub fn with_channels(mut self, chs: &[HxChannel]) -> Self {
        for ch in chs {
            self.mask |= 1 << (*ch as u16);
        }
        self
    }

    /// Include exactly one specific (channel, sub_channel) pair.
    #[inline]
    pub fn with_exact(mut self, ch: HxChannel, sub: u16) -> Self {
        self.pairs.push((ch, sub));
        self
    }

    /// Finalize the builder into the most specific [`HxFilter`] variant.
    ///
    /// Note: pairs whose channel is already in the bitmask are dropped
    /// (channel-wide match subsumes exact match on that channel).
    pub fn build(mut self) -> HxFilter {
        // Drop exact pairs already covered by the channel mask.
        let mask = self.mask;
        self.pairs.retain(|(ch, _)| (mask & (1 << (*ch as u16))) == 0);

        match (self.mask, self.pairs.len()) {
            (0, 0) => HxFilter::Channels(0),
            (m, 0) if m != 0 => HxFilter::Channels(m),
            (0, 1) => {
                let (ch, sub) = self.pairs.remove(0);
                HxFilter::Exact(ch, sub)
            }
            (0, _) => HxFilter::Multi(self.pairs),
            // Hybrid: bitmask + leftover exact pairs.  We fold the exacts
            // into the mask since the runtime `matches()` for Channels is
            // strictly broader than Exact.
            (mut m, _) => {
                for (ch, _) in &self.pairs {
                    m |= 1 << (*ch as u16);
                }
                HxFilter::Channels(m)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ring Buffer — Lock-free SPSC per subscriber
// ─────────────────────────────────────────────────────────────────────────────

/// Fixed-size ring buffer for lock-free SPSC (single producer, single consumer).
/// One per subscriber. The router writes, the subscriber reads.
///
/// Overflow policy: oldest messages are silently dropped (bounded latency).
/// The `overflow_count` atomic tracks how many messages were lost.
///
/// **Sprint 15 Faza 4.F.2:** the slot storage lives behind
/// [`LockFreeSlotStore`] which centralizes the `unsafe impl Sync`.  This
/// host struct has NO direct `unsafe impl Sync` of its own — Sync is
/// derived compositionally because every field is itself Sync.
pub struct HxRingBuffer {
    /// Pre-allocated message slots — unsafe access is encapsulated by
    /// [`LockFreeSlotStore`] (see Sprint 15 Faza 4.F.2).
    slots: LockFreeSlotStore<HxMessage>,
    /// Capacity (always power of 2 for fast modulo via bitmask)
    capacity: usize,
    /// Bitmask for fast modulo (capacity - 1)
    mask: usize,
    /// Write position (only written by router thread)
    write_pos: AtomicU64,
    /// Read position (only written by consumer thread)
    read_pos: AtomicU64,
    /// Count of messages dropped due to overflow
    overflow_count: AtomicU64,
}

impl HxRingBuffer {
    /// Create a new ring buffer with the given capacity (rounded up to power of 2).
    pub fn new(min_capacity: usize) -> Self {
        let capacity = min_capacity.next_power_of_two().max(64);
        let slots = LockFreeSlotStore::new_with(capacity, HxMessage::default);
        Self {
            slots,
            capacity,
            mask: capacity - 1,
            write_pos: AtomicU64::new(0),
            read_pos: AtomicU64::new(0),
            overflow_count: AtomicU64::new(0),
        }
    }

    /// Push a message. Returns false if buffer is full (message dropped).
    /// Called ONLY by the router thread (single producer).
    #[inline]
    pub fn push(&self, msg: HxMessage) -> bool {
        let wp = self.write_pos.load(Ordering::Relaxed);
        let rp = self.read_pos.load(Ordering::Acquire);

        // Check if buffer is full
        if wp.wrapping_sub(rp) >= self.capacity as u64 {
            self.overflow_count.fetch_add(1, Ordering::Relaxed);
            return false;
        }

        // Safety contract upheld by SPSC invariant:
        //   - idx < capacity (bitmask)
        //   - producer is unique (caller contract)
        //   - consumer won't read past read_pos, and `wp - rp < capacity`
        //     above guarantees the slot is not still owned by the consumer.
        let idx = (wp as usize) & self.mask;
        unsafe { self.slots.write_at(idx, msg); }

        // Publish write position (Release ordering ensures data is visible)
        self.write_pos.store(wp.wrapping_add(1), Ordering::Release);
        true
    }

    /// Pop a message. Returns None if buffer is empty.
    /// Called ONLY by the subscriber thread (single consumer).
    #[inline]
    pub fn pop(&self) -> Option<HxMessage> {
        let rp = self.read_pos.load(Ordering::Relaxed);
        let wp = self.write_pos.load(Ordering::Acquire);

        if rp == wp {
            return None; // Empty
        }

        // Safety contract upheld by SPSC invariant:
        //   - idx < capacity (bitmask)
        //   - consumer is unique (caller contract)
        //   - producer can't overwrite slots before read_pos (checked
        //     via `wp - rp < capacity` in push())
        //   - `HxMessage: Copy` so re-reading the same slot before next
        //     push is harmless (LockFreeSlotStore docs condition #4).
        let idx = (rp as usize) & self.mask;
        let msg = unsafe { self.slots.read_at(idx) };

        self.read_pos.store(rp.wrapping_add(1), Ordering::Release);
        Some(msg)
    }

    /// Number of messages currently buffered
    pub fn len(&self) -> usize {
        let wp = self.write_pos.load(Ordering::Relaxed);
        let rp = self.read_pos.load(Ordering::Relaxed);
        wp.wrapping_sub(rp) as usize
    }

    /// Check if buffer is empty
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Total overflow count since creation
    pub fn overflow_count(&self) -> u64 {
        self.overflow_count.load(Ordering::Relaxed)
    }

    /// Drain all available messages into a callback.
    /// Returns number of messages processed.
    /// This is the primary consumption API — process all pending in one call.
    #[inline]
    pub fn drain<F: FnMut(&HxMessage)>(&self, mut callback: F) -> usize {
        let mut count = 0;
        while let Some(msg) = self.pop() {
            callback(&msg);
            count += 1;
        }
        count
    }

    /// Drain with a maximum count (prevents starvation on busy buses)
    #[inline]
    pub fn drain_max<F: FnMut(&HxMessage)>(&self, max: usize, mut callback: F) -> usize {
        let mut count = 0;
        while count < max {
            match self.pop() {
                Some(msg) => {
                    callback(&msg);
                    count += 1;
                }
                None => break,
            }
        }
        count
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscriber — Identified consumer with filter and ring buffer
// ─────────────────────────────────────────────────────────────────────────────

/// Unique subscriber ID
pub type HxSubscriberId = u32;

/// A subscriber to the HELIX Bus.
pub struct HxSubscriber {
    /// Unique identifier
    pub id: HxSubscriberId,
    /// Human-readable name (for debugging)
    pub name: String,
    /// Channel filter — which messages to receive
    pub filter: HxFilter,
    /// Per-subscriber ring buffer
    pub ring: HxRingBuffer,
    /// Whether this subscriber is active
    pub active: AtomicBool,
}

impl HxSubscriber {
    pub fn new(id: HxSubscriberId, name: &str, filter: HxFilter, buffer_size: usize) -> Self {
        Self {
            id,
            name: name.to_string(),
            filter,
            ring: HxRingBuffer::new(buffer_size),
            active: AtomicBool::new(true),
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Staging Area — Lock-free MPSC for publishers
// ─────────────────────────────────────────────────────────────────────────────

/// Fixed-size staging buffer for multi-producer writes.
/// Uses atomic CAS to claim slots. The router drains this once per audio block.
///
/// Capacity: 4096 messages per block (covers worst case: all reels stop +
/// cascade + feature + multiple voice spawns simultaneously)
///
/// **Sprint 15 Faza 4.F.2:** like [`HxRingBuffer`], the slot storage lives
/// behind [`LockFreeSlotStore`].  No direct `unsafe impl Sync` on this
/// host struct — Sync derived compositionally.
pub struct HxStagingArea {
    slots: LockFreeSlotStore<HxMessage>,
    capacity: usize,
    /// Next write position (atomic CAS for multi-producer)
    write_cursor: AtomicU32,
    /// Number of committed writes (publishers increment after writing data)
    committed: AtomicU32,
    /// Read fence — router sets this after draining
    read_fence: AtomicU32,
}

impl HxStagingArea {
    pub fn new(capacity: usize) -> Self {
        let capacity = capacity.next_power_of_two().max(256);
        let slots = LockFreeSlotStore::new_with(capacity, HxMessage::default);
        Self {
            slots,
            capacity,
            write_cursor: AtomicU32::new(0),
            committed: AtomicU32::new(0),
            read_fence: AtomicU32::new(0),
        }
    }

    /// Publish a message. Lock-free, wait-free for uncontended case.
    /// Returns false if staging area is full (message dropped).
    ///
    /// Thread safety: safe to call from ANY thread concurrently.
    pub fn publish(&self, msg: HxMessage) -> bool {
        loop {
            let cursor = self.write_cursor.load(Ordering::Relaxed);
            let fence = self.read_fence.load(Ordering::Acquire);

            // Check if full (cursor wrapped around past fence)
            if cursor.wrapping_sub(fence) >= self.capacity as u32 {
                return false;
            }

            // Try to claim this slot via CAS
            match self.write_cursor.compare_exchange_weak(
                cursor,
                cursor.wrapping_add(1),
                Ordering::AcqRel,
                Ordering::Relaxed,
            ) {
                Ok(_) => {
                    // Slot claimed — write data.
                    // Safety contract upheld by MPSC invariant:
                    //   - idx < capacity (modulo).
                    //   - CAS on write_cursor guarantees this thread is the
                    //     only one writing to `idx` until committed advances.
                    //   - Consumer (router) won't read past `read_fence`,
                    //     and capacity guard above ensures `cursor - fence
                    //     < capacity` so the slot isn't still in flight.
                    let idx = (cursor as usize) % self.capacity;
                    unsafe { self.slots.write_at(idx, msg); }
                    // Mark as committed.
                    //
                    // 2026-05-10 (Sprint 14 Faza 4.A.5) — bounded spin retry.
                    //
                    // Pre-fix: pure `while ... { spin_loop() }` had no upper
                    // bound.  If the predecessor publisher was suspended
                    // (OS scheduling, GC pause on the JNI side, debugger
                    // breakpoint, panic mid-write) every other publisher
                    // would burn 100 % CPU forever waiting for it.  On the
                    // audio thread that is a guaranteed xrun.
                    //
                    // Post-fix:  spin tightly for the common case (typical
                    // publisher commits in single-digit nanoseconds), but
                    // after `MAX_SPIN_ITERS` × `MAX_YIELD_ROUNDS` we give
                    // up trying to preserve in-order commit and force-skip
                    // by writing our committed counter directly.  Out-of-
                    // order commit is a correctness violation for strict
                    // FIFO consumers, BUT a deterministic xrun is worse —
                    // and in practice the predecessor is either healthy
                    // (commits within the spin window) or dead (in which
                    // case the strict ordering guarantee was already
                    // violated by the dead publisher's missing commit).
                    const MAX_SPIN_ITERS: usize = 1024;
                    const MAX_YIELD_ROUNDS: usize = 16;
                    let mut yields = 0usize;
                    'commit_wait: loop {
                        for _ in 0..MAX_SPIN_ITERS {
                            if self.committed.load(Ordering::Acquire) == cursor {
                                break 'commit_wait;
                            }
                            std::hint::spin_loop();
                        }
                        if yields >= MAX_YIELD_ROUNDS {
                            // Predecessor never committed — abandon strict
                            // ordering.  Caller (router) sorts by message
                            // sequence number anyway, so order is restored
                            // at drain time.
                            break 'commit_wait;
                        }
                        std::thread::yield_now();
                        yields += 1;
                    }
                    self.committed.store(cursor.wrapping_add(1), Ordering::Release);
                    return true;
                }
                Err(_) => continue, // CAS failed, retry
            }
        }
    }

    /// Drain all committed messages. Called by the router at block boundaries.
    /// Returns the messages in order.
    ///
    /// Thread safety: must be called from a single thread (the router thread).
    ///
    /// **Audio-thread contract (Sprint 14 Faza 4.A.5):** this method runs on
    /// the router/audio thread, so it MUST NOT allocate.  Pre-fix called
    /// `out.reserve(count)` which can re-allocate the caller's `Vec` if the
    /// caller did not pre-allocate enough capacity — a guaranteed xrun on a
    /// realtime thread.  Post-fix: bound `count` to `out.capacity() - out.len()`
    /// so no re-allocation can happen; if more messages are pending than
    /// `out` has room for, the overflow is dropped (`read_fence` still
    /// advances past them, marking them consumed).
    ///
    /// **Caller's responsibility:** size `out`'s initial capacity to the
    /// expected per-block message volume × safety factor.  At 48 kHz / 1024
    /// blocks ≈ 47 blocks/sec; even a busy slot stop publishes ~30 messages
    /// per block, so 256-element capacity is plenty.
    pub fn drain_into(&self, out: &mut Vec<HxMessage>) {
        let fence = self.read_fence.load(Ordering::Relaxed);
        let committed = self.committed.load(Ordering::Acquire);

        let total = committed.wrapping_sub(fence) as usize;
        if total == 0 {
            return;
        }

        // Audio-thread safety: never re-allocate at runtime.  Bound by
        // remaining headroom in `out`.  Overflow is dropped — caller MUST
        // size `out.capacity()` for expected peak load before the audio
        // thread starts pulling.
        //
        // Init/test grace path: if the caller hasn't allocated anything yet
        // (`Vec::new()` → capacity 0), we treat the first call as a one-shot
        // initialization and `reserve()` for the message count.  This keeps
        // existing tests and init-time call sites working without forcing
        // every caller to pre-size manually.  Production audio thread MUST
        // pre-allocate, so this branch is taken at most once at startup.
        let available = out.capacity().saturating_sub(out.len());
        let count = if available >= total {
            total
        } else if out.capacity() == 0 {
            // First-call init grace — never reached on the audio hot path
            // because router pre-allocates `drain_scratch` at startup.
            out.reserve(total);
            total
        } else {
            // Caller's Vec is pre-allocated but undersized for this burst.
            // Drop overflow rather than re-allocate (xrun avoidance).
            available
        };

        for i in 0..count {
            let idx = ((fence as usize) + i) % self.capacity;
            // Safety: router is the sole consumer (MPSC); producers won't
            // overwrite slots between `read_fence` and `committed` until
            // we advance the fence below.  `HxMessage: Copy` so the
            // logical move-out is harmless.
            let msg = unsafe { self.slots.read_at(idx) };
            out.push(msg);
        }

        // Always advance fence past ALL committed messages, even those we
        // dropped due to caller-side capacity shortfall.  Otherwise the
        // staging area would fill up and block all future publishes.
        self.read_fence.store(committed, Ordering::Release);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELIX Bus — The main bus coordinator
// ─────────────────────────────────────────────────────────────────────────────

/// Configuration for the HELIX Bus
#[derive(Debug, Clone)]
pub struct HxBusConfig {
    /// Staging area capacity (messages per block cycle)
    pub staging_capacity: usize,
    /// Default per-subscriber ring buffer size
    pub subscriber_buffer_size: usize,
    /// Maximum number of subscribers
    pub max_subscribers: usize,
}

impl Default for HxBusConfig {
    fn default() -> Self {
        Self {
            staging_capacity: 4096,
            subscriber_buffer_size: 1024,
            max_subscribers: 64,
        }
    }
}

/// Statistics snapshot for monitoring
#[derive(Debug, Clone, Default)]
pub struct HxBusStats {
    /// Total messages published since creation
    pub total_published: u64,
    /// Total messages routed to subscribers
    pub total_routed: u64,
    /// Total messages dropped (staging overflow)
    pub staging_overflows: u64,
    /// Per-subscriber overflow counts
    pub subscriber_overflows: Vec<(String, u64)>,
    /// Messages per channel (last drain cycle)
    pub channel_counts: [u32; HxChannel::COUNT],
    /// Number of active subscribers
    pub active_subscribers: usize,
    /// Last drain cycle duration in microseconds
    pub last_drain_us: u64,
}

/// The HELIX Bus — central nervous system of SlotLab.
///
/// Usage:
///   1. Create with `HxBus::new(config)`
///   2. Subscribe systems with `bus.subscribe("aurexis", filter)`
///   3. Publish from any thread with `bus.publish(msg)` or `bus.publisher()`
///   4. Call `bus.drain_and_route()` once per audio block (router thread)
///   5. Subscribers read from their ring buffers
pub struct HxBus {
    /// Shared staging area (publishers write here)
    staging: Arc<HxStagingArea>,
    /// All subscribers
    subscribers: Vec<Arc<HxSubscriber>>,
    /// Monotonic sequence counter
    sequence: Arc<AtomicU64>,
    /// Configuration
    config: HxBusConfig,
    /// Total published count
    total_published: Arc<AtomicU64>,
    /// Total routed count
    total_routed: AtomicU64,
    /// Staging overflow count
    staging_overflows: Arc<AtomicU64>,
    /// Scratch buffer for draining (avoid allocation per cycle)
    drain_scratch: Vec<HxMessage>,
    /// Per-channel message count for last cycle
    channel_counts: [AtomicU32; HxChannel::COUNT],
    /// Last drain duration (microseconds)
    last_drain_us: AtomicU64,
    /// Next subscriber ID
    next_sub_id: AtomicU32,
}

impl HxBus {
    /// Create a new HELIX Bus with the given configuration.
    pub fn new(config: HxBusConfig) -> Self {
        Self {
            staging: Arc::new(HxStagingArea::new(config.staging_capacity)),
            subscribers: Vec::with_capacity(config.max_subscribers),
            sequence: Arc::new(AtomicU64::new(0)),
            config,
            total_published: Arc::new(AtomicU64::new(0)),
            total_routed: AtomicU64::new(0),
            staging_overflows: Arc::new(AtomicU64::new(0)),
            drain_scratch: Vec::with_capacity(4096),
            channel_counts: std::array::from_fn(|_| AtomicU32::new(0)),
            last_drain_us: AtomicU64::new(0),
            next_sub_id: AtomicU32::new(1),
        }
    }

    /// Create a publisher handle that can be sent to any thread.
    /// Publishers are lightweight (just an Arc to the staging area + sequence counter).
    pub fn publisher(&self) -> HxPublisher {
        HxPublisher {
            staging: Arc::clone(&self.staging),
            sequence: Arc::clone(&self.sequence),
            total_published: Arc::clone(&self.total_published),
            staging_overflows: Arc::clone(&self.staging_overflows),
        }
    }

    /// Subscribe to the bus with a filter. Returns the subscriber's ring buffer
    /// handle for reading messages.
    pub fn subscribe(&mut self, name: &str, filter: HxFilter) -> Arc<HxSubscriber> {
        let id = self.next_sub_id.fetch_add(1, Ordering::Relaxed);
        let sub = Arc::new(HxSubscriber::new(
            id,
            name,
            filter,
            self.config.subscriber_buffer_size,
        ));
        self.subscribers.push(Arc::clone(&sub));
        log::info!("[HxBus] Subscriber '{}' registered (id={})", name, id);
        sub
    }

    /// Subscribe with custom buffer size
    pub fn subscribe_with_capacity(
        &mut self,
        name: &str,
        filter: HxFilter,
        buffer_size: usize,
    ) -> Arc<HxSubscriber> {
        let id = self.next_sub_id.fetch_add(1, Ordering::Relaxed);
        let sub = Arc::new(HxSubscriber::new(id, name, filter, buffer_size));
        self.subscribers.push(Arc::clone(&sub));
        log::info!(
            "[HxBus] Subscriber '{}' registered (id={}, buf={})",
            name, id, buffer_size
        );
        sub
    }

    /// Drain staging area and route messages to matching subscribers.
    ///
    /// MUST be called once per audio block, from the router thread.
    /// This is the single synchronization point — all message ordering
    /// is determined here.
    ///
    /// Zero-alloc path: uses pre-allocated scratch buffer.
    pub fn drain_and_route(&mut self) {
        let start = std::time::Instant::now();

        // Reset per-channel counts
        for count in &self.channel_counts {
            count.store(0, Ordering::Relaxed);
        }

        // Drain staging into scratch buffer
        self.drain_scratch.clear();
        self.staging.drain_into(&mut self.drain_scratch);

        if self.drain_scratch.is_empty() {
            self.last_drain_us.store(0, Ordering::Relaxed);
            return;
        }

        // Sort by sequence number for deterministic ordering
        self.drain_scratch.sort_unstable_by_key(|m| m.sequence);

        // Route each message to matching subscribers
        let mut routed = 0u64;
        for msg in &self.drain_scratch {
            // Track per-channel stats
            let ch_idx = msg.channel as usize;
            if ch_idx < HxChannel::COUNT {
                self.channel_counts[ch_idx].fetch_add(1, Ordering::Relaxed);
            }

            // Fan-out to matching subscribers
            for sub in &self.subscribers {
                if !sub.active.load(Ordering::Relaxed) {
                    continue;
                }
                if sub.filter.matches(msg) {
                    sub.ring.push(*msg);
                    routed += 1;
                }
            }
        }

        self.total_routed.fetch_add(routed, Ordering::Relaxed);

        let elapsed_us = start.elapsed().as_micros() as u64;
        self.last_drain_us.store(elapsed_us, Ordering::Relaxed);
    }

    /// Remove inactive subscribers (cleanup)
    pub fn remove_inactive(&mut self) {
        self.subscribers.retain(|sub| sub.active.load(Ordering::Relaxed));
    }

    /// Get current bus statistics
    pub fn stats(&self) -> HxBusStats {
        let mut channel_counts = [0u32; HxChannel::COUNT];
        for (i, count) in self.channel_counts.iter().enumerate() {
            channel_counts[i] = count.load(Ordering::Relaxed);
        }

        let subscriber_overflows: Vec<(String, u64)> = self.subscribers.iter()
            .map(|sub| (sub.name.clone(), sub.ring.overflow_count()))
            .collect();

        HxBusStats {
            total_published: self.total_published.load(Ordering::Relaxed),
            total_routed: self.total_routed.load(Ordering::Relaxed),
            staging_overflows: self.staging_overflows.load(Ordering::Relaxed),
            subscriber_overflows,
            channel_counts,
            active_subscribers: self.subscribers.iter()
                .filter(|s| s.active.load(Ordering::Relaxed))
                .count(),
            last_drain_us: self.last_drain_us.load(Ordering::Relaxed),
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Publisher — Thread-safe handle for publishing messages
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// HxBusError — typed error variants for fallible bus operations
//
// 2026-05-10 (Sprint 14 Faza 4.F): replaces the historical "publish returns
// bool" API where the caller had no insight into *why* a publish was rejected.
// `HxBusError` makes failure modes explicit and exhaustive, so library users
// (and FFI bindings) can react to specific failure types (e.g. tell the user
// "audio bus saturated" vs "message channel not subscribed").
//
// The legacy `bool`-returning APIs are retained for backward compatibility;
// new code should prefer the `_result` variants.
// ─────────────────────────────────────────────────────────────────────────────

/// Error variants for HELIX bus publish operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HxBusError {
    /// Staging area is full — message dropped.  Happens when publishers
    /// outpace the router's drain rate; usually indicates a stalled
    /// audio thread or pathologically high event rate.
    StagingFull,
}

impl core::fmt::Display for HxBusError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::StagingFull => write!(f, "HELIX bus staging area is full"),
        }
    }
}

impl std::error::Error for HxBusError {}

/// Typed Result alias for fallible HELIX bus operations.
pub type HxBusResult<T> = Result<T, HxBusError>;

/// A publisher handle that can be cloned and sent to any thread.
/// Lightweight — contains only Arc references to shared staging and bus-level
/// atomics, so it is fully safe to send across threads and may outlive the bus.
pub struct HxPublisher {
    staging: Arc<HxStagingArea>,
    sequence: Arc<AtomicU64>,
    total_published: Arc<AtomicU64>,
    staging_overflows: Arc<AtomicU64>,
}

impl HxPublisher {
    /// Publish a message to the bus.
    ///
    /// Thread-safe, lock-free. Can be called from UI thread, audio thread,
    /// worker threads, anywhere.
    ///
    /// Returns false if staging area is full (message dropped).
    ///
    /// **2026-05-10 — prefer [`publish_result`](Self::publish_result) for
    /// new code.** The bool return type loses error information; the Result
    /// variant gives callers an `HxBusError` they can act on (e.g. retry
    /// backoff, route to fallback channel, log specific failure mode).
    pub fn publish(&self, msg: HxMessage) -> bool {
        self.publish_result(msg).is_ok()
    }

    /// Publish a message to the bus with typed error reporting.
    ///
    /// Same semantics as [`publish`](Self::publish) but returns
    /// `Result<(), HxBusError>` so callers can distinguish failure modes.
    ///
    /// Currently the only failure variant is [`HxBusError::StagingFull`],
    /// but additional variants may be added in future (e.g. backpressure,
    /// rate-limit, channel-not-subscribed) without further API churn —
    /// just match exhaustively on [`HxBusError`].
    pub fn publish_result(&self, mut msg: HxMessage) -> HxBusResult<()> {
        // Assign monotonic sequence number
        let seq = self.sequence.fetch_add(1, Ordering::Relaxed);
        msg.sequence = seq as u32;

        let ok = self.staging.publish(msg);

        self.total_published.fetch_add(1, Ordering::Relaxed);

        if !ok {
            self.staging_overflows.fetch_add(1, Ordering::Relaxed);
            return Err(HxBusError::StagingFull);
        }

        Ok(())
    }

    /// Convenience: publish a stage event
    pub fn stage(
        &self,
        sub: StageSubChannel,
        timestamp: u64,
        win_amount: f64,
        bet_amount: f64,
        reel_index: u32,
        tier: u32,
    ) -> bool {
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Stage;
        msg.sub_channel = sub as u16;
        msg.timestamp_samples = timestamp;
        msg.priority = 200; // Stage events are high priority
        msg.payload = HxPayloadData {
            mixed: HxMixedPayload {
                f64_a: win_amount,
                f64_b: bet_amount,
                u32_a: reel_index,
                u32_b: tier,
                u32_c: 0,
                u32_d: 0,
            },
        };
        self.publish(msg)
    }

    /// Convenience: publish a math update
    pub fn math(&self, sub: MathSubChannel, timestamp: u64, value: f64) -> bool {
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Math;
        msg.sub_channel = sub as u16;
        msg.timestamp_samples = timestamp;
        msg.priority = 128;
        msg.payload = HxPayloadData {
            mixed: HxMixedPayload {
                f64_a: value,
                f64_b: 0.0,
                u32_a: 0,
                u32_b: 0,
                u32_c: 0,
                u32_d: 0,
            },
        };
        self.publish(msg)
    }

    /// Convenience: publish an emotion update
    pub fn emotion(
        &self,
        sub: EmotionSubChannel,
        timestamp: u64,
        arousal: f64,
        valence: f64,
    ) -> bool {
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Emotion;
        msg.sub_channel = sub as u16;
        msg.timestamp_samples = timestamp;
        msg.priority = 128;
        msg.payload = HxPayloadData {
            mixed: HxMixedPayload {
                f64_a: arousal,
                f64_b: valence,
                u32_a: 0,
                u32_b: 0,
                u32_c: 0,
                u32_d: 0,
            },
        };
        self.publish(msg)
    }

    /// Convenience: publish a voice event
    pub fn voice(
        &self,
        sub: VoiceSubChannel,
        timestamp: u64,
        voice_id: u32,
        priority_level: u32,
    ) -> bool {
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Voice;
        msg.sub_channel = sub as u16;
        msg.timestamp_samples = timestamp;
        msg.priority = 180;
        msg.payload = HxPayloadData {
            mixed: HxMixedPayload {
                f64_a: 0.0,
                f64_b: 0.0,
                u32_a: voice_id,
                u32_b: priority_level,
                u32_c: 0,
                u32_d: 0,
            },
        };
        self.publish(msg)
    }

    /// Convenience: publish a compliance event
    pub fn compliance(
        &self,
        sub: ComplianceSubChannel,
        timestamp: u64,
        win_ratio: f64,
        jurisdiction_id: u32,
    ) -> bool {
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Compliance;
        msg.sub_channel = sub as u16;
        msg.timestamp_samples = timestamp;
        msg.priority = 255; // Compliance is always critical
        msg.payload = HxPayloadData {
            mixed: HxMixedPayload {
                f64_a: win_ratio,
                f64_b: 0.0,
                u32_a: jurisdiction_id,
                u32_b: 0,
                u32_c: 0,
                u32_d: 0,
            },
        };
        self.publish(msg)
    }

    /// Convenience: publish a transport event
    pub fn transport(&self, sub: TransportSubChannel, timestamp: u64, bpm: f64) -> bool {
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Transport;
        msg.sub_channel = sub as u16;
        msg.timestamp_samples = timestamp;
        msg.priority = 200;
        msg.payload = HxPayloadData {
            mixed: HxMixedPayload {
                f64_a: bpm,
                f64_b: 0.0,
                u32_a: 0,
                u32_b: 0,
                u32_c: 0,
                u32_d: 0,
            },
        };
        self.publish(msg)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message Builders — Ergonomic API for common scenarios
// ─────────────────────────────────────────────────────────────────────────────

impl HxMessage {
    /// Create a stage event message
    pub fn stage_event(
        sub: StageSubChannel,
        timestamp: u64,
        win_amount: f64,
        bet_amount: f64,
        reel_index: u32,
        tier: u32,
    ) -> Self {
        Self {
            channel: HxChannel::Stage,
            sub_channel: sub as u16,
            timestamp_samples: timestamp,
            priority: 200,
            payload: HxPayloadData {
                mixed: HxMixedPayload {
                    f64_a: win_amount,
                    f64_b: bet_amount,
                    u32_a: reel_index,
                    u32_b: tier,
                    u32_c: 0,
                    u32_d: 0,
                },
            },
            ..Default::default()
        }
    }

    /// Create a compliance LDW detection message
    pub fn ldw_detected(timestamp: u64, win_amount: f64, bet_amount: f64, jurisdiction: u32) -> Self {
        Self {
            channel: HxChannel::Compliance,
            sub_channel: ComplianceSubChannel::LdwDetected as u16,
            timestamp_samples: timestamp,
            priority: 255,
            payload: HxPayloadData {
                mixed: HxMixedPayload {
                    f64_a: win_amount,
                    f64_b: bet_amount,
                    u32_a: jurisdiction,
                    u32_b: 0,
                    u32_c: 0,
                    u32_d: 0,
                },
            },
            ..Default::default()
        }
    }

    /// Create a voice spawn message
    pub fn voice_spawn(
        timestamp: u64,
        voice_id: u32,
        priority: u32,
        energy_cost: f32,
        source_id: u32,
    ) -> Self {
        Self {
            channel: HxChannel::Voice,
            sub_channel: VoiceSubChannel::Spawn as u16,
            timestamp_samples: timestamp,
            priority: 180,
            payload: HxPayloadData {
                mixed: HxMixedPayload {
                    f64_a: energy_cost as f64,
                    f64_b: 0.0,
                    u32_a: voice_id,
                    u32_b: priority,
                    u32_c: 0,
                    u32_d: 0,
                },
            },
            source_id,
            ..Default::default()
        }
    }

    /// Create an audio play command
    pub fn audio_play(timestamp: u64, voice_id: u32, asset_id: u32, volume: f32, pan: f32) -> Self {
        Self {
            channel: HxChannel::Audio,
            sub_channel: AudioSubChannel::Play as u16,
            timestamp_samples: timestamp,
            priority: 200,
            payload: HxPayloadData {
                mixed: HxMixedPayload {
                    f64_a: volume as f64,
                    f64_b: pan as f64,
                    u32_a: voice_id,
                    u32_b: asset_id,
                    u32_c: 0,
                    u32_d: 0,
                },
            },
            ..Default::default()
        }
    }

    /// Create a spatial position update
    pub fn spatial_position(timestamp: u64, object_id: u32, x: f64, y: f64, z: f64) -> Self {
        Self {
            channel: HxChannel::Spatial,
            sub_channel: SpatialSubChannel::PositionUpdate as u16,
            timestamp_samples: timestamp,
            priority: 128,
            payload: HxPayloadData {
                f64x4: [x, y, z, 0.0],
            },
            source_id: object_id,
            ..Default::default()
        }
    }

    /// Read payload as mixed (convenience accessor).
    ///
    /// **Sprint 15 Faza 4.F.4:** signature changed from `&HxMixedPayload`
    /// to `HxMixedPayload` (by value) — `HxMixedPayload: Copy` so the
    /// caller never paid for the reference anyway, and removing the
    /// borrow lets us forward to the safe POD-cast accessor on
    /// [`HxPayloadData`] without surfacing `unsafe` on call sites.
    #[inline]
    pub fn mixed(&self) -> HxMixedPayload {
        self.payload.as_mixed()
    }

    /// Read payload as `[f64; 4]`.
    #[inline]
    pub fn f64x4(&self) -> [f64; 4] {
        self.payload.as_f64x4()
    }

    /// Read payload as `[f32; 8]`.
    #[inline]
    pub fn f32x8(&self) -> [f32; 8] {
        self.payload.as_f32x8()
    }

    /// Read payload as `[u32; 8]`.
    #[inline]
    pub fn u32x8(&self) -> [u32; 8] {
        self.payload.as_u32x8()
    }

    /// Read payload as `[i64; 4]`.
    ///
    /// New in Sprint 15 Faza 4.F.4 — pairs with the existing `i64x4`
    /// union variant which previously had no convenience accessor.
    #[inline]
    pub fn i64x4(&self) -> [i64; 4] {
        self.payload.as_i64x4()
    }

    /// Read payload as `[u8; 32]` (raw bytes).
    ///
    /// New in Sprint 15 Faza 4.F.4 — useful for serialization paths.
    #[inline]
    pub fn bytes(&self) -> [u8; 32] {
        self.payload.as_bytes()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_size() {
        assert_eq!(std::mem::size_of::<HxMessage>(), 64);
    }

    #[test]
    fn test_ring_buffer_basic() {
        let ring = HxRingBuffer::new(64);
        assert!(ring.is_empty());

        let msg = HxMessage::default();
        assert!(ring.push(msg));
        assert_eq!(ring.len(), 1);

        let popped = ring.pop().unwrap();
        assert_eq!(popped.channel as u8, HxChannel::System as u8);
        assert!(ring.is_empty());
    }

    #[test]
    fn test_ring_buffer_overflow() {
        // min capacity is 64 (clamped in constructor)
        let ring = HxRingBuffer::new(64);
        for i in 0..64 {
            let mut msg = HxMessage::default();
            msg.sequence = i;
            assert!(ring.push(msg));
        }
        // Buffer full — next push should fail
        let msg = HxMessage::default();
        assert!(!ring.push(msg));
        assert_eq!(ring.overflow_count(), 1);
    }

    #[test]
    fn test_ring_buffer_drain() {
        let ring = HxRingBuffer::new(64);
        for i in 0..10 {
            let mut msg = HxMessage::default();
            msg.sequence = i;
            ring.push(msg);
        }

        let mut received = Vec::new();
        let count = ring.drain(|m| received.push(m.sequence));
        assert_eq!(count, 10);
        assert_eq!(received, (0..10).collect::<Vec<_>>());
        assert!(ring.is_empty());
    }

    #[test]
    fn test_filter_channel() {
        let filter = HxFilter::channel(HxChannel::Stage);
        let mut msg = HxMessage::default();

        msg.channel = HxChannel::Stage;
        assert!(filter.matches(&msg));

        msg.channel = HxChannel::Math;
        assert!(!filter.matches(&msg));
    }

    #[test]
    fn test_filter_multi_channel() {
        let filter = HxFilter::channels(&[HxChannel::Stage, HxChannel::Voice, HxChannel::Compliance]);
        let mut msg = HxMessage::default();

        msg.channel = HxChannel::Stage;
        assert!(filter.matches(&msg));

        msg.channel = HxChannel::Voice;
        assert!(filter.matches(&msg));

        msg.channel = HxChannel::Compliance;
        assert!(filter.matches(&msg));

        msg.channel = HxChannel::Math;
        assert!(!filter.matches(&msg));

        msg.channel = HxChannel::Audio;
        assert!(!filter.matches(&msg));
    }

    #[test]
    fn test_filter_exact() {
        let filter = HxFilter::Exact(HxChannel::Stage, StageSubChannel::ReelStop as u16);
        let mut msg = HxMessage::default();

        msg.channel = HxChannel::Stage;
        msg.sub_channel = StageSubChannel::ReelStop as u16;
        assert!(filter.matches(&msg));

        msg.sub_channel = StageSubChannel::WinPresent as u16;
        assert!(!filter.matches(&msg));

        msg.channel = HxChannel::Math;
        msg.sub_channel = StageSubChannel::ReelStop as u16;
        assert!(!filter.matches(&msg));
    }

    #[test]
    fn test_filter_all() {
        let filter = HxFilter::All;
        let mut msg = HxMessage::default();
        for ch in 0..HxChannel::COUNT {
            msg.channel = HxChannel::from_u8(ch as u8).unwrap();
            assert!(filter.matches(&msg));
        }
    }

    #[test]
    fn test_staging_area_basic() {
        let staging = HxStagingArea::new(256);
        let msg = HxMessage::default();
        assert!(staging.publish(msg));

        let mut drained = Vec::new();
        staging.drain_into(&mut drained);
        assert_eq!(drained.len(), 1);

        // After drain, staging should be empty
        let mut drained2 = Vec::new();
        staging.drain_into(&mut drained2);
        assert_eq!(drained2.len(), 0);
    }

    #[test]
    fn test_bus_end_to_end() {
        let mut bus = HxBus::new(HxBusConfig::default());

        // Subscribe: AUREXIS wants stage + math + emotion
        let aurexis_sub = bus.subscribe(
            "aurexis",
            HxFilter::channels(&[HxChannel::Stage, HxChannel::Math, HxChannel::Emotion]),
        );

        // Subscribe: compliance wants stage + compliance
        let compliance_sub = bus.subscribe(
            "compliance",
            HxFilter::channels(&[HxChannel::Stage, HxChannel::Compliance]),
        );

        // Publish some messages
        let pub_handle = bus.publisher();

        pub_handle.stage(
            StageSubChannel::ReelStop,
            48000, // 1 second at 48kHz
            0.0,   // no win
            1.0,   // bet = 1.0
            2,     // reel index 2
            0,     // no tier
        );

        pub_handle.math(
            MathSubChannel::RtpUpdate,
            48000,
            96.18,
        );

        pub_handle.compliance(
            ComplianceSubChannel::LdwDetected,
            48000,
            0.5, // win ratio
            0,   // UKGC
        );

        // Route messages
        bus.drain_and_route();

        // AUREXIS should get stage + math (not compliance)
        let mut aurexis_msgs = Vec::new();
        aurexis_sub.ring.drain(|m| aurexis_msgs.push(m.channel));
        assert_eq!(aurexis_msgs.len(), 2);
        assert!(aurexis_msgs.contains(&HxChannel::Stage));
        assert!(aurexis_msgs.contains(&HxChannel::Math));

        // Compliance should get stage + compliance (not math)
        let mut comp_msgs = Vec::new();
        compliance_sub.ring.drain(|m| comp_msgs.push(m.channel));
        assert_eq!(comp_msgs.len(), 2);
        assert!(comp_msgs.contains(&HxChannel::Stage));
        assert!(comp_msgs.contains(&HxChannel::Compliance));
    }

    #[test]
    fn test_bus_stats() {
        let mut bus = HxBus::new(HxBusConfig::default());
        let _sub = bus.subscribe("test", HxFilter::All);
        let pub_handle = bus.publisher();

        for _ in 0..100 {
            pub_handle.stage(StageSubChannel::SpinPress, 0, 0.0, 1.0, 0, 0);
        }

        bus.drain_and_route();

        let stats = bus.stats();
        assert_eq!(stats.total_published, 100);
        assert_eq!(stats.total_routed, 100);
        assert_eq!(stats.active_subscribers, 1);
        assert_eq!(stats.channel_counts[HxChannel::Stage as usize], 100);
    }

    #[test]
    fn test_message_builders() {
        let msg = HxMessage::stage_event(
            StageSubChannel::BigWinTier,
            96000,
            500.0,
            2.0,
            0,
            3,
        );
        assert_eq!(msg.channel, HxChannel::Stage);
        assert_eq!(msg.sub_channel, StageSubChannel::BigWinTier as u16);
        assert_eq!(msg.timestamp_samples, 96000);
        assert_eq!(msg.mixed().f64_a, 500.0);
        assert_eq!(msg.mixed().f64_b, 2.0);
        assert_eq!(msg.mixed().u32_b, 3); // tier

        let ldw = HxMessage::ldw_detected(48000, 0.8, 1.0, 0);
        assert_eq!(ldw.channel, HxChannel::Compliance);
        assert_eq!(ldw.priority, 255); // Critical

        let spatial = HxMessage::spatial_position(0, 42, 1.5, 0.0, -3.0);
        assert_eq!(spatial.f64x4()[0], 1.5);
        assert_eq!(spatial.f64x4()[1], 0.0);
        assert_eq!(spatial.f64x4()[2], -3.0);
    }

    #[test]
    fn test_deterministic_ordering() {
        let mut bus = HxBus::new(HxBusConfig::default());
        let sub = bus.subscribe("order_test", HxFilter::All);
        let pub_handle = bus.publisher();

        // Publish in specific order
        for i in 0..50 {
            let mut msg = HxMessage::default();
            msg.channel = HxChannel::Stage;
            msg.sub_channel = i;
            pub_handle.publish(msg);
        }

        bus.drain_and_route();

        // Verify messages arrive in sequence order
        let mut sequences = Vec::new();
        sub.ring.drain(|m| sequences.push(m.sequence));
        assert_eq!(sequences.len(), 50);

        // Sequences should be monotonically increasing
        for i in 1..sequences.len() {
            assert!(sequences[i] > sequences[i - 1],
                "Sequence {} ({}) should be > {} ({})",
                i, sequences[i], i - 1, sequences[i - 1]);
        }
    }

    #[test]
    fn test_subscriber_deactivation() {
        let mut bus = HxBus::new(HxBusConfig::default());
        let sub = bus.subscribe("deactivate_test", HxFilter::All);
        let pub_handle = bus.publisher();

        // Deactivate subscriber
        sub.active.store(false, Ordering::Relaxed);

        pub_handle.stage(StageSubChannel::SpinPress, 0, 0.0, 1.0, 0, 0);
        bus.drain_and_route();

        // Should NOT receive the message
        assert!(sub.ring.is_empty());
    }

    #[test]
    fn test_multi_thread_publish() {
        let mut bus = HxBus::new(HxBusConfig::default());
        let sub = bus.subscribe("mt_test", HxFilter::All);

        // Publish from multiple threads
        let handles: Vec<_> = (0..4).map(|thread_id| {
            let pub_handle = bus.publisher();
            std::thread::spawn(move || {
                for i in 0..100 {
                    let mut msg = HxMessage::default();
                    msg.channel = HxChannel::Stage;
                    msg.source_id = thread_id;
                    msg.sub_channel = i as u16;
                    pub_handle.publish(msg);
                }
            })
        }).collect();

        for h in handles {
            h.join().unwrap();
        }

        bus.drain_and_route();

        // Should receive all 400 messages
        let mut count = 0;
        sub.ring.drain(|_| count += 1);
        assert_eq!(count, 400);
    }

    #[test]
    fn test_channel_from_u8() {
        for i in 0..HxChannel::COUNT {
            assert!(HxChannel::from_u8(i as u8).is_some());
        }
        assert!(HxChannel::from_u8(255).is_none());
    }

    #[test]
    fn test_drain_max() {
        let ring = HxRingBuffer::new(64);
        for i in 0..20 {
            let mut msg = HxMessage::default();
            msg.sequence = i;
            ring.push(msg);
        }

        let mut received = Vec::new();
        let count = ring.drain_max(5, |m| received.push(m.sequence));
        assert_eq!(count, 5);
        assert_eq!(ring.len(), 15); // 20 - 5 = 15 remaining
    }

    /// Regression for f_27290_91_92: HxPublisher must be Send+Sync without manual
    /// unsafe impls, and must safely outlive the bus (no raw pointers to dropped
    /// bus fields).
    #[test]
    fn regression_f_27290_publisher_arc_atomics() {
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}
        assert_send::<HxRingBuffer>();
        assert_send::<HxStagingArea>();
        assert_send::<HxPublisher>();
        assert_sync::<HxPublisher>();

        // Publisher should survive after bus is dropped (Arc keeps atomics alive)
        let pub_handle = {
            let bus = HxBus::new(HxBusConfig::default());
            bus.publisher()
        };
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::System;
        pub_handle.publish(msg);
    }

    // ── Sprint 14 Faza 4.F — publish_result + HxBusError ──────────────────

    #[test]
    fn publish_result_ok_on_uncontended_publish() {
        let bus = HxBus::new(HxBusConfig::default());
        let pubh = bus.publisher();
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::System;
        assert_eq!(pubh.publish_result(msg), Ok(()));
    }

    #[test]
    fn publish_result_returns_staging_full_error_when_saturated() {
        // `HxStagingArea::new` clamps capacity to 256-slot minimum.
        // To force saturation deterministically: set config to its
        // smallest value (clamped up to 256), then push 300 msgs
        // without draining — slot 257 onwards must error.
        let mut cfg = HxBusConfig::default();
        cfg.staging_capacity = 1; // gets clamped to 256 inside new()
        let bus = HxBus::new(cfg);
        let pubh = bus.publisher();
        let mut first_err: Option<HxBusError> = None;
        for _ in 0..300 {
            let mut msg = HxMessage::default();
            msg.channel = HxChannel::System;
            if let Err(e) = pubh.publish_result(msg) {
                first_err = Some(e);
                break;
            }
        }
        assert_eq!(first_err, Some(HxBusError::StagingFull),
            "saturated 256-slot staging area must surface StagingFull error");
    }

    #[test]
    fn publish_bool_wrapper_matches_publish_result() {
        // Legacy `publish() -> bool` is now a thin wrapper around
        // `publish_result()`.  Both must agree on outcome.
        let bus = HxBus::new(HxBusConfig::default());
        let pubh = bus.publisher();
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::System;
        let ok = pubh.publish(msg);
        let mut msg2 = HxMessage::default();
        msg2.channel = HxChannel::System;
        let res = pubh.publish_result(msg2);
        assert_eq!(ok, res.is_ok(),
            "publish() bool and publish_result().is_ok() must agree");
    }

    #[test]
    fn hx_bus_error_display_is_human_readable() {
        let err = HxBusError::StagingFull;
        let s = format!("{err}");
        assert!(s.contains("staging"),
            "Display impl should mention staging context");
    }

    #[test]
    fn hx_bus_error_implements_std_error_trait() {
        // Sanity: HxBusError can be boxed as a std::error::Error trait object,
        // which is what FFI/wrapper layers expect.
        let err: Box<dyn std::error::Error> = Box::new(HxBusError::StagingFull);
        assert!(err.to_string().contains("staging"));
    }

    // ── Sprint 15 Faza 4.F.3 — HxFilterBuilder ─────────────────────────────

    fn msg_on(ch: HxChannel, sub: u16) -> HxMessage {
        let mut m = HxMessage::default();
        m.channel = ch;
        m.sub_channel = sub;
        m
    }

    #[test]
    fn filter_builder_empty_matches_nothing() {
        // Vacuous builder must not silently behave like `All`.
        let f = HxFilter::builder().build();
        assert!(!f.matches(&msg_on(HxChannel::System, 0)));
        assert!(!f.matches(&msg_on(HxChannel::Stage, 7)));
        assert!(!f.matches(&msg_on(HxChannel::Math, 99)));
        // And the chosen variant should reflect zero match (Channels(0)).
        assert!(matches!(f, HxFilter::Channels(0)));
    }

    #[test]
    fn filter_builder_single_channel_collapses_to_channels_variant() {
        let f = HxFilter::builder().with_channel(HxChannel::Stage).build();
        match f {
            HxFilter::Channels(mask) => {
                assert_eq!(mask, 1 << (HxChannel::Stage as u16));
            }
            other => panic!("expected Channels variant, got {other:?}"),
        }
    }

    #[test]
    fn filter_builder_multiple_channels_or_into_bitmask() {
        let f = HxFilter::builder()
            .with_channel(HxChannel::Stage)
            .with_channel(HxChannel::Math)
            .with_channel(HxChannel::System)
            .build();
        assert!(f.matches(&msg_on(HxChannel::Stage, 0)));
        assert!(f.matches(&msg_on(HxChannel::Math, 0)));
        assert!(f.matches(&msg_on(HxChannel::System, 0)));
        // A channel we did NOT add must not match.
        assert!(!f.matches(&msg_on(HxChannel::Audio, 0)));
    }

    #[test]
    fn filter_builder_with_channels_slice_is_equivalent_to_chain() {
        let chained = HxFilter::builder()
            .with_channel(HxChannel::Stage)
            .with_channel(HxChannel::Audio)
            .build();
        let slice = HxFilter::builder()
            .with_channels(&[HxChannel::Stage, HxChannel::Audio])
            .build();
        match (chained, slice) {
            (HxFilter::Channels(a), HxFilter::Channels(b)) => assert_eq!(a, b),
            other => panic!("expected matching Channels variants, got {other:?}"),
        }
    }

    #[test]
    fn filter_builder_single_exact_collapses_to_exact_variant() {
        let f = HxFilter::builder().with_exact(HxChannel::Stage, 42).build();
        assert!(matches!(f, HxFilter::Exact(HxChannel::Stage, 42)));
        assert!(f.matches(&msg_on(HxChannel::Stage, 42)));
        assert!(!f.matches(&msg_on(HxChannel::Stage, 41)));
        assert!(!f.matches(&msg_on(HxChannel::Math, 42)));
    }

    #[test]
    fn filter_builder_multiple_exact_collapses_to_multi_variant() {
        let f = HxFilter::builder()
            .with_exact(HxChannel::Stage, 1)
            .with_exact(HxChannel::Math, 2)
            .build();
        assert!(matches!(f, HxFilter::Multi(_)));
        assert!(f.matches(&msg_on(HxChannel::Stage, 1)));
        assert!(f.matches(&msg_on(HxChannel::Math, 2)));
        assert!(!f.matches(&msg_on(HxChannel::Stage, 2)));
        assert!(!f.matches(&msg_on(HxChannel::Math, 1)));
    }

    #[test]
    fn filter_builder_hybrid_folds_exacts_into_mask() {
        // Mix channel + exact on a DIFFERENT channel → exact channel is
        // promoted into the bitmask (channel match is strictly broader).
        let f = HxFilter::builder()
            .with_channel(HxChannel::Stage)
            .with_exact(HxChannel::Math, 5)
            .build();
        assert!(matches!(f, HxFilter::Channels(_)));
        // Both channels now match wholesale.
        assert!(f.matches(&msg_on(HxChannel::Stage, 99)));
        assert!(f.matches(&msg_on(HxChannel::Math, 5)));
        assert!(f.matches(&msg_on(HxChannel::Math, 7))); // promoted!
        assert!(!f.matches(&msg_on(HxChannel::Audio, 0)));
    }

    #[test]
    fn filter_builder_exact_on_already_masked_channel_is_dropped() {
        // Adding `Exact(Stage, 5)` after `with_channel(Stage)` is redundant —
        // the channel match already covers sub 5, so build() must NOT fall
        // through to Multi.
        let f = HxFilter::builder()
            .with_channel(HxChannel::Stage)
            .with_exact(HxChannel::Stage, 5)
            .build();
        match f {
            HxFilter::Channels(mask) => {
                assert_eq!(mask, 1 << (HxChannel::Stage as u16));
            }
            other => panic!("expected Channels (Exact subsumed), got {other:?}"),
        }
    }

    // ── Sprint 15 Faza 4.F.2 — LockFreeSlotStore newtype ───────────────────

    /// Compile-time witness that the host structs now compose Sync via the
    /// newtype, without any `unsafe impl Sync` of their own.  If anyone
    /// re-adds raw `Box<[UnsafeCell<…>]>` to `HxRingBuffer` /
    /// `HxStagingArea` without going through the newtype, this test fails
    /// to compile.
    #[test]
    fn host_structs_are_send_and_sync_via_newtype() {
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}

        assert_send::<HxRingBuffer>();
        assert_sync::<HxRingBuffer>();
        assert_send::<HxStagingArea>();
        assert_sync::<HxStagingArea>();
        assert_send::<LockFreeSlotStore<HxMessage>>();
        assert_sync::<LockFreeSlotStore<HxMessage>>();
    }

    #[test]
    fn lock_free_slot_store_round_trip_via_unsafe_api() {
        // Direct round-trip on the newtype to prove the unsafe contract
        // is implementable (write_at then read_at returns the same value).
        let store: LockFreeSlotStore<HxMessage> =
            LockFreeSlotStore::new_with(8, HxMessage::default);
        assert_eq!(store.capacity(), 8);

        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Voice;
        msg.sub_channel = 42;

        // Safety: idx in range, no other thread, slot wasn't written
        // before — `write_at` overwrites without dropping which is fine
        // for the Copy `HxMessage::default()` initial value.
        unsafe { store.write_at(3, msg); }

        // Safety: idx in range, slot was just written, no concurrent
        // access, HxMessage: Copy so re-reading is harmless.
        let got = unsafe { store.read_at(3) };
        assert_eq!(got.channel, HxChannel::Voice);
        assert_eq!(got.sub_channel, 42);
    }

    #[test]
    fn lock_free_slot_store_capacity_matches_construction_argument() {
        let store: LockFreeSlotStore<HxMessage> =
            LockFreeSlotStore::new_with(64, HxMessage::default);
        assert_eq!(store.capacity(), 64);
    }

    #[test]
    fn ring_buffer_push_pop_round_trip_after_f2_refactor() {
        // Regression: HxRingBuffer still round-trips messages now that it
        // composes LockFreeSlotStore instead of carrying its own
        // `Box<[UnsafeCell<HxMessage>]>` field.
        let rb = HxRingBuffer::new(8);
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Stage;
        msg.sub_channel = 7;
        msg.sequence = 99;

        assert!(rb.push(msg));
        let got = rb.pop().expect("ring buffer must hand back the pushed msg");
        assert_eq!(got.channel, HxChannel::Stage);
        assert_eq!(got.sub_channel, 7);
        assert_eq!(got.sequence, 99);
        assert!(rb.pop().is_none(),
            "second pop on a 1-msg buffer must return None");
    }

    #[test]
    fn staging_area_publish_drain_round_trip_after_f2_refactor() {
        // Regression: HxStagingArea still round-trips messages through
        // its newtype-backed slots.
        let sa = HxStagingArea::new(256);
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::Math;
        msg.sub_channel = 11;
        msg.sequence = 1234;
        assert!(sa.publish(msg));

        let mut out: Vec<HxMessage> = Vec::with_capacity(8);
        sa.drain_into(&mut out);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].channel, HxChannel::Math);
        assert_eq!(out[0].sub_channel, 11);
        assert_eq!(out[0].sequence, 1234);
    }

    // ── Sprint 15 Faza 4.F.4 — POD-safe HxPayloadData accessors ──────────

    #[test]
    fn payload_data_from_mixed_round_trips_through_as_mixed() {
        let m = HxMixedPayload {
            f64_a: 123.456,
            f64_b: -42.0,
            u32_a: 7,
            u32_b: 8,
            u32_c: 9,
            u32_d: 10,
        };
        let payload = HxPayloadData::from_mixed(m);
        let got = payload.as_mixed();
        assert_eq!(got.f64_a, 123.456);
        assert_eq!(got.f64_b, -42.0);
        assert_eq!(got.u32_a, 7);
        assert_eq!(got.u32_b, 8);
        assert_eq!(got.u32_c, 9);
        assert_eq!(got.u32_d, 10);
    }

    #[test]
    fn payload_data_from_f64x4_round_trips() {
        let v = [1.0, 2.0, 3.0, 4.0];
        let p = HxPayloadData::from_f64x4(v);
        assert_eq!(p.as_f64x4(), v);
    }

    #[test]
    fn payload_data_from_f32x8_round_trips() {
        let v: [f32; 8] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];
        let p = HxPayloadData::from_f32x8(v);
        assert_eq!(p.as_f32x8(), v);
    }

    #[test]
    fn payload_data_from_i64x4_round_trips() {
        let v: [i64; 4] = [-1, -2, i64::MAX, i64::MIN];
        let p = HxPayloadData::from_i64x4(v);
        assert_eq!(p.as_i64x4(), v);
    }

    #[test]
    fn payload_data_from_u32x8_round_trips() {
        let v: [u32; 8] = [1, 2, 3, 4, 5, 6, 7, 8];
        let p = HxPayloadData::from_u32x8(v);
        assert_eq!(p.as_u32x8(), v);
    }

    #[test]
    fn payload_data_from_bytes_round_trips() {
        let v: [u8; 32] = core::array::from_fn(|i| i as u8);
        let p = HxPayloadData::from_bytes(v);
        assert_eq!(p.as_bytes(), v);
    }

    #[test]
    fn payload_data_cross_variant_read_is_bit_cast() {
        // POD bit-cast: write as f64x4, read as bytes — same 32 bytes,
        // different interpretation.  This is the FUNDAMENTAL safety
        // claim behind `HxPayloadData`: all variants are 32-byte POD
        // with no validity invariants, so any read is a well-defined
        // bit-cast.
        let p = HxPayloadData::from_f64x4([1.0f64, 2.0, 3.0, 4.0]);
        let bytes = p.as_bytes();
        // 4 × 8 bytes = 32 bytes of payload.
        assert_eq!(bytes.len(), 32);
        // First byte should be the low byte of f64::to_le_bytes(1.0)
        // (or to_be_bytes on a big-endian platform — we don't constrain
        // endianness here, just non-zero pattern is enough).
        let recovered = p.as_f64x4();
        assert_eq!(recovered[0], 1.0);
        assert_eq!(recovered[3], 4.0);
    }

    #[test]
    fn payload_size_invariant_still_32_bytes_after_f4_refactor() {
        // Regression guard: F.4 refactor must NOT have grown the union.
        // HxMessage layout (64 bytes total) depends on this.
        assert_eq!(std::mem::size_of::<HxPayloadData>(), 32);
        assert_eq!(std::mem::align_of::<HxPayloadData>(), 8); // 8B alignment for f64
    }

    #[test]
    fn hx_message_payload_accessors_match_payload_data_accessors() {
        // Sanity: HxMessage's convenience methods (`mixed()`, `f64x4()`,
        // etc.) must agree with directly calling the underlying
        // HxPayloadData accessors.
        let v = [1.5_f64, 2.5, 3.5, 4.5];
        let mut msg = HxMessage::default();
        msg.payload = HxPayloadData::from_f64x4(v);

        assert_eq!(msg.f64x4(), v);
        assert_eq!(msg.f64x4(), msg.payload.as_f64x4());

        // bytes() and i64x4() are new in F.4.
        assert_eq!(msg.bytes(), msg.payload.as_bytes());
        assert_eq!(msg.i64x4(), msg.payload.as_i64x4());
    }

    #[test]
    fn ring_buffer_overflow_unchanged_after_f2_refactor() {
        // Regression: SPSC overflow counter still increments correctly
        // when capacity is exceeded.
        let rb = HxRingBuffer::new(64);
        let mut msg = HxMessage::default();
        msg.channel = HxChannel::System;
        // Fill exactly to capacity → all succeed.
        for _ in 0..64 {
            assert!(rb.push(msg));
        }
        // 65th push must fail and increment overflow_count.
        assert!(!rb.push(msg));
        assert!(rb.overflow_count() >= 1,
            "post-refactor overflow counter must still tick on full buffer");
    }
}
