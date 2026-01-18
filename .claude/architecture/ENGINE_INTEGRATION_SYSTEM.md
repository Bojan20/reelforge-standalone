# FluxForge Engine Integration System

## Dva Režima Rada

FluxForge podržava dva fundamentalno različita režima:

```
┌─────────────────────────────────────────────────────────────────┐
│  MODE 1: OFFLINE                    MODE 2: LIVE (Connected)   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐                    ┌─────────────┐            │
│  │ JSON Files  │                    │ Game Engine │            │
│  └──────┬──────┘                    └──────┬──────┘            │
│         │                                  │                    │
│         ▼                                  ▼                    │
│  ┌─────────────┐                    ┌─────────────┐            │
│  │   Adapter   │                    │  Connector  │            │
│  │   Wizard    │                    │  (WS/TCP)   │            │
│  └──────┬──────┘                    └──────┬──────┘            │
│         │                                  │                    │
│         ▼                                  ▼                    │
│  ┌─────────────────────────────────────────────────┐           │
│  │              STAGE INGEST LAYER                  │           │
│  │         (Normalizacija u STAGES)                │           │
│  └─────────────────────────────────────────────────┘           │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────┐           │
│  │              FLUXFORGE AUDIO ENGINE              │           │
│  └─────────────────────────────────────────────────┘           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. OFFLINE Mode — JSON Import

### Use Case
- Audio dizajn bez pristupa engine-u
- Kreiranje soundbank-a pre integracije
- Testing sa sample podacima

### Workflow

```
1. Klijent dostavi JSON sample-ove (spin results, feature triggers)
2. Adapter Wizard analizira strukturu
3. Mapiranje se potvrdi/dopuni
4. FluxForge generiše StageTrace iz JSON-a
5. Audio dizajner radi sa StageTrace-om
6. Export soundbank + adapter config
7. Integracija u game engine
```

### Komponente

```rust
pub struct OfflineIngestService {
    adapter_registry: AdapterRegistry,
    timing_resolver: TimingResolver,
}

impl OfflineIngestService {
    /// Import JSON file and convert to StageTrace
    pub fn import_json(&self, json: serde_json::Value, adapter_id: &str) -> Result<StageTrace> {
        let adapter = self.adapter_registry.get(adapter_id)?;
        let trace = adapter.parse_json(&json)?;
        Ok(trace)
    }

    /// Import multiple JSON files for batch analysis
    pub fn import_batch(&self, files: Vec<PathBuf>, adapter_id: &str) -> Result<Vec<StageTrace>> {
        files.iter()
            .map(|path| {
                let json = std::fs::read_to_string(path)?;
                let value: serde_json::Value = serde_json::from_str(&json)?;
                self.import_json(value, adapter_id)
            })
            .collect()
    }

    /// Generate timed trace for preview
    pub fn preview(&self, trace: &StageTrace, profile: TimingProfile) -> TimedStageTrace {
        self.timing_resolver.resolve(trace, profile)
    }
}
```

---

## 2. LIVE Mode — Engine Connected

### Use Case
- Real-time audio testing
- Live preview tačno kao u finalnoj igri
- Bidirekciona kontrola (FluxForge ↔ Engine)
- Debugging i fine-tuning

### Arhitektura

```
┌─────────────────────────────────────────────────────────────────┐
│                      GAME ENGINE                                │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  Event Emitter                    Command Receiver        │ │
│  │  ─────────────                    ────────────────        │ │
│  │  • spin_start                     • trigger_spin          │ │
│  │  • reel_stop                      • trigger_bigwin        │ │
│  │  • win_present                    • trigger_feature       │ │
│  │  • feature_enter                  • set_bet               │ │
│  │  • ...                            • skip_animation        │ │
│  └───────────────┬───────────────────────────┬───────────────┘ │
│                  │                           │                  │
│                  │ WebSocket / TCP           │                  │
│                  │                           │                  │
└──────────────────┼───────────────────────────┼──────────────────┘
                   │                           │
                   ▼                           ▲
┌──────────────────┴───────────────────────────┴──────────────────┐
│                      FLUXFORGE STUDIO                           │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   ENGINE CONNECTOR                        │ │
│  │  ─────────────────────────────────────────────────────── │ │
│  │  • Connection management (reconnect, heartbeat)          │ │
│  │  • Protocol handling (WS/TCP/Custom)                     │ │
│  │  • Event routing                                          │ │
│  │  • Command dispatching                                    │ │
│  └───────────────┬───────────────────────────┬───────────────┘ │
│                  │                           │                  │
│                  ▼                           ▲                  │
│  ┌───────────────────────────┐ ┌─────────────────────────────┐ │
│  │     STAGE NORMALIZER      │ │     COMMAND GENERATOR       │ │
│  │  ───────────────────────  │ │  ─────────────────────────  │ │
│  │  Engine events → STAGES   │ │  FluxForge actions → Cmds   │ │
│  └───────────────┬───────────┘ └─────────────────────────────┘ │
│                  │                                              │
│                  ▼                                              │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   AUDIO ENGINE                            │ │
│  │  • Triggers sounds in real-time                          │ │
│  │  • Ducking matrix active                                  │ │
│  │  • Music system responding                                │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Connection Protocols

```rust
#[derive(Debug, Clone)]
pub enum ConnectionProtocol {
    /// WebSocket (most common for web-based engines)
    WebSocket {
        url: String,
        auth_token: Option<String>,
    },

    /// TCP Socket (for native engines)
    Tcp {
        host: String,
        port: u16,
    },

    /// Named pipe (Windows native games)
    NamedPipe {
        pipe_name: String,
    },

    /// Shared memory (ultra-low latency)
    SharedMemory {
        shm_name: String,
    },

    /// Custom plugin SDK
    PluginSdk {
        dll_path: PathBuf,
        entry_point: String,
    },
}
```

### Engine Connector

```rust
pub struct EngineConnector {
    protocol: ConnectionProtocol,
    adapter: Arc<dyn EngineAdapter>,
    state: ConnectionState,

    // Event channels
    stage_tx: Producer<StageEvent>,
    command_rx: Consumer<EngineCommand>,

    // Metrics
    latency_ms: AtomicF64,
    events_received: AtomicU64,
    commands_sent: AtomicU64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Error,
}

impl EngineConnector {
    pub async fn connect(&mut self) -> Result<()> {
        self.state = ConnectionState::Connecting;

        match &self.protocol {
            ConnectionProtocol::WebSocket { url, auth_token } => {
                self.connect_websocket(url, auth_token.as_deref()).await?;
            }
            ConnectionProtocol::Tcp { host, port } => {
                self.connect_tcp(host, *port).await?;
            }
            _ => todo!("Other protocols"),
        }

        self.state = ConnectionState::Connected;
        self.start_event_loop().await;
        Ok(())
    }

    pub async fn disconnect(&mut self) {
        self.state = ConnectionState::Disconnected;
        // Cleanup...
    }

    /// Send command to engine
    pub fn send_command(&self, command: EngineCommand) -> Result<()> {
        if self.state != ConnectionState::Connected {
            return Err(ConnectorError::NotConnected);
        }
        // Serialize and send via protocol
        Ok(())
    }

    /// Event loop - receives events, normalizes to STAGES, sends to audio
    async fn start_event_loop(&mut self) {
        loop {
            match self.receive_raw_event().await {
                Ok(raw_event) => {
                    // Parse through adapter
                    if let Ok(Some(stage_event)) = self.adapter.parse_event(&raw_event) {
                        // Send to audio engine
                        let _ = self.stage_tx.push(stage_event);
                        self.events_received.fetch_add(1, Ordering::Relaxed);
                    }
                }
                Err(e) => {
                    // Handle disconnect/reconnect
                    self.handle_error(e).await;
                }
            }
        }
    }
}
```

### Engine Commands (FluxForge → Engine)

```rust
#[derive(Debug, Clone)]
pub enum EngineCommand {
    // ═══ PLAYBACK CONTROL ═══
    /// Trigger a spin
    TriggerSpin,

    /// Skip current animation
    SkipAnimation,

    /// Force spin result (for testing)
    ForceResult {
        reels: Vec<Vec<String>>,
        win_amount: f64,
    },

    // ═══ FEATURE CONTROL ═══
    /// Trigger specific feature
    TriggerFeature { feature_type: FeatureType },

    /// Trigger big win presentation
    TriggerBigWin { tier: BigWinTier, amount: f64 },

    /// Exit current feature
    ExitFeature,

    // ═══ GAME STATE ═══
    /// Set bet amount
    SetBet { amount: f64 },

    /// Set autoplay
    SetAutoplay { enabled: bool, spins: Option<u32> },

    /// Toggle turbo mode
    SetTurbo { enabled: bool },

    // ═══ DEBUG ═══
    /// Request current game state
    GetState,

    /// Request event history
    GetHistory { count: u32 },

    /// Pause event emission
    PauseEvents,

    /// Resume event emission
    ResumeEvents,

    // ═══ CUSTOM ═══
    /// Custom command (adapter-specific)
    Custom {
        command: String,
        payload: serde_json::Value,
    },
}
```

### Command Mapping Config

```toml
[commands]
# FluxForge command → Engine command format
TriggerSpin = { cmd: "SPIN", params: {} }
SkipAnimation = { cmd: "SKIP", params: {} }
TriggerBigWin = { cmd: "DEBUG_BIGWIN", params: { tier: "$tier", amount: "$amount" } }
TriggerFeature = { cmd: "DEBUG_FEATURE", params: { type: "$feature_type" } }
SetBet = { cmd: "SET_BET", params: { value: "$amount" } }
SetTurbo = { cmd: "SET_SPEED", params: { turbo: "$enabled" } }
GetState = { cmd: "GET_STATE", params: {} }

[command_format]
# How commands are serialized
type = "json"
wrapper = { action: "$cmd", data: "$params" }
```

---

## 3. Live Preview Panel

### UI Komponente

```
┌─────────────────────────────────────────────────────────────────┐
│  ENGINE CONNECTION                                    [IGT AVP] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Status: ● Connected (ws://localhost:8080)      Latency: 12ms  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  LIVE STAGE TRACE                              [Clear]  │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  00:00.000  ▶ SPIN_START                               │   │
│  │  00:00.812  ▶ REEL_STOP [0] symbol: WILD               │   │
│  │  00:00.965  ▶ REEL_STOP [1] symbol: CHERRY             │   │
│  │  00:01.118  ▶ REEL_STOP [2] symbol: CHERRY             │   │
│  │  00:01.271  ● ANTICIPATION_ON [3]          ← current   │   │
│  │  ...                                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  QUICK TRIGGERS                                         │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  [Spin] [Skip] [BigWin▾] [Feature▾] [Jackpot▾]         │   │
│  │                                                         │   │
│  │  Force Result:                                          │   │
│  │  [WILD] [WILD] [WILD] [WILD] [WILD]  Win: [____] [Go]  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  AUDIO MONITOR                                          │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  ▶ spin_start.wav                              [Stop]  │   │
│  │  ▶ reel_stop_0.wav                             [Stop]  │   │
│  │  ▶ anticipation_loop.wav (looping)             [Stop]  │   │
│  │  ♪ tension_music.wav (crossfading...)                   │   │
│  │                                                         │   │
│  │  Ducking: anticipation_duck (active)                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Flutter Widget

```dart
class EngineConnectionPanel extends StatefulWidget {
  const EngineConnectionPanel({super.key});

  @override
  State<EngineConnectionPanel> createState() => _EngineConnectionPanelState();
}

class _EngineConnectionPanelState extends State<EngineConnectionPanel> {
  @override
  Widget build(BuildContext context) {
    return Consumer<EngineConnectionProvider>(
      builder: (context, provider, _) {
        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Column(
            children: [
              // Connection header
              _buildConnectionHeader(provider),

              // Live stage trace
              Expanded(
                child: _buildStageTraceView(provider),
              ),

              // Quick triggers
              _buildQuickTriggers(provider),

              // Audio monitor
              _buildAudioMonitor(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectionHeader(EngineConnectionProvider provider) {
    final isConnected = provider.state == ConnectionState.connected;
    final statusColor = isConnected ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),

          // Status text
          Text(
            isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 12,
            ),
          ),

          if (isConnected) ...[
            const SizedBox(width: 8),
            Text(
              '(${provider.connectionUrl})',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ],

          const Spacer(),

          // Latency
          if (isConnected)
            Text(
              'Latency: ${provider.latencyMs.toStringAsFixed(0)}ms',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),

          const SizedBox(width: 12),

          // Connect/Disconnect button
          GestureDetector(
            onTap: () {
              if (isConnected) {
                provider.disconnect();
              } else {
                _showConnectionDialog(context, provider);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isConnected
                    ? Colors.red.withOpacity(0.2)
                    : FluxForgeTheme.accentBlue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isConnected ? Colors.red : FluxForgeTheme.accentBlue,
                ),
              ),
              child: Text(
                isConnected ? 'Disconnect' : 'Connect',
                style: TextStyle(
                  color: isConnected ? Colors.red : FluxForgeTheme.accentBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageTraceView(EngineConnectionProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: provider.stageTrace.length,
      itemBuilder: (context, index) {
        final event = provider.stageTrace[index];
        final isCurrent = index == provider.stageTrace.length - 1;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: isCurrent
                ? FluxForgeTheme.accentBlue.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              // Timestamp
              SizedBox(
                width: 70,
                child: Text(
                  _formatTimestamp(event.timestampMs),
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),

              // Stage icon
              Icon(
                isCurrent ? Icons.arrow_right : Icons.circle,
                size: isCurrent ? 16 : 6,
                color: _getStageColor(event.stage),
              ),

              const SizedBox(width: 8),

              // Stage name
              Expanded(
                child: Text(
                  _formatStageName(event),
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickTriggers(EngineConnectionProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Triggers',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildTriggerButton('Spin', Icons.play_arrow, () {
                provider.sendCommand(EngineCommand.triggerSpin());
              }),
              const SizedBox(width: 8),
              _buildTriggerButton('Skip', Icons.skip_next, () {
                provider.sendCommand(EngineCommand.skipAnimation());
              }),
              const SizedBox(width: 8),
              _buildTriggerDropdown('BigWin', Icons.star, [
                ('Win', BigWinTier.win),
                ('Big Win', BigWinTier.bigWin),
                ('Mega Win', BigWinTier.megaWin),
                ('Epic Win', BigWinTier.epicWin),
              ], (tier) {
                provider.sendCommand(
                  EngineCommand.triggerBigWin(tier: tier, amount: 1000),
                );
              }),
              const SizedBox(width: 8),
              _buildTriggerDropdown('Feature', Icons.auto_awesome, [
                ('Free Spins', FeatureType.freeSpins),
                ('Bonus', FeatureType.bonusGame),
                ('Pick', FeatureType.pickBonus),
                ('Wheel', FeatureType.wheelBonus),
              ], (feature) {
                provider.sendCommand(
                  EngineCommand.triggerFeature(featureType: feature),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}
```

---

## 4. Connection Profiles

### Saved Connections

```dart
class ConnectionProfile {
  final String id;
  final String name;
  final String companyName;
  final String adapterId;
  final ConnectionProtocol protocol;
  final Map<String, dynamic> settings;

  // Quick connect info
  final String? lastConnected;
  final bool favorite;
}

// Example profiles
final exampleProfiles = [
  ConnectionProfile(
    id: 'igt-dev-local',
    name: 'IGT Dev (Local)',
    companyName: 'IGT',
    adapterId: 'igt-avp',
    protocol: ConnectionProtocol.webSocket(
      url: 'ws://localhost:8080/events',
    ),
    settings: {
      'auth_required': false,
    },
  ),
  ConnectionProfile(
    id: 'aristocrat-staging',
    name: 'Aristocrat Staging',
    companyName: 'Aristocrat',
    adapterId: 'aristocrat-helix',
    protocol: ConnectionProtocol.tcp(
      host: 'staging.aristocrat.internal',
      port: 9090,
    ),
    settings: {
      'auth_required': true,
      'auth_token_env': 'ARISTOCRAT_TOKEN',
    },
  ),
];
```

---

## 5. Latency Optimization

### Za Live Mode critical path:

```rust
// Lock-free event pipeline
pub struct LiveEventPipeline {
    // Triple buffer for zero-copy event passing
    event_buffer: TripleBuffer<StageEvent>,

    // Pre-allocated event pool
    event_pool: ObjectPool<StageEvent>,

    // Direct audio trigger (bypass queue when possible)
    direct_trigger: AtomicBool,
}

impl LiveEventPipeline {
    pub fn on_raw_event(&self, raw: &[u8]) {
        // Fast path: pre-parsed common events
        if let Some(stage) = self.try_fast_parse(raw) {
            // Direct trigger without going through queue
            if self.direct_trigger.load(Ordering::Relaxed) {
                self.audio_engine.trigger_immediate(stage);
                return;
            }
        }

        // Slow path: full parsing
        let event = self.event_pool.get();
        self.adapter.parse_into(raw, &mut event);
        self.event_buffer.write(event);
    }

    /// Fast parse for common events (no allocation)
    fn try_fast_parse(&self, raw: &[u8]) -> Option<Stage> {
        // Check for known event signatures
        // This is adapter-specific but can be very fast
        match raw {
            b"SPIN_START" => Some(Stage::SpinStart),
            b"SPIN_END" => Some(Stage::SpinEnd),
            _ if raw.starts_with(b"REEL_STOP_") => {
                let idx = raw[10] - b'0';
                Some(Stage::ReelStop { reel_index: idx })
            }
            _ => None,
        }
    }
}
```

### Target Latency

| Component | Target | Notes |
|-----------|--------|-------|
| Network receive | < 5ms | WebSocket/TCP |
| Event parsing | < 1ms | Pre-allocated, no alloc |
| Stage normalization | < 0.5ms | Lookup table |
| Audio trigger | < 1ms | Lock-free queue |
| **Total** | **< 10ms** | End-to-end |

---

## 6. Error Handling & Reconnection

```rust
impl EngineConnector {
    async fn handle_error(&mut self, error: ConnectorError) {
        match error {
            ConnectorError::ConnectionLost => {
                self.state = ConnectionState::Reconnecting;
                self.attempt_reconnect().await;
            }
            ConnectorError::AuthFailed => {
                self.state = ConnectionState::Error;
                self.notify_ui("Authentication failed");
            }
            ConnectorError::ProtocolError(msg) => {
                log::warn!("Protocol error: {}", msg);
                // Continue if possible
            }
            ConnectorError::AdapterError(e) => {
                log::error!("Adapter error: {:?}", e);
                // Log but don't disconnect
            }
        }
    }

    async fn attempt_reconnect(&mut self) {
        let mut attempt = 0;
        let max_attempts = 10;
        let base_delay = Duration::from_millis(500);

        while attempt < max_attempts {
            attempt += 1;
            let delay = base_delay * 2u32.pow(attempt.min(5));

            log::info!("Reconnect attempt {} in {:?}", attempt, delay);
            tokio::time::sleep(delay).await;

            match self.connect().await {
                Ok(_) => {
                    log::info!("Reconnected successfully");
                    return;
                }
                Err(e) => {
                    log::warn!("Reconnect failed: {:?}", e);
                }
            }
        }

        self.state = ConnectionState::Error;
        self.notify_ui("Failed to reconnect after {} attempts", max_attempts);
    }
}
```

---

## 7. Security Considerations

```rust
pub struct ConnectionSecurity {
    /// Allowed hosts (whitelist)
    allowed_hosts: HashSet<String>,

    /// TLS required
    require_tls: bool,

    /// Auth token validation
    auth_validator: Option<Box<dyn AuthValidator>>,

    /// Rate limiting
    rate_limiter: RateLimiter,
}

impl ConnectionSecurity {
    pub fn validate_connection(&self, url: &str) -> Result<()> {
        let parsed = url::Url::parse(url)?;

        // Check host whitelist
        if !self.allowed_hosts.is_empty() {
            let host = parsed.host_str().ok_or(SecurityError::InvalidHost)?;
            if !self.allowed_hosts.contains(host) {
                return Err(SecurityError::HostNotAllowed(host.to_string()));
            }
        }

        // Check TLS
        if self.require_tls && parsed.scheme() != "wss" && parsed.scheme() != "https" {
            return Err(SecurityError::TlsRequired);
        }

        Ok(())
    }
}
```

---

## Sledeći koraci

1. **rf-connector** crate — Connection protocols, EngineConnector
2. **Provider** — EngineConnectionProvider za Flutter
3. **UI** — Connection panel, live trace view, quick triggers
4. **Integration** — Connect rf-ingest sa rf-connector
5. **Testing** — Mock engine za lokalno testiranje
