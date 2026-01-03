/**
 * ReelForge Avatar
 *
 * Avatar component:
 * - Image avatars
 * - Initials fallback
 * - Status indicator
 * - Sizes and shapes
 * - Avatar groups
 *
 * @module avatar/Avatar
 */

import { useState } from 'react';
import './Avatar.css';

// ============ Types ============

export type AvatarSize = 'xs' | 'small' | 'medium' | 'large' | 'xl';
export type AvatarShape = 'circle' | 'square' | 'rounded';
export type AvatarStatus = 'online' | 'offline' | 'away' | 'busy';

export interface AvatarProps {
  /** Image source */
  src?: string;
  /** Alt text */
  alt?: string;
  /** Name (for initials fallback) */
  name?: string;
  /** Size */
  size?: AvatarSize;
  /** Shape */
  shape?: AvatarShape;
  /** Status indicator */
  status?: AvatarStatus;
  /** Custom icon fallback */
  icon?: React.ReactNode;
  /** Custom class */
  className?: string;
  /** On click */
  onClick?: () => void;
}

// ============ Helpers ============

function getInitials(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function getColorFromName(name: string): string {
  const colors = [
    '#ff6b6b', '#ff922b', '#ffd43b', '#51cf66', '#20c997',
    '#4a9eff', '#7950f2', '#e64980', '#be4bdb', '#15aabf',
  ];
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = name.charCodeAt(i) + ((hash << 5) - hash);
  }
  return colors[Math.abs(hash) % colors.length];
}

// ============ Component ============

export function Avatar({
  src,
  alt,
  name,
  size = 'medium',
  shape = 'circle',
  status,
  icon,
  className = '',
  onClick,
}: AvatarProps) {
  const [imgError, setImgError] = useState(false);

  const showImage = src && !imgError;
  const showInitials = !showImage && name;
  const showIcon = !showImage && !showInitials && icon;
  const showPlaceholder = !showImage && !showInitials && !showIcon;

  return (
    <div
      className={`avatar avatar--${size} avatar--${shape} ${
        onClick ? 'avatar--clickable' : ''
      } ${className}`}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
    >
      {/* Image */}
      {showImage && (
        <img
          src={src}
          alt={alt || name || 'Avatar'}
          className="avatar__image"
          onError={() => setImgError(true)}
        />
      )}

      {/* Initials */}
      {showInitials && (
        <span
          className="avatar__initials"
          style={{ backgroundColor: getColorFromName(name) }}
        >
          {getInitials(name)}
        </span>
      )}

      {/* Icon */}
      {showIcon && <span className="avatar__icon">{icon}</span>}

      {/* Placeholder */}
      {showPlaceholder && (
        <span className="avatar__placeholder">
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
          </svg>
        </span>
      )}

      {/* Status */}
      {status && <span className={`avatar__status avatar__status--${status}`} />}
    </div>
  );
}

// ============ Avatar Group ============

export interface AvatarGroupProps {
  /** Children avatars */
  children: React.ReactNode;
  /** Max visible avatars */
  max?: number;
  /** Size override for all avatars */
  size?: AvatarSize;
  /** Custom class */
  className?: string;
}

export function AvatarGroup({
  children,
  max,
  size,
  className = '',
}: AvatarGroupProps) {
  const avatars = Array.isArray(children) ? children : [children];
  const visibleAvatars = max ? avatars.slice(0, max) : avatars;
  const hiddenCount = max ? avatars.length - max : 0;

  return (
    <div className={`avatar-group ${size ? `avatar-group--${size}` : ''} ${className}`}>
      {visibleAvatars}
      {hiddenCount > 0 && (
        <div className={`avatar avatar--${size || 'medium'} avatar--circle avatar-group__overflow`}>
          <span className="avatar__initials">+{hiddenCount}</span>
        </div>
      )}
    </div>
  );
}

export default Avatar;
