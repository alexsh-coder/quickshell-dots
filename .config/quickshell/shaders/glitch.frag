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
};

layout(binding = 1) uniform sampler2D source;

float hash(float n) {
    return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float hash2(vec2 p) {
    return hash(p.x * 17.0 + p.y * 131.0);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float shift = 0.0;
    float flash = 0.0;
    float invert = 0.0;
    // Per-burst look, steady across reseeds: the seed's integer part is the burst
    float look = styles > 0.5 ? fract(floor(seed) * 0.6180339) : 0.0;

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
