/**
 * ReelForge M9.1 Parameter Binding Tests
 */

import { describe, it, expect } from 'vitest';
import {
  normalizeForUI,
  validateOnLoad,
  validateParamsOnLoad,
  applyPatch,
  resetParam,
  getDefaultParams,
  createDescriptorMap,
  paramsEqual,
  snapToStep,
} from '../paramBinding';
import type { ParamDescriptor } from '../ParamDescriptor';

// Test descriptor
const testDescriptor: ParamDescriptor = {
  id: 'threshold',
  name: 'Threshold',
  unit: 'dB',
  min: -60,
  max: 0,
  default: -24,
  step: 1,
  fineStep: 0.5,
  scale: 'linear',
};

describe('paramBinding', () => {
  describe('normalizeForUI', () => {
    it('should clamp value to min', () => {
      expect(normalizeForUI(testDescriptor, -100)).toBe(-60);
    });

    it('should clamp value to max', () => {
      expect(normalizeForUI(testDescriptor, 10)).toBe(0);
    });

    it('should pass through valid values', () => {
      expect(normalizeForUI(testDescriptor, -30)).toBe(-30);
    });
  });

  describe('validateOnLoad', () => {
    it('should accept valid values', () => {
      const result = validateOnLoad(testDescriptor, -24);
      expect(result.valid).toBe(true);
      expect(result.error).toBeUndefined();
    });

    it('should reject values below min', () => {
      const result = validateOnLoad(testDescriptor, -100);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('below minimum');
    });

    it('should reject values above max', () => {
      const result = validateOnLoad(testDescriptor, 10);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('above maximum');
    });

    it('should reject NaN', () => {
      const result = validateOnLoad(testDescriptor, NaN);
      expect(result.valid).toBe(false);
    });

    it('should reject non-numbers', () => {
      const result = validateOnLoad(testDescriptor, 'test' as unknown as number);
      expect(result.valid).toBe(false);
    });
  });

  describe('validateParamsOnLoad', () => {
    const descriptors: ParamDescriptor[] = [
      testDescriptor,
      { ...testDescriptor, id: 'ratio', min: 1, max: 20, default: 4 },
    ];

    it('should accept valid params', () => {
      const result = validateParamsOnLoad(descriptors, {
        threshold: -30,
        ratio: 4,
      });
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('should collect multiple errors', () => {
      const result = validateParamsOnLoad(descriptors, {
        threshold: -100, // Invalid
        ratio: 50, // Invalid
      });
      expect(result.valid).toBe(false);
      expect(result.errors).toHaveLength(2);
    });

    it('should allow missing params (will use defaults)', () => {
      const result = validateParamsOnLoad(descriptors, {});
      expect(result.valid).toBe(true);
    });

    it('should skip read-only params', () => {
      const withReadOnly: ParamDescriptor[] = [
        { ...testDescriptor, readOnly: true },
      ];
      const result = validateParamsOnLoad(withReadOnly, {
        threshold: -100, // Would be invalid, but skipped
      });
      expect(result.valid).toBe(true);
    });
  });

  describe('applyPatch', () => {
    it('should immutably update a param', () => {
      const params = { threshold: -24, ratio: 4 };
      const updated = applyPatch(params, 'threshold', -30, testDescriptor);

      expect(updated.threshold).toBe(-30);
      expect(updated.ratio).toBe(4);
      expect(params.threshold).toBe(-24); // Original unchanged
    });

    it('should clamp the patched value', () => {
      const params = { threshold: -24 };
      const updated = applyPatch(params, 'threshold', -100, testDescriptor);

      expect(updated.threshold).toBe(-60);
    });
  });

  describe('resetParam', () => {
    it('should reset to default value', () => {
      const params = { threshold: -30 };
      const updated = resetParam(params, 'threshold', testDescriptor);

      expect(updated.threshold).toBe(-24);
    });
  });

  describe('getDefaultParams', () => {
    it('should return default values for all descriptors', () => {
      const descriptors: ParamDescriptor[] = [
        { ...testDescriptor, id: 'a', default: 10 },
        { ...testDescriptor, id: 'b', default: 20 },
      ];
      const defaults = getDefaultParams(descriptors);

      expect(defaults).toEqual({ a: 10, b: 20 });
    });
  });

  describe('createDescriptorMap', () => {
    it('should create a map for efficient lookup', () => {
      const descriptors = [
        { ...testDescriptor, id: 'a' },
        { ...testDescriptor, id: 'b' },
      ];
      const map = createDescriptorMap(descriptors);

      expect(map.get('a')).toBeDefined();
      expect(map.get('b')).toBeDefined();
      expect(map.get('c')).toBeUndefined();
    });
  });

  describe('paramsEqual', () => {
    it('should return true for equal objects', () => {
      expect(paramsEqual({ a: 1, b: 2 }, { a: 1, b: 2 })).toBe(true);
    });

    it('should return false for different values', () => {
      expect(paramsEqual({ a: 1 }, { a: 2 })).toBe(false);
    });

    it('should return false for different keys', () => {
      expect(paramsEqual({ a: 1 }, { b: 1 })).toBe(false);
    });
  });

  describe('snapToStep', () => {
    it('should snap to normal step', () => {
      const snapped = snapToStep(-24.3, testDescriptor, false);
      expect(snapped).toBe(-24);
    });

    it('should snap to fine step', () => {
      const snapped = snapToStep(-24.3, testDescriptor, true);
      expect(snapped).toBe(-24.5);
    });

    it('should clamp after snapping', () => {
      const snapped = snapToStep(-100, testDescriptor, false);
      expect(snapped).toBe(-60);
    });
  });
});
