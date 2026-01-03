/**
 * VanEQ Pro - Filter Type Icons
 * Professional monoline SVG icons for each filter type
 */

import type { BandType } from './utils';

type Props = {
  type: BandType;
  size?: number;
  color?: string;
};

export function FilterTypeIcon({ type, size = 16, color = 'currentColor' }: Props) {
  const sw = 1.6; // strokeWidth

  switch (type) {
    case 'bell':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          {/* Bell curve - boost/cut shape */}
          <path d="M2 16 C5 16, 7 4, 12 4 C17 4, 19 16, 22 16" />
          <path d="M2 16 L22 16" opacity=".3" />
        </svg>
      );

    case 'lowShelf':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          {/* Low shelf - flat left, transition, flat right */}
          <path d="M2 8 L7 8 C9 8, 11 14, 13 16 L22 16" />
          <path d="M2 16 L22 16" opacity=".3" />
        </svg>
      );

    case 'highShelf':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          {/* High shelf - flat left, transition, flat right */}
          <path d="M2 16 L9 16 C11 16, 13 10, 15 8 L22 8" />
          <path d="M2 16 L22 16" opacity=".3" />
        </svg>
      );

    case 'lowPass':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          {/* Low pass - flat then steep rolloff */}
          <path d="M2 8 L10 8 C12 8, 14 10, 16 14 C18 18, 20 20, 22 20" />
          <path d="M2 16 L22 16" opacity=".3" />
        </svg>
      );

    case 'highPass':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          {/* High pass - steep rise then flat */}
          <path d="M2 20 C4 20, 6 18, 8 14 C10 10, 12 8, 14 8 L22 8" />
          <path d="M2 16 L22 16" opacity=".3" />
        </svg>
      );

    case 'notch':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          {/* Notch - deep narrow cut */}
          <path d="M2 8 L8 8 C10 8, 10.5 16, 12 18 C13.5 16, 14 8, 16 8 L22 8" />
          <path d="M2 16 L22 16" opacity=".3" />
        </svg>
      );

    case 'bandPass':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          {/* Band pass - peak with rolloffs on both sides */}
          <path d="M2 18 C4 18, 6 16, 8 12 C10 8, 11 6, 12 6 C13 6, 14 8, 16 12 C18 16, 20 18, 22 18" />
          <path d="M2 16 L22 16" opacity=".3" />
          {/* Vertical markers */}
          <path d="M7 16 L7 13" opacity=".4" />
          <path d="M17 16 L17 13" opacity=".4" />
        </svg>
      );

    case 'tilt':
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          {/* Tilt - diagonal line with pivot point */}
          <path d="M3 14 L21 10" />
          <circle cx="12" cy="12" r="2.5" fill={color} opacity=".5" />
          <path d="M2 16 L22 16" opacity=".3" />
        </svg>
      );

    default:
      // Default to bell
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
          <path d="M2 16 C5 16, 7 4, 12 4 C17 4, 19 16, 22 16" />
          <path d="M2 16 L22 16" opacity=".3" />
        </svg>
      );
  }
}
