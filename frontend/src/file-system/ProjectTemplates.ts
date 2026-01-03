/**
 * ReelForge Project Templates
 *
 * Quick-start templates for new projects.
 *
 * @module file-system/ProjectTemplates
 */

// ============ Types ============

export interface ProjectTemplate {
  id: string;
  name: string;
  description: string;
  category: TemplateCategory;
  thumbnail?: string; // Base64 or URL
  tags: string[];
  data: TemplateData;
}

export type TemplateCategory =
  | 'music'
  | 'podcast'
  | 'sound-design'
  | 'game-audio'
  | 'film'
  | 'custom';

export interface TemplateData {
  tempo: number;
  timeSignature: [number, number];
  sampleRate: number;
  tracks: TemplateTrack[];
  buses?: TemplateBus[];
  markers?: TemplateMarker[];
}

export interface TemplateTrack {
  name: string;
  type: 'audio' | 'midi' | 'bus';
  color: string;
  volume: number;
  pan: number;
  muted: boolean;
  solo: boolean;
}

export interface TemplateBus {
  name: string;
  color: string;
  volume: number;
}

export interface TemplateMarker {
  name: string;
  time: number;
  color: string;
}

// ============ Built-in Templates ============

export const BUILT_IN_TEMPLATES: ProjectTemplate[] = [
  // Empty Project
  {
    id: 'empty',
    name: 'Empty Project',
    description: 'Start from scratch with a blank canvas',
    category: 'custom',
    tags: ['blank', 'empty', 'minimal'],
    data: {
      tempo: 120,
      timeSignature: [4, 4],
      sampleRate: 48000,
      tracks: [],
    },
  },

  // Music Production
  {
    id: 'music-basic',
    name: 'Basic Music Session',
    description: 'Simple setup with drums, bass, and melodic tracks',
    category: 'music',
    tags: ['music', 'production', 'basic'],
    data: {
      tempo: 120,
      timeSignature: [4, 4],
      sampleRate: 48000,
      tracks: [
        { name: 'Drums', type: 'audio', color: '#ef4444', volume: 0.8, pan: 0, muted: false, solo: false },
        { name: 'Bass', type: 'audio', color: '#3b82f6', volume: 0.75, pan: 0, muted: false, solo: false },
        { name: 'Keys', type: 'midi', color: '#22c55e', volume: 0.7, pan: -0.2, muted: false, solo: false },
        { name: 'Lead', type: 'midi', color: '#eab308', volume: 0.65, pan: 0.2, muted: false, solo: false },
      ],
      buses: [
        { name: 'Reverb', color: '#8b5cf6', volume: 0.5 },
        { name: 'Delay', color: '#06b6d4', volume: 0.4 },
      ],
    },
  },

  // EDM Production
  {
    id: 'edm-template',
    name: 'EDM Production',
    description: 'Electronic dance music template with synth layers',
    category: 'music',
    tags: ['edm', 'electronic', 'dance', 'synth'],
    data: {
      tempo: 128,
      timeSignature: [4, 4],
      sampleRate: 48000,
      tracks: [
        { name: 'Kick', type: 'audio', color: '#dc2626', volume: 0.9, pan: 0, muted: false, solo: false },
        { name: 'Snare', type: 'audio', color: '#ea580c', volume: 0.8, pan: 0, muted: false, solo: false },
        { name: 'Hi-Hats', type: 'audio', color: '#f59e0b', volume: 0.6, pan: 0.3, muted: false, solo: false },
        { name: 'Bass', type: 'midi', color: '#2563eb', volume: 0.85, pan: 0, muted: false, solo: false },
        { name: 'Lead Synth', type: 'midi', color: '#7c3aed', volume: 0.7, pan: 0, muted: false, solo: false },
        { name: 'Pad', type: 'midi', color: '#0891b2', volume: 0.5, pan: 0, muted: false, solo: false },
        { name: 'FX', type: 'audio', color: '#059669', volume: 0.4, pan: 0, muted: false, solo: false },
      ],
      buses: [
        { name: 'Sidechain', color: '#be185d', volume: 1 },
        { name: 'Reverb', color: '#8b5cf6', volume: 0.6 },
        { name: 'Delay', color: '#06b6d4', volume: 0.5 },
      ],
      markers: [
        { name: 'Intro', time: 0, color: '#22c55e' },
        { name: 'Buildup', time: 32, color: '#f59e0b' },
        { name: 'Drop', time: 64, color: '#ef4444' },
        { name: 'Breakdown', time: 128, color: '#3b82f6' },
        { name: 'Drop 2', time: 192, color: '#ef4444' },
        { name: 'Outro', time: 256, color: '#8b5cf6' },
      ],
    },
  },

  // Podcast
  {
    id: 'podcast-stereo',
    name: 'Podcast (Stereo)',
    description: 'Two-person podcast setup with music beds',
    category: 'podcast',
    tags: ['podcast', 'voice', 'interview'],
    data: {
      tempo: 120,
      timeSignature: [4, 4],
      sampleRate: 48000,
      tracks: [
        { name: 'Host', type: 'audio', color: '#3b82f6', volume: 1, pan: -0.3, muted: false, solo: false },
        { name: 'Guest', type: 'audio', color: '#22c55e', volume: 1, pan: 0.3, muted: false, solo: false },
        { name: 'Intro Music', type: 'audio', color: '#8b5cf6', volume: 0.5, pan: 0, muted: false, solo: false },
        { name: 'Outro Music', type: 'audio', color: '#8b5cf6', volume: 0.5, pan: 0, muted: false, solo: false },
        { name: 'Sound FX', type: 'audio', color: '#f59e0b', volume: 0.6, pan: 0, muted: false, solo: false },
      ],
      markers: [
        { name: 'Intro', time: 0, color: '#8b5cf6' },
        { name: 'Topic 1', time: 60, color: '#3b82f6' },
        { name: 'Topic 2', time: 600, color: '#22c55e' },
        { name: 'Outro', time: 1800, color: '#8b5cf6' },
      ],
    },
  },

  // Sound Design
  {
    id: 'sound-design',
    name: 'Sound Design',
    description: 'Multi-layer sound design session',
    category: 'sound-design',
    tags: ['sfx', 'foley', 'layers'],
    data: {
      tempo: 120,
      timeSignature: [4, 4],
      sampleRate: 48000,
      tracks: [
        { name: 'Layer 1 - Low', type: 'audio', color: '#1e40af', volume: 0.8, pan: 0, muted: false, solo: false },
        { name: 'Layer 2 - Mid', type: 'audio', color: '#0369a1', volume: 0.75, pan: 0, muted: false, solo: false },
        { name: 'Layer 3 - High', type: 'audio', color: '#0891b2', volume: 0.7, pan: 0, muted: false, solo: false },
        { name: 'Texture', type: 'audio', color: '#7c3aed', volume: 0.5, pan: 0, muted: false, solo: false },
        { name: 'Transient', type: 'audio', color: '#ef4444', volume: 0.6, pan: 0, muted: false, solo: false },
        { name: 'Sweetener', type: 'audio', color: '#f59e0b', volume: 0.4, pan: 0, muted: false, solo: false },
      ],
      buses: [
        { name: 'Group', color: '#64748b', volume: 1 },
        { name: 'Reverb', color: '#8b5cf6', volume: 0.5 },
      ],
    },
  },

  // Game Audio
  {
    id: 'game-audio',
    name: 'Game Audio',
    description: 'Game sound effects and music layers',
    category: 'game-audio',
    tags: ['game', 'interactive', 'sfx', 'music'],
    data: {
      tempo: 120,
      timeSignature: [4, 4],
      sampleRate: 48000,
      tracks: [
        { name: 'Music - Base', type: 'audio', color: '#8b5cf6', volume: 0.6, pan: 0, muted: false, solo: false },
        { name: 'Music - Action', type: 'audio', color: '#ef4444', volume: 0.7, pan: 0, muted: true, solo: false },
        { name: 'Music - Calm', type: 'audio', color: '#22c55e', volume: 0.5, pan: 0, muted: true, solo: false },
        { name: 'SFX - Player', type: 'audio', color: '#3b82f6', volume: 0.8, pan: 0, muted: false, solo: false },
        { name: 'SFX - Enemy', type: 'audio', color: '#dc2626', volume: 0.75, pan: 0, muted: false, solo: false },
        { name: 'SFX - UI', type: 'audio', color: '#f59e0b', volume: 0.6, pan: 0, muted: false, solo: false },
        { name: 'Ambience', type: 'audio', color: '#0891b2', volume: 0.4, pan: 0, muted: false, solo: false },
        { name: 'Voice', type: 'audio', color: '#ec4899', volume: 1, pan: 0, muted: false, solo: false },
      ],
      buses: [
        { name: 'Music Bus', color: '#8b5cf6', volume: 0.7 },
        { name: 'SFX Bus', color: '#3b82f6', volume: 0.85 },
        { name: 'Reverb', color: '#64748b', volume: 0.5 },
      ],
    },
  },

  // Film Scoring
  {
    id: 'film-score',
    name: 'Film Score',
    description: 'Orchestral template for film/TV scoring',
    category: 'film',
    tags: ['film', 'orchestra', 'score', 'cinematic'],
    data: {
      tempo: 90,
      timeSignature: [4, 4],
      sampleRate: 48000,
      tracks: [
        { name: 'Strings Hi', type: 'midi', color: '#b91c1c', volume: 0.7, pan: -0.4, muted: false, solo: false },
        { name: 'Strings Lo', type: 'midi', color: '#991b1b', volume: 0.75, pan: 0.4, muted: false, solo: false },
        { name: 'Brass', type: 'midi', color: '#b45309', volume: 0.65, pan: 0.2, muted: false, solo: false },
        { name: 'Woodwinds', type: 'midi', color: '#15803d', volume: 0.6, pan: -0.3, muted: false, solo: false },
        { name: 'Percussion', type: 'midi', color: '#1d4ed8', volume: 0.7, pan: 0, muted: false, solo: false },
        { name: 'Choir', type: 'midi', color: '#7e22ce', volume: 0.55, pan: 0, muted: false, solo: false },
        { name: 'Piano', type: 'midi', color: '#475569', volume: 0.6, pan: 0, muted: false, solo: false },
        { name: 'Synth/Pads', type: 'midi', color: '#0e7490', volume: 0.45, pan: 0, muted: false, solo: false },
      ],
      buses: [
        { name: 'Orch Verb', color: '#8b5cf6', volume: 0.6 },
        { name: 'Room', color: '#64748b', volume: 0.4 },
      ],
      markers: [
        { name: 'M01 - Opening', time: 0, color: '#22c55e' },
        { name: 'Hit 1', time: 45, color: '#ef4444' },
        { name: 'M02 - Tension', time: 120, color: '#f59e0b' },
      ],
    },
  },
];

// ============ Template Manager Class ============

class ProjectTemplateManagerClass {
  private customTemplates: ProjectTemplate[] = [];

  constructor() {
    this.loadCustomTemplates();
  }

  /**
   * Get all templates.
   */
  getAllTemplates(): ProjectTemplate[] {
    return [...BUILT_IN_TEMPLATES, ...this.customTemplates];
  }

  /**
   * Get templates by category.
   */
  getByCategory(category: TemplateCategory): ProjectTemplate[] {
    return this.getAllTemplates().filter(t => t.category === category);
  }

  /**
   * Get template by ID.
   */
  getById(id: string): ProjectTemplate | undefined {
    return this.getAllTemplates().find(t => t.id === id);
  }

  /**
   * Search templates.
   */
  search(query: string): ProjectTemplate[] {
    const lowerQuery = query.toLowerCase();
    return this.getAllTemplates().filter(t =>
      t.name.toLowerCase().includes(lowerQuery) ||
      t.description.toLowerCase().includes(lowerQuery) ||
      t.tags.some(tag => tag.toLowerCase().includes(lowerQuery))
    );
  }

  /**
   * Add custom template.
   */
  addCustomTemplate(template: Omit<ProjectTemplate, 'id'>): ProjectTemplate {
    const newTemplate: ProjectTemplate = {
      ...template,
      id: `custom_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
      category: 'custom',
    };

    this.customTemplates.push(newTemplate);
    this.saveCustomTemplates();

    return newTemplate;
  }

  /**
   * Remove custom template.
   */
  removeCustomTemplate(id: string): boolean {
    const index = this.customTemplates.findIndex(t => t.id === id);
    if (index === -1) return false;

    this.customTemplates.splice(index, 1);
    this.saveCustomTemplates();

    return true;
  }

  /**
   * Create project data from template.
   */
  createFromTemplate(templateId: string): TemplateData | null {
    const template = this.getById(templateId);
    if (!template) return null;

    // Deep clone the template data
    return JSON.parse(JSON.stringify(template.data));
  }

  /**
   * Load custom templates from localStorage.
   */
  private loadCustomTemplates(): void {
    try {
      const saved = localStorage.getItem('reelforge-custom-templates');
      if (saved) {
        this.customTemplates = JSON.parse(saved);
      }
    } catch {
      this.customTemplates = [];
    }
  }

  /**
   * Save custom templates to localStorage.
   */
  private saveCustomTemplates(): void {
    try {
      localStorage.setItem('reelforge-custom-templates', JSON.stringify(this.customTemplates));
    } catch {
      console.error('Failed to save custom templates');
    }
  }

  /**
   * Get all categories with counts.
   */
  getCategoryCounts(): Record<TemplateCategory, number> {
    const templates = this.getAllTemplates();
    const counts: Record<TemplateCategory, number> = {
      'music': 0,
      'podcast': 0,
      'sound-design': 0,
      'game-audio': 0,
      'film': 0,
      'custom': 0,
    };

    for (const template of templates) {
      counts[template.category]++;
    }

    return counts;
  }
}

// Singleton instance
export const ProjectTemplateManager = new ProjectTemplateManagerClass();

// ============ Utility Functions ============

/**
 * Get category display name.
 */
export function getCategoryDisplayName(category: TemplateCategory): string {
  const names: Record<TemplateCategory, string> = {
    'music': 'Music Production',
    'podcast': 'Podcast',
    'sound-design': 'Sound Design',
    'game-audio': 'Game Audio',
    'film': 'Film & TV',
    'custom': 'Custom',
  };
  return names[category];
}

/**
 * Get category icon (emoji).
 */
export function getCategoryIcon(category: TemplateCategory): string {
  const icons: Record<TemplateCategory, string> = {
    'music': '🎵',
    'podcast': '🎙️',
    'sound-design': '🔊',
    'game-audio': '🎮',
    'film': '🎬',
    'custom': '⚡',
  };
  return icons[category];
}
