#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uRefractionStrength;
uniform float uCornerRadius;
uniform sampler2D uTexture;

out vec4 fragColor;

// Signed distance field to a rounded box
float roundedBoxSDF(vec2 pos, vec2 halfSize, float radius) {
    vec2 q = abs(pos) - halfSize + vec2(radius);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uSize;
    
    vec2 halfSize = uSize * 0.5;
    vec2 centered = fragCoord - halfSize;
    
    float dist = roundedBoxSDF(centered, halfSize, uCornerRadius);
    
    // Smooth edge lensing factor near the border
    float edgeWidth = 24.0;
    float edgeFactor = smoothstep(-edgeWidth, 0.0, dist);
    
    vec2 normal = (length(centered) > 0.0001) ? normalize(centered) : vec2(0.0);
    vec2 offset = normal * (edgeFactor * (uRefractionStrength / uSize));
    
    vec2 distortedUV = clamp(uv - offset, vec2(0.001), vec2(0.999));
    
    vec4 texColor = texture(uTexture, distortedUV);
    
    // Subtle edge highlight (specular rim)
    float rim = smoothstep(-3.0, 0.0, dist) * (1.0 - smoothstep(0.0, 1.5, dist));
    vec4 rimColor = vec4(1.0, 1.0, 1.0, 0.25) * rim;
    
    fragColor = mix(texColor, vec4(1.0), rim * 0.15) + rimColor;
}
