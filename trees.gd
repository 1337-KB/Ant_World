class_name Trees
extends RefCounted

# The non-oak trees, built the same way as the oak (oak_tree.gd): wood as one merged mesh in plain
# brown, leaves as a second merged mesh that sways in the wind. Two draw calls per tree, and a
# shape that follows the real tree:
#   spruce  - a straight trunk with whorls of drooping branches, narrowing to a spire
#   pine    - a tall bare trunk with a high crown of flat pads of needles (like a Scots pine)
#   willow  - a short fat trunk, arching limbs, and curtains of hanging strands
#   acacia  - a leaning, forked trunk under a wide flat umbrella of leaves
#   dead    - a grey, bare, crooked trunk with snapped branches

# A tapered rod from a to b, in the wood mesh (or the leaf mesh, for needle strands).
static func rod(b: Flora.Builder, a: Vector3, to: Vector3, r0: float, r1: float, color: Color, seg: int = 6) -> void:
	OakTree.limb(b, a, to, r0, r1, color, seg)

# A flattened lump of leaves or needles.
static func lump(lb: Flora.Builder, p: Vector3, size: Vector3, color: Color, rng: RandomNumberGenerator, seg: int = 6) -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = seg
	sm.rings = maxi(3, seg / 2)
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(size)
	lb.add(sm, Transform3D(basis, p), color)

static func shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)

static func make_body(c: Content, x: float, z: float, burn_r: float) -> StaticBody3D:
	return c.new_plant_body(x, z, true, burn_r)

# Add the wood and the leaves to the body, plus a solid trunk.
static func finish(c: Content, body: StaticBody3D, wb: Flora.Builder, lb: Flora.Builder, low: float, high: float, amp: float, trunk_r: float, trunk_h: float, x: float, z: float) -> void:
	OakTree.end_shapes()
	var wood := MeshInstance3D.new()
	wood.mesh = wb.build()
	wood.material_override = OakTree.bark_material()
	c.fade_far(wood)
	body.add_child(wood)
	if lb.verts.size() > 0:
		var lm := ShaderMaterial.new()
		lm.shader = PlantSway.get_shader()
		lm.set_shader_parameter("use_vertex_color", true)
		lm.set_shader_parameter("base_y", low)
		lm.set_shader_parameter("mesh_height", maxf(1.0, high - low))
		lm.set_shader_parameter("amp", amp)
		lm.set_shader_parameter("push_amt", 0.0)
		lm.set_shader_parameter("roughness_v", 0.9)
		var leaves := MeshInstance3D.new()
		leaves.mesh = lb.build()
		leaves.material_override = lm
		leaves.set_meta("leafy", true)   # fire hides it when the tree burns (plant_burn.gd)
		c.fade_far(leaves)
		body.add_child(leaves)
	var tm := CylinderMesh.new()
	tm.bottom_radius = trunk_r * 1.25
	tm.top_radius = trunk_r * 0.6
	tm.height = trunk_h
	tm.radial_segments = 10
	tm.rings = 1
	var col := CollisionShape3D.new()
	col.shape = tm.create_convex_shape(true, true)
	col.position = Vector3(0, trunk_h * 0.5, 0)
	body.add_child(col)
	c.add_obstacle({"pos": Vector3(x, c.terrain.ground_height(x, z), z), "radius": trunk_r * 1.4})

# ---------- Spruce ----------

static func spruce(c: Content, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var H := rng.randf_range(30.0, 44.0)
	var r := rng.randf_range(0.9, 1.4)
	var body := make_body(c, x, z, 4.0)
	var wb := Flora.Builder.new()
	var lb := Flora.Builder.new()
	var bark := Color(0.26, 0.17, 0.11)
	rod(wb, Vector3.ZERO, Vector3(0, H, 0), r * 1.2, r * 0.12, bark, 8)
	var base := Color(0.07, 0.22, 0.12).lerp(Color(0.11, 0.3, 0.16), rng.randf())
	var widest := rng.randf_range(7.0, 9.0)
	var y0 := H * 0.16
	var y := y0
	while y < H * 0.97:
		var t := (y - y0) / (H * 0.97 - y0)
		var reach := lerpf(widest, 0.9, pow(t, 0.85))
		var n := 6 if t < 0.6 else 5
		var spin := rng.randf() * TAU
		for i in n:
			var a := spin + TAU * float(i) / float(n) + rng.randf_range(-0.2, 0.2)
			var L := reach * rng.randf_range(0.82, 1.05)
			var dir := Vector3(cos(a), lerpf(-0.42, -0.1, t), sin(a)).normalized()
			var start := Vector3(0, y, 0)
			var tip := start + dir * L
			rod(wb, start, tip, 0.2 * (1.0 - t * 0.6), 0.05, bark, 4)
			# A skirt of needles drooping along the branch, darker near the trunk and lighter at the tips.
			var g := rng.randf_range(0.85, 1.12)
			lump(lb, start.lerp(tip, 0.55) + Vector3(0, -0.5, 0), Vector3(L * 0.34, 0.9, L * 0.34), shade(base, 0.8 * g), rng)
			lump(lb, start.lerp(tip, 0.88) + Vector3(0, -0.8, 0), Vector3(L * 0.2, 0.75, L * 0.2), shade(base, 1.15 * g), rng)
		y += lerpf(3.0, 2.0, t)
	# The leader: a slim spire of needles at the top.
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 1.1
	spire.height = H * 0.1
	spire.radial_segments = 6
	spire.rings = 1
	lb.add(spire, Transform3D(Basis.IDENTITY, Vector3(0, H * 0.96, 0)), shade(base, 1.1))
	finish(c, body, wb, lb, y0, H, 0.4, r, H * 0.8, x, z)

# ---------- Pine ----------

static func pine(c: Content, x: float, z: float, rng: RandomNumberGenerator, leaf: Color) -> void:
	var H := rng.randf_range(24.0, 34.0)
	var r := rng.randf_range(1.2, 1.7)
	var body := make_body(c, x, z, 4.0)
	var wb := Flora.Builder.new()
	var lb := Flora.Builder.new()
	OakTree.start_shapes(body, wb, 0.3)
	var low_bark := Color(0.24, 0.16, 0.1)
	var high_bark := Color(0.46, 0.27, 0.14)   # the upper trunk of a pine is orange-red
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * H * 0.025
	var crown_y := H * 0.64
	rod(wb, Vector3.ZERO, Vector3(0, crown_y, 0) + lean * 0.6, r * 1.25, r * 0.8, low_bark, 10)
	rod(wb, Vector3(0, crown_y, 0) + lean * 0.6, Vector3(0, H * 0.98, 0) + lean, r * 0.8, r * 0.15, high_bark, 8)
	var branches := rng.randi_range(5, 7)
	var spin := rng.randf() * TAU
	for i in branches:
		var a := spin + TAU * float(i) / float(branches) + rng.randf_range(-0.3, 0.3)
		var t := float(i) / float(branches - 1)
		var from := Vector3(0, crown_y + t * (H * 0.3), 0) + lean * (0.6 + t * 0.4)
		var L := lerpf(8.0, 4.0, t) * rng.randf_range(0.85, 1.15)
		var dir := Vector3(cos(a), rng.randf_range(0.15, 0.5), sin(a)).normalized()
		var tip := from + dir * L
		rod(wb, from, tip, r * 0.32, r * 0.1, high_bark, 5)
		# A flat pad of needles at the end of each branch, and a smaller one partway along.
		var g := rng.randf_range(0.85, 1.12)
		var pad := lerpf(4.8, 3.0, t) * rng.randf_range(0.85, 1.15)
		lump(lb, tip + Vector3(0, 0.6, 0), Vector3(pad, pad * 0.3, pad), shade(leaf, g), rng, 8)
		lump(lb, from.lerp(tip, 0.6) + Vector3(0, 0.9, 0), Vector3(pad * 0.6, pad * 0.2, pad * 0.6), shade(leaf, g * 0.85), rng, 6)
	lump(lb, Vector3(0, H, 0) + lean, Vector3(3.2, 1.1, 3.2), shade(leaf, 1.1), rng, 8)
	finish(c, body, wb, lb, crown_y, H, 0.4, r, H * 0.7, x, z)

# ---------- Willow ----------

static func willow(c: Content, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var H := rng.randf_range(15.0, 22.0)
	var r := rng.randf_range(2.0, 2.8)
	var body := make_body(c, x, z, 4.0)
	var wb := Flora.Builder.new()
	var lb := Flora.Builder.new()
	OakTree.start_shapes(body, wb, 0.4)
	var bark := Color(0.22, 0.17, 0.12)
	var trunk_h := H * 0.38
	rod(wb, Vector3.ZERO, Vector3(0, trunk_h, 0), r * 1.45, r * 1.0, bark, 12)
	var limbs := rng.randi_range(4, 5)
	var spin := rng.randf() * TAU
	for i in limbs:
		var a := spin + TAU * float(i) / float(limbs) + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		var p1 := Vector3(0, trunk_h, 0) + d * H * 0.18 + Vector3(0, H * 0.3, 0)
		var p2 := p1 + d * H * 0.3 + Vector3(0, H * 0.12, 0)
		rod(wb, Vector3(0, trunk_h * 0.9, 0), p1, r * 0.62, r * 0.45, bark, 7)
		rod(wb, p1, p2, r * 0.45, r * 0.22, bark, 6)
		# Strands hanging from the limb, thick enough to read as a curtain of leaves.
		for k in 14:
			var u := rng.randf_range(0.15, 1.0)
			var p := p1.lerp(p2, u) if k % 2 == 0 else Vector3(0, trunk_h * 0.9, 0).lerp(p1, u)
			p += Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
			var len := rng.randf_range(0.45, 0.8) * (H * 0.75) * lerpf(0.7, 1.0, u)
			var sway := Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8))
			var tint := Color(0.2, 0.36, 0.12).lerp(Color(0.42, 0.5, 0.16), rng.randf())
			rod(lb, p, p + Vector3(0, -len, 0) + sway, 0.42, 0.16, tint, 4)
		lump(lb, p2 + Vector3(0, 0.8, 0), Vector3(4.0, 1.6, 4.0), Color(0.2, 0.36, 0.12), rng, 7)
	lump(lb, Vector3(0, H * 0.78, 0), Vector3(5.0, 2.0, 5.0), Color(0.24, 0.4, 0.13), rng, 7)
	finish(c, body, wb, lb, trunk_h, H, 0.55, r, trunk_h + 1.0, x, z)

# ---------- Acacia ----------

static func acacia(c: Content, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var H := rng.randf_range(18.0, 27.0)
	var r := rng.randf_range(1.0, 1.5)
	var body := make_body(c, x, z, 4.0)
	var wb := Flora.Builder.new()
	var lb := Flora.Builder.new()
	OakTree.start_shapes(body, wb, 0.45)
	var bark := Color(0.32, 0.23, 0.15)
	# A trunk that leans and bends, then forks into three or four limbs.
	var facing := rng.randf() * TAU
	var lean := Vector3(cos(facing), 0, sin(facing)) * H * rng.randf_range(0.06, 0.16)
	var k1 := Vector3(0, H * 0.4, 0) + lean * 0.4
	var fork := Vector3(0, H * 0.68, 0) + lean
	rod(wb, Vector3.ZERO, k1, r * 1.25, r * 0.95, bark, 8)
	rod(wb, k1, fork, r * 0.95, r * 0.7, bark, 8)
	var limbs := rng.randi_range(3, 4)
	var spin := rng.randf() * TAU
	var top := fork.y
	for i in limbs:
		var a := spin + TAU * float(i) / float(limbs) + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		var mid := fork + d * H * 0.14 + Vector3(0, H * 0.14, 0)
		var tip := mid + d * H * 0.2 + Vector3(0, H * 0.12, 0)
		rod(wb, fork, mid, r * 0.6, r * 0.42, bark, 6)
		rod(wb, mid, tip, r * 0.42, r * 0.2, bark, 5)
		top = maxf(top, tip.y)
		# The umbrella: flat layers of leaves, dark underneath and bright on top.
		var w := H * rng.randf_range(0.26, 0.34)
		lump(lb, tip + Vector3(0, 0.4, 0), Vector3(w, 0.9, w), Color(0.22, 0.34, 0.1), rng, 8)
		lump(lb, tip + Vector3(0, 1.3, 0), Vector3(w * 0.85, 0.8, w * 0.85), Color(0.36, 0.5, 0.13), rng, 8)
		lump(lb, mid + Vector3(0, 0.6, 0), Vector3(w * 0.6, 0.7, w * 0.6), Color(0.3, 0.44, 0.12), rng, 6)
	lump(lb, Vector3(0, top + 0.5, 0) + lean, Vector3(H * 0.32, 0.9, H * 0.32), Color(0.34, 0.48, 0.13), rng, 8)
	finish(c, body, wb, lb, H * 0.55, top + 2.0, 0.4, r, fork.y, x, z)

# ---------- Dead tree ----------

static func dead_grow(wb: Flora.Builder, rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float, radius: float, depth: int, color: Color) -> void:
	# Two crooked segments, then a snapped stub or a fork.
	var d1 := dir
	var p1 := start + d1 * length * 0.55
	rod(wb, start, p1, radius, radius * 0.75, color, 5)
	var d2 := d1.rotated(Vector3.UP.cross(d1).normalized() if absf(d1.y) < 0.95 else Vector3.RIGHT, rng.randf_range(-0.7, 0.7)).normalized()
	d2 = d2.rotated(Vector3.UP, rng.randf_range(-0.5, 0.5)).normalized()
	var p2 := p1 + d2 * length * 0.5
	rod(wb, p1, p2, radius * 0.75, radius * 0.4, color, 5)
	if depth >= 2:
		return
	for k in 2:
		var cd := d2.rotated(Vector3.UP, rng.randf_range(-1.1, 1.1)).rotated(d2.cross(Vector3.UP).normalized() if absf(d2.y) < 0.95 else Vector3.RIGHT, rng.randf_range(0.2, 0.7)).normalized()
		if rng.randf() < 0.85:
			dead_grow(wb, rng, p2, cd, length * rng.randf_range(0.5, 0.75), radius * 0.45, depth + 1, color)

static func dead(c: Content, x: float, z: float, rng: RandomNumberGenerator) -> void:
	var H := rng.randf_range(16.0, 25.0)
	var r := rng.randf_range(1.2, 1.8)
	var body := make_body(c, x, z, 4.0)
	var wb := Flora.Builder.new()
	var lb := Flora.Builder.new()
	OakTree.start_shapes(body, wb, 0.3)
	var wood := Color(0.42, 0.38, 0.34)
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * 1.2
	rod(wb, Vector3.ZERO, Vector3(0, H * 0.5, 0) + lean * 0.5, r * 1.3, r * 0.8, wood, 9)
	rod(wb, Vector3(0, H * 0.5, 0) + lean * 0.5, Vector3(0, H, 0) + lean, r * 0.8, r * 0.28, wood, 8)   # the top is snapped off
	var branches := rng.randi_range(4, 6)
	for i in branches:
		var t := rng.randf_range(0.35, 0.95)
		var a := rng.randf() * TAU
		var from := Vector3(0, H * t, 0) + lean * t
		var dir := Vector3(cos(a), rng.randf_range(0.2, 0.9), sin(a)).normalized()
		dead_grow(wb, rng, from, dir, rng.randf_range(5.0, 8.5) * lerpf(1.0, 0.6, t), r * 0.34, 0, wood)
	finish(c, body, wb, lb, 0.0, H, 0.0, r, H * 0.7, x, z)
