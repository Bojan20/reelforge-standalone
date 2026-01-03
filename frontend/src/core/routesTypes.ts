/**
 * ReelForge M6.7 Routes Editor Types
 *
 * TypeScript types for runtime_routes.json editing.
 * Extended with full audio parameters.
 */

/**
 * Valid bus names for routes.
 * Note: Ambience is valid internally but maps to Music in public API.
 */
export const ROUTE_BUSES = ['Master', 'Music', 'SFX', 'UI', 'VO', 'Ambience'] as const;
export type RouteBus = typeof ROUTE_BUSES[number];

/**
 * Public-facing bus names (Ambience hidden, maps to Music).
 */
export const PUBLIC_BUSES = ['Master', 'Music', 'SFX', 'UI', 'VO'] as const;
export type PublicBus = typeof PUBLIC_BUSES[number];

/**
 * Route action types - extended set.
 */
export const ROUTE_ACTION_TYPES = ['Play', 'Stop', 'StopAll', 'Fade', 'Pause', 'SetBusGain', 'Execute'] as const;
export type RouteActionType = typeof ROUTE_ACTION_TYPES[number];

/**
 * Play action definition - full parameters.
 */
export interface PlayAction {
  type: 'Play';
  assetId: string;
  bus?: RouteBus;      // Optional, uses defaultBus if empty
  gain?: number;       // 0.0-1.0, default 1.0
  loop?: boolean;      // default false
  loopCount?: number;  // Number of loops (0 = infinite when loop=true)
  fadeIn?: number;     // Fade in duration in seconds
  delay?: number;      // Delay before playback in seconds
  pan?: number;        // -1.0 (left) to 1.0 (right), default 0.0 (center)
  overlap?: boolean;   // Allow overlapping instances
}

/**
 * Stop action definition.
 */
export interface StopAction {
  type: 'Stop';
  assetId?: string;    // Optional - stop specific asset or all
  voiceId?: string;    // Runtime only, not persisted
  fadeOut?: number;    // Fade out duration in seconds
  delay?: number;      // Delay before stop in seconds
}

/**
 * StopAll action definition.
 */
export interface StopAllAction {
  type: 'StopAll';
  fadeOut?: number;    // Fade out duration for all voices
}

/**
 * Fade action definition - crossfade/volume automation.
 */
export interface FadeAction {
  type: 'Fade';
  assetId: string;
  targetVolume: number;  // 0.0-1.0 target gain
  duration?: number;     // Fade duration in seconds
  durationUp?: number;   // Fade up duration (asymmetric)
  durationDown?: number; // Fade down duration (asymmetric)
  delay?: number;        // Delay before fade starts
  pan?: number;          // Pan position during fade
}

/**
 * Pause action definition.
 */
export interface PauseAction {
  type: 'Pause';
  assetId?: string;     // Optional - pause specific asset or all
  fadeOut?: number;     // Fade out before pause
  delay?: number;       // Delay before pause
  overall?: boolean;    // Pause entire audio system
}

/**
 * SetBusGain action definition.
 */
export interface SetBusGainAction {
  type: 'SetBusGain';
  bus: RouteBus;
  gain: number;        // 0.0-1.0
  duration?: number;   // Fade duration for gain change
}

/**
 * Execute action definition.
 * Calls another event by ID, with optional volume and fade modifiers.
 */
export interface ExecuteAction {
  type: 'Execute';
  eventId: string;          // ID of event to call
  volume?: number;          // Volume multiplier (0.0-1.0)
  fadeDuration?: number;    // Fade duration override
  delay?: number;           // Delay before execution
}

/**
 * Union of all action types.
 */
export type RouteAction = PlayAction | StopAction | StopAllAction | FadeAction | PauseAction | SetBusGainAction | ExecuteAction;

/**
 * Event route definition.
 * Maps an event name to a list of actions.
 */
export interface EventRoute {
  name: string;
  actions: RouteAction[];
  description?: string;
  tags?: string[];
}

/**
 * Routes configuration file schema.
 */
export interface RoutesConfig {
  routesVersion: number; // Must be 1
  defaultBus: RouteBus;
  events: EventRoute[];
}

/**
 * Validation error with field-level location.
 */
export interface RouteValidationError {
  type: 'error' | 'warning';
  message: string;
  eventName?: string;
  eventIndex?: number;
  actionIndex?: number;
  field?: string;
}

/**
 * Validation result.
 */
export interface RouteValidationResult {
  valid: boolean;
  errors: RouteValidationError[];
  warnings: RouteValidationError[];
}

/**
 * Create a default empty routes config.
 */
export function createEmptyRoutesConfig(): RoutesConfig {
  return {
    routesVersion: 1,
    defaultBus: 'SFX',
    events: [],
  };
}

/**
 * Create a default Play action.
 */
export function createDefaultPlayAction(defaultBus: RouteBus = 'SFX'): PlayAction {
  return {
    type: 'Play',
    assetId: '',
    bus: defaultBus,
    gain: 1.0,
    loop: false,
    loopCount: 0,
    fadeIn: 0,
    delay: 0,
    pan: 0,
    overlap: false,
  };
}

/**
 * Create a default Stop action.
 */
export function createDefaultStopAction(): StopAction {
  return {
    type: 'Stop',
    fadeOut: 0,
    delay: 0,
  };
}

/**
 * Create a default Fade action.
 */
export function createDefaultFadeAction(): FadeAction {
  return {
    type: 'Fade',
    assetId: '',
    targetVolume: 1.0,
    duration: 0.5,
    delay: 0,
    pan: 0,
  };
}

/**
 * Create a default Pause action.
 */
export function createDefaultPauseAction(): PauseAction {
  return {
    type: 'Pause',
    fadeOut: 0,
    delay: 0,
    overall: false,
  };
}

/**
 * Create a default SetBusGain action.
 */
export function createDefaultSetBusGainAction(): SetBusGainAction {
  return {
    type: 'SetBusGain',
    bus: 'Music',
    gain: 1.0,
    duration: 0,
  };
}

/**
 * Create a default StopAll action.
 */
export function createDefaultStopAllAction(): StopAllAction {
  return {
    type: 'StopAll',
    fadeOut: 0,
  };
}

/**
 * Create a default Execute action.
 */
export function createDefaultExecuteAction(): ExecuteAction {
  return {
    type: 'Execute',
    eventId: '',
    volume: 1.0,
    fadeDuration: 0,
    delay: 0,
  };
}

/**
 * Create a new empty event route.
 */
export function createEmptyEventRoute(name: string = ''): EventRoute {
  return {
    name,
    actions: [],
  };
}

/**
 * Type guards for action types.
 */
export function isPlayAction(action: RouteAction): action is PlayAction {
  return action.type === 'Play';
}

export function isStopAction(action: RouteAction): action is StopAction {
  return action.type === 'Stop';
}

export function isFadeAction(action: RouteAction): action is FadeAction {
  return action.type === 'Fade';
}

export function isPauseAction(action: RouteAction): action is PauseAction {
  return action.type === 'Pause';
}

export function isSetBusGainAction(action: RouteAction): action is SetBusGainAction {
  return action.type === 'SetBusGain';
}

export function isStopAllAction(action: RouteAction): action is StopAllAction {
  return action.type === 'StopAll';
}

export function isExecuteAction(action: RouteAction): action is ExecuteAction {
  return action.type === 'Execute';
}

/**
 * Check if action has assetId field.
 */
export function hasAssetId(action: RouteAction): action is PlayAction | FadeAction {
  return action.type === 'Play' || action.type === 'Fade';
}
