/**
 * ReelForge Anchor
 *
 * Page anchor navigation:
 * - Automatic section detection
 * - Smooth scrolling
 * - Active state tracking
 * - Fixed positioning
 *
 * @module anchor/Anchor
 */

import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import './Anchor.css';

// ============ Types ============

export interface AnchorLink {
  key: string;
  href: string;
  title: React.ReactNode;
  children?: AnchorLink[];
}

export interface AnchorProps {
  /** Links */
  items: AnchorLink[];
  /** Offset from top (px) */
  offsetTop?: number;
  /** Target container */
  targetOffset?: number;
  /** Show ink indicator */
  showInk?: boolean;
  /** On link change */
  onChange?: (activeLink: string) => void;
  /** On link click */
  onClick?: (e: React.MouseEvent, link: AnchorLink) => void;
  /** Get container */
  getContainer?: () => HTMLElement | Window;
  /** Affix position */
  affix?: boolean;
  /** Custom class */
  className?: string;
}

// ============ Anchor Component ============

export function Anchor({
  items,
  offsetTop = 0,
  targetOffset = 0,
  showInk = true,
  onChange,
  onClick,
  getContainer = () => window,
  affix = true,
  className = '',
}: AnchorProps) {
  const [activeLink, setActiveLink] = useState<string>('');
  const [inkTop, setInkTop] = useState(0);
  const containerRef = useRef<HTMLDivElement>(null);
  const linksRef = useRef<Map<string, HTMLElement>>(new Map());

  // Collect all hrefs
  const allHrefs = useMemo(() => {
    const hrefs: string[] = [];
    const collect = (links: AnchorLink[]) => {
      for (const link of links) {
        hrefs.push(link.href);
        if (link.children) collect(link.children);
      }
    };
    collect(items);
    return hrefs;
  }, [items]);

  // Get section positions
  const getSectionPositions = useCallback(() => {
    const container = getContainer();
    const scrollTop =
      container === window
        ? window.pageYOffset
        : (container as HTMLElement).scrollTop;

    const positions = allHrefs.map((href) => {
      const id = href.replace(/^#/, '');
      const element = document.getElementById(id);
      if (!element) return { href, top: Infinity };

      const rect = element.getBoundingClientRect();
      const top =
        container === window
          ? rect.top + scrollTop
          : rect.top - (container as HTMLElement).getBoundingClientRect().top + scrollTop;

      return { href, top };
    });

    return positions;
  }, [allHrefs, getContainer]);

  // Update active link
  const updateActiveLink = useCallback(() => {
    const container = getContainer();
    const scrollTop =
      container === window
        ? window.pageYOffset
        : (container as HTMLElement).scrollTop;

    const positions = getSectionPositions();
    const threshold = scrollTop + offsetTop + targetOffset + 10;

    let active = '';
    for (const { href, top } of positions) {
      if (top <= threshold) {
        active = href;
      } else {
        break;
      }
    }

    if (active && active !== activeLink) {
      setActiveLink(active);
      onChange?.(active);

      // Update ink position
      const linkElement = linksRef.current.get(active);
      if (linkElement && containerRef.current) {
        const containerRect = containerRef.current.getBoundingClientRect();
        const linkRect = linkElement.getBoundingClientRect();
        setInkTop(linkRect.top - containerRect.top + linkRect.height / 2);
      }
    }
  }, [getContainer, getSectionPositions, offsetTop, targetOffset, activeLink, onChange]);

  // Handle link click
  const handleLinkClick = useCallback(
    (e: React.MouseEvent, link: AnchorLink) => {
      e.preventDefault();
      onClick?.(e, link);

      const id = link.href.replace(/^#/, '');
      const element = document.getElementById(id);
      if (!element) return;

      const container = getContainer();
      const scrollTop =
        container === window
          ? window.pageYOffset
          : (container as HTMLElement).scrollTop;

      const rect = element.getBoundingClientRect();
      const top =
        container === window
          ? rect.top + scrollTop - offsetTop
          : rect.top -
            (container as HTMLElement).getBoundingClientRect().top +
            scrollTop -
            offsetTop;

      if (container === window) {
        window.scrollTo({ top, behavior: 'smooth' });
      } else {
        (container as HTMLElement).scrollTo({ top, behavior: 'smooth' });
      }

      setActiveLink(link.href);
      onChange?.(link.href);
    },
    [onClick, getContainer, offsetTop, onChange]
  );

  // Register link ref
  const registerLink = useCallback((href: string, element: HTMLElement | null) => {
    if (element) {
      linksRef.current.set(href, element);
    } else {
      linksRef.current.delete(href);
    }
  }, []);

  // Listen to scroll
  useEffect(() => {
    const container = getContainer();

    const handleScroll = () => {
      requestAnimationFrame(updateActiveLink);
    };

    container.addEventListener('scroll', handleScroll, { passive: true });
    updateActiveLink();

    return () => {
      container.removeEventListener('scroll', handleScroll);
    };
  }, [getContainer, updateActiveLink]);

  // Render links recursively
  const renderLinks = (links: AnchorLink[], level = 0) => {
    return links.map((link) => (
      <div key={link.key} className="anchor__item" style={{ paddingLeft: level * 16 }}>
        <a
          ref={(el) => registerLink(link.href, el)}
          href={link.href}
          className={`anchor__link ${activeLink === link.href ? 'anchor__link--active' : ''}`}
          onClick={(e) => handleLinkClick(e, link)}
        >
          {link.title}
        </a>
        {link.children && link.children.length > 0 && (
          <div className="anchor__children">{renderLinks(link.children, level + 1)}</div>
        )}
      </div>
    ));
  };

  return (
    <div
      ref={containerRef}
      className={`anchor ${affix ? 'anchor--affix' : ''} ${className}`}
      style={affix ? { top: offsetTop } : undefined}
    >
      {showInk && (
        <div className="anchor__ink">
          <span
            className="anchor__ink-ball"
            style={{ top: inkTop, opacity: activeLink ? 1 : 0 }}
          />
        </div>
      )}
      <div className="anchor__items">{renderLinks(items)}</div>
    </div>
  );
}

// ============ useAnchor Hook ============

export function useAnchor(sectionIds: string[]) {
  const [activeSection, setActiveSection] = useState<string>('');

  useEffect(() => {
    const handleScroll = () => {
      const scrollTop = window.pageYOffset;

      let active = '';
      for (const id of sectionIds) {
        const element = document.getElementById(id);
        if (element) {
          const rect = element.getBoundingClientRect();
          const top = rect.top + scrollTop;
          if (top <= scrollTop + 100) {
            active = id;
          }
        }
      }

      if (active !== activeSection) {
        setActiveSection(active);
      }
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    handleScroll();

    return () => window.removeEventListener('scroll', handleScroll);
  }, [sectionIds, activeSection]);

  const scrollTo = useCallback((id: string) => {
    const element = document.getElementById(id);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth' });
    }
  }, []);

  return { activeSection, scrollTo };
}

export default Anchor;
