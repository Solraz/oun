shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_tex : source_color;
uniform sampler2D rock_tex  : source_color;
uniform sampler2D dirt_tex  : source_color;

uniform float grass_tiling : hint_range(0.1, 64.0, 0.1) = 8.0;
uniform float rock_tiling  : hint_range(0.1, 64.0, 0.1) = 8.0;
uniform float dirt_tiling  : hint_range(0.1, 64.0, 0.1) = 8.0;

uniform float grass_min_height = 0.0;
uniform float grass_max_height = 20.0;

uniform float rock_min_height  = 10.0;
uniform float rock_max_height  = 80.0;

uniform float dirt_min_height  = -20.0;
uniform float dirt_max_height  = 30.0;

uniform float slope_rock_start : hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float slope_rock_full  : hint_range(0.0, 1.0, 0.01) = 0.8;

uniform float rock_slope_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float rock_slope_smooth : hint_range(0.0, 1.0) = 0.15;

uniform float slope_dirt_start : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float slope_dirt_full  : hint_range(0.0, 1.0, 0.01) = 0.6;

uniform vec3 grass_tint = vec3(0.85, 1.0, 0.85);
uniform vec3 rock_tint  = vec3(1.0, 1.0, 1.0);
uniform vec3 dirt_tint  = vec3(1.0, 0.95, 0.9);
uniform float height_blend_range : hint_range(0.0, 50.0) = 4.0;

uniform float global_brightness : hint_range(0.0, 2.0, 0.01) = 1.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float remap(float v, float in_min, float in_max) {
	return clamp((v - in_min) / max(in_max - in_min, 0.0001), 0.0, 1.0);
}

float linearstep(float edge0, float edge1, float x) {
	return clamp((x - edge0) / max(edge1 - edge0, 0.0001), 0.0, 1.0);
}

varying vec3 world_position;

void vertex()
{
		v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 world_pos = v_world_pos;
	float height = world_pos.y;

	float slope = 1.0 - abs(normalize(v_world_normal).y);
	slope = clamp(slope, 0.0, 1.0);

	// Height-based masks
	float dirt_mask = 1.0 - linearstep(dirt_max_height - height_blend_range, dirt_max_height + height_blend_range, height);
	float grass_mask = linearstep(dirt_max_height - height_blend_range, dirt_max_height + height_blend_range, height)
	                 * (1.0 - linearstep(grass_max_height - height_blend_range, grass_max_height + height_blend_range, height));
	float rock_height_mask = linearstep(grass_max_height - height_blend_range, grass_max_height + height_blend_range * 2.0, height);

	// Slope-based rock mask (steep = more rock)
	float rock_slope_mask = linearstep(rock_slope_threshold - rock_slope_smooth, rock_slope_threshold + rock_slope_smooth, slope);

	float rock_mask = clamp(max(rock_height_mask, rock_slope_mask), 0.0, 1.0);


	// float grass_height_w = remap(h, grass_min_height, grass_max_height);
	// float rock_height_w  = remap(h, rock_min_height, rock_max_height);
	// float dirt_height_w  = remap(h, dirt_min_height, dirt_max_height);

	// float rock_slope_w = remap(slope, slope_rock_start, slope_rock_full);
	// float dirt_slope_w = remap(slope, slope_dirt_start, slope_dirt_full);

	// float grass_w = grass_height_w * (1.0 - rock_slope_w) * (1.0 - dirt_slope_w);
	// float rock_w  = rock_height_w  * rock_slope_w;
	// float dirt_w  = dirt_height_w  * dirt_slope_w * (1.0 - rock_slope_w * 0.5);

	// float w_sum = grass_w + rock_w + dirt_w + 0.0001;
	// grass_w /= w_sum;
	// rock_w  /= w_sum;
	// dirt_w  /= w_sum;

	float sum = dirt_mask + grass_mask + rock_mask + 0.0001;
	dirt_mask /= sum;
	grass_mask /= sum;
	rock_mask /= sum;

	vec2 uv = UV;

	vec3 grass_col = texture(grass_tex, uv * grass_tiling).rgb * grass_tint;
	vec3 rock_col  = texture(rock_tex,  uv * rock_tiling).rgb  * rock_tint;
	vec3 dirt_col  = texture(dirt_tex,  uv * dirt_tiling).rgb  * dirt_tint;

	vec3 albedo = dirt_col.rgb * dirt_mask
	            + grass_col.rgb * grass_mask
	            + rock_col.rgb * rock_mask;

	// vec3 albedo = grass_col * grass_w + rock_col * rock_w + dirt_col * dirt_w;
	albedo *= global_brightness;

	ALBEDO = albedo;
}