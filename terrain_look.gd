class_name TerrainLook
extends RefCounted

# The look of the ground. One shader gives every kind of earth its own surface detail, all drawn from
# two seamless noise textures projected onto the ground from three sides (so nothing stretches on
# slopes or cliffs):
#   grass and dry grass : fine blades with light-tipped highlights
#   stone               : cracked strata, dark in the cracks
#   dirt, clay, mounds  : pebbly, crumbly soil
#   gravel              : chunky stones
#   sand                : fine grains, with the odd glint
#   mud                 : dark and wet, so it shines
#   snow, chalk         : soft and smooth, snow glints
# The bumps catch the light because the shader tilts the surface normal where the detail rises and
# falls, so low sun rakes across every pebble. The surface mesher stores each vertex's material in the
# alpha channel of its colour (material number / 32), which is how the shader knows which earth it is on.
#
# To use real photographic textures later (from Poly Haven or ambientCG), add sampler uniforms for them
# here and mix them in where the noise samples are used.

const SHADER_CODE := """
shader_type spatial;

uniform sampler2D grain : repeat_enable, filter_linear_mipmap;   // soft fractal noise
uniform sampler2D cells : repeat_enable, filter_linear_mipmap;   // cell edges: cracks and pebbles
uniform float fade_start = 200.0;   // the detailed ground starts to thin out here...
uniform float fade_end = 262.0;     // ...and is gone here, where the distant land takes over
uniform float bump_height = 0.16;   // how tall the surface detail is, in world units

varying vec3 wpos;
varying vec3 wnrm;
varying flat float mat_id;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mat_id = floor(COLOR.a * 32.0 + 0.5);
}

vec3 blend_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z + 0.0001);
}

float tri_grain(vec3 p, vec3 w) {
	return texture(grain, p.zy).r * w.x + texture(grain, p.xz).r * w.y + texture(grain, p.xy).r * w.z;
}

float tri_cells(vec3 p, vec3 w) {
	return texture(cells, p.zy).r * w.x + texture(cells, p.xz).r * w.y + texture(cells, p.xy).r * w.z;
}

void fragment() {
	// Fade into the distant land with a fine dither, so the detailed ground never pops.
	float vis = 1.0 - smoothstep(fade_start, fade_end, length(VERTEX));
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (vis < dither) {
		discard;
	}

	vec3 w = blend_weights(wnrm);
	float g1 = tri_grain(wpos * 0.08, w);   // patches a few units wide
	float g2 = tri_grain(wpos * 0.5, w);    // grain about the size of a pebble
	float g3 = tri_grain(wpos * 2.5, w);    // very fine: blades and specks
	float c1 = tri_cells(wpos * 0.35, w);   // large cells
	float c2 = tri_cells(wpos * 1.2, w);    // small cells

	int id = int(mat_id + 0.5);
	vec3 base = COLOR.rgb;
	float k = 1.0;          // brightness variation
	float h = g2;           // the height of the detail, 0 to 1
	float rough = 0.9;
	float spec = 0.35;
	float ao = 1.0;
	float strength = 1.0;

	if (id == 3 || id == 10) {
		// Grass: fine blades, with brighter tips where the blade pattern peaks.
		k = 0.7 + 0.5 * g2 + 0.3 * (g3 - 0.5);
		h = g3 * 0.8 + g2 * 0.4;
		base = mix(base, base * 1.28 + vec3(0.03, 0.04, 0.0), smoothstep(0.55, 0.85, g3) * 0.5);
		ao = 0.75 + 0.25 * g3;
		rough = 0.92;
		strength = 1.2;
	} else if (id == 2) {
		// Stone: cracked strata, dark and recessed in the cracks.
		float crack = 1.0 - smoothstep(0.02, 0.16, c1);
		k = 0.8 + 0.4 * g2 - 0.5 * crack;
		h = g2 * 0.5 - crack * 1.4;
		ao = 1.0 - crack * 0.6;
		rough = 0.85;
		strength = 1.4;
	} else if (id == 7) {
		// Gravel: chunky stones separated by dark gaps.
		float stones = smoothstep(0.08, 0.45, c1);
		k = 0.6 + 0.5 * stones * (0.6 + 0.5 * g2);
		h = stones * 1.2 + g3 * 0.2;
		ao = 0.55 + 0.45 * stones;
		rough = 0.9;
		strength = 1.5;
	} else if (id == 5) {
		// Sand: fine grain and the odd glint.
		k = 0.88 + 0.22 * g3;
		h = g2 * 0.25 + g3 * 0.2;
		spec = 0.3 + 0.5 * step(0.9, g3);
		rough = 0.95;
		strength = 0.7;
	} else if (id == 6) {
		// Mud: dark, wet and shiny.
		k = 0.85 + 0.25 * g1;
		h = g1 * 0.3 + g3 * 0.1;
		rough = 0.22;
		spec = 0.7;
		strength = 0.6;
	} else if (id == 9) {
		// Snow: soft drifts, with a glint.
		k = 0.94 + 0.08 * g2;
		h = g1 * 0.4 + g2 * 0.15;
		spec = 0.4 + 0.5 * step(0.92, g3);
		rough = 0.5;
		strength = 0.6;
	} else if (id == 8) {
		// Chalk: pale and powdery.
		k = 0.9 + 0.12 * g2;
		h = g2 * 0.35;
		rough = 0.95;
		strength = 0.7;
	} else {
		// Dirt, clay, mound earth: crumbly, with pebbles.
		float pebble = smoothstep(0.35, 0.65, c2);
		k = 0.78 + 0.35 * g2 + 0.15 * pebble;
		h = pebble * 0.8 + g2 * 0.3;
		ao = 0.8 + 0.2 * pebble;
		rough = 0.95;
		strength = 1.1;
	}

	ALBEDO = base * k;
	ROUGHNESS = rough;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;

	// Bump mapping from the height: tilt the surface normal where the detail rises and falls.
	vec3 n = normalize(NORMAL);
	vec3 sx = dFdx(VERTEX);
	vec3 sy = dFdy(VERTEX);
	vec3 r1 = cross(sy, n);
	vec3 r2 = cross(n, sx);
	float det = dot(sx, r1);
	float hs = h * bump_height * strength;
	vec3 grad = sign(det) * (dFdx(hs) * r1 + dFdy(hs) * r2);
	NORMAL = normalize(abs(det) * n - grad);
}
"""

# Fills the shared ground material. main.gd owns the material; streaming.gd calls this once.
static func setup(mat: ShaderMaterial) -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	mat.shader = shader

	# Soft fractal noise, about four swells per tile.
	var grain_noise := FastNoiseLite.new()
	grain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain_noise.frequency = 0.016
	grain_noise.fractal_octaves = 4
	grain_noise.seed = 11
	var grain := NoiseTexture2D.new()
	grain.noise = grain_noise
	grain.seamless = true
	grain.width = 256
	grain.height = 256

	# Cell edges: near zero along the borders between cells.
	var cell_noise := FastNoiseLite.new()
	cell_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cell_noise.frequency = 0.023
	cell_noise.seed = 29
	var cells := NoiseTexture2D.new()
	cells.noise = cell_noise
	cells.seamless = true
	cells.width = 256
	cells.height = 256

	mat.set_shader_parameter("grain", grain)
	mat.set_shader_parameter("cells", cells)
	mat.set_shader_parameter("fade_start", Main.TERRAIN_FADE_START)
	mat.set_shader_parameter("fade_end", Main.TERRAIN_FADE_END)
