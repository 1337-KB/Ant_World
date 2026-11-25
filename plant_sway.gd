class_name PlantSway
extends RefCounted

# Wind for everything that grows that is not grass: wildflowers, bushes, ferns, tree canopies and
# the layered needles of pines and spruces. One shared shader bends each plant more the higher up a
# vertex is, so the base stays planted and the tip or the leaf mass moves. The same rolling gusts
# that ripple the grass (see GRASS_SHADER in main.gd) pass through, so a whole meadow, bush and
# canopy move together. Flowers and bushes also lean away from you as you walk past.
# Mushrooms, cacti, logs and trunks are rigid and keep plain materials.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled;

global uniform vec3 ant_pos;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float base_y = 0.0;        // the lowest point of the mesh, which never moves
uniform float mesh_height = 2.0;   // how tall the mesh is, in its own units
uniform float amp = 0.3;           // how far the top moves in a strong gust, in world units
uniform float push_amt = 0.0;      // how far it leans away from you
uniform float fade_near = 0.0;     // distance fade by dither (0 = off; trees use visibility range instead)
uniform float fade_far = 0.0;
uniform float roughness_v = 0.85;
uniform vec2 wind_dir = vec2(0.8, 0.6);

varying vec3 vcol;
varying float dist;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vcol = COLOR.rgb;
	vec3 origin = MODEL_MATRIX[3].xyz;
	dist = length(origin - INV_VIEW_MATRIX[3].xyz);

	// The higher on the plant, the more it moves.
	float f = clamp((VERTEX.y - base_y) / mesh_height, 0.0, 1.0);
	f = f * f;

	// The same gust wave as the grass, plus each plant's own beat and flutter.
	float gust = sin(dot(origin.xz, wind_dir) * 0.09 - TIME * 0.9) * 0.5 + 0.5;
	gust = gust * gust;
	float wind = amp * (0.4 + 0.9 * gust);
	float rnd = hash21(origin.xz * 0.7);
	float phase = TIME * 1.3 + origin.x * 0.6 + origin.z * 0.45;
	float flutter = sin(TIME * 2.7 + rnd * 6.2832) * 0.25;
	float bend = (sin(phase) * 0.6 + 0.5 + flutter) * wind * f;
	vec3 push_world = vec3(wind_dir.x, 0.0, wind_dir.y) * bend;

	// Leaning away from you as you pass (not when you are well above, up a tree).
	if (push_amt > 0.0) {
		vec2 away = origin.xz - ant_pos.xz;
		float d = length(away);
		float touch = (1.0 - smoothstep(0.8, 3.6, d)) * (1.0 - smoothstep(1.5, 4.0, ant_pos.y - origin.y));
		if (d > 0.01) {
			push_world += vec3(away.x, 0.0, away.y) / d * touch * push_amt * f;
		}
	}

	// Turn the world-space push into the plant's own space, because each is rotated and scaled.
	mat3 M = mat3(MODEL_MATRIX);
	vec3 s2 = vec3(dot(M[0], M[0]), dot(M[1], M[1]), dot(M[2], M[2]));
	VERTEX += (transpose(M) * push_world) / s2;
}

void fragment() {
	if (fade_far > 0.0 && hash21(FRAGCOORD.xy) > 1.0 - smoothstep(fade_near, fade_far, dist)) {
		discard;
	}
	ALBEDO = use_vertex_color ? vcol : albedo_color.rgb;
	ROUGHNESS = roughness_v;
	BACKLIGHT = ALBEDO * 0.3;   // light shines through leaves and petals from behind
}
"""

static var shader: Shader

static func get_shader() -> Shader:
	if shader == null:
		shader = Shader.new()
		shader.code = SHADER_CODE
	return shader

# How tall each swaying wildflower kind is, so the bend can be spread over its height.
# Kinds not listed here use 1.6.
const FLORA_HEIGHT := {2: 2.4, 5: 2.6, 6: 3.0, 9: 1.8, 18: 1.3, 19: 0.7, 20: 2.0, 21: 2.0, 22: 1.5, 26: 1.7, 27: 2.6}
# Flora kinds that move. The rest (cacti, mushrooms, moss, litter, twigs, acorns) are rigid.
const FLORA_SWAYS := [0, 1, 2, 3, 4, 5, 6, 9, 11, 18, 19, 20, 21, 22, 26, 27]
# Bushes and shrubs rustle gently; flowers and reeds bend further.
const BUSHES := [20, 21, 27]

static func flora_sways(id: int) -> bool:
	return FLORA_SWAYS.has(id)

# The material for a swaying wildflower, bush or fern kind. Colours come from the mesh's vertices.
static func flora_material(id: int, fade_near: float, fade_far: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = get_shader()
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("base_y", 0.0)
	mat.set_shader_parameter("mesh_height", float(FLORA_HEIGHT.get(id, 1.6)))
	var bush := BUSHES.has(id)
	mat.set_shader_parameter("amp", 0.14 if bush else 0.34)
	mat.set_shader_parameter("push_amt", 0.3 if bush else 0.7)
	mat.set_shader_parameter("fade_near", fade_near)
	mat.set_shader_parameter("fade_far", fade_far)
	return mat

# The material for a canopy, bush lump or needle layer made from a sphere or cone mesh, whose middle
# is at its own origin. `amp` is how far the top moves in a strong gust, in world units.
static func leaf_material(color: Color, mesh: Mesh, amp: float, push: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = get_shader()
	var h := 2.0
	if mesh is SphereMesh:
		h = (mesh as SphereMesh).height
	elif mesh is CylinderMesh:
		h = (mesh as CylinderMesh).height
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("use_vertex_color", false)
	mat.set_shader_parameter("base_y", -h * 0.5)
	mat.set_shader_parameter("mesh_height", h)
	mat.set_shader_parameter("amp", amp)
	mat.set_shader_parameter("push_amt", push)
	mat.set_shader_parameter("roughness_v", 0.9)
	return mat
