/**
 * ReelForge Image
 *
 * Image component:
 * - Lazy loading
 * - Fallback on error
 * - Loading placeholder
 * - Zoom/lightbox
 *
 * @module image/Image
 */

import { useState, useRef, useEffect } from 'react';
import './Image.css';

// ============ Types ============

export type ImageFit = 'cover' | 'contain' | 'fill' | 'none' | 'scale-down';

export interface ImageProps {
  /** Image source */
  src: string;
  /** Alt text */
  alt: string;
  /** Width */
  width?: number | string;
  /** Height */
  height?: number | string;
  /** Object fit */
  fit?: ImageFit;
  /** Fallback image or element */
  fallback?: React.ReactNode;
  /** Placeholder while loading */
  placeholder?: React.ReactNode;
  /** Lazy loading */
  lazy?: boolean;
  /** Border radius */
  radius?: number | string;
  /** Enable click to zoom */
  zoom?: boolean;
  /** Custom class */
  className?: string;
  /** On load */
  onLoad?: () => void;
  /** On error */
  onError?: () => void;
}

// ============ Component ============

export function Image({
  src,
  alt,
  width,
  height,
  fit = 'cover',
  fallback,
  placeholder,
  lazy = true,
  radius,
  zoom = false,
  className = '',
  onLoad,
  onError,
}: ImageProps) {
  const [status, setStatus] = useState<'loading' | 'loaded' | 'error'>('loading');
  const [isZoomed, setIsZoomed] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);

  // Intersection observer for lazy loading
  useEffect(() => {
    if (!lazy || !imgRef.current) return;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const img = entry.target as HTMLImageElement;
            if (img.dataset.src) {
              img.src = img.dataset.src;
              observer.unobserve(img);
            }
          }
        });
      },
      { rootMargin: '50px' }
    );

    observer.observe(imgRef.current);

    return () => observer.disconnect();
  }, [lazy, src]);

  const handleLoad = () => {
    setStatus('loaded');
    onLoad?.();
  };

  const handleError = () => {
    setStatus('error');
    onError?.();
  };

  const style: React.CSSProperties = {
    width: typeof width === 'number' ? `${width}px` : width,
    height: typeof height === 'number' ? `${height}px` : height,
    borderRadius: typeof radius === 'number' ? `${radius}px` : radius,
  };

  const imgStyle: React.CSSProperties = {
    objectFit: fit,
  };

  return (
    <>
      <div
        className={`image ${status === 'loading' ? 'image--loading' : ''} ${
          zoom ? 'image--zoomable' : ''
        } ${className}`}
        style={style}
        onClick={zoom && status === 'loaded' ? () => setIsZoomed(true) : undefined}
      >
        {/* Loading placeholder */}
        {status === 'loading' && (
          <div className="image__placeholder">
            {placeholder || <div className="image__placeholder-default" />}
          </div>
        )}

        {/* Error fallback */}
        {status === 'error' && (
          <div className="image__fallback">
            {fallback || (
              <svg viewBox="0 0 24 24" fill="currentColor">
                <path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z" />
              </svg>
            )}
          </div>
        )}

        {/* Image */}
        <img
          ref={imgRef}
          src={lazy ? undefined : src}
          data-src={lazy ? src : undefined}
          alt={alt}
          className="image__img"
          style={imgStyle}
          onLoad={handleLoad}
          onError={handleError}
        />
      </div>

      {/* Zoom overlay */}
      {isZoomed && (
        <div className="image-zoom" onClick={() => setIsZoomed(false)}>
          <img src={src} alt={alt} className="image-zoom__img" />
          <button
            type="button"
            className="image-zoom__close"
            onClick={() => setIsZoomed(false)}
            aria-label="Close"
          >
            ×
          </button>
        </div>
      )}
    </>
  );
}

// ============ Image Gallery ============

export interface ImageGalleryProps {
  /** Image sources */
  images: { src: string; alt: string }[];
  /** Columns */
  columns?: 2 | 3 | 4 | 5;
  /** Gap between images */
  gap?: number;
  /** Image fit */
  fit?: ImageFit;
  /** Enable zoom */
  zoom?: boolean;
  /** Custom class */
  className?: string;
}

export function ImageGallery({
  images,
  columns = 3,
  gap = 8,
  fit = 'cover',
  zoom = true,
  className = '',
}: ImageGalleryProps) {
  return (
    <div
      className={`image-gallery image-gallery--cols-${columns} ${className}`}
      style={{ gap }}
    >
      {images.map((image, index) => (
        <Image
          key={index}
          src={image.src}
          alt={image.alt}
          fit={fit}
          zoom={zoom}
        />
      ))}
    </div>
  );
}

export default Image;
