#include <flutter/runtime_effect.glsl>

// Uniforms
uniform vec2 uResolution;      // Canvas size
uniform float uRange;          // dB range (e.g., 60 for -60 to 0)
uniform float uGlow;           // Glow intensity (0-1)
uniform sampler2D uSpectrum;   // Spectrum data as 1D texture

// Output
out vec4 fragColor;

// Colors
const vec3 COLOR_FILL_TOP = vec3(0.29, 0.62, 1.0);    // #4a9eff cyan-blue
const vec3 COLOR_FILL_BOT = vec3(0.25, 1.0, 0.56);    // #40ff90 green
const vec3 COLOR_LINE = vec3(0.29, 0.78, 1.0);        // #4ac8ff bright cyan
const vec3 COLOR_BG = vec3(0.04, 0.04, 0.05);         // #0a0a0c deep black

// Sample spectrum with smoothing
float sampleSpectrum(float x) {
    // Texture lookup with linear interpolation
    float value = texture(uSpectrum, vec2(x, 0.5)).r;
    return value;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;

    // Get spectrum value at this x position
    float spectrum = sampleSpectrum(uv.x);

    // Spectrum is 0-1 where 1 = 0dB, 0 = -uRange dB
    float spectrumY = spectrum;

    // Current pixel Y position (inverted: 0 at top, 1 at bottom)
    float pixelY = 1.0 - uv.y;

    // Base color (background)
    vec3 color = COLOR_BG;
    float alpha = 0.0;

    // Fill below spectrum curve
    if (pixelY <= spectrumY) {
        // Gradient from bottom to top
        float gradientT = pixelY / max(spectrumY, 0.001);
        color = mix(COLOR_FILL_BOT, COLOR_FILL_TOP, gradientT);

        // Fade out near top
        float fadeTop = smoothstep(0.0, 0.1, spectrumY - pixelY);
        alpha = mix(0.2, 0.5, fadeTop);
    }

    // Draw spectrum line (anti-aliased)
    float lineWidth = 2.0 / uResolution.y;
    float lineDist = abs(pixelY - spectrumY);
    float lineAlpha = smoothstep(lineWidth, 0.0, lineDist);

    if (lineAlpha > 0.0) {
        color = mix(color, COLOR_LINE, lineAlpha);
        alpha = max(alpha, lineAlpha * 0.9);
    }

    // Glow effect (simple approximation without blur)
    if (uGlow > 0.0) {
        float glowWidth = 20.0 / uResolution.y;
        float glowDist = abs(pixelY - spectrumY);
        float glowAlpha = smoothstep(glowWidth, 0.0, glowDist) * uGlow * 0.15;

        color = mix(color, COLOR_LINE, glowAlpha);
        alpha = max(alpha, glowAlpha);
    }

    fragColor = vec4(color, alpha);
}
