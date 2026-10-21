#version 440

// Themes a full-colour app icon in two tones, like Android's themed icons: the icon's dominant colour
// (usually its plate) becomes `base`, everything that stands apart from it (the logo, its details) `color`.
// Icons drawn in a single colour come out solid `color`. The dominant colour comes from appicon-stats.frag.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;
    vec4 base;
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D stats;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec4 st = texture(stats, vec2(0.5));
    float spread = st.a * 2.0;
    float mark = spread > 0.0 ? smoothstep(0.15, 0.45, distance(c.rgb / c.a, st.rgb) / spread) : 1.0;
    fragColor = mix(base, color, mark) * c.a * qt_Opacity;
}
