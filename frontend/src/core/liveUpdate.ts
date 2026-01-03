/**
 * Live Update Service
 *
 * Real-time connection between editor and runtime:
 * - WebSocket-based communication
 * - Push event changes
 * - Push mix changes
 * - Push asset updates
 * - Receive runtime metrics
 * - Voice activity monitoring
 */

// ============ TYPES ============

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'error';

export interface LiveUpdateConfig {
  /** Enable live update */
  enabled: boolean;
  /** WebSocket port */
  port: number;
  /** Auto-connect on startup */
  autoConnect: boolean;
  /** Reconnect on disconnect */
  autoReconnect: boolean;
  /** Reconnect delay (ms) */
  reconnectDelay: number;
  /** Heartbeat interval (ms) */
  heartbeatInterval: number;
  /** Max reconnect attempts */
  maxReconnectAttempts: number;
}

export interface EventDelta {
  /** Event ID */
  eventId: string;
  /** Change type */
  changeType: 'add' | 'modify' | 'remove';
  /** Changed properties */
  properties?: Record<string, unknown>;
  /** Timestamp */
  timestamp: number;
}

export interface MixSnapshotDelta {
  /** Snapshot ID */
  snapshotId: string;
  /** Bus changes */
  busChanges?: Record<string, {
    volume?: number;
    muted?: boolean;
    soloed?: boolean;
  }>;
  /** RTPC changes */
  rtpcChanges?: Record<string, number>;
  /** Timestamp */
  timestamp: number;
}

export interface AssetUpdateMessage {
  /** Asset ID */
  assetId: string;
  /** Asset URL or base64 data */
  data: string;
  /** Is base64 encoded */
  isBase64: boolean;
  /** Timestamp */
  timestamp: number;
}

export interface RuntimeMetrics {
  /** CPU usage (0-100) */
  cpuUsage: number;
  /** Memory usage (bytes) */
  memoryUsage: number;
  /** Active voices */
  activeVoices: number;
  /** Streaming buffers */
  streamingBuffers: number;
  /** Audio context state */
  contextState: AudioContextState;
  /** Sample rate */
  sampleRate: number;
  /** Current latency (ms) */
  latency: number;
  /** Timestamp */
  timestamp: number;
}

export interface VoiceSnapshot {
  /** Voice ID */
  voiceId: string;
  /** Asset ID */
  assetId: string;
  /** Bus */
  bus: string;
  /** Volume */
  volume: number;
  /** Is playing */
  isPlaying: boolean;
  /** Playback position */
  position: number;
  /** Duration */
  duration: number;
  /** Is looping */
  isLooping: boolean;
}

export interface LiveMessage {
  /** Message type */
  type: 'event' | 'mix' | 'asset' | 'metrics' | 'voices' | 'command' | 'heartbeat' | 'ack';
  /** Payload */
  payload: unknown;
  /** Message ID */
  messageId: string;
  /** Timestamp */
  timestamp: number;
}

// ============ DEFAULT CONFIG ============

const DEFAULT_CONFIG: LiveUpdateConfig = {
  enabled: true,
  port: 9876,
  autoConnect: false,
  autoReconnect: true,
  reconnectDelay: 3000,
  heartbeatInterval: 5000,
  maxReconnectAttempts: 10,
};

// ============ LIVE UPDATE SERVICE ============

export class LiveUpdateService {
  private config: LiveUpdateConfig;
  private socket: WebSocket | null = null;
  private status: ConnectionStatus = 'disconnected';
  private reconnectAttempts: number = 0;
  private heartbeatInterval: number | null = null;
  private messageQueue: LiveMessage[] = [];
  private pendingAcks: Map<string, (success: boolean) => void> = new Map();

  // Callbacks
  private onStatusChange?: (status: ConnectionStatus) => void;
  private onRuntimeMetrics?: (metrics: RuntimeMetrics) => void;
  private onVoiceActivity?: (voices: VoiceSnapshot[]) => void;
  private onError?: (error: Error) => void;
  private onMessage?: (message: LiveMessage) => void;

  constructor(
    config: Partial<LiveUpdateConfig> = {},
    callbacks?: {
      onStatusChange?: (status: ConnectionStatus) => void;
      onRuntimeMetrics?: (metrics: RuntimeMetrics) => void;
      onVoiceActivity?: (voices: VoiceSnapshot[]) => void;
      onError?: (error: Error) => void;
      onMessage?: (message: LiveMessage) => void;
    }
  ) {
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.onStatusChange = callbacks?.onStatusChange;
    this.onRuntimeMetrics = callbacks?.onRuntimeMetrics;
    this.onVoiceActivity = callbacks?.onVoiceActivity;
    this.onError = callbacks?.onError;
    this.onMessage = callbacks?.onMessage;

    if (this.config.autoConnect) {
      this.connect('localhost', this.config.port);
    }
  }

  // ============ CONNECTION ============

  /**
   * Connect to runtime
   */
  async connect(host: string, port: number): Promise<void> {
    if (this.socket?.readyState === WebSocket.OPEN) {
      return; // Already connected
    }

    this.setStatus('connecting');

    return new Promise((resolve, reject) => {
      try {
        const url = `ws://${host}:${port}`;
        this.socket = new WebSocket(url);

        this.socket.onopen = () => {
          this.setStatus('connected');
          this.reconnectAttempts = 0;
          this.startHeartbeat();
          this.flushMessageQueue();
          resolve();
        };

        this.socket.onclose = () => {
          this.handleDisconnect();
        };

        this.socket.onerror = () => {
          const error = new Error('WebSocket error');
          this.onError?.(error);
          if (this.status === 'connecting') {
            reject(error);
          }
        };

        this.socket.onmessage = (event) => {
          this.handleMessage(event.data);
        };

      } catch (error) {
        this.setStatus('error');
        reject(error);
      }
    });
  }

  /**
   * Disconnect from runtime
   */
  disconnect(): void {
    this.stopHeartbeat();

    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }

    this.setStatus('disconnected');
    this.reconnectAttempts = 0;
  }

  /**
   * Handle disconnect
   */
  private handleDisconnect(): void {
    this.stopHeartbeat();
    this.socket = null;

    if (this.config.autoReconnect &&
        this.reconnectAttempts < this.config.maxReconnectAttempts) {
      this.setStatus('connecting');
      this.reconnectAttempts++;

      setTimeout(() => {
        this.connect('localhost', this.config.port).catch(() => {
          // Reconnect failed, will try again
        });
      }, this.config.reconnectDelay);
    } else {
      this.setStatus('disconnected');
    }
  }

  /**
   * Set connection status
   */
  private setStatus(status: ConnectionStatus): void {
    this.status = status;
    this.onStatusChange?.(status);
  }

  /**
   * Get current status
   */
  getStatus(): ConnectionStatus {
    return this.status;
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    return this.status === 'connected' && this.socket?.readyState === WebSocket.OPEN;
  }

  // ============ HEARTBEAT ============

  /**
   * Start heartbeat
   */
  private startHeartbeat(): void {
    this.stopHeartbeat();

    this.heartbeatInterval = window.setInterval(() => {
      this.sendMessage({
        type: 'heartbeat',
        payload: { timestamp: Date.now() },
        messageId: this.generateId(),
        timestamp: Date.now(),
      });
    }, this.config.heartbeatInterval);
  }

  /**
   * Stop heartbeat
   */
  private stopHeartbeat(): void {
    if (this.heartbeatInterval !== null) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }

  // ============ MESSAGE HANDLING ============

  /**
   * Send message
   */
  private sendMessage(message: LiveMessage): boolean {
    if (!this.isConnected()) {
      this.messageQueue.push(message);
      return false;
    }

    try {
      this.socket!.send(JSON.stringify(message));
      return true;
    } catch (error) {
      this.onError?.(error as Error);
      return false;
    }
  }

  /**
   * Send message and wait for acknowledgment
   */
  private async sendMessageWithAck(message: LiveMessage, timeoutMs: number = 5000): Promise<boolean> {
    return new Promise((resolve) => {
      this.pendingAcks.set(message.messageId, resolve);

      const sent = this.sendMessage(message);
      if (!sent) {
        this.pendingAcks.delete(message.messageId);
        resolve(false);
        return;
      }

      // Timeout
      setTimeout(() => {
        if (this.pendingAcks.has(message.messageId)) {
          this.pendingAcks.delete(message.messageId);
          resolve(false);
        }
      }, timeoutMs);
    });
  }

  /**
   * Handle incoming message
   */
  private handleMessage(data: string): void {
    try {
      const message = JSON.parse(data) as LiveMessage;
      this.onMessage?.(message);

      switch (message.type) {
        case 'metrics':
          this.onRuntimeMetrics?.(message.payload as RuntimeMetrics);
          break;

        case 'voices':
          this.onVoiceActivity?.(message.payload as VoiceSnapshot[]);
          break;

        case 'ack':
          const ackPayload = message.payload as { messageId: string; success: boolean };
          const callback = this.pendingAcks.get(ackPayload.messageId);
          if (callback) {
            this.pendingAcks.delete(ackPayload.messageId);
            callback(ackPayload.success);
          }
          break;

        case 'heartbeat':
          // Respond to runtime heartbeat
          this.sendMessage({
            type: 'ack',
            payload: { messageId: message.messageId, success: true },
            messageId: this.generateId(),
            timestamp: Date.now(),
          });
          break;
      }
    } catch (error) {
      this.onError?.(error as Error);
    }
  }

  /**
   * Flush queued messages
   */
  private flushMessageQueue(): void {
    while (this.messageQueue.length > 0 && this.isConnected()) {
      const message = this.messageQueue.shift();
      if (message) {
        this.sendMessage(message);
      }
    }
  }

  // ============ PUSH TO RUNTIME ============

  /**
   * Push event changes to runtime
   */
  async pushEventChanges(changes: EventDelta[]): Promise<boolean> {
    const message: LiveMessage = {
      type: 'event',
      payload: changes,
      messageId: this.generateId(),
      timestamp: Date.now(),
    };

    return this.sendMessageWithAck(message);
  }

  /**
   * Push mix changes to runtime
   */
  async pushMixChanges(snapshot: MixSnapshotDelta): Promise<boolean> {
    const message: LiveMessage = {
      type: 'mix',
      payload: snapshot,
      messageId: this.generateId(),
      timestamp: Date.now(),
    };

    return this.sendMessageWithAck(message);
  }

  /**
   * Push asset update to runtime
   */
  async pushAssetUpdate(assetId: string, data: ArrayBuffer | string): Promise<boolean> {
    const isBase64 = typeof data === 'string';
    const payload: AssetUpdateMessage = {
      assetId,
      data: isBase64 ? data : this.arrayBufferToBase64(data),
      isBase64: true,
      timestamp: Date.now(),
    };

    const message: LiveMessage = {
      type: 'asset',
      payload,
      messageId: this.generateId(),
      timestamp: Date.now(),
    };

    return this.sendMessageWithAck(message);
  }

  /**
   * Send command to runtime
   */
  async sendCommand(command: string, params?: Record<string, unknown>): Promise<boolean> {
    const message: LiveMessage = {
      type: 'command',
      payload: { command, params },
      messageId: this.generateId(),
      timestamp: Date.now(),
    };

    return this.sendMessageWithAck(message);
  }

  // ============ REQUESTS TO RUNTIME ============

  /**
   * Request runtime metrics
   */
  requestMetrics(): void {
    this.sendCommand('getMetrics');
  }

  /**
   * Request voice activity snapshot
   */
  requestVoiceActivity(): void {
    this.sendCommand('getVoices');
  }

  /**
   * Request runtime to play an event
   */
  async playEvent(eventId: string): Promise<boolean> {
    return this.sendCommand('play', { eventId });
  }

  /**
   * Request runtime to stop an event
   */
  async stopEvent(eventId: string, fadeMs?: number): Promise<boolean> {
    return this.sendCommand('stop', { eventId, fadeMs });
  }

  /**
   * Request runtime to set RTPC
   */
  async setRTPC(name: string, value: number): Promise<boolean> {
    return this.sendCommand('setRTPC', { name, value });
  }

  /**
   * Request runtime to set switch
   */
  async setSwitch(groupId: string, value: string): Promise<boolean> {
    return this.sendCommand('setSwitch', { groupId, value });
  }

  // ============ UTILITIES ============

  /**
   * Generate unique ID
   */
  private generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Convert ArrayBuffer to base64
   */
  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  // ============ CONFIGURATION ============

  /**
   * Update configuration
   */
  setConfig(config: Partial<LiveUpdateConfig>): void {
    this.config = { ...this.config, ...config };
  }

  /**
   * Get current configuration
   */
  getConfig(): LiveUpdateConfig {
    return { ...this.config };
  }

  // ============ DISPOSAL ============

  /**
   * Dispose service
   */
  dispose(): void {
    this.disconnect();
    this.messageQueue = [];
    this.pendingAcks.clear();
  }
}

// ============ LIVE UPDATE SERVER (for runtime) ============

/**
 * Server-side component for runtime integration
 * This would run in the game/runtime environment
 */
export class LiveUpdateServer {
  private port: number;
  private connections: Set<WebSocket> = new Set();

  // For browser-based runtime, we use a different approach
  // This is a placeholder for the API design
  constructor(port: number = 9876) {
    this.port = port;
  }

  /**
   * Start server (Node.js only)
   */
  start(): void {
    // Would use ws package in Node.js
    console.log(`Live Update Server would start on port ${this.port}`);
  }

  /**
   * Broadcast metrics to all connections
   */
  broadcastMetrics(metrics: RuntimeMetrics): void {
    const message: LiveMessage = {
      type: 'metrics',
      payload: metrics,
      messageId: `server_${Date.now()}`,
      timestamp: Date.now(),
    };

    this.broadcast(message);
  }

  /**
   * Broadcast voice activity to all connections
   */
  broadcastVoices(voices: VoiceSnapshot[]): void {
    const message: LiveMessage = {
      type: 'voices',
      payload: voices,
      messageId: `server_${Date.now()}`,
      timestamp: Date.now(),
    };

    this.broadcast(message);
  }

  /**
   * Broadcast message to all connections
   */
  private broadcast(message: LiveMessage): void {
    const data = JSON.stringify(message);
    this.connections.forEach(conn => {
      if (conn.readyState === WebSocket.OPEN) {
        conn.send(data);
      }
    });
  }

  /**
   * Stop server
   */
  stop(): void {
    this.connections.forEach(conn => conn.close());
    this.connections.clear();
  }
}

// ============ PRESETS ============

export const LIVE_UPDATE_PRESETS: Record<string, Partial<LiveUpdateConfig>> = {
  development: {
    enabled: true,
    autoConnect: true,
    autoReconnect: true,
    heartbeatInterval: 1000,
  },
  production: {
    enabled: false,
    autoConnect: false,
    autoReconnect: false,
  },
  debug: {
    enabled: true,
    autoConnect: true,
    autoReconnect: true,
    heartbeatInterval: 500,
  },
};
