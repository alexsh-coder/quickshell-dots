#version 440

// Wallpaper transitions: draws the new wallpaper (source) over whatever lies underneath.
// When the old one (previous) is known it is drawn too, so effects can move or distort it;
// otherwise what isn't new yet stays transparent and the real wallpaper shows through.
// s runs 0..1 from the edge the switch comes from, q across it.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Linear 0..1
    float t;
    float mode;
    float hasFrom;
    // Item size in pixels
    vec2 extent;
    // Share of each texture shown on each axis: a centred crop, as fillMode PreserveAspectCrop
    vec2 cropTo;
    vec2 cropFrom;
    // s = axis.x * u + axis.y * v + axis.z
    vec4 axis;
    // Circle and ripple: where they grow from, and how far they have got (pixels)
    vec2 center;
    float radius;
    vec4 glow;
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D previous;

const float PI = 3.14159265;

bool inside(vec2 uv) {
    return uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
}

vec4 texTo(vec2 uv) {
    return inside(uv) ? texture(source, 0.5 + (uv - 0.5) * cropTo) : vec4(0.0);
}

vec4 texFrom(vec2 uv) {
    return hasFrom > 0.5 && inside(uv) ? texture(previous, 0.5 + (uv - 0.5) * cropFrom) : vec4(0.0);
}

vec4 over(vec4 top, vec4 bottom) {
    return top + bottom * (1.0 - top.a);
}

// The old wallpaper darkened by k; without it, a translucent black over the real one
vec4 dimFrom(vec2 uv, float k) {
    return hasFrom > 0.5 ? vec4(texFrom(uv).rgb * (1.0 - k), 1.0) : vec4(0.0, 0.0, 0.0, k);
}

float easeInOut(float x) {
    return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0;
}

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = p * 2.03 + 17.1;
        a *= 0.5;
    }
    return v;
}

bool horizontal() {
    return abs(axis.x) > 0.5;
}

float along(vec2 uv) {
    return axis.x * uv.x + axis.y * uv.y + axis.z;
}

float across(vec2 uv) {
    return horizontal() ? uv.y : uv.x;
}

vec2 uvAt(float s, float q) {
    return horizontal() ? vec2((s - axis.z) / axis.x, q) : vec2(q, (s - axis.z) / axis.y);
}

vec4 circle(vec2 uv) {
    float d = distance(uv * extent, center);
    return texTo(uv) * (1.0 - smoothstep(radius - 0.5, radius + 0.5, d));
}

// The new one pushes in, the old one drifts a little and darkens
vec4 slide(vec2 uv) {
    float e = easeInOut(t);
    vec2 dir = axis.xy;
    vec2 tu = uv + dir * (1.0 - e);
    if (inside(tu))
        return texTo(tu);
    float s = along(uv);
    float shade = 0.45 * e + 0.35 * exp(-(s - e) * 14.0) * e;
    return dimFrom(uv - dir * 0.3 * e, min(shade, 0.85));
}

// A slanted soft edge with a streak of light along it
vec4 wipe(vec2 uv) {
    float e = easeInOut(t);
    float w = 0.14;
    float x = along(uv) + (across(uv) - 0.5) * 0.25;
    float th = mix(-0.125 - w, 1.125, e);
    float m = 1.0 - smoothstep(th, th + w, x);
    vec4 c = texTo(uv) * m;
    float streak = exp(-abs(x - th - w * 0.5) * 60.0) * sin(PI * e) * 0.45;
    return vec4(c.rgb + glow.rgb * streak, max(c.a, streak));
}

vec4 fade(vec2 uv) {
    float e = easeInOut(t);
    vec2 tu = 0.5 + (uv - 0.5) / (1.0 + 0.06 * (1.0 - e));
    return texTo(tu) * e;
}

// Burns through the old one along a noisy front with a glowing rim
vec4 burn(vec2 uv) {
    float asp = extent.x / extent.y;
    float n = clamp((fbm(uv * vec2(asp, 1.0) * 3.0) - 0.3) / 0.4, 0.0, 1.0);
    n = mix(n, along(uv), 0.4);
    float th = mix(0.05, 0.95, t) * 1.3 - 0.15;
    float d = th - n;
    float w = 0.04;
    float m = smoothstep(0.0, 0.012, d);
    vec4 c = texTo(uv) * m;
    // Charring just ahead of the front
    float charred = d < 0.0 ? (1.0 - smoothstep(0.0, w * 2.0, -d)) * 0.9 : 0.0;
    c = over(c, m < 1.0 ? dimFrom(uv, charred) * (1.0 - m) : vec4(0.0));
    float rim = (1.0 - smoothstep(0.0, w, abs(d - 0.006))) * step(0.001, t) * step(t, 0.999);
    vec3 hot = glow.rgb * rim * 1.2 + vec3(1.0, 0.95, 0.85) * pow(rim, 6.0) * 0.9;
    return vec4(c.rgb + hot, max(c.a, min(1.0, rim)));
}

// Squares pop in, holding a pixelated copy that sharpens at the end; the old one pixelates away
vec4 pixels(vec2 uv) {
    vec2 px = uv * extent;
    float cellPx = extent.x / 26.0;
    vec2 cell = floor(px / cellPx);
    vec2 cuv = (cell + 0.5) * cellPx / extent;
    float a = mix(hash(cell), along(cuv), 0.55) * 0.62;
    float local = clamp((t - a) / 0.3, 0.0, 1.0);
    // easeOutBack: a slight overshoot as each one lands
    float k = local - 1.0;
    float size = local <= 0.0 ? 0.0 : 1.0 + 2.7 * k * k * k + 1.7 * k * k;
    vec2 f = abs(px / cellPx - cell - 0.5);
    bool shown = max(f.x, f.y) < 0.5 * size;
    float blockTo = mix(cellPx, 1.0, smoothstep(0.62, 1.0, t));
    vec2 bt = (floor(px / blockTo) + 0.5) * blockTo / extent;
    if (shown)
        return texTo(blockTo <= 1.01 ? uv : bt);
    float blockFrom = mix(1.0, cellPx, smoothstep(0.0, 0.45, t));
    vec2 bf = (floor(px / blockFrom) + 0.5) * blockFrom / extent;
    return texFrom(blockFrom <= 1.01 ? uv : bf);
}

vec4 glitchSample(vec2 uv, bool next, float ca) {
    vec4 g = next ? texTo(uv) : texFrom(uv);
    float r = (next ? texTo(uv + vec2(ca, 0.0)) : texFrom(uv + vec2(ca, 0.0))).r;
    float b = (next ? texTo(uv - vec2(ca, 0.0)) : texFrom(uv - vec2(ca, 0.0))).b;
    return vec4(r * g.a, g.g, b * g.a, g.a);
}

// Bands flicker between the two, torn sideways, with split colour and scanlines
vec4 glitch(vec2 uv) {
    float amp = pow(sin(PI * t), 0.6);
    float k = floor(t * 22.0);
    float rows = mix(6.0, 38.0, hash(vec2(k, 3.7)));
    float band = floor(uv.y * rows);
    float rb = hash(vec2(band, k));
    float shift = (rb - 0.5) * 0.22 * amp * step(0.5, rb);
    // Some rectangular blocks jump further
    vec2 blk = floor(uv * vec2(7.0, 15.0) + k * 1.3);
    float rk = hash(blk + k);
    shift += step(0.88, rk) * (hash(blk * 1.7) - 0.5) * 0.3 * amp;
    bool next = hash(vec2(band * 7.13, k + 0.5)) < smoothstep(0.08, 0.9, t);
    if (rk > 0.94)
        next = !next;
    if (t > 0.96)
        next = true;
    if (t < 0.03)
        next = false;
    vec2 su = vec2(uv.x + shift, uv.y);
    vec4 c = glitchSample(su, next, 0.014 * amp);
    float line = step(0.5, fract(uv.y * extent.y / 3.0));
    c.rgb *= 1.0 - 0.18 * amp * line;
    if (rb > 0.93)
        c.rgb = mix(c.rgb, glow.rgb * c.a, 0.55 * amp);
    return c;
}

// The old page peels off over a cylinder, showing its back
vec4 curl(vec2 uv) {
    float q = across(uv);
    float k = 0.25;
    float R = 0.07;
    float u = along(uv) + k * (q - 0.5);
    float e0 = k * (q - 0.5);
    float c = mix(-k * 0.5, 1.0 + k * 0.5 + R + 0.02, easeInOut(t));
    vec3 paper = vec3(0.95, 0.95, 0.93);

    // Flap lying on top after going round the cylinder
    if (u >= c) {
        float sf = 2.0 * c - u - PI * R;
        if (sf >= e0 && c > e0 + PI * R) {
            vec2 fu = uvAt(sf - e0, q);
            vec3 back = hasFrom > 0.5 ? mix(texFrom(fu).rgb, paper, 0.8) : paper;
            float edge = smoothstep(0.0, 0.01, sf - e0);
            return vec4(back * 0.97, 1.0) * edge + dimFrom(uv, 0.4) * (1.0 - edge);
        }
        float uf = 2.0 * c - PI * R - e0;
        float shadow = u > uf && c > e0 + PI * R ? 0.35 * exp(-(u - uf) * 40.0) : 0.0;
        return dimFrom(uv, shadow);
    }
    if (u > c - R) {
        float a = clamp((c - u) / R, 0.0, 1.0);
        float up = PI - asin(a);
        float su = c - R * up;
        if (su >= e0) {
            vec2 fu = uvAt(su - e0, q);
            vec3 back = hasFrom > 0.5 ? mix(texFrom(fu).rgb, paper, 0.8) : paper;
            return vec4(back * (0.7 - 0.3 * cos(up)), 1.0);
        }
        float lo = asin(a);
        float sl = c - R * lo;
        if (sl >= e0) {
            vec2 fu = uvAt(sl - e0, q);
            vec3 front = hasFrom > 0.5 ? texFrom(fu).rgb : paper * 0.8;
            return vec4(front * (0.55 + 0.45 * cos(lo)), 1.0);
        }
    }
    float shadow = 0.5 * exp(-max(0.0, c - R - u) * 22.0) * step(e0 + 0.001, c) * (1.0 - smoothstep(0.85, 1.0, t));
    vec4 n = texTo(uv);
    return vec4(n.rgb * (1.0 - shadow), n.a);
}

// Jagged rip line in the old page, s measured in the unit of along()
float tearAt(float q) {
    return 0.5 + 0.05 * (fbm(vec2(q * 5.0, 1.3)) - 0.5) + 0.012 * (noise(vec2(q * 90.0, 7.7)) - 0.5);
}

// Where pixel p falls on half `side` (-1 toward the origin, 1 away) of the torn page: x is the
// uv there, z how far into the half from the rip, w < 0 when off the half
vec4 tearHalf(vec2 p, float side, float e) {
    vec2 dir = axis.xy * side;
    float len = horizontal() ? extent.x : extent.y;
    vec2 drop = horizontal() ? vec2(0.0, extent.y * 0.25 * e * e) : vec2(0.0);
    vec2 move = dir * 1.1 * e * len + drop;
    float ang = 0.32 * e * ((dir.x + dir.y) >= 0.0 ? 1.0 : -1.0);
    vec2 pivot = extent * 0.5;
    vec2 d = p - pivot - move;
    float cs = cos(-ang);
    float sn = sin(-ang);
    vec2 p0 = vec2(cs * d.x - sn * d.y, sn * d.x + cs * d.y) + pivot;
    vec2 uv0 = p0 / extent;
    float into = (along(uv0) - tearAt(across(uv0))) * side;
    return vec4(uv0, into, inside(uv0) && into >= 0.0 ? 1.0 : -1.0);
}

vec4 tear(vec2 uv) {
    // Slow to come apart, then falling away
    float e = pow(t, 2.2);
    vec2 p = uv * extent;
    vec3 paper = vec3(0.96, 0.95, 0.92);
    float seam = smoothstep(0.0, 0.04, e);
    for (int i = 0; i < 2; i++) {
        vec4 h = tearHalf(p, i == 0 ? -1.0 : 1.0, e);
        if (h.w > 0.0) {
            float fiber = 0.004 + 0.006 * noise(vec2(across(h.xy) * 220.0, float(i) * 9.0));
            if (h.z < fiber * seam)
                return vec4(paper, 1.0);
            return hasFrom > 0.5 ? texFrom(h.xy) : vec4(0.0);
        }
    }
    float shadow = 0.0;
    vec2 off = vec2(10.0, 16.0) * e;
    for (int i = 0; i < 2; i++)
        shadow = max(shadow, tearHalf(p - off, i == 0 ? -1.0 : 1.0, e).w > 0.0 ? 0.45 : 0.0);
    vec4 n = texTo(uv);
    return vec4(n.rgb * (1.0 - shadow * seam), n.a);
}

// Slats flip over one after another
vec4 blinds(vec2 uv) {
    float n = 10.0;
    float s = along(uv);
    float idx = floor(s * n);
    float local = easeInOut(clamp(t * 1.8 - idx / n * 0.8, 0.0, 1.0));
    float f = fract(s * n) - 0.5;
    float h = abs(cos(PI * local)) * 0.5;
    vec4 gap = vec4(0.0, 0.0, 0.0, 0.6 * sin(PI * local));
    if (abs(f) >= h)
        return gap;
    float src = (idx + 0.5 + f * 0.5 / max(h, 0.001)) / n;
    vec2 su = uvAt(src, across(uv));
    float shade = 0.55 + 0.45 * (2.0 * h);
    vec4 c = local < 0.5 ? texFrom(su) : texTo(su);
    return over(vec4(c.rgb * shade, c.a), gap);
}

vec4 hexCell(vec2 p) {
    vec2 r = vec2(1.0, 1.7320508);
    vec2 h = r * 0.5;
    vec2 a = mod(p, r) - h;
    vec2 b = mod(p - h, r) - h;
    vec2 g = dot(a, a) < dot(b, b) ? a : b;
    return vec4(g, p - g);
}

float hexDist(vec2 p) {
    p = abs(p);
    return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

// Hexagons grow in a wave from the edge, rimmed with light while they do
vec4 honeycomb(vec2 uv) {
    float asp = extent.x / extent.y;
    float scale = 9.0;
    vec4 hc = hexCell(uv * vec2(asp, 1.0) * scale);
    vec2 cuv = hc.zw / scale / vec2(asp, 1.0);
    float a = mix(along(cuv), hash(floor(hc.zw * 10.0)), 0.25) * 0.68;
    float local = clamp((t - a) / 0.32, 0.0, 1.0);
    float d = hexDist(hc.xy);
    float r = 0.5 * easeInOut(local) * 1.08;
    float m = 1.0 - smoothstep(r - 0.02, r, d);
    vec4 c = texTo(uv) * m;
    float rim = exp(-abs(d - r) * 60.0) * sin(PI * local);
    return vec4(c.rgb + glow.rgb * rim * 0.9, max(c.a, rim));
}

// A wave front spreads from the edge, refracting both sides of it
vec4 ripple(vec2 uv) {
    vec2 p = uv * extent;
    float d = distance(p, center);
    vec2 dir = d > 0.0 ? (p - center) / d : vec2(0.0);
    float w = 0.08 * length(extent);
    float x = (radius - d) / w;
    if (x >= 0.0) {
        float bump = x < 1.0 ? sin(x * PI) : 0.0;
        float rings = sin(d * 0.045 - t * 18.0) * 6.0 * (1.0 - t);
        vec2 tu = (p - dir * (bump * 0.4 * w + rings)) / extent;
        vec4 c = texTo(tu);
        float shine = bump * bump * 0.35;
        return vec4(c.rgb + glow.rgb * shine * c.a, c.a);
    }
    float y = -x;
    float bump = y < 0.6 ? sin(y / 0.6 * PI) * (1.0 - y / 0.6) * smoothstep(0.0, 0.1, t) : 0.0;
    return texFrom((p + dir * bump * 0.25 * w) / extent);
}

vec2 rotateAround(vec2 uv, float ang) {
    float asp = extent.x / extent.y;
    vec2 v = (uv - 0.5) * vec2(asp, 1.0);
    float cs = cos(ang);
    float sn = sin(ang);
    v = vec2(cs * v.x - sn * v.y, sn * v.x + cs * v.y);
    return v / vec2(asp, 1.0) + 0.5;
}

// Both twist into a vortex at the centre and the new one unwinds out of it
vec4 swirl(vec2 uv) {
    float asp = extent.x / extent.y;
    float r = length((uv - 0.5) * vec2(asp, 1.0)) / (0.5 * length(vec2(asp, 1.0)));
    float strength = pow(sin(PI * t), 2.0) * 7.0 * pow(max(0.0, 1.0 - r), 2.0);
    vec2 su = clamp(rotateAround(uv, strength), 0.0, 1.0);
    float m = smoothstep(0.0, 1.0, clamp((t - 0.25 + (r - 0.5) * 0.4) / 0.5, 0.0, 1.0));
    return texTo(su) * m + texFrom(su) * (1.0 - m);
}

void main() {
    vec2 uv = qt_TexCoord0;
    int m = int(mode + 0.5);
    vec4 c;
    if (m == 1)
        c = slide(uv);
    else if (m == 2)
        c = wipe(uv);
    else if (m == 3)
        c = fade(uv);
    else if (m == 4)
        c = burn(uv);
    else if (m == 5)
        c = pixels(uv);
    else if (m == 6)
        c = glitch(uv);
    else if (m == 7)
        c = curl(uv);
    else if (m == 8)
        c = tear(uv);
    else if (m == 9)
        c = blinds(uv);
    else if (m == 10)
        c = honeycomb(uv);
    else if (m == 11)
        c = ripple(uv);
    else if (m == 12)
        c = swirl(uv);
    else
        c = circle(uv);
    fragColor = c * qt_Opacity;
}
