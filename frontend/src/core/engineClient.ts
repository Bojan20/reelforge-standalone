export type EngineStatus = 'disconnected' | 'connecting' | 'connected' | 'error';

export type OutgoingMessage =
  | { type: 'TriggerEvent'; eventName: string }
  | { type: 'SetParameter'; name: string; value: number }
  | { type: 'Ping'; source: 'ReelForge' }
  // Stress test commands (dev-only)
  | { type: 'StressTest'; mode: 'duplicate' | 'flood' | 'outOfOrder' | 'rapidFire'; count?: number; eventName?: string };

export type IncomingMessage =
  | { type: 'GameEventFired'; eventName: string; seq?: number; engineTimeMs?: number }
  | { type: 'ParameterChanged'; name: string; value: number }
  | { type: 'Log'; level: 'info' | 'warn' | 'error'; message: string };

/** Raw message data for logging - typed as union of known message types */
export type EngineLogRaw = IncomingMessage | OutgoingMessage | Record<string, unknown>;

export interface EngineLogEntry {
  id: string;
  direction: 'in' | 'out' | 'system';
  timestamp: number;
  message: string;
  raw?: EngineLogRaw;
}

type MessageHandler = (msg: IncomingMessage) => void;
type StatusHandler = (status: EngineStatus) => void;
type LogHandler = (entry: EngineLogEntry) => void;

export class EngineClient {
  private ws: WebSocket | null = null;
  private status: EngineStatus = 'disconnected';
  private onMessage?: MessageHandler;
  private onStatus?: StatusHandler;
  private onLog?: LogHandler;
  private reconnectTimer: number | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 999;
  private lastUrl: string | null = null;
  private shouldReconnect = false;
  private isManualDisconnect = false;

  constructor(
    onMessage?: MessageHandler,
    onStatus?: StatusHandler,
    onLog?: LogHandler
  ) {
    this.onMessage = onMessage;
    this.onStatus = onStatus;
    this.onLog = onLog;
  }

  connect(url: string) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.log('system', 'Already connected');
      return;
    }

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    this.lastUrl = url;
    this.shouldReconnect = true;
    this.isManualDisconnect = false;
    this.setStatus('connecting');

    try {
      this.ws = new WebSocket(url);

      this.ws.onopen = () => {
        this.reconnectAttempts = 0;
        this.setStatus('connected');
        this.log('system', '✅ Connected to engine: ' + url);
        this.send({ type: 'Ping', source: 'ReelForge' });
      };

      this.ws.onclose = () => {
        const wasConnected = this.status === 'connected';
        this.ws = null;

        if (this.isManualDisconnect) {
          this.setStatus('disconnected');
          this.log('system', 'Disconnected from engine');
          return;
        }

        if (wasConnected) {
          this.log('system', '⚠️ Connection lost. Reconnecting...');
        }

        if (this.shouldReconnect && this.reconnectAttempts < this.maxReconnectAttempts) {
          const delay = Math.min(1000 + (this.reconnectAttempts * 500), 5000);
          this.reconnectAttempts++;

          if (this.reconnectAttempts === 1) {
            this.log('system', `🔄 Reconnecting...`);
          } else if (this.reconnectAttempts % 5 === 0) {
            this.log('system', `🔄 Still trying to reconnect... (attempt ${this.reconnectAttempts})`);
          }

          this.setStatus('connecting');

          this.reconnectTimer = window.setTimeout(() => {
            if (this.shouldReconnect && this.lastUrl) {
              this.connect(this.lastUrl);
            }
          }, delay);
        } else if (this.reconnectAttempts >= this.maxReconnectAttempts) {
          this.log('system', '❌ Max reconnection attempts reached. Please reconnect manually.');
          this.setStatus('error');
        }
      };

      this.ws.onerror = () => {
        if (this.reconnectAttempts === 0) {
          this.log('system', '❌ WebSocket error - check if server is running');
        }
      };

      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data) as IncomingMessage;
          this.log('in', `← ${data.type}`, data);
          this.onMessage?.(data);
        } catch (e) {
          this.log('system', 'Failed to parse incoming message');
        }
      };
    } catch (e) {
      this.setStatus('error');
      this.log('system', 'Failed to create WebSocket: ' + (e as Error).message);
    }
  }

  disconnect() {
    this.shouldReconnect = false;
    this.isManualDisconnect = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.reconnectAttempts = 0;
    this.setStatus('disconnected');
  }

  getStatus(): EngineStatus {
    return this.status;
  }

  isConnected(): boolean {
    return this.status === 'connected' && this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  send(msg: OutgoingMessage) {
    this.log('out', `→ ${msg.type}`, msg);
    if (!this.ws || this.status !== 'connected') return;
    this.ws.send(JSON.stringify(msg));
  }

  triggerEvent(eventName: string) {
    this.send({ type: 'TriggerEvent', eventName });
  }

  setParameter(name: string, value: number) {
    this.send({ type: 'SetParameter', name, value });
  }

  /** Send stress test command to server (dev-only) */
  stressTest(mode: 'duplicate' | 'flood' | 'outOfOrder' | 'rapidFire', count?: number, eventName?: string) {
    this.send({ type: 'StressTest', mode, count, eventName });
  }

  private setStatus(status: EngineStatus) {
    this.status = status;
    this.onStatus?.(status);
  }

  private log(direction: 'in' | 'out' | 'system', message: string, raw?: EngineLogRaw) {
    this.onLog?.({
      id: Math.random().toString(36).slice(2),
      direction,
      timestamp: Date.now(),
      message,
      raw
    });
  }
}
