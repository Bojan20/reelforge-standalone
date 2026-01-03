/**
 * Zod Schemas for Session Persistence
 *
 * Validates IndexedDB/localStorage session data to prevent corrupt state
 * from crashing the application. Provides graceful degradation when
 * data doesn't match expected schema.
 *
 * @module schemas/sessionSchema
 */

import { z } from 'zod';

// ============ Sub-Schemas ============

/**
 * Serialized insert (plugin instance in a bus)
 */
export const SerializedInsertSchema = z.object({
  id: z.string().min(1),
  pluginId: z.string().min(1),
  name: z.string(),
  bypassed: z.boolean(),
  params: z.record(z.string(), z.number()),
});

/**
 * Serialized bus (mixer channel)
 */
export const SerializedBusSchema = z.object({
  id: z.string().min(1),
  name: z.string(),
  volume: z.number().min(0).max(2), // 0-200% (0-2 linear)
  pan: z.number().min(-1).max(1),   // -1 to 1
  muted: z.boolean(),
  solo: z.boolean(),
  inserts: z.array(SerializedInsertSchema),
});

/**
 * Serialized track (timeline track)
 */
export const SerializedTrackSchema = z.object({
  id: z.string().min(1),
  name: z.string(),
  color: z.string(),
  muted: z.boolean(),
  solo: z.boolean(),
  armed: z.boolean(),
});

/**
 * Serialized clip (audio region on timeline)
 */
export const SerializedClipSchema = z.object({
  id: z.string().min(1),
  trackId: z.string().min(1),
  name: z.string(),
  startTime: z.number().min(0),
  duration: z.number().min(0),
  color: z.string(),
  audioFileId: z.string().optional(),
});

/**
 * Timeline state
 */
export const TimelineStateSchema = z.object({
  clips: z.array(SerializedClipSchema),
  tracks: z.array(SerializedTrackSchema),
  zoom: z.number().min(1).max(500),
  scrollOffset: z.number().min(0),
});

/**
 * Transport state
 */
export const TransportStateSchema = z.object({
  currentTime: z.number().min(0),
  loopEnabled: z.boolean(),
  loopStart: z.number().min(0),
  loopEnd: z.number().min(0),
  tempo: z.number().min(20).max(300),
});

/**
 * Mixer state
 */
export const MixerStateSchema = z.object({
  buses: z.array(SerializedBusSchema),
});

/**
 * UI state
 */
export const UIStateSchema = z.object({
  leftPanelOpen: z.boolean(),
  rightPanelOpen: z.boolean(),
  bottomPanelOpen: z.boolean(),
  leftPanelWidth: z.number().min(100).max(800),
  rightPanelWidth: z.number().min(100).max(800),
  bottomPanelHeight: z.number().min(50).max(600),
  selectedBusId: z.string().nullable(),
  selectedClipIds: z.array(z.string()),
});

// ============ Main Session Schema ============

/**
 * Full session state schema
 */
export const SessionStateSchema = z.object({
  version: z.number().int().min(1),
  timestamp: z.number().int().positive(),
  timeline: TimelineStateSchema,
  transport: TransportStateSchema,
  mixer: MixerStateSchema,
  ui: UIStateSchema,
});

// ============ Type Inference ============

export type ValidatedSessionState = z.infer<typeof SessionStateSchema>;
export type ValidatedSerializedClip = z.infer<typeof SerializedClipSchema>;
export type ValidatedSerializedTrack = z.infer<typeof SerializedTrackSchema>;
export type ValidatedSerializedBus = z.infer<typeof SerializedBusSchema>;
export type ValidatedSerializedInsert = z.infer<typeof SerializedInsertSchema>;

// ============ Validation Helpers ============

export interface ValidationResult<T> {
  success: boolean;
  data?: T;
  error?: z.ZodError;
  issues?: string[];
}

/**
 * Validate session state with detailed error reporting.
 */
export function validateSessionState(data: unknown): ValidationResult<ValidatedSessionState> {
  const result = SessionStateSchema.safeParse(data);

  if (result.success) {
    return { success: true, data: result.data };
  }

  return {
    success: false,
    error: result.error,
    issues: result.error.issues.map(
      (issue) => `${issue.path.join('.')}: ${issue.message}`
    ),
  };
}

/**
 * Validate and coerce session state with defaults for missing/invalid fields.
 * Use this for graceful recovery from partially corrupt data.
 */
export function parseSessionStateWithDefaults(data: unknown): ValidatedSessionState {
  // Deep partial schema that fills in defaults
  const PartialSessionSchema = SessionStateSchema.partial().extend({
    timeline: TimelineStateSchema.partial().optional(),
    transport: TransportStateSchema.partial().optional(),
    mixer: MixerStateSchema.partial().optional(),
    ui: UIStateSchema.partial().optional(),
  });

  const parsed = PartialSessionSchema.safeParse(data);

  // Build state with defaults
  const defaults = getDefaultSessionState();

  if (!parsed.success) {
    console.warn('[SessionSchema] Failed to parse, using defaults:', parsed.error.issues);
    return defaults;
  }

  const d = parsed.data;

  return {
    version: d.version ?? defaults.version,
    timestamp: d.timestamp ?? defaults.timestamp,
    timeline: {
      clips: d.timeline?.clips ?? defaults.timeline.clips,
      tracks: d.timeline?.tracks ?? defaults.timeline.tracks,
      zoom: d.timeline?.zoom ?? defaults.timeline.zoom,
      scrollOffset: d.timeline?.scrollOffset ?? defaults.timeline.scrollOffset,
    },
    transport: {
      currentTime: d.transport?.currentTime ?? defaults.transport.currentTime,
      loopEnabled: d.transport?.loopEnabled ?? defaults.transport.loopEnabled,
      loopStart: d.transport?.loopStart ?? defaults.transport.loopStart,
      loopEnd: d.transport?.loopEnd ?? defaults.transport.loopEnd,
      tempo: d.transport?.tempo ?? defaults.transport.tempo,
    },
    mixer: {
      buses: d.mixer?.buses ?? defaults.mixer.buses,
    },
    ui: {
      leftPanelOpen: d.ui?.leftPanelOpen ?? defaults.ui.leftPanelOpen,
      rightPanelOpen: d.ui?.rightPanelOpen ?? defaults.ui.rightPanelOpen,
      bottomPanelOpen: d.ui?.bottomPanelOpen ?? defaults.ui.bottomPanelOpen,
      leftPanelWidth: d.ui?.leftPanelWidth ?? defaults.ui.leftPanelWidth,
      rightPanelWidth: d.ui?.rightPanelWidth ?? defaults.ui.rightPanelWidth,
      bottomPanelHeight: d.ui?.bottomPanelHeight ?? defaults.ui.bottomPanelHeight,
      selectedBusId: d.ui?.selectedBusId ?? defaults.ui.selectedBusId,
      selectedClipIds: d.ui?.selectedClipIds ?? defaults.ui.selectedClipIds,
    },
  };
}

/**
 * Get default session state.
 */
export function getDefaultSessionState(): ValidatedSessionState {
  return {
    version: 1,
    timestamp: Date.now(),
    timeline: {
      clips: [],
      tracks: [],
      zoom: 50,
      scrollOffset: 0,
    },
    transport: {
      currentTime: 0,
      loopEnabled: false,
      loopStart: 0,
      loopEnd: 60,
      tempo: 120,
    },
    mixer: {
      buses: [],
    },
    ui: {
      leftPanelOpen: true,
      rightPanelOpen: true,
      bottomPanelOpen: true,
      leftPanelWidth: 280,
      rightPanelWidth: 320,
      bottomPanelHeight: 200,
      selectedBusId: null,
      selectedClipIds: [],
    },
  };
}

/**
 * Check if stored version needs migration.
 */
export function needsMigration(data: unknown, currentVersion: number): boolean {
  if (typeof data !== 'object' || data === null) return true;
  const version = (data as Record<string, unknown>).version;
  if (typeof version !== 'number') return true;
  return version < currentVersion;
}

/**
 * Migrate session state from older versions.
 * Add migration logic here as schema evolves.
 */
export function migrateSessionState(
  data: unknown,
  _targetVersion: number
): ValidatedSessionState {
  // Currently only version 1 exists
  // Future migrations would go here:
  // if (data.version === 1) { migrate to v2 }
  // if (data.version === 2) { migrate to v3 }

  // For now, just parse with defaults
  return parseSessionStateWithDefaults(data);
}
