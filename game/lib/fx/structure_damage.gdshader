// Runtime damage overlay for the drone-city structure skins.
//
// The skin (the original imported mesh) keeps its own materials. This shader
// runs on a slightly-inflated twin of the same mesh, and only draws where the
// per-building damage mask says the surface is damaged: charred, cracked
// scorch that deepens toward a hole past the hole cutoff. The mask is a
// 512x512 ImageTexture the structure controller paints into wherever a piece
// takes damage or breaks. Where nothing is damaged the fragment stays fully
// transparent, so the skin shows through untouched.
//
// Coordinate space: the mask spans the building's LOCAL AABB (mask_origin =
// local min corner, mask_scale = 1 / local max dimension), sampled triplanar
// so damage lands on exactly the wall that was hit.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D damage_mask : filter_linear, repeat_disable;
uniform vec3 mask_origin = vec3(-1.0, -1.0, -1.0);
uniform float mask_scale = 0.1;
uniform float damage_cutoff : hint_range(0.0, 1.0) = 0.35;   // char starts
uniform float hole_cutoff : hint_range(0.0, 1.0) = 0.8;      // alpha hole

varying vec3 v_mask;
varying vec3 v_nrm;

void vertex() {
	v_mask = (VERTEX - mask_origin) * mask_scale;
	v_nrm = NORMAL;
}

void fragment() {
	vec3 w = pow(abs(normalize(v_nrm)), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float dmg = texture(damage_mask, v_mask.zy).r * w.x
			+ texture(damage_mask, v_mask.xz).r * w.y
			+ texture(damage_mask, v_mask.xy).r * w.z;

	// Nothing damaged -> fully transparent. Charred scorch rises with the
	// mask, opening a hole past hole_cutoff so the inside shows through.
	float a = smoothstep(damage_cutoff, 1.0, dmg);
	ALPHA = a * (1.0 - smoothstep(hole_cutoff, 1.0, dmg));
	ALBEDO = vec3(0.06, 0.055, 0.05);
	ROUGHNESS = 1.0;
}