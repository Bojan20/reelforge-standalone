/**
 * Automation Lane System
 *
 * DAW-style automation lanes for precise parameter control over time.
 * Supports multiple interpolation modes, recording, and real-time playback.
 *
 * Features:
 * - Timeline-synchronized automation points
 * - Multiple interpolation modes (linear, bezier, step, exponential)
 * - Recording mode for real-time automation capture
 * - Touch/Latch/Write recording modes
 * - Parameter snapping and quantization
 * - Undo/redo support via command pattern
 *
 * Architecture:
 * ```
 * [AutomationLane] ── manages ── [AutomationPoint[]]
 *       │
 *       ├── getValue(time) → interpolated value
 *       ├── record(time, value) → adds/updates points
 *       └── connect(target) → applies to parameter
 * ```
 *
 * @module core/AutomationLane
 */

import { rfDebug } from './dspMetrics';

// ============ Types ============

export type InterpolationMode = 'linear' | 'bezier' | 'step' | 'exponential' | 'smooth';

export type RecordingMode = 'off' | 'touch' | 'latch' | 'write';

export interface AutomationPoint {
  /** Time in seconds from start */
  time: number;
  /** Parameter value (normalized 0-1 or raw depending on target) */
  value: number;
  /** Interpolation to next point */
  interpolation: InterpolationMode;
  /** Bezier control points [x1, y1, x2, y2] for cubic bezier */
  bezierHandles?: [number, number, number, number];
  /** Whether this point is selected (for UI) */
  selected?: boolean;
}

export interface AutomationLaneConfig {
  /** Unique ID */
  id: string;
  /** Display name */
  name: string;
  /** Target parameter path (e.g., "master.inserts.0.params.gain") */
  targetPath: string;
  /** Parameter range */
  range: {
    min: number;
    max: number;
    /** Default value */
    default: number;
    /** Value step/resolution */
    step?: number;
  };
  /** Display color (hex) */
  color?: string;
  /** Whether lane is visible in UI */
  visible?: boolean;
  /** Whether lane is locked (no editing) */
  locked?: boolean;
  /** Default interpolation for new points */
  defaultInterpolation?: InterpolationMode;
}

export interface AutomationLaneState {
  config: AutomationLaneConfig;
  points: AutomationPoint[];
  /** Current recording mode */
  recordingMode: RecordingMode;
  /** Is currently recording */
  isRecording: boolean;
  /** Last recorded time (for touch mode) */
  lastRecordTime: number;
  /** Last read time (for interpolation cache) */
  lastReadTime: number;
  /** Cached interpolated value */
  cachedValue: number;
}

// ============ Interpolation Functions ============

/**
 * Linear interpolation between two values.
 */
function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/**
 * Cubic bezier interpolation.
 */
function cubicBezier(
  t: number,
  p0: number,
  p1: number,
  p2: number,
  p3: number
): number {
  const oneMinusT = 1 - t;
  return (
    oneMinusT * oneMinusT * oneMinusT * p0 +
    3 * oneMinusT * oneMinusT * t * p1 +
    3 * oneMinusT * t * t * p2 +
    t * t * t * p3
  );
}

/**
 * Smooth step interpolation (ease in-out).
 */
function smoothstep(t: number): number {
  return t * t * (3 - 2 * t);
}

/**
 * Exponential interpolation.
 */
function exponential(a: number, b: number, t: number, curve: number = 2): number {
  // curve > 1 = ease out, curve < 1 = ease in
  const tCurved = Math.pow(t, curve);
  return lerp(a, b, tCurved);
}

// ============ Automation Lane Class ============

/**
 * Manages automation data for a single parameter.
 */
export class AutomationLane {
  private state: AutomationLaneState;
  private updateCallback: ((value: number) => void) | null = null;
  private recording = false;
  private recordBuffer: AutomationPoint[] = [];
  private recordStartTime = 0;

  constructor(config: AutomationLaneConfig) {
    this.state = {
      config,
      points: [],
      recordingMode: 'off',
      isRecording: false,
      lastRecordTime: 0,
      lastReadTime: -1,
      cachedValue: config.range.default,
    };
  }

  // ============ Point Management ============

  /**
   * Add an automation point.
   */
  addPoint(point: Omit<AutomationPoint, 'interpolation'> & { interpolation?: InterpolationMode }): void {
    if (this.state.config.locked) return;

    const newPoint: AutomationPoint = {
      ...point,
      interpolation: point.interpolation ?? this.state.config.defaultInterpolation ?? 'linear',
    };

    // Insert in sorted order by time
    const insertIndex = this.findInsertIndex(newPoint.time);
    this.state.points.splice(insertIndex, 0, newPoint);

    rfDebug('AutomationLane', `Added point at ${newPoint.time.toFixed(3)}s: ${newPoint.value}`);
  }

  /**
   * Remove an automation point by index.
   */
  removePoint(index: number): void {
    if (this.state.config.locked) return;
    if (index >= 0 && index < this.state.points.length) {
      this.state.points.splice(index, 1);
    }
  }

  /**
   * Update an automation point.
   */
  updatePoint(index: number, updates: Partial<AutomationPoint>): void {
    if (this.state.config.locked) return;
    if (index >= 0 && index < this.state.points.length) {
      this.state.points[index] = { ...this.state.points[index], ...updates };
      // Re-sort if time changed
      if (updates.time !== undefined) {
        this.state.points.sort((a, b) => a.time - b.time);
      }
    }
  }

  /**
   * Move a point to a new time/value.
   */
  movePoint(index: number, time: number, value: number): void {
    this.updatePoint(index, { time, value });
  }

  /**
   * Clear all automation points.
   */
  clearPoints(): void {
    if (this.state.config.locked) return;
    this.state.points = [];
  }

  /**
   * Set all points at once (for undo/redo).
   */
  setPoints(points: AutomationPoint[]): void {
    if (this.state.config.locked) return;
    this.state.points = [...points].sort((a, b) => a.time - b.time);
  }

  /**
   * Get all points.
   */
  getPoints(): AutomationPoint[] {
    return [...this.state.points];
  }

  // ============ Value Interpolation ============

  /**
   * Get interpolated value at a specific time.
   */
  getValue(time: number): number {
    // Use cache if time hasn't changed
    if (time === this.state.lastReadTime) {
      return this.state.cachedValue;
    }

    const points = this.state.points;
    const config = this.state.config;

    // No points - return default
    if (points.length === 0) {
      return config.range.default;
    }

    // Before first point
    if (time <= points[0].time) {
      return points[0].value;
    }

    // After last point
    if (time >= points[points.length - 1].time) {
      return points[points.length - 1].value;
    }

    // Find surrounding points
    let p0 = points[0];
    let p1 = points[1];

    for (let i = 0; i < points.length - 1; i++) {
      if (time >= points[i].time && time < points[i + 1].time) {
        p0 = points[i];
        p1 = points[i + 1];
        break;
      }
    }

    // Calculate interpolation factor
    const t = (time - p0.time) / (p1.time - p0.time);

    // Interpolate based on mode
    let value: number;

    switch (p0.interpolation) {
      case 'step':
        value = p0.value;
        break;

      case 'linear':
        value = lerp(p0.value, p1.value, t);
        break;

      case 'smooth':
        value = lerp(p0.value, p1.value, smoothstep(t));
        break;

      case 'exponential':
        value = exponential(p0.value, p1.value, t);
        break;

      case 'bezier':
        if (p0.bezierHandles) {
          // Use bezier handles for value curve
          const [, y1, , y2] = p0.bezierHandles;
          // Approximate bezier by using y values as control points
          value = cubicBezier(t, p0.value, p0.value + y1 * (p1.value - p0.value),
            p1.value + y2 * (p0.value - p1.value), p1.value);
        } else {
          value = lerp(p0.value, p1.value, smoothstep(t));
        }
        break;

      default:
        value = lerp(p0.value, p1.value, t);
    }

    // Clamp to range
    value = Math.max(config.range.min, Math.min(config.range.max, value));

    // Apply step quantization if defined
    if (config.range.step) {
      value = Math.round(value / config.range.step) * config.range.step;
    }

    // Cache result
    this.state.lastReadTime = time;
    this.state.cachedValue = value;

    return value;
  }

  /**
   * Get value and apply to connected callback.
   */
  tick(time: number): number {
    const value = this.getValue(time);
    if (this.updateCallback) {
      this.updateCallback(value);
    }
    return value;
  }

  // ============ Recording ============

  /**
   * Set recording mode.
   */
  setRecordingMode(mode: RecordingMode): void {
    this.state.recordingMode = mode;
    if (mode === 'off') {
      this.stopRecording();
    }
  }

  /**
   * Start recording automation.
   */
  startRecording(startTime: number): void {
    if (this.state.config.locked) return;
    if (this.state.recordingMode === 'off') return;

    this.recording = true;
    this.state.isRecording = true;
    this.recordStartTime = startTime;
    this.recordBuffer = [];

    // In write mode, clear existing points from start time
    if (this.state.recordingMode === 'write') {
      this.state.points = this.state.points.filter(p => p.time < startTime);
    }

    rfDebug('AutomationLane', `Started recording (${this.state.recordingMode})`);
  }

  /**
   * Record a value at a specific time.
   */
  record(time: number, value: number): void {
    if (!this.recording) return;

    const point: AutomationPoint = {
      time,
      value: Math.max(this.state.config.range.min,
        Math.min(this.state.config.range.max, value)),
      interpolation: this.state.config.defaultInterpolation ?? 'linear',
    };

    // Add to buffer for later processing
    this.recordBuffer.push(point);
    this.state.lastRecordTime = time;
  }

  /**
   * Stop recording and finalize points.
   */
  stopRecording(): void {
    if (!this.recording) return;

    this.recording = false;
    this.state.isRecording = false;

    // Process record buffer - thin out redundant points
    const thinnedPoints = this.thinRecordBuffer(this.recordBuffer);

    // Merge with existing points based on mode
    if (this.state.recordingMode === 'write') {
      // Already cleared, just add new points
      for (const point of thinnedPoints) {
        this.addPoint(point);
      }
    } else {
      // Touch/Latch: replace points in recorded range
      if (thinnedPoints.length > 0) {
        const startTime = thinnedPoints[0].time;
        const endTime = thinnedPoints[thinnedPoints.length - 1].time;

        // Remove existing points in range
        this.state.points = this.state.points.filter(
          p => p.time < startTime || p.time > endTime
        );

        // Add new points
        for (const point of thinnedPoints) {
          this.addPoint(point);
        }
      }
    }

    this.recordBuffer = [];
    rfDebug('AutomationLane', `Stopped recording, added ${thinnedPoints.length} points`);
  }

  /**
   * Thin out redundant points from recording buffer.
   * Keeps points where value changed significantly.
   */
  private thinRecordBuffer(points: AutomationPoint[]): AutomationPoint[] {
    if (points.length <= 2) return points;

    const threshold = (this.state.config.range.max - this.state.config.range.min) * 0.01;
    const thinned: AutomationPoint[] = [points[0]];

    for (let i = 1; i < points.length - 1; i++) {
      const prev = thinned[thinned.length - 1];
      const curr = points[i];
      const next = points[i + 1];

      // Keep point if value differs significantly from linear interpolation
      const expectedValue = lerp(prev.value, next.value,
        (curr.time - prev.time) / (next.time - prev.time));
      const diff = Math.abs(curr.value - expectedValue);

      if (diff > threshold) {
        thinned.push(curr);
      }
    }

    thinned.push(points[points.length - 1]);
    return thinned;
  }

  // ============ Target Connection ============

  /**
   * Connect to a parameter update callback.
   */
  connect(callback: (value: number) => void): void {
    this.updateCallback = callback;
  }

  /**
   * Disconnect from parameter.
   */
  disconnect(): void {
    this.updateCallback = null;
  }

  // ============ Utility ============

  /**
   * Find insertion index for sorted array.
   */
  private findInsertIndex(time: number): number {
    let low = 0;
    let high = this.state.points.length;

    while (low < high) {
      const mid = Math.floor((low + high) / 2);
      if (this.state.points[mid].time < time) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    return low;
  }

  /**
   * Get configuration.
   */
  getConfig(): AutomationLaneConfig {
    return this.state.config;
  }

  /**
   * Update configuration.
   */
  updateConfig(updates: Partial<AutomationLaneConfig>): void {
    this.state.config = { ...this.state.config, ...updates };
  }

  /**
   * Get current state (for serialization).
   */
  getState(): AutomationLaneState {
    return { ...this.state };
  }

  /**
   * Check if lane is recording.
   */
  isRecording(): boolean {
    return this.recording;
  }

  /**
   * Get recording start time.
   */
  getRecordingStartTime(): number {
    return this.recordStartTime;
  }

  /**
   * Get point at or near a time (for selection).
   */
  getPointNear(time: number, tolerance: number): { point: AutomationPoint; index: number } | null {
    for (let i = 0; i < this.state.points.length; i++) {
      if (Math.abs(this.state.points[i].time - time) <= tolerance) {
        return { point: this.state.points[i], index: i };
      }
    }
    return null;
  }

  /**
   * Select points in a time range.
   */
  selectPointsInRange(startTime: number, endTime: number): void {
    for (const point of this.state.points) {
      point.selected = point.time >= startTime && point.time <= endTime;
    }
  }

  /**
   * Clear all selections.
   */
  clearSelection(): void {
    for (const point of this.state.points) {
      point.selected = false;
    }
  }

  /**
   * Delete selected points.
   */
  deleteSelected(): void {
    if (this.state.config.locked) return;
    this.state.points = this.state.points.filter(p => !p.selected);
  }
}

// ============ Automation Manager ============

/**
 * Manages multiple automation lanes and coordinates playback.
 */
class AutomationManagerClass {
  private lanes: Map<string, AutomationLane> = new Map();
  private isPlaying = false;
  private currentTime = 0;
  private animationFrame: number | null = null;

  /**
   * Create a new automation lane.
   */
  createLane(config: AutomationLaneConfig): AutomationLane {
    const lane = new AutomationLane(config);
    this.lanes.set(config.id, lane);
    rfDebug('AutomationManager', `Created lane: ${config.id}`);
    return lane;
  }

  /**
   * Get an automation lane by ID.
   */
  getLane(id: string): AutomationLane | undefined {
    return this.lanes.get(id);
  }

  /**
   * Remove an automation lane.
   */
  removeLane(id: string): void {
    const lane = this.lanes.get(id);
    if (lane) {
      lane.disconnect();
      this.lanes.delete(id);
      rfDebug('AutomationManager', `Removed lane: ${id}`);
    }
  }

  /**
   * Get all lane IDs.
   */
  getLaneIds(): string[] {
    return Array.from(this.lanes.keys());
  }

  /**
   * Get all lanes.
   */
  getAllLanes(): AutomationLane[] {
    return Array.from(this.lanes.values());
  }

  /**
   * Start playback at a specific time.
   */
  play(startTime: number = 0): void {
    this.currentTime = startTime;
    this.isPlaying = true;
    this.tick();
    rfDebug('AutomationManager', `Started playback at ${startTime}`);
  }

  /**
   * Stop playback.
   */
  stop(): void {
    this.isPlaying = false;
    if (this.animationFrame !== null) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
    rfDebug('AutomationManager', 'Stopped playback');
  }

  /**
   * Seek to a specific time.
   */
  seek(time: number): void {
    this.currentTime = time;
    // Update all lanes to new time
    for (const lane of this.lanes.values()) {
      lane.tick(time);
    }
  }

  /**
   * Get values for all lanes at a specific time.
   */
  getValuesAt(time: number): Map<string, number> {
    const values = new Map<string, number>();
    for (const [id, lane] of this.lanes) {
      values.set(id, lane.getValue(time));
    }
    return values;
  }

  /**
   * Start recording on specified lanes.
   */
  startRecording(laneIds: string[], startTime: number): void {
    for (const id of laneIds) {
      const lane = this.lanes.get(id);
      if (lane) {
        lane.startRecording(startTime);
      }
    }
  }

  /**
   * Stop recording on all lanes.
   */
  stopRecording(): void {
    for (const lane of this.lanes.values()) {
      lane.stopRecording();
    }
  }

  /**
   * Record a value to a lane.
   */
  recordValue(laneId: string, time: number, value: number): void {
    const lane = this.lanes.get(laneId);
    if (lane) {
      lane.record(time, value);
    }
  }

  /**
   * Internal tick for playback.
   */
  private tick(): void {
    if (!this.isPlaying) return;

    // Update all lanes
    for (const lane of this.lanes.values()) {
      lane.tick(this.currentTime);
    }

    // Schedule next tick
    this.animationFrame = requestAnimationFrame(() => this.tick());
  }

  /**
   * Update current time (called by transport).
   */
  setCurrentTime(time: number): void {
    this.currentTime = time;
  }

  /**
   * Dispose all lanes.
   */
  dispose(): void {
    this.stop();
    for (const lane of this.lanes.values()) {
      lane.disconnect();
    }
    this.lanes.clear();
    rfDebug('AutomationManager', 'Disposed');
  }
}

// ============ Singleton Export ============

/**
 * Global automation manager.
 */
export const automationManager = new AutomationManagerClass();

// Cleanup on page unload
if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    automationManager.dispose();
  });
}

export default automationManager;
