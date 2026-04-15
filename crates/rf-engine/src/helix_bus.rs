// ═══════════════════════════════════════════════════════════════════════════════
// HELIX BUS — Unified Lock-Free Reactive Message Bus
// ═══════════════════════════════════════════════════════════════════════════════
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
        // Safe: bytes is always valid
        write!(f, "HxPayloadData({} bytes)", unsafe { self.bytes.len() })
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

// ─────────────────────────────────────────────────────────────────────────────
// Ring Buffer — Lock-free SPSC per subscriber
// ─────────────────────────────────────────────────────────────────────────────

/// Fixed-size ring buffer for lock-free SPSC (single producer, single consumer).
/// One per subscriber. The router writes, the subscriber reads.
///
/// Overflow policy: oldest messages are silently dropped (bounded latency).
/// The `overflow_count` atomic tracks how many messages were lost.
pub struct HxRingBuffer {
    /// Pre-allocated message slots (UnsafeCell for interior mutability in SPSC pattern)
    buffer: Box<[UnsafeCell<HxMessage>]>,
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

// Safety: HxRingBuffer is SPSC — single producer (router) and single consumer (subscriber).
// The UnsafeCell slots are protected by atomic read_pos/write_pos fences.
unsafe impl Send for HxRingBuffer {}
unsafe impl Sync for HxRingBuffer {}

impl HxRingBuffer {
    /// Create a new ring buffer with the given capacity (rounded up to power of 2).
    pub fn new(min_capacity: usize) -> Self {
        let capacity = min_capacity.next_power_of_two().max(64);
        let buffer = (0..capacity)
            .map(|_| UnsafeCell::new(HxMessage::default()))
            .collect::<Vec<_>>()
            .into_boxed_slice();

        Self {
            buffer,
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

        // Write to slot (safe: we're the only writer, and consumer won't read
        // past read_pos which is behind write_pos)
        let idx = (wp as usize) & self.mask;
        // Safety: single producer guarantees no concurrent writes to this slot,
        // and consumer won't read past read_pos which is behind write_pos
        unsafe {
            std::ptr::write(self.buffer[idx].get(), msg);
        }

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

        let idx = (rp as usize) & self.mask;
        // Safety: single consumer guarantees no concurrent reads from this slot,
        // and producer won't overwrite (checked via wrapping_sub above)
        let msg = unsafe { std::ptr::read(self.buffer[idx].get()) };

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
pub struct HxStagingArea {
    buffer: Box<[UnsafeCell<HxMessage>]>,
    capacity: usize,
    /// Next write position (atomic CAS for multi-producer)
    write_cursor: AtomicU32,
    /// Number of committed writes (publishers increment after writing data)
    committed: AtomicU32,
    /// Read fence — router sets this after draining
    read_fence: AtomicU32,
}

// Safety: HxStagingArea is MPSC — multiple producers (atomic CAS for slot claiming)
// and single consumer (router thread drains). UnsafeCell slots are protected by
// write_cursor CAS + committed counter + read_fence.
unsafe impl Send for HxStagingArea {}
unsafe impl Sync for HxStagingArea {}

impl HxStagingArea {
    pub fn new(capacity: usize) -> Self {
        let capacity = capacity.next_power_of_two().max(256);
        let buffer = (0..capacity)
            .map(|_| UnsafeCell::new(HxMessage::default()))
            .collect::<Vec<_>>()
            .into_boxed_slice();

        Self {
            buffer,
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
                    // Slot claimed — write data
                    let idx = (cursor as usize) % self.capacity;
                    unsafe {
                        std::ptr::write(self.buffer[idx].get(), msg);
                    }
                    // Mark as committed
                    // Spin until our predecessor committed (maintains ordering)
                    while self.committed.load(Ordering::Acquire) != cursor {
                        std::hint::spin_loop();
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
    pub fn drain_into(&self, out: &mut Vec<HxMessage>) {
        let fence = self.read_fence.load(Ordering::Relaxed);
        let committed = self.committed.load(Ordering::Acquire);

        let count = committed.wrapping_sub(fence) as usize;
        if count == 0 {
            return;
        }

        out.reserve(count);
        for i in 0..count {
            let idx = ((fence as usize) + i) % self.capacity;
            let msg = unsafe { std::ptr::read(self.buffer[idx].get()) };
            out.push(msg);
        }

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
    sequence: AtomicU64,
    /// Configuration
    config: HxBusConfig,
    /// Total published count
    total_published: AtomicU64,
    /// Total routed count
    total_routed: AtomicU64,
    /// Staging overflow count
    staging_overflows: AtomicU64,
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
            sequence: AtomicU64::new(0),
            config,
            total_published: AtomicU64::new(0),
            total_routed: AtomicU64::new(0),
            staging_overflows: AtomicU64::new(0),
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
            sequence: &self.sequence as *const AtomicU64,
            total_published: &self.total_published as *const AtomicU64,
            staging_overflows: &self.staging_overflows as *const AtomicU64,
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

/// A publisher handle that can be cloned and sent to any thread.
/// Lightweight — contains only an Arc to shared staging and raw pointers
/// to bus-level atomics.
pub struct HxPublisher {
    staging: Arc<HxStagingArea>,
    // Raw pointers to bus-level atomics (bus outlives all publishers)
    sequence: *const AtomicU64,
    total_published: *const AtomicU64,
    staging_overflows: *const AtomicU64,
}

// Safety: HxPublisher only accesses atomics through raw pointers.
// The bus guarantees these pointers remain valid for the publisher's lifetime.
unsafe impl Send for HxPublisher {}
unsafe impl Sync for HxPublisher {}

impl HxPublisher {
    /// Publish a message to the bus.
    ///
    /// Thread-safe, lock-free. Can be called from UI thread, audio thread,
    /// worker threads, anywhere.
    ///
    /// Returns false if staging area is full (message dropped).
    pub fn publish(&self, mut msg: HxMessage) -> bool {
        // Assign monotonic sequence number
        let seq = unsafe { &*self.sequence }.fetch_add(1, Ordering::Relaxed);
        msg.sequence = seq as u32;

        let ok = self.staging.publish(msg);

        unsafe { &*self.total_published }.fetch_add(1, Ordering::Relaxed);

        if !ok {
            unsafe { &*self.staging_overflows }.fetch_add(1, Ordering::Relaxed);
        }

        ok
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

    /// Read payload as mixed (convenience accessor)
    pub fn mixed(&self) -> &HxMixedPayload {
        unsafe { &self.payload.mixed }
    }

    /// Read payload as f64x4
    pub fn f64x4(&self) -> &[f64; 4] {
        unsafe { &self.payload.f64x4 }
    }

    /// Read payload as f32x8
    pub fn f32x8(&self) -> &[f32; 8] {
        unsafe { &self.payload.f32x8 }
    }

    /// Read payload as u32x8
    pub fn u32x8(&self) -> &[u32; 8] {
        unsafe { &self.payload.u32x8 }
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
}
