#version 440

// Shows the source only inside a growing circle, so it spreads over whatever lies underneath.
// Sizes are in item pixels; the edge is antialiased over one pixel.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;
    vec2 center;
    vec2 extent;
    // Share of the texture the item shows on each axis: a centred crop, as fillMode PreserveAspectCrop
    vec2 crop;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    float d = distance(qt_TexCoord0 * extent, center);
    vec2 uv = 0.5 + (qt_TexCoord0 - 0.5) * crop;
    fragColor = texture(source, uv) * (1.0 - smoothstep(radius - 0.5, radius + 0.5, d)) * qt_Opacity;
}
