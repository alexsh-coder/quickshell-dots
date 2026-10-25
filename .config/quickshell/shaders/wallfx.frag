#version 440

// Music effects over the wallpaper copy, each off at 0: rings rippling out from `center`, VHS wobble with
// scanlines and grain, bloom on the highlights, a flash on kicks and a hue rotation.
// Bloom reads `glow`, a blurred copy of the same image.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float pulse;
    float bloom;
    float vhs;
    float hue;
    float hueMix;
    float time;
    vec2 px;
    vec2 center;
    // Seconds since each ring started (< 0: none) and its push in px
    vec4 ages;
    vec4 amps;
    // Extra saturation and contrast, with bloom
    float sat;
    float contrast;
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D glow;

const float LIFE = 1.4;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 res = 1.0 / px;
    float shine = 0.0;

    // Rings: a crest that pushes the image outwards and a trough behind it
    if (amps != vec4(0.0)) {
        vec2 d = (uv - center) * res;
        float dist = length(d);
        vec2 dir = d / max(dist, 1.0);
        float push = 0.0;
        for (int i = 0; i < 4; i++) {
            float age = ages[i];
            if (age < 0.0 || age > LIFE)
                continue;
            float r = age * res.y * 0.9;
            float x = (dist - r) / (res.y * 0.05);
            float env = exp(-x * x * 1.5);
            float fall = pow(1.0 - age / LIFE, 2.0) * smoothstep(0.0, 0.08, age);
            push += env * sin(x * 2.5) * amps[i] * fall;
            shine += env * max(0.0, sin(x * 2.5)) * fall * amps[i] / 40.0;
        }
        uv -= dir * push * px;
    }

    // Tape: lines wobble, a tracking band rolls down
    if (vhs > 0.0) {
        float line = floor(uv.y * res.y / 2.0);
        float wob = sin(uv.y * 40.0 + time * 6.0) * 0.6 + sin(uv.y * 170.0 - time * 11.0) * 0.4;
        float band = fract(uv.y * 0.8 - time * 0.09);
        float track = smoothstep(0.0, 0.015, band) * (1.0 - smoothstep(0.015, 0.05, band));
        uv.x += (wob * 1.5 + track * (hash(vec2(line, floor(time * 30.0))) - 0.5) * 14.0) * vhs * px.x;
    }

    vec4 c = texture(source, uv);
    if (vhs > 0.0) {
        // Chroma bleeds sideways, as on tape
        vec2 o = vec2(2.5 * vhs * px.x, 0.0);
        c.r = texture(source, uv + o).r;
        c.b = texture(source, uv - o).b;
    }

    if (bloom > 0.0) {
        // Dreamy glow: the blurred light parts screened over the image, richer in color than the source
        vec3 g = texture(glow, uv).rgb;
        float gl = dot(g, vec3(0.299, 0.587, 0.114));
        // Only what stands out from the picture glows: on a light wallpaper that's its real highlights,
        // not the whole screen fogging over
        float avg = 0.0;
        for (int i = 0; i < 9; i++)
            avg += dot(texture(glow, vec2(float(i % 3), float(i / 3)) * 0.33 + 0.17).rgb, vec3(0.299, 0.587, 0.114));
        avg /= 9.0;
        float knee = mix(0.25, avg + 0.08, smoothstep(0.3, 0.7, avg));
        g = max(mix(vec3(gl), g, 1.3), 0.0) * smoothstep(knee, knee + 0.4, gl);
        // Lighter on what's already light, so it spills into the dark parts instead of whiting out
        float here = dot(c.rgb, vec3(0.299, 0.587, 0.114));
        // Soft knee instead of a clamp, so a strong glow stays colored instead of going white
        g = (1.0 - exp(-g * bloom * (1.0 - here * 0.85))) * c.a;
        c.rgb = c.rgb + g - c.rgb * g;
    }

    if (sat > 0.0) {
        // Vibrance: dull colors get the most, already vivid ones (a pink wallpaper) little
        float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
        float hi = max(c.r, max(c.g, c.b));
        float s = (hi - min(c.r, min(c.g, c.b))) / max(hi, 1e-4);
        c.rgb = clamp(mix(vec3(l), c.rgb, 1.0 + sat * 0.7 * (1.0 - s)), 0.0, c.a);
    }
    if (contrast > 0.0) {
        // S-curve, two thirds on brightness alone and a third per channel, which also spreads the colors
        // a little: darks deeper, lights brighter, without turning pastels loud
        vec3 n = c.rgb / max(c.a, 1e-4);
        float l = dot(n, vec3(0.299, 0.587, 0.114));
        // Mostly deeper shadows: near-white parts barely move, so they don't burn out
        float k = contrast * mix(1.0, 0.3, smoothstep(0.5, 1.0, l));
        float lt = mix(l, l * l * (3.0 - 2.0 * l), k);
        vec3 bright = n * lt / max(l, 1e-4);
        // Scaled back where a channel would clip, keeping the hue
        bright /= max(1.0, max(bright.r, max(bright.g, bright.b)));
        vec3 spread = clamp(mix(n, n * n * (3.0 - 2.0 * n), k), 0.0, 1.0);
        c.rgb = mix(bright, spread, 0.33) * c.a;
    }

    c.rgb += shine * 0.25;
    if (pulse > 0.0) {
        // Flash: up to ~30% brighter, scaled back where a channel would clip so colors keep their hue
        // instead of going white, and a touch more saturation only for the dull ones (vibrance)
        vec3 n = c.rgb / max(c.a, 1e-4);
        vec3 f = n * min(1.0 + pulse * 0.15, 1.3);
        f /= max(1.0, max(f.r, max(f.g, f.b)));
        float chroma = max(n.r, max(n.g, n.b)) - min(n.r, min(n.g, n.b));
        float l = dot(f, vec3(0.299, 0.587, 0.114));
        f = clamp(mix(vec3(l), f, 1.0 + min(pulse, 2.0) * 0.2 * (1.0 - chroma)), 0.0, 1.0);
        c.rgb = f * c.a;
    }

    if (hueMix > 0.0) {
        // Rotation around the grey axis keeps the brightness
        const vec3 k = vec3(0.57735);
        float s = sin(hue), co = cos(hue);
        vec3 r = c.rgb * co + cross(k, c.rgb) * s + k * dot(k, c.rgb) * (1.0 - co);
        c.rgb = mix(c.rgb, r, hueMix);
    }

    if (vhs > 0.0) {
        float scan = 0.5 + 0.5 * sin(qt_TexCoord0.y * res.y * 2.094);
        c.rgb *= 1.0 - scan * 0.12 * min(vhs, 1.5);
        c.rgb += (hash(qt_TexCoord0 * res + fract(time * 7.3) * 91.0) - 0.5) * 0.07 * vhs;
    }

    fragColor = vec4(clamp(c.rgb, 0.0, 1.0), 1.0) * c.a * qt_Opacity;
}
