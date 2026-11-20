class_name World
extends RefCounted

# Nothing below this height can be dug or smoothed, so the world has a floor.
const BEDROCK_Y := 3

var chunks := {}
var last_removed := 0.0   # volume of ground removed by the latest dig

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

# Carve a smooth tube between two points. A sphere is a tube of length zero.
# Returns the chunks whose meshes need rebuilding.
func dig_capsule(a: Vector3, b: Vector3, radius: float) -> Array[Vector3i]:
	var pad := int(ceil(radius)) + 1
	var lo := Vector3i(
		floori(minf(a.x, b.x)) - pad, floori(minf(a.y, b.y)) - pad, floori(minf(a.z, b.z)) - pad)
	var hi := Vector3i(
		floori(maxf(a.x, b.x)) + pad, floori(maxf(a.y, b.y)) + pad, floori(maxf(a.z, b.z)) + pad)
	var ab := b - a
	var len2 := ab.length_squared()
	var changed := false
	last_removed = 0.0

	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if y < BEDROCK_Y:
					continue
				var p := Vector3(x, y, z)
				# Closest point on the segment a-b, then distance to it.
				var t := 0.0
				if len2 > 0.0001:
					t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var dist := p.distance_to(a + ab * t)
				var old_d := get_density(x, y, z)
				var new_d := maxf(minf(old_d, dist - radius), -1.0)
				if new_d < old_d:
					var chunk := get_or_create_chunk(world_to_chunk(x, y, z))
					var l := world_to_local(x, y, z)
					chunk.set_density(l.x, l.y, l.z, new_d)
					changed = true
					# Density -1..1 maps to how solid the sample is, 0..1.
					last_removed += clampf(old_d * 0.5 + 0.5, 0.0, 1.0) - clampf(new_d * 0.5 + 0.5, 0.0, 1.0)

	if not changed:
		var empty: Array[Vector3i] = []
		return empty
	return _chunks_touching(lo, hi)

func dig_sphere(center: Vector3, radius: float) -> Array[Vector3i]:
	return dig_capsule(center, center, radius)

# Blur the density field around a point. Rough surfaces get rounder.
func smooth_sphere(center: Vector3, radius: float, strength: float = 0.5) -> Array[Vector3i]:
	var pad := int(ceil(radius)) + 1
	var c := Vector3i(floori(center.x), floori(center.y), floori(center.z))
	var lo := c - Vector3i.ONE * pad
	var hi := c + Vector3i.ONE * pad

	# Read everything first, write after, so one voxel's new value
	# doesn't change the average used by its neighbor.
	var edits := {}
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if y < BEDROCK_Y:
					continue
				var falloff := 1.0 - Vector3(x, y, z).distance_to(center) / radius
				if falloff <= 0.0:
					continue
				var sum := 0.0
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						for dz in range(-1, 2):
							sum += get_density(x + dx, y + dy, z + dz)
				var avg := sum / 27.0
				var old_d := get_density(x, y, z)
				edits[Vector3i(x, y, z)] = lerpf(old_d, avg, strength * falloff)

	for pos in edits:
		var chunk := get_chunk(world_to_chunk(pos.x, pos.y, pos.z))
		if chunk == null:
			continue
		var l := world_to_local(pos.x, pos.y, pos.z)
		chunk.set_density(l.x, l.y, l.z, edits[pos])
	return _chunks_touching(lo, hi)

# Every existing chunk whose mesh could change when samples in lo..hi change.
# A mesh reads one sample past its edges, so pad by 1.
func _chunks_touching(lo: Vector3i, hi: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
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
