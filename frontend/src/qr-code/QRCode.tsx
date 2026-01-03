/**
 * ReelForge QRCode
 *
 * QR Code generator:
 * - Canvas/SVG rendering
 * - Custom colors
 * - Logo/image overlay
 * - Download support
 *
 * @module qr-code/QRCode
 */

import { useRef, useEffect, useCallback } from 'react';
import './QRCode.css';

// ============ Types ============

export interface QRCodeProps {
  /** Data to encode */
  value: string;
  /** Size in pixels */
  size?: number;
  /** Error correction level */
  level?: 'L' | 'M' | 'Q' | 'H';
  /** Foreground color */
  fgColor?: string;
  /** Background color */
  bgColor?: string;
  /** Include margin */
  includeMargin?: boolean;
  /** Render as SVG or Canvas */
  renderAs?: 'svg' | 'canvas';
  /** Logo image URL */
  logoImage?: string;
  /** Logo size ratio (0-0.3) */
  logoSize?: number;
  /** Custom class */
  className?: string;
}

export interface QRCodeCanvasProps extends QRCodeProps {
  /** On render complete */
  onRender?: (canvas: HTMLCanvasElement) => void;
}

// ============ QR Matrix Generator (Simple Implementation) ============

// This is a simplified QR code generator for demonstration
// In production, use a library like 'qrcode' or 'qr.js'

interface QRMatrix {
  modules: boolean[][];
  size: number;
}

function generateQRMatrix(data: string, errorLevel: string): QRMatrix {
  // Simple hash-based pseudo QR for demo
  // Real implementation would use Reed-Solomon encoding
  const size = Math.max(21, Math.min(177, 21 + Math.floor(data.length / 10) * 4));
  const modules: boolean[][] = [];

  // Create simple pattern based on data
  const hash = simpleHash(data + errorLevel);

  for (let row = 0; row < size; row++) {
    modules[row] = [];
    for (let col = 0; col < size; col++) {
      // Finder patterns (corners)
      if (isFinderPattern(row, col, size)) {
        modules[row][col] = isFinderPatternDark(row, col, size);
      }
      // Timing patterns
      else if (row === 6 || col === 6) {
        modules[row][col] = (row + col) % 2 === 0;
      }
      // Data area
      else {
        const idx = row * size + col;
        modules[row][col] = ((hash >> (idx % 32)) & 1) === 1 || Math.sin(idx * 0.1) > 0.3;
      }
    }
  }

  return { modules, size };
}

function simpleHash(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash);
}

function isFinderPattern(row: number, col: number, size: number): boolean {
  // Top-left
  if (row < 7 && col < 7) return true;
  // Top-right
  if (row < 7 && col >= size - 7) return true;
  // Bottom-left
  if (row >= size - 7 && col < 7) return true;
  return false;
}

function isFinderPatternDark(row: number, col: number, size: number): boolean {
  // Normalize to 0-6 range
  let r = row;
  let c = col;

  if (row >= size - 7) r = row - (size - 7);
  if (col >= size - 7) c = col - (size - 7);

  // Outer border
  if (r === 0 || r === 6 || c === 0 || c === 6) return true;
  // White ring
  if (r === 1 || r === 5 || c === 1 || c === 5) return false;
  // Inner square
  if (r >= 2 && r <= 4 && c >= 2 && c <= 4) return true;

  return false;
}

// ============ QRCodeCanvas Component ============

export function QRCodeCanvas({
  value,
  size = 128,
  level = 'M',
  fgColor = '#000000',
  bgColor = '#ffffff',
  includeMargin = true,
  logoImage,
  logoSize = 0.2,
  onRender,
  className = '',
}: QRCodeCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const qr = generateQRMatrix(value, level);
    const margin = includeMargin ? 4 : 0;
    const cellSize = size / (qr.size + margin * 2);

    // Clear
    ctx.fillStyle = bgColor;
    ctx.fillRect(0, 0, size, size);

    // Draw modules
    ctx.fillStyle = fgColor;
    for (let row = 0; row < qr.size; row++) {
      for (let col = 0; col < qr.size; col++) {
        if (qr.modules[row][col]) {
          ctx.fillRect(
            (col + margin) * cellSize,
            (row + margin) * cellSize,
            cellSize,
            cellSize
          );
        }
      }
    }

    // Draw logo
    if (logoImage) {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => {
        const logoSizePx = size * logoSize;
        const logoX = (size - logoSizePx) / 2;
        const logoY = (size - logoSizePx) / 2;

        // White background for logo
        ctx.fillStyle = bgColor;
        ctx.fillRect(logoX - 4, logoY - 4, logoSizePx + 8, logoSizePx + 8);

        ctx.drawImage(img, logoX, logoY, logoSizePx, logoSizePx);
        onRender?.(canvas);
      };
      img.src = logoImage;
    } else {
      onRender?.(canvas);
    }
  }, [value, size, level, fgColor, bgColor, includeMargin, logoImage, logoSize, onRender]);

  return (
    <canvas
      ref={canvasRef}
      width={size}
      height={size}
      className={`qr-code-canvas ${className}`}
    />
  );
}

// ============ QRCodeSVG Component ============

export function QRCodeSVG({
  value,
  size = 128,
  level = 'M',
  fgColor = '#000000',
  bgColor = '#ffffff',
  includeMargin = true,
  logoImage,
  logoSize = 0.2,
  className = '',
}: QRCodeProps) {
  const qr = generateQRMatrix(value, level);
  const margin = includeMargin ? 4 : 0;
  const cellSize = size / (qr.size + margin * 2);
  const logoSizePx = size * logoSize;

  const paths: string[] = [];

  for (let row = 0; row < qr.size; row++) {
    for (let col = 0; col < qr.size; col++) {
      if (qr.modules[row][col]) {
        const x = (col + margin) * cellSize;
        const y = (row + margin) * cellSize;
        paths.push(`M${x},${y}h${cellSize}v${cellSize}h-${cellSize}z`);
      }
    }
  }

  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      className={`qr-code-svg ${className}`}
    >
      <rect width={size} height={size} fill={bgColor} />
      <path d={paths.join('')} fill={fgColor} />

      {logoImage && (
        <>
          <rect
            x={(size - logoSizePx) / 2 - 4}
            y={(size - logoSizePx) / 2 - 4}
            width={logoSizePx + 8}
            height={logoSizePx + 8}
            fill={bgColor}
          />
          <image
            x={(size - logoSizePx) / 2}
            y={(size - logoSizePx) / 2}
            width={logoSizePx}
            height={logoSizePx}
            href={logoImage}
          />
        </>
      )}
    </svg>
  );
}

// ============ QRCode Component (Auto Select) ============

export function QRCode({
  renderAs = 'canvas',
  ...props
}: QRCodeProps) {
  if (renderAs === 'svg') {
    return <QRCodeSVG {...props} />;
  }
  return <QRCodeCanvas {...props} />;
}

// ============ useQRCode Hook ============

export function useQRCode(value: string, size = 128) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  const download = useCallback(
    (filename = 'qrcode.png') => {
      if (!canvasRef.current) return;

      const link = document.createElement('a');
      link.download = filename;
      link.href = canvasRef.current.toDataURL('image/png');
      link.click();
    },
    []
  );

  const getDataURL = useCallback(() => {
    return canvasRef.current?.toDataURL('image/png') ?? null;
  }, []);

  const render = useCallback(
    (canvas: HTMLCanvasElement) => {
      canvasRef.current = canvas;
    },
    []
  );

  return {
    download,
    getDataURL,
    QRCode: (props: Omit<QRCodeCanvasProps, 'value' | 'size' | 'onRender'>) => (
      <QRCodeCanvas value={value} size={size} onRender={render} {...props} />
    ),
  };
}

export default QRCode;
