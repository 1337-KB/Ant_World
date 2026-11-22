class_name SurfaceMesher
extends RefCounted

const SIZE := Chunk.SIZE
const PAD := SIZE + 2   # samples from -1 to SIZE, so we can read past the chunk edges
const CS := SIZE + 1    # cells from -1 to SIZE-1

# The 8 corners of a cell, as offsets from its minimum corner.
const CORNERS = [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
]
# The 12 edges of a cell, as pairs of corner indices.
const EDGES = [
	[0, 1], [2, 3], [4, 5], [6, 7],
	[0, 2], [1, 3], [4, 6], [5, 7],
	[0, 4], [1, 5], [2, 6], [3, 7],
]
const AXES = [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]

static func block_color(id: int) -> Color:
	match id:
		Blocks.STONE: return Color(0.48, 0.47, 0.45)
		Blocks.DIRT: return Color(0.40, 0.27, 0.15)
		Blocks.GRASS: return Color(0.22, 0.68, 0.12)
		Blocks.CLAY: return Color(0.62, 0.38, 0.25)
		Blocks.SAND: return Color(0.80, 0.72, 0.48)
		Blocks.MUD: return Color(0.17, 0.12, 0.09)
		Blocks.GRAVEL: return Color(0.55, 0.52, 0.47)
		Blocks.CHALK: return Color(0.86, 0.85, 0.80)
		Blocks.SNOW: return Color(0.93, 0.96, 1.0)
		Blocks.DRY_GRASS: return Color(0.80, 0.66, 0.28)
		Blocks.MOUND: return Color(0.55, 0.34, 0.20)
		Blocks.DEAD_MOUND: return Color(0.50, 0.50, 0.52)
	return Color(1, 0, 1)  # magenta = unknown material

# Final color of one vertex: base material color, then slope, veins, staining,
# speckle, and depth. Uses world position so chunks match at their borders.
static func vertex_color(mat: int, wp: Vector3, normal: Vector3,
		vein_noise: FastNoiseLite, speck_noise: FastNoiseLite,
		blotch_noise: FastNoiseLite) -> Color:
	var base := block_color(mat)

	# Steep grass turns into bare dirt.
	if mat == Blocks.GRASS:
		var steep := 1.0 - smoothstep(0.45, 0.75, normal.y)
		base = base.lerp(block_color(Blocks.DIRT), steep)

	# Richer ground: patches and layers that differ by material, so no area is one flat colour.
	var mid := speck_noise.get_noise_3d(wp.x * 0.3, wp.y * 0.3, wp.z * 0.3)     # patches about 10 units wide
	var big := blotch_noise.get_noise_3d(wp.x * 2.2 + 40.0, wp.y * 2.2, wp.z * 2.2)   # a second, different pattern
	match mat:
		Blocks.GRASS:
			if mid > 0.0:
				base = base.lerp(Color(0.50, 0.62, 0.14), minf(mid * 1.3, 1.0) * 0.6)   # sun-bleached olive patches
			else:
				base = base.lerp(Color(0.08, 0.46, 0.16), minf(-mid * 1.3, 1.0) * 0.55)  # deep, damp green patches
			var bare := smoothstep(0.40, 0.60, big)
			base = base.lerp(Color(0.45, 0.31, 0.17), bare * 0.85)                      # worn bare soil
		Blocks.DRY_GRASS:
			base = base.lerp(Color(0.68, 0.46, 0.18), smoothstep(0.0, 0.5, mid) * 0.5)
			base = base.lerp(Color(0.90, 0.80, 0.40), smoothstep(0.0, 0.5, -mid) * 0.45)
		Blocks.DIRT, Blocks.CLAY:
			var band := sin(wp.y * 0.9 + big * 2.5) * 0.5 + 0.5                           # soil layers, easy to see in tunnels
			base = base.lerp(base.darkened(0.3), band * 0.4)
			base = base.lerp(Color(0.52, 0.38, 0.22), smoothstep(0.3, 0.7, mid) * 0.35)
		Blocks.SAND:
			var ripple := sin(wp.x * 0.7 + wp.z * 0.4 + big * 4.0) * 0.5 + 0.5
			base = base.lerp(Color(0.90, 0.82, 0.56), ripple * 0.5)
			base = base.lerp(Color(0.70, 0.60, 0.38), (1.0 - ripple) * 0.35)
		Blocks.STONE:
			var layers := sin(wp.y * 1.1 + vein_noise.get_noise_3d(wp.x, 0.0, wp.z) * 3.0) * 0.5 + 0.5
			base = base.lerp(Color(0.38, 0.38, 0.40), layers * 0.45)                     # rock strata
			base = base.lerp(Color(0.58, 0.52, 0.44), smoothstep(0.3, 0.7, big) * 0.35)
		Blocks.GRAVEL:
			base = base.lerp(Color(0.40, 0.38, 0.36), smoothstep(-0.2, 0.6, big) * 0.6)
			base = base.lerp(Color(0.68, 0.62, 0.52), smoothstep(0.0, 0.6, -mid) * 0.5)
		Blocks.SNOW:
			base = base.lerp(Color(0.78, 0.87, 0.98), smoothstep(0.1, 0.6, mid) * 0.7)   # cold blue hollows
		Blocks.MUD:
			base = base.lerp(Color(0.09, 0.07, 0.05), smoothstep(0.0, 0.5, big) * 0.7)   # wet dark spots
			base = base.lerp(Color(0.28, 0.20, 0.13), smoothstep(0.1, 0.6, -mid) * 0.5)

	# Thin, lighter veins running through stone.
	if mat == Blocks.STONE:
		var vein := 1.0 - smoothstep(0.0, 0.1, absf(vein_noise.get_noise_3d(wp.x, wp.y, wp.z)))
		base = base.lerp(Color(0.72, 0.68, 0.58), vein * 0.8)

	# Large soft patches: some areas stained warm (iron-rich), others cooler and greyer.
	var blotch := blotch_noise.get_noise_3d(wp.x, wp.y, wp.z)
	if blotch > 0.0:
		base = base.lerp(Color(0.60, 0.38, 0.20), blotch * 0.35)
	else:
		base = base.lerp(Color(0.42, 0.45, 0.48), -blotch * 0.3)

	# Fine speckle so no area is a flat color.
	var shade := 1.0 + speck_noise.get_noise_3d(wp.x, wp.y, wp.z) * 0.18 + blotch * 0.1

	# Deeper ground is darker.
	var depth := 0.55 + 0.45 * smoothstep(8.0, 44.0, wp.y)

	var k := shade * depth
	return Color(base.r * k, base.g * k, base.b * k)

static func _pidx(x: int, y: int, z: int) -> int:
	return (x + 1) + (z + 1) * PAD + (y + 1) * PAD * PAD

static func _cidx(c: Vector3i) -> int:
	return (c.x + 1) + (c.z + 1) * CS + (c.y + 1) * CS * CS

static func build(world: World, cpos: Vector3i) -> ArrayMesh:
	if world.get_chunk(cpos) == null:
		return null
	var origin := cpos * SIZE

	var vein_noise := FastNoiseLite.new()
	vein_noise.seed = 11
	vein_noise.frequency = 0.12
	var speck_noise := FastNoiseLite.new()
	speck_noise.seed = 23
	speck_noise.frequency = 0.35
	var blotch_noise := FastNoiseLite.new()
	blotch_noise.seed = 31
	blotch_noise.frequency = 0.05
	blotch_noise.fractal_octaves = 2

	# 1. Copy samples into local arrays, including a 1-sample border from neighbors.
	var dens := PackedFloat32Array()
	var mats := PackedByteArray()
	dens.resize(PAD * PAD * PAD)
	mats.resize(PAD * PAD * PAD)
	var any_solid := false
	var any_air := false
	# Fetch the 3x3x3 neighbor chunks once, then read samples straight from them.
	# (Asking the world for every sample was the slow part of remeshing.)
	var near: Array = []
	for oy in range(-1, 2):
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				near.append(world.get_chunk(cpos + Vector3i(ox, oy, oz)))
	for y in range(-1, SIZE + 1):
		var cy := 0 if y >= 0 and y < SIZE else (-1 if y < 0 else 1)
		var ly := y - cy * SIZE
		for z in range(-1, SIZE + 1):
			var cz := 0 if z >= 0 and z < SIZE else (-1 if z < 0 else 1)
			var lz := z - cz * SIZE
			for x in range(-1, SIZE + 1):
				var cx := 0 if x >= 0 and x < SIZE else (-1 if x < 0 else 1)
				var lx := x - cx * SIZE
				var i := _pidx(x, y, z)
				var ch = near[(cx + 1) + (cz + 1) * 3 + (cy + 1) * 9]
				var d := -1.0
				var m := Blocks.AIR
				if ch != null:
					d = ch.get_density(lx, ly, lz)
					m = ch.get_material(lx, ly, lz)
				dens[i] = d
				mats[i] = m
				if d > 0.0:
					any_solid = true
				else:
					any_air = true

	# All solid or all air means there is no surface here, so skip the meshing.
	if not (any_solid and any_air):
		return null

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# 2. One vertex for every cell that the surface passes through.
	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(CS * CS * CS)
	cell_vertex.fill(-1)
	var cd: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

	for cy in range(-1, SIZE):
		for cz in range(-1, SIZE):
			for cx in range(-1, SIZE):
				var solid_count := 0
				for i in 8:
					var c: Vector3i = CORNERS[i]
					var v := dens[_pidx(cx + c.x, cy + c.y, cz + c.z)]
					cd[i] = v
					if v > 0.0:
						solid_count += 1
				if solid_count == 0 or solid_count == 8:
					continue  # entirely air or entirely solid: no surface here

				# Average the points where the surface crosses the cell's edges.
				var sum := Vector3.ZERO
				var n := 0
				for e in EDGES:
					var ia: int = e[0]
					var ib: int = e[1]
					if (cd[ia] > 0.0) != (cd[ib] > 0.0):
						var t: float = cd[ia] / (cd[ia] - cd[ib])
						var ca: Vector3i = CORNERS[ia]
						var cb: Vector3i = CORNERS[ib]
						sum += Vector3(ca).lerp(Vector3(cb), t)
						n += 1
				var pos := Vector3(cx, cy, cz) + sum / n

				# Normal = direction the density decreases fastest (out of the solid).
				var g := Vector3(
					(cd[1] + cd[3] + cd[5] + cd[7]) - (cd[0] + cd[2] + cd[4] + cd[6]),
					(cd[2] + cd[3] + cd[6] + cd[7]) - (cd[0] + cd[1] + cd[4] + cd[5]),
					(cd[4] + cd[5] + cd[6] + cd[7]) - (cd[0] + cd[1] + cd[2] + cd[3])
				)
				var normal := Vector3.UP
				if g.length() > 0.0001:
					normal = (-g).normalized()

				# Material comes from the most solid corner.
				var best := -INF
				var mat := Blocks.STONE
				for i in 8:
					if cd[i] > best:
						best = cd[i]
						var c: Vector3i = CORNERS[i]
						mat = mats[_pidx(cx + c.x, cy + c.y, cz + c.z)]

				cell_vertex[_cidx(Vector3i(cx, cy, cz))] = verts.size()
				verts.append(pos)
				normals.append(normal)
				var wp := Vector3(origin) + pos
				colors.append(vertex_color(mat, wp, normal, vein_noise, speck_noise, blotch_noise))

	# 3. Connect vertices: each edge where density changes sign becomes one quad
	#    made from the 4 cells that share that edge.
	for y in SIZE:
		for z in SIZE:
			for x in SIZE:
				var solid_a := dens[_pidx(x, y, z)] > 0.0
				for axis in 3:
					var e: Vector3i = AXES[axis]
					var solid_b := dens[_pidx(x + e.x, y + e.y, z + e.z)] > 0.0
					if solid_a == solid_b:
						continue
					var eu: Vector3i = AXES[(axis + 1) % 3]
					var ev: Vector3i = AXES[(axis + 2) % 3]
					var p := Vector3i(x, y, z)
					var q0 := cell_vertex[_cidx(p - eu - ev)]
					var q1 := cell_vertex[_cidx(p - ev)]
					var q2 := cell_vertex[_cidx(p)]
					var q3 := cell_vertex[_cidx(p - eu)]
					# Flip the order so the face always points from solid to air.
					var o := [q0, q3, q2, q1] if solid_a else [q0, q1, q2, q3]
					indices.append_array([o[0], o[1], o[2], o[0], o[2], o[3]])

	if indices.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
