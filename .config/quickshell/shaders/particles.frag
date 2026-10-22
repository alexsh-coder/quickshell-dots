#version 440

// Particles flying out of the centre, Trap Nation style. Space is cut into cells by angle and by
// log radius, each cell holds at most one particle, and the whole grid slides outwards: in log radius
// that is a constant shift, so particles speed up as they leave the centre, like stars at warp.
// offsets carries each layer's shift in cells, already wrapped at the hash period.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float aspect;
    float pixel;
    float inner;
    float speed;
    float level;
    vec4 offsets;
    vec4 accent;
    vec4 highlight;
    vec2 origin;
    float zoom;
    float density;
    float dotScale;
};

const float TAU = 6.28318530718;
const float PERIOD = 4096.0;

float hash(vec2 p) {
    p = fract(p * vec2(0.1031, 0.1030));
    p += dot(p, p.yx + 33.33);
    return fract((p.x + p.y) * p.x);
}

vec3 layer(vec2 p, float r, float ang, float sectors, float density, float shift, float seed) {
    float cell = TAU / sectors;
    float u = log(r) / cell - shift;
    float si = floor(ang / TAU * sectors);
    float ci = floor(u);
    vec3 acc = vec3(0.0);
    // The streak trails back towards the centre, so cells further in can reach this pixel
    for (int k = -3; k <= 1; k++) {
        float ck = ci + float(k);
        vec2 id = vec2(si + seed * 97.0, mod(ck, PERIOD));
        float h = hash(id);
        if (h > density)
            continue;
        float h2 = hash(id + 17.3), h3 = hash(id + 41.9);
        float pa = (si + 0.25 + 0.5 * h2) / sectors * TAU - TAU * 0.5;
        float pr = exp((ck + 0.5 + shift) * cell + (h3 - 0.5) * cell * 0.8);
        vec2 dir = vec2(cos(pa), sin(pa));
        vec2 d = p - dir * pr;
        float along = dot(d, dir), across = dot(d, vec2(-dir.y, dir.x));

        // Grows with distance, as if coming closer; streaks with the current speed
        float size = pixel / zoom * dotScale * (1.0 + h2 * 1.5) * (0.6 + pr * 2.2);
        float tail = pr * speed * 0.06;
        float t = clamp(along, -tail, 0.0);
        float dist = length(vec2(along - t, across)) / size;
        float tailFade = tail > 0.0 ? 1.0 - (-t / tail) * 0.8 : 1.0;

        float core = 1.0 - smoothstep(0.6, 1.2, dist);
        float glow = exp(-dist * 1.4) * 0.35;
        float fade = smoothstep(inner, inner * 1.8, pr);
        float twinkle = 0.55 + 0.45 * h3;
        float a = (core + glow) * tailFade * fade * twinkle;
        vec3 rgb = mix(highlight.rgb, accent.rgb, h * 0.7 / density);
        acc += rgb * a;
    }
    return acc;
}

void main() {
    vec2 p = ((qt_TexCoord0 - 0.5) * vec2(aspect, 1.0) - origin) / zoom;
    float r = max(length(p), 1e-4);
    float ang = atan(p.y, p.x) + TAU * 0.5;
    if (r < inner * 0.9) {
        fragColor = vec4(0.0);
        return;
    }

    vec3 c = layer(p, r, ang, 70.0, min(0.08 * density, 1.0), offsets.x, 1.0)
           + layer(p, r, ang, 110.0, min(0.032 * density, 1.0), offsets.y, 2.0)
           + layer(p, r, ang, 170.0, min(0.016 * density, 1.0), offsets.z, 3.0);
    c *= 0.75 + level * 0.6;
    float a = clamp(max(c.r, max(c.g, c.b)), 0.0, 1.0);
    fragColor = vec4(min(c, vec3(1.0)), a) * qt_Opacity;
}
