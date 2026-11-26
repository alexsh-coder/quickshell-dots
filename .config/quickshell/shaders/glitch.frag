#version 440

// Chromatic aberration with torn strips: red and blue drift apart from green by `split` px, and a burst
// (0..1) cuts the image into strips that jump sideways, with an occasional block out of place. With `styles`
// on, a burst may instead break into compression blocks or slip the frame down with interlaced lines.
// Works on premultiplied colour, so it keeps the edges of transparent widgets clean.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float split;
    float burst;
    float seed;
    float tear;
    vec2 px;
    // 0: torn strips only; 1: the wallpaper's mix, which picks a look per burst
    float styles;
    // styles 2: which pieces look
    float variant;
};

layout(binding = 1) uniform sampler2D source;

float hash(float n) {
    return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float hash2(vec2 p) {
    return hash(p.x * 17.0 + p.y * 131.0);
}

// Edge weight: little in the middle, most towards the edges
float edge(vec2 p) {
    return 0.12 + 0.88 * smoothstep(0.12, 0.62, length((p - 0.5) * vec2(1.3, 1.0)));
}

// Row and piece under a px position: rows of hmax split into 1..3, pieces wmin..wmax wide.
// x: row id, y: piece id, z: piece start in px, w: piece width in px
vec4 piece(vec2 p, float hmax, float wmin, float wmax) {
    float coarse = floor(p.y / hmax);
    float parts = 1.0 + floor(hash(coarse + 31.0) * 3.0);
    float row = floor(p.y / (hmax / parts)) + coarse * 0.37;
    float w = wmin + hash(row + 43.0) * (wmax - wmin);
    float off = hash(row + 47.0) * w;
    float seg = floor((p.x + off) / w);
    return vec4(row, seg, seg * w - off, w);
}

// Mixed pieces: chunky ones torn sideways, thin slivers between them, the odd chunk smeared into streaks.
// hmax/wmin/wmax: chunk size in px; pc/ps: chunk/sliver odds; streak: chunk smear odds; sh: shift px;
// abk: aberration px; vj: vertical jump px. Moves uv, returns the piece's aberration (0: untouched)
float mixed(inout vec2 uv, vec2 p, float e, float amt, float hmax, float wmin, float wmax, float pc, float ps,
            float streak, float sh, float abk, float vj) {
    vec4 k = piece(p, hmax, wmin, wmax);
    float h = hash(k.x * 1.7 + k.y * 5.3 + 53.0);
    vec4 t = piece(p + vec2(0.0, 7.0), 9.0, 20.0, 120.0);
    float ht = hash(t.x * 2.3 + t.y * 4.1 + 83.0);
    if (h < e * pc * burst) {
        uv.x += (hash(k.x + k.y * 3.1 + 59.0) * 2.0 - 1.0) * (0.3 + 0.7 * e) * sh * amt * px.x;
        uv.y += (hash(k.x + k.y * 2.3 + 61.0) - 0.5) * vj * e * amt * px.y;
        if (hash(k.x + k.y * 7.0 + 79.0) < streak)
            uv.x = (k.z + hash(k.x + k.y + 73.0) * k.w) * px.x;
        return (0.3 + 0.7 * hash(k.y + k.x + 67.0)) * abk * sign(hash(k.x + k.y + 71.0) - 0.5);
    }
    if (ht < e * ps * burst) {
        uv.x += (hash(t.x + t.y + 89.0) * 2.0 - 1.0) * 0.7 * sh * e * amt * px.x;
        return abk * 0.25 * sign(hash(t.y + 97.0) - 0.5);
    }
    return 0.0;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float shift = 0.0;
    float flash = 0.0;
    float invert = 0.0;
    // Per-burst look, steady across reseeds: the seed's integer part is the burst
    float look = styles > 0.5 ? fract(floor(seed) * 0.6180339) : 0.0;

    if (styles > 1.5) {
        // Torn pieces with red/cyan aberration of their own, more of them towards the edges
        vec2 p = qt_TexCoord0 / px;
        int v = int(variant + 0.5);
        float e = edge(qt_TexCoord0);
        float amt = burst * tear / 60.0;
        float ab = 0.0;
        // Base split of the whole frame, per style
        float base = 1.5;
        if (v == 0) {
            // Wide: long pieces, few of them, thrown far
            ab = mixed(uv, p, e, amt, 56.0, 150.0, 520.0, 0.35, 0.2, 0.15, 110.0, 20.0, 0.0);
            base = 3.0;
        } else if (v == 1) {
            // Soft: the same pieces, half as far and half the colour
            ab = mixed(uv, p, e, amt, 56.0, 150.0, 520.0, 0.35, 0.2, 0.15, 60.0, 10.0, 0.0);
        } else if (v == 2) {
            // Sparse: half as many pieces
            ab = mixed(uv, p, e, amt, 56.0, 150.0, 520.0, 0.18, 0.08, 0.15, 90.0, 16.0, 0.0);
        } else if (v == 3) {
            // Thin: lower pieces, a little calmer
            ab = mixed(uv, p, e, amt, 30.0, 150.0, 520.0, 0.3, 0.15, 0.1, 80.0, 12.0, 0.0);
        } else if (v == 4) {
            // Clean: only the long pieces, no slivers or streaks
            ab = mixed(uv, p, e, amt, 56.0, 150.0, 520.0, 0.3, 0.0, 0.0, 90.0, 14.0, 0.0);
        } else if (v == 5) {
            // Gentle: few pieces, short throws, faint colour
            ab = mixed(uv, p, e, amt, 56.0, 150.0, 520.0, 0.22, 0.1, 0.1, 50.0, 8.0, 0.0);
            base = 0.8;
        } else {
            // Edges: the middle stays clean, the sides tear
            float e2 = smoothstep(0.3, 0.75, length((qt_TexCoord0 - 0.5) * vec2(1.3, 1.0)));
            ab = mixed(uv, p, e2, amt, 56.0, 150.0, 520.0, 0.5, 0.2, 0.15, 80.0, 14.0, 0.0);
        }
        // The whole frame splits a little, more at the edges
        ab += (split + base * burst) * e;
        vec2 o = vec2(ab * tear / 60.0, 0.0) * px;
        vec4 r = texture(source, uv + o);
        vec4 g = texture(source, uv - o);
        vec4 c = vec4(r.r, g.g, g.b, max(r.a, g.a));
        fragColor = c * qt_Opacity;
        return;
    }

    if (burst > 0.0 && look >= 0.7) {
        // Macroblocks in px, a few smeared from one line or swapped with a neighbour
        vec2 size = vec2(32.0, 16.0) * (1.0 + floor(hash(2.0) * 3.0));
        vec2 cell = floor(uv / (px * size));
        float h = hash2(cell + 5.0);
        if (h < 0.18 * burst) {
            vec2 local = fract(uv / (px * size));
            uv = (cell + vec2(local.x, 0.5)) * px * size;
            flash = 0.3;
        } else if (h < 0.32 * burst) {
            uv += (vec2(hash2(cell + 7.0), hash2(cell + 9.0)) - 0.5) * px * size * 4.0;
            invert = step(0.85, hash2(cell + 13.0));
        }
        shift = h < 0.32 * burst ? 0.4 : 0.0;
    } else if (burst > 0.0 && look >= 0.45) {
        // The frame slips down, odd lines lag behind, a bright seam where it wraps
        float slip = (0.05 + hash(3.0) * 0.2) * burst;
        uv.y = fract(uv.y - slip);
        float line = mod(floor(qt_TexCoord0.y / px.y / 2.0), 2.0);
        uv.x += line * (hash(4.0) - 0.5) * burst * tear * 0.5 * px.x;
        flash = (1.0 - smoothstep(0.0, 0.004, abs(uv.y - (1.0 - slip)))) * 0.8;
        shift = 0.3;
    } else if (burst > 0.0) {
        // Coarse strips, a few of them torn, and thin slivers between them
        float rows = 8.0 + floor(hash(1.0) * 16.0);
        float row = floor(uv.y * rows);
        if (hash(row + 3.0) < 0.15 + 0.35 * burst)
            shift = hash(row + 7.0) * 2.0 - 1.0;
        float sliver = floor(uv.y * rows * 7.0);
        if (hash(sliver + 11.0) < 0.1 * burst)
            shift += (hash(sliver + 13.0) * 2.0 - 1.0) * 0.6;
        uv.x += shift * burst * tear * px.x;
        if (styles > 0.5 && abs(shift) > 0.8)
            invert = step(0.9, hash(row + 17.0));

        // A block copied from somewhere nearby
        vec2 cell = floor(uv * vec2(6.0, 10.0));
        if (burst > 0.4 && hash(cell.x * 17.0 + cell.y * 5.0 + 19.0) < 0.06)
            uv += (vec2(hash(cell.x + 23.0), hash(cell.y + 29.0)) - 0.5) * vec2(0.08, 0.02);
    }

    vec2 o = vec2(0.97, 0.24) * (split + burst * (6.0 + abs(shift) * 18.0) * tear / 60.0) * px;
    vec4 r = texture(source, uv + o);
    vec4 g = texture(source, uv);
    vec4 b = texture(source, uv - o);
    vec4 c = vec4(r.r, g.g, b.b, max(g.a, max(r.a, b.a)));
    // Torn strips flash a little brighter, a rare one comes out inverted
    c.rgb = mix(c.rgb, c.a - c.rgb, invert);
    c.rgb = min(c.rgb * (1.0 + (abs(shift) * 0.25 + flash) * burst), vec3(c.a));
    fragColor = c * qt_Opacity;
}
