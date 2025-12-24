// res://shaders/erosion_height_gpu.gdshader
shader_type canvas_item;

uniform sampler2D height_tex;
uniform vec2 map_size = vec2(256.0, 256.0);

uniform int erosion_iterations = 8;
uniform float erosion_strength = 0.12;

uniform int enable_thermal = 1;
uniform float talus_angle = 2.0;
uniform float thermal_strength = 0.5;

uniform int enable_hydraulic = 1;
uniform float rain_amount = 0.5;
uniform float hydraulic_strength = 0.7;
uniform float evaporation = 0.5;
uniform float sediment_capacity = 1.0;

uniform int enable_wind = 1;
uniform vec2 wind_direction = vec2(1.0, 0.3);
uniform float wind_strength = 0.4;


vec4 sample_height(vec2 uv) {
	return texture(height_tex, uv);
}


void fragment() {
	vec2 texel = 1.0 / map_size;
	vec2 uv = UV;

	float h = sample_height(uv).r;
	float water = 0.0;
	float sediment = 0.0;

	vec2 wdir = normalize(wind_direction);

	for (int it = 0; it < erosion_iterations; it++) {
		if (enable_thermal == 1) {
			float max_diff = 0.0;
			vec2 best_offset = vec2(0.0);

			for (int j = -1; j <= 1; j++) {
				for (int i = -1; i <= 1; i++) {
					if (i == 0 && j == 0) {
						continue;
					}
					vec2 off = vec2(float(i), float(j)) * texel;
					float nh = sample_height(uv + off).r;
					float diff = h - nh;
					if (diff > max_diff) {
						max_diff = diff;
						best_offset = off;
					}
				}
			}

			if (max_diff > talus_angle) {
				float move = max_diff * thermal_strength * erosion_strength;
				h -= move;
			}
		}

		if (enable_hydraulic == 1) {
			water += rain_amount;
			float h_total = h + water;

			float lowest_h = h_total;
			vec2 best_offset = vec2(0.0);

			for (int j = -1; j <= 1; j++) {
				for (int i = -1; i <= 1; i++) {
					if (i == 0 && j == 0) {
						continue;
					}
					vec2 off = vec2(float(i), float(j)) * texel;
					float nh = sample_height(uv + off).r;
					float n_total = nh + water;
					if (n_total < lowest_h) {
						lowest_h = n_total;
						best_offset = off;
					}
				}
			}

			float delta = h_total - lowest_h;
			if (delta > 0.0) {
				float flow = delta * hydraulic_strength * erosion_strength;
				flow = min(flow, water);

				float capacity = flow * sediment_capacity;

				if (sediment < capacity) {
					float amount = min(capacity - sediment, h * erosion_strength);
					sediment += amount;
					h -= amount;
				} else {
					float deposit = (sediment - capacity) * erosion_strength;
					sediment -= deposit;
					h += deposit;
				}

				water -= flow;
			}

			water *= (1.0 - evaporation);
		}

		if (enable_wind == 1) {
			vec2 up_uv = uv - wdir * texel;
			float up_h = sample_height(up_uv).r;
			float slope = up_h - h;
			if (slope > 0.0) {
				float move = slope * wind_strength * erosion_strength;
				h += move * 0.5;
			}
		}
	}

	COLOR = vec4(h, 0.0, 0.0, 1.0);
}
