#version 150
#extension GL_GOOGLE_include_directive : require
#include "/rendering/programs/shaders/util/preamble.h.glsl"

#include "/rendering/programs/shaders/util/tonemappers.h.glsl"

LAYOUT_SAMPLER(0, 0) uniform sampler2D texFramebuf;
LAYOUT_SAMPLER(0, 1) uniform sampler2D texBlurred;

LAYOUT_UBO(0, 4) uniform Blur {
	float exposure;
	bool applyBloom;
	bool legacyToneMapping;
	float contrast;
	float hdrMax;
	float shoulder;
	float midIn;
	float midOut;
} u_blur;

INPUT(TC_LOC, vec4, texCoord, vec4(1.0));

OUTPUT(OUT_0, vec4, color);

vec3 gamma22(vec3 x) {
	return pow(x, vec3(1.0 / 2.2));
}

vec3 legacyToneMapAndGammaAndContrastBump(vec3 x) {
	x = (x * (6.2 * x + vec3(.5))) / (x * (6.2 * x + vec3(1.7)) + vec3(.06));
	float lb = .0 / 255.0;
	float ub = 210.0 / 255.0;
	return (x - vec3(lb)) / (ub - lb);
}

void main() {
	vec2 texCoord2 = texCoord.xy;
#ifdef INVERT_FRAMEBUFFER_READ_Y
	texCoord2.y = 1 - texCoord2.y;
#endif
    vec3 col = texture(texFramebuf, texCoord2.xy).rgb;

	col *= u_blur.exposure;

	if (u_blur.applyBloom) {
		vec3 bloomCol = texture(texBlurred, texCoord2.xy).rgb;
		col += bloomCol;
	}

	if (u_blur.legacyToneMapping) {
		col = legacyToneMapAndGammaAndContrastBump(col);
	} else {
		if (u_blur.contrast > .0) {
			col = amdTonemapper(col, u_blur.hdrMax, u_blur.contrast, u_blur.shoulder, u_blur.midIn, u_blur.midOut);
		}
		col = gamma22(col);
	}

	// DEV square_shader_override_probe: strong magenta tint, so an override is obvious at a glance
	col = mix(col, vec3(1.0, 0.0, 1.0), 0.35);
	color.rgb = col;
}
