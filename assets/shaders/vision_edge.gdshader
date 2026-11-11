shader_type canvas_item;

uniform vec2 vision_center;
uniform float vision_radius_px = 864.0;
// Keep the explored area fully lit; blend only the outer half-tile.
uniform float feather_px = 18.0;

varying vec2 map_position;
varying float fade_edge;

void vertex() {
	map_position = VERTEX;
	fade_edge = COLOR.a < 0.975 ? 1.0 : 0.0;
	COLOR.a = 1.0;
}

void fragment() {
	if (fade_edge > 0.5) {
		float distance_to_player = distance(map_position, vision_center);
		COLOR.a *= 1.0 - smoothstep(vision_radius_px - feather_px, vision_radius_px + feather_px, distance_to_player);
	}
}
