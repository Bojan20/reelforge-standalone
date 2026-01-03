/**
 * ReelForge Watermark
 *
 * Watermark overlay component:
 * - Text watermark
 * - Image watermark
 * - Repeating pattern
 * - Custom positioning
 *
 * @module watermark/Watermark
 */

import { useMemo, useEffect, useRef } from 'react';
import './Watermark.css';

// ============ Types ============

export interface WatermarkProps {
  /** Watermark text (array for multiple lines) */
  content?: string | string[];
  /** Image URL (alternative to text) */
  image?: string;
  /** Font size */
  fontSize?: number;
  /** Font color */
  fontColor?: string;
  /** Font family */
  fontFamily?: string;
  /** Font weight */
  fontWeight?: number | string;
  /** Rotation angle (degrees) */
  rotate?: number;
  /** Opacity (0-1) */
  opacity?: number;
  /** Gap between watermarks */
  gap?: [number, number];
  /** Offset from origin */
  offset?: [number, number];
  /** Z-index */
  zIndex?: number;
  /** Width of each watermark */
  width?: number;
  /** Height of each watermark */
  height?: number;
  /** Children to wrap */
  children?: React.ReactNode;
  /** Custom class */
  className?: string;
}

// ============ Watermark Component ============

export function Watermark({
  content,
  image,
  fontSize = 16,
  fontColor = 'rgba(0, 0, 0, 0.1)',
  fontFamily = 'sans-serif',
  fontWeight = 'normal',
  rotate = -22,
  opacity = 1,
  gap = [100, 100],
  offset = [0, 0],
  zIndex = 9,
  width = 120,
  height = 64,
  children,
  className = '',
}: WatermarkProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const watermarkRef = useRef<HTMLDivElement>(null);

  // Generate watermark pattern
  const watermarkUrl = useMemo(() => {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) return '';

    const ratio = window.devicePixelRatio || 1;
    const canvasWidth = (width + gap[0]) * ratio;
    const canvasHeight = (height + gap[1]) * ratio;

    canvas.width = canvasWidth;
    canvas.height = canvasHeight;

    ctx.scale(ratio, ratio);

    // Apply transformations
    ctx.translate(width / 2 + offset[0], height / 2 + offset[1]);
    ctx.rotate((rotate * Math.PI) / 180);

    if (image) {
      // Image watermark
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.src = image;
      // Note: For sync generation, we'd need to preload
      // This is simplified - in production, use async loading
    } else if (content) {
      // Text watermark
      ctx.font = `${fontWeight} ${fontSize}px ${fontFamily}`;
      ctx.fillStyle = fontColor;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';

      const lines = Array.isArray(content) ? content : [content];
      const lineHeight = fontSize * 1.4;
      const startY = -((lines.length - 1) * lineHeight) / 2;

      lines.forEach((line, index) => {
        ctx.fillText(line, 0, startY + index * lineHeight);
      });
    }

    return canvas.toDataURL();
  }, [content, image, fontSize, fontColor, fontFamily, fontWeight, rotate, width, height, gap, offset]);

  // Apply watermark
  useEffect(() => {
    if (!watermarkRef.current) return;

    watermarkRef.current.style.backgroundImage = `url(${watermarkUrl})`;
    watermarkRef.current.style.backgroundRepeat = 'repeat';
    watermarkRef.current.style.backgroundSize = `${width + gap[0]}px ${height + gap[1]}px`;
  }, [watermarkUrl, width, height, gap]);

  return (
    <div ref={containerRef} className={`watermark ${className}`}>
      {children}
      <div
        ref={watermarkRef}
        className="watermark__layer"
        style={{
          zIndex,
          opacity,
        }}
      />
    </div>
  );
}

// ============ ImageWatermark Component ============

export interface ImageWatermarkProps {
  /** Image source to watermark */
  src: string;
  /** Watermark text */
  text?: string;
  /** Watermark image URL */
  watermarkImage?: string;
  /** Position */
  position?: 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right' | 'center';
  /** Margin from edge */
  margin?: number;
  /** Opacity */
  opacity?: number;
  /** Font size (for text) */
  fontSize?: number;
  /** Font color (for text) */
  fontColor?: string;
  /** On watermarked image ready */
  onReady?: (dataUrl: string) => void;
  /** Custom class */
  className?: string;
}

export function ImageWatermark({
  src,
  text,
  watermarkImage,
  position = 'bottom-right',
  margin = 20,
  opacity = 0.5,
  fontSize = 24,
  fontColor = '#ffffff',
  onReady,
  className = '',
}: ImageWatermarkProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const img = new Image();
    img.crossOrigin = 'anonymous';

    img.onload = () => {
      canvas.width = img.width;
      canvas.height = img.height;

      // Draw original image
      ctx.drawImage(img, 0, 0);

      // Apply watermark
      ctx.globalAlpha = opacity;

      if (watermarkImage) {
        const wm = new Image();
        wm.crossOrigin = 'anonymous';
        wm.onload = () => {
          const pos = getPosition(img.width, img.height, wm.width, wm.height);
          ctx.drawImage(wm, pos.x, pos.y);
          ctx.globalAlpha = 1;
          onReady?.(canvas.toDataURL());
        };
        wm.src = watermarkImage;
      } else if (text) {
        ctx.font = `bold ${fontSize}px sans-serif`;
        ctx.fillStyle = fontColor;
        ctx.textBaseline = 'top';

        const metrics = ctx.measureText(text);
        const textWidth = metrics.width;
        const textHeight = fontSize;

        const pos = getPosition(img.width, img.height, textWidth, textHeight);

        // Add shadow for visibility
        ctx.shadowColor = 'rgba(0, 0, 0, 0.5)';
        ctx.shadowBlur = 4;
        ctx.shadowOffsetX = 2;
        ctx.shadowOffsetY = 2;

        ctx.fillText(text, pos.x, pos.y);
        ctx.globalAlpha = 1;
        onReady?.(canvas.toDataURL());
      }
    };

    img.src = src;

    function getPosition(
      imgW: number,
      imgH: number,
      wmW: number,
      wmH: number
    ): { x: number; y: number } {
      switch (position) {
        case 'top-left':
          return { x: margin, y: margin };
        case 'top-right':
          return { x: imgW - wmW - margin, y: margin };
        case 'bottom-left':
          return { x: margin, y: imgH - wmH - margin };
        case 'bottom-right':
          return { x: imgW - wmW - margin, y: imgH - wmH - margin };
        case 'center':
          return { x: (imgW - wmW) / 2, y: (imgH - wmH) / 2 };
        default:
          return { x: imgW - wmW - margin, y: imgH - wmH - margin };
      }
    }
  }, [src, text, watermarkImage, position, margin, opacity, fontSize, fontColor, onReady]);

  return (
    <canvas
      ref={canvasRef}
      className={`image-watermark ${className}`}
    />
  );
}

// ============ useWatermark Hook ============

export function useWatermark(options: Omit<WatermarkProps, 'children' | 'className'>) {
  const watermarkUrl = useMemo(() => {
    const {
      content,
      fontSize = 16,
      fontColor = 'rgba(0, 0, 0, 0.1)',
      fontFamily = 'sans-serif',
      fontWeight = 'normal',
      rotate = -22,
      gap = [100, 100],
      offset = [0, 0],
      width = 120,
      height = 64,
    } = options;

    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) return '';

    const ratio = window.devicePixelRatio || 1;
    canvas.width = (width + gap[0]) * ratio;
    canvas.height = (height + gap[1]) * ratio;

    ctx.scale(ratio, ratio);
    ctx.translate(width / 2 + offset[0], height / 2 + offset[1]);
    ctx.rotate((rotate * Math.PI) / 180);

    if (content) {
      ctx.font = `${fontWeight} ${fontSize}px ${fontFamily}`;
      ctx.fillStyle = fontColor;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';

      const lines = Array.isArray(content) ? content : [content];
      const lineHeight = fontSize * 1.4;
      const startY = -((lines.length - 1) * lineHeight) / 2;

      lines.forEach((line, index) => {
        ctx.fillText(line, 0, startY + index * lineHeight);
      });
    }

    return canvas.toDataURL();
  }, [options]);

  return { watermarkUrl };
}

export default Watermark;
