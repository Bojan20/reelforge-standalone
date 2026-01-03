/**
 * ReelForge List
 *
 * List component:
 * - Simple and interactive lists
 * - Avatars, icons, actions
 * - Selectable items
 * - Dividers
 *
 * @module list/List
 */

import './List.css';

// ============ Types ============

export interface ListProps {
  /** Dense mode */
  dense?: boolean;
  /** Show dividers */
  dividers?: boolean;
  /** Children list items */
  children: React.ReactNode;
  /** Custom class */
  className?: string;
}

export interface ListItemProps {
  /** Primary text */
  primary: React.ReactNode;
  /** Secondary text */
  secondary?: React.ReactNode;
  /** Left element (avatar, icon) */
  left?: React.ReactNode;
  /** Right element (action, badge) */
  right?: React.ReactNode;
  /** Selected state */
  selected?: boolean;
  /** Disabled */
  disabled?: boolean;
  /** Clickable */
  onClick?: () => void;
  /** Href for link */
  href?: string;
  /** Custom class */
  className?: string;
}

export interface ListSubheaderProps {
  /** Subheader text */
  children: React.ReactNode;
  /** Sticky positioning */
  sticky?: boolean;
  /** Custom class */
  className?: string;
}

// ============ List ============

export function List({
  dense = false,
  dividers = false,
  children,
  className = '',
}: ListProps) {
  return (
    <ul
      className={`list ${dense ? 'list--dense' : ''} ${dividers ? 'list--dividers' : ''} ${className}`}
      role="list"
    >
      {children}
    </ul>
  );
}

// ============ List Item ============

export function ListItem({
  primary,
  secondary,
  left,
  right,
  selected = false,
  disabled = false,
  onClick,
  href,
  className = '',
}: ListItemProps) {
  const isInteractive = onClick || href;

  const content = (
    <>
      {left && <div className="list-item__left">{left}</div>}
      <div className="list-item__content">
        <div className="list-item__primary">{primary}</div>
        {secondary && <div className="list-item__secondary">{secondary}</div>}
      </div>
      {right && <div className="list-item__right">{right}</div>}
    </>
  );

  const itemClass = `list-item ${selected ? 'list-item--selected' : ''} ${
    disabled ? 'list-item--disabled' : ''
  } ${isInteractive ? 'list-item--interactive' : ''} ${className}`;

  if (href && !disabled) {
    return (
      <li role="listitem">
        <a href={href} className={itemClass}>
          {content}
        </a>
      </li>
    );
  }

  if (onClick && !disabled) {
    return (
      <li role="listitem">
        <button type="button" className={itemClass} onClick={onClick}>
          {content}
        </button>
      </li>
    );
  }

  return (
    <li className={itemClass} role="listitem">
      {content}
    </li>
  );
}

// ============ List Subheader ============

export function ListSubheader({
  children,
  sticky = false,
  className = '',
}: ListSubheaderProps) {
  return (
    <li
      className={`list-subheader ${sticky ? 'list-subheader--sticky' : ''} ${className}`}
      role="presentation"
    >
      {children}
    </li>
  );
}

// ============ List Divider ============

export function ListDivider({ className = '' }: { className?: string }) {
  return <li className={`list-divider ${className}`} role="separator" />;
}

// ============ List Item Icon ============

export function ListItemIcon({
  children,
  className = '',
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return <div className={`list-item-icon ${className}`}>{children}</div>;
}

// ============ List Item Avatar ============

export function ListItemAvatar({
  src,
  alt = '',
  fallback,
  className = '',
}: {
  src?: string;
  alt?: string;
  fallback?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`list-item-avatar ${className}`}>
      {src ? (
        <img src={src} alt={alt} className="list-item-avatar__image" />
      ) : (
        <div className="list-item-avatar__fallback">{fallback}</div>
      )}
    </div>
  );
}

// ============ List Item Action ============

export function ListItemAction({
  children,
  className = '',
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`list-item-action ${className}`} onClick={(e) => e.stopPropagation()}>
      {children}
    </div>
  );
}

export default List;
