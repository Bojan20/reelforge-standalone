#include <flutter/runtime_effect.glsl>

// ═══════════════════════════════════════════════════════════════════════════
// P2.2: GPU Spectrum Shader — 60fps at 4K resolution
// ═══════════════════════════════════════════════════════════════════════════

// Uniforms
uniform vec2 uResolution;      // Canvas size
uniform float uTime;           // Animation time
uniform float uRange;          // dB range (e.g., 60 for -60 to 0)
uniform float uMinFreq;        // Minimum frequency (Hz)
uniform float uMaxFreq;        // Maximum frequency (Hz)
uniform float uGlow;           // Glow intensity (0-1)
uniform float uMode;           // 0=fill, 1=line, 2=bars, 3=both
uniform float uBarWidth;       // Bar width factor (0-1)
uniform float uShowPeaks;      // Show peak hold (0 or 1)
uniform sampler2D uSpectrum;   // Spectrum data as 1D texture (R=spectrum, G=peaks)

// Output
out vec4 fragColor;

// Colors
const vec3 COLOR_FILL_TOP = vec3(0.29, 0.62, 1.0);    // #4a9eff cyan-blue
const vec3 COLOR_FILL_BOT = vec3(0.25, 1.0, 0.56);    // #40ff90 green
const vec3 COLOR_LINE = vec3(0.29, 0.78, 1.0);        // #4ac8ff bright cyan
const vec3 COLOR_PEAK = vec3(1.0, 0.56, 0.25);        // #ff9040 orange
const vec3 COLOR_BAR_TOP = vec3(0.29, 0.62, 1.0);     // #4a9eff
const vec3 COLOR_BAR_MID = vec3(1.0, 1.0, 0.25);      // #ffff40 yellow
const vec3 COLOR_BAR_BOT = vec3(0.25, 1.0, 0.56);     // #40ff90 green
const vec3 COLOR_BAR_HOT = vec3(1.0, 0.25, 0.38);     // #ff4060 red (near 0dB)
const vec3 COLOR_BG = vec3(0.04, 0.04, 0.05);         // #0a0a0c deep black
const vec3 COLOR_GRID = vec3(0.15, 0.15, 0.18);       // #262630

// Sample spectrum with smoothing
vec2 sampleSpectrum(float x) {
    // Texture lookup: R = spectrum value, G = peak value
    vec2 value = texture(uSpectrum, vec2(x, 0.5)).rg;
    return value;
}

// Calculate bar color gradient based on level
vec3 getBarColor(float level) {
    if (level > 0.9) {
        return mix(COLOR_BAR_HOT, COLOR_BAR_TOP, (1.0 - level) * 10.0);
    } else if (level > 0.5) {
        return mix(COLOR_BAR_MID, COLOR_BAR_HOT, (level - 0.5) * 2.5);
    } else {
        return mix(COLOR_BAR_BOT, COLOR_BAR_MID, level * 2.0);
    }
}

// Draw grid lines
float drawGrid(vec2 uv) {
    float grid = 0.0;

    // Horizontal lines (dB scale)
    for (float db = -60.0; db <= 0.0; db += 6.0) {
        float y = 1.0 - (db + uRange) / uRange;
        float dist = abs(uv.y - y);
        grid = max(grid, smoothstep(2.0/uResolution.y, 0.0, dist) * 0.3);
    }

    // Vertical lines (frequency scale - log spacing)
    float[] freqs = float[](100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0);
    for (int i = 0; i < 8; i++) {
        float freq = freqs[i];
        if (freq >= uMinFreq && freq <= uMaxFreq) {
            float x = log(freq / uMinFreq) / log(uMaxFreq / uMinFreq);
            float dist = abs(uv.x - x);
            grid = max(grid, smoothstep(1.5/uResolution.x, 0.0, dist) * 0.3);
        }
    }

    return grid;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;

    // Get spectrum and peak values at this x position
    vec2 specData = sampleSpectrum(uv.x);
    float spectrum = specData.r;  // Current spectrum value
    float peak = specData.g;      // Peak hold value

    // Current pixel Y position (inverted: 0 at top, 1 at bottom)
    float pixelY = 1.0 - uv.y;

    // Base color (background)
    vec3 color = COLOR_BG;
    float alpha = 1.0;

    // Draw grid
    float grid = drawGrid(uv);
    color = mix(color, COLOR_GRID, grid);

    // Mode 2: Bars
    if (uMode > 1.5 && uMode < 2.5) {
        // Calculate bar boundaries
        float binWidth = 1.0 / 128.0; // Assume 128 bins
        float barGap = binWidth * (1.0 - uBarWidth);
        float barPos = mod(uv.x, binWidth);

        // Check if within bar
        if (barPos > barGap / 2.0 && barPos < binWidth - barGap / 2.0) {
            if (pixelY <= spectrum) {
                // Bar fill with gradient
                vec3 barColor = getBarColor(pixelY);
                color = barColor;
                alpha = 0.9;
            }
        }

        // Peak markers
        if (uShowPeaks > 0.5 && peak > spectrum) {
            float peakDist = abs(pixelY - peak);
            float peakWidth = 3.0 / uResolution.y;
            if (peakDist < peakWidth && barPos > barGap / 2.0 && barPos < binWidth - barGap / 2.0) {
                color = COLOR_PEAK;
                alpha = 1.0;
            }
        }
    }
    // Mode 0: Fill
    else if (uMode < 0.5) {
        // Fill below spectrum curve
        if (pixelY <= spectrum) {
            // Gradient from bottom to top
            float gradientT = pixelY / max(spectrum, 0.001);
            color = mix(COLOR_FILL_BOT, COLOR_FILL_TOP, gradientT);

            // Fade out near top
            float fadeTop = smoothstep(0.0, 0.1, spectrum - pixelY);
            alpha = mix(0.2, 0.6, fadeTop);
        }

        // Peak line
        if (uShowPeaks > 0.5) {
            float peakDist = abs(pixelY - peak);
            float peakWidth = 2.0 / uResolution.y;
            float peakAlpha = smoothstep(peakWidth, 0.0, peakDist);
            if (peakAlpha > 0.0) {
                color = mix(color, COLOR_PEAK, peakAlpha);
                alpha = max(alpha, peakAlpha * 0.8);
            }
        }
    }
    // Mode 1: Line only
    else if (uMode < 1.5) {
        // Draw spectrum line (anti-aliased)
        float lineWidth = 2.0 / uResolution.y;
        float lineDist = abs(pixelY - spectrum);
        float lineAlpha = smoothstep(lineWidth, 0.0, lineDist);

        if (lineAlpha > 0.0) {
            color = mix(color, COLOR_LINE, lineAlpha);
            alpha = max(alpha, lineAlpha * 0.9);
        }

        // Peak line
        if (uShowPeaks > 0.5) {
            float peakDist = abs(pixelY - peak);
            float peakWidth = 1.5 / uResolution.y;
            float peakAlpha = smoothstep(peakWidth, 0.0, peakDist);
            if (peakAlpha > 0.0) {
                color = mix(color, COLOR_PEAK, peakAlpha * 0.7);
                alpha = max(alpha, peakAlpha * 0.6);
            }
        }
    }
    // Mode 3: Both (fill + line)
    else {
        // Fill below spectrum curve
        if (pixelY <= spectrum) {
            float gradientT = pixelY / max(spectrum, 0.001);
            color = mix(COLOR_FILL_BOT, COLOR_FILL_TOP, gradientT);
            float fadeTop = smoothstep(0.0, 0.1, spectrum - pixelY);
            alpha = mix(0.15, 0.4, fadeTop);
        }

        // Spectrum line on top
        float lineWidth = 2.5 / uResolution.y;
        float lineDist = abs(pixelY - spectrum);
        float lineAlpha = smoothstep(lineWidth, 0.0, lineDist);
        if (lineAlpha > 0.0) {
            color = mix(color, COLOR_LINE, lineAlpha);
            alpha = max(alpha, lineAlpha * 0.95);
        }

        // Peak line
        if (uShowPeaks > 0.5) {
            float peakDist = abs(pixelY - peak);
            float peakWidth = 2.0 / uResolution.y;
            float peakAlpha = smoothstep(peakWidth, 0.0, peakDist);
            if (peakAlpha > 0.0) {
                color = mix(color, COLOR_PEAK, peakAlpha);
                alpha = max(alpha, peakAlpha * 0.8);
            }
        }
    }

    // Glow effect
    if (uGlow > 0.0) {
        float glowWidth = 25.0 / uResolution.y;
        float glowDist = abs(pixelY - spectrum);
        float glowAlpha = smoothstep(glowWidth, 0.0, glowDist) * uGlow * 0.2;
        color = mix(color, COLOR_LINE, glowAlpha);
        alpha = max(alpha, glowAlpha * 0.5);
    }

    fragColor = vec4(color, alpha);
}
