/**
 * Markers & Cue Points System
 *
 * Provides time-based markers within audio assets for:
 * - Loop points (start/end)
 * - Entry/exit cues for transitions
 * - Action triggers (events at specific times)
 * - Beat markers for music synchronization
 * - Region markers (intro, verse, chorus, etc.)
 */

import type { BusId } from './types';

// ============ TYPES ============

export type MarkerType =
  | 'cue'           // Generic cue point
  | 'loop-start'    // Loop start point
  | 'loop-end'      // Loop end point
  | 'entry'         // Entry point for transitions
  | 'exit'          // Exit point for transitions
  | 'beat'          // Beat marker
  | 'bar'           // Bar marker
  | 'region-start'  // Region start
  | 'region-end'    // Region end
  | 'action';       // Triggers an action

export interface MarkerAction {
  /** Action type */
  type: 'play' | 'stop' | 'set-rtpc' | 'post-trigger' | 'callback';
  /** Target for play/stop */
  targetId?: string;
  /** Bus for play */
  bus?: BusId;
  /** Volume for play */
  volume?: number;
  /** RTPC name */
  rtpcName?: string;
  /** RTPC value */
  rtpcValue?: number;
  /** Trigger name */
  triggerName?: string;
  /** Callback ID for custom handling */
  callbackId?: string;
}

export interface Marker {
  /** Unique marker ID */
  id: string;
  /** Marker type */
  type: MarkerType;
  /** Time position in seconds */
  time: number;
  /** Optional duration (for regions) */
  duration?: number;
  /** Display name */
  name?: string;
  /** Associated region ID (for region-start/end) */
  regionId?: string;
  /** Actions to execute when marker is reached */
  actions?: MarkerAction[];
  /** Custom data */
  userData?: Record<string, unknown>;
}

export interface MarkerRegion {
  /** Unique region ID */
  id: string;
  /** Region name (intro, verse, chorus, etc.) */
  name: string;
  /** Start time in seconds */
  startTime: number;
  /** End time in seconds */
  endTime: number;
  /** Color for UI */
  color?: string;
}

export interface AssetMarkers {
  /** Asset ID this belongs to */
  assetId: string;
  /** All markers for this asset */
  markers: Marker[];
  /** Defined regions */
  regions: MarkerRegion[];
  /** BPM if known */
  bpm?: number;
  /** Time signature (e.g., [4, 4]) */
  timeSignature?: [number, number];
  /** Beat offset in seconds */
  beatOffset?: number;
}

export interface ActiveMarkerTracking {
  assetId: string;
  voiceId: string;
  startTime: number; // performance.now() when started
  audioStartTime: number; // Audio time offset when started
  lastCheckedTime: number;
  triggeredMarkers: Set<string>;
}

// ============ MARKER MANAGER ============

export class MarkerManager {
  private assetMarkers: Map<string, AssetMarkers> = new Map();
  private activeTracking: Map<string, ActiveMarkerTracking> = new Map();
  private updateInterval: number | null = null;
  private actionCallbacks: Map<string, () => void> = new Map();

  // Callbacks
  private playCallback: (assetId: string, bus: BusId, volume: number) => void;
  private stopCallback: (assetId: string) => void;
  private setRTPCCallback: (name: string, value: number) => void;
  private postTriggerCallback: (name: string) => void;
  private onMarkerReached?: (marker: Marker, assetId: string, voiceId: string) => void;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number) => void,
    stopCallback: (assetId: string) => void,
    setRTPCCallback: (name: string, value: number) => void,
    postTriggerCallback: (name: string) => void,
    onMarkerReached?: (marker: Marker, assetId: string, voiceId: string) => void
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;
    this.setRTPCCallback = setRTPCCallback;
    this.postTriggerCallback = postTriggerCallback;
    this.onMarkerReached = onMarkerReached;

    this.startUpdateLoop();
  }

  /**
   * Register markers for an asset
   */
  registerAssetMarkers(markers: AssetMarkers): void {
    // Sort markers by time
    markers.markers.sort((a, b) => a.time - b.time);
    this.assetMarkers.set(markers.assetId, markers);
  }

  /**
   * Get markers for an asset
   */
  getAssetMarkers(assetId: string): AssetMarkers | null {
    return this.assetMarkers.get(assetId) ?? null;
  }

  /**
   * Add a single marker to an asset
   */
  addMarker(assetId: string, marker: Marker): boolean {
    let assetData = this.assetMarkers.get(assetId);
    if (!assetData) {
      assetData = { assetId, markers: [], regions: [] };
      this.assetMarkers.set(assetId, assetData);
    }

    assetData.markers.push(marker);
    assetData.markers.sort((a, b) => a.time - b.time);
    return true;
  }

  /**
   * Remove a marker
   */
  removeMarker(assetId: string, markerId: string): boolean {
    const assetData = this.assetMarkers.get(assetId);
    if (!assetData) return false;

    const index = assetData.markers.findIndex(m => m.id === markerId);
    if (index === -1) return false;

    assetData.markers.splice(index, 1);
    return true;
  }

  /**
   * Add a region to an asset
   */
  addRegion(assetId: string, region: MarkerRegion): boolean {
    let assetData = this.assetMarkers.get(assetId);
    if (!assetData) {
      assetData = { assetId, markers: [], regions: [] };
      this.assetMarkers.set(assetId, assetData);
    }

    assetData.regions.push(region);

    // Auto-create region markers
    this.addMarker(assetId, {
      id: `${region.id}_start`,
      type: 'region-start',
      time: region.startTime,
      name: `${region.name} Start`,
      regionId: region.id,
    });

    this.addMarker(assetId, {
      id: `${region.id}_end`,
      type: 'region-end',
      time: region.endTime,
      name: `${region.name} End`,
      regionId: region.id,
    });

    return true;
  }

  /**
   * Generate beat markers for an asset
   */
  generateBeatMarkers(
    assetId: string,
    bpm: number,
    duration: number,
    timeSignature: [number, number] = [4, 4],
    beatOffset: number = 0
  ): void {
    let assetData = this.assetMarkers.get(assetId);
    if (!assetData) {
      assetData = { assetId, markers: [], regions: [] };
      this.assetMarkers.set(assetId, assetData);
    }

    assetData.bpm = bpm;
    assetData.timeSignature = timeSignature;
    assetData.beatOffset = beatOffset;

    // Remove existing beat/bar markers
    assetData.markers = assetData.markers.filter(
      m => m.type !== 'beat' && m.type !== 'bar'
    );

    const beatDuration = 60 / bpm;
    const beatsPerBar = timeSignature[0];
    let beatCount = 0;
    let time = beatOffset;

    while (time < duration) {
      const isBar = beatCount % beatsPerBar === 0;
      const barNumber = Math.floor(beatCount / beatsPerBar) + 1;
      const beatInBar = (beatCount % beatsPerBar) + 1;

      assetData.markers.push({
        id: `beat_${beatCount}`,
        type: isBar ? 'bar' : 'beat',
        time,
        name: isBar ? `Bar ${barNumber}` : `Beat ${barNumber}.${beatInBar}`,
      });

      time += beatDuration;
      beatCount++;
    }

    assetData.markers.sort((a, b) => a.time - b.time);
  }

  /**
   * Start tracking markers for a playing voice
   */
  startTracking(assetId: string, voiceId: string, audioStartTime: number = 0): void {
    this.activeTracking.set(voiceId, {
      assetId,
      voiceId,
      startTime: performance.now(),
      audioStartTime,
      lastCheckedTime: audioStartTime,
      triggeredMarkers: new Set(),
    });
  }

  /**
   * Stop tracking a voice
   */
  stopTracking(voiceId: string): void {
    this.activeTracking.delete(voiceId);
  }

  /**
   * Get current audio time for a tracked voice
   */
  getCurrentTime(voiceId: string): number | null {
    const tracking = this.activeTracking.get(voiceId);
    if (!tracking) return null;

    const elapsed = (performance.now() - tracking.startTime) / 1000;
    return tracking.audioStartTime + elapsed;
  }

  /**
   * Get markers in a time range
   */
  getMarkersInRange(assetId: string, startTime: number, endTime: number): Marker[] {
    const assetData = this.assetMarkers.get(assetId);
    if (!assetData) return [];

    return assetData.markers.filter(m => m.time >= startTime && m.time < endTime);
  }

  /**
   * Get next marker of a specific type
   */
  getNextMarker(assetId: string, currentTime: number, type?: MarkerType): Marker | null {
    const assetData = this.assetMarkers.get(assetId);
    if (!assetData) return null;

    for (const marker of assetData.markers) {
      if (marker.time > currentTime) {
        if (!type || marker.type === type) {
          return marker;
        }
      }
    }
    return null;
  }

  /**
   * Get loop points for an asset
   */
  getLoopPoints(assetId: string): { start: number; end: number } | null {
    const assetData = this.assetMarkers.get(assetId);
    if (!assetData) return null;

    const loopStart = assetData.markers.find(m => m.type === 'loop-start');
    const loopEnd = assetData.markers.find(m => m.type === 'loop-end');

    if (loopStart && loopEnd) {
      return { start: loopStart.time, end: loopEnd.time };
    }
    return null;
  }

  /**
   * Get entry point for transitions
   */
  getEntryPoint(assetId: string): number | null {
    const assetData = this.assetMarkers.get(assetId);
    if (!assetData) return null;

    const entry = assetData.markers.find(m => m.type === 'entry');
    return entry?.time ?? null;
  }

  /**
   * Get exit point for transitions
   */
  getExitPoint(assetId: string): number | null {
    const assetData = this.assetMarkers.get(assetId);
    if (!assetData) return null;

    const exit = assetData.markers.find(m => m.type === 'exit');
    return exit?.time ?? null;
  }

  /**
   * Get region at a specific time
   */
  getRegionAtTime(assetId: string, time: number): MarkerRegion | null {
    const assetData = this.assetMarkers.get(assetId);
    if (!assetData) return null;

    return assetData.regions.find(
      r => time >= r.startTime && time < r.endTime
    ) ?? null;
  }

  /**
   * Register a custom action callback
   */
  registerActionCallback(callbackId: string, callback: () => void): void {
    this.actionCallbacks.set(callbackId, callback);
  }

  /**
   * Unregister a custom action callback
   */
  unregisterActionCallback(callbackId: string): void {
    this.actionCallbacks.delete(callbackId);
  }

  /**
   * Execute marker actions
   */
  private executeMarkerActions(marker: Marker): void {
    if (!marker.actions) return;

    for (const action of marker.actions) {
      switch (action.type) {
        case 'play':
          if (action.targetId) {
            this.playCallback(action.targetId, action.bus ?? 'sfx', action.volume ?? 1);
          }
          break;

        case 'stop':
          if (action.targetId) {
            this.stopCallback(action.targetId);
          }
          break;

        case 'set-rtpc':
          if (action.rtpcName !== undefined && action.rtpcValue !== undefined) {
            this.setRTPCCallback(action.rtpcName, action.rtpcValue);
          }
          break;

        case 'post-trigger':
          if (action.triggerName) {
            this.postTriggerCallback(action.triggerName);
          }
          break;

        case 'callback':
          if (action.callbackId) {
            const callback = this.actionCallbacks.get(action.callbackId);
            callback?.();
          }
          break;
      }
    }
  }

  /**
   * Update loop - check for marker crossings
   */
  private startUpdateLoop(): void {
    const update = () => {
      const now = performance.now();

      this.activeTracking.forEach((tracking, voiceId) => {
        const elapsed = (now - tracking.startTime) / 1000;
        const currentTime = tracking.audioStartTime + elapsed;

        // Get markers crossed since last check
        const assetData = this.assetMarkers.get(tracking.assetId);
        if (assetData) {
          const crossedMarkers = assetData.markers.filter(
            m => m.time > tracking.lastCheckedTime &&
                 m.time <= currentTime &&
                 !tracking.triggeredMarkers.has(m.id)
          );

          for (const marker of crossedMarkers) {
            tracking.triggeredMarkers.add(marker.id);

            // Execute actions
            this.executeMarkerActions(marker);

            // Notify callback
            this.onMarkerReached?.(marker, tracking.assetId, voiceId);
          }
        }

        tracking.lastCheckedTime = currentTime;
      });

      this.updateInterval = requestAnimationFrame(update);
    };

    this.updateInterval = requestAnimationFrame(update);
  }

  /**
   * Stop update loop
   */
  private stopUpdateLoop(): void {
    if (this.updateInterval !== null) {
      cancelAnimationFrame(this.updateInterval);
      this.updateInterval = null;
    }
  }

  /**
   * Get all registered assets
   */
  getRegisteredAssets(): string[] {
    return Array.from(this.assetMarkers.keys());
  }

  /**
   * Clear all markers for an asset
   */
  clearAssetMarkers(assetId: string): void {
    this.assetMarkers.delete(assetId);
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopUpdateLoop();
    this.assetMarkers.clear();
    this.activeTracking.clear();
    this.actionCallbacks.clear();
  }
}

// ============ HELPER FUNCTIONS ============

/**
 * Create loop markers for an asset
 */
export function createLoopMarkers(
  assetId: string,
  loopStart: number,
  loopEnd: number
): AssetMarkers {
  return {
    assetId,
    markers: [
      { id: 'loop_start', type: 'loop-start', time: loopStart, name: 'Loop Start' },
      { id: 'loop_end', type: 'loop-end', time: loopEnd, name: 'Loop End' },
    ],
    regions: [],
  };
}

/**
 * Create intro-loop markers (common pattern)
 */
export function createIntroLoopMarkers(
  assetId: string,
  introEnd: number,
  loopEnd: number
): AssetMarkers {
  return {
    assetId,
    markers: [
      { id: 'intro_end', type: 'cue', time: introEnd, name: 'Intro End' },
      { id: 'loop_start', type: 'loop-start', time: introEnd, name: 'Loop Start' },
      { id: 'loop_end', type: 'loop-end', time: loopEnd, name: 'Loop End' },
    ],
    regions: [
      { id: 'intro', name: 'Intro', startTime: 0, endTime: introEnd, color: '#4a90d9' },
      { id: 'loop', name: 'Loop', startTime: introEnd, endTime: loopEnd, color: '#5cb85c' },
    ],
  };
}

/**
 * Create music section markers
 */
export function createMusicSectionMarkers(
  assetId: string,
  sections: Array<{ name: string; startTime: number; endTime: number; color?: string }>
): AssetMarkers {
  const markers: Marker[] = [];
  const regions: MarkerRegion[] = [];

  sections.forEach((section, index) => {
    const regionId = `section_${index}`;

    regions.push({
      id: regionId,
      name: section.name,
      startTime: section.startTime,
      endTime: section.endTime,
      color: section.color,
    });

    markers.push({
      id: `${regionId}_start`,
      type: 'region-start',
      time: section.startTime,
      name: `${section.name} Start`,
      regionId,
    });

    markers.push({
      id: `${regionId}_end`,
      type: 'region-end',
      time: section.endTime,
      name: `${section.name} End`,
      regionId,
    });
  });

  markers.sort((a, b) => a.time - b.time);

  return { assetId, markers, regions };
}
