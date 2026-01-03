/**
 * ReelForge Cropper
 *
 * Image cropping component:
 * - Drag to position
 * - Resize handles
 * - Aspect ratio lock
 * - Zoom support
 * - Rotation
 *
 * @module cropper/Cropper
 */

import { useState, useRef, useCallback, useEffect } from 'react';
import './Cropper.css';

// ============ Types ============

export interface CropArea {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface CropperProps {
  /** Image source */
  src: string;
  /** Aspect ratio (width/height) */
  aspectRatio?: number;
  /** Initial crop area (0-1 normalized) */
  initialCrop?: CropArea;
  /** On crop change */
  onChange?: (crop: CropArea) => void;
  /** On crop complete */
  onComplete?: (croppedImage: string, crop: CropArea) => void;
  /** Minimum crop size */
  minWidth?: number;
  minHeight?: number;
  /** Show grid */
  showGrid?: boolean;
  /** Grid type */
  gridType?: 'rule-of-thirds' | 'grid' | 'none';
  /** Allow rotation */
  allowRotation?: boolean;
  /** Rotation angle */
  rotation?: number;
  /** On rotation change */
  onRotationChange?: (rotation: number) => void;
  /** Zoom level */
  zoom?: number;
  /** On zoom change */
  onZoomChange?: (zoom: number) => void;
  /** Custom class */
  className?: string;
}

export interface CropperResult {
  /** Cropped image data URL */
  dataUrl: string;
  /** Crop area in pixels */
  cropArea: CropArea;
  /** Original image dimensions */
  originalSize: { width: number; height: number };
}

// ============ Cropper Component ============

export function Cropper({
  src,
  aspectRatio,
  initialCrop,
  onChange,
  onComplete,
  minWidth = 50,
  minHeight = 50,
  showGrid = true,
  gridType = 'rule-of-thirds',
  className = '',
}: CropperProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const imageRef = useRef<HTMLImageElement>(null);

  const [imageLoaded, setImageLoaded] = useState(false);
  const [, setImageDimensions] = useState({ width: 0, height: 0 });

  const [crop, setCrop] = useState<CropArea>(
    initialCrop || { x: 0.1, y: 0.1, width: 0.8, height: 0.8 }
  );

  const [dragging, setDragging] = useState<'move' | 'resize' | null>(null);
  const [resizeHandle, setResizeHandle] = useState<string | null>(null);
  const dragStart = useRef({ x: 0, y: 0, crop: crop });

  // Handle image load
  const handleImageLoad = useCallback(() => {
    if (imageRef.current) {
      setImageDimensions({
        width: imageRef.current.naturalWidth,
        height: imageRef.current.naturalHeight,
      });
      setImageLoaded(true);
    }
  }, []);

  // Convert normalized to pixel coordinates
  const toPixels = useCallback(
    (normalizedCrop: CropArea) => {
      if (!containerRef.current) return { x: 0, y: 0, width: 0, height: 0 };
      const rect = containerRef.current.getBoundingClientRect();
      return {
        x: normalizedCrop.x * rect.width,
        y: normalizedCrop.y * rect.height,
        width: normalizedCrop.width * rect.width,
        height: normalizedCrop.height * rect.height,
      };
    },
    []
  );

  // Convert pixel to normalized coordinates (reserved for future use)
  const _toNormalized = useCallback(
    (pixelCrop: CropArea) => {
      if (!containerRef.current) return { x: 0, y: 0, width: 0, height: 0 };
      const rect = containerRef.current.getBoundingClientRect();
      return {
        x: pixelCrop.x / rect.width,
        y: pixelCrop.y / rect.height,
        width: pixelCrop.width / rect.width,
        height: pixelCrop.height / rect.height,
      };
    },
    []
  );
  void _toNormalized;

  // Constrain crop to bounds and aspect ratio
  const constrainCrop = useCallback(
    (newCrop: CropArea): CropArea => {
      let { x, y, width, height } = newCrop;

      // Apply aspect ratio
      if (aspectRatio) {
        const currentRatio = width / height;
        if (currentRatio > aspectRatio) {
          width = height * aspectRatio;
        } else {
          height = width / aspectRatio;
        }
      }

      // Constrain to bounds
      x = Math.max(0, Math.min(1 - width, x));
      y = Math.max(0, Math.min(1 - height, y));
      width = Math.min(width, 1 - x);
      height = Math.min(height, 1 - y);

      return { x, y, width, height };
    },
    [aspectRatio]
  );

  // Handle mouse down on crop area
  const handleCropMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      setDragging('move');
      dragStart.current = {
        x: e.clientX,
        y: e.clientY,
        crop: { ...crop },
      };
    },
    [crop]
  );

  // Handle mouse down on resize handle
  const handleResizeMouseDown = useCallback(
    (e: React.MouseEvent, handle: string) => {
      e.preventDefault();
      e.stopPropagation();
      setDragging('resize');
      setResizeHandle(handle);
      dragStart.current = {
        x: e.clientX,
        y: e.clientY,
        crop: { ...crop },
      };
    },
    [crop]
  );

  // Handle mouse move
  useEffect(() => {
    if (!dragging) return;

    const handleMouseMove = (e: MouseEvent) => {
      if (!containerRef.current) return;

      const rect = containerRef.current.getBoundingClientRect();
      const deltaX = (e.clientX - dragStart.current.x) / rect.width;
      const deltaY = (e.clientY - dragStart.current.y) / rect.height;
      const startCrop = dragStart.current.crop;

      let newCrop: CropArea;

      if (dragging === 'move') {
        newCrop = {
          ...startCrop,
          x: startCrop.x + deltaX,
          y: startCrop.y + deltaY,
        };
      } else {
        // Resize
        newCrop = { ...startCrop };

        if (resizeHandle?.includes('e')) {
          newCrop.width = Math.max(minWidth / rect.width, startCrop.width + deltaX);
        }
        if (resizeHandle?.includes('w')) {
          const newWidth = Math.max(minWidth / rect.width, startCrop.width - deltaX);
          newCrop.x = startCrop.x + (startCrop.width - newWidth);
          newCrop.width = newWidth;
        }
        if (resizeHandle?.includes('s')) {
          newCrop.height = Math.max(minHeight / rect.height, startCrop.height + deltaY);
        }
        if (resizeHandle?.includes('n')) {
          const newHeight = Math.max(minHeight / rect.height, startCrop.height - deltaY);
          newCrop.y = startCrop.y + (startCrop.height - newHeight);
          newCrop.height = newHeight;
        }
      }

      const constrained = constrainCrop(newCrop);
      setCrop(constrained);
      onChange?.(constrained);
    };

    const handleMouseUp = () => {
      setDragging(null);
      setResizeHandle(null);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [dragging, resizeHandle, constrainCrop, onChange, minWidth, minHeight]);

  // Get cropped image
  const getCroppedImage = useCallback((): Promise<CropperResult> => {
    return new Promise((resolve, reject) => {
      if (!imageRef.current) {
        reject(new Error('Image not loaded'));
        return;
      }

      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        reject(new Error('Canvas context not available'));
        return;
      }

      const img = imageRef.current;
      const pixelCrop = {
        x: crop.x * img.naturalWidth,
        y: crop.y * img.naturalHeight,
        width: crop.width * img.naturalWidth,
        height: crop.height * img.naturalHeight,
      };

      canvas.width = pixelCrop.width;
      canvas.height = pixelCrop.height;

      ctx.drawImage(
        img,
        pixelCrop.x,
        pixelCrop.y,
        pixelCrop.width,
        pixelCrop.height,
        0,
        0,
        pixelCrop.width,
        pixelCrop.height
      );

      resolve({
        dataUrl: canvas.toDataURL('image/png'),
        cropArea: pixelCrop,
        originalSize: {
          width: img.naturalWidth,
          height: img.naturalHeight,
        },
      });
    });
  }, [crop]);

  // Export getCroppedImage on complete
  useEffect(() => {
    if (onComplete && imageLoaded) {
      getCroppedImage().then((result) => {
        onComplete(result.dataUrl, result.cropArea);
      });
    }
  }, [crop, imageLoaded, onComplete, getCroppedImage]);

  const pixelCrop = toPixels(crop);

  // Render grid
  const renderGrid = () => {
    if (!showGrid || gridType === 'none') return null;

    if (gridType === 'rule-of-thirds') {
      return (
        <div className="cropper__grid cropper__grid--thirds">
          <div className="cropper__grid-line cropper__grid-line--h1" />
          <div className="cropper__grid-line cropper__grid-line--h2" />
          <div className="cropper__grid-line cropper__grid-line--v1" />
          <div className="cropper__grid-line cropper__grid-line--v2" />
        </div>
      );
    }

    return (
      <div className="cropper__grid cropper__grid--full">
        {Array.from({ length: 9 }).map((_, i) => (
          <div key={i} className="cropper__grid-cell" />
        ))}
      </div>
    );
  };

  return (
    <div ref={containerRef} className={`cropper ${className}`}>
      <img
        ref={imageRef}
        src={src}
        alt="Crop target"
        className="cropper__image"
        onLoad={handleImageLoad}
        draggable={false}
      />

      {imageLoaded && (
        <>
          {/* Overlay */}
          <div className="cropper__overlay">
            <div
              className="cropper__overlay-top"
              style={{ height: pixelCrop.y }}
            />
            <div
              className="cropper__overlay-left"
              style={{
                top: pixelCrop.y,
                height: pixelCrop.height,
                width: pixelCrop.x,
              }}
            />
            <div
              className="cropper__overlay-right"
              style={{
                top: pixelCrop.y,
                height: pixelCrop.height,
                left: pixelCrop.x + pixelCrop.width,
              }}
            />
            <div
              className="cropper__overlay-bottom"
              style={{ top: pixelCrop.y + pixelCrop.height }}
            />
          </div>

          {/* Crop area */}
          <div
            className="cropper__crop-area"
            style={{
              left: pixelCrop.x,
              top: pixelCrop.y,
              width: pixelCrop.width,
              height: pixelCrop.height,
            }}
            onMouseDown={handleCropMouseDown}
          >
            {renderGrid()}

            {/* Resize handles */}
            {['n', 'e', 's', 'w', 'ne', 'se', 'sw', 'nw'].map((handle) => (
              <div
                key={handle}
                className={`cropper__handle cropper__handle--${handle}`}
                onMouseDown={(e) => handleResizeMouseDown(e, handle)}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

// ============ useCropper Hook ============

export interface UseCropperOptions {
  aspectRatio?: number;
  initialCrop?: CropArea;
}

export function useCropper(options: UseCropperOptions = {}) {
  const [crop, setCrop] = useState<CropArea>(
    options.initialCrop || { x: 0.1, y: 0.1, width: 0.8, height: 0.8 }
  );
  const imageRef = useRef<HTMLImageElement | null>(null);

  const getCroppedImage = useCallback(async (): Promise<string | null> => {
    if (!imageRef.current) return null;

    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;

    const img = imageRef.current;
    const pixelCrop = {
      x: crop.x * img.naturalWidth,
      y: crop.y * img.naturalHeight,
      width: crop.width * img.naturalWidth,
      height: crop.height * img.naturalHeight,
    };

    canvas.width = pixelCrop.width;
    canvas.height = pixelCrop.height;

    ctx.drawImage(
      img,
      pixelCrop.x,
      pixelCrop.y,
      pixelCrop.width,
      pixelCrop.height,
      0,
      0,
      pixelCrop.width,
      pixelCrop.height
    );

    return canvas.toDataURL('image/png');
  }, [crop]);

  return {
    crop,
    setCrop,
    getCroppedImage,
    setImageRef: (ref: HTMLImageElement | null) => {
      imageRef.current = ref;
    },
  };
}

export default Cropper;
