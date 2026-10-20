#version 440

// Sakura petals drifting down in a few parallax layers. Each grid cell may hold one petal that
// sways, spins and tumbles (squashed along its short axis to fake a 3D flip).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float density;
    vec4 tint;
};

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x * aspect, qt_TexCoord0.y);
    float acc = 0.0;
    for (int i = 0; i < 4; i++) {
        float layer = float(i);
        float scale = 3.0 + layer * 2.2;
        vec2 q = p * scale;
        q.y -= time * (0.11 - layer * 0.018) * scale;
        q.x += time * 0.05 * scale + sin(time * 0.21 + layer * 1.7) * 0.4;
        vec2 id = floor(q);
        float h = hash(id + layer * 17.0);
        if (h > density)
            continue;
        vec2 d = fract(q) - 0.5 - (vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5) * 0.3;
        d.x += sin(time * 0.8 + h * 40.0) * 0.08;
        float ang = h * 6.2832 + time * (0.4 + h) * (h > 0.5 ? 1.0 : -1.0);
        float c = cos(ang), s = sin(ang);
        d = mat2(c, -s, s, c) * d;
        float size = 0.07 * (0.7 + 0.6 * hash(id + 1.3));
        float flip = 0.3 + 0.7 * abs(cos(time * 1.3 + h * 30.0));
        float e = length(vec2(d.x / size, d.y / (size * 0.55 * flip)));
        float notch = smoothstep(size * 0.3, size * 0.2, length(d - vec2(size, 0.0)));
        float a = smoothstep(1.0, 0.7, e) * (1.0 - notch);
        acc += a * (0.55 - layer * 0.11);
    }
    // Qt hands colour uniforms over premultiplied
    fragColor = tint * min(acc, 1.0) * qt_Opacity;
}
