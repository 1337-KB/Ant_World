class_name World
extends RefCounted

var chunks := {}

static func world_to_chunk(wx: int, wy: int, wz: int) -> Vector3i:
	return Vector3i(
		floori(float(wx) / Chunk.SIZE),
		floori(float(wy) / Chunk.SIZE),
		floori(float(wz) / Chunk.SIZE)
	)

static func world_to_local(wx: int, wy: int, wz: int) -> Vector3i:
	return Vector3i(
		posmod(wx, Chunk.SIZE),
		posmod(wy, Chunk.SIZE),
		posmod(wz, Chunk.SIZE)
	)

func get_chunk(cpos: Vector3i) -> Chunk:
	return chunks.get(cpos)

func get_or_create_chunk(cpos: Vector3i) -> Chunk:
	if not chunks.has(cpos):
		chunks[cpos] = Chunk.new()
	return chunks[cpos]

# Missing chunks count as air.
func get_density(wx: int, wy: int, wz: int) -> float:
	var chunk := get_chunk(world_to_chunk(wx, wy, wz))
	if chunk == null:
		return -1.0
	var l := world_to_local(wx, wy, wz)
	return chunk.get_density(l.x, l.y, l.z)

func get_material(wx: int, wy: int, wz: int) -> int:
	var chunk := get_chunk(world_to_chunk(wx, wy, wz))
	if chunk == null:
		return Blocks.AIR
	var l := world_to_local(wx, wy, wz)
	return chunk.get_material(l.x, l.y, l.z)

func set_voxel(wx: int, wy: int, wz: int, d: float, mat: int) -> void:
	var chunk := get_or_create_chunk(world_to_chunk(wx, wy, wz))
	var l := world_to_local(wx, wy, wz)
	chunk.set_voxel(l.x, l.y, l.z, d, mat)

# Carve a smooth spherical hole. Returns the chunks whose meshes need rebuilding.
func dig_sphere(center: Vector3, radius: float) -> Array[Vector3i]:
	var r := int(ceil(radius)) + 1
	var cx := int(floor(center.x))
	var cy := int(floor(center.y))
	var cz := int(floor(center.z))

	var changed := false
	var lo := Vector3i(1000000, 1000000, 1000000)
	var hi := Vector3i(-1000000, -1000000, -1000000)

	for x in range(cx - r, cx + r + 1):
		for y in range(cy - r, cy + r + 1):
			for z in range(cz - r, cz + r + 1):
				var dist := Vector3(x, y, z).distance_to(center)
				var old_d := get_density(x, y, z)
				# Subtracting a sphere = keep the smaller density.
				var new_d := maxf(minf(old_d, dist - radius), -1.0)
				if new_d < old_d:
					var chunk := get_or_create_chunk(world_to_chunk(x, y, z))
					var l := world_to_local(x, y, z)
					chunk.set_density(l.x, l.y, l.z, new_d)
					changed = true
					lo = Vector3i(mini(lo.x, x), mini(lo.y, y), mini(lo.z, z))
					hi = Vector3i(maxi(hi.x, x), maxi(hi.y, y), maxi(hi.z, z))

	var result: Array[Vector3i] = []
	if not changed:
		return result

	# A chunk's mesh reads one sample past its edges, so a changed sample can
	# affect chunks up to one sample away. Pad the changed area by 1.
	var cmin := world_to_chunk(lo.x - 1, lo.y - 1, lo.z - 1)
	var cmax := world_to_chunk(hi.x + 1, hi.y + 1, hi.z + 1)
	for ccx in range(cmin.x, cmax.x + 1):
		for ccy in range(cmin.y, cmax.y + 1):
			for ccz in range(cmin.z, cmax.z + 1):
				var cpos := Vector3i(ccx, ccy, ccz)
				if chunks.has(cpos):
					result.append(cpos)
	return result

# Density at any point, blended smoothly between the 8 surrounding samples.
func sample_density(p: Vector3) -> float:
	var x0 := floori(p.x)
	var y0 := floori(p.y)
	var z0 := floori(p.z)
	var fx := p.x - x0
	var fy := p.y - y0
	var fz := p.z - z0
	var d00 := lerpf(get_density(x0, y0, z0), get_density(x0 + 1, y0, z0), fx)
	var d10 := lerpf(get_density(x0, y0 + 1, z0), get_density(x0 + 1, y0 + 1, z0), fx)
	var d01 := lerpf(get_density(x0, y0, z0 + 1), get_density(x0 + 1, y0, z0 + 1), fx)
	var d11 := lerpf(get_density(x0, y0 + 1, z0 + 1), get_density(x0 + 1, y0 + 1, z0 + 1), fx)
	return lerpf(lerpf(d00, d10, fy), lerpf(d01, d11, fy), fz)

# March along a ray in small steps. Returns the first solid point, or null.
func raycast(origin: Vector3, dir: Vector3, max_dist: float, step: float = 0.1) -> Variant:
	var d := dir.normalized()
	var t := 0.0
	while t <= max_dist:
		var p := origin + d * t
		if sample_density(p) > 0.0:
			return p
		t += step
	return null
