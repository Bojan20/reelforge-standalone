/**
 * ReelForge Empty State
 *
 * Empty state component:
 * - Customizable icon/image
 * - Title and description
 * - Action buttons
 * - Preset variants
 *
 * @module empty/Empty
 */

import './Empty.css';

// ============ Types ============

export type EmptySize = 'small' | 'medium' | 'large';

export interface EmptyProps {
  /** Custom icon or image */
  icon?: React.ReactNode;
  /** Title text */
  title?: React.ReactNode;
  /** Description text */
  description?: React.ReactNode;
  /** Action buttons */
  actions?: React.ReactNode;
  /** Size variant */
  size?: EmptySize;
  /** Custom class */
  className?: string;
  /** Children (alternative to description) */
  children?: React.ReactNode;
}

// ============ Default Icons ============

const EmptyIcon = () => (
  <svg viewBox="0 0 64 64" fill="currentColor">
    <path d="M32 4C16.536 4 4 16.536 4 32s12.536 28 28 28 28-12.536 28-28S47.464 4 32 4zm0 52C18.745 56 8 45.255 8 32S18.745 8 32 8s24 10.745 24 24-10.745 24-24 24z" opacity="0.3" />
    <path d="M32 14c-9.941 0-18 8.059-18 18s8.059 18 18 18 18-8.059 18-18-8.059-18-18-18zm0 32c-7.732 0-14-6.268-14-14s6.268-14 14-14 14 6.268 14 14-6.268 14-14 14z" opacity="0.2" />
    <circle cx="32" cy="32" r="8" opacity="0.3" />
  </svg>
);

const NoDataIcon = () => (
  <svg viewBox="0 0 64 64" fill="currentColor">
    <path d="M52 8H12c-2.2 0-4 1.8-4 4v40c0 2.2 1.8 4 4 4h40c2.2 0 4-1.8 4-4V12c0-2.2-1.8-4-4-4zm0 44H12V12h40v40z" opacity="0.3" />
    <path d="M20 24h24v4H20zM20 32h16v4H20zM20 40h20v4H20z" opacity="0.2" />
  </svg>
);

const NoSearchIcon = () => (
  <svg viewBox="0 0 64 64" fill="currentColor">
    <path d="M28 8C16.954 8 8 16.954 8 28s8.954 20 20 20c4.514 0 8.694-1.498 12.042-4.022l13.99 13.99 2.828-2.828-13.99-13.99C45.502 37.694 48 33.514 48 28c0-11.046-8.954-20-20-20zm0 36c-8.837 0-16-7.163-16-16s7.163-16 16-16 16 7.163 16 16-7.163 16-16 16z" opacity="0.3" />
    <path d="M34 26h-4v-4h-4v4h-4v4h4v4h4v-4h4z" opacity="0.2" transform="rotate(45 28 28)" />
  </svg>
);

const ErrorIcon = () => (
  <svg viewBox="0 0 64 64" fill="currentColor">
    <path d="M32 4C16.536 4 4 16.536 4 32s12.536 28 28 28 28-12.536 28-28S47.464 4 32 4zm0 52C18.745 56 8 45.255 8 32S18.745 8 32 8s24 10.745 24 24-10.745 24-24 24z" opacity="0.3" />
    <path d="M30 18h4v20h-4zM30 42h4v4h-4z" />
  </svg>
);

const NoFilesIcon = () => (
  <svg viewBox="0 0 64 64" fill="currentColor">
    <path d="M52 14H36l-4-4H12c-2.2 0-4 1.8-4 4v40c0 2.2 1.8 4 4 4h40c2.2 0 4-1.8 4-4V18c0-2.2-1.8-4-4-4zm0 40H12V14h18.34l4 4H52v36z" opacity="0.3" />
    <path d="M28 28h8v4h-8zM24 36h16v4H24z" opacity="0.2" />
  </svg>
);

const NoConnectionIcon = () => (
  <svg viewBox="0 0 64 64" fill="currentColor">
    <path d="M32 12c-11.046 0-20 8.954-20 20h4c0-8.837 7.163-16 16-16s16 7.163 16 16h4c0-11.046-8.954-20-20-20z" opacity="0.2" />
    <path d="M32 20c-6.627 0-12 5.373-12 12h4c0-4.418 3.582-8 8-8s8 3.582 8 8h4c0-6.627-5.373-12-12-12z" opacity="0.3" />
    <circle cx="32" cy="40" r="6" />
    <path d="M8 8l48 48-2.828 2.828L5.172 10.828z" opacity="0.5" />
  </svg>
);

// ============ Component ============

export function Empty({
  icon,
  title,
  description,
  actions,
  size = 'medium',
  className = '',
  children,
}: EmptyProps) {
  return (
    <div className={`empty empty--${size} ${className}`}>
      {icon !== undefined ? (
        <div className="empty__icon">{icon}</div>
      ) : (
        <div className="empty__icon">
          <EmptyIcon />
        </div>
      )}

      {title && <div className="empty__title">{title}</div>}

      {(description || children) && (
        <div className="empty__description">{description || children}</div>
      )}

      {actions && <div className="empty__actions">{actions}</div>}
    </div>
  );
}

// ============ Preset Variants ============

export interface EmptyPresetProps {
  /** Action buttons */
  actions?: React.ReactNode;
  /** Size variant */
  size?: EmptySize;
  /** Custom class */
  className?: string;
}

export function EmptyNoData({ actions, size, className }: EmptyPresetProps) {
  return (
    <Empty
      icon={<NoDataIcon />}
      title="No Data"
      description="There's no data to display yet."
      actions={actions}
      size={size}
      className={className}
    />
  );
}

export function EmptyNoResults({ actions, size, className }: EmptyPresetProps) {
  return (
    <Empty
      icon={<NoSearchIcon />}
      title="No Results"
      description="No results match your search criteria. Try adjusting your filters."
      actions={actions}
      size={size}
      className={className}
    />
  );
}

export function EmptyError({ actions, size, className }: EmptyPresetProps) {
  return (
    <Empty
      icon={<ErrorIcon />}
      title="Something Went Wrong"
      description="An error occurred while loading. Please try again."
      actions={actions}
      size={size}
      className={className}
    />
  );
}

export function EmptyNoFiles({ actions, size, className }: EmptyPresetProps) {
  return (
    <Empty
      icon={<NoFilesIcon />}
      title="No Files"
      description="This folder is empty. Upload or create new files to get started."
      actions={actions}
      size={size}
      className={className}
    />
  );
}

export function EmptyNoConnection({ actions, size, className }: EmptyPresetProps) {
  return (
    <Empty
      icon={<NoConnectionIcon />}
      title="No Connection"
      description="You appear to be offline. Check your internet connection and try again."
      actions={actions}
      size={size}
      className={className}
    />
  );
}

export default Empty;
