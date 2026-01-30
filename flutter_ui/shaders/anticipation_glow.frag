#include <flutter/runtime_effect.glsl>

// ═══════════════════════════════════════════════════════════════════════════
// P3.2: GPU Anticipation Glow Shader — Per-reel intensity with tension levels
// Industry-standard anticipation effect for slot machines
// ═══════════════════════════════════════════════════════════════════════════

// Uniforms
uniform vec2 uResolution;      // Canvas size
uniform float uTime;           // Animation time for pulsing
uniform float uTensionLevel;   // 1-4 tension level (higher = more intense)
uniform float uProgress;       // 0-1 progress through anticipation
uniform vec3 uGlowColor;       // Glow color (Gold → Orange → Red based on tension)
uniform float uReelIndex;      // Which reel (0-4) for position calculation
uniform float uReelCount;      // Total number of reels

// Output
out vec4 fragColor;

// Constants
const float PI = 3.14159265359;
const float GLOW_RADIUS = 0.15;       // Base glow radius
const float PULSE_SPEED = 4.0;        // Pulse animation speed
const float PULSE_AMOUNT = 0.3;       // Pulse intensity variation

// Industry-standard tension colors (Gold → Orange → Red-Orange → Red)
vec3 getTensionColor(float level) {
    if (level < 1.5) {
        return vec3(1.0, 0.843, 0.0);     // Gold #FFD700
    } else if (level < 2.5) {
        return vec3(1.0, 0.647, 0.0);     // Orange #FFA500
    } else if (level < 3.5) {
        return vec3(1.0, 0.388, 0.278);   // Red-Orange #FF6347
    } else {
        return vec3(1.0, 0.271, 0.0);     // Red #FF4500
    }
}

// Soft glow function
float softGlow(vec2 uv, vec2 center, float radius, float softness) {
    float dist = length(uv - center);
    return smoothstep(radius + softness, radius - softness, dist);
}

// Animated pulse value
float getPulse(float time, float speed) {
    return sin(time * speed) * 0.5 + 0.5;
}

// Edge glow for reel border effect
float edgeGlow(vec2 uv, float width, float softness) {
    float left = smoothstep(0.0, width, uv.x);
    float right = smoothstep(0.0, width, 1.0 - uv.x);
    float top = smoothstep(0.0, width, uv.y);
    float bottom = smoothstep(0.0, width, 1.0 - uv.y);

    float edges = min(min(left, right), min(top, bottom));
    return 1.0 - edges;
}

// Radial gradient for centered glow
float radialGlow(vec2 uv, float intensity) {
    vec2 center = vec2(0.5, 0.5);
    float dist = length(uv - center) * 2.0;
    return pow(1.0 - clamp(dist, 0.0, 1.0), intensity);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uResolution;

    // Calculate pulse animation
    float pulse = getPulse(uTime, PULSE_SPEED);

    // Intensity scales with tension level (L1=0.7, L2=0.85, L3=1.0, L4=1.2)
    float intensityMultiplier = 0.55 + (uTensionLevel * 0.15);

    // Base glow radius scales with tension
    float baseRadius = GLOW_RADIUS * (0.8 + uTensionLevel * 0.1);
    float pulseRadius = baseRadius + pulse * PULSE_AMOUNT * intensityMultiplier;

    // Get color based on tension level (or use provided color)
    vec3 glowColor = uGlowColor;
    if (length(glowColor) < 0.1) {
        glowColor = getTensionColor(uTensionLevel);
    }

    // Calculate edge glow
    float edgeWidth = 0.1 + uTensionLevel * 0.02;
    float edge = edgeGlow(uv, edgeWidth, 0.05);

    // Calculate radial glow from center (for dramatic effect at high tension)
    float radial = radialGlow(uv, 1.5 + uTensionLevel * 0.5);

    // Combine glows
    float combinedGlow = edge * 0.8 + radial * 0.2;

    // Apply pulse
    float finalIntensity = combinedGlow * (0.5 + pulse * 0.5) * intensityMultiplier;

    // Extra bloom for high tension (L3+)
    if (uTensionLevel >= 3.0) {
        float bloom = radialGlow(uv, 2.0) * 0.3;
        finalIntensity += bloom * pulse;
    }

    // Extra outer ring for L4 (max tension)
    if (uTensionLevel >= 4.0) {
        float outerRing = 1.0 - abs(length(uv - 0.5) - 0.45) * 10.0;
        outerRing = clamp(outerRing, 0.0, 1.0) * pulse * 0.4;
        finalIntensity += outerRing;
    }

    // Progress indicator (brightness increases as anticipation progresses)
    finalIntensity *= 0.7 + uProgress * 0.3;

    // Apply color and intensity
    vec3 color = glowColor * finalIntensity;
    float alpha = clamp(finalIntensity * 0.9, 0.0, 0.9);

    // Subtle chromatic aberration at high tension for extra drama
    if (uTensionLevel >= 3.0) {
        vec2 offset = (uv - 0.5) * 0.02 * (uTensionLevel - 2.0);
        float rOffset = edgeGlow(uv + offset, edgeWidth, 0.05);
        float bOffset = edgeGlow(uv - offset, edgeWidth, 0.05);
        color.r *= 1.0 + (rOffset - edge) * 0.2;
        color.b *= 1.0 + (bOffset - edge) * 0.2;
    }

    fragColor = vec4(color, alpha);
}
