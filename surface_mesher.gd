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
		Blocks.STONE: return Color(0.5, 0.5, 0.5)
		Blocks.DIRT: return Color(0.45, 0.3, 0.15)
		Blocks.GRASS: return Color(0.3, 0.65, 0.2)
	return Color(1, 0, 1)  # magenta = unknown material

static func _pidx(x: int, y: int, z: int) -> int:
	return (x + 1) + (z + 1) * PAD + (y + 1) * PAD * PAD

static func _cidx(c: Vector3i) -> int:
	return (c.x + 1) + (c.z + 1) * CS + (c.y + 1) * CS * CS

static func build(world: World, cpos: Vector3i) -> ArrayMesh:
	if world.get_chunk(cpos) == null:
		return null
	var origin := cpos * SIZE

	# 1. Copy samples into local arrays, including a 1-sample border from neighbors.
	var dens := PackedFloat32Array()
	var mats := PackedByteArray()
	dens.resize(PAD * PAD * PAD)
	mats.resize(PAD * PAD * PAD)
	for y in range(-1, SIZE + 1):
		for z in range(-1, SIZE + 1):
			for x in range(-1, SIZE + 1):
				var i := _pidx(x, y, z)
				dens[i] = world.get_density(origin.x + x, origin.y + y, origin.z + z)
				mats[i] = world.get_material(origin.x + x, origin.y + y, origin.z + z)

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
				colors.append(block_color(mat))

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
