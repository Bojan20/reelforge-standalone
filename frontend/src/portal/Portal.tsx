/**
 * ReelForge Portal
 *
 * Render children into different DOM node:
 * - Document body portal
 * - Custom container portal
 * - Auto-cleanup
 *
 * @module portal/Portal
 */

import { useState, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';

// ============ Types ============

export interface PortalProps {
  /** Children to render in portal */
  children: React.ReactNode;
  /** Target container (defaults to document.body) */
  container?: Element | null;
  /** Disable portal (render in place) */
  disabled?: boolean;
}

export interface PortalContainerProps {
  /** Children to render */
  children: React.ReactNode;
  /** Container ID */
  id?: string;
  /** Z-index for container */
  zIndex?: number;
  /** Custom class */
  className?: string;
}

// ============ Portal Component ============

export function Portal({ children, container, disabled = false }: PortalProps) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (disabled || !mounted) {
    return <>{children}</>;
  }

  const target = container ?? document.body;
  return createPortal(children, target);
}

// ============ PortalContainer ============

export function PortalContainer({
  children,
  id = 'rf-portal-container',
  zIndex = 1000,
  className = '',
}: PortalContainerProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [, forceUpdate] = useState({});

  useEffect(() => {
    // Check if container already exists
    let container = document.getElementById(id) as HTMLDivElement | null;

    if (!container) {
      container = document.createElement('div');
      container.id = id;
      container.className = `portal-container ${className}`;
      container.style.position = 'fixed';
      container.style.top = '0';
      container.style.left = '0';
      container.style.width = '100%';
      container.style.height = '100%';
      container.style.pointerEvents = 'none';
      container.style.zIndex = String(zIndex);
      document.body.appendChild(container);
    }

    containerRef.current = container;
    forceUpdate({});

    return () => {
      // Only remove if no children
      if (container && container.childNodes.length === 0) {
        container.remove();
      }
    };
  }, [id, zIndex, className]);

  if (!containerRef.current) {
    return null;
  }

  return createPortal(children, containerRef.current);
}

// ============ usePortal Hook ============

export interface UsePortalOptions {
  /** Container ID */
  id?: string;
  /** Auto create container */
  autoCreate?: boolean;
}

export function usePortal({ id = 'rf-portal', autoCreate = true }: UsePortalOptions = {}) {
  const [container, setContainer] = useState<HTMLElement | null>(null);

  useEffect(() => {
    let element = document.getElementById(id);

    if (!element && autoCreate) {
      element = document.createElement('div');
      element.id = id;
      document.body.appendChild(element);
    }

    setContainer(element);

    return () => {
      if (element && autoCreate && element.childNodes.length === 0) {
        element.remove();
      }
    };
  }, [id, autoCreate]);

  const render = (children: React.ReactNode) => {
    if (!container) return null;
    return createPortal(children, container);
  };

  return { container, render };
}

// ============ PortalTarget ============

export interface PortalTargetProps {
  /** Target ID for portal */
  id: string;
  /** Custom class */
  className?: string;
  /** Additional styles */
  style?: React.CSSProperties;
}

export function PortalTarget({ id, className = '', style }: PortalTargetProps) {
  return <div id={id} className={`portal-target ${className}`} style={style} />;
}

export default Portal;
