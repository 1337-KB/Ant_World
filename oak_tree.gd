class_name OakTree
extends RefCounted

# A broadleaf tree modelled on a mature oak: a short thick trunk that flares into buttress roots,
# into a few heavy boughs that bend outward and up, thinner limbs and twigs, and a crown made of
# many separate leaf clumps (lighter on top where the sun hits, darker underneath) instead of a few
# big balls. The wood is one merged mesh with plain dark brown bark and
# the leaves are another, which sways in the wind. Two draw calls per tree.

# Plain dark brown bark: the colour comes from the vertices, so every tree gets a slightly different shade.
static var bark_mat: StandardMaterial3D

static func bark_material() -> StandardMaterial3D:
	if bark_mat == null:
		bark_mat = StandardMaterial3D.new()
		bark_mat.vertex_color_use_as_albedo = true
		bark_mat.roughness = 0.95
	return bark_mat

# While a tree is being built, limbs added to this wood mesh also get collision on this body.
static var shape_body: StaticBody3D
static var shape_wood: Flora.Builder
static var shape_min_r := 0.5

static func start_shapes(body: StaticBody3D, wood: Flora.Builder, min_r: float) -> void:
	shape_body = body
	shape_wood = wood
	shape_min_r = min_r

static func end_shapes() -> void:
	shape_body = null
	shape_wood = null

# A tapered round segment from a to b, added to the wood mesh.
static func limb(b: Flora.Builder, a: Vector3, to: Vector3, r0: float, r1: float, color: Color, seg: int = 8) -> void:
	var d := to - a
	var len := d.length()
	if len < 0.01:
		return
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = len
	cm.radial_segments = seg
	cm.rings = 1
	var dir := d / len
	var q := Quaternion(Vector3.UP, dir) if dir.dot(Vector3.UP) > -0.999 else Quaternion(Vector3.RIGHT, PI)
	b.add(cm, Transform3D(Basis(q), (a + to) * 0.5), color)
	# Thick limbs are solid, so the ant can stand and walk on them. The thin twigs are not, to keep physics cheap.
	if shape_body != null and b == shape_wood and maxf(r0, r1) >= shape_min_r:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = (r0 + r1) * 0.5 * 1.05
		sh.height = len
		cs.shape = sh
		cs.transform = Transform3D(Basis(q), (a + to) * 0.5)
		shape_body.add_child(cs)

# A small bunch of leaf lumps around `p`. The outer shell of the crown catches the light and is
# yellow-green; the inside is dark, as in a real oak seen against the sky.
static func clump(lb: Flora.Builder, p: Vector3, size: float, rng: RandomNumberGenerator, ctx: Dictionary) -> void:
	var cy: float = ctx["cy"]
	var hr: float = ctx["R"]
	var vr: float = ctx["Ry"]
	var low: float = ctx["low"]
	var high: float = ctx["high"]
	var out := clampf(Vector3(p.x / hr, (p.y - cy) / vr, p.z / hr).length(), 0.0, 1.2) / 1.2
	var top := clampf((p.y - low) / maxf(1.0, high - low), 0.0, 1.0)
	var n := rng.randi_range(4, 6)
	for i in n:
		var off := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.8), rng.randf_range(-1.0, 1.0)) * size * 0.9
		var s := size * rng.randf_range(0.5, 0.9)
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 6
		sm.rings = 3
		var lit := clampf(out * 0.65 + top * 0.35 + rng.randf_range(-0.12, 0.12), 0.0, 1.0)
		var col := Color(0.08, 0.15, 0.06).lerp(Color(0.30, 0.42, 0.12), lit)
		if rng.randf() < 0.12:
			col = col.lerp(Color(0.55, 0.45, 0.12), 0.6)   # the odd golden patch of leaves
		var basis := Basis.from_euler(Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5)).scaled(Vector3(s, s * 0.7, s))
		lb.add(sm, Transform3D(basis, p + off), col)

# Grow one limb and, recursively, everything that forks off it. Each level is shorter and thinner,
# forks into two or three, and is pulled back inside the crown's egg shape so the outline stays
# a round dome like the real tree. The finest limbs end in leaf clumps.
static func grow(wb: Flora.Builder, lb: Flora.Builder, rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float, radius: float, depth: int, ctx: Dictionary) -> void:
	var cy: float = ctx["cy"]
	var hr: float = ctx["R"]
	var vr: float = ctx["Ry"]
	var max_depth: int = ctx["depth"]
	var bark_c: Color = ctx["bark"]
	var d := dir
	var tip := start + d * length
	# Keep the tip inside the crown: if it would leave the egg, bend the limb back toward the centre.
	var e := Vector3(tip.x / hr, (tip.y - cy) / vr, tip.z / hr).length()
	if e > 1.0:
		var inward := (Vector3(0, cy, 0) - start).normalized()
		d = d.lerp(inward, clampf((e - 1.0) * 1.2 + 0.25, 0.0, 0.85)).normalized()
		tip = start + d * length * clampf(1.0 / e, 0.5, 1.0)
	var end_r := radius * 0.62
	limb(wb, start, tip, radius, end_r, bark_c, 8 if depth == 0 else (6 if depth == 1 else 4))
	if depth >= max_depth:
		clump(lb, tip + Vector3(0, 0.6, 0), rng.randf_range(2.0, 3.4), rng, ctx)
		return
	if depth >= 2:
		# Leaves along the limb, but only out in the shell of the crown, so the branches show inside it.
		var mid := start.lerp(tip, 0.55)
		if Vector3(mid.x / hr, (mid.y - cy) / vr, mid.z / hr).length() > 0.62:
			clump(lb, mid, rng.randf_range(1.8, 2.8), rng, ctx)
	var kids := 3 if rng.randf() < 0.4 else 2
	var around := rng.randf() * TAU
	for k in kids:
		var axis := d.cross(Vector3.UP)
		if axis.length() < 0.05:
			axis = Vector3.RIGHT
		axis = axis.normalized().rotated(d, around + TAU * float(k) / float(kids) + rng.randf_range(-0.4, 0.4))
		var cd := d.rotated(axis, rng.randf_range(0.45, 0.85))
		cd.y = maxf(cd.y, 0.05 if depth < 2 else -0.25)   # young limbs rise; the outer twigs may droop a little
		cd = cd.normalized()
		grow(wb, lb, rng, tip, cd, length * rng.randf_range(0.7, 0.88), end_r * 0.95, depth + 1, ctx)

static func build(c: Content, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(2.4, 3.4)          # trunk radius
	var total := rng.randf_range(36.0, 44.0)    # height of the whole tree
	var trunk_h := total * rng.randf_range(0.2, 0.25)   # a short trunk, as on a real oak: it forks low
	var base_y := c.terrain.ground_height(x, z)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	c.m.stream.region_node(c.m.stream.region_key(x, z)).add_child(body)
	body.global_position = Vector3(x, base_y - 2.0, z)   # sunk a little so it never floats
	body.set_meta("climbable", true)
	body.set_meta("burn_r", 5.0)
	Registry.add(body, "plants")

	var wb := Flora.Builder.new()   # trunk and limbs
	var lb := Flora.Builder.new()   # leaves
	start_shapes(body, wb, 0.55)
	var bark_c := Color(0.24, 0.16, 0.10).lerp(Color(0.2, 0.14, 0.1), rng.randf())

	# The crown is an egg: wide, and reaching from just above the fork to the top.
	var low := trunk_h * 0.9
	var ctx := {
		"cy": (trunk_h + total) * 0.5 + 1.0,
		"R": rng.randf_range(15.0, 18.0),   # much wider than it is tall, like a spreading park oak
		"Ry": (total - trunk_h) * 0.5 + 2.0,
		"low": low,
		"high": total,
		"depth": 4,
		"bark": bark_c,
	}

	# Trunk: short, thick and flared, with a slight lean.
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * 0.8
	var fork := Vector3(0, trunk_h, 0) + lean
	limb(wb, Vector3.ZERO, Vector3(0, trunk_h * 0.35, 0) + lean * 0.3, r * 1.75, r * 1.2, bark_c, 14)
	limb(wb, Vector3(0, trunk_h * 0.35, 0) + lean * 0.3, fork + Vector3(0, 1.0, 0), r * 1.2, r * 0.95, bark_c, 14)
	# Buttress roots spreading from the foot.
	var roots := rng.randi_range(5, 7)
	for i in roots:
		var a := TAU * float(i) / float(roots) + rng.randf_range(-0.25, 0.25)
		var dirh := Vector3(cos(a), 0, sin(a))
		var rl := r * rng.randf_range(2.0, 3.0)
		var from := dirh * r * 0.9 + Vector3(0, trunk_h * 0.2, 0)
		var mid := dirh * (r * 1.6 + rl * 0.5) + Vector3(0, trunk_h * 0.05, 0)
		var rtip := dirh * (r * 1.4 + rl) + Vector3(0, 1.0, 0)
		limb(wb, from, mid, r * 0.5, r * 0.4, bark_c, 6)
		limb(wb, mid, rtip, r * 0.4, r * 0.15, bark_c, 6)

	# Main limbs leave the fork and rise outward at about 55 degrees, each splitting again and again.
	var mains := rng.randi_range(3, 4)
	var yaw0 := rng.randf() * TAU
	for i in mains:
		var a := yaw0 + TAU * float(i) / float(mains) + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), rng.randf_range(0.55, 0.85), sin(a)).normalized()   # sweeping out low, then curving up
		grow(wb, lb, rng, fork, dir, float(ctx["R"]) * rng.randf_range(0.42, 0.5), r * rng.randf_range(0.62, 0.74), 0, ctx)
	# And one leader carrying on up the middle, so the top of the dome is filled.
	grow(wb, lb, rng, fork, Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.15, 0.15)).normalized(), (total - trunk_h) * 0.35, r * 0.5, 0, ctx)

	end_shapes()
	var wood := MeshInstance3D.new()
	wood.mesh = wb.build()
	wood.material_override = bark_material()
	c.fade_far(wood)
	body.add_child(wood)

	var lm := ShaderMaterial.new()
	lm.shader = PlantSway.get_shader()
	lm.set_shader_parameter("use_vertex_color", true)
	lm.set_shader_parameter("base_y", low)
	lm.set_shader_parameter("mesh_height", total - low)
	lm.set_shader_parameter("amp", 0.6)
	lm.set_shader_parameter("push_amt", 0.0)
	lm.set_shader_parameter("roughness_v", 0.88)
	var leaves := MeshInstance3D.new()
	leaves.mesh = lb.build()
	leaves.material_override = lm
	leaves.set_meta("leafy", true)   # fire hides it when the tree burns (plant_burn.gd)
	c.fade_far(leaves)
	body.add_child(leaves)

	# The trunk is solid. One tapered shape matches its widest part.
	var tm := CylinderMesh.new()
	tm.bottom_radius = r * 1.5
	tm.top_radius = r * 0.9
	tm.height = trunk_h + 2.0
	tm.radial_segments = 16
	tm.rings = 2
	var col := CollisionShape3D.new()
	col.shape = tm.create_convex_shape(true, true)
	col.position = Vector3(0, (trunk_h + 2.0) * 0.5, 0)
	body.add_child(col)

	c.add_obstacle({"pos": Vector3(x, base_y, z), "radius": r * 1.5})
