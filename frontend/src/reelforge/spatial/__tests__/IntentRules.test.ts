/**
 * ReelForge Spatial System - Intent Rules Tests
 * @module reelforge/spatial/__tests__/IntentRules
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  IntentRulesManager,
  createIntentRulesManager,
  DEFAULT_INTENT_RULES,
} from '../core/IntentRules';
import type { IntentRule } from '../types';

// Test fixture for custom rule
function createCustomRule(intent: string, overrides?: Partial<IntentRule>): IntentRule {
  return {
    intent,
    wAnchor: 0.5,
    wMotion: 0.3,
    wIntent: 0.2,
    width: 0.5,
    deadzone: 0.03,
    maxPan: 1.0,
    smoothingTauMs: 50,
    lifetimeMs: 1000,
    ...overrides,
  };
}

describe('IntentRulesManager', () => {
  let manager: IntentRulesManager;

  beforeEach(() => {
    manager = new IntentRulesManager();
  });

  describe('initialization', () => {
    it('loads default rules', () => {
      const rules = manager.getAllRules();
      expect(rules.length).toBeGreaterThan(0);
    });

    it('includes DEFAULT rule', () => {
      const defaultRule = manager.getRule('DEFAULT');
      expect(defaultRule).toBeDefined();
      expect(defaultRule.intent).toBe('DEFAULT');
    });

    it('accepts custom rules in constructor', () => {
      const customRules = [
        createCustomRule('CUSTOM_INTENT_1'),
        createCustomRule('CUSTOM_INTENT_2'),
      ];

      const customManager = new IntentRulesManager(customRules);
      expect(customManager.getRule('CUSTOM_INTENT_1').intent).toBe('CUSTOM_INTENT_1');
      expect(customManager.getRule('CUSTOM_INTENT_2').intent).toBe('CUSTOM_INTENT_2');
    });

    it('merges custom rules with defaults', () => {
      const customRules = [createCustomRule('CUSTOM_ONLY')];
      const customManager = new IntentRulesManager(customRules);

      // Should have both custom and default rules
      expect(customManager.getRule('CUSTOM_ONLY').intent).toBe('CUSTOM_ONLY');
      expect(customManager.getRule('BUTTON_CLICK').intent).toBe('BUTTON_CLICK');
    });

    it('custom rules override defaults with same intent', () => {
      const customRules = [
        createCustomRule('BUTTON_CLICK', { maxPan: 0.123 }),
      ];
      const customManager = new IntentRulesManager(customRules);

      expect(customManager.getRule('BUTTON_CLICK').maxPan).toBe(0.123);
    });
  });

  describe('getRule', () => {
    it('returns exact match', () => {
      const rule = manager.getRule('BUTTON_CLICK');
      expect(rule.intent).toBe('BUTTON_CLICK');
    });

    it('returns DEFAULT for unknown intent', () => {
      const rule = manager.getRule('COMPLETELY_UNKNOWN_INTENT');
      expect(rule.intent).toBe('DEFAULT');
    });

    it('returns rule with all required properties', () => {
      const rule = manager.getRule('SPIN_START');

      expect(rule).toHaveProperty('intent');
      expect(rule).toHaveProperty('wAnchor');
      expect(rule).toHaveProperty('wMotion');
      expect(rule).toHaveProperty('wIntent');
      expect(rule).toHaveProperty('width');
      expect(rule).toHaveProperty('deadzone');
      expect(rule).toHaveProperty('maxPan');
      expect(rule).toHaveProperty('smoothingTauMs');
      expect(rule).toHaveProperty('lifetimeMs');
    });
  });

  describe('partial matching', () => {
    it('matches partial intent names', () => {
      // REEL_0_STOP should match for REEL_0_STOP_WITH_WILD
      const rule = manager.getRule('REEL_0_STOP_WILD');

      // Should find a reel-related rule, not DEFAULT
      // Note: depends on implementation - checking it doesn't fall back unnecessarily
      expect(rule.intent).not.toBe('DEFAULT');
    });

    it('prefers longer matches', () => {
      // Add specific rules for testing
      manager.setRule(createCustomRule('WIN', { priority: 1 }));
      manager.setRule(createCustomRule('WIN_BIG', { priority: 2 }));

      const rule = manager.getRule('WIN_BIG_CELEBRATION');
      // Should match WIN_BIG (longer) not WIN
      expect(rule.intent).toBe('WIN_BIG');
    });

    it('caches partial matches', () => {
      // First lookup
      manager.getRule('SOME_UNKNOWN_PARTIAL_MATCH');

      // Should be cached now
      const stats = manager.getCacheStats();
      expect(stats.cacheSize).toBeGreaterThan(0);
    });

    it('returns consistent results for partial matches', () => {
      const intent = 'REEL_2_STOP_FEATURE';
      const result1 = manager.getRule(intent);
      const result2 = manager.getRule(intent);

      expect(result1.intent).toBe(result2.intent);
    });
  });

  describe('setRule', () => {
    it('adds new rule', () => {
      const newRule = createCustomRule('NEW_TEST_RULE');
      manager.setRule(newRule);

      expect(manager.getRule('NEW_TEST_RULE').intent).toBe('NEW_TEST_RULE');
    });

    it('updates existing rule', () => {
      const updatedRule = createCustomRule('BUTTON_CLICK', { maxPan: 0.999 });
      manager.setRule(updatedRule);

      expect(manager.getRule('BUTTON_CLICK').maxPan).toBe(0.999);
    });

    it('clears partial match cache after setRule', () => {
      // Prime the cache
      manager.getRule('SOME_CACHED_INTENT');
      const statsBefore = manager.getCacheStats();

      // Add rule
      manager.setRule(createCustomRule('NEW_RULE'));
      const statsAfter = manager.getCacheStats();

      expect(statsAfter.cacheSize).toBe(0);
    });
  });

  describe('removeRule', () => {
    it('removes rule', () => {
      manager.setRule(createCustomRule('REMOVABLE_RULE'));
      expect(manager.getRule('REMOVABLE_RULE').intent).toBe('REMOVABLE_RULE');

      manager.removeRule('REMOVABLE_RULE');
      expect(manager.getRule('REMOVABLE_RULE').intent).toBe('DEFAULT');
    });

    it('cannot remove DEFAULT rule', () => {
      manager.removeRule('DEFAULT');
      expect(manager.getRule('DEFAULT').intent).toBe('DEFAULT');
    });

    it('clears cache after removeRule', () => {
      manager.getRule('SOME_INTENT');
      manager.removeRule('BUTTON_CLICK');

      expect(manager.getCacheStats().cacheSize).toBe(0);
    });
  });

  describe('getAllRules', () => {
    it('returns all rules', () => {
      const rules = manager.getAllRules();
      expect(rules.length).toBeGreaterThanOrEqual(DEFAULT_INTENT_RULES.length);
    });

    it('includes added rules', () => {
      manager.setRule(createCustomRule('EXTRA_RULE'));
      const rules = manager.getAllRules();
      const found = rules.find(r => r.intent === 'EXTRA_RULE');
      expect(found).toBeDefined();
    });
  });

  describe('getRulesForBus', () => {
    it('returns rules', () => {
      const rules = manager.getRulesForBus('FX');
      expect(rules.length).toBeGreaterThan(0);
    });
  });

  describe('resetToDefaults', () => {
    it('restores default rules', () => {
      // Add custom rules
      manager.setRule(createCustomRule('CUSTOM_1'));
      manager.setRule(createCustomRule('CUSTOM_2'));

      // Modify existing
      manager.setRule(createCustomRule('BUTTON_CLICK', { maxPan: 0.111 }));

      // Reset
      manager.resetToDefaults();

      // Custom should be gone
      expect(manager.getRule('CUSTOM_1').intent).toBe('DEFAULT');
      expect(manager.getRule('CUSTOM_2').intent).toBe('DEFAULT');

      // Original should be restored
      const original = DEFAULT_INTENT_RULES.find(r => r.intent === 'BUTTON_CLICK');
      expect(manager.getRule('BUTTON_CLICK').maxPan).toBe(original?.maxPan);
    });

    it('clears cache', () => {
      manager.getRule('SOME_INTENT');
      manager.resetToDefaults();
      expect(manager.getCacheStats().cacheSize).toBe(0);
    });
  });

  describe('clearCache', () => {
    it('clears partial match cache', () => {
      // Prime cache
      manager.getRule('INTENT_A');
      manager.getRule('INTENT_B');
      manager.getRule('INTENT_C');

      expect(manager.getCacheStats().cacheSize).toBeGreaterThan(0);

      manager.clearCache();
      expect(manager.getCacheStats().cacheSize).toBe(0);
    });
  });

  describe('getCacheStats', () => {
    it('returns cache size and rules count', () => {
      const stats = manager.getCacheStats();

      expect(stats).toHaveProperty('cacheSize');
      expect(stats).toHaveProperty('rulesCount');
      expect(typeof stats.cacheSize).toBe('number');
      expect(typeof stats.rulesCount).toBe('number');
    });

    it('reflects actual state', () => {
      const initialStats = manager.getCacheStats();

      // Add rules
      manager.setRule(createCustomRule('RULE_1'));
      manager.setRule(createCustomRule('RULE_2'));

      const afterAddStats = manager.getCacheStats();
      expect(afterAddStats.rulesCount).toBe(initialStats.rulesCount + 2);

      // Prime cache
      manager.getRule('UNKNOWN_FOR_CACHE');
      expect(manager.getCacheStats().cacheSize).toBeGreaterThan(0);
    });
  });
});

describe('DEFAULT_INTENT_RULES', () => {
  it('is an array', () => {
    expect(Array.isArray(DEFAULT_INTENT_RULES)).toBe(true);
  });

  it('has minimum required rules', () => {
    expect(DEFAULT_INTENT_RULES.length).toBeGreaterThanOrEqual(10);
  });

  it('includes DEFAULT rule', () => {
    const defaultRule = DEFAULT_INTENT_RULES.find(r => r.intent === 'DEFAULT');
    expect(defaultRule).toBeDefined();
  });

  it('all rules have valid structure', () => {
    for (const rule of DEFAULT_INTENT_RULES) {
      expect(rule.intent).toBeTruthy();
      expect(typeof rule.wAnchor).toBe('number');
      expect(typeof rule.wMotion).toBe('number');
      expect(typeof rule.wIntent).toBe('number');
      expect(typeof rule.width).toBe('number');
      expect(typeof rule.deadzone).toBe('number');
      expect(typeof rule.maxPan).toBe('number');
      expect(typeof rule.smoothingTauMs).toBe('number');
      expect(typeof rule.lifetimeMs).toBe('number');
    }
  });

  it('weights sum to approximately 1', () => {
    for (const rule of DEFAULT_INTENT_RULES) {
      const sum = rule.wAnchor + rule.wMotion + rule.wIntent;
      expect(sum).toBeCloseTo(1, 1);
    }
  });

  it('values are in valid ranges', () => {
    for (const rule of DEFAULT_INTENT_RULES) {
      expect(rule.wAnchor).toBeGreaterThanOrEqual(0);
      expect(rule.wAnchor).toBeLessThanOrEqual(1);
      expect(rule.wMotion).toBeGreaterThanOrEqual(0);
      expect(rule.wMotion).toBeLessThanOrEqual(1);
      expect(rule.wIntent).toBeGreaterThanOrEqual(0);
      expect(rule.wIntent).toBeLessThanOrEqual(1);
      expect(rule.width).toBeGreaterThanOrEqual(0);
      expect(rule.width).toBeLessThanOrEqual(1);
      expect(rule.deadzone).toBeGreaterThanOrEqual(0);
      expect(rule.deadzone).toBeLessThanOrEqual(0.5);
      expect(rule.maxPan).toBeGreaterThan(0);
      expect(rule.maxPan).toBeLessThanOrEqual(1);
      expect(rule.smoothingTauMs).toBeGreaterThan(0);
      expect(rule.lifetimeMs).toBeGreaterThan(0);
    }
  });

  describe('rule categories', () => {
    const categories = {
      UI: ['BUTTON_CLICK', 'SPIN_BUTTON', 'UI_OPEN', 'UI_CLOSE', 'MENU_ITEM_HOVER'],
      REELS: ['SPIN_START', 'REEL_STOP', 'REEL_0_STOP', 'ANTICIPATION'],
      WINS: ['WIN', 'BIG_WIN', 'MEGA_WIN'],
    };

    it.each(Object.entries(categories))('has %s category rules', (_, intents) => {
      for (const intent of intents) {
        const rule = DEFAULT_INTENT_RULES.find(r => r.intent === intent);
        expect(rule).toBeDefined();
      }
    });
  });
});

describe('createIntentRulesManager', () => {
  it('creates manager with defaults', () => {
    const manager = createIntentRulesManager();
    expect(manager).toBeInstanceOf(IntentRulesManager);
    expect(manager.getAllRules().length).toBeGreaterThan(0);
  });

  it('creates manager with custom rules', () => {
    const customRules = [createCustomRule('FACTORY_CUSTOM')];
    const manager = createIntentRulesManager(customRules);

    expect(manager.getRule('FACTORY_CUSTOM').intent).toBe('FACTORY_CUSTOM');
  });
});

describe('performance characteristics', () => {
  let manager: IntentRulesManager;

  beforeEach(() => {
    manager = new IntentRulesManager();
  });

  it('exact match is fast (O(1))', () => {
    // Warm up
    manager.getRule('BUTTON_CLICK');

    const start = performance.now();
    for (let i = 0; i < 1000; i++) {
      manager.getRule('BUTTON_CLICK');
    }
    const elapsed = performance.now() - start;

    // Should complete in under 10ms for 1000 lookups
    expect(elapsed).toBeLessThan(10);
  });

  it('cached partial match is fast', () => {
    // First call populates cache
    manager.getRule('SOME_UNKNOWN_INTENT_XYZ');

    const start = performance.now();
    for (let i = 0; i < 1000; i++) {
      manager.getRule('SOME_UNKNOWN_INTENT_XYZ');
    }
    const elapsed = performance.now() - start;

    // Cached lookups should be very fast
    expect(elapsed).toBeLessThan(10);
  });

  it('cache grows with unique lookups', () => {
    for (let i = 0; i < 100; i++) {
      manager.getRule(`UNIQUE_INTENT_${i}`);
    }

    expect(manager.getCacheStats().cacheSize).toBe(100);
  });
});

describe('edge cases', () => {
  let manager: IntentRulesManager;

  beforeEach(() => {
    manager = new IntentRulesManager();
  });

  it('handles empty string intent', () => {
    const rule = manager.getRule('');
    expect(rule.intent).toBe('DEFAULT');
  });

  it('handles very long intent names', () => {
    const longIntent = 'A'.repeat(1000);
    const rule = manager.getRule(longIntent);
    expect(rule).toBeDefined();
  });

  it('handles special characters in intent', () => {
    const specialIntent = 'INTENT_WITH-SPECIAL.CHARS@123';
    const rule = manager.getRule(specialIntent);
    expect(rule).toBeDefined();
  });

  it('handles unicode in intent', () => {
    const unicodeIntent = 'INTENT_🎰_SLOT';
    const rule = manager.getRule(unicodeIntent);
    expect(rule).toBeDefined();
  });

  it('setRule with same intent twice keeps only one', () => {
    const rulesBefore = manager.getAllRules().length;

    manager.setRule(createCustomRule('DUPLICATE_TEST', { priority: 1 }));
    const rulesAfterFirst = manager.getAllRules().length;

    manager.setRule(createCustomRule('DUPLICATE_TEST', { priority: 2 }));
    const rulesAfterSecond = manager.getAllRules().length;

    expect(rulesAfterSecond).toBe(rulesAfterFirst);
    expect(manager.getRule('DUPLICATE_TEST').priority).toBe(2);
  });
});
