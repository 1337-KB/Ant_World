class_name Flora
extends RefCounted

# Wildflowers, cacti, moss and mushrooms. Each kind is one small mesh, built here from simple
# shapes with the colours baked into the vertices, so a whole meadow of one kind is a single
# cheap draw. Which kinds grow where depends on the biome (see WEIGHTS).
#
# Sizes are for an ant: a flower is a bit taller than you, a mushroom cap is about your length.

const NAMES := [
	"daisy", "poppy", "lupine", "buttercup", "pink bloom", "red hot poker", "cattail",
	"barrel cactus", "saguaro", "desert bloom", "moss", "saxifrage",
	"fly agaric", "porcini", "parasol", "mushroom cluster", "chanterelle", "glow mushroom",
	"fern", "clover", "bush", "dry shrub", "dandelion", "leaf litter", "twigs", "acorn", "snow tussock",
	"hedge bush",
]
const GLOW := 17   # this kind glows in the dark

# How common each kind is in each biome: forest, desert, highlands, tundra, swamp, savanna, plains.
const WEIGHTS := [
	[3.0, 0.0, 3.0, 0.5, 0.5, 1.5, 4.0],   # daisy
	[2.0, 0.3, 1.0, 0.0, 0.0, 3.0, 3.0],   # poppy
	[2.0, 0.0, 3.0, 2.0, 0.0, 0.0, 1.0],   # lupine
	[2.0, 0.0, 1.0, 0.0, 1.5, 2.0, 4.0],   # buttercup
	[1.0, 0.0, 0.5, 0.0, 1.5, 2.0, 2.5],   # pink bloom
	[0.0, 1.5, 0.0, 0.0, 0.0, 3.0, 0.5],   # red hot poker
	[0.2, 0.0, 0.0, 0.0, 4.0, 0.0, 0.0],   # cattail
	[0.0, 3.0, 0.0, 0.0, 0.0, 0.3, 0.0],   # barrel cactus
	[0.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0],   # saguaro
	[0.0, 3.0, 0.0, 0.0, 0.0, 1.0, 0.0],   # desert bloom
	[1.5, 0.0, 1.5, 3.0, 2.0, 0.0, 0.0],   # moss
	[0.0, 0.0, 1.0, 3.0, 0.0, 0.0, 0.0],   # saxifrage
	[3.0, 0.0, 2.5, 0.5, 0.5, 0.0, 0.0],   # fly agaric
	[2.5, 0.0, 1.5, 0.0, 1.5, 0.3, 0.0],   # porcini
	[1.5, 0.0, 1.0, 0.0, 0.0, 1.5, 0.6],   # parasol
	[2.0, 0.0, 1.0, 0.0, 2.0, 0.0, 0.0],   # mushroom cluster
	[1.0, 0.0, 1.5, 0.0, 0.0, 0.5, 0.0],   # chanterelle
	[1.0, 0.0, 0.5, 1.5, 3.0, 0.0, 0.0],   # glow mushroom
	[3.0, 0.0, 1.5, 0.3, 3.0, 0.0, 0.3],   # fern
	[2.0, 0.0, 2.0, 0.0, 1.0, 1.5, 4.0],   # clover
	[2.0, 0.5, 1.5, 0.6, 1.5, 1.0, 2.0],   # bush
	[0.0, 2.5, 0.0, 0.0, 0.0, 1.5, 0.0],   # dry shrub
	[1.5, 0.0, 1.0, 0.0, 0.3, 2.0, 4.0],   # dandelion
	[4.0, 0.0, 2.0, 0.0, 1.0, 0.5, 0.0],   # leaf litter
	[3.0, 0.5, 2.0, 0.5, 2.0, 1.0, 0.3],   # twigs
	[1.5, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0],   # acorn
	[0.0, 0.0, 1.5, 3.0, 0.0, 0.0, 0.0],   # snow tussock
	[3.0, 0.0, 1.5, 0.3, 1.5, 0.8, 0.8],   # hedge bush
]

# Patch size: how many grow together, and how far they spread (units).
const PATCH := [
	[3, 9, 2.4], [2, 6, 2.4], [3, 8, 2.2], [3, 9, 2.4], [2, 6, 2.4], [1, 4, 2.4], [3, 8, 2.0],
	[1, 2, 3.0], [1, 2, 4.0], [2, 5, 2.6], [2, 5, 2.2], [3, 8, 1.6],
	[1, 4, 1.4], [1, 3, 1.4], [1, 3, 1.8], [1, 2, 1.0], [1, 4, 1.4], [1, 3, 1.2],
	[1, 4, 2.0], [4, 12, 2.2], [1, 3, 2.6], [1, 3, 3.0], [2, 6, 2.2], [3, 9, 2.6], [2, 6, 2.4], [1, 3, 1.6], [3, 8, 2.0],
	[1, 3, 3.5],
]

static var meshes := {}

# ---------- Picking ----------

static func pick(biome: int, roll: float) -> int:
	var total := 0.0
	for i in WEIGHTS.size():
		total += float(WEIGHTS[i][biome])
	if total <= 0.0:
		return -1
	var r := roll * total
	for i in WEIGHTS.size():
		r -= float(WEIGHTS[i][biome])
		if r <= 0.0 and float(WEIGHTS[i][biome]) > 0.0:
			return i
	return 0

static func get_mesh(id: int) -> ArrayMesh:
	if not meshes.has(id):
		meshes[id] = build(id)
	return meshes[id]

static func make_material(id: int, fade_near: float, fade_far: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_max_distance = fade_near
	m.distance_fade_min_distance = fade_far
	if id == GLOW:
		m.emission_enabled = true
		m.emission = Color(0.2, 0.95, 0.85)
		m.emission_energy_multiplier = 1.6
	return m

# ---------- Mesh building ----------

class Builder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(prim: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
		var arrays := prim.get_mesh_arrays()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized())
			cols.append(color)
		for i in ix:
			idx.append(base + i)

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

# A rod standing on `base`, going up `h` (or along `axis`).
static func rod(b: Builder, top: float, bottom: float, h: float, base: Vector3, color: Color, seg: int = 6, tilt: Basis = Basis.IDENTITY) -> void:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	b.add(m, Transform3D(tilt, base + tilt.y * h * 0.5), color)

static func ball(b: Builder, r: float, pos: Vector3, scale: Vector3, color: Color, seg: int = 8, rings: int = 4, rot: Basis = Basis.IDENTITY) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	b.add(m, Transform3D(rot * Basis.from_scale(scale), pos), color)

static func petals(b: Builder, count: int, ring: float, y: float, r: float, scale: Vector3, color: Color) -> void:
	for i in count:
		var a := float(i) * TAU / float(count)
		ball(b, r, Vector3(cos(a) * ring, y, sin(a) * ring), scale, color, 5, 3, Basis(Vector3.UP, -a))

static func mushroom(b: Builder, pos: Vector3, h: float, cap_r: float, stem_color: Color, cap_color: Color, flat: float = 0.55) -> void:
	rod(b, cap_r * 0.28, cap_r * 0.36, h, pos, stem_color, 6)
	ball(b, cap_r, pos + Vector3(0, h - cap_r * 0.1, 0), Vector3(1, flat, 1), cap_color, 8, 5)

static func build(id: int) -> ArrayMesh:
	var b := Builder.new()
	var green := Color(0.25, 0.5, 0.18)
	var dark_green := Color(0.2, 0.42, 0.16)
	match id:
		0:   # daisy
			rod(b, 0.03, 0.04, 1.3, Vector3.ZERO, green, 5)
			ball(b, 0.13, Vector3(0, 1.32, 0), Vector3(1, 0.6, 1), Color(0.95, 0.75, 0.1), 7, 4)
			petals(b, 9, 0.27, 1.32, 0.14, Vector3(1.0, 0.18, 0.45), Color(0.97, 0.97, 0.94))
			ball(b, 0.16, Vector3(0.35, 0.18, 0), Vector3(1, 0.4, 0.5), dark_green, 5, 3)
		1:   # poppy
			rod(b, 0.03, 0.04, 1.3, Vector3.ZERO, green, 5)
			ball(b, 0.27, Vector3(0, 1.4, 0), Vector3(1, 0.75, 1), Color(0.88, 0.1, 0.08), 8, 5)
			petals(b, 4, 0.2, 1.5, 0.2, Vector3(0.9, 0.7, 0.5), Color(0.8, 0.07, 0.07))
			ball(b, 0.07, Vector3(0, 1.58, 0), Vector3.ONE, Color(0.08, 0.05, 0.05), 5, 3)
		2:   # lupine: a spike of blue-purple blooms
			rod(b, 0.03, 0.05, 1.9, Vector3.ZERO, green, 5)
			for i in 9:
				var y := 0.95 + float(i) * 0.11
				var a := float(i) * 2.4
				var c := Color(0.45, 0.3, 0.85) if i % 2 == 0 else Color(0.62, 0.42, 0.92)
				ball(b, 0.1 * (1.0 - float(i) * 0.05), Vector3(cos(a) * 0.1, y, sin(a) * 0.1), Vector3(1, 0.9, 1), c, 5, 3)
			ball(b, 0.07, Vector3(0, 1.98, 0), Vector3.ONE, Color(0.6, 0.4, 0.9), 5, 3)
		3:   # buttercup
			rod(b, 0.03, 0.04, 1.0, Vector3.ZERO, green, 5)
			ball(b, 0.24, Vector3(0, 1.05, 0), Vector3(1, 0.45, 1), Color(1.0, 0.85, 0.1), 8, 4)
			ball(b, 0.09, Vector3(0, 1.12, 0), Vector3(1, 0.6, 1), Color(1.0, 0.95, 0.5), 5, 3)
		4:   # pink bloom
			rod(b, 0.03, 0.045, 1.9, Vector3.ZERO, green, 5)
			petals(b, 6, 0.24, 1.9, 0.2, Vector3(1.0, 0.22, 0.6), Color(0.95, 0.45, 0.7))
			ball(b, 0.1, Vector3(0, 1.93, 0), Vector3(1, 0.7, 1), Color(0.98, 0.8, 0.2), 6, 3)
		5:   # red hot poker
			rod(b, 0.03, 0.05, 1.5, Vector3.ZERO, green, 5)
			rod(b, 0.15, 0.13, 0.4, Vector3(0, 1.25, 0), Color(0.98, 0.75, 0.15), 7)
			rod(b, 0.09, 0.15, 0.5, Vector3(0, 1.62, 0), Color(0.95, 0.35, 0.1), 7)
			ball(b, 0.09, Vector3(0, 2.12, 0), Vector3(1, 1.2, 1), Color(0.95, 0.3, 0.08), 6, 3)
		6:   # cattail
			rod(b, 0.04, 0.05, 2.7, Vector3.ZERO, Color(0.35, 0.5, 0.2), 5)
			rod(b, 0.09, 0.09, 0.65, Vector3(0, 2.0, 0), Color(0.36, 0.2, 0.1), 7)
			ball(b, 0.07, Vector3(0, 2.68, 0), Vector3(0.7, 1.5, 0.7), Color(0.3, 0.18, 0.1), 5, 3)
			rod(b, 0.0, 0.06, 2.2, Vector3(0.1, 0, 0), Color(0.3, 0.55, 0.2), 4, Basis(Vector3(0, 0, 1), -0.18))
			rod(b, 0.0, 0.06, 1.8, Vector3(-0.1, 0, 0), Color(0.28, 0.5, 0.18), 4, Basis(Vector3(0, 0, 1), 0.22))
		7:   # barrel cactus with a flower
			ball(b, 0.55, Vector3(0, 0.45, 0), Vector3(1, 0.95, 1), Color(0.25, 0.55, 0.3), 10, 6)
			for i in 6:
				var a := float(i) * TAU / 6.0
				ball(b, 0.1, Vector3(cos(a) * 0.42, 0.5, sin(a) * 0.42), Vector3(0.5, 3.2, 0.5), Color(0.18, 0.45, 0.24), 4, 3)
			ball(b, 0.17, Vector3(0, 0.98, 0), Vector3(1, 0.6, 1), Color(0.95, 0.4, 0.6), 6, 3)
		8:   # small saguaro
			var cg := Color(0.22, 0.5, 0.28)
			rod(b, 0.2, 0.24, 2.4, Vector3.ZERO, cg, 8)
			ball(b, 0.2, Vector3(0, 2.4, 0), Vector3.ONE, cg, 8, 4)
			rod(b, 0.14, 0.14, 0.7, Vector3(-0.15, 1.2, 0), cg, 7, Basis(Vector3(0, 0, 1), PI / 2.0))
			rod(b, 0.13, 0.13, 0.8, Vector3(-0.85, 1.2, 0), cg, 7)
			ball(b, 0.13, Vector3(-0.85, 2.0, 0), Vector3.ONE, cg, 6, 3)
			rod(b, 0.12, 0.12, 0.5, Vector3(0.15, 0.9, 0), cg, 7, Basis(Vector3(0, 0, 1), -PI / 2.0))
			rod(b, 0.11, 0.11, 0.6, Vector3(0.65, 0.9, 0), cg, 7)
			ball(b, 0.11, Vector3(0.65, 1.5, 0), Vector3.ONE, cg, 6, 3)
		9:   # desert bloom: a low grey-green bush with yellow flowers on stems
			ball(b, 0.38, Vector3(0, 0.2, 0), Vector3(1, 0.55, 1), Color(0.45, 0.55, 0.36), 7, 4)
			var stems := [Vector3(0.12, 0.0, 0.05), Vector3(-0.15, 0.0, 0.0), Vector3(0.0, 0.0, -0.14)]
			var hs := [1.3, 1.0, 1.15]
			for i in 3:
				var s: Vector3 = stems[i]
				rod(b, 0.02, 0.03, float(hs[i]), s, Color(0.4, 0.5, 0.3), 4)
				ball(b, 0.14, s + Vector3(0, float(hs[i]) + 0.02, 0), Vector3(1, 0.5, 1), Color(0.98, 0.8, 0.12), 6, 3)
		10:  # moss cushion
			ball(b, 0.7, Vector3(0, 0.05, 0), Vector3(1, 0.3, 1), Color(0.22, 0.45, 0.2), 9, 4)
			for i in 5:
				var a := float(i) * 1.9
				ball(b, 0.22, Vector3(cos(a) * 0.35, 0.16, sin(a) * 0.35), Vector3(1, 0.5, 1), Color(0.34, 0.6, 0.26), 6, 3)
		11:  # purple saxifrage: a green cushion covered in tiny flowers
			ball(b, 0.45, Vector3(0, 0.04, 0), Vector3(1, 0.35, 1), Color(0.3, 0.42, 0.3), 8, 4)
			for i in 9:
				var a := float(i) * 2.4
				var rr := 0.05 + 0.3 * fmod(float(i) * 0.37, 1.0)
				ball(b, 0.08, Vector3(cos(a) * rr, 0.17, sin(a) * rr), Vector3(1, 0.6, 1), Color(0.7, 0.35, 0.85), 5, 3)
		12:  # fly agaric: red with white spots
			rod(b, 0.13, 0.17, 0.9, Vector3.ZERO, Color(0.95, 0.93, 0.85), 7)
			ball(b, 0.55, Vector3(0, 0.88, 0), Vector3(1, 0.65, 1), Color(0.85, 0.1, 0.08), 10, 6)
			for i in 8:
				var a := float(i) * 2.4
				var t := 0.3 + float(i % 3) * 0.28
				ball(b, 0.075, Vector3(0.55 * sin(t) * cos(a), 0.88 + 0.36 * cos(t), 0.55 * sin(t) * sin(a)), Vector3(1, 0.6, 1), Color(0.97, 0.96, 0.9), 5, 3)
		13:  # porcini: fat pale stem and a brown cap
			rod(b, 0.17, 0.24, 0.7, Vector3.ZERO, Color(0.9, 0.82, 0.65), 7)
			ball(b, 0.5, Vector3(0, 0.68, 0), Vector3(1, 0.55, 1), Color(0.5, 0.3, 0.15), 9, 5)
			ball(b, 0.46, Vector3(0, 0.6, 0), Vector3(1, 0.3, 1), Color(0.9, 0.85, 0.7), 8, 3)
		14:  # parasol: tall and thin with a pale cone cap
			rod(b, 0.05, 0.08, 1.7, Vector3.ZERO, Color(0.9, 0.85, 0.75), 6)
			rod(b, 0.04, 0.55, 0.45, Vector3(0, 1.45, 0), Color(0.85, 0.78, 0.65), 9)
			ball(b, 0.1, Vector3(0, 1.93, 0), Vector3(1, 0.8, 1), Color(0.5, 0.35, 0.25), 6, 3)
		15:  # a cluster of small brown mushrooms
			var data := [[0.0, 0.0, 0.9, 0.38], [0.45, 0.15, 0.6, 0.28], [-0.4, 0.25, 0.5, 0.24], [0.1, -0.45, 0.7, 0.3]]
			for i in data.size():
				var d: Array = data[i]
				var cap := Color(0.55, 0.35, 0.2) if i % 2 == 0 else Color(0.62, 0.42, 0.26)
				mushroom(b, Vector3(float(d[0]), 0.0, float(d[1])), float(d[2]), float(d[3]), Color(0.9, 0.85, 0.72), cap)
		16:  # chanterelle: orange funnels
			for p in [[0.0, 0.0, 1.0], [0.4, 0.2, 0.7]]:
				var s: float = p[2]
				var base := Vector3(float(p[0]), 0.0, float(p[1]))
				rod(b, 0.07 * s, 0.14 * s, 0.5 * s, base, Color(0.95, 0.6, 0.15), 6)
				rod(b, 0.5 * s, 0.1 * s, 0.35 * s, base + Vector3(0, 0.45 * s, 0), Color(0.98, 0.66, 0.12), 8)
		17:  # glow mushrooms
			var gdata := [[0.0, 0.0, 0.7, 0.34], [0.38, 0.1, 0.45, 0.22], [-0.3, 0.25, 0.35, 0.18]]
			for i in gdata.size():
				var d: Array = gdata[i]
				mushroom(b, Vector3(float(d[0]), 0.0, float(d[1])), float(d[2]), float(d[3]), Color(0.55, 0.9, 0.9), Color(0.2, 0.9, 0.82), 0.6)
		18:  # fern: a spray of long fronds
			for i in 9:
				var a := float(i) * TAU / 9.0 + 0.3
				var flen := 0.9 + 0.2 * float(i % 2)
				var c := Color(0.16, 0.5, 0.2) if i % 2 == 0 else Color(0.22, 0.58, 0.24)
				ball(b, 0.5, Vector3(cos(a) * flen * 0.45, 0.35 + 0.1 * float(i % 3), sin(a) * flen * 0.45), Vector3(flen, 0.07, 0.3), c, 6, 3, Basis(Vector3.UP, -a) * Basis(Vector3(0, 0, 1), 0.5))
		19:  # clover: low leaves with small flower heads
			for i in 6:
				var a := float(i) * 1.1
				var rr := 0.12 + 0.22 * float(i % 3)
				ball(b, 0.2, Vector3(cos(a) * rr, 0.08, sin(a) * rr), Vector3(1, 0.18, 1), Color(0.2, 0.55, 0.2), 6, 3)
			for i in 3:
				var a := float(i) * 2.1 + 0.4
				rod(b, 0.012, 0.015, 0.4, Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3), Color(0.25, 0.5, 0.2), 4)
				ball(b, 0.09, Vector3(cos(a) * 0.3, 0.42, sin(a) * 0.3), Vector3.ONE, Color(0.97, 0.9, 0.95) if i % 2 == 0 else Color(0.9, 0.55, 0.7), 5, 3)
		20:  # bush: a clump of leafy lobes with a few berries
			var lobes := [[0.0, 0.0, 0.8, 0.9], [0.65, 0.2, 0.55, 0.7], [-0.6, 0.15, 0.6, 0.75], [0.1, -0.6, 0.55, 0.65], [0.0, 0.1, 1.15, 0.6]]
			for i in lobes.size():
				var l: Array = lobes[i]
				var c := Color(0.14, 0.42, 0.16) if i % 2 == 0 else Color(0.2, 0.5, 0.2)
				ball(b, float(l[3]), Vector3(float(l[0]), float(l[2]) * 0.7, float(l[1])), Vector3(1, 0.85, 1), c, 8, 4)
			for i in 7:
				var a := float(i) * 2.4
				ball(b, 0.07, Vector3(cos(a) * 0.9, 0.5 + 0.12 * float(i % 3), sin(a) * 0.9), Vector3.ONE, Color(0.75, 0.1, 0.15) if i % 2 == 0 else Color(0.35, 0.1, 0.45), 5, 3)
		21:  # dry shrub: a low, grey-green sage bush
			for i in 6:
				var a := float(i) * 1.05
				var rr := 0.1 + 0.35 * float(i % 3) / 2.0
				ball(b, 0.38, Vector3(cos(a) * rr, 0.3 + 0.08 * float(i % 2), sin(a) * rr), Vector3(1, 0.8, 1), Color(0.46, 0.52, 0.36) if i % 2 == 0 else Color(0.55, 0.58, 0.4), 7, 3)
			for i in 4:
				var a := float(i) * 1.6
				rod(b, 0.012, 0.02, 0.5, Vector3(cos(a) * 0.3, 0.45, sin(a) * 0.3), Color(0.5, 0.4, 0.3), 4)
		22:  # dandelion puff
			rod(b, 0.025, 0.035, 1.4, Vector3.ZERO, green, 5)
			ball(b, 0.3, Vector3(0, 1.5, 0), Vector3.ONE, Color(0.96, 0.96, 0.92), 8, 5)
			ball(b, 0.14, Vector3(0, 1.5, 0), Vector3.ONE, Color(0.8, 0.8, 0.72), 5, 3)
			ball(b, 0.14, Vector3(0.3, 0.1, 0), Vector3(1, 0.3, 0.5), dark_green, 5, 3)
		23:  # fallen leaves lying flat
			var leaf_colors := [Color(0.72, 0.42, 0.12), Color(0.55, 0.3, 0.1), Color(0.8, 0.65, 0.15), Color(0.62, 0.2, 0.1), Color(0.45, 0.4, 0.12)]
			for i in 6:
				var a := float(i) * 2.1
				var rr := 0.15 + 0.5 * fmod(float(i) * 0.41, 1.0)
				ball(b, 0.3, Vector3(cos(a) * rr, 0.03 + 0.01 * float(i), sin(a) * rr), Vector3(1.0, 0.06, 0.55), leaf_colors[i % 5], 6, 3, Basis(Vector3.UP, a * 1.7))
		24:  # twigs lying on the ground
			for i in 4:
				var a := float(i) * 0.9 + 0.2
				var tw := Basis(Vector3.UP, a) * Basis(Vector3(0, 0, 1), PI / 2.0)
				var tlen := 0.9 + 0.4 * float(i % 3)
				rod(b, 0.035, 0.045, tlen, Vector3(cos(a) * 0.1, 0.05, sin(a) * 0.1) + tw.y * tlen * -0.5, Color(0.36, 0.24, 0.14) if i % 2 == 0 else Color(0.3, 0.2, 0.12), 4, tw)
		25:  # acorn with its cap
			ball(b, 0.2, Vector3(0, 0.18, 0), Vector3(0.9, 1.2, 0.9), Color(0.62, 0.42, 0.2), 7, 4)
			ball(b, 0.2, Vector3(0, 0.36, 0), Vector3(1.05, 0.6, 1.05), Color(0.36, 0.22, 0.12), 7, 3)
			rod(b, 0.012, 0.03, 0.1, Vector3(0, 0.42, 0), Color(0.3, 0.2, 0.1), 4)
		26:  # snow tussock: a clump of pale grass blades
			for i in 11:
				var a := float(i) * 2.4
				var rr := 0.12 + 0.08 * float(i % 3)
				var tilt := Basis(Vector3.UP, a) * Basis(Vector3(0, 0, 1), -0.35 - 0.1 * float(i % 4))
				rod(b, 0.0, 0.05, 1.0 + 0.2 * float(i % 3), Vector3(cos(a) * rr, 0, sin(a) * rr), Color(0.72, 0.7, 0.42) if i % 2 == 0 else Color(0.82, 0.8, 0.55), 4, tilt)
		27:  # hedge bush: a big, dense, dark green shrub with lighter new growth
			var hl := [[0.0, 0.0, 1.0, 1.3], [0.95, 0.3, 0.8, 1.05], [-0.95, 0.2, 0.85, 1.1], [0.2, -0.95, 0.8, 1.0], [0.3, 0.9, 0.85, 1.0], [-0.5, -0.7, 0.75, 0.9], [0.1, 0.1, 1.55, 0.95]]
			for i in hl.size():
				var l: Array = hl[i]
				var c := Color(0.1, 0.34, 0.14) if i % 3 == 0 else (Color(0.14, 0.42, 0.17) if i % 3 == 1 else Color(0.18, 0.48, 0.2))
				ball(b, float(l[3]), Vector3(float(l[0]), float(l[2]), float(l[1])), Vector3(1, 0.8, 1), c, 8, 4)
			for i in 8:
				var a := float(i) * 2.2
				ball(b, 0.2, Vector3(cos(a) * 1.0, 1.6 + 0.15 * float(i % 3), sin(a) * 1.0), Vector3(1, 0.7, 1), Color(0.36, 0.62, 0.22), 5, 3)
	return b.build()

# ---------- Landmarks ----------
# Bigger, solid things to find and steer by. kind: 0 fallen log, 1 hollow stump, 2 bottle cap, 3 giant acorn.
# variant picks a colour (caps) or wood tone.

const LANDMARK_WEIGHTS := [
	[3.0, 0.0, 2.0, 0.5, 3.0, 1.5, 0.5],   # fallen log
	[3.0, 0.0, 2.0, 0.0, 1.0, 0.5, 0.2],   # hollow stump
	[1.0, 1.5, 1.0, 1.0, 1.0, 1.5, 1.5],   # bottle cap
	[2.0, 0.0, 1.5, 0.0, 0.0, 0.0, 0.0],   # giant acorn
]

static func pick_landmark(biome: int, roll: float) -> int:
	var total := 0.0
	for i in LANDMARK_WEIGHTS.size():
		total += float(LANDMARK_WEIGHTS[i][biome])
	if total <= 0.0:
		return -1
	var r := roll * total
	for i in LANDMARK_WEIGHTS.size():
		r -= float(LANDMARK_WEIGHTS[i][biome])
		if r <= 0.0 and float(LANDMARK_WEIGHTS[i][biome]) > 0.0:
			return i
	return 0

static func landmark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m

static func get_landmark_mesh(kind: int, variant: int) -> ArrayMesh:
	var key := 1000 + kind * 10 + variant
	if not meshes.has(key):
		meshes[key] = build_landmark(kind, variant)
	return meshes[key]

static func build_landmark(kind: int, variant: int) -> ArrayMesh:
	var b := Builder.new()
	match kind:
		0:   # fallen log, lying along X, about 7 long
			var bark := Color(0.4, 0.27, 0.17) if variant == 0 else Color(0.5, 0.4, 0.3)
			var lay := Basis(Vector3(0, 0, 1), PI / 2.0)
			rod(b, 0.85, 0.95, 7.0, Vector3(3.5, 0.9, 0), bark, 10, lay)
			rod(b, 0.82, 0.82, 0.08, Vector3(3.5, 0.9, 0), Color(0.72, 0.55, 0.34), 10, lay)
			rod(b, 0.4, 0.4, 0.1, Vector3(3.5, 0.9, 0), Color(0.58, 0.42, 0.25), 10, lay)
			rod(b, 0.9, 0.9, 0.05, Vector3(-3.5, 0.9, 0), bark.darkened(0.2), 10, lay)
			ball(b, 0.35, Vector3(0.5, 1.7, 0.1), Vector3(2.2, 0.35, 1.0), Color(0.24, 0.5, 0.2), 8, 4)
			ball(b, 0.3, Vector3(-1.8, 1.65, -0.1), Vector3(1.6, 0.35, 1.0), Color(0.3, 0.55, 0.22), 8, 4)
			ball(b, 0.3, Vector3(1.8, 0.95, 0.85), Vector3(0.9, 0.7, 0.45), Color(0.95, 0.6, 0.2), 6, 3, Basis(Vector3(0, 1, 0), 0.3))
			ball(b, 0.26, Vector3(-0.8, 0.9, -0.88), Vector3(0.9, 0.6, 0.45), Color(0.9, 0.5, 0.18), 6, 3, Basis(Vector3(0, 1, 0), 2.9))
			rod(b, 0.12, 0.2, 0.9, Vector3(-1.2, 1.3, 0), bark, 6, Basis(Vector3(1, 0, 0), 0.9))
		1:   # hollow stump
			var wood := Color(0.4, 0.27, 0.17) if variant == 0 else Color(0.5, 0.4, 0.3)
			rod(b, 0.95, 1.15, 1.7, Vector3.ZERO, wood, 10)
			rod(b, 0.9, 0.9, 0.06, Vector3(0, 1.7, 0), Color(0.75, 0.58, 0.36), 10)
			rod(b, 0.55, 0.55, 0.07, Vector3(0, 1.72, 0), Color(0.18, 0.12, 0.08), 10)
			for i in 4:
				var a := float(i) * 1.6 + 0.3
				ball(b, 0.4, Vector3(cos(a) * 1.05, 0.2, sin(a) * 1.05), Vector3(1.6, 0.6, 0.7), wood.darkened(0.1), 6, 3, Basis(Vector3.UP, -a))
			ball(b, 0.3, Vector3(0.5, 1.75, 0.6), Vector3(1.3, 0.4, 1.0), Color(0.24, 0.5, 0.2), 6, 3)
			mushroom(b, Vector3(-0.9, 1.2, 0.5), 0.35, 0.2, Color(0.9, 0.85, 0.7), Color(0.85, 0.2, 0.12))
		2:   # bottle cap, half buried
			var cols := [Color(0.78, 0.12, 0.1), Color(0.12, 0.35, 0.75), Color(0.15, 0.6, 0.25)]
			var c: Color = cols[variant % 3]
			rod(b, 1.5, 1.5, 0.55, Vector3.ZERO, c, 20)
			rod(b, 1.25, 1.25, 0.05, Vector3(0, 0.52, 0), c.darkened(0.25), 20)
			rod(b, 0.55, 0.55, 0.03, Vector3(0, 0.56, 0), Color(0.95, 0.93, 0.85), 14)
			for i in 14:
				var a := float(i) * TAU / 14.0
				ball(b, 0.1, Vector3(cos(a) * 1.5, 0.28, sin(a) * 1.5), Vector3(0.6, 2.4, 0.6), c.lightened(0.15), 4, 3)
		3:   # giant acorn
			ball(b, 1.0, Vector3(0, 1.2, 0), Vector3(1.0, 1.25, 1.0), Color(0.64, 0.44, 0.2), 10, 6)
			ball(b, 1.05, Vector3(0, 2.2, 0), Vector3(1.08, 0.65, 1.08), Color(0.36, 0.22, 0.12), 10, 5)
			rod(b, 0.08, 0.16, 0.5, Vector3(0, 2.6, 0), Color(0.3, 0.2, 0.1), 6)
			ball(b, 0.1, Vector3(0, 0.1, 0), Vector3(1.0, 0.8, 1.0), Color(0.3, 0.2, 0.1), 6, 3)
	return b.build()
