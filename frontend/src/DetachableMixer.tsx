import { useEffect, useRef, useState, useCallback } from 'react';
import { useMixer } from './store';
import MixerView from './components/MixerView';
import type { BusId } from './core/types';
import { escapeHtml, sanitizeSelector } from './utils/security';

// ============ Type-safe Window Extension for Detached Mixer ============

interface BusState {
  volume: number;
  muted: boolean;
}

/**
 * Extension interface for Window object used by detached mixer.
 * Provides type-safe access to ReelForge-specific properties.
 */
interface ReelForgeWindowExtension {
  __reelforge_getBusState?: (busId: BusId) => BusState;
  __reelforge_onBusChange?: (busId: BusId, volume: number, muted?: boolean) => void;
  __reelforge_selectedBus?: () => BusId | null;
  __reelforge_setSelectedBus?: (busId: BusId | null) => void;
  __reelforge_isPinned?: () => boolean;
}

type ReelForgeWindow = Window & ReelForgeWindowExtension;

interface DetachableMixerProps {
  onBusChange: (busId: BusId, volume: number, muted?: boolean) => void;
  onPinnedChange?: (isPinned: boolean) => void;
  onDetachedChange?: (isDetached: boolean) => void;
  detachedWindowRef?: React.MutableRefObject<Window | null>;
}

function throttle<T extends (...args: any[]) => void>(func: T, delay: number): T {
  let lastCall = 0;
  return ((...args: Parameters<T>) => {
    const now = Date.now();
    if (now - lastCall >= delay) {
      lastCall = now;
      func(...args);
    }
  }) as T;
}

export default function DetachableMixer({ onBusChange, onPinnedChange, onDetachedChange, detachedWindowRef: externalDetachedWindowRef }: DetachableMixerProps) {
  const { state, setDetached, setVisible, setDetachedWindow, getBusState } = useMixer();
  const { project, isDetached, isVisible } = state;

  const [isClosing, setIsClosing] = useState(false);
  const [shouldRender, setShouldRender] = useState(isVisible);
  const [selectedBus, setSelectedBus] = useState<BusId | null>(null);
  const [, setIsPinned] = useState(false);
  const detachedWindowRef = useRef<ReelForgeWindow | null>(null);

  const toggleMixer = () => setVisible(!isVisible);

  useEffect(() => {
    if (isVisible) {
      setShouldRender(true);
      setIsClosing(false);
    } else if (shouldRender && !isDetached) {
      setIsClosing(true);
      const timer = setTimeout(() => {
        setShouldRender(false);
        setIsClosing(false);
      }, 400);
      return () => clearTimeout(timer);
    }
  }, [isVisible, shouldRender, isDetached]);

  useEffect(() => {
    return () => {
      if (detachedWindowRef.current && !detachedWindowRef.current.closed) {
        detachedWindowRef.current.close();
      }
    };
  }, []);

  useEffect(() => {
    if (detachedWindowRef.current && !detachedWindowRef.current.closed) {
      detachedWindowRef.current.__reelforge_getBusState = getBusState;
      detachedWindowRef.current.__reelforge_onBusChange = onBusChange;
      detachedWindowRef.current.__reelforge_selectedBus = () => selectedBus;
      detachedWindowRef.current.__reelforge_setSelectedBus = setSelectedBus;
    }
  }, [getBusState, onBusChange, selectedBus]);

  useEffect(() => {
    if (externalDetachedWindowRef) {
      externalDetachedWindowRef.current = detachedWindowRef.current;
    }
  }, [externalDetachedWindowRef, isDetached]);

  const handleDetach = useCallback(() => {
    if (isDetached && detachedWindowRef.current && !detachedWindowRef.current.closed) {
      detachedWindowRef.current.close();
      detachedWindowRef.current = null;
      setDetached(false);
      setDetachedWindow(null);
      onDetachedChange?.(false);
      return;
    }

    const width = 1100;
    const height = 450;
    const left = window.screenX + window.outerWidth - width - 20;
    const top = window.screenY + 100;

    const newWindow = window.open(
      '',
      'ReelForge Mixer',
      `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=no,alwaysRaised=yes,alwaysOnTop=yes`
    );

    if (!newWindow) {
      alert('Please allow pop-ups for this site to use detached mixer');
      return;
    }

    const rfWindow = newWindow as ReelForgeWindow;
    detachedWindowRef.current = rfWindow;
    setDetached(true);
    setDetachedWindow(newWindow);
    onDetachedChange?.(true);

    rfWindow.__reelforge_getBusState = getBusState;
    rfWindow.__reelforge_onBusChange = onBusChange;
    rfWindow.__reelforge_selectedBus = () => selectedBus;
    rfWindow.__reelforge_setSelectedBus = setSelectedBus;

    newWindow.document.write(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>ReelForge Mixer</title>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: radial-gradient(ellipse 800px 300px at 50% 100%, rgba(74, 158, 255, 0.12) 0%, transparent 70%),
                          repeating-linear-gradient(90deg, transparent, transparent 50px, rgba(74, 158, 255, 0.03) 50px, rgba(74, 158, 255, 0.03) 51px),
                          linear-gradient(180deg, #1a1d26 0%, #0f1117 100%);
              color: #e0e0e0;
              overflow: hidden;
              height: 100vh;
              display: flex;
              flex-direction: column;
              position: relative;
            }
            
            body::before {
              content: 'REELFORGE';
              position: absolute;
              top: 50%;
              left: 50%;
              transform: translate(-50%, -50%) perspective(800px) rotateX(25deg) rotateY(-2deg);
              font-size: clamp(80px, 15vw, 240px);
              font-weight: 900;
              letter-spacing: clamp(20px, 4vw, 60px);
              padding-left: clamp(20px, 4vw, 60px);
              color: transparent;
              background: linear-gradient(180deg, rgba(74, 158, 255, 0.12) 0%, rgba(74, 158, 255, 0.06) 50%, rgba(74, 158, 255, 0.02) 100%);
              -webkit-background-clip: text;
              background-clip: text;
              text-transform: uppercase;
              pointer-events: none;
              user-select: none;
              z-index: 0;
              text-shadow: 0 10px 30px rgba(0, 0, 0, 0.5), 0 0 60px rgba(74, 158, 255, 0.2), 0 20px 40px rgba(0, 0, 0, 0.3);
              filter: blur(0.5px);
            }
            
            .mixer-content {
              flex: 1;
              display: flex;
              justify-content: center;
              align-items: center;
              padding: 30px 20px;
              position: relative;
              z-index: 1;
            }
            
            .mixer-strips {
              display: flex;
              gap: 24px;
              align-items: flex-end;
            }
            
            @keyframes fadeInScale {
              from {
                opacity: 0;
                transform: translateY(30px) scale(0.8);
              }
              to {
                opacity: 1;
                transform: translateY(0) scale(1);
              }
            }

            .mixer-strip {
              display: flex;
              flex-direction: column;
              align-items: center;
              gap: 10px;
              padding: 16px 14px;
              background: linear-gradient(135deg, #1e2229 0%, #181b21 100%);
              border-radius: 8px;
              border: 3px solid #2a2e3a;
              transition: all 0.2s;
              box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
              animation: fadeInScale 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) backwards;
              cursor: pointer;
              width: 100px;
              box-sizing: border-box;
            }
            
            .mixer-strip:hover {
              background: linear-gradient(135deg, #252930 0%, #1e2229 100%);
              border-color: #3a3e4a;
              box-shadow: 0 6px 16px rgba(0, 0, 0, 0.4);
            }
            
            .mixer-strip:nth-child(1) {
              animation-delay: 0.1s;
              background: linear-gradient(135deg, #1e2229 0%, #181b21 100%);
              border-color: #2a4e3a;
            }

            .mixer-strip:nth-child(1):hover {
              border-color: #3a5e4a;
              box-shadow: 0 6px 16px rgba(58, 158, 122, 0.2);
            }

            .mixer-strip:nth-child(2) {
              animation-delay: 0.15s;
              background: linear-gradient(135deg, #221e29 0%, #1b1821 100%);
              border-color: #3a2e4a;
            }

            .mixer-strip:nth-child(2):hover {
              border-color: #5a3e6a;
              box-shadow: 0 6px 16px rgba(139, 92, 246, 0.2);
            }

            .mixer-strip:nth-child(3) {
              animation-delay: 0.2s;
              background: linear-gradient(135deg, #29221e 0%, #211b18 100%);
              border-color: #4a322a;
            }

            .mixer-strip:nth-child(3):hover {
              border-color: #5a423a;
              box-shadow: 0 6px 16px rgba(255, 140, 60, 0.2);
            }

            .mixer-strip:nth-child(4) {
              animation-delay: 0.25s;
              background: linear-gradient(135deg, #1e2529 0%, #181e21 100%);
              border-color: #2a3e4a;
            }

            .mixer-strip:nth-child(4):hover {
              border-color: #3a5e6a;
              box-shadow: 0 6px 16px rgba(74, 222, 255, 0.2);
            }

            .mixer-strip:nth-child(5) {
              animation-delay: 0.3s;
              background: linear-gradient(135deg, #251e29 0%, #1e1821 100%);
              border-color: #3a2e4a;
            }

            .mixer-strip:nth-child(5):hover {
              border-color: #5a3e5a;
              box-shadow: 0 6px 16px rgba(255, 92, 200, 0.2);
            }
            
            .mixer-strip-master {
              background: linear-gradient(135deg, #252a35 0%, #1a1e28 100%) !important;
              border: 3px solid #4a9eff !important;
              box-shadow: 0 4px 16px rgba(74, 158, 255, 0.2) !important;
            }
            
            .mixer-strip-master:hover {
              background: linear-gradient(135deg, #2d3240 0%, #212530 100%) !important;
              border-color: #60a5fa !important;
              box-shadow: 0 6px 20px rgba(74, 158, 255, 0.3) !important;
            }
            
            /* Music Bus - Purple */
            .mixer-strip:nth-child(1) {
              border-color: #7c3aed22;
            }

            .mixer-strip:nth-child(1).mixer-strip-selected {
              background: linear-gradient(135deg, #3d2a50 0%, #2a1f38 100%) !important;
              border: 3px solid #a78bfa !important;
              box-shadow: 0 4px 20px rgba(167, 139, 250, 0.4), inset 0 0 20px rgba(167, 139, 250, 0.1) !important;
            }

            /* SFX Bus - Green */
            .mixer-strip:nth-child(2) {
              border-color: #10b98122;
            }

            .mixer-strip:nth-child(2).mixer-strip-selected {
              background: linear-gradient(135deg, #2a4038 0%, #1f3028 100%) !important;
              border: 3px solid #34d399 !important;
              box-shadow: 0 4px 20px rgba(52, 211, 153, 0.4), inset 0 0 20px rgba(52, 211, 153, 0.1) !important;
            }

            /* Voice Bus - Orange */
            .mixer-strip:nth-child(3) {
              border-color: #f9731622;
            }

            .mixer-strip:nth-child(3).mixer-strip-selected {
              background: linear-gradient(135deg, #503d2a 0%, #382a1f 100%) !important;
              border: 3px solid #fb923c !important;
              box-shadow: 0 4px 20px rgba(251, 146, 60, 0.4), inset 0 0 20px rgba(251, 146, 60, 0.1) !important;
            }

            /* Ambience Bus - Cyan */
            .mixer-strip:nth-child(4) {
              border-color: #06b6d422;
            }

            .mixer-strip:nth-child(4).mixer-strip-selected {
              background: linear-gradient(135deg, #2a4650 0%, #1f3438 100%) !important;
              border: 3px solid #22d3ee !important;
              box-shadow: 0 4px 20px rgba(34, 211, 238, 0.4), inset 0 0 20px rgba(34, 211, 238, 0.1) !important;
            }

            /* Master Bus - Blue */
            .mixer-strip-master.mixer-strip-selected {
              background: linear-gradient(135deg, #2d3d50 0%, #212f40 100%) !important;
              border: 3px solid #60a5fa !important;
              box-shadow: 0 4px 20px rgba(96, 165, 250, 0.5), inset 0 0 20px rgba(96, 165, 250, 0.15) !important;
            }
            
            .mixer-name {
              font-weight: 700;
              text-transform: uppercase;
              font-size: 10px;
              letter-spacing: 1px;
              color: #6b7280;
              margin-bottom: 4px;
              transition: color 0.2s;
              width: 100%;
              text-align: center;
              white-space: nowrap;
              overflow: hidden;
              text-overflow: ellipsis;
            }

            .mixer-strip:nth-child(1) .mixer-name {
              color: #a78bfa;
            }

            .mixer-strip:nth-child(2) .mixer-name {
              color: #34d399;
            }

            .mixer-strip:nth-child(3) .mixer-name {
              color: #fb923c;
            }

            .mixer-strip:nth-child(4) .mixer-name {
              color: #22d3ee;
            }

            .mixer-strip-master .mixer-name {
              color: #60a5fa !important;
            }

            .mixer-strip-selected .mixer-name {
              color: #ffffff !important;
              font-weight: 800;
              text-shadow: 0 0 8px currentColor;
            }
            
            .mixer-mute {
              width: 36px;
              height: 24px;
              font-size: 11px;
              font-weight: 700;
              border-radius: 4px;
              border: 1px solid #3a3e4a;
              background: linear-gradient(180deg, #2a2e3a 0%, #1e2229 100%);
              color: #9ca3af;
              cursor: pointer;
              transition: all 0.15s;
              box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.3);
            }
            
            .mixer-mute:hover {
              background: linear-gradient(180deg, #343842 0%, #252930 100%);
              border-color: #4a9eff;
              color: #e0e0e0;
              box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.2), 0 0 8px rgba(74, 158, 255, 0.3);
            }
            
            .mixer-mute-active {
              background: linear-gradient(180deg, #ef4444 0%, #dc2626 100%);
              border-color: #f87171;
              color: #fff;
              box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.3), 0 0 12px rgba(239, 68, 68, 0.5);
            }
            
            .mixer-mute-active:hover {
              background: linear-gradient(180deg, #dc2626 0%, #b91c1c 100%);
              box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.3), 0 0 16px rgba(239, 68, 68, 0.6);
            }
            
            .mixer-fader-container {
              position: relative;
              width: 60px;
              height: 220px;
              display: flex;
              align-items: center;
              justify-content: center;
              background: #0a0c10;
              border-radius: 6px;
              padding: 8px 0;
              box-shadow: inset 0 2px 8px rgba(0, 0, 0, 0.6);
            }
            
            .mixer-fader-bg {
              position: absolute;
              width: 8px;
              height: calc(100% - 16px);
              background: linear-gradient(to bottom, #dc2626 0%, #ef4444 10%, #f59e0b 30%, #fbbf24 50%, #84cc16 70%, #22c55e 85%, #16a34a 100%);
              border-radius: 4px;
              opacity: 0.4;
              pointer-events: none;
            }
            
            .mixer-fader {
              -webkit-appearance: slider-vertical;
              appearance: none;
              width: 60px;
              height: calc(100% - 16px);
              background: transparent;
              outline: none;
              cursor: pointer;
              position: relative;
              z-index: 2;
              writing-mode: vertical-lr;
              direction: rtl;
            }
            
            .mixer-fader::-webkit-slider-runnable-track {
              width: 6px;
              height: 100%;
              background: linear-gradient(to bottom, #2a2e3a 0%, #1a1d26 50%, #2a2e3a 100%);
              border-radius: 3px;
              border: 1px solid #0a0c10;
              box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.8);
              margin: 0 auto;
            }
            
            .mixer-fader::-webkit-slider-thumb {
              -webkit-appearance: none;
              appearance: none;
              width: 40px;
              height: 24px;
              background: linear-gradient(180deg, #e8e8e8 0%, #c0c0c0 20%, #a0a0a0 40%, #808080 60%, #707070 80%, #606060 100%);
              border: 2px solid #2a2a2a;
              border-radius: 3px;
              cursor: grab;
              box-shadow: 0 4px 10px rgba(0, 0, 0, 0.9), inset 0 3px 2px rgba(255, 255, 255, 0.5), inset 0 -3px 2px rgba(0, 0, 0, 0.6), inset 3px 0 2px rgba(255, 255, 255, 0.3), inset -3px 0 2px rgba(0, 0, 0, 0.4), 0 1px 0 rgba(255, 255, 255, 0.1);
              transition: none;
              position: relative;
            }
            
            .mixer-fader::-webkit-slider-thumb:hover {
              background: linear-gradient(180deg, #f4f4f4 0%, #d0d0d0 20%, #b0b0b0 40%, #909090 60%, #808080 80%, #707070 100%);
              box-shadow: 0 5px 12px rgba(0, 0, 0, 1), inset 0 3px 2px rgba(255, 255, 255, 0.6), inset 0 -3px 2px rgba(0, 0, 0, 0.6), inset 3px 0 2px rgba(255, 255, 255, 0.4), inset -3px 0 2px rgba(0, 0, 0, 0.4), 0 1px 0 rgba(255, 255, 255, 0.2);
            }
            
            .mixer-fader::-webkit-slider-thumb:active {
              cursor: grabbing;
              background: linear-gradient(180deg, #d0d0d0 0%, #a0a0a0 20%, #808080 40%, #606060 60%, #505050 80%, #404040 100%);
              box-shadow: 0 2px 6px rgba(0, 0, 0, 1), inset 0 3px 3px rgba(0, 0, 0, 0.5), inset 0 -1px 1px rgba(255, 255, 255, 0.2);
            }
            
            .mixer-fader::-moz-range-track {
              width: 6px;
              height: 100%;
              background: linear-gradient(to bottom, #2a2e3a 0%, #1a1d26 50%, #2a2e3a 100%);
              border-radius: 3px;
              border: 1px solid #0a0c10;
              box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.8);
            }
            
            .mixer-fader::-moz-range-thumb {
              width: 40px;
              height: 24px;
              background: linear-gradient(180deg, #e8e8e8 0%, #c0c0c0 20%, #a0a0a0 40%, #808080 60%, #707070 80%, #606060 100%);
              border: 2px solid #2a2a2a;
              border-radius: 3px;
              cursor: grab;
              box-shadow: 0 4px 10px rgba(0, 0, 0, 0.9), inset 0 3px 2px rgba(255, 255, 255, 0.5), inset 0 -3px 2px rgba(0, 0, 0, 0.6), inset 3px 0 2px rgba(255, 255, 255, 0.3), inset -3px 0 2px rgba(0, 0, 0, 0.4), 0 1px 0 rgba(255, 255, 255, 0.1);
            }
            
            .mixer-fader::-moz-range-thumb:hover {
              background: linear-gradient(180deg, #f4f4f4 0%, #d0d0d0 20%, #b0b0b0 40%, #909090 60%, #808080 80%, #707070 100%);
              box-shadow: 0 5px 12px rgba(0, 0, 0, 1), inset 0 3px 2px rgba(255, 255, 255, 0.6), inset 0 -3px 2px rgba(0, 0, 0, 0.6), inset 3px 0 2px rgba(255, 255, 255, 0.4), inset -3px 0 2px rgba(0, 0, 0, 0.4), 0 1px 0 rgba(255, 255, 255, 0.2);
            }
            
            .mixer-fader::-moz-range-thumb:active {
              cursor: grabbing;
              background: linear-gradient(180deg, #d0d0d0 0%, #a0a0a0 20%, #808080 40%, #606060 60%, #505050 80%, #404040 100%);
              box-shadow: 0 2px 6px rgba(0, 0, 0, 1), inset 0 3px 3px rgba(0, 0, 0, 0.5), inset 0 -1px 1px rgba(255, 255, 255, 0.2);
            }
            
            .mixer-value {
              font-size: 11px;
              font-weight: 600;
              color: #9ca3af;
              font-family: 'SF Mono', 'Monaco', 'Courier New', monospace;
              min-width: 70px;
              width: 70px;
              text-align: center;
              padding: 4px 6px;
              background: #0a0c10;
              border: 1px solid #2a2e3a;
              border-radius: 4px;
              margin-top: 4px;
              box-shadow: inset 0 1px 3px rgba(0, 0, 0, 0.4);
            }
            
            .mixer-strip-master .mixer-value {
              color: #4a9eff;
              border-color: #3a3e4a;
            }

            .pin-button {
              position: fixed;
              top: 12px;
              right: 12px;
              width: 40px;
              height: 40px;
              background: linear-gradient(135deg, #2a2e3a 0%, #1e2229 100%);
              border: 2px solid #3a3e4a;
              border-radius: 8px;
              color: #9ca3af;
              font-size: 20px;
              cursor: pointer;
              transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
              display: flex;
              align-items: center;
              justify-content: center;
              z-index: 99999;
              box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.05);
              padding: 0;
              outline: none;
            }

            .pin-button:hover {
              background: linear-gradient(135deg, #343842 0%, #252930 100%);
              border-color: #4a9eff;
              color: #e0e0e0;
              transform: translateY(-2px) scale(1.05);
              box-shadow: 0 4px 12px rgba(74, 158, 255, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.1);
            }

            .pin-button:active {
              transform: translateY(0) scale(0.98);
              box-shadow: 0 1px 4px rgba(0, 0, 0, 0.5), inset 0 1px 2px rgba(0, 0, 0, 0.3);
            }

            .pin-button.pinned {
              background: linear-gradient(135deg, #4a9eff 0%, #3a7ede 100%);
              border-color: #5aa5ff;
              color: #fff;
              box-shadow: 0 3px 10px rgba(74, 158, 255, 0.6), inset 0 1px 0 rgba(255, 255, 255, 0.3);
              animation: pulse-glow 2s ease-in-out infinite;
            }

            .pin-button.pinned:hover {
              background: linear-gradient(135deg, #5aa5ff 0%, #4a8eef 100%);
              border-color: #6ab5ff;
              transform: translateY(-2px) scale(1.05);
              box-shadow: 0 5px 15px rgba(74, 158, 255, 0.8), inset 0 1px 0 rgba(255, 255, 255, 0.4);
            }

            .pin-button.pinned:active {
              transform: translateY(0) scale(0.98);
              box-shadow: 0 2px 6px rgba(74, 158, 255, 0.7), inset 0 1px 2px rgba(0, 0, 0, 0.2);
            }

            @keyframes pulse-glow {
              0%, 100% {
                box-shadow: 0 3px 10px rgba(74, 158, 255, 0.6), inset 0 1px 0 rgba(255, 255, 255, 0.3);
              }
              50% {
                box-shadow: 0 3px 15px rgba(74, 158, 255, 0.9), inset 0 1px 0 rgba(255, 255, 255, 0.4);
              }
            }
          </style>
        </head>
        <body>
          <button class="pin-button" id="pin-button" title="Keep window on top">📌</button>
          <div class="mixer-content">
            <div class="mixer-strips" id="mixer-strips"></div>
          </div>
        </body>
      </html>
    `);

    newWindow.document.close();

    const buses = [
      { id: 'music' as BusId, name: 'Music' },
      { id: 'sfx' as BusId, name: 'SFX' },
      { id: 'voice' as BusId, name: 'Voice' },
      { id: 'ambience' as BusId, name: 'Ambience' },
      { id: 'master' as BusId, name: 'Master' }
    ];

    const container = newWindow.document.getElementById('mixer-strips');
    if (!container) return;

    const draggingState: Record<string, boolean> = {};

    const getBusStateFromParent = () => rfWindow.__reelforge_getBusState;
    const onBusChangeFromParent = () => rfWindow.__reelforge_onBusChange;
    const getSelectedBusFromParent = () => rfWindow.__reelforge_selectedBus;
    const setSelectedBusFromParent = () => rfWindow.__reelforge_setSelectedBus;

    const throttledOnBusChange = throttle((busId: BusId, volume: number, muted?: boolean) => {
      const callback = onBusChangeFromParent();
      if (callback) callback(busId, volume, muted);
    }, 16);

    container.innerHTML = buses.map(bus => {
      const getBusStateFn = getBusStateFromParent();
      const busState = getBusStateFn ? getBusStateFn(bus.id) : { volume: 1, muted: false };
      const volume = busState.volume;
      const muted = busState.muted;
      const isMaster = bus.id === 'master';
      const getSelectedBusFn = getSelectedBusFromParent();
      const isSelected = getSelectedBusFn ? getSelectedBusFn() === bus.id : false;
      const volumeDb = volume <= 0 ? '-∞' : (20 * Math.log10(volume)).toFixed(1);
      const volumePercent = (volume * 100).toFixed(0);

      // Escape user-controllable values to prevent XSS
      const safeBusId = sanitizeSelector(bus.id);
      const safeBusName = escapeHtml(bus.name);
      const safeVolumeDb = escapeHtml(volumeDb);

      return `
        <div class="mixer-strip ${isMaster ? 'mixer-strip-master' : ''} ${isSelected ? 'mixer-strip-selected' : ''}"
             data-bus="${safeBusId}">
          <div class="mixer-name">${safeBusName}</div>
          <button class="mixer-mute ${muted ? 'mixer-mute-active' : ''}"
                  data-bus="${safeBusId}">
            M
          </button>
          <div class="mixer-fader-container">
            <div class="mixer-fader-bg"></div>
            <input type="range"
                   class="mixer-fader"
                   min="0"
                   max="1"
                   step="0.01"
                   value="${volume}"
                   data-bus="${safeBusId}" />
          </div>
          <div class="mixer-value">
            <div class="mixer-value-number">${safeVolumeDb}</div>
            <div class="mixer-value-label" style="font-size: 9px; color: #888;">dB (${volumePercent}%)</div>
          </div>
        </div>
      `;
    }).join('');

    container.querySelectorAll('.mixer-fader').forEach(slider => {
      const input = slider as HTMLInputElement;
      const busId = input.dataset.bus as BusId;

      const handleMouseDown = () => {
        draggingState[busId] = true;
      };

      const updateValue = (e: Event) => {
        const value = parseFloat((e.target as HTMLInputElement).value);
        throttledOnBusChange(busId, value);

        const valueContainer = input.parentElement?.nextElementSibling;
        if (valueContainer) {
          const volumeDb = value <= 0 ? '-∞' : (20 * Math.log10(value)).toFixed(1);
          const volumePercent = (value * 100).toFixed(0);

          const numberDisplay = valueContainer.querySelector('.mixer-value-number');
          const labelDisplay = valueContainer.querySelector('.mixer-value-label');

          if (numberDisplay) {
            numberDisplay.textContent = volumeDb;
          }
          if (labelDisplay) {
            labelDisplay.textContent = `dB (${volumePercent}%)`;
          }
        }
      };

      input.addEventListener('mousedown', handleMouseDown);
      input.addEventListener('input', updateValue);
      input.addEventListener('change', updateValue);
    });

    const handleGlobalMouseUp = () => {
      Object.keys(draggingState).forEach(key => {
        draggingState[key] = false;
      });
    };

    newWindow.document.addEventListener('mouseup', handleGlobalMouseUp);
    newWindow.document.addEventListener('mouseleave', handleGlobalMouseUp);

    container.querySelectorAll('.mixer-mute').forEach(btn => {
      const button = btn as HTMLButtonElement;
      const busId = button.dataset.bus as BusId;

      button.addEventListener('click', (e) => {
        e.stopPropagation();
        const getBusState = getBusStateFromParent();
        const onBusChange = onBusChangeFromParent();
        if (getBusState && onBusChange) {
          const busState = getBusState(busId);
          onBusChange(busId, busState.volume, !busState.muted);
        }
      });
    });

    container.querySelectorAll('.mixer-strip').forEach(strip => {
      const stripElement = strip as HTMLElement;
      const busId = stripElement.dataset.bus as BusId;

      stripElement.addEventListener('click', (e) => {
        const target = e.target as HTMLElement;
        if (target.classList.contains('mixer-mute') ||
            target.classList.contains('mixer-fader') ||
            target.closest('.mixer-fader-container')) {
          return;
        }

        const setSelectedBusFn = setSelectedBusFromParent();
        const getSelectedBusFn = getSelectedBusFromParent();
        const currentSelectedBus = getSelectedBusFn ? getSelectedBusFn() : null;
        if (setSelectedBusFn) {
          setSelectedBusFn(busId === currentSelectedBus ? null : busId);
        }
      });
    });

    const syncFromState = () => {
      if (!newWindow || newWindow.closed) return;

      const getBusStateFn = getBusStateFromParent();
      const getSelectedBusFn = getSelectedBusFromParent();
      const currentSelectedBus = getSelectedBusFn ? getSelectedBusFn() : null;
      if (!getBusStateFn) return;

      buses.forEach((bus, index) => {
        if (draggingState[bus.id]) return;

        const busState = getBusStateFn(bus.id);
        const volume = busState.volume;
        const muted = busState.muted;

        const slider = container.querySelectorAll('.mixer-fader')[index] as HTMLInputElement;
        if (slider && Math.abs(parseFloat(slider.value) - volume) > 0.001) {
          slider.value = volume.toString();
        }

        const valueContainer = container.querySelectorAll('.mixer-value')[index];
        if (valueContainer) {
          const volumeDb = volume <= 0 ? '-∞' : (20 * Math.log10(volume)).toFixed(1);
          const volumePercent = (volume * 100).toFixed(0);

          const numberDisplay = valueContainer.querySelector('.mixer-value-number');
          const labelDisplay = valueContainer.querySelector('.mixer-value-label');

          if (numberDisplay) {
            numberDisplay.textContent = volumeDb;
          }
          if (labelDisplay) {
            labelDisplay.textContent = `dB (${volumePercent}%)`;
          }
        }

        const muteBtn = container.querySelectorAll('.mixer-mute')[index] as HTMLButtonElement;
        if (muteBtn) {
          if (muted) {
            muteBtn.classList.add('mixer-mute-active');
          } else {
            muteBtn.classList.remove('mixer-mute-active');
          }
        }

        const stripElement = container.querySelectorAll('.mixer-strip')[index] as HTMLElement;
        if (stripElement) {
          const isSelected = currentSelectedBus === bus.id;
          if (isSelected) {
            stripElement.classList.add('mixer-strip-selected');
          } else {
            stripElement.classList.remove('mixer-strip-selected');
          }
        }
      });
    };

    const syncInterval = window.setInterval(syncFromState, 100);

    const pinButton = newWindow.document.getElementById('pin-button');
    let localIsPinned = false;

    rfWindow.__reelforge_isPinned = () => localIsPinned;

    if (pinButton) {
      pinButton.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();

        localIsPinned = !localIsPinned;

        if (localIsPinned) {
          pinButton.classList.add('pinned');
          pinButton.title = 'Unpin window';
          setIsPinned(true);
          onPinnedChange?.(true);
        } else {
          pinButton.classList.remove('pinned');
          pinButton.title = 'Keep window on top';
          setIsPinned(false);
          onPinnedChange?.(false);
        }
      });
    }

    newWindow.addEventListener('beforeunload', () => {
      clearInterval(syncInterval);
      newWindow.document.removeEventListener('mouseup', handleGlobalMouseUp);
      newWindow.document.removeEventListener('mouseleave', handleGlobalMouseUp);
      delete rfWindow.__reelforge_getBusState;
      delete rfWindow.__reelforge_onBusChange;
      delete rfWindow.__reelforge_isPinned;
      setDetached(false);
      setDetachedWindow(null);
      setVisible(true);
      setIsPinned(false);
      onPinnedChange?.(false);
      onDetachedChange?.(false);
    });
  }, [isDetached, setDetached, setDetachedWindow, onDetachedChange, getBusState, onBusChange, project, setIsPinned, onPinnedChange, setVisible]);

  if (!project) return null;

  if (isDetached) {
    return (
      <>
        <button
          className="rf-mixer-toggle"
          onClick={() => {
            handleDetach();
            setVisible(true);
          }}
          title="Reattach and open mixer"
        >
          🎚️ MIXER
        </button>
      </>
    );
  }

  if (!shouldRender) {
    return (
      <button
        className="rf-mixer-toggle"
        onClick={toggleMixer}
        title="Open mixer"
      >
        🎚️ MIXER
      </button>
    );
  }

  return (
    <div className={`rf-mixer-panel ${isClosing ? 'closing' : ''}`}>
      <MixerView
        onBusChange={onBusChange}
        selectedBus={selectedBus}
        onSelectBus={setSelectedBus}
      />
      <button
        className="rf-mixer-close"
        onClick={toggleMixer}
        title="Close mixer"
      >
        ✕
      </button>
      <button
        className="rf-mixer-detach"
        onClick={handleDetach}
        title="Detach mixer to separate window"
      >
        ⬈ Detach
      </button>
    </div>
  );
}
