class_name Terrain
extends RefCounted

# How the ground, biomes, caves, termite mounds, lakes, rivers and underground pools are
# generated. Everything here is a pure function of the world seed. main.gd owns the streaming.

var m: Main
var world: World
var water: Water

func setup(main: Main) -> void:
	m = main
	world = main.world
	water = main.water

var noise := FastNoiseLite.new()
var temp_noise := FastNoiseLite.new()    # biomes: hot and cold
var moist_noise := FastNoiseLite.new()   # biomes: wet and dry
var ridge_noise := FastNoiseLite.new()   # shapes the rocky highlands
var open_noise := FastNoiseLite.new()    # where the forest opens up into plains
var patch_noise := FastNoiseLite.new()
var pocket_noise := FastNoiseLite.new()
var patch_noise2 := FastNoiseLite.new()
var soil_noise := FastNoiseLite.new()
var soil_noise2 := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()
var pockets := []   # water pockets: {pos, radii, rmin, level}
var rivers := []    # the river around the world, in short pieces
var pools := []     # surface pools: {x, z, radius, depth, rim, stock, ...}
var pool_cells := {}      # Vector2i -> pools in that square (made the first time it is looked at)
var pocket_cells := {}    # same for underground pockets
var mound_cells := {}     # same for termite mounds ({} when a square has none)
# A chunk that is solid all through, and so are all its neighbors, has no surface to draw. Most of
# the deep ground is like this, so it is never meshed. Digging into it clears the mark.
var solid_chunks := {}

# Just where a mound stands and how big it is, without its inside. The far view uses this to draw
# every mound out to the horizon. It follows gen_mound_cell's first rolls exactly, so they agree.
var mound_sites: Dictionary = {}


func setup_noise() -> void:
	noise.seed = 1234
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012       # wide, gentle hills (one rise every ~80 units)
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.25     # the second layer is faint, so no small bumps

	# Biomes: big slow patterns, so each biome is a large region, found by exploring.
	temp_noise.seed = 4001
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.frequency = Main.BIOME_FREQ
	temp_noise.fractal_octaves = 2      # Godot's default is 5, which made biomes patchy at every scale
	temp_noise.fractal_gain = 0.2
	moist_noise.seed = 4002
	moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moist_noise.frequency = Main.BIOME_FREQ
	moist_noise.fractal_octaves = 2
	moist_noise.fractal_gain = 0.2
	open_noise.seed = 4004
	open_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	open_noise.frequency = Main.BIOME_FREQ * 1.2
	open_noise.fractal_octaves = 2
	open_noise.fractal_gain = 0.2
	ridge_noise.seed = 4003
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.frequency = 0.03

	# Decides where the surface is grass, sand, or clay.
	patch_noise.seed = 77
	patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch_noise.frequency = 0.035

	# Decides where clay pockets hide underground.
	pocket_noise.seed = 5
	pocket_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pocket_noise.frequency = 0.12

	# Surface patches of gravel.
	patch_noise2.seed = 91
	patch_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch_noise2.frequency = 0.05

	# Random pockets of different earth underground: one big-scale, one smaller.
	cave_noise.seed = 404
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_noise.frequency = 0.045
	cave_noise.fractal_octaves = 3
	soil_noise.seed = 301
	soil_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	soil_noise.frequency = 0.07
	soil_noise.fractal_octaves = 2
	soil_noise2.seed = 302
	soil_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	soil_noise2.frequency = 0.15

# How much of each biome there is at a spot, as six numbers: desert, highlands, tundra,
# swamp, savanna, plains. Whatever is left over is forest. The start and the river zone are always
# forest-like.
func biome_weights(x: float, z: float) -> PackedFloat32Array:
	var t := temp_noise.get_noise_2d(x, z)
	var mnd := moist_noise.get_noise_2d(x, z)
	var desert := smoothstep(0.12, 0.3, t) * smoothstep(0.08, -0.08, mnd)
	var tundra := smoothstep(-0.12, -0.3, t)
	var swamp := smoothstep(0.3, 0.48, mnd) * (1.0 - desert) * (1.0 - tundra)
	var high := smoothstep(-0.18, -0.36, mnd) * (1.0 - desert) * (1.0 - tundra)
	var savanna := smoothstep(0.04, 0.16, t) * smoothstep(-0.02, 0.1, mnd) * (1.0 - smoothstep(0.3, 0.42, mnd)) * (1.0 - desert)
	# Plains open up out of the forest wherever nothing else claims the land.
	var plains := smoothstep(0.1, 0.28, open_noise.get_noise_2d(x, z)) * (1.0 - desert) * (1.0 - tundra) * (1.0 - swamp) * (1.0 - high) * (1.0 - savanna)
	var w := PackedFloat32Array([desert, high, tundra, swamp, savanna, plains])
	var total := 0.0
	for v in w:
		total += v
	var norm := 1.0
	if total > 1.0:
		norm = 1.0 / total
	norm *= smoothstep(320.0, 560.0, Vector2(x - 8.0, z - 8.0).length()) * smoothstep(4.0, 26.0, edge_dist(x, z))
	for i in w.size():
		w[i] *= norm
	return w

# Which biome a spot is in.
func biome_at(x: float, z: float) -> int:
	var w := biome_weights(x, z)
	var best := 0.0
	var which := -1
	for i in w.size():
		if w[i] > best:
			best = w[i]
			which = i
	if best < 0.5:
		return Main.FOREST
	return which + 1   # weights start at DESERT, which is 1

# The hills before pools are carved into them, shaped further by the biome.
func base_height(x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	var h := clampf(Main.SURFACE_BASE + n * absf(n) * 12.0, Main.SURFACE_BASE - 6.0, Main.SURFACE_BASE + 4.0)
	var w := biome_weights(x, z)
	if w[0] + w[1] + w[2] + w[3] + w[4] + w[5] <= 0.0:
		return h
	# Desert: rolling dunes.
	var dune := sin(x * 0.11 + 1.7 * sin(z * 0.06)) * cos(z * 0.08 + 1.3 * sin(x * 0.05))
	h += w[0] * (dune * 4.0 + 1.0)
	# Highlands: raised ridges with steep sides.
	var ridge := 1.0 - 2.0 * absf(ridge_noise.get_noise_2d(x, z))
	h += w[1] * 9.0 * smoothstep(0.0, 0.25, ridge)
	# Tundra: flatter ground. Swamp: low, flat and wet. Savanna: wide, gentle plains.
	h = lerpf(h, Main.SURFACE_BASE - 1.0, w[2] * 0.7)
	h = lerpf(h, Main.SURFACE_BASE - 4.5, w[3] * 0.85)
	h = lerpf(h, Main.SURFACE_BASE + 0.5, w[4] * 0.92)   # savanna: very flat, wide plains
	h = lerpf(h, Main.SURFACE_BASE + 1.0 + n * 3.0, w[5] * 0.85)   # plains: soft, rolling, open ground
	return h

# How far inside the world's edge a spot is. 0 at the very edge.
func edge_dist(x: float, z: float) -> float:
	return float(Main.HALF) - maxf(absf(x), absf(z))

# The real ground height. Around each pool the ground is flattened to a level rim,
# then a shallow bowl is pressed into the middle of it.
func ground_height(x: float, z: float) -> float:
	var h := base_height(x, z)
	for p in pools_at(x, z):
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		var d := pool_dist(p, x, z)
		if d > r * 1.9:
			continue
		var flat := 1.0 - smoothstep(r, r * 1.9, d)
		h = lerpf(h, float(p["rim"]), flat)
		h -= float(p["depth"]) * (1.0 - smoothstep(r * 0.3, r, d))

	# The river runs all the way around the edge, with a high wall of ground on its far side.
	var e := edge_dist(x, z)
	if e < Main.RIVER_WIDTH + 8.0:
		var channel := 1.0 - smoothstep(5.0, 10.0, absf(e - Main.RIVER_CENTER))
		h = lerpf(h, Main.RIVER_BED_Y, channel)
		h += 14.0 * (1.0 - smoothstep(0.0, 4.0, e))
	return h

# What the very top layer of ground is made of at this spot.
func surface_kind(x: float, z: float) -> int:
	var e := edge_dist(x, z)
	if e < Main.RIVER_WIDTH - 1.0:
		return Blocks.MUD    # riverbed
	if e < Main.RIVER_WIDTH + 6.0:
		return Blocks.SAND   # banks
	for p in pools_at(x, z):
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		var d := pool_dist(p, x, z)
		if p.get("lake", false):
			if d < r * 0.8:
				return Blocks.MUD     # the lake bed
			if d < r * 0.87:
				return Blocks.SAND    # a thin beach, then grass and bushes
			continue
		if d < r * 1.1:
			return Blocks.MUD
		if d < r * 1.5:
			return Blocks.SAND
	match biome_at(x, z):
		Main.DESERT:
			return Blocks.GRAVEL if patch_noise2.get_noise_2d(x, z) > 0.5 else Blocks.SAND
		Main.HIGHLANDS:
			return Blocks.GRAVEL if patch_noise2.get_noise_2d(x, z) > 0.1 else Blocks.STONE
		Main.TUNDRA:
			return Blocks.GRAVEL if patch_noise2.get_noise_2d(x, z) > 0.55 else Blocks.SNOW
		Main.SWAMP:
			return Blocks.GRASS if patch_noise.get_noise_2d(x, z) > 0.0 else Blocks.MUD
		Main.SAVANNA:
			return Blocks.CLAY if patch_noise2.get_noise_2d(x, z) > 0.45 else Blocks.DRY_GRASS
		Main.PLAINS:
			return Blocks.GRASS   # fresh, green and unbroken
	var n := patch_noise.get_noise_2d(x, z)
	if n > 0.32:
		return Blocks.SAND
	if n < -0.38:
		return Blocks.CLAY
	if patch_noise2.get_noise_2d(x, z) > 0.55:
		return Blocks.GRAVEL
	return Blocks.GRASS

# Ground height and surface kind for every spot in one column, worked out once.
func gen_column_cache(col: Vector2i) -> Dictionary:
	var size := Chunk.SIZE
	var hs := PackedFloat32Array()
	var ks := PackedInt32Array()
	hs.resize(size * size)
	ks.resize(size * size)
	var top := -1000.0
	var low := 1000.0
	for lx in size:
		for lz in size:
			var x := col.x * size + lx
			var z := col.y * size + lz
			var gh := ground_height(x, z)
			hs[lx * size + lz] = gh
			ks[lx * size + lz] = surface_kind(x, z)
			top = maxf(top, gh)
			low = minf(low, gh)
	return {"h": hs, "k": ks, "max": top, "min": low}

func shallow_layer(col: Vector2i, cache: Dictionary) -> int:
	var margin := Main.DEEP_SHALLOW
	var mx := (float(col.x) + 0.5) * Chunk.SIZE
	var mz := (float(col.y) + 0.5) * Chunk.SIZE
	var ms := mound_site(Vector2i(floori(mx / Main.MOUND_CELL), floori(mz / Main.MOUND_CELL)))
	if not ms.is_empty() and Vector2(mx - float(ms["x"]), mz - float(ms["z"])).length() < float(ms["R"]) + 60.0:
		margin = Main.DEEP_NEAR_MOUND
	return clampi(floori((float(cache["min"]) - margin) / Chunk.SIZE), Main.CY_MIN, Main.HEIGHT_CHUNKS - 1)

# Fills one chunk straight from the height function. Chunks that are all open
# air are never created, so the empty sky costs nothing.
func fill_chunk(cpos: Vector3i, cache: Dictionary) -> void:
	var size := Chunk.SIZE
	var origin := cpos * size
	var near := pockets_near_chunk(cpos)
	var mound := mounds_near_chunk(cpos)
	var cones: Array = mound.get("cones", [])
	var prims: Array = mound.get("prims", [])
	if cones.is_empty() and float(origin.y) - 1.0 > float(cache["max"]):
		return   # all open sky
	var dead_mound: bool = mound.get("dead", false)
	var chunk: Chunk = null
	var all_solid := true   # stays true while every voxel in this chunk is fully solid
	# The deep earth and the caves change slowly, so their noise is sampled once per 2x2x2 block of voxels, not once per voxel.
	var blk := size / 2
	var blk_have := PackedByteArray()
	var blk_a := PackedFloat32Array()
	var blk_b := PackedFloat32Array()
	var blk_p := PackedFloat32Array()
	var blk_c := PackedFloat32Array()
	blk_have.resize(blk * blk * blk)
	blk_a.resize(blk * blk * blk)
	blk_b.resize(blk * blk * blk)
	blk_p.resize(blk * blk * blk)
	blk_c.resize(blk * blk * blk)
	var hs: PackedFloat32Array = cache["h"]
	var ks: PackedInt32Array = cache["k"]
	for lx in size:
		for lz in size:
			var x := origin.x + lx
			var z := origin.z + lz
			var h := hs[lx * size + lz]
			var kind := ks[lx * size + lz]
			var under := kind if (kind != Blocks.GRASS and kind != Blocks.SNOW and kind != Blocks.DRY_GRASS) else Blocks.DIRT
			for ly in size:
				var y := origin.y + ly
				var depth := h - y
				var in_mound := false
				for cn in cones:
					var md := cone_depth(cn, x, y, z)
					if md > depth:
						depth = md
						in_mound = true
				if depth <= -1.0:
					all_solid = false
					continue   # open air; a new chunk already starts as air
				if chunk == null:
					chunk = world.get_or_create_chunk(cpos)
				var dens := clampf(depth, -1.0, 1.0)
				var mat := Blocks.AIR
				var bi := (lx >> 1) + (lz >> 1) * blk + (ly >> 1) * blk * blk
				if depth >= 12.0 and not in_mound and blk_have[bi] == 0:
					var sx := float(origin.x + (lx & ~1)) + 1.0
					var sy := float(origin.y + (ly & ~1)) + 1.0
					var sz := float(origin.z + (lz & ~1)) + 1.0
					blk_a[bi] = soil_noise.get_noise_3d(sx, sy, sz)
					blk_b[bi] = soil_noise2.get_noise_3d(sx, sy, sz)
					blk_p[bi] = pocket_noise.get_noise_3d(sx, sy, sz)
					blk_c[bi] = cave_noise.get_noise_3d(sx, sy * 1.6, sz)
					blk_have[bi] = 1
				if depth > 0.0:
					if in_mound:
						mat = Blocks.DEAD_MOUND if dead_mound else Blocks.MOUND
					elif depth >= 12.0:
						# Deep ground: the same rules as soil_at, from the block's noise.
						if depth < 30.0 and blk_p[bi] > 0.45:
							mat = Blocks.CLAY
						elif blk_b[bi] > 0.6:
							mat = Blocks.GRAVEL
						elif blk_a[bi] > 0.55:
							mat = Blocks.CHALK
						else:
							mat = Blocks.STONE
					else:
						mat = soil_at(x, y, z, depth, kind, under)

				# Water pockets: carve a cavity, and stain the earth around it dark and damp.
				var damp := false
				for p in near:
					var q: Vector3 = (Vector3(x, y, z) - p["pos"]) / p["radii"]
					var sdf: float = (q.length() - 1.0) * float(p["rmin"])
					if sdf < dens:
						dens = clampf(sdf, -1.0, 1.0)
					if sdf < 2.5:
						damp = true
				if damp and dens > 0.0:
					mat = Blocks.MUD

				# Caves: random pockets of air deep underground, wide and low, never open to the surface.
				if not in_mound and depth > 10.0 and y > World.BEDROCK_Y + 4:
					# Most of the ground is nowhere near a cave, which the block's rough value shows, so only look closely near one.
					if depth < 12.0 or blk_c[bi] > Main.CAVE_THRESHOLD - 0.25:
						var cave_n := cave_noise.get_noise_3d(float(x), float(y) * 1.6, float(z))
						if cave_n > Main.CAVE_THRESHOLD:
							dens = minf(dens, clampf((Main.CAVE_THRESHOLD - cave_n) * 14.0, -1.0, 1.0))

				# Termite tunnels and chambers: carved out, with chewed mound earth for walls.
				for pr in prims:
					var sdf2 := prim_sdf(pr, x, y, z)
					if sdf2 < dens:
						dens = clampf(sdf2, -1.0, 1.0)
					if sdf2 < 1.8 and dens > 0.0:
						mat = Blocks.DEAD_MOUND if dead_mound else Blocks.MOUND

				if dens < 1.0:
					all_solid = false
				var vi := lx + lz * size + ly * size * size   # straight into the chunk's arrays, no bounds checks
				chunk.density[vi] = dens
				chunk.material[vi] = mat
	if all_solid and chunk != null:
		solid_chunks[cpos] = true

func is_buried_solid(cpos: Vector3i) -> bool:
	if not solid_chunks.has(cpos):
		return false
	for oy in range(-1, 2):
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				var n := cpos + Vector3i(ox, oy, oz)
				if n.y < Main.CY_MIN:
					continue   # below the bottom of the world: nobody sees that side
				if not solid_chunks.has(n):
					return false
	return true

# ---------- Termite mounds ----------
# The world is split into big squares. Each may hold one mound, decided from the square's own
# number the first time anything looks there. A mound is a tall tapered tower of mound earth,
# hollowed out inside by tunnels and chambers, with the queen's cell deep underground.
# The shapes are worked out here as simple solids and hollows; fill_chunk builds them in.

func mound_at_cell(cell: Vector2i) -> Dictionary:
	if not mound_cells.has(cell):
		mound_cells[cell] = gen_mound_cell(cell)
	return mound_cells[cell]

func mound_near(x: float, z: float) -> Dictionary:
	return mound_at_cell(Vector2i(floori(x / Main.MOUND_CELL), floori(z / Main.MOUND_CELL)))

# Is this spot on or close to a mound? Used to keep trees, grass and so on off it.
func near_mound(x: float, z: float, margin: float) -> bool:
	var mnd := mound_near(x, z)
	if mnd.is_empty():
		return false
	return Vector2(x - float(mnd["x"]), z - float(mnd["z"])).length() < float(mnd["R"]) + margin + 6.0

# The mound whose shapes could touch this chunk (a mound always fits inside its own square).
func mounds_near_chunk(cpos: Vector3i) -> Dictionary:
	var mnd := mound_at_cell(Vector2i(floori(float(cpos.x * Chunk.SIZE) / Main.MOUND_CELL), floori(float(cpos.z * Chunk.SIZE) / Main.MOUND_CELL)))
	if mnd.is_empty():
		return {}
	var lo := Vector3(cpos * Chunk.SIZE)
	var hi := lo + Vector3.ONE * Chunk.SIZE
	var cones := []
	for cn in mnd["cones"]:
		if aabb_hits(cn["lo"], cn["hi"], lo, hi):
			cones.append(cn)
	var prims := []
	for pr in mnd["prims"]:
		if aabb_hits(pr["lo"], pr["hi"], lo, hi):
			prims.append(pr)
	if cones.is_empty() and prims.is_empty():
		return {}
	return {"cones": cones, "prims": prims, "dead": mnd["dead"]}

func aabb_hits(a_lo: Vector3, a_hi: Vector3, b_lo: Vector3, b_hi: Vector3) -> bool:
	return a_lo.x <= b_hi.x and a_hi.x >= b_lo.x and a_lo.y <= b_hi.y and a_hi.y >= b_lo.y and a_lo.z <= b_hi.z and a_hi.z >= b_lo.z

# How far inside a tapered tower this point is (negative outside, -2 for "not near").
func cone_depth(cn: Dictionary, x: float, y: float, z: float) -> float:
	var yr := y - float(cn["y0"])
	var hh := float(cn["H"])
	if yr < 0.0 or yr > hh:
		return -2.0
	var dx := x - float(cn["x"])
	var dz := z - float(cn["z"])
	var rr2 := dx * dx + dz * dz
	var rmax := float(cn["R"]) * 1.12
	if rr2 > rmax * rmax:
		return -2.0
	var t := 1.0 - yr / hh
	var rad := float(cn["R"]) * pow(t, 0.7) * (1.0 + 0.08 * sin(0.45 * x + 0.35 * z + yr * 0.12))
	return rad - sqrt(rr2)

# Distance to a hollow (negative inside it): an egg-shaped chamber or a round tunnel.
func prim_sdf(p: Dictionary, x: float, y: float, z: float) -> float:
	var c: Vector3 = p["c"]
	if int(p["t"]) == 0:
		var r: Vector3 = p["r"]
		var q := Vector3((x - c.x) / r.x, (y - c.y) / r.y, (z - c.z) / r.z)
		return (q.length() - 1.0) * float(p["rmin"])
	var b: Vector3 = p["b"]
	var pa := Vector3(x, y, z) - c
	var ba := b - c
	var h := clampf(pa.dot(ba) / float(p["len2"]), 0.0, 1.0)
	return (pa - ba * h).length() - float(p["rad"])

func make_chamber(c: Vector3, r: Vector3) -> Dictionary:
	var pad := 4.0
	return {"t": 0, "c": c, "r": r, "rmin": minf(r.x, minf(r.y, r.z)),
		"lo": c - r - Vector3.ONE * pad, "hi": c + r + Vector3.ONE * pad}

func make_tunnel(a: Vector3, b: Vector3, rad: float) -> Dictionary:
	var pad := rad + 3.0
	return {"t": 1, "c": a, "b": b, "rad": rad, "len2": maxf(a.distance_squared_to(b), 0.001),
		"lo": Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3.ONE * pad,
		"hi": Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3.ONE * pad}

func make_cone(x: float, z: float, y0: float, rad: float, height: float) -> Dictionary:
	return {"x": x, "z": z, "y0": y0, "R": rad, "H": height,
		"lo": Vector3(x - rad * 1.2, y0 - 1.0, z - rad * 1.2), "hi": Vector3(x + rad * 1.2, y0 + height + 1.0, z + rad * 1.2)}

func mound_site(cell: Vector2i) -> Dictionary:
	if mound_sites.has(cell):
		return mound_sites[cell]
	var site := {}
	var rng := cell_rng(cell, 9090)
	var great := cell == Main.GREAT_CELL
	var origin := Vector2(cell) * float(Main.MOUND_CELL)
	var x := origin.x + rng.randf_range(64.0, Main.MOUND_CELL - 64.0)
	var z := origin.y + rng.randf_range(64.0, Main.MOUND_CELL - 64.0)
	var chance := float(Main.MOUND_CHANCE[biome_at(x, z)]) * smoothstep(Main.MOUND_START_CLEAR, 400.0, Vector2(x, z).length())
	if rng.randf() <= chance or great:
		for t in (60 if great else 8):
			x = origin.x + rng.randf_range(64.0, Main.MOUND_CELL - 64.0)
			z = origin.y + rng.randf_range(64.0, Main.MOUND_CELL - 64.0)
			var rad := rng.randf_range(15.0, 25.0)
			if great:
				rad = 34.0
			if edge_dist(x, z) < 140.0:
				continue
			var wet := false
			for p in pools_at(x, z):
				if Vector2(x - float(p["x"]), z - float(p["z"])).length() < float(p["radius"]) * 1.5 + rad + 12.0:
					wet = true
			if wet:
				continue
			var gh := ground_height(x, z)
			if not great and (gh < 40.0 or gh > 54.0):
				continue
			var flat := true
			for off in [Vector2(rad, 0), Vector2(-rad, 0), Vector2(0, rad), Vector2(0, -rad)]:
				if absf(ground_height(x + off.x, z + off.y) - gh) > (9.0 if great else 4.0):
					flat = false
			if flat:
				var hh := minf(rng.randf_range(34.0, 52.0), 100.0 - gh)
				if great:
					hh = minf(68.0, 100.0 - gh)
				site = {"x": x, "z": z, "gh": gh, "R": rad, "H": hh}
				break
	if great and site.is_empty():
		var fx := origin.x + float(Main.MOUND_CELL) * 0.5
		var fz := origin.y + float(Main.MOUND_CELL) * 0.5
		var fgh := ground_height(fx, fz)
		site = {"x": fx, "z": fz, "gh": fgh, "R": 34.0, "H": minf(68.0, 100.0 - fgh)}
	mound_sites[cell] = site
	return site

# Every mound within reach of the far view, as {x, z, gh, R, H}.
func far_mounds(center: Vector2, radius: float) -> Array:
	var out := []
	var lo := Vector2i(floori((center.x - radius) / Main.MOUND_CELL), floori((center.y - radius) / Main.MOUND_CELL))
	var hi := Vector2i(floori((center.x + radius) / Main.MOUND_CELL), floori((center.y + radius) / Main.MOUND_CELL))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var st := mound_site(Vector2i(cx, cz))
			if not st.is_empty():
				out.append(st)
	return out

# The water level of a lake at this spot, or a huge negative number when it is not over a lake.
func far_lake_level(x: float, z: float) -> float:
	for p in pools_at(x, z):
		if p.get("lake", false) and pool_dist(p, x, z) < float(p["radius"]) * 0.8:
			return float(p["level0"])
	return -1.0e9

func gen_mound_cell(cell: Vector2i) -> Dictionary:
	var rng := cell_rng(cell, 9090)
	var great := cell == Main.GREAT_CELL   # the Great Mound: always there, bigger, and the final boss
	var origin := Vector2(cell) * float(Main.MOUND_CELL)
	# One roll decides whether this square has a mound: unlikely near the start, likelier far out.
	var x := origin.x + rng.randf_range(64.0, Main.MOUND_CELL - 64.0)
	var z := origin.y + rng.randf_range(64.0, Main.MOUND_CELL - 64.0)
	var chance := float(Main.MOUND_CHANCE[biome_at(x, z)]) * smoothstep(Main.MOUND_START_CLEAR, 400.0, Vector2(x, z).length())
	if rng.randf() > chance and not great:
		return {}
	var rad := 0.0
	var gh := 0.0
	var found := false
	for t in (60 if great else 8):
		x = origin.x + rng.randf_range(64.0, Main.MOUND_CELL - 64.0)
		z = origin.y + rng.randf_range(64.0, Main.MOUND_CELL - 64.0)
		rad = rng.randf_range(15.0, 25.0)
		if great:
			rad = 34.0
		if edge_dist(x, z) < 140.0:
			continue
		var wet := false
		for p in pools_at(x, z):
			if Vector2(x - float(p["x"]), z - float(p["z"])).length() < float(p["radius"]) * 1.5 + rad + 12.0:
				wet = true
		if wet:
			continue
		gh = ground_height(x, z)
		if not great and (gh < 40.0 or gh > 54.0):
			continue
		var flat := true
		for off in [Vector2(rad, 0), Vector2(-rad, 0), Vector2(0, rad), Vector2(0, -rad)]:
			if absf(ground_height(x + off.x, z + off.y) - gh) > (9.0 if great else 4.0):
				flat = false
		if flat:
			found = true
			break
	if not found and great:
		x = origin.x + float(Main.MOUND_CELL) * 0.5
		z = origin.y + float(Main.MOUND_CELL) * 0.5
		rad = 34.0
		gh = ground_height(x, z)
		found = true
	if not found:
		return {}

	var height := minf(rng.randf_range(34.0, 52.0), 100.0 - gh)
	if great:
		height = minf(68.0, 100.0 - gh)
	var y0 := gh - 8.0   # the base is buried, so the mound grows out of the ground
	var cones := [make_cone(x, z, y0, rad, height)]
	for i in rng.randi_range(2, 5):   # a few smaller spires leaning against the main tower
		var a := rng.randf() * TAU
		cones.append(make_cone(x + cos(a) * rad * rng.randf_range(0.5, 0.75), z + sin(a) * rad * rng.randf_range(0.5, 0.75), y0,
				rad * rng.randf_range(0.3, 0.5), height * rng.randf_range(0.4, 0.75)))

	# The layout inside. Every mound is different: how deep it goes, how far it spreads, how many
	# rooms it has, and how they join. Rooms sit on several levels. They are linked by winding
	# tunnels, with side loops and dead ends. The queen's cell is on the deepest level, far from
	# the entrance, and reached only through a guarded antechamber.
	var levels := rng.randi_range(5, 6)
	var ly := []
	for i in levels:
		ly.append(gh + 2.5 - i * 6.5)
	var spread := rng.randf_range(30.0, 44.0)
	var a0 := rng.randf() * TAU
	var dir0 := Vector2(cos(a0), sin(a0))
	var eo2 := Vector2(x, z) + dir0 * (rad + 4.0)
	var ei2 := Vector2(x, z) + dir0 * (rad * 0.45)
	var eo := Vector3(eo2.x, ground_height(eo2.x, eo2.y) + 1.5, eo2.y)
	var ei := Vector3(ei2.x, gh + 1.5, ei2.y)

	var chambers := []   # each: {"c", "r", "lvl", "role"}
	var edges := []      # pairs of chamber indexes joined by a tunnel
	var prims := []
	var hall_r := Vector3(rng.randf_range(5.5, 7.5), 4.5, rng.randf_range(5.5, 7.5))
	chambers.append({"c": Vector3(x, ly[0], z), "r": hall_r, "lvl": 0, "role": "hall"})
	prims.append(make_tunnel(eo, ei, 2.4))                                     # the door
	prims.append(make_tunnel(ei, Vector3(x, ly[0], z), 2.2))
	prims.append(make_chamber(chambers[0]["c"], hall_r))

	# The royal cell: deepest level, far to one side. Placed first so nothing crowds it.
	var aq := rng.randf() * TAU
	var royal_r := Vector3(8.5, 4.2, 7.0)
	var qc := Vector3(x + cos(aq) * spread * rng.randf_range(0.8, 1.0), ly[levels - 1], z + sin(aq) * spread * rng.randf_range(0.8, 1.0))
	chambers.append({"c": qc, "r": royal_r, "lvl": levels - 1, "role": "royal"})
	var royal_i := 1
	prims.append(make_chamber(qc, royal_r))

	# Its antechamber, where the guards wait.
	var ante_i := -1
	var to_center := (Vector3(x, qc.y, z) - qc).normalized()
	for t in 16:
		var rot := to_center.rotated(Vector3.UP, rng.randf_range(-1.4, 1.4))
		var ap := qc + rot * 17.0
		var ar := Vector3(4.4, 3.0, 4.4)
		if mound_place(chambers, ap, ar, 3.0):
			chambers.append({"c": ap, "r": ar, "lvl": levels - 1, "role": "antechamber"})
			ante_i = chambers.size() - 1
			prims.append(make_chamber(ap, ar))
			break
	if ante_i < 0:   # very unlikely: put it straight toward the center
		var ap2 := qc + to_center * 17.0
		chambers.append({"c": ap2, "r": Vector3(4.4, 3.0, 4.4), "lvl": levels - 1, "role": "antechamber"})
		ante_i = chambers.size() - 1
		prims.append(make_chamber(ap2, Vector3(4.4, 3.0, 4.4)))

	# Rooms inside the tower itself, around the great hall.
	var galleries := rng.randi_range(3, 4)
	for i in galleries:
		for t in 20:
			var ga := rng.randf() * TAU
			var gd := rad * rng.randf_range(0.3, 0.45)
			var gr := Vector3(rng.randf_range(3.2, 4.4), 3.0, rng.randf_range(3.2, 4.4))
			var gp := Vector3(x + cos(ga) * gd, ly[0] + rng.randf_range(-0.5, 2.0), z + sin(ga) * gd)
			if mound_place(chambers, gp, gr, 2.0):
				chambers.append({"c": gp, "r": gr, "lvl": 0, "role": "larder" if i == 0 else "sleep"})
				prims.append(make_chamber(gp, gr))
				break
	# Rooms on the lower levels.
	var roles := ["nursery", "sleep", "fungus", "store", "empty", "nursery"]
	for lvl in range(1, levels):
		for i in rng.randi_range(3, 5):
			for t in 30:
				var ra := rng.randf() * TAU
				var rd := rng.randf_range(8.0, spread)
				var rr := Vector3(rng.randf_range(3.2, 5.2), rng.randf_range(2.6, 3.4), rng.randf_range(3.2, 5.2))
				var rp := Vector3(x + cos(ra) * rd, ly[lvl] + rng.randf_range(-1.0, 1.0), z + sin(ra) * rd)
				if mound_place(chambers, rp, rr, 3.0):
					chambers.append({"c": rp, "r": rr, "lvl": lvl, "role": roles[rng.randi() % roles.size()]})
					prims.append(make_chamber(rp, rr))
					break

	# Join them: each room links to the nearest room already joined, on its own level or next to it.
	var avoid_c := qc
	var avoid_r := royal_r * 1.25
	var joined := [0]
	var order := []
	for i in chambers.size():
		if i != 0 and i != royal_i:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ca: Dictionary = chambers[a]
		var cb: Dictionary = chambers[b]
		if int(ca["lvl"]) != int(cb["lvl"]):
			return int(ca["lvl"]) < int(cb["lvl"])
		return Vector2((ca["c"] as Vector3).x - x, (ca["c"] as Vector3).z - z).length() < Vector2((cb["c"] as Vector3).x - x, (cb["c"] as Vector3).z - z).length())
	for i in order:
		var ci: Dictionary = chambers[i]
		# Nearest joined room, strongly preferring the same or the next level, so the way down is a chain.
		var cands := joined.duplicate()
		cands.sort_custom(func(a: int, b: int) -> bool:
			var pa := (chambers[a]["c"] as Vector3).distance_to(ci["c"]) + 40.0 * maxf(0.0, absf(float(chambers[a]["lvl"]) - float(ci["lvl"])) - 1.0)
			var pb := (chambers[b]["c"] as Vector3).distance_to(ci["c"]) + 40.0 * maxf(0.0, absf(float(chambers[b]["lvl"]) - float(ci["lvl"])) - 1.0)
			return pa < pb)
		var best := -1
		var best_pts := []
		for j in cands:
			var pts := mound_path(chambers[j]["c"], ci["c"], rng)
			if i == ante_i or mound_path_clear(pts, avoid_c, avoid_r):
				best = j
				best_pts = pts
				break
		if best < 0:
			best = cands[0]
			best_pts = mound_path(chambers[best]["c"], ci["c"], rng)
		mound_add_path(prims, best_pts, rng.randf_range(1.7, 2.1))
		edges.append([best, i])
		joined.append(i)
	# The only way into the royal cell is from its antechamber.
	mound_add_path(prims, mound_path(chambers[ante_i]["c"], qc, rng), 2.1)
	edges.append([ante_i, royal_i])

	# A few extra loops, so there is more than one way around.
	for t in 6:
		var i2 := rng.randi_range(0, chambers.size() - 1)
		var j2 := rng.randi_range(0, chambers.size() - 1)
		if i2 == j2 or i2 == royal_i or j2 == royal_i:
			continue
		if absi(int(chambers[i2]["lvl"]) - int(chambers[j2]["lvl"])) > 1:
			continue
		if (chambers[i2]["c"] as Vector3).distance_to(chambers[j2]["c"]) > 26.0:
			continue
		var pts2 := mound_path(chambers[i2]["c"], chambers[j2]["c"], rng)
		if mound_path_clear(pts2, avoid_c, avoid_r):
			mound_add_path(prims, pts2, 1.6)
			edges.append([i2, j2])

	# Dead ends: tunnels that wander off and stop, some with a little room at the end.
	for t in rng.randi_range(4, 8):
		var di := rng.randi_range(0, chambers.size() - 1)
		if di == royal_i or di == ante_i:
			continue
		var dc: Vector3 = chambers[di]["c"]
		var da := rng.randf() * TAU
		var dl := rng.randf_range(7.0, 14.0)
		var de := dc + Vector3(cos(da) * dl, rng.randf_range(-2.0, 1.5), sin(da) * dl)
		if Vector2(de.x - x, de.z - z).length() > spread + 6.0:
			continue
		var dpts := mound_path(dc, de, rng)
		if not mound_path_clear(dpts, avoid_c, avoid_r):
			continue
		mound_add_path(prims, dpts, 1.4)
		if rng.randf() < 0.6:
			var er := Vector3(rng.randf_range(2.2, 3.2), 2.2, rng.randf_range(2.2, 3.2))
			if mound_place(chambers, de, er, 1.5):
				chambers.append({"c": de, "r": er, "lvl": int(chambers[di]["lvl"]), "role": "empty"})
				prims.append(make_chamber(de, er))

	# Chimneys: air shafts rising through the tower.
	for i in rng.randi_range(1, 3):
		var ca := rng.randf() * TAU
		var cx2 := x + cos(ca) * rad * 0.22
		var cz2 := z + sin(ca) * rad * 0.22
		prims.append(make_tunnel(Vector3(x, ly[0], z), Vector3(cx2, ly[0] + 3.0, cz2), 1.5))
		prims.append(make_tunnel(Vector3(cx2, ly[0] + 3.0, cz2), Vector3(cx2, gh + height * rng.randf_range(0.5, 0.72), cz2), 1.5))

	# Pick out the rooms the colony uses.
	var hall: Vector3 = chambers[0]["c"]
	var larder := hall
	var sleepers := []
	var nurseries := []
	var posts := [ei, mound_floor(chambers[0])]
	for i in chambers.size():
		var chm: Dictionary = chambers[i]
		match String(chm["role"]):
			"larder":
				larder = chm["c"]
			"sleep":
				sleepers.append(chm["c"])
			"nursery":
				nurseries.append(chm["c"])
	posts.append(mound_floor(chambers[ante_i]))
	posts.append(Vector3(qc.x + 4.5, qc.y - 3.9, qc.z))
	posts.append(Vector3(qc.x - 4.5, qc.y - 3.9, qc.z + 2.0))
	for k in 3:   # guards in random rooms on the way down
		if chambers.size() > 4:
			posts.append(mound_floor(chambers[rng.randi_range(2, chambers.size() - 1)]))

	# Sealed rooms: no tunnel leads to them. You only find one by digging into it. They hold the
	# colony's spare nurseries and fungus gardens, and nothing walks there.
	for i in rng.randi_range(3, 5):
		for t in 40:
			var sa := rng.randf() * TAU
			var sd := rng.randf_range(6.0, spread)
			var sl := rng.randi_range(1, levels - 1)
			var sr := Vector3(rng.randf_range(3.0, 4.6), rng.randf_range(2.4, 3.2), rng.randf_range(3.0, 4.6))
			var sp := Vector3(x + cos(sa) * sd, ly[sl] + rng.randf_range(-1.0, 1.0), z + sin(sa) * sd)
			if not mound_place(chambers, sp, sr, 3.0):
				continue
			var open := false
			for pr in prims:
				if prim_sdf(pr, sp.x, sp.y, sp.z) < maxf(sr.x, sr.z) + 1.5:
					open = true
					break
			if open:
				continue
			var rq := Vector3((sp.x - qc.x) / (royal_r.x * 2.2), (sp.y - qc.y) / (royal_r.y * 2.2), (sp.z - qc.z) / (royal_r.z * 2.2))
			if rq.length() < 1.0:
				continue
			chambers.append({"c": sp, "r": sr, "lvl": sl, "role": "sealed"})
			prims.append(make_chamber(sp, sr))
			break

	return {
		"kind": "mound", "great": great, "x": x, "z": z, "gh": gh, "R": rad, "H": height, "royal_r": royal_r,
		"center": Vector3(x, gh, z), "cones": cones, "prims": prims,
		"alive": true, "dead": false, "alerted": false,
		"stock": {"sugar": 0, "pebble": 0, "fiber": 0},
		"workers": 0, "soldiers": 0, "alarm_until": 0.0,
		"entrance_out": eo, "entrance_in": ei, "hall": hall, "larder": larder,
		"queen_pos": Vector3(qc.x, qc.y - 3.9, qc.z), "royal": qc,
		"nurseries": nurseries, "sleepers": sleepers, "posts": posts,
	}

# True when a new room at c with radii r fits without touching the rooms already there.
func mound_place(chambers: Array, c: Vector3, r: Vector3, gap: float) -> bool:
	for o in chambers:
		var oc: Vector3 = o["c"]
		var orr: Vector3 = o["r"]
		var dxz := Vector2(c.x - oc.x, c.z - oc.z).length()
		var reach := maxf(r.x, r.z) + maxf(orr.x, orr.z) + gap
		if dxz < reach and absf(c.y - oc.y) < r.y + orr.y + 2.0:
			return false
	return true

# A winding route between two points: a few waypoints pushed sideways, so tunnels curve.
func mound_path(a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> Array:
	var pts := [a]
	var dist := a.distance_to(b)
	var n := clampi(int(dist / 8.0), 2, 5)
	var d := b - a
	var side := Vector3(-d.z, 0.0, d.x).normalized()
	for i in range(1, n):
		var t := float(i) / float(n)
		var p := a.lerp(b, t) + side * rng.randf_range(-0.22, 0.22) * dist
		p.y += rng.randf_range(-1.2, 1.2)
		pts.append(p)
	pts.append(b)
	return pts

# True when no part of the route runs through the protected ellipsoid (the royal cell's surroundings).
func mound_path_clear(pts: Array, c: Vector3, r: Vector3) -> bool:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		for k in 7:
			var p := a.lerp(b, float(k) / 6.0)
			var q := Vector3((p.x - c.x) / r.x, (p.y - c.y) / r.y, (p.z - c.z) / r.z)
			if q.length() < 1.0:
				return false
	return true

func mound_add_path(prims: Array, pts: Array, rad: float) -> void:
	for i in pts.size() - 1:
		prims.append(make_tunnel(pts[i], pts[i + 1], rad))

# Where something standing in a room stands: just above its floor.
func mound_floor(chm: Dictionary) -> Vector3:
	var c: Vector3 = chm["c"]
	var r: Vector3 = chm["r"]
	return Vector3(c.x, c.y - r.y + 1.2, c.z)

# What the earth is made of at one point. Mostly layered, with random pockets
# of other kinds, so no stretch of ground is the same all the way through.
func soil_at(x: float, y: float, z: float, depth: float, kind: int, under: int) -> int:
	if depth < 1.5:
		return kind

	var a := soil_noise.get_noise_3d(x, y, z)    # big patches
	var b := soil_noise2.get_noise_3d(x, y, z)   # smaller patches

	# Subsoil: the usual soil with pockets of clay, gravel, sand, and dark loam.
	if depth < 12.0:
		if a > 0.45:
			return Blocks.CLAY
		if b > 0.5:
			return Blocks.GRAVEL
		if b < -0.55:
			return Blocks.SAND
		if a < -0.6:
			return Blocks.MUD
		return under

	# Deep ground: stone, with pockets of clay, gravel, and chalk.
	if depth < 30.0 and pocket_noise.get_noise_3d(x, y, z) > 0.45:
		return Blocks.CLAY
	if b > 0.6:
		return Blocks.GRAVEL
	if a > 0.55:
		return Blocks.CHALK
	return Blocks.STONE

# ---------- Surface pools ----------
# The world is split into big squares. Each square may hold one pool, decided from the square's
# own number the first time anything looks there, so the same pool is always in the same place.

func cell_rng(cell: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, salt))
	return rng

# How far out a lake reaches in a direction, as a share of its radius (0.68 to 1.0). Each lake has
# its own mix of lobes, so no two share a shape.
func lake_reach(p: Dictionary, angle: float) -> float:
	var w: PackedFloat32Array = p["wob"]
	var h := 0.0
	for k in 6:
		h += w[k * 2] * cos(float(k + 1) * (angle - w[k * 2 + 1]))
	return 0.35 + 0.65 * clampf((h - w[12]) / maxf(w[13] - w[12], 0.001), 0.0, 1.0)

# A random lake outline: six waves of different counts, stretched so the lake's shortest reach is
# 35% of its radius and its longest is 100%. That gives bays, fingers and peninsulas.
func make_lake_wobble(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	for k in 6:
		w.append(rng.randf_range(0.4, 1.0) / (1.0 + 0.35 * float(k)))
		w.append(rng.randf_range(0.0, TAU))
	var lo := 1e9
	var hi := -1e9
	for i in 90:
		var a := TAU * float(i) / 90.0
		var h := 0.0
		for k in 6:
			h += w[k * 2] * cos(float(k + 1) * (a - w[k * 2 + 1]))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	w.append(lo)
	w.append(hi)
	return w

# Distance from a pool's middle, stretched so a lake's odd outline counts as a circle of its radius.
func pool_dist(p: Dictionary, x: float, z: float) -> float:
	var dx := x - float(p["x"])
	var dz := z - float(p["z"])
	var d := sqrt(dx * dx + dz * dz)
	if not p.get("lake", false):
		return d
	return d / lake_reach(p, atan2(dz, dx))

func lake_outline(p: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		var rr := float(p["radius"]) * lake_reach(p, a)
		pts.append(Vector2(float(p["x"]) + cos(a) * rr, float(p["z"]) + sin(a) * rr))
	return pts

func pools_at(x: float, z: float) -> Array:
	var cell := Vector2i(floori(x / Main.POOL_CELL), floori(z / Main.POOL_CELL))
	if not pool_cells.has(cell):
		gen_pool_cell(cell)
	return pool_cells[cell]

# A big, deep forest lake with grassy banks. The square holding the start always gets one, a short walk away.
# It has to sit well inside its square, because ground_height() only looks at the square's own water.
func try_lake(cell: Vector2i, origin: Vector2, list: Array) -> bool:
	var rng := cell_rng(cell, 4242)
	var is_start := cell == Vector2i(0, 0)
	if not is_start and rng.randf() > Main.LAKE_CHANCE:
		return false
	for t in 10:
		var radius := rng.randf_range(50.0, 60.0)
		var margin := radius * 1.9 + 4.0
		if margin > Main.POOL_CELL * 0.5 - 6.0:
			radius = (Main.POOL_CELL * 0.5 - 10.0 - 4.0) / 1.9
			margin = radius * 1.9 + 4.0
		var x := origin.x + rng.randf_range(margin, Main.POOL_CELL - margin)
		var z := origin.y + rng.randf_range(margin, Main.POOL_CELL - margin)
		if edge_dist(x, z) < Main.RIVER_WIDTH + radius * 1.9 + 10.0:
			continue
		if Vector2(x, z).distance_to(Main.STORAGE_XZ) < radius * 1.5 + 60.0:
			continue
		var wb := biome_weights(x, z)
		var wet_total := wb[0] + wb[1] + wb[2] + wb[3] + wb[4]
		if wet_total > 0.5 and not (is_start and t >= 6):
			continue   # lakes belong in the forest (the start square falls back to any biome after a few tries)
		var depth := rng.randf_range(7.0, 9.5)
		var rim := base_height(x, z)
		var bound := radius * 1.12 + 2.0   # the water never reaches past the radius, and the ground around it has to be loaded to draw it
		var p := {
			"kind": "pool", "lake": true, "x": x, "z": z, "radius": radius, "depth": depth, "rim": rim,
			"wob": make_lake_wobble(rng),
			"stock": radius * radius * 10.0, "stock_max": radius * radius * 10.0,
			"floor": rim - depth,
			"level0": rim - 0.25 * depth,
			"bound": Vector2(bound, bound), "seed": Vector2(x, z),
			"built": false, "dirty": false,
		}
		list.append(p)
		water.unbuilt_water.append(p)
		return true
	return false

func gen_pool_cell(cell: Vector2i) -> void:
	var list := []
	pool_cells[cell] = list
	var rng := cell_rng(cell, 777)
	var origin := Vector2(cell) * float(Main.POOL_CELL)
	if try_lake(cell, origin, list):
		return
	if rng.randf() > Main.POOL_CHANCE:
		return
	for t in 8:
		var x := origin.x + rng.randf_range(30.0, Main.POOL_CELL - 30.0)   # always well inside its square
		var z := origin.y + rng.randf_range(30.0, Main.POOL_CELL - 30.0)
		var radius := rng.randf_range(5.0, 8.0)
		var depth := rng.randf_range(5.0, 7.5)   # deep enough to dive in
		if edge_dist(x, z) < Main.RIVER_WIDTH + 30.0:
			continue
		if Vector2(x, z).distance_to(Main.STORAGE_XZ) < radius + 14.0:
			continue
		var wb := biome_weights(x, z)
		if wb[1] > 0.05 or wb[0] > 0.3:
			continue   # no pools on rocky ridges or deep in the desert
		if wb[3] < 0.5 and wb[4] < 0.5 and wb[5] < 0.5 and rng.randf() > 0.3:
			continue   # pools are likelier in the swamp and the savanna
		if wb[4] >= 0.5:
			radius = rng.randf_range(10.0, 14.0)   # a savanna waterhole: wide and shallow
			depth = rng.randf_range(2.2, 3.0)
		var rim := base_height(x, z)
		var bound := radius * 1.5 + 2.0
		var p := {
			"kind": "pool", "x": x, "z": z, "radius": radius, "depth": depth, "rim": rim,
			"stock": radius * radius * 10.0, "stock_max": radius * radius * 10.0,
			"floor": rim - depth,                 # lowest point of the bowl
			"level0": rim - 0.25 * depth,         # water line when the pool is full
			"bound": Vector2(bound, bound), "seed": Vector2(x, z),
			"built": false, "dirty": false,       # drawn once the terrain around it exists
		}
		list.append(p)
		water.unbuilt_water.append(p)
		return

func near_pool(x: float, z: float, factor: float = 1.3) -> bool:
	for p in pools_at(x, z):
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		var f := factor
		if p.get("lake", false):
			f = 1.0 + (factor - 1.0) * 0.25   # a big lake only needs a thin margin kept clear, so its banks can be planted
		if pool_dist(p, x, z) < r * f:
			return true
	return false

# ---------- The river ----------
# A river runs around the whole world and is its boundary. It is built from short pieces,
# each a body of water like a pool, so each one is drawn only when the ground near it is.

func generate_river() -> void:
	var seg := 25   # cells along the river per piece. Odd, so each piece has a middle cell.
	var across := int(Main.RIVER_WIDTH / 2.0)   # half-width of a piece, in cells
	var c := int(Main.RIVER_CENTER)
	# North and south pieces run the full width. East and west skip the corners the others cover.
	var sides := [
		{"axis": "x", "lo": -Main.HALF, "hi": Main.HALF - 1, "pos": Main.HALF - c},
		{"axis": "x", "lo": -Main.HALF, "hi": Main.HALF - 1, "pos": -(Main.HALF - c)},
		{"axis": "z", "lo": -(Main.HALF - Main.RIVER_WIDTH) + 1, "hi": Main.HALF - Main.RIVER_WIDTH - 1, "pos": Main.HALF - c},
		{"axis": "z", "lo": -(Main.HALF - Main.RIVER_WIDTH) + 1, "hi": Main.HALF - Main.RIVER_WIDTH - 1, "pos": -(Main.HALF - c)},
	]
	for side in sides:
		var a: int = side["lo"]
		while a <= int(side["hi"]):
			var b: int = mini(a + seg - 1, int(side["hi"]))
			var mid := int((a + b) / 2.0)
			var half := int((b - a) / 2.0)
			var seed_v := Vector2(mid, side["pos"]) if side["axis"] == "x" else Vector2(side["pos"], mid)
			var bound := Vector2(half, across) if side["axis"] == "x" else Vector2(across, half)
			rivers.append({
				"seed": seed_v, "bound": bound,
				"kind": "river", "floor": Main.RIVER_BED_Y, "level0": Main.RIVER_LEVEL,
				"stock": 1.0e12, "stock_max": 1.0e12,   # a river never runs dry
				"built": false, "dirty": false,
			})
			water.unbuilt_rivers.append(rivers[rivers.size() - 1])
			a = b + 1

# ---------- Water pockets ----------

func pockets_at_cell(cell: Vector2i) -> Array:
	if not pocket_cells.has(cell):
		gen_pocket_cell(cell)
	return pocket_cells[cell]

# Pockets are sealed cavities underground that you find by digging. Each square makes its own.
func gen_pocket_cell(cell: Vector2i) -> void:
	var list := []
	pocket_cells[cell] = list
	var rng := cell_rng(cell, 2024)
	var origin := Vector2(cell) * float(Main.POCKET_CELL)
	for t in Main.POCKET_TRIES:
		var x := origin.x + rng.randf_range(11.0, Main.POCKET_CELL - 11.0)   # keeps each pocket inside its square
		var z := origin.y + rng.randf_range(11.0, Main.POCKET_CELL - 11.0)
		var radii := Vector3(
			rng.randf_range(3.0, 6.5), rng.randf_range(2.0, 3.5), rng.randf_range(3.0, 6.5))
		if edge_dist(x, z) < Main.HALF - Main.LAND + 8:
			continue
		var h := ground_height(x, z)
		var min_y := World.BEDROCK_Y + radii.y + 3.0
		var max_y := h - radii.y - Main.POCKET_MIN_DEPTH   # only deep down
		if max_y <= min_y:
			continue
		var y := rng.randf_range(min_y, max_y)
		var pos := Vector3(x, y, z)
		var clear := true
		for other in list:
			var other_pos: Vector3 = other["pos"]
			if other_pos.distance_to(pos) < 12.0:
				clear = false
				break
		if not clear:
			continue
		var p := {
			"kind": "pocket", "pos": pos, "radii": radii,
			"rmin": minf(radii.x, minf(radii.y, radii.z)),
			"level": y - radii.y * 0.2,   # water fills the lower part of the cavity
			"stock": radii.x * radii.z * 4.0,
			"stock_max": radii.x * radii.z * 4.0,
			"floor": y - radii.y, "level0": y - radii.y * 0.2,
			"bound": Vector2(radii.x + 2.0, radii.z + 2.0), "seed": Vector2(x, z),
			"built": false, "dirty": false,
		}
		list.append(p)
		water.unbuilt_water.append(p)

func pockets_near_chunk(cpos: Vector3i) -> Array:
	var cell := Vector2i(floori(float(cpos.x * Chunk.SIZE) / Main.POCKET_CELL), floori(float(cpos.z * Chunk.SIZE) / Main.POCKET_CELL))
	var lo := Vector3(cpos * Chunk.SIZE)
	var hi := lo + Vector3.ONE * Chunk.SIZE
	var margin := 4.0
	var result := []
	for p in pockets_at_cell(cell):
		var pos: Vector3 = p["pos"]
		var r: Vector3 = p["radii"]
		if pos.x + r.x + margin < lo.x or pos.x - r.x - margin > hi.x:
			continue
		if pos.y + r.y + margin < lo.y or pos.y - r.y - margin > hi.y:
			continue
		if pos.z + r.z + margin < lo.z or pos.z - r.z - margin > hi.z:
			continue
		result.append(p)
	return result
