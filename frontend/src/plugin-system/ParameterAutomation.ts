/**
 * ReelForge Plugin Parameter Automation
 *
 * Handles parameter automation with recording and playback.
 * Supports multiple automation modes and curve types.
 *
 * @module plugin-system/ParameterAutomation
 */

import type { PluginInstance } from './PluginRegistry';

// ============ Types ============

export type AutomationMode = 'read' | 'write' | 'touch' | 'latch' | 'off';
export type AutomationCurve = 'linear' | 'exponential' | 'logarithmic' | 's-curve' | 'hold';

export interface AutomationPoint {
  time: number; // In beats or seconds
  value: number; // Normalized 0-1
  curve: AutomationCurve;
}

export interface AutomationLane {
  id: string;
  instanceId: string;
  parameterId: string;
  parameterName: string;
  points: AutomationPoint[];
  mode: AutomationMode;
  isArmed: boolean;
  color?: string;
}

export interface AutomationSnapshot {
  time: number;
  values: Map<string, number>; // parameterId -> value
}

export interface RecordingSession {
  laneId: string;
  startTime: number;
  points: AutomationPoint[];
  isRecording: boolean;
}

// ============ Interpolation Functions ============

function interpolate(
  start: number,
  end: number,
  t: number,
  curve: AutomationCurve
): number {
  switch (curve) {
    case 'linear':
      return start + (end - start) * t;
    case 'exponential':
      return start * Math.pow(end / start, t);
    case 'logarithmic':
      return start + (end - start) * (1 - Math.pow(1 - t, 2));
    case 's-curve':
      const smooth = t * t * (3 - 2 * t);
      return start + (end - start) * smooth;
    case 'hold':
      return start;
    default:
      return start + (end - start) * t;
  }
}

// ============ Automation Engine ============

class AutomationEngineImpl {
  private lanes = new Map<string, AutomationLane>();
  private recordings = new Map<string, RecordingSession>();
  private instanceLanes = new Map<string, Set<string>>(); // instanceId -> laneIds
  private currentTime = 0;
  private isPlaying = false;
  private listeners = new Set<(event: AutomationEvent) => void>();

  // Thinning threshold for recorded points
  private recordingThreshold = 0.01;

  // ============ Lane Management ============

  /**
   * Create automation lane for parameter.
   */
  createLane(
    instance: PluginInstance,
    parameterId: string
  ): AutomationLane {
    const paramInfo = (instance as { getParameterInfo?: (id: string) => { name: string } | undefined })
      .getParameterInfo?.(parameterId);

    const lane: AutomationLane = {
      id: `lane_${instance.id}_${parameterId}`,
      instanceId: instance.id,
      parameterId,
      parameterName: paramInfo?.name ?? parameterId,
      points: [],
      mode: 'read',
      isArmed: false,
    };

    this.lanes.set(lane.id, lane);

    // Index by instance
    if (!this.instanceLanes.has(instance.id)) {
      this.instanceLanes.set(instance.id, new Set());
    }
    this.instanceLanes.get(instance.id)!.add(lane.id);

    this.emit({ type: 'laneCreated', lane });
    return lane;
  }

  /**
   * Get lane by ID.
   */
  getLane(laneId: string): AutomationLane | undefined {
    return this.lanes.get(laneId);
  }

  /**
   * Get all lanes for instance.
   */
  getLanesForInstance(instanceId: string): AutomationLane[] {
    const laneIds = this.instanceLanes.get(instanceId);
    if (!laneIds) return [];

    return Array.from(laneIds)
      .map(id => this.lanes.get(id))
      .filter((l): l is AutomationLane => l !== undefined);
  }

  /**
   * Delete lane.
   */
  deleteLane(laneId: string): boolean {
    const lane = this.lanes.get(laneId);
    if (!lane) return false;

    this.lanes.delete(laneId);
    this.instanceLanes.get(lane.instanceId)?.delete(laneId);
    this.recordings.delete(laneId);

    this.emit({ type: 'laneDeleted', laneId });
    return true;
  }

  /**
   * Set lane mode.
   */
  setMode(laneId: string, mode: AutomationMode): void {
    const lane = this.lanes.get(laneId);
    if (!lane) return;

    lane.mode = mode;
    this.emit({ type: 'modeChanged', laneId, mode });

    // Stop recording if switching away from write modes
    if (mode === 'read' || mode === 'off') {
      this.stopRecording(laneId);
    }
  }

  /**
   * Arm/disarm lane for recording.
   */
  setArmed(laneId: string, armed: boolean): void {
    const lane = this.lanes.get(laneId);
    if (!lane) return;

    lane.isArmed = armed;
    this.emit({ type: 'armedChanged', laneId, armed });
  }

  // ============ Points Management ============

  /**
   * Add automation point.
   */
  addPoint(
    laneId: string,
    time: number,
    value: number,
    curve: AutomationCurve = 'linear'
  ): void {
    const lane = this.lanes.get(laneId);
    if (!lane) return;

    // Clamp value
    value = Math.max(0, Math.min(1, value));

    // Find insertion position (keep sorted)
    let insertIndex = lane.points.length;
    for (let i = 0; i < lane.points.length; i++) {
      if (lane.points[i].time > time) {
        insertIndex = i;
        break;
      } else if (Math.abs(lane.points[i].time - time) < 0.001) {
        // Update existing point
        lane.points[i].value = value;
        lane.points[i].curve = curve;
        this.emit({ type: 'pointUpdated', laneId, point: lane.points[i] });
        return;
      }
    }

    const point: AutomationPoint = { time, value, curve };
    lane.points.splice(insertIndex, 0, point);
    this.emit({ type: 'pointAdded', laneId, point });
  }

  /**
   * Remove point.
   */
  removePoint(laneId: string, time: number): boolean {
    const lane = this.lanes.get(laneId);
    if (!lane) return false;

    const index = lane.points.findIndex(p => Math.abs(p.time - time) < 0.001);
    if (index === -1) return false;

    lane.points.splice(index, 1);
    this.emit({ type: 'pointRemoved', laneId, time });
    return true;
  }

  /**
   * Move point.
   */
  movePoint(
    laneId: string,
    oldTime: number,
    newTime: number,
    newValue?: number
  ): boolean {
    const lane = this.lanes.get(laneId);
    if (!lane) return false;

    const point = lane.points.find(p => Math.abs(p.time - oldTime) < 0.001);
    if (!point) return false;

    // Remove and re-add to maintain sort order
    this.removePoint(laneId, oldTime);
    this.addPoint(laneId, newTime, newValue ?? point.value, point.curve);

    return true;
  }

  /**
   * Clear all points in lane.
   */
  clearLane(laneId: string): void {
    const lane = this.lanes.get(laneId);
    if (!lane) return;

    lane.points = [];
    this.emit({ type: 'laneCleared', laneId });
  }

  /**
   * Clear points in time range.
   */
  clearRange(laneId: string, startTime: number, endTime: number): void {
    const lane = this.lanes.get(laneId);
    if (!lane) return;

    lane.points = lane.points.filter(
      p => p.time < startTime || p.time > endTime
    );
    this.emit({ type: 'rangeCleared', laneId, startTime, endTime });
  }

  // ============ Playback ============

  /**
   * Get value at time.
   */
  getValueAtTime(laneId: string, time: number): number | undefined {
    const lane = this.lanes.get(laneId);
    if (!lane || lane.points.length === 0) return undefined;
    if (lane.mode === 'off') return undefined;

    // Before first point
    if (time <= lane.points[0].time) {
      return lane.points[0].value;
    }

    // After last point
    if (time >= lane.points[lane.points.length - 1].time) {
      return lane.points[lane.points.length - 1].value;
    }

    // Find surrounding points
    for (let i = 0; i < lane.points.length - 1; i++) {
      const p1 = lane.points[i];
      const p2 = lane.points[i + 1];

      if (time >= p1.time && time < p2.time) {
        const t = (time - p1.time) / (p2.time - p1.time);
        return interpolate(p1.value, p2.value, t, p1.curve);
      }
    }

    return lane.points[0].value;
  }

  /**
   * Update current playback time.
   */
  setTime(time: number): void {
    this.currentTime = time;
  }

  /**
   * Start playback.
   */
  play(): void {
    this.isPlaying = true;
  }

  /**
   * Stop playback.
   */
  stop(): void {
    this.isPlaying = false;

    // Stop all recordings
    for (const laneId of this.recordings.keys()) {
      this.stopRecording(laneId);
    }
  }

  /**
   * Process automation for current time.
   * Returns parameter updates to apply.
   */
  process(time: number): Map<string, Map<string, number>> {
    this.currentTime = time;
    const updates = new Map<string, Map<string, number>>();

    for (const lane of this.lanes.values()) {
      if (lane.mode === 'off') continue;
      if (lane.mode !== 'read' && !this.isPlaying) continue;

      const value = this.getValueAtTime(lane.id, time);
      if (value === undefined) continue;

      if (!updates.has(lane.instanceId)) {
        updates.set(lane.instanceId, new Map());
      }
      updates.get(lane.instanceId)!.set(lane.parameterId, value);
    }

    return updates;
  }

  // ============ Recording ============

  /**
   * Start recording automation.
   */
  startRecording(laneId: string): void {
    const lane = this.lanes.get(laneId);
    if (!lane || !lane.isArmed) return;
    if (lane.mode !== 'write' && lane.mode !== 'touch' && lane.mode !== 'latch') return;

    const session: RecordingSession = {
      laneId,
      startTime: this.currentTime,
      points: [],
      isRecording: true,
    };

    this.recordings.set(laneId, session);
    this.emit({ type: 'recordingStarted', laneId });
  }

  /**
   * Record value during playback.
   */
  recordValue(laneId: string, value: number): void {
    const session = this.recordings.get(laneId);
    if (!session || !session.isRecording) return;

    const lane = this.lanes.get(laneId);
    if (!lane) return;

    // Thinning: skip if value hasn't changed significantly
    if (session.points.length > 0) {
      const lastPoint = session.points[session.points.length - 1];
      if (Math.abs(lastPoint.value - value) < this.recordingThreshold) {
        return;
      }
    }

    session.points.push({
      time: this.currentTime,
      value: Math.max(0, Math.min(1, value)),
      curve: 'linear',
    });
  }

  /**
   * Stop recording.
   */
  stopRecording(laneId: string): void {
    const session = this.recordings.get(laneId);
    if (!session) return;

    session.isRecording = false;

    // Merge recorded points into lane
    const lane = this.lanes.get(laneId);
    if (lane && session.points.length > 0) {
      // Clear existing points in recorded range
      const startTime = session.startTime;
      const endTime = session.points[session.points.length - 1].time;
      this.clearRange(laneId, startTime, endTime);

      // Add recorded points
      for (const point of session.points) {
        this.addPoint(laneId, point.time, point.value, point.curve);
      }
    }

    this.recordings.delete(laneId);
    this.emit({ type: 'recordingStopped', laneId, pointCount: session.points.length });
  }

  /**
   * Check if recording.
   */
  isRecording(laneId: string): boolean {
    return this.recordings.get(laneId)?.isRecording ?? false;
  }

  // ============ Curve Operations ============

  /**
   * Set curve type for range.
   */
  setCurveForRange(
    laneId: string,
    startTime: number,
    endTime: number,
    curve: AutomationCurve
  ): void {
    const lane = this.lanes.get(laneId);
    if (!lane) return;

    for (const point of lane.points) {
      if (point.time >= startTime && point.time <= endTime) {
        point.curve = curve;
      }
    }

    this.emit({ type: 'curveChanged', laneId, startTime, endTime, curve });
  }

  /**
   * Thin points (reduce density).
   */
  thinPoints(laneId: string, tolerance: number): number {
    const lane = this.lanes.get(laneId);
    if (!lane || lane.points.length < 3) return 0;

    const originalCount = lane.points.length;
    const newPoints: AutomationPoint[] = [lane.points[0]];

    for (let i = 1; i < lane.points.length - 1; i++) {
      const prev = newPoints[newPoints.length - 1];
      const curr = lane.points[i];
      const next = lane.points[i + 1];

      // Calculate interpolated value at current time
      const t = (curr.time - prev.time) / (next.time - prev.time);
      const interpolated = interpolate(prev.value, next.value, t, 'linear');

      // Keep point if it differs significantly from interpolation
      if (Math.abs(curr.value - interpolated) > tolerance) {
        newPoints.push(curr);
      }
    }

    newPoints.push(lane.points[lane.points.length - 1]);
    lane.points = newPoints;

    return originalCount - lane.points.length;
  }

  // ============ Events ============

  subscribe(callback: (event: AutomationEvent) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  private emit(event: AutomationEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  // ============ Serialization ============

  /**
   * Export lane to JSON.
   */
  exportLane(laneId: string): string | undefined {
    const lane = this.lanes.get(laneId);
    if (!lane) return undefined;

    return JSON.stringify({
      parameterId: lane.parameterId,
      points: lane.points,
    });
  }

  /**
   * Import lane from JSON.
   */
  importLane(laneId: string, data: string): boolean {
    const lane = this.lanes.get(laneId);
    if (!lane) return false;

    try {
      const parsed = JSON.parse(data);
      if (!Array.isArray(parsed.points)) return false;

      lane.points = parsed.points;
      this.emit({ type: 'laneImported', laneId });
      return true;
    } catch {
      return false;
    }
  }
}

// ============ Event Types ============

export type AutomationEvent =
  | { type: 'laneCreated'; lane: AutomationLane }
  | { type: 'laneDeleted'; laneId: string }
  | { type: 'laneCleared'; laneId: string }
  | { type: 'laneImported'; laneId: string }
  | { type: 'modeChanged'; laneId: string; mode: AutomationMode }
  | { type: 'armedChanged'; laneId: string; armed: boolean }
  | { type: 'pointAdded'; laneId: string; point: AutomationPoint }
  | { type: 'pointUpdated'; laneId: string; point: AutomationPoint }
  | { type: 'pointRemoved'; laneId: string; time: number }
  | { type: 'rangeCleared'; laneId: string; startTime: number; endTime: number }
  | { type: 'curveChanged'; laneId: string; startTime: number; endTime: number; curve: AutomationCurve }
  | { type: 'recordingStarted'; laneId: string }
  | { type: 'recordingStopped'; laneId: string; pointCount: number };

// ============ Singleton Instance ============

export const AutomationEngine = new AutomationEngineImpl();

// ============ Utility Functions ============

/**
 * Get automation mode name.
 */
export function getModeName(mode: AutomationMode): string {
  const names: Record<AutomationMode, string> = {
    read: 'Read',
    write: 'Write',
    touch: 'Touch',
    latch: 'Latch',
    off: 'Off',
  };
  return names[mode];
}

/**
 * Get curve name.
 */
export function getCurveName(curve: AutomationCurve): string {
  const names: Record<AutomationCurve, string> = {
    linear: 'Linear',
    exponential: 'Exponential',
    logarithmic: 'Logarithmic',
    's-curve': 'S-Curve',
    hold: 'Hold',
  };
  return names[curve];
}
