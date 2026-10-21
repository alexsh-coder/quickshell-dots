#version 440

// Turns a full-colour icon into a symbolic one in a single colour: the dominant tone becomes solid,
// details that contrast with it (the plane on a round badge, a logo inside a circle) are cut out.
// Icons that are already one tone just get recoloured.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;
};

layout(binding = 1) uniform sampler2D source;

const int GRID = 12;

float luma(vec4 c) {
    return c.a > 0.0 ? dot(c.rgb / c.a, vec3(0.2126, 0.7152, 0.0722)) : 0.0;
}

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Coverage-weighted mean tone, then how far the icon strays from it at most
    float sum = 0.0;
    float weight = 0.0;
    for (int y = 0; y < GRID; y++)
        for (int x = 0; x < GRID; x++) {
            vec4 s = texture(source, (vec2(x, y) + 0.5) / float(GRID));
            sum += luma(s) * s.a * s.a;
            weight += s.a * s.a;
        }
    float mean = sum / max(weight, 1e-4);
    float spread = 0.0;
    for (int y = 0; y < GRID; y++)
        for (int x = 0; x < GRID; x++) {
            vec4 s = texture(source, (vec2(x, y) + 0.5) / float(GRID));
            if (s.a > 0.5)
                spread = max(spread, abs(luma(s) - mean));
        }

    float d = spread > 0.15 ? abs(luma(c) - mean) / spread : 0.0;
    float keep = 1.0 - smoothstep(0.35, 0.65, d);
    fragColor = vec4(color.rgb, 1.0) * c.a * keep * qt_Opacity;
}
