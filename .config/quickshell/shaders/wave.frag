#version 440

// Password line: a thin glowing stroke whose length tracks the typed length. Every keystroke
// drops a ripple at the centre that runs out to both ends and dies off.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float pixel;
    float reach;
    vec4 tint;
    vec4 hitsA;
    vec4 hitsB;
    vec4 signsA;
    vec4 signsB;
};

float ripple(float x, float t0, float sgn) {
    float a = time - t0;
    if (a < 0.0 || a > 2.5)
        return 0.0;
    float r = abs(x) - a * 2.4;
    return sgn * 0.17 * exp(-a * 2.2) * exp(-r * r * 6.0) * sin(r * 11.0);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float x = (uv.x - 0.5) * aspect;
    float len = reach * aspect;
    float disp = 0.006 * sin(x * 2.5 - time * 1.4);
    for (int i = 0; i < 4; i++) {
        disp += ripple(x, hitsA[i], signsA[i]);
        disp += ripple(x, hitsB[i], signsB[i]);
    }
    float edge = smoothstep(len, len - 0.8, abs(x));
    float dist = abs(uv.y - 0.5 - disp);
    float core = smoothstep(pixel * 1.6, 0.0, dist);
    float glow = exp(-dist / (pixel * 7.0)) * 0.4;
    // Qt hands colour uniforms over premultiplied
    fragColor = tint * (core + glow) * edge * qt_Opacity;
}
