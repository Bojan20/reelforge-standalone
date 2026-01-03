/**
 * ReelForge Spatial System - Debug Overlay
 * Visual debugging for spatial audio positioning.
 *
 * @module reelforge/spatial/debug
 */

import type { SpatialDebugFrame, SpatialBus } from '../types';

/**
 * Color palette for buses.
 */
const BUS_COLORS: Record<SpatialBus, string> = {
  UI: '#00ff88',
  REELS: '#ff6600',
  FX: '#ff00ff',
  VO: '#00ffff',
  MUSIC: '#ffff00',
  AMBIENT: '#8888ff',
};

/**
 * Debug overlay configuration.
 */
export interface DebugOverlayConfig {
  /** Canvas element or ID */
  canvas?: HTMLCanvasElement | string;

  /** Width (defaults to window.innerWidth) */
  width?: number;

  /** Height (defaults to window.innerHeight) */
  height?: number;

  /** Show velocity vectors */
  showVelocity?: boolean;

  /** Show confidence as opacity */
  showConfidence?: boolean;

  /** Show predicted position */
  showPredicted?: boolean;

  /** Show pan meter */
  showPanMeter?: boolean;

  /** Point size */
  pointSize?: number;

  /** Trail length (frames) */
  trailLength?: number;

  /** Z-index for overlay */
  zIndex?: number;
}

/**
 * Trail entry for position history.
 */
interface TrailEntry {
  x: number;
  y: number;
  timestamp: number;
}

/**
 * Debug overlay for visualizing spatial positions.
 */
export class DebugOverlay {
  /** Canvas element */
  private canvas: HTMLCanvasElement;

  /** 2D rendering context */
  private ctx: CanvasRenderingContext2D;

  /** Configuration */
  private config: Required<DebugOverlayConfig>;

  /** Active frames by event ID */
  private frames = new Map<string, SpatialDebugFrame>();

  /** Position trails */
  private trails = new Map<string, TrailEntry[]>();

  /** Is overlay visible */
  private visible = true;

  /** Animation frame handle */
  private rafHandle: number | null = null;

  /** Enabled buses (for filtering) */
  private enabledBuses = new Set<SpatialBus>(['UI', 'REELS', 'FX', 'VO', 'MUSIC', 'AMBIENT']);

  /** Keyboard shortcuts enabled */
  private keyboardEnabled = true;

  /** Bus order for keyboard shortcuts */
  private static readonly BUS_ORDER: SpatialBus[] = ['UI', 'REELS', 'FX', 'VO', 'MUSIC', 'AMBIENT'];

  constructor(config?: DebugOverlayConfig) {
    this.config = {
      canvas: config?.canvas ?? this.createCanvas(),
      width: config?.width ?? (typeof window !== 'undefined' ? window.innerWidth : 800),
      height: config?.height ?? (typeof window !== 'undefined' ? window.innerHeight : 600),
      showVelocity: config?.showVelocity ?? true,
      showConfidence: config?.showConfidence ?? true,
      showPredicted: config?.showPredicted ?? true,
      showPanMeter: config?.showPanMeter ?? true,
      pointSize: config?.pointSize ?? 12,
      trailLength: config?.trailLength ?? 30,
      zIndex: config?.zIndex ?? 9999,
    };

    // Get or create canvas
    if (typeof this.config.canvas === 'string') {
      const el = document.getElementById(this.config.canvas);
      if (!(el instanceof HTMLCanvasElement)) {
        throw new Error(`Canvas element not found: ${this.config.canvas}`);
      }
      this.canvas = el;
    } else {
      this.canvas = this.config.canvas as HTMLCanvasElement;
    }

    // Get context
    const ctx = this.canvas.getContext('2d');
    if (!ctx) {
      throw new Error('Failed to get 2D context');
    }
    this.ctx = ctx;

    // Setup canvas
    this.resize(this.config.width, this.config.height);

    // Listen for resize
    if (typeof window !== 'undefined') {
      window.addEventListener('resize', this.handleResize);
      window.addEventListener('keydown', this.handleKeyDown);
    }
  }

  /**
   * Create default canvas element.
   */
  private createCanvas(): HTMLCanvasElement {
    const canvas = document.createElement('canvas');
    canvas.id = 'rf-spatial-debug';
    canvas.style.position = 'fixed';
    canvas.style.top = '0';
    canvas.style.left = '0';
    canvas.style.pointerEvents = 'none';
    canvas.style.zIndex = String(this.config?.zIndex ?? 9999);
    document.body.appendChild(canvas);
    return canvas;
  }

  /**
   * Resize canvas.
   */
  resize(width: number, height: number): void {
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = width * dpr;
    this.canvas.height = height * dpr;
    this.canvas.style.width = `${width}px`;
    this.canvas.style.height = `${height}px`;
    this.ctx.scale(dpr, dpr);
    this.config.width = width;
    this.config.height = height;
  }

  /**
   * Handle window resize.
   */
  private handleResize = (): void => {
    this.resize(window.innerWidth, window.innerHeight);
  };

  /**
   * Handle keyboard shortcuts.
   * Keys 1-6: Toggle individual buses (UI, REELS, FX, VO, MUSIC, AMBIENT)
   * D: Toggle debug overlay visibility
   * A: Toggle all buses on/off
   */
  private handleKeyDown = (e: KeyboardEvent): void => {
    if (!this.keyboardEnabled) return;

    // Ignore if user is typing in an input
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
      return;
    }

    const key = e.key.toLowerCase();

    // D = Toggle debug overlay
    if (key === 'd' && e.ctrlKey && e.shiftKey) {
      e.preventDefault();
      this.toggle();
      return;
    }

    // A = Toggle all buses
    if (key === 'a' && e.ctrlKey && e.shiftKey) {
      e.preventDefault();
      if (this.enabledBuses.size === DebugOverlay.BUS_ORDER.length) {
        this.enabledBuses.clear();
      } else {
        this.enableAllBuses();
      }
      return;
    }

    // 1-6 = Toggle specific bus (with Ctrl+Shift)
    if (e.ctrlKey && e.shiftKey) {
      const num = parseInt(key, 10);
      if (num >= 1 && num <= 6) {
        e.preventDefault();
        const bus = DebugOverlay.BUS_ORDER[num - 1];
        this.toggleBus(bus);
      }
    }
  };

  /**
   * Update frame for event.
   */
  updateFrame(frame: SpatialDebugFrame): void {
    this.frames.set(frame.eventId, frame);

    // Update trail
    let trail = this.trails.get(frame.eventId);
    if (!trail) {
      trail = [];
      this.trails.set(frame.eventId, trail);
    }

    trail.push({
      x: frame.smoothX,
      y: frame.smoothY,
      timestamp: performance.now(),
    });

    // Trim trail
    if (trail.length > this.config.trailLength) {
      trail.shift();
    }
  }

  /**
   * Remove event from overlay.
   */
  removeEvent(eventId: string): void {
    this.frames.delete(eventId);
    this.trails.delete(eventId);
  }

  /**
   * Clear all events.
   */
  clear(): void {
    this.frames.clear();
    this.trails.clear();
  }

  /**
   * Start rendering loop.
   */
  start(): void {
    if (this.rafHandle !== null) return;
    this.render();
  }

  /**
   * Stop rendering loop.
   */
  stop(): void {
    if (this.rafHandle !== null) {
      cancelAnimationFrame(this.rafHandle);
      this.rafHandle = null;
    }
  }

  /**
   * Main render function.
   */
  private render = (): void => {
    this.rafHandle = requestAnimationFrame(this.render);

    if (!this.visible) return;

    const { width, height } = this.config;
    const ctx = this.ctx;

    // Clear
    ctx.clearRect(0, 0, width, height);

    // Draw pan meter
    if (this.config.showPanMeter) {
      this.drawPanMeter();
    }

    // Draw each event (filtered by enabled buses)
    for (const [eventId, frame] of this.frames) {
      if (!this.enabledBuses.has(frame.bus)) continue;
      const trail = this.trails.get(eventId);
      this.drawEvent(frame, trail);
    }

    // Draw legend
    this.drawLegend();
  };

  /**
   * Draw pan meter at bottom of screen.
   */
  private drawPanMeter(): void {
    const ctx = this.ctx;
    const { width, height } = this.config;

    const meterHeight = 20;
    const meterY = height - meterHeight - 10;
    const meterWidth = width * 0.6;
    const meterX = (width - meterWidth) / 2;

    // Background
    ctx.fillStyle = 'rgba(0, 0, 0, 0.5)';
    ctx.fillRect(meterX, meterY, meterWidth, meterHeight);

    // Center line
    ctx.strokeStyle = '#888';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(meterX + meterWidth / 2, meterY);
    ctx.lineTo(meterX + meterWidth / 2, meterY + meterHeight);
    ctx.stroke();

    // Labels
    ctx.fillStyle = '#888';
    ctx.font = '10px monospace';
    ctx.textAlign = 'center';
    ctx.fillText('L', meterX + 10, meterY + 14);
    ctx.fillText('C', meterX + meterWidth / 2, meterY + 14);
    ctx.fillText('R', meterX + meterWidth - 10, meterY + 14);

    // Draw pan indicators for each event (filtered by enabled buses)
    let indicatorY = meterY + 4;
    for (const [_eventId, frame] of this.frames) {
      if (!this.enabledBuses.has(frame.bus)) continue;
      const color = BUS_COLORS[frame.bus] ?? '#fff';
      const panX = meterX + (frame.pan + 1) / 2 * meterWidth;

      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(panX, indicatorY, 4, 0, Math.PI * 2);
      ctx.fill();

      indicatorY += 3;
      if (indicatorY > meterY + meterHeight - 4) break;
    }
  }

  /**
   * Draw a single event.
   */
  private drawEvent(frame: SpatialDebugFrame, trail?: TrailEntry[]): void {
    const ctx = this.ctx;
    const { width, height, pointSize, showConfidence, showPredicted } = this.config;
    const color = BUS_COLORS[frame.bus] ?? '#fff';

    // Convert normalized to pixel coordinates
    const x = frame.smoothX * width;
    const y = frame.smoothY * height;
    const rawX = frame.rawX * width;
    const rawY = frame.rawY * height;
    const predX = frame.predictX * width;
    const predY = frame.predictY * height;

    // Draw trail
    if (trail && trail.length > 1) {
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.globalAlpha = 0.3;
      ctx.beginPath();
      ctx.moveTo(trail[0].x * width, trail[0].y * height);
      for (let i = 1; i < trail.length; i++) {
        ctx.lineTo(trail[i].x * width, trail[i].y * height);
      }
      ctx.stroke();
      ctx.globalAlpha = 1;
    }

    // Draw raw position (hollow circle)
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.globalAlpha = 0.5;
    ctx.beginPath();
    ctx.arc(rawX, rawY, pointSize * 0.6, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;

    // Draw predicted position
    if (showPredicted) {
      ctx.strokeStyle = color;
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(predX, predY);
      ctx.stroke();
      ctx.setLineDash([]);

      // Predicted point
      ctx.fillStyle = color;
      ctx.globalAlpha = 0.4;
      ctx.beginPath();
      ctx.arc(predX, predY, pointSize * 0.4, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }

    // Draw main point
    const alpha = showConfidence ? 0.3 + 0.7 * frame.confidence : 1;
    ctx.globalAlpha = alpha;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, pointSize, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;

    // Draw label
    ctx.fillStyle = color;
    ctx.font = '11px monospace';
    ctx.textAlign = 'left';
    ctx.fillText(
      `${frame.intent} (${frame.bus})`,
      x + pointSize + 4,
      y - 4
    );
    ctx.font = '9px monospace';
    ctx.fillStyle = '#aaa';
    ctx.fillText(
      `pan: ${frame.pan.toFixed(2)} | conf: ${frame.confidence.toFixed(2)}`,
      x + pointSize + 4,
      y + 8
    );
  }

  /**
   * Draw legend with keyboard shortcuts.
   */
  private drawLegend(): void {
    const ctx = this.ctx;
    const x = 10;
    let y = 20;

    ctx.font = '12px monospace';
    ctx.fillStyle = '#fff';
    ctx.fillText('ReelForge Spatial Debug', x, y);
    y += 18;

    ctx.font = '10px monospace';
    let busIndex = 1;
    for (const [bus, color] of Object.entries(BUS_COLORS)) {
      const isEnabled = this.enabledBuses.has(bus as SpatialBus);

      // Draw checkbox/indicator
      ctx.strokeStyle = color;
      ctx.lineWidth = 1;
      ctx.strokeRect(x, y - 8, 10, 10);

      if (isEnabled) {
        ctx.fillStyle = color;
        ctx.fillRect(x + 2, y - 6, 6, 6);
      }

      // Bus label with shortcut hint (dimmed if disabled)
      ctx.fillStyle = isEnabled ? '#aaa' : '#555';
      ctx.fillText(`[${busIndex}] ${bus}`, x + 15, y);
      busIndex++;
      y += 14;
    }

    // Active count (only count enabled buses)
    let visibleCount = 0;
    for (const frame of this.frames.values()) {
      if (this.enabledBuses.has(frame.bus)) {
        visibleCount++;
      }
    }
    y += 10;
    ctx.fillStyle = '#888';
    ctx.fillText(`Visible: ${visibleCount} / ${this.frames.size}`, x, y);

    // Keyboard hints
    y += 16;
    ctx.fillStyle = '#666';
    ctx.font = '9px monospace';
    ctx.fillText('Ctrl+Shift+1-6: Toggle bus', x, y);
    y += 11;
    ctx.fillText('Ctrl+Shift+A: Toggle all', x, y);
    y += 11;
    ctx.fillText('Ctrl+Shift+D: Hide overlay', x, y);
  }

  /**
   * Toggle visibility.
   */
  toggle(): void {
    this.visible = !this.visible;
    this.canvas.style.display = this.visible ? 'block' : 'none';
  }

  /**
   * Show overlay.
   */
  show(): void {
    this.visible = true;
    this.canvas.style.display = 'block';
  }

  /**
   * Hide overlay.
   */
  hide(): void {
    this.visible = false;
    this.canvas.style.display = 'none';
  }

  /**
   * Toggle bus visibility.
   */
  toggleBus(bus: SpatialBus): void {
    if (this.enabledBuses.has(bus)) {
      this.enabledBuses.delete(bus);
    } else {
      this.enabledBuses.add(bus);
    }
  }

  /**
   * Enable specific bus.
   */
  enableBus(bus: SpatialBus): void {
    this.enabledBuses.add(bus);
  }

  /**
   * Disable specific bus.
   */
  disableBus(bus: SpatialBus): void {
    this.enabledBuses.delete(bus);
  }

  /**
   * Enable only specific buses (disable all others).
   */
  setEnabledBuses(buses: SpatialBus[]): void {
    this.enabledBuses.clear();
    for (const bus of buses) {
      this.enabledBuses.add(bus);
    }
  }

  /**
   * Enable all buses.
   */
  enableAllBuses(): void {
    this.enabledBuses = new Set<SpatialBus>(['UI', 'REELS', 'FX', 'VO', 'MUSIC', 'AMBIENT']);
  }

  /**
   * Get currently enabled buses.
   */
  getEnabledBuses(): SpatialBus[] {
    return Array.from(this.enabledBuses);
  }

  /**
   * Check if bus is enabled.
   */
  isBusEnabled(bus: SpatialBus): boolean {
    return this.enabledBuses.has(bus);
  }

  /**
   * Enable keyboard shortcuts.
   */
  enableKeyboard(): void {
    this.keyboardEnabled = true;
  }

  /**
   * Disable keyboard shortcuts.
   */
  disableKeyboard(): void {
    this.keyboardEnabled = false;
  }

  /**
   * Dispose overlay.
   */
  dispose(): void {
    this.stop();

    if (typeof window !== 'undefined') {
      window.removeEventListener('resize', this.handleResize);
      window.removeEventListener('keydown', this.handleKeyDown);
    }

    if (this.canvas.parentNode) {
      this.canvas.parentNode.removeChild(this.canvas);
    }

    this.frames.clear();
    this.trails.clear();
  }
}

/**
 * Create debug overlay.
 */
export function createDebugOverlay(config?: DebugOverlayConfig): DebugOverlay {
  return new DebugOverlay(config);
}
