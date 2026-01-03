/**
 * ReelForge Badge
 *
 * Badge component:
 * - Status indicators
 * - Counters
 * - Labels
 * - Dot variant
 * - Pulse animation
 *
 * @module badge/Badge
 */

import './Badge.css';

// ============ Types ============

export type BadgeVariant = 'default' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
export type BadgeSize = 'small' | 'medium' | 'large';

export interface BadgeProps {
  /** Content */
  children?: React.ReactNode;
  /** Variant */
  variant?: BadgeVariant;
  /** Size */
  size?: BadgeSize;
  /** Dot only (no content) */
  dot?: boolean;
  /** Show pulse animation */
  pulse?: boolean;
  /** Max count (shows "99+" if exceeded) */
  max?: number;
  /** Show zero */
  showZero?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Component ============

export function Badge({
  children,
  variant = 'default',
  size = 'medium',
  dot = false,
  pulse = false,
  max = 99,
  showZero = false,
  className = '',
}: BadgeProps) {
  // Format count
  const formatContent = () => {
    if (dot) return null;

    if (typeof children === 'number') {
      if (children === 0 && !showZero) return null;
      if (children > max) return `${max}+`;
      return children;
    }

    return children;
  };

  const content = formatContent();

  // Don't render if empty and not dot
  if (content === null && !dot) return null;

  return (
    <span
      className={`badge badge--${variant} badge--${size} ${
        dot ? 'badge--dot' : ''
      } ${pulse ? 'badge--pulse' : ''} ${className}`}
    >
      {content}
      {pulse && <span className="badge__pulse" />}
    </span>
  );
}

// ============ Badge with Anchor ============

export interface BadgeAnchorProps extends BadgeProps {
  /** Element to attach badge to */
  children: React.ReactNode;
  /** Badge content */
  content?: React.ReactNode;
  /** Position */
  position?: 'top-right' | 'top-left' | 'bottom-right' | 'bottom-left';
  /** Offset */
  offset?: { x?: number; y?: number };
}

export function BadgeAnchor({
  children,
  content,
  position = 'top-right',
  offset,
  ...badgeProps
}: BadgeAnchorProps) {
  return (
    <span className={`badge-anchor badge-anchor--${position}`}>
      {children}
      <span
        className="badge-anchor__badge"
        style={{
          '--badge-offset-x': offset?.x ? `${offset.x}px` : undefined,
          '--badge-offset-y': offset?.y ? `${offset.y}px` : undefined,
        } as React.CSSProperties}
      >
        <Badge {...badgeProps}>{content}</Badge>
      </span>
    </span>
  );
}

// ============ Status Badge ============

export interface StatusBadgeProps {
  /** Status */
  status: 'online' | 'offline' | 'away' | 'busy' | 'invisible';
  /** Size */
  size?: BadgeSize;
  /** Show label */
  showLabel?: boolean;
  /** Custom class */
  className?: string;
}

const STATUS_LABELS: Record<StatusBadgeProps['status'], string> = {
  online: 'Online',
  offline: 'Offline',
  away: 'Away',
  busy: 'Busy',
  invisible: 'Invisible',
};

const STATUS_VARIANTS: Record<StatusBadgeProps['status'], BadgeVariant> = {
  online: 'success',
  offline: 'default',
  away: 'warning',
  busy: 'danger',
  invisible: 'default',
};

export function StatusBadge({
  status,
  size = 'medium',
  showLabel = false,
  className = '',
}: StatusBadgeProps) {
  return (
    <span className={`status-badge status-badge--${status} ${className}`}>
      <Badge
        variant={STATUS_VARIANTS[status]}
        size={size}
        dot
        pulse={status === 'online'}
      />
      {showLabel && (
        <span className="status-badge__label">{STATUS_LABELS[status]}</span>
      )}
    </span>
  );
}

export default Badge;
