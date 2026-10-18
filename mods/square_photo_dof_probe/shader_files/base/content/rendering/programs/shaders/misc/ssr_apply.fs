#version 150
// sqdof: DEV square_photo_dof_probe copy of base rendering/programs/shaders/misc/ssr_apply.fs
// sqdof: base build 40420, base sha256 3d5a2ed8cff5a3d338c8b1457ac9b36a3b81526997bf8a48985af5bc5a196a5b
// sqdof: every change is marked "sqdof:"; manual install only (plans/square_photo_dof_probe/TESTING.md)
#extension GL_GOOGLE_include_directive : require
#include "/rendering/programs/shaders/util/preamble.h.glsl"

#include "/rendering/programs/shaders/util/util.h.glsl"

#include "/rendering/programs/shaders/pbr/view.h.glsl"
#include "/rendering/programs/shaders/pbr/light.h.glsl"

LAYOUT_SAMPLER(0, 0) uniform sampler2D colorTex;
LAYOUT_SAMPLER(0, 1) uniform sampler2D normalTex;
LAYOUT_SAMPLER(0, 11) uniform sampler2D specTex;
LAYOUT_SAMPLER(0, 9) uniform sampler2D depthBufTex;
LAYOUT_SAMPLER(0, 7) uniform sampler2D blurredTex;

LAYOUT_SAMPLER2(0, 20) uniform samplerCube lightTex0;
LAYOUT_SAMPLER2(0, 21) uniform samplerCube lightTex1;

LAYOUT_SAMPLER2(0, 23) uniform sampler2D waterDropsNormal;
LAYOUT_SAMPLER2(0, 24) uniform sampler2D waterDropsMask;

LAYOUT_UBO(0, 4) uniform Ssao {
	mat4 projMat;
	mat4 invProjMat;
	mat4 invViewMat;
	mat4 invProjViewMat;
	vec2 normalMapRes1;
	vec2 nearPlaneHalfSize;
	vec2 nearFar;
	bool ssrOn;
	int maxNumMips;
	int maxSteps;
	float stride;
	bool enablePostProcessing;
	float effectAlpha;
	float maxDistance;
} u_ssao;

INPUT(TC_LOC, vec2, texCoord, vec2(1.0));

OUTPUT(OUT_0, vec4, color);

float compShadow(vec3 vpos);

vec3 rgbToNormal(vec3 rgb) {
	return normalize(2 * (rgb - 0.5));
}

float calcEyeZ(float depth) {
	float near = u_ssao.nearFar.x;
	float far = u_ssao.nearFar.y;
	float d = 2.0 * depth - 1.0;
	return -2.0 * near * far / (far + near - d * (far - near));
}

float getDepth(vec2 uv) {
#ifdef INVERT_FRAMEBUFFER_READ_Y
	uv.y = 1 - uv.y;
#endif
	float z = calcEyeZ(texture(depthBufTex, uv).r);
	return (-z - u_ssao.nearFar.x) / (u_ssao.nearFar.y - u_ssao.nearFar.x);
}

vec3 getNormal(vec2 uv) {
	return rgbToNormal(texture(normalTex, uv).rgb);
}

vec3 lightSpec(vec3 pos, vec3 reflDir, vec3 specColor, float glossiness) {
	float maxLod = 6.0;
	float specLod = maxLod * (1.0 - glossiness);

	vec3 specLight0 = textureLod(lightTex0, reflDir, specLod).rgb;
	vec3 specLight1 = textureLod(lightTex1, reflDir, specLod).rgb;

	float shadow = compShadow(pos);		// 1 = no shadow!
	float ambientScale = u_light.ambientScale;
	float lightScale = u_light.lightScale;
	
	vec3 specLight = mix(ambientScale * specLight0, 1.0 / ambientScale * specLight1, shadow);

	return lightScale * specColor * specLight;
}

vec3 depth2Position(vec2 uv, float depth) {
	vec2 xyOnNearPlane = (uv - .5) * 2.0 * u_ssao.nearPlaneHalfSize;
	vec3 xyzOnNearPlane = vec3(xyOnNearPlane.x, xyOnNearPlane.y, -u_ssao.nearFar.x);
	float scale = mix(u_ssao.nearFar.x, u_ssao.nearFar.y, depth) / u_ssao.nearFar.x;
	return xyzOnNearPlane * scale;
}

bool traceScreenSpaceRay1a(
	vec3            csOrigin, 
	vec3            csDirection,
	mat4            projectToPixelMatrix,
	sampler2D       csZBuffer,
	vec2            csZBufferSize,
	float           csZThickness,
	const bool      csZBufferIsHyperbolic,
	vec3            clipInfo,
	float           nearPlaneZ,
	float			stride,
	float           jitterFraction,
	float           maxSteps,
	float           maxRayTraceDistance,
	out vec2        hitPixel,
	out vec3		csHitPoint, out vec3 debugColor);

vec2 matchPixelCenter(vec2 uv) {
	return uv;
}

vec3 project(vec3 p) {
	vec4 pp = u_ssao.projMat * vec4(p, 1.0);
	return .5 * (pp.xyz / pp.w + vec3(1.0));
}

vec3 unproject(vec3 p) {
	vec4 pp = u_ssao.invProjMat * vec4(2.0 * p - vec3(1.0), 1.0);
	return pp.xyz / pp.w;
}

// sqdof: the base main, renamed; the new main() at the end of the file runs it, then the depth of field
void sqdofBaseMain() {
	vec2 texCoord2 = texCoord;
#ifdef INVERT_FRAMEBUFFER_READ_Y
	texCoord2.y = 1 - texCoord.y;
#endif
	vec4 s = texture(specTex, texCoord2);
	vec3 specCol = s.rgb;
	float gloss = s.a;

	vec3 normal = getNormal(texCoord2);

	float depth = getDepth(texCoord);
	depth -= mix(0, 0.01, depth*depth);
	vec3 screenSpacePos = depth2Position(texCoord, depth);

	vec3 reflDir = normalize(reflect(screenSpacePos, normal)); // screen space
	
	vec3 worldPos = vec3(u_ssao.invViewMat * vec4(screenSpacePos, 1.0));
	vec3 worldReflDir = vec3(u_ssao.invViewMat * vec4(reflDir, .0));

	if (u_ssao.enablePostProcessing && u_ssao.effectAlpha > 0.4) {
		vec2 tx = texCoord2 + u_view.time * vec2(0.0, -0.2);

		float mask = textureLod(waterDropsMask, tx, 0).r;
		vec3 n = textureLod(waterDropsNormal, tx, 0).rgb;
		n = normalize(mix(vec3(0.0, 0.0, 1.0), (n * 2.0 - 1.0), smoothstep(0.4, 0.5, u_ssao.effectAlpha)));

		float strength = 0.7;
		// float g = smoothstep(0.4, 0.6, distance(texCoord2, vec2(0.5, 0.5)));
		float g = 1.0;
		texCoord2 += mask * (n.xy * strength * g);
	}
	
	color = textureLod(colorTex, texCoord2, .0);

	float glossThreshold = 0.3;
	if (!u_ssao.ssrOn || gloss < glossThreshold) {
		return;
	}

	float csZThickness = 2.0;
	const bool csZBufferIsHyperbolic = true;
	vec3 clipInfo = vec3(-u_ssao.nearFar.x * u_ssao.nearFar.y, u_ssao.nearFar.x - u_ssao.nearFar.y, u_ssao.nearFar.y);
	float nearPlaneZ = -u_ssao.nearFar.x;
	float stride = u_ssao.stride;
	float jitterFraction = 1.0 + float((int(gl_FragCoord.x) + int(gl_FragCoord.y)) & 1) * 0.5;
	float maxSteps = u_ssao.maxSteps;
	float maxRayTraceDistance = u_ssao.maxDistance;
	vec2 hitPixel;
	vec3 csHitPoint;
	vec3 debugColor;
	bool hit = traceScreenSpaceRay1a(screenSpacePos, reflDir, u_ssao.projMat,
			depthBufTex, u_ssao.normalMapRes1, csZThickness, csZBufferIsHyperbolic, clipInfo,
			nearPlaneZ, stride, jitterFraction, maxSteps, maxRayTraceDistance, hitPixel, csHitPoint, debugColor);
	// color.xyz = debugColor;
	// return;

	//vec3 envSpecLight = lightSpec(worldPos, worldReflDir, specCol, gloss);
	if (hit) {
		vec2 uv = hitPixel / u_ssao.normalMapRes1;

		vec3 reflCol = gloss > 0.9 ? textureLod(colorTex, uv, .0).xyz : textureLod(blurredTex, uv, invLerp(clamp(gloss, 0.5, 0.9), 0.9, 0.0) * u_ssao.maxNumMips).xyz;

		vec3 hitNormal = getNormal(uv);
		vec3 worldHitNormal = vec3(u_ssao.invViewMat * vec4(hitNormal, .0));
		if (dot(reflDir, hitNormal) > 0.0 && worldHitNormal.z > 0.0) {
			reflCol *= mix(1.0, 0.2, worldHitNormal.z);
		}		

		//vec3 diff = clamp(specCol * reflCol, 0.0 , 1.0);
		//color.xyz += diff;

		float f = smoothstep(glossThreshold, 0.5, gloss);
		color.xyz = color.xyz * max(vec3(1.0) - 3.0 * f * specCol, vec3(.25)) + f * specCol * reflCol;
	} else { 
		// color.xyz += envSpecLight;
	}
	
	
}

// sqdof: ---------------------------------------------------------------------------------------------------------
// sqdof: Depth of field / tilt-shift probe. Off unless the environment's light.latitude carries a mode:
// sqdof: latitude = real latitude + 2 pi * mode (sun and stars use it through sin / cos / rotations, so the sky is
// sqdof: unchanged; a real latitude is always within +-pi/2, so mode 0 = every base climate = untouched picture).
// sqdof: mode 1 tilt-shift (sharp horizontal band in the screen middle), 2 depth of field focused on the screen
// sqdof: centre, 3 the same with a shallow focus, 4 debug (left: blur source, right: depth, centre: focus probe).
// sqdof: A 6 px magenta square in a screen corner is always drawn: it shows this file is the one running.
// sqdof: SQDOF_FORCE_MODE >= 0 ignores the latitude channel (fallback if the channel shows nothing: set 2, re-copy,
// sqdof: AltGr+R or restart; then the effect is always on, so restore the base file afterwards)
#define SQDOF_FORCE_MODE -1
const float SQDOF_TWO_PI = 6.2831853;
const float SQDOF_HALF_PI = 1.5707963;

int sqdofMode() {
	if (SQDOF_FORCE_MODE >= 0) {
		return SQDOF_FORCE_MODE;
	}
	float m = floor((u_light.latitude + SQDOF_HALF_PI) / SQDOF_TWO_PI);
	return int(clamp(m, 0.0, 15.0));
}

// sqdof: linear distance from the camera in metres (getDepth: 0 = near plane, 1 = far plane)
float sqdofMetres(vec2 uvUnflipped) {
	return mix(u_ssao.nearFar.x, u_ssao.nearFar.y, clamp(getDepth(uvUnflipped), 0.0, 1.0));
}

// sqdof: blurred colour at strength c (0..1). Prefers the SSR blur mip chain; without it (maxNumMips < 1) a
// sqdof: 12-tap disc on the sharp frame.
vec3 sqdofBlur(vec2 uv, float c) {
	if (u_ssao.maxNumMips >= 1) {
		float lod = c * min(float(u_ssao.maxNumMips), 5.0);
		return textureLod(blurredTex, uv, lod).rgb;
	}
	vec2 px = 1.0 / max(u_ssao.normalMapRes1, vec2(1.0));
	float r = 12.0 * c;
	vec3 sum = textureLod(colorTex, uv, 0.0).rgb;
	for (int i = 0; i < 12; ++i) {
		float a = float(i) * (SQDOF_TWO_PI / 12.0);
		float rr = (i % 2 == 0) ? r : 0.5 * r;
		sum += textureLod(colorTex, uv + vec2(cos(a), sin(a)) * rr * px, 0.0).rgb;
	}
	return sum / 13.0;
}

void main() {
	sqdofBaseMain();

	int mode = sqdofMode();

	// sqdof: install marker, in every mode
	if (gl_FragCoord.x < 6.0 && gl_FragCoord.y < 6.0) {
		color = vec4(1.0, 0.0, 1.0, 1.0);
		return;
	}
	if (mode == 0) {
		return;
	}

	vec2 uv = texCoord;			// unflipped, as getDepth() expects
	vec2 uv2 = texCoord;		// flipped like the base main's colour reads
#ifdef INVERT_FRAMEBUFFER_READ_Y
	uv2.y = 1 - uv2.y;
#endif

	float c = 0.0;
	if (mode == 1) {
		// sqdof: tilt-shift: sharp within +-0.10 of the screen height around the middle, full blur from +-0.38
		float dy = abs(uv.y - 0.5);
		c = smoothstep(0.10, 0.38, dy);
	} else if (mode == 2 || mode == 3) {
		// sqdof: focus = nearest of five depth samples around the screen centre (a small autofocus spot)
		float f = sqdofMetres(vec2(0.5, 0.5));
		f = min(f, sqdofMetres(vec2(0.48, 0.5)));
		f = min(f, sqdofMetres(vec2(0.52, 0.5)));
		f = min(f, sqdofMetres(vec2(0.5, 0.47)));
		f = min(f, sqdofMetres(vec2(0.5, 0.53)));
		float d = sqdofMetres(uv);
		// sqdof: in focus within +-range of the focus distance (relative), full blur at 4x that
		float range = (mode == 2 ? 0.25 : 0.08) * f;
		float off = abs(d - f);
		c = smoothstep(range, 4.0 * range, off);
		// sqdof: the near side blurs faster than the far side, like a real lens
		if (d < f) {
			c = smoothstep(0.5 * range, 2.0 * range, off);
		}
	} else {
		// sqdof: debug: left half the blur source at strength 0.6, right half the depth (white = near)
		if (uv.x < 0.5) {
			color.rgb = u_ssao.maxNumMips >= 1 ? sqdofBlur(uv2, 0.6) : vec3(0.6, 0.0, 0.0);
		} else {
			float dd = clamp(getDepth(uv), 0.0, 1.0);
			color.rgb = vec3(1.0 - sqrt(dd));
		}
		if (abs(uv.x - 0.5) < 0.002 || (abs(uv.x - 0.5) < 0.02 && abs(uv.y - 0.5) < 0.002)) {
			color.rgb = vec3(0.0, 1.0, 0.0);
		}
		return;
	}

	if (c > 0.001) {
		vec3 b = sqdofBlur(uv2, c);
		color.rgb = mix(color.rgb, b, smoothstep(0.0, 0.3, c));
	}
}
