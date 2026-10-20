#version 440

// Flat spectrogram of neon ribbons. The history texture holds one column per ribbon (red: band
// level, green: hit pulse) as a ring buffer whose row `head` is the newest frame. Each ribbon is
// mirrored around the centre: the live frame sits in the middle, older ones further out.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float aspect;
    float pixel;
    float laneBase;
    float laneGap;
    float lanes;
    float halfSpan;
    float head;
    float rows;
    vec4 accent;
    vec4 highlight;
};

layout(binding = 1) uniform sampler2D history;

void main() {
    vec2 uv = qt_TexCoord0;
    // Nearest ribbon and the distance to its centre line, in screen heights
    float lane = (laneBase - uv.y) / laneGap;
    float k = floor(lane + 0.5);
    float t = abs(uv.x - 0.5) * aspect / halfSpan;
    if (k < 0.0 || k >= lanes || t >= 1.0) {
        fragColor = vec4(0.0);
        return;
    }

    // A few taps along time round off frame-to-frame jitter; clamped at the newest row so the
    // centre never reads the oldest one across the ring's seam
    float age = t * (rows - 1.0), u = (k + 0.5) / lanes;
    vec2 s = vec2(0.0);
    for (int i = -2; i <= 2; i++) {
        float a = max(age + float(i), 0.0);
        s += texture(history, vec2(u, (head + 0.5 + a) / rows)).rg * (3.0 - abs(float(i)));
    }
    s /= 9.0;
    float body = s.r, pulse = s.g;

    // Ribbon half-thickness in pixels: a hairline at rest, swelling with the band and its pulses
    float radius = (0.7 + body * 2.5 + pulse * 13.0) * (1.0 - 0.35 * t);
    float dist = abs(lane - k) * laneGap / pixel - radius;
    float core = 1.0 - smoothstep(-0.6, 0.8, dist);
    float halo = exp(-max(dist, 0.0) / (3.0 + pulse * 6.0)) * (0.2 + pulse * 0.6);

    float fade = 1.0 - smoothstep(0.5, 1.0, t);
    vec3 rgb = mix(accent.rgb, highlight.rgb, clamp(pulse * 0.9, 0.0, 1.0));
    float a = max(core * (0.6 + 0.4 * max(body, pulse)), halo) * fade;
    fragColor = vec4(rgb * a, a) * qt_Opacity;
}
