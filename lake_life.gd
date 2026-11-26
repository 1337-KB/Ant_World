class_name LakeLife
extends RefCounted

# Plants that grow on the lake bed: kelp, seagrass and sea cabbage. The kelp and seagrass sway in
# the current. Everything is built from a few simple meshes. Each builder puts one plant on the
# bed at `pos` (the bed height) and returns it.

const SWAY_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.1, 0.35, 0.12);
uniform vec3 tip_color : source_color = vec3(0.35, 0.6, 0.2);
uniform float plant_height = 3.0;
uniform float amplitude = 0.4;
uniform float speed = 1.0;

varying float k;

void vertex() {
	k = clamp(VERTEX.y / plant_height, 0.0, 1.0);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * speed + origin.x * 0.6 + origin.z * 0.45;
	float bend = k * k;
	VERTEX.x += sin(t + VERTEX.y * 0.9) * amplitude * bend;
	VERTEX.z += cos(t * 0.8 + VERTEX.y * 0.7) * amplitude * 0.6 * bend;
}

void fragment() {
	ALBEDO = mix(base_color, tip_color, k);
	ROUGHNESS = 0.55;
}
"""

static var sway_shader: Shader

static func sway_material(base: Color, tip: Color, height: float, amp: float, speed: float) -> ShaderMaterial:
	if sway_shader == null:
		sway_shader = Shader.new()
		sway_shader.code = SWAY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sway_shader
	mat.set_shader_parameter("base_color", Vector3(base.r, base.g, base.b))
	mat.set_shader_parameter("tip_color", Vector3(tip.r, tip.g, tip.b))
	mat.set_shader_parameter("plant_height", height)
	mat.set_shader_parameter("amplitude", amp)
	mat.set_shader_parameter("speed", speed)
	return mat

# One upright ribbon, standing on the origin, as a tall plane with many rows so it can bend.
static func ribbon(parent: Node3D, width: float, height: float, rows: int, mat: Material, yaw: float, offset: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = Vector2(width, height)
	pm.subdivide_depth = rows
	pm.center_offset = Vector3(0, height * 0.5, 0)
	mi.mesh = pm
	mi.material_override = mat
	mi.rotation.y = yaw
	mi.position = offset
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

# Tall kelp: a few long fronds rising toward the surface, never quite reaching it.
static func kelp(parent: Node, pos: Vector3, max_height: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var h := clampf(rng.randf_range(3.0, 7.5), 1.5, maxf(1.5, max_height))
	var tint := rng.randf()
	var base := Color(0.25, 0.22, 0.06).lerp(Color(0.08, 0.28, 0.1), tint)
	var tip := Color(0.55, 0.5, 0.15).lerp(Color(0.3, 0.65, 0.22), tint)
	for i in 4:
		var fh := h * rng.randf_range(0.65, 1.0)
		var mat := sway_material(base, tip, fh, rng.randf_range(0.35, 0.7), rng.randf_range(0.8, 1.2))
		ribbon(root, rng.randf_range(0.35, 0.6), fh, 12, mat, rng.randf() * PI,
			Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35)))
	return root

# A tuft of grass-like blades.
static func seagrass(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var base := Color(0.1, 0.3, 0.12)
	var tip := Color(0.4, 0.75, 0.3).lerp(Color(0.6, 0.8, 0.35), rng.randf())
	for i in 9:
		var bh := rng.randf_range(0.8, 1.9)
		var mat := sway_material(base, tip, bh, rng.randf_range(0.2, 0.35), rng.randf_range(1.0, 1.5))
		ribbon(root, 0.12, bh, 5, mat, rng.randf() * PI,
			Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4)))
	return root

# Sea cabbage: a low rosette of frilly purple-green leaves.
static func sea_cabbage(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var purple := rng.randf() < 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.2, 0.5) if purple else Color(0.2, 0.5, 0.45)
	mat.roughness = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.7, 0.4, 0.7) if purple else Color(0.45, 0.75, 0.6)
	inner.roughness = 0.5
	var scale_all := rng.randf_range(0.8, 1.4)
	for ring in 2:
		var n := 6 if ring == 0 else 5
		for i in n:
			var leaf := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 10
			sm.rings = 5
			leaf.mesh = sm
			leaf.material_override = mat if ring == 0 else inner
			leaf.scale = Vector3(0.9, 0.12, 0.6) * scale_all * (1.0 - 0.3 * float(ring))
			var a := TAU * float(i) / float(n) + float(ring) * 0.5
			var r := (0.55 - 0.25 * float(ring)) * scale_all
			leaf.position = Vector3(cos(a) * r, 0.25 + 0.2 * float(ring), sin(a) * r)
			leaf.rotation = Vector3(0, -a, 0)
			leaf.rotate_object_local(Vector3(0, 0, 1), 0.55 + 0.4 * float(ring))
			root.add_child(leaf)
	return root
