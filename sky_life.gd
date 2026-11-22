class_name SkyLife
extends Node3D

# Everything in the distance and overhead: two rings of hazy mountains on the horizon, and
# flocks of big birds that cross the sky by day. The mountains move with the camera, so like
# a real horizon you never get closer to them. Both fade into the haze color of the sky.

const RING_SEGMENTS := 384
const FLOCK_BASE_COUNT := [4, 1, 3, 1, 3, 6]   # flocks by biome: forest, desert, highlands, tundra, swamp, savanna
const NORTH := 4.712389       # angle of the -Z direction on the ring (3 pi / 2)
const RANGE_HALF_WIDTH := 1.15   # the range spans about 130 degrees; the rest of the horizon is flat
const WORLD_HALF := 7200.0
const MAX_BIRDS := 200
const FLOCK_RADIUS := 520.0       # flocks farther than this from you are moved to the other side
const BIRD_SPEED := 13.0

const MOUNTAIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 haze_color : source_color = vec3(0.65, 0.78, 0.92);
uniform vec3 rock_color : source_color = vec3(0.34, 0.42, 0.55);
uniform float strength = 0.8;
uniform float snow_amount = 0.5;
uniform float height_scale = 1.0;
void vertex() {
	if (VERTEX.y > 0.0) {
		VERTEX.y *= height_scale;
	}
}
void fragment() {
	float h = COLOR.r;
	float v = COLOR.g;
	vec3 rock = rock_color * (0.85 + 0.3 * v);
	vec3 c = mix(haze_color, rock, smoothstep(0.05, 0.85, h) * strength);
	// Pale peaks near the tops.
	float cap = smoothstep(0.82, 0.97, h) * snow_amount;
	c = mix(c, mix(haze_color, vec3(1.0), 0.6), cap);
	ALBEDO = c;
}
"""

const STAR_RADIUS := 3000.0
const CLOUD_HEIGHT := 300.0       # clouds float at this height above sea level
const CLOUD_SIZE := 6400.0
const CLOUD_COVER := [0.5, 0.3, 0.55, 0.65, 0.7, 0.45]   # by biome: forest, desert, highlands, tundra, swamp, savanna
const CLOUD_DRIFT := Vector2(6.0, 2.5)                    # how fast the wind pushes them, in units per second

# Stars and the moon: painted on a huge ball around the camera. Only visible at night.
const STAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never, fog_disabled;
uniform float night = 0.0;
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
varying vec3 dir;
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
void vertex() {
	dir = normalize(VERTEX);
}
void fragment() {
	vec3 d = normalize(dir);
	vec3 q = d * 95.0;
	vec3 id = floor(q);
	vec3 f = fract(q) - 0.5;
	float h = hash(id);
	float star = 0.0;
	if (h > 0.94) {
		vec3 off = (vec3(hash(id + 1.3), hash(id + 7.1), hash(id + 3.7)) - 0.5) * 0.5;
		float dd = length(f - off);
		float size = mix(0.07, 0.2, hash(id + 9.1));
		star = smoothstep(size, 0.0, dd) * mix(0.5, 1.0, hash(id + 5.5));
		star *= 0.65 + 0.35 * sin(TIME * (1.5 + h * 3.0) + h * 60.0);
	}
	float up = smoothstep(0.0, 0.2, d.y);
	vec3 col = vec3(0.9, 0.95, 1.0) * star * up * night;
	float md = dot(d, normalize(moon_dir));
	float moon = smoothstep(0.9990, 0.9993, md) + 0.10 * smoothstep(0.990, 0.9993, md);
	col += vec3(0.88, 0.92, 1.0) * moon * smoothstep(-0.02, 0.1, d.y) * night;
	ALBEDO = col;
}
"""

# Clouds: one big flat layer of drifting noise high above the ground, faded out in the distance.
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 lit_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade_color : source_color = vec3(0.6, 0.65, 0.75);
uniform float coverage = 0.5;
uniform float opacity = 0.9;
uniform vec2 wind = vec2(0.0);
varying vec3 wpos;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = (wpos.xz + wind) / 700.0;
	float n = fbm(p);
	float dens = smoothstep(1.0 - coverage, 1.0 - coverage + 0.22, n);
	// Cloud bellies are darker: compare with the noise a little toward the sun.
	float shade = clamp((n - fbm(p + vec2(0.05, 0.04))) * 5.0 + 0.4, 0.0, 1.0);
	vec3 col = mix(lit_color, shade_color, shade);
	float dist = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	float edge = 1.0 - smoothstep(1800.0, 3200.0, dist);
	ALBEDO = col;
	ALPHA = dens * edge * opacity;
}
"""

const BIRD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 bird_color : source_color = vec3(0.08, 0.08, 0.10);
uniform vec3 haze_color : source_color = vec3(0.65, 0.78, 0.92);
varying float dist;
void vertex() {
	float ph = INSTANCE_CUSTOM.x;
	float sp = INSTANCE_CUSTOM.y;
	float ax = abs(VERTEX.x);
	// The wings beat up and down; the tips move the most.
	VERTEX.y += sin(TIME * sp + ph) * ax * 0.32 - ax * ax * 0.02;
	dist = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - INV_VIEW_MATRIX[3].xyz);
}
void fragment() {
	ALBEDO = mix(bird_color, haze_color, clamp(dist / 900.0, 0.0, 1.0) * 0.85);
}
"""

var layers: Array = []        # each: {"node": MeshInstance3D, "mat": ShaderMaterial, "strength": float}
var bird_mat: ShaderMaterial
var birds: MultiMeshInstance3D
var flocks: Array = []        # each: {"pos", "heading", "turn", "alt", "offsets", "phases", "first"}
var time := 0.0
var rng := RandomNumberGenerator.new()
var bird_total := 0
var star_node: MeshInstance3D
var star_mat: ShaderMaterial
var cloud_node: MeshInstance3D
var cloud_mat: ShaderMaterial
var cloud_cover := 0.5
var wind_offset := Vector2.ZERO
var moon_dir := Vector3.UP     # set every frame by the main script

func _ready() -> void:
	rng.seed = 5150
	# The mountain rings were removed. add_mountain_ring() is still here if they are wanted again.
	build_birds()
	build_sky_extras()

# ---- Stars and clouds ----

func build_sky_extras() -> void:
	var sh := Shader.new()
	sh.code = STAR_SHADER
	star_mat = ShaderMaterial.new()
	star_mat.shader = sh
	var ball := SphereMesh.new()
	ball.radius = STAR_RADIUS
	ball.height = STAR_RADIUS * 2.0
	ball.radial_segments = 32
	ball.rings = 16
	star_node = MeshInstance3D.new()
	star_node.mesh = ball
	star_node.material_override = star_mat
	star_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star_node.top_level = true
	add_child(star_node)

	var csh := Shader.new()
	csh.code = CLOUD_SHADER
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = csh
	var plane := PlaneMesh.new()
	plane.size = Vector2(CLOUD_SIZE, CLOUD_SIZE)
	cloud_node = MeshInstance3D.new()
	cloud_node.mesh = plane
	cloud_node.material_override = cloud_mat
	cloud_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_node.top_level = true
	add_child(cloud_node)

func update_sky_extras(delta: float, cam: Vector3, haze: Color, day: float, warm: float, biome: int, openness: float) -> void:
	var night := 1.0 - smoothstep(0.05, 0.45, day)
	var outside := openness > 0.05
	star_node.visible = outside and night > 0.01
	star_node.global_position = cam
	star_mat.set_shader_parameter("night", night)
	star_mat.set_shader_parameter("moon_dir", moon_dir)

	cloud_cover = lerpf(cloud_cover, float(CLOUD_COVER[clampi(biome, 0, 5)]), minf(1.0, delta * 0.2))
	wind_offset += CLOUD_DRIFT * delta
	cloud_node.visible = outside
	cloud_node.global_position = Vector3(cam.x, CLOUD_HEIGHT, cam.z)
	var lit := Vector3(0.1, 0.12, 0.2).lerp(Vector3(1.0, 1.0, 1.0), day).lerp(Vector3(1.0, 0.62, 0.42), warm * 0.8)
	var shade := Vector3(0.04, 0.05, 0.09).lerp(Vector3(0.55, 0.6, 0.7), day).lerp(Vector3(0.6, 0.4, 0.45), warm * 0.6)
	cloud_mat.set_shader_parameter("lit_color", lit)
	cloud_mat.set_shader_parameter("shade_color", shade)
	cloud_mat.set_shader_parameter("coverage", cloud_cover)
	cloud_mat.set_shader_parameter("opacity", lerpf(0.7, 0.92, day))
	cloud_mat.set_shader_parameter("wind", wind_offset)

# ---- Mountains ----

func add_mountain_ring(radius: float, max_height: float, strength: float, freq: float, seed_v: int, center_angle: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_v * 977
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5
	var detail := FastNoiseLite.new()
	detail.seed = seed_v * 31
	detail.frequency = 1.0
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var bottom := -max_height * 1.4
	for i in RING_SEGMENTS + 1:
		var a := float(i % RING_SEGMENTS) / float(RING_SEGMENTS) * TAU
		var dx := cos(a)
		var dz := sin(a)
		# Sampling noise on a circle makes the ring join up with no seam.
		var n := noise.get_noise_2d(dx * freq, dz * freq)
		var ridge := pow(clampf(1.0 - absf(n) * 1.3, 0.0, 1.0), 1.3)
		var broad := 0.5 + 0.5 * noise.get_noise_2d(dx * freq * 0.3 + 20.0, dz * freq * 0.3)
		var away := absf(wrapf(a - center_angle, -PI, PI))
		var mask := 1.0 - smoothstep(RANGE_HALF_WIDTH * 0.45, RANGE_HALF_WIDTH, away)   # full in the middle of the range, fading to nothing at its ends
		var h := max_height * (0.1 + 0.9 * ridge * (0.35 + 0.65 * broad)) * mask
		var v := 0.5 + 0.5 * detail.get_noise_2d(dx * 90.0, dz * 90.0)
		verts.append(Vector3(dx * radius, bottom, dz * radius))
		cols.append(Color(0.0, v, 0.0))
		verts.append(Vector3(dx * radius, h * 0.12, dz * radius))
		cols.append(Color(0.08, v, 0.0))
		verts.append(Vector3(dx * radius, h, dz * radius))
		cols.append(Color(1.0, v, 0.0))
	for i in RING_SEGMENTS:
		var b := i * 3
		var c := (i + 1) * 3
		for row in 2:
			idx.append_array(PackedInt32Array([b + row, b + row + 1, c + row, c + row, b + row + 1, c + row + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sh := Shader.new()
	sh.code = MOUNTAIN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("strength", strength)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	layers.append({"node": mi, "mat": mat, "strength": strength})

# ---- Birds ----

func build_birds() -> void:
	# One simple bird: a diamond body with two broad wings, flying toward -Z.
	var v := PackedVector3Array([
		Vector3(0, 0, -1.4), Vector3(-0.3, 0, 0.2), Vector3(0.3, 0, 0.2),           # body front
		Vector3(-0.3, 0, 0.2), Vector3(0, 0, 1.4), Vector3(0.3, 0, 0.2),            # body back and tail
		Vector3(-0.25, 0, -0.5), Vector3(-0.25, 0, 0.5), Vector3(-4.6, 0, 0.15),    # left wing
		Vector3(0.25, 0, -0.5), Vector3(4.6, 0, 0.15), Vector3(0.25, 0, 0.5),       # right wing
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sh := Shader.new()
	sh.code = BIRD_SHADER
	bird_mat = ShaderMaterial.new()
	bird_mat.shader = sh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = MAX_BIRDS
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-6000, -1000, -6000), Vector3(12000, 3000, 12000))
	birds = MultiMeshInstance3D.new()
	birds.multimesh = mm
	birds.material_override = bird_mat
	birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	birds.extra_cull_margin = 16384.0
	add_child(birds)

func new_flock(center: Vector3, toward: bool) -> Dictionary:
	var count := rng.randi_range(5, 12)
	var offsets := []
	var phases := []
	for i in count:
		var row := float(i + 1) / 2.0
		var side := 1.0 if i % 2 == 0 else -1.0
		offsets.append(Vector3(side * row * rng.randf_range(3.0, 4.2), rng.randf_range(-0.8, 0.8), row * rng.randf_range(2.5, 3.5)))
		phases.append(rng.randf() * TAU)
	var a := rng.randf() * TAU
	var pos := center + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(260.0, 480.0)
	var heading := rng.randf() * TAU
	if toward:   # a fresh flock enters from the far side and crosses over you
		heading = atan2(center.z - pos.z, center.x - pos.x) + rng.randf_range(-0.8, 0.8)
	return {"pos": pos, "heading": heading, "turn": 0.0, "alt": rng.randf_range(55.0, 120.0),
		"offsets": offsets, "phases": phases, "wander": rng.randf() * TAU, "speed": BIRD_SPEED * rng.randf_range(0.8, 1.2)}

# Called every frame by main.
func update(delta: float, cam: Vector3, haze: Color, day: float, warm: float, biome: int, openness: float) -> void:
	time += delta
	update_sky_extras(delta, cam, haze, day, warm, biome, openness)
	global_position = Vector3(cam.x, cam.y, cam.z)   # the mountains follow you, so they stay at the horizon
	birds.global_position = Vector3.ZERO

	# Colours: the mountains fade into the haze, and go dark blue-grey at night.
	var rock := Color(0.02, 0.03, 0.06).lerp(Color(0.33, 0.41, 0.55), day).lerp(Color(0.45, 0.30, 0.38), warm * 0.45)
	for l in layers:
		var m: ShaderMaterial = l["mat"]
		m.set_shader_parameter("haze_color", Vector3(haze.r, haze.g, haze.b))
		m.set_shader_parameter("rock_color", Vector3(rock.r, rock.g, rock.b))
		m.set_shader_parameter("snow_amount", 0.3 * day)
		# Closer to the north edge of the world, the range looms larger.
		m.set_shader_parameter("height_scale", lerpf(0.55, 1.5, clampf((WORLD_HALF - cam.z) / (WORLD_HALF * 2.0), 0.0, 1.0)))
	bird_mat.set_shader_parameter("haze_color", Vector3(haze.r, haze.g, haze.b))
	bird_mat.set_shader_parameter("bird_color", Vector3(0.06, 0.06, 0.08).lerp(Vector3(0.02, 0.02, 0.03), 1.0 - day))

	# Birds fly by day and roost at night; and nobody sees them from underground.
	var want := 0
	if day > 0.4 and openness > 0.25:
		want = int(FLOCK_BASE_COUNT[clampi(biome, 0, 5)])
	while flocks.size() < want:
		flocks.append(new_flock(cam, true))
	while flocks.size() > want:
		flocks.pop_back()

	var mm := birds.multimesh
	var n := 0
	for f in flocks:
		# The flock wanders in long gentle curves.
		f["wander"] = float(f["wander"]) + delta * 0.4
		f["turn"] = lerpf(float(f["turn"]), sin(float(f["wander"])) * 0.18, minf(1.0, delta))
		f["heading"] = float(f["heading"]) + float(f["turn"]) * delta
		var dir := Vector3(cos(float(f["heading"])), 0.0, sin(float(f["heading"])))
		f["pos"] = (f["pos"] as Vector3) + dir * float(f["speed"]) * delta
		var p: Vector3 = f["pos"]
		if Vector2(p.x - cam.x, p.z - cam.z).length() > FLOCK_RADIUS:
			var fresh := new_flock(cam, true)
			f["pos"] = fresh["pos"]
			f["heading"] = fresh["heading"]
			p = f["pos"]
		var base_y := cam.y + float(f["alt"]) + sin(time * 0.3 + float(f["wander"])) * 5.0
		var facing := Basis.looking_at(dir, Vector3.UP)
		facing = facing.rotated(dir, float(f["turn"]) * 2.5)   # lean into the turns
		var offs: Array = f["offsets"]
		var phs: Array = f["phases"]
		for i in offs.size():
			if n >= MAX_BIRDS:
				break
			var o: Vector3 = offs[i]
			var bob := sin(time * 1.7 + float(phs[i])) * 0.7
			var pos := Vector3(p.x, base_y, p.z) + facing * (o + Vector3(0, bob, 0))
			mm.set_instance_transform(n, Transform3D(facing, pos))
			mm.set_instance_custom_data(n, Color(float(phs[i]), 8.0 + fposmod(float(phs[i]) * 1.7, 3.0), 0.0, 0.0))
			n += 1
	mm.visible_instance_count = n
