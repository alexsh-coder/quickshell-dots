#version 440

// Nation halo. The ring layers arrive as a mask: alpha is the halo's coverage, green marks the white
// front ring. Each halo pixel is coloured by how far it sits outside the white ring, found by stepping
// towards the centre: at rest the halo is thin and shows only the start of the palette, the rest of it
// opens up only where loud music throws the layers out. Distance is continuous, so there are no seams.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float reach;
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D palette;

const int STEPS = 32;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    if (c.a <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    // Unit step towards the centre, in texture coordinates per pixel
    vec2 dir = normalize((vec2(0.5) - qt_TexCoord0) * size) / size;
    float dist = reach;
    for (int i = 1; i <= STEPS; i++) {
        float s = reach * float(i) / float(STEPS);
        if (textureLod(source, qt_TexCoord0 + dir * s, 0.0).g > 0.5) {
            dist = s;
            break;
        }
    }
    float white = c.g / c.a;
    vec4 col = mix(textureLod(palette, vec2(dist / reach, 0.5), 0.0), vec4(1.0), white);
    fragColor = col * c.a * qt_Opacity;
}
