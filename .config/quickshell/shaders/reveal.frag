#version 440

// Cuts a growing circle out of the source, so whatever lies underneath shows through it.
// Sizes are in item pixels; the edge is antialiased over one pixel.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;
    vec2 center;
    vec2 extent;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float d = distance(qt_TexCoord0 * extent, center);
    fragColor = texture(source, qt_TexCoord0) * smoothstep(radius - 0.5, radius + 0.5, d) * qt_Opacity;
}
