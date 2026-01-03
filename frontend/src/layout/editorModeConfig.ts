/**
 * Editor Mode Layout Configuration
 *
 * Defines layout differences between DAW and Middleware modes.
 *
 * DAW Mode:
 * - Timeline-centric editing
 * - Full mixer in lower zone
 * - Audio clip editing focus
 * - Transport bar prominent
 * - Default tab: Timeline or Mixer
 *
 * Middleware Mode:
 * - Event-centric editing
 * - Routing and states focus
 * - Game integration tools
 * - Console/debug prominent
 * - Default tab: Slot Studio or Events
 *
 * @module layout/editorModeConfig
 */

import type { EditorMode } from '../hooks/useEditorMode';

// ============ Types ============

export interface LowerZoneConfig {
  /** Default active tab ID */
  defaultTab: string;
  /** Tab groups to show (by group ID) */
  visibleGroups: string[];
  /** Individual tabs to hide (even if group visible) */
  hiddenTabs?: string[];
  /** Priority order for tab groups (leftmost first) */
  groupOrder: string[];
}

export interface LeftZoneConfig {
  /** Default expanded folders */
  defaultExpanded: string[];
  /** Folder visibility */
  visibleFolders: ('events' | 'audio-files' | 'buses' | 'states' | 'switches' | 'rtpc')[];
}

export interface RightZoneConfig {
  /** Default inspector mode */
  defaultType: 'event' | 'sound' | 'bus' | 'state' | 'switch' | 'rtpc' | 'clip';
  /** Available section presets */
  sectionPresets: string[];
}

export interface EditorModeLayoutConfig {
  mode: EditorMode;
  lowerZone: LowerZoneConfig;
  leftZone: LeftZoneConfig;
  rightZone: RightZoneConfig;
  /** Center zone default view */
  centerDefault: 'timeline' | 'events' | 'routing';
  /** Feature flags for this mode */
  features: {
    showTransport: boolean;
    showTempo: boolean;
    showTimecode: boolean;
    showMusicLayers: boolean;
    showSlotTools: boolean;
    showGameSync: boolean;
  };
}

// ============ Mode Configurations ============

/**
 * DAW Mode - Cubase-style layout
 *
 * Lower Zone tabs (left to right):
 * - Editor (Timeline/Clip editing)
 * - MixConsole (Full mixer)
 * - Sampler (Layered music)
 * - Media (Audio Browser & Pool)
 * - DSP (Processing tools)
 */
export const DAW_MODE_CONFIG: EditorModeLayoutConfig = {
  mode: 'daw',
  lowerZone: {
    defaultTab: 'mixer',
    visibleGroups: ['mixconsole', 'clip-editor', 'sampler', 'media', 'dsp'],
    hiddenTabs: ['timeline'], // Timeline is in center zone, not needed in lower zone
    groupOrder: ['mixconsole', 'clip-editor', 'sampler', 'media', 'dsp'],
  },
  leftZone: {
    defaultExpanded: ['audio-files', 'buses'],
    visibleFolders: ['audio-files', 'buses', 'events'],
  },
  rightZone: {
    defaultType: 'clip',
    sectionPresets: ['clip-properties', 'bus-routing', 'effects'],
  },
  centerDefault: 'timeline',
  features: {
    showTransport: true,
    showTempo: true,
    showTimecode: true,
    showMusicLayers: true,
    showSlotTools: false,
    showGameSync: false,
  },
};

/**
 * Middleware Mode - Game audio middleware layout
 *
 * Lower Zone tabs (left to right):
 * - Slot (Spin cycle, win tiers, reel sequencer, studio)
 * - Features (Audio features, pro tools)
 * - DSP (Processing tools)
 * - Tools (Validation, console, debug)
 */
export const MIDDLEWARE_MODE_CONFIG: EditorModeLayoutConfig = {
  mode: 'middleware',
  lowerZone: {
    defaultTab: 'slot-studio',
    visibleGroups: ['slot', 'features', 'dsp', 'tools'],
    hiddenTabs: ['timeline', 'mixer', 'layers', 'audio-browser', 'audio-pool'],
    groupOrder: ['slot', 'features', 'dsp', 'tools'],
  },
  leftZone: {
    defaultExpanded: ['events'],
    visibleFolders: ['events', 'buses', 'states', 'switches', 'rtpc'],
  },
  rightZone: {
    defaultType: 'event',
    sectionPresets: ['event-commands', 'bus-routing', 'game-sync'],
  },
  centerDefault: 'events',
  features: {
    showTransport: false,
    showTempo: false,
    showTimecode: false,
    showMusicLayers: false,
    showSlotTools: true,
    showGameSync: true,
  },
};

// ============ Config Map ============

export const MODE_LAYOUT_CONFIGS: Record<EditorMode, EditorModeLayoutConfig> = {
  daw: DAW_MODE_CONFIG,
  middleware: MIDDLEWARE_MODE_CONFIG,
};

// ============ Utility Functions ============

/**
 * Get layout config for a given mode.
 */
export function getModeLayoutConfig(mode: EditorMode): EditorModeLayoutConfig {
  return MODE_LAYOUT_CONFIGS[mode];
}

/**
 * Check if a tab should be visible in the given mode.
 */
export function isTabVisibleInMode(tabId: string, mode: EditorMode): boolean {
  const config = MODE_LAYOUT_CONFIGS[mode];
  if (config.lowerZone.hiddenTabs?.includes(tabId)) {
    return false;
  }
  return true;
}

/**
 * Check if a tab group should be visible in the given mode.
 */
export function isTabGroupVisibleInMode(groupId: string, mode: EditorMode): boolean {
  const config = MODE_LAYOUT_CONFIGS[mode];
  return config.lowerZone.visibleGroups.includes(groupId);
}

/**
 * Get the ordered tab groups for a mode.
 */
export function getOrderedTabGroups(mode: EditorMode): string[] {
  return MODE_LAYOUT_CONFIGS[mode].lowerZone.groupOrder;
}

/**
 * Get the default tab for a mode.
 */
export function getDefaultTabForMode(mode: EditorMode): string {
  return MODE_LAYOUT_CONFIGS[mode].lowerZone.defaultTab;
}

/**
 * Filter tab groups based on mode visibility.
 */
export function filterTabGroupsForMode<T extends { id: string }>(
  groups: T[],
  mode: EditorMode
): T[] {
  const config = MODE_LAYOUT_CONFIGS[mode];
  const visibleSet = new Set(config.lowerZone.visibleGroups);
  const orderMap = new Map(config.lowerZone.groupOrder.map((id, i) => [id, i]));

  return groups
    .filter(g => visibleSet.has(g.id))
    .sort((a, b) => {
      const aOrder = orderMap.get(a.id) ?? 999;
      const bOrder = orderMap.get(b.id) ?? 999;
      return aOrder - bOrder;
    });
}

/**
 * Filter tabs based on mode visibility.
 */
export function filterTabsForMode<T extends { id: string }>(
  tabs: T[],
  mode: EditorMode
): T[] {
  const config = MODE_LAYOUT_CONFIGS[mode];
  const hiddenSet = new Set(config.lowerZone.hiddenTabs ?? []);
  return tabs.filter(t => !hiddenSet.has(t.id));
}

export default MODE_LAYOUT_CONFIGS;
