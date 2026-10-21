#version 440

// One-pixel pass for appicon.frag: finds the icon's dominant colour (rgb) and how far the rest of it
// typically strays from that (a, halved to fit). a = 0 means the icon is a single tone.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

layout(binding = 1) uniform sampler2D source;

const int GRID = 12;
const int N = GRID * GRID;
// Colours closer than this count as the same tone
const float NEAR = 0.2;

void main() {
    vec3 s[N];
    float w[N];
    for (int i = 0; i < N; i++) {
        vec4 t = texture(source, (vec2(i % GRID, i / GRID) + 0.5) / float(GRID));
        s[i] = t.a > 0.0 ? t.rgb / t.a : vec3(0.0);
        w[i] = t.a > 0.5 ? t.a * t.a : 0.0;
    }

    // The sample with the most coverage within NEAR of it
    vec3 body = vec3(0.0);
    float best = -1.0;
    for (int i = 0; i < N; i++) {
        if (w[i] <= 0.0)
            continue;
        float score = 0.0;
        for (int j = 0; j < N; j++)
            score += distance(s[i], s[j]) < NEAR ? w[j] : 0.0;
        if (score > best) {
            best = score;
            body = s[i];
        }
    }

    float sum = 0.0;
    float weight = 0.0;
    for (int i = 0; i < N; i++) {
        float d = distance(s[i], body);
        if (d > NEAR) {
            sum += d * w[i];
            weight += w[i];
        }
    }

    fragColor = vec4(body, weight > 0.0 ? sum / weight / 2.0 : 0.0);
}
