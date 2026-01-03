/**
 * VanEQ Pro Plugin
 *
 * FabFilter-style 8-band parametric EQ with:
 * - Glass morphism UI
 * - 3D band nodes with GSAP animations
 * - WebGL spectrum analyzer
 * - Anti-aliased EQ curve rendering
 * - Micro-interactions
 */

// Main editor
export { default as VanEQProEditor } from './VanEQProEditor';

// WebGL components
export { SpectrumWebGL } from './SpectrumWebGL';
export { EQCurveWebGL } from './EQCurveWebGL';

// Animation utilities
export * from './animations';
export { useVanEQAnimations } from './useVanEQAnimations';
export { useMicroInteractions } from './useMicroInteractions';
