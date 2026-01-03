/**
 * ActionTemplates unit tests
 */

import { describe, it, expect } from 'vitest';
import { ACTION_TEMPLATES } from './ActionTemplates';

describe('ACTION_TEMPLATES', () => {
  it('contains 5 predefined templates', () => {
    expect(ACTION_TEMPLATES).toHaveLength(5);
  });

  it('has Play SFX One-shot template', () => {
    const template = ACTION_TEMPLATES.find((t) => t.id === 'play-sfx-oneshot');
    expect(template).toBeDefined();
    expect(template!.action).toEqual({
      type: 'Play',
      assetId: '',
      bus: 'SFX',
      gain: 1.0,
      loop: false,
    });
    expect(template!.focusAssetPicker).toBe(true);
  });

  it('has Play Loop (SFX) template', () => {
    const template = ACTION_TEMPLATES.find((t) => t.id === 'play-sfx-loop');
    expect(template).toBeDefined();
    expect(template!.action).toEqual({
      type: 'Play',
      assetId: '',
      bus: 'SFX',
      gain: 1.0,
      loop: true,
    });
    expect(template!.focusAssetPicker).toBe(true);
  });

  it('has Play Music Loop template', () => {
    const template = ACTION_TEMPLATES.find((t) => t.id === 'play-music-loop');
    expect(template).toBeDefined();
    expect(template!.action).toEqual({
      type: 'Play',
      assetId: '',
      bus: 'Music',
      gain: 1.0,
      loop: true,
    });
    expect(template!.focusAssetPicker).toBe(true);
  });

  it('has Duck Music template', () => {
    const template = ACTION_TEMPLATES.find((t) => t.id === 'duck-music');
    expect(template).toBeDefined();
    expect(template!.action).toEqual({
      type: 'SetBusGain',
      bus: 'Music',
      gain: 0.35,
    });
    expect(template!.focusAssetPicker).toBe(false);
  });

  it('has StopAll template', () => {
    const template = ACTION_TEMPLATES.find((t) => t.id === 'stop-all');
    expect(template).toBeDefined();
    expect(template!.action).toEqual({
      type: 'StopAll',
    });
    expect(template!.focusAssetPicker).toBe(false);
  });

  it('all templates have required fields', () => {
    for (const template of ACTION_TEMPLATES) {
      expect(template.id).toBeDefined();
      expect(template.label).toBeDefined();
      expect(template.icon).toBeDefined();
      expect(template.description).toBeDefined();
      expect(template.action).toBeDefined();
      expect(template.action.type).toBeDefined();
    }
  });

  it('all template IDs are unique', () => {
    const ids = ACTION_TEMPLATES.map((t) => t.id);
    const uniqueIds = new Set(ids);
    expect(uniqueIds.size).toBe(ids.length);
  });
});
