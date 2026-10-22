#version 440

// Wallpaper transitions: draws the new wallpaper (source) over whatever lies underneath.
// When the old one (previous) is known it is drawn too, so effects can move or distort it;
// otherwise what isn't new yet stays transparent and the real wallpaper shows through.
// s runs 0..1 from the edge the switch comes from, q across it; spread() is s, or the distance
// from the cursor when the switch starts there.

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
    // From the cursor (radial = 1): where it is, in uv. Reveals then spread out from there
    vec2 point;
    float radial;
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

float aspect() {
    return extent.x / extent.y;
}

// Farthest corner from p, in height units
float reach(vec2 p) {
    vec2 a = vec2(aspect(), 1.0);
    return max(max(length(p * a), length((p - vec2(1.0, 0.0)) * a)), max(length((p - vec2(0.0, 1.0)) * a), length((p - vec2(1.0)) * a)));
}

float spread(vec2 uv) {
    if (radial < 0.5)
        return along(uv);
    return length((uv - point) * vec2(aspect(), 1.0)) / reach(point);
}

// Away from where the switch starts, in uv
vec2 outward(vec2 uv) {
    if (radial < 0.5)
        return axis.xy;
    vec2 d = (uv - point) * vec2(aspect(), 1.0);
    return length(d) > 0.0001 ? normalize(d) / vec2(aspect(), 1.0) : vec2(0.0, -1.0);
}

// Middle of radial effects: the cursor, or the middle of the screen
vec2 focus() {
    return radial > 0.5 ? point : vec2(0.5);
}

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec2 rotate(vec2 v, float a) {
    float cs = cos(a);
    float sn = sin(a);
    return vec2(cs * v.x - sn * v.y, sn * v.x + cs * v.y);
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
    float x = spread(uv) + (radial > 0.5 ? 0.0 : (across(uv) - 0.5) * 0.25);
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
    n = mix(n, spread(uv), 0.4);
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
    float a = mix(hash(cell), spread(cuv), 0.55) * 0.62;
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
    float a = mix(spread(cuv), hash(floor(hc.zw * 10.0)), 0.25) * 0.68;
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

// Finer glitch: thin lines flicker over, each with its own jitter, with rare long tears,
// split colour, smeared runs of pixels and grain
vec4 signalSample(vec2 uv, bool next) {
    return next ? texTo(uv) : texFrom(uv);
}

vec4 signal(vec2 uv) {
    float amp = pow(sin(PI * t), 0.8);
    float frame = floor(t * 30.0);
    float y = uv.y * extent.y;
    float line = floor(y / 2.0);
    float r = hash(vec2(line, frame));

    // Clusters of jittering lines, and now and then a long tear
    float busy = step(0.62, noise(vec2(uv.y * 55.0, t * 14.0)));
    float jitter = (r - 0.5) * 0.02 * busy;
    float tearBand = step(0.9, noise(vec2(uv.y * 9.0, floor(t * 16.0) * 3.1)));
    float rip = tearBand * (hash(vec2(floor(uv.y * 9.0), frame)) - 0.5) * 0.18;
    vec2 su = vec2(uv.x + (jitter + rip) * amp, uv.y);

    // Smeared runs: a stretch of the line repeats one pixel
    if (r > 0.9 && amp > 0.2) {
        float run = 1.0 / mix(8.0, 40.0, hash(vec2(line, frame + 1.0)));
        su.x = floor(su.x / run) * run;
    }

    // Lines cross over one by one, gathered in loose bands
    float order = hash(vec2(line * 1.7, frame * 0.5)) * 0.35 + noise(vec2(uv.y * 6.0, floor(t * 10.0))) * 0.65;
    bool next = order < smoothstep(0.08, 0.92, t);
    if (t > 0.97)
        next = true;
    if (t < 0.02)
        next = false;

    vec2 ca = vec2(0.008 + 0.01 * noise(vec2(uv.y * 4.0, t * 9.0)), 0.0015) * amp;
    vec4 g = signalSample(su, next);
    float red = signalSample(su + ca, next).r;
    float blue = signalSample(su - ca, next).b;
    vec4 c = vec4(red * g.a, g.g, blue * g.a, g.a);

    float grain = (hash(uv * extent + t * 91.0) - 0.5) * 0.14 * amp;
    float scan = 1.0 - 0.1 * amp * step(0.5, fract(y / 2.0));
    float flicker = 1.0 + 0.12 * amp * (hash(vec2(frame, 5.3)) - 0.5);
    c.rgb = (c.rgb * scan * flicker + grain * c.a);
    if (r > 0.985)
        c.rgb = mix(c.rgb, glow.rgb * c.a, 0.6 * amp);
    return vec4(clamp(c.rgb, 0.0, 1.0), c.a);
}

// The old one crumbles into grains that blow away, front first
float dustTime(vec2 q) {
    return mix(noise(q * vec2(aspect(), 1.0) * 6.0), spread(q), 0.65) * 0.62;
}

float dustTravel(vec2 q) {
    float age = max(0.0, t - dustTime(q));
    return age * age * 1.6;
}

vec4 dust(vec2 uv) {
    float t0 = dustTime(uv);
    vec4 base = t < t0 ? texFrom(uv) : texTo(uv);
    vec2 wind = normalize(outward(uv) * vec2(aspect(), 1.0) + vec2(0.0, -0.45)) / vec2(aspect(), 1.0);
    // Where the grain now over uv started: solve q + wind * travel(q) = uv
    vec2 q = uv;
    for (int i = 0; i < 6; i++)
        q = uv - wind * dustTravel(q);
    float age = t - dustTime(q);
    float cell = 2.0;
    vec2 cq = floor(q * extent / cell);
    float grain = hash(cq);
    if (age > 0.0 && inside(q) && grain > 0.45 + age * 0.9) {
        vec4 g = texFrom((cq + 0.5) * cell / extent);
        float fade = 1.0 - smoothstep(0.15, 0.6, age);
        vec3 col = mix(g.rgb, glow.rgb * g.a, smoothstep(0.1, 0.5, age) * 0.25);
        base = over(vec4(col, g.a) * fade, base);
    }
    return base;
}

vec4 blurred(vec2 uv, float r, bool next) {
    vec4 acc = vec4(0.0);
    for (int i = 0; i < 16; i++) {
        float a = float(i) * 2.39996;
        float rr = r * sqrt((float(i) + 0.5) / 16.0);
        vec2 q = clamp(uv + vec2(cos(a), sin(a)) * rr / vec2(aspect(), 1.0), 0.0, 1.0);
        acc += next ? texTo(q) : texFrom(q);
    }
    return acc / 16.0;
}

// Melts out of focus, swaps at the blurriest, comes back sharp
vec4 dream(vec2 uv) {
    float r = sin(PI * t) * 0.035;
    float m = smoothstep(0.3, 0.7, t);
    vec4 c = r < 0.0005 ? texTo(uv) * m + texFrom(uv) * (1.0 - m) : blurred(uv, r, true) * m + blurred(uv, r, false) * (1.0 - m);
    c.rgb *= 1.0 + 0.18 * sin(PI * t);
    return c;
}

// A black hole swallows the old one, spinning it in, and the new one spills back out of it
vec4 lens(vec2 uv) {
    vec2 a = vec2(aspect(), 1.0);
    vec2 c = focus();
    vec2 v = (uv - c) * a;
    float r = length(v);
    float far = reach(c) * 1.05;
    if (t < 0.5) {
        float e = t / 0.5;
        e = e * e;
        float hole = e * far;
        if (r < hole)
            return vec4(0.0, 0.0, 0.0, 1.0);
        float near = 1.0 / (1.0 + (r - hole) / (0.12 * far));
        float rs = r + 0.35 * far * e * near;
        vec2 sv = rotate(v * rs / max(r, 0.0001), 2.5 * e * near);
        vec4 o = texFrom(c + sv / a);
        float rim = exp(-(r - hole) * 50.0) * e;
        return vec4(o.rgb + glow.rgb * rim, max(o.a, rim));
    }
    float e = (t - 0.5) / 0.5;
    float out_ = 1.0 - (1.0 - e) * (1.0 - e);
    float edge = out_ * far;
    if (r > edge)
        return vec4(0.0, 0.0, 0.0, 1.0);
    float near = 1.0 / (1.0 + (edge - r) / (0.12 * far));
    float rs = r * (1.0 - 0.4 * (1.0 - e) * near);
    vec2 sv = rotate(v * rs / max(r, 0.0001), -2.0 * (1.0 - e) * near);
    vec4 n = texTo(c + sv / a);
    float rim = exp(-(edge - r) * 50.0) * (1.0 - e);
    return vec4(n.rgb + mix(glow.rgb, vec3(1.0), 0.4) * rim, n.a);
}

// Breaks into mirrored wedges that turn, and settle into the new picture
vec4 kaleido(vec2 uv) {
    vec2 a = vec2(aspect(), 1.0);
    vec2 c = focus();
    vec2 v = (uv - c) * a;
    float k = smoothstep(0.0, 0.7, sin(PI * t));
    float seg = 2.0 * PI / 6.0;
    float ang = atan(v.y, v.x) + t * 2.0;
    float fa = abs(mod(ang, seg) - seg * 0.5);
    vec2 kuv = c + vec2(cos(fa), sin(fa)) * length(v) * (1.0 - 0.25 * k) / a;
    vec2 su = clamp(mix(uv, kuv, k), 0.0, 1.0);
    float m = smoothstep(0.4, 0.6, t);
    return texTo(su) * m + texFrom(su) * (1.0 - m);
}

// Red, green and blue fly apart, and come back together as the new picture
vec4 rgbSplit(vec2 uv) {
    float o = pow(sin(PI * t), 1.5) * 0.16;
    float m = smoothstep(0.42, 0.58, t);
    vec2 d = outward(uv) * vec2(aspect(), 1.0);
    d = length(d) > 0.0 ? normalize(d) : vec2(1.0, 0.0);
    vec2 dr = d / vec2(aspect(), 1.0) * o;
    vec2 dg = rotate(d, 2.094) / vec2(aspect(), 1.0) * o;
    vec2 db = rotate(d, 4.189) / vec2(aspect(), 1.0) * o;
    vec4 fr = texFrom(clamp(uv + dr, 0.0, 1.0)), fg = texFrom(clamp(uv + dg, 0.0, 1.0)), fb = texFrom(clamp(uv + db, 0.0, 1.0));
    vec4 tr = texTo(clamp(uv - dr, 0.0, 1.0)), tg = texTo(clamp(uv - dg, 0.0, 1.0)), tb = texTo(clamp(uv - db, 0.0, 1.0));
    vec3 f = vec3(fr.r, fg.g, fb.b);
    vec3 n = vec3(tr.r, tg.g, tb.b);
    float fa = max(fr.a, max(fg.a, fb.a));
    float na = max(tr.a, max(tg.a, tb.a));
    return vec4(f * (1.0 - m) + n * m, fa * (1.0 - m) + na * m);
}

// Spreads like paint on wet paper, pooling darker at the edge
vec4 watercolor(vec2 uv) {
    vec2 p = uv * vec2(aspect(), 1.0) * 2.5;
    vec2 warp = vec2(fbm(p + 3.1), fbm(p + 7.7)) - 0.5;
    float n = clamp((fbm(p * 1.3 + warp * 2.0) - 0.3) / 0.4, 0.0, 1.0);
    float s = mix(n, spread(uv), 0.55);
    float d = mix(-0.25, 1.3, easeInOut(t)) - s;
    float m = smoothstep(0.0, 0.03, d);
    float wet = 1.0 - smoothstep(0.0, 0.15, d);
    vec4 c = texTo(uv + warp * 0.02 * wet) * m;
    float rim = smoothstep(0.0, 0.02, d) * (1.0 - smoothstep(0.02, 0.07, d));
    c.rgb *= 1.0 - 0.35 * rim;
    c.rgb = mix(c.rgb, glow.rgb * c.a, 0.25 * rim);
    c.rgb *= 1.0 - 0.1 * (1.0 - smoothstep(0.0, 0.3, d)) * noise(uv * extent * 0.5);
    return c;
}

// Anime cut: streaks race across in bands and the new picture rides in behind them
vec4 speedlines(vec2 uv) {
    float e = easeInOut(t);
    float x = spread(uv) + (radial > 0.5 ? 0.0 : (across(uv) - 0.5) * 0.35);
    float qpx = radial > 0.5 ? atan(uv.y - point.y, (uv.x - point.x) * aspect()) * extent.y * 0.5 : across(uv) * (horizontal() ? extent.y : extent.x);
    float band = floor(qpx / 9.0);
    float delay = hash(vec2(band, 2.1)) * 0.25;
    float f = mix(-0.6, 1.5, e) - delay;
    if (x < f)
        return texTo(uv);
    float len = 0.25 + 0.5 * hash(vec2(band, 7.3));
    float streak = x - f < len ? pow(1.0 - (x - f) / len, 1.5) * step(0.3, hash(vec2(band, 3.7))) * sin(PI * e) : 0.0;
    float head = exp(-(x - f) * 300.0) * sin(PI * e);
    vec3 col = mix(vec3(1.0), glow.rgb, hash(vec2(band, 5.9)));
    float a = clamp(streak * 0.85 + head, 0.0, 1.0);
    return over(vec4(col * a, a), texFrom(uv));
}

// Tiles flip over in a wave
vec4 tiles(vec2 uv) {
    vec2 n = vec2(12.0, floor(12.0 / aspect() + 0.5));
    vec2 cell = floor(uv * n);
    vec2 f = fract(uv * n) - 0.5;
    float delay = spread((cell + 0.5) / n) * 0.6 + hash(cell) * 0.08;
    float lp = easeInOut(clamp((t - delay) / 0.32, 0.0, 1.0));
    float ang = PI * lp;
    float w = abs(cos(ang)) * 0.5;
    vec4 gap = vec4(0.0, 0.0, 0.0, 0.7 * sin(ang));
    if (abs(f.x) >= w)
        return gap;
    vec2 su = (cell + 0.5 + vec2(f.x * 0.5 / max(w, 0.001), f.y)) / n;
    vec4 c = lp < 0.5 ? texFrom(su) : texTo(su);
    return over(vec4(c.rgb * (0.55 + 0.45 * abs(cos(ang))), c.a), gap);
}

// Cherry petals blow across and the new picture opens behind them
vec4 sakura(vec2 uv) {
    float e = easeInOut(t);
    float s = spread(uv);
    float f = mix(-0.35, 1.35, e);
    float edge = s + (noise(uv * vec2(aspect(), 1.0) * 8.0) - 0.5) * 0.12;
    vec4 base = edge < f ? texTo(uv) : texFrom(uv);
    vec2 wind = outward(uv) * vec2(aspect(), 1.0);
    wind = length(wind) > 0.0 ? normalize(wind) : vec2(1.0, 0.0);
    vec2 p = uv * vec2(aspect(), 1.0) * 7.0 - wind * t * 6.0;
    p.y += sin(t * 6.0 + p.x * 0.5) * 0.3;
    vec2 cell = floor(p);
    vec2 fp = fract(p) - 0.5;
    float h = hash(cell);
    vec2 off = (vec2(hash(cell + 1.3), hash(cell + 2.7)) - 0.5) * 0.5;
    vec2 lp = rotate(fp - off, hash(cell + 4.1) * 6.28 + t * 5.0 * (h - 0.5));
    float size = 0.22 + 0.14 * hash(cell + 5.5);
    vec2 q = lp / vec2(size, size * 0.62);
    float d = length(q);
    float shape = (1.0 - smoothstep(0.85, 1.0, d)) * (1.0 - (1.0 - smoothstep(0.0, 0.2, abs(q.y))) * smoothstep(0.7, 1.0, q.x));
    float dense = exp(-pow((s - f) / 0.3, 2.0)) * pow(sin(PI * e), 0.5);
    float a = shape * step(1.0 - dense, h);
    vec3 pink = mix(vec3(1.0, 0.8, 0.87), vec3(1.0, 0.56, 0.7), clamp(q.x * 0.5 + 0.5, 0.0, 1.0)) * (0.85 + 0.15 * (1.0 - d));
    return over(vec4(pink * a, a), base);
}

// Glitch: compression gone wrong. Old pixels get dragged along by the new picture's motion,
// in 16px blocks, until each block refreshes clean
vec4 datamosh(vec2 uv) {
    vec2 px = uv * extent;
    vec2 blk = floor(px / 16.0);
    float tb = noise(blk * 0.09) * 0.42 + hash(blk * 0.37) * 0.1 + spread((blk + 0.5) * 16.0 / extent) * 0.33 + 0.08;
    if (t > tb + 0.1 || t > 0.97)
        return texTo(uv);
    if (t < tb - 0.22 || t < 0.02)
        return texFrom(uv);
    // Motion shared by neighbouring blocks, so smears run in streams; old colour bleeds along
    // it, the new picture's edges showing through
    vec2 mv = (vec2(noise(blk * 0.12 + 1.7), noise(blk * 0.12 + 9.2)) - 0.5) * 2.0;
    mv = mv / max(length(mv), 0.2) * 0.25;
    float drag = smoothstep(tb - 0.22, tb + 0.1, t);
    vec4 c = vec4(0.0);
    for (int i = 0; i < 4; i++)
        c += texFrom(uv - mv * drag * (0.4 + 0.2 * float(i)));
    c *= 0.25;
    vec4 n = texTo(uv - mv * drag * 0.1);
    c = mix(c, n, smoothstep(0.35, 1.0, drag) * 0.7);
    c.rgb = floor(c.rgb * 7.0 + 0.5) / 7.0;
    return c;
}

// Glitch: bright pixels run down in sorted streaks while each column switches over
vec4 pixelsort(vec2 uv) {
    float col = floor(uv.x * extent.x / 2.0);
    float h = hash(vec2(col, 1.7));
    float len = pow(sin(PI * t), 1.2) * (0.06 + 0.35 * hash(vec2(col, 4.2)));
    vec4 best = t > h * 0.35 + spread(uv) * 0.55 ? texTo(uv) : texFrom(uv);
    float bl = luma(best.rgb);
    for (int i = 1; i <= 12; i++) {
        vec2 q = uv - vec2(0.0, len * float(i) / 12.0);
        if (q.y < 0.0)
            break;
        vec4 c = t > h * 0.35 + spread(q) * 0.55 ? texTo(q) : texFrom(q);
        float l = luma(c.rgb);
        if (l > bl && l > 0.4) {
            best = c;
            bl = l;
        }
    }
    return best;
}

// Glitch: a broken file. Bands jump in 8px steps, repeat a chunk, swap or invert colour,
// posterize, or turn into a solid bar
vec4 corrupt(vec2 uv) {
    float frame = floor(t * 14.0);
    float y = uv.y * extent.y;
    float size = 4.0 * floor(mix(1.0, 10.0, pow(hash(vec2(floor(y / 64.0), frame)), 2.0)));
    float band = floor(y / size);
    float r = t > 0.03 && t < 0.97 ? hash(vec2(band, frame * 1.37)) : 0.0;
    bool next = hash(vec2(band * 3.1, frame)) < smoothstep(0.05, 0.95, t);
    if (t > 0.97)
        next = true;
    vec2 su = uv;
    if (r > 0.55)
        su.x += floor((hash(vec2(band, frame + 9.0)) - 0.5) * 24.0) * 8.0 / extent.x;
    if (r > 0.85) {
        float x = su.x * extent.x;
        su.x = (floor(x / 64.0) * 64.0 + mod(x, 16.0)) / extent.x;
    }
    vec4 c = next ? texTo(su) : texFrom(su);
    float k = hash(vec2(band, frame + 3.0));
    if (r > 0.72) {
        if (k < 0.3)
            c.rgb = c.brg;
        else if (k < 0.45)
            c.rgb = c.a - c.rgb;
        else if (k < 0.65)
            c.rgb = floor(c.rgb * 3.0 + 0.5) / 3.0;
    }
    if (r > 0.975) {
        float x0 = hash(vec2(band, frame + 5.0));
        if (uv.x > x0 && uv.x < x0 + 0.04 + 0.16 * k)
            c = vec4(mix(glow.rgb, vec3(0.1, 1.0, 0.45), step(0.6, k)), 1.0);
    }
    return c;
}

// Glitch: crisp slices of many heights snap in sideways at a low frame rate, colour split on the move
vec4 slices(vec2 uv) {
    float y = uv.y * extent.y;
    float id = hash(vec2(floor(y / 120.0), 0.5)) > 0.5 ? floor(y / 24.0) * 1.13 : floor(y / 5.0) * 7.7;
    float delay = hash(vec2(id, 5.0)) * 0.5;
    float lp = clamp((t - delay) / 0.45, 0.0, 1.0);
    lp = floor(lp * 10.0) / 10.0;
    float e = 1.0 - pow(1.0 - lp, 4.0);
    float dir = hash(vec2(id, 6.0)) > 0.5 ? 1.0 : -1.0;
    float moving = lp > 0.0 && lp < 1.0 ? 1.0 - e : 0.0;
    vec2 ca = vec2(0.03 * moving, 0.0);
    vec2 tu = vec2(uv.x + (1.0 - e) * dir, uv.y);
    if (inside(tu)) {
        vec4 g = texTo(tu);
        return vec4(texTo(tu + ca).r * g.a, g.g, texTo(tu - ca).b * g.a, g.a);
    }
    vec2 fu = vec2(uv.x - e * dir, uv.y);
    vec4 g = texFrom(fu);
    return vec4(texFrom(fu + ca).r * g.a, g.g, texFrom(fu - ca).b * g.a, g.a);
}

vec4 crtFrame(vec2 uv, float e, float dot_, bool next) {
    vec2 c = uv - 0.5;
    float sy = 1.0 - smoothstep(0.0, 0.6, e) * 0.997;
    float sx = 1.0 - smoothstep(0.6, 1.0, e) * 0.997;
    vec2 q = c / vec2(sx, sy) + 0.5;
    // Bulges like the glass
    q = 0.5 + (q - 0.5) * (1.0 - 0.08 * e * dot(c, c));
    vec3 col = vec3(0.0);
    if (inside(q)) {
        vec4 o = next ? texTo(q) : texFrom(q);
        col = mix(o.rgb * (1.0 + 2.5 * smoothstep(0.2, 0.7, e)), vec3(1.0), smoothstep(0.35, 0.8, e));
        col *= 1.0 - 0.3 * e * step(0.5, fract(uv.y * extent.y / 3.0));
    }
    float ay = abs(c.y) * aspect();
    float halo = (exp(-ay / (0.003 + sy * 0.5) * 2.0) + 0.5 * exp(-ay * 25.0))
        * exp(-abs(c.x) / (0.004 + sx * 0.5) * 2.0) * smoothstep(0.3, 1.0, e) * dot_;
    col = col * dot_ + mix(glow.rgb, vec3(1.0), 0.6) * halo;
    return vec4(col, 1.0);
}

// Glitch: an old TV switching off to a dot, and on again with the new picture
vec4 crt(vec2 uv) {
    if (t < 0.02 && hasFrom < 0.5)
        return vec4(0.0);
    if (t < 0.5)
        return crtFrame(uv, clamp(t / 0.38, 0.0, 1.0), 1.0 - smoothstep(0.38, 0.5, t), false);
    return crtFrame(uv, clamp((1.0 - t) / 0.38, 0.0, 1.0), 1.0 - smoothstep(0.38, 0.5, 1.0 - t), true);
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
    else if (m == 13)
        c = signal(uv);
    else if (m == 14)
        c = dust(uv);
    else if (m == 15)
        c = dream(uv);
    else if (m == 16)
        c = lens(uv);
    else if (m == 17)
        c = kaleido(uv);
    else if (m == 18)
        c = rgbSplit(uv);
    else if (m == 19)
        c = watercolor(uv);
    else if (m == 20)
        c = speedlines(uv);
    else if (m == 21)
        c = tiles(uv);
    else if (m == 22)
        c = sakura(uv);
    else if (m == 23)
        c = datamosh(uv);
    else if (m == 24)
        c = pixelsort(uv);
    else if (m == 25)
        c = corrupt(uv);
    else if (m == 26)
        c = slices(uv);
    else if (m == 27)
        c = crt(uv);
    else
        c = circle(uv);
    fragColor = c * qt_Opacity;
}
