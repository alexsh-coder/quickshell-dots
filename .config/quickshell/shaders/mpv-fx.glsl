// mpv user shader for a video wallpaper: glitch.frag's wallpaper styles and wallfx.frag's red/cyan split,
// driven by VideoFx over the IPC socket (glsl-shader-opts)

//!PARAM split
//!TYPE float
0.0

//!PARAM burst
//!TYPE float
0.0

//!PARAM seed
//!TYPE float
0.0

//!PARAM tear
//!TYPE float
60.0

//!PARAM variant
//!TYPE float
0.0

//!PARAM glitch
//!TYPE float
0.0

//!PARAM rgb
//!TYPE float
0.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC wallpaper fx

float hash(float n) {
    return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float edge(vec2 p) {
    return 0.12 + 0.88 * smoothstep(0.12, 0.62, length((p - 0.5) * vec2(1.3, 1.0)));
}

vec4 piece(vec2 p, float hmax, float wmin, float wmax) {
    float coarse = floor(p.y / hmax);
    float parts = 1.0 + floor(hash(coarse + 31.0) * 3.0);
    float row = floor(p.y / (hmax / parts)) + coarse * 0.37;
    float w = wmin + hash(row + 43.0) * (wmax - wmin);
    float off = hash(row + 47.0) * w;
    float seg = floor((p.x + off) / w);
    return vec4(row, seg, seg * w - off, w);
}

float mixed(inout vec2 uv, vec2 p, vec2 px, float e, float amt, float hmax, float wmin, float wmax, float pc,
            float ps, float streak, float sh, float abk) {
    vec4 k = piece(p, hmax, wmin, wmax);
    float h = hash(k.x * 1.7 + k.y * 5.3 + 53.0);
    vec4 t = piece(p + vec2(0.0, 7.0), 9.0, 20.0, 120.0);
    float ht = hash(t.x * 2.3 + t.y * 4.1 + 83.0);
    if (h < e * pc * burst) {
        uv.x += (hash(k.x + k.y * 3.1 + 59.0) * 2.0 - 1.0) * (0.3 + 0.7 * e) * sh * amt * px.x;
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

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 px = HOOKED_pt;
    vec4 c = HOOKED_tex(pos);

    if (glitch > 0.5 && (burst > 0.0 || split > 0.0)) {
        vec2 uv = pos;
        vec2 p = pos / px;
        int v = int(variant + 0.5);
        float e = edge(pos);
        float amt = burst * tear / 60.0;
        float ab = 0.0;
        float base = 1.5;
        if (v == 0) {
            ab = mixed(uv, p, px, e, amt, 56.0, 150.0, 520.0, 0.35, 0.2, 0.15, 110.0, 20.0);
            base = 3.0;
        } else if (v == 1) {
            ab = mixed(uv, p, px, e, amt, 56.0, 150.0, 520.0, 0.35, 0.2, 0.15, 60.0, 10.0);
        } else if (v == 2) {
            ab = mixed(uv, p, px, e, amt, 56.0, 150.0, 520.0, 0.18, 0.08, 0.15, 90.0, 16.0);
        } else if (v == 3) {
            ab = mixed(uv, p, px, e, amt, 30.0, 150.0, 520.0, 0.3, 0.15, 0.1, 80.0, 12.0);
        } else if (v == 4) {
            ab = mixed(uv, p, px, e, amt, 56.0, 150.0, 520.0, 0.3, 0.0, 0.0, 90.0, 14.0);
        } else if (v == 5) {
            ab = mixed(uv, p, px, e, amt, 56.0, 150.0, 520.0, 0.22, 0.1, 0.1, 50.0, 8.0);
            base = 0.8;
        } else {
            float e2 = smoothstep(0.3, 0.75, length((pos - 0.5) * vec2(1.3, 1.0)));
            ab = mixed(uv, p, px, e2, amt, 56.0, 150.0, 520.0, 0.5, 0.2, 0.15, 80.0, 14.0);
        }
        ab += (split + base * burst) * e;
        vec2 o = vec2(ab * tear / 60.0, 0.0) * px;
        c = vec4(HOOKED_tex(uv + o).r, HOOKED_tex(uv - o).gb, c.a);
        pos = uv;
    }

    if (rgb > 0.0) {
        vec2 d = pos - 0.5;
        float l = length(d);
        vec2 o = d / max(l, 1e-4) * rgb * 4.0 * l * l * px;
        c.r = HOOKED_tex(pos + o).r;
        c.gb = HOOKED_tex(pos - o).gb;
    }
    return c;
}
