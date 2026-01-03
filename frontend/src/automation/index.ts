/**
 * ReelForge Automation Module
 *
 * Parameter automation system:
 * - Automation lanes (SVG)
 * - GPU-accelerated curves (PixiJS)
 * - Point editing
 * - Curve interpolation
 * - Recording
 *
 * @module automation
 */

export { AutomationLane, generatePointId } from './AutomationLane';
export type {
  AutomationLaneProps,
  AutomationLaneData,
  AutomationPoint,
  CurveType,
} from './AutomationLane';

// GPU-accelerated automation curve
export { AutomationCurveGPU } from './AutomationCurveGPU';
export type { AutomationCurveGPUProps } from './AutomationCurveGPU';

export { useAutomation } from './useAutomation';
export type { UseAutomationOptions, UseAutomationReturn } from './useAutomation';
