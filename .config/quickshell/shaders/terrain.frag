#version 440

// Spectrogram terrain: the history texture is a height map (red and blue: height as high and low
// bytes, green: hit glow) laid on
// a floor in perspective and ray-marched per pixel. It is a ring buffer: row `head` holds the
// newest frame and older ones follow it, wrapping around.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float aspect;
    float pixel;
    float horizon;
    float eye;
    float amp;
    float halfWidth;
    float zNear;
    float zFar;
    float head;
    float rows;
    vec4 accent;
    vec4 highlight;
    vec4 shade;
};

layout(binding = 1) uniform sampler2D history;

const int STEPS = 56;
const float PI = 3.14159265;

vec2 sampleAt(float x, float z) {
    // Smoothed abs, so the mirrored halves meet without a crease down the middle
    float m = (sqrt(x * x + 0.01) - 0.1) / (halfWidth - 0.1);
    if (m >= 1.0)
        return vec2(0.0);
    float age = (z - zNear) / (zFar - zNear) * (rows - 1.0);
    // Taps along time smooth out frame-to-frame jitter; clamped at the newest row so the front
    // never reads the oldest one across the ring's seam
    vec3 t = vec3(0.0);
    for (int k = -2; k <= 2; k++) {
        float a = max(age + float(k), 0.0);
        t += texture(history, vec2(m, (head + 0.5 + a) / rows)).rgb * (3.0 - abs(float(k)));
    }
    t /= 9.0;
    // Both bytes filter linearly, so recombining after filtering stays exact
    vec2 s = vec2(t.r + t.b / 255.0, t.g);
    // Flat towards the edges, like the album cover
    return vec2(s.r * amp * pow(cos(m * PI * 0.5), 1.5), s.g);
}

float heightAt(float x, float z) {
    return sampleAt(x, z).x;
}

void main() {
    vec2 uv = qt_TexCoord0;
    // Ray through this pixel: at depth z it is eye - z * dy above the floor, z * sx to the side
    float dy = uv.y - horizon;
    float sx = (uv.x - 0.5) * aspect;
    if (dy <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 color = vec4(0.0);
    float gPrev = eye - zNear * dy - heightAt(sx * zNear, zNear);
    if (eye - zNear * dy < 0.0) {
        // Below the front edge: only the live profile line can be here
    } else if (gPrev <= 0.0) {
        // The front face under the live profile
        color = vec4(shade.rgb, 1.0) * 0.55;
    } else {
        float zPrev = zNear;
        for (int i = 1; i <= STEPS; i++) {
            float f = float(i) / float(STEPS);
            // Denser steps up close, where the surface is large on screen
            float z = zNear + (zFar - zNear) * f * f;
            float g = eye - z * dy - heightAt(sx * z, z);
            if (g <= 0.0) {
                // Refine the crossing; contour lines need an accurate height to stay continuous
                float z0 = zPrev, g0 = gPrev, z1 = z, g1 = g, zh = z;
                for (int r = 0; r < 5; r++) {
                    zh = z0 + (z1 - z0) * g0 / (g0 - g1);
                    float gh = eye - zh * dy - heightAt(sx * zh, zh);
                    if (gh > 0.0) {
                        z0 = zh;
                        g0 = gh;
                    } else {
                        z1 = zh;
                        g1 = gh;
                    }
                }
                float x = sx * zh;
                vec2 s = sampleAt(x, zh);
                float e = 0.01;
                vec3 n = normalize(vec3(heightAt(x - e, zh) - heightAt(x + e, zh), 2.0 * e,
                                        heightAt(x, zh - e * 3.0) - heightAt(x, zh + e * 3.0)));
                float light = max(dot(n, normalize(vec3(-0.35, 0.8, -0.5))), 0.0);
                float h = clamp(s.x / amp, 0.0, 1.0);
                float depth = (zh - zNear) / (zFar - zNear);
                float fog = 1.0 - smoothstep(0.4, 1.0, depth);
                // Lit slopes and crests glow in the accent over a dark body; flat ground stays clear
                float crest = pow(1.0 - abs(n.z), 3.0) * smoothstep(0.05, 0.3, h);
                float glow = clamp(light * light * (0.15 + 1.2 * h) + crest * 0.8, 0.0, 1.0);
                vec3 rgb = mix(shade.rgb, accent.rgb, glow);
                rgb = mix(rgb, highlight.rgb, s.y * 0.6 + h * h * 0.15);
                float a = (0.85 * smoothstep(0.0, 0.2, h) + 0.25 * s.y) * fog;
                // Contour lines, like a topographic map: they follow the relief instead of running in rows
                float level = h * 9.0;
                float iso = 1.0 - smoothstep(0.0, 1.5 * fwidth(level), abs(fract(level + 0.5) - 0.5));
                iso *= smoothstep(0.1, 0.18, h) * fog;
                rgb = mix(rgb, mix(accent.rgb, highlight.rgb, 0.3), iso * 0.8);
                a = max(a, iso * 0.9);
                color = vec4(rgb * a, a);
                break;
            }
            zPrev = z;
            gPrev = g;
        }
    }

    // The live profile along the front edge, the brightest thing on screen
    vec2 front = sampleAt(sx * zNear, zNear);
    float lineDy = (eye - front.x) / zNear;
    float d = abs(dy - lineDy) / pixel;
    float line = 1.0 - smoothstep(0.6, 1.8 + front.y * 1.2, d);
    vec3 lineRgb = mix(accent.rgb, highlight.rgb, 0.25 + front.y * 0.6);
    float edge = abs(sx * zNear) < halfWidth ? line : 0.0;
    color = color * (1.0 - edge) + vec4(lineRgb, 1.0) * edge;

    fragColor = color * qt_Opacity;
}
