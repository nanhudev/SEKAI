shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
//
// THE LINE THAT IS NOT A SURFACE.
//
// Everything in this lab that is a line rather than a body uses this: the crack
// of 地脉拔刀, the blades pulled out of the world in 世界剑鞘, the hinge of 天地合页,
// the lightning of 神罚雷, the rim of the corridor, the hairline of 黑日.
//
// -----------------------------------------------------------------------------
// WHY ADDITIVE AND WHY UNLIT
// -----------------------------------------------------------------------------
//
// A glowing line has no shading. It is not a surface catching light, it is light.
// `unshaded` + `blend_add` means the line adds its own colour to whatever is
// behind it, which is the only way a hairline stays visible against both a lit
// wall and the sky, and the only way two crossing lines read as brighter where
// they cross rather than as two opaque ribbons fighting over a pixel.
//
// `depth_draw_never` because a line must not occlude what it is drawn over —
// otherwise a glowing rail on a building punches a hole in the building.
//
// -----------------------------------------------------------------------------
// THE FRESNEL IS THE EDGE
// -----------------------------------------------------------------------------
//
// A thin quad seen edge-on disappears. So the intensity is driven partly by the
// view angle: `fresnel_power` keeps a hairline from vanishing when the camera
// happens to be level with it. Set `fresnel_power = 0` for a line that should
// just be a flat additive ribbon, which is what the lightning wants.

uniform vec3 line_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float intensity : hint_range(0.0, 12.0) = 2.0;
// How much of the brightness turns on with the view angle. 0 = never, 1 = mostly.
uniform float fresnel_power : hint_range(0.0, 4.0) = 0.0;
// A travelling highlight along the line's own U, for a line that is energised.
uniform float travel : hint_range(-8.0, 8.0) = 0.0;
uniform float travel_width : hint_range(0.01, 1.0) = 0.25;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;
varying vec2 line_uv;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	line_uv = UV;
}


void fragment() {
	float a = alpha;
	if (fresnel_power > 0.0) {
		float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
		a *= mix(1.0, clamp(f * 2.0, 0.0, 1.0), clamp(fresnel_power, 0.0, 1.0));
	}
	if (travel != 0.0) {
		float band = 1.0 - smoothstep(0.0, max(travel_width, 0.001),
			abs(line_uv.x - fract(travel)));
		a *= 0.35 + band * 1.4;
	}
	ALBEDO = line_color;
	EMISSION = line_color * intensity;
	ALPHA = a;
}
