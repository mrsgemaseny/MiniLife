shader_type canvas_item;

uniform float vision_radius_px = 864.0;
uniform float mask_size_px = 4096.0;
uniform float feather_px = 16.0;

void fragment() {
	float distance_to_player = distance(UV * mask_size_px, vec2(mask_size_px * 0.5));
	COLOR = vec4(0.05, 0.06, 0.08,
		smoothstep(vision_radius_px - feather_px, vision_radius_px + feather_px, distance_to_player));
}
