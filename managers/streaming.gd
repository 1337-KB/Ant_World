class_name Streaming
extends RefCounted

# The world is much bigger than what exists at once. This is the part that keeps the right bit of it
# alive around the ant: generating terrain data in 16 x 16 columns near you, drawing a smaller ring
# of columns, building each chunk's mesh on worker threads, switching on collision only for ground
# you can touch, building scenery regions (grass, trees, rocks) as you near them, and forgetting
# far-away ground you never changed. Edits stay in memory, so dug ground is still dug when you return.
# main.gd calls stream_world(), process_remesh_queue() and preload_world(); everything that changes
# the ground calls mark_edited() and queue_remesh().

var m: Main

var chunk_nodes := {}
var col_data := {}       # Vector2i column -> true once all its chunks are generated
var col_meshed := {}     # Vector2i column -> true while it is drawn
var data_wanted: Array = []
var gen_job := {}
var stream_timer := 0.0
var region_nodes := {}   # Vector2i -> Node3D holding that square's grass, rocks and trees
var obstacles_by_region := {}   # region -> trees and boulders inside it
var region_queue: Array = []
var region_done := {}
var edited_cols := {}     # columns you have dug or filled. Their terrain is never forgotten.
var decor_sets := []
var remesh_queue: Array[Vector3i] = []   # chunks waiting to be rebuilt
var remesh_set := {}                    # the same chunks, for a quick 'is it already waiting' check
var remesh_focus := Vector3.ZERO        # the chunks nearest this point are rebuilt first

func setup(main: Main) -> void:
	m = main

# ---------- Terrain ----------

func generate_terrain() -> void:
	m.terrain.generate_river()
	# Pools and pockets are made per square as the ant gets near, and the terrain itself is
	# generated the same way. See the streaming section.

# The lowest chunk layer a column gets generated down to before you are near it.
var col_deep_from := {}   # column -> its lowest generated layer (CY_MIN once the deep ground is done too)
var deep_wanted: Array = []

# The deep ground of a column was just generated, so it and its neighbors are drawn again to include it.
func finish_deep(col: Vector2i) -> void:
	col_deep_from[col] = Main.CY_MIN
	m.content.spawn_cave_contents(col)
	var list: Array = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var n := col + Vector2i(dx, dz)
			if col_meshed.has(n):
				for cy in range(Main.CY_MIN, Main.HEIGHT_CHUNKS):
					if m.world.chunks.has(Vector3i(n.x, cy, n.y)):
						list.append(Vector3i(n.x, cy, n.y))
	if not list.is_empty():
		queue_remesh(list, remesh_focus)

# ---------- World streaming ----------
# The world is much bigger than what is built at once. Terrain data is generated in
# 16 x 16 columns near the ant, a smaller ring of columns is drawn, and columns left far
# behind are un-drawn. Edits stay in memory, so dug ground is still dug when you return.

func col_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / Chunk.SIZE), floori(pos.z / Chunk.SIZE))

func col_in_world(c: Vector2i) -> bool:
	var m := int(Main.HALF / float(Chunk.SIZE))
	return c.x >= -m and c.x < m and c.y >= -m and c.y < m

func region_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / Main.REGION_SIZE), floori(z / Main.REGION_SIZE))

func region_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key) * Main.REGION_SIZE, Vector2(Main.REGION_SIZE, Main.REGION_SIZE))

func region_node(key: Vector2i) -> Node3D:
	if not region_nodes.has(key):
		var n := Node3D.new()
		m.add_child(n)
		region_nodes[key] = n
	return region_nodes[key]

# Columns within a radius of a center column, nearest first.
func columns_around(center: Vector2i, radius: float) -> Array:
	var out := []
	var r := ceili(radius)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if Vector2(dx, dz).length() > radius:
				continue
			var c := center + Vector2i(dx, dz)
			if col_in_world(c):
				out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - center).length_squared() < Vector2(b - center).length_squared())
	return out

# True if this column and all its neighbors have terrain data, so it can be drawn correctly.
func neighbors_have_data(c: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var n := c + Vector2i(dx, dz)
			if col_in_world(n) and not col_data.has(n):
				return false
	return true

# True once the ground at this spot is drawn and solid.
func ground_ready(pos: Vector3) -> bool:
	var c := col_of(pos)
	if not col_in_world(c):
		return true
	if not col_meshed.has(c):
		return false
	# Only the ground at your own height matters. Deep layers being redrawn far below you must not freeze you.
	var my_layer := floori(pos.y / Chunk.SIZE)
	for q in remesh_queue:
		if q.x == c.x and q.z == c.y and absi(q.y - my_layer) <= 1:
			return false
	for q in mesh_inflight:
		if q.x == c.x and q.z == c.y and absi(q.y - my_layer) <= 1:
			return false
	ensure_solid(c)
	return true

func on_column_data(col: Vector2i) -> void:
	col_data[col] = true
	try_queue_region(Vector2i(floori(col.x / 2.0), floori(col.y / 2.0)))

# A region (2 x 2 columns) gets its trees, grass and creatures once all its ground exists.
func try_queue_region(key: Vector2i) -> void:
	if region_done.has(key):
		return
	for dx in 2:
		for dz in 2:
			var c := Vector2i(key.x * 2 + dx, key.y * 2 + dz)
			if col_in_world(c) and not col_data.has(c):
				return
	region_done[key] = true
	region_queue.append(key)

func mark_edited(chunks: Array) -> void:
	for c in chunks:
		m.terrain.solid_chunks.erase(c)
		edited_cols[Vector2i(c.x, c.z)] = true
		m.save.note_edited(c)

# Generates terrain data a chunk at a time, within a time budget.
func gen_step(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	while true:
		if gen_job.is_empty():
			var found = null
			var deep := false
			while not deep_wanted.is_empty():   # ground right around you comes first
				var dc: Vector2i = deep_wanted.pop_front()
				if col_data.has(dc) and int(col_deep_from.get(dc, Main.CY_MIN)) > Main.CY_MIN:
					found = dc
					deep = true
					break
			if found == null:
				while not data_wanted.is_empty():
					var c: Vector2i = data_wanted.pop_front()
					if not col_data.has(c):
						found = c
						break
			if found == null:
				return
			var cache := m.terrain.gen_column_cache(found)
			if deep:
				gen_job = {"col": found, "cy": Main.CY_MIN, "end": int(col_deep_from[found]), "cache": cache, "deep": true}
			else:
				var first := m.terrain.shallow_layer(found, cache)
				col_deep_from[found] = first
				gen_job = {"col": found, "cy": first, "end": Main.HEIGHT_CHUNKS, "cache": cache, "deep": false}
		var col: Vector2i = gen_job["col"]
		var gen_cpos := Vector3i(col.x, gen_job["cy"], col.y)
		if not m.save.apply_saved_chunk(gen_cpos):   # your dug version of it, if you changed it
			m.terrain.fill_chunk(gen_cpos, gen_job["cache"])
		gen_job["cy"] += 1
		if gen_job["cy"] >= int(gen_job["end"]):
			var was_deep: bool = gen_job["deep"]
			gen_job = {}
			if was_deep:
				finish_deep(col)
			else:
				on_column_data(col)
		if (Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
			return

# Decides what to generate, draw and un-draw for an ant standing at this spot.
func stream_update(center: Vector3, data_r: float, mesh_r: float) -> void:
	var cc := col_of(center)

	data_wanted = []
	for c in columns_around(cc, data_r):
		if not col_data.has(c):
			data_wanted.append(c)
	# While you are moving, the ground ahead of you is generated before the ground beside and behind you.
	if m.ant != null:
		var heading := Vector2(m.ant.velocity.x, m.ant.velocity.z)
		if heading.length() > 1.0:
			heading = heading.normalized()
			data_wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var da := Vector2(a - cc)
				var db := Vector2(b - cc)
				return da.length() - 0.6 * da.dot(heading) < db.length() - 0.6 * db.dot(heading))
	deep_wanted = []
	for c in columns_around(cc, Main.DEEP_COLS):
		if col_data.has(c) and int(col_deep_from.get(c, Main.CY_MIN)) > Main.CY_MIN:
			deep_wanted.append(c)

	# Dug columns keep their data when you leave, so their regions need asking for again.
	for c in columns_around(cc, data_r):
		if col_data.has(c):
			try_queue_region(Vector2i(floori(c.x / 2.0), floori(c.y / 2.0)))

	for c in columns_around(cc, mesh_r):
		if col_meshed.has(c) or not neighbors_have_data(c):
			continue
		col_meshed[c] = true
		var chunks: Array = []
		for cy in range(Main.CY_MIN, Main.HEIGHT_CHUNKS):
			if m.world.chunks.has(Vector3i(c.x, cy, c.y)):
				chunks.append(Vector3i(c.x, cy, c.y))
		queue_remesh(chunks, center)

	# Un-draw columns left far behind. Their data stays.
	for c in col_meshed.keys():
		if Vector2(c - cc).length() > mesh_r + 1.5:
			col_meshed.erase(c)
			for cy in range(Main.CY_MIN, Main.HEIGHT_CHUNKS):
				var cpos := Vector3i(c.x, cy, c.y)
				if chunk_nodes.has(cpos):
					chunk_nodes[cpos].queue_free()
					chunk_nodes.erase(cpos)
				remesh_queue.erase(cpos)
				remesh_set.erase(cpos)

	update_collision(cc)

	# Grass, rocks, trees and creatures are shown over ground that is drawn, and run only fairly close to you.
	for key in region_nodes:
		var rn: Node3D = region_nodes[key]
		var shown := false
		var active := false
		var decor := false
		for dx in 2:
			for dz in 2:
				var rc := Vector2i(key.x * 2 + dx, key.y * 2 + dz)
				if col_meshed.has(rc):
					shown = true
				var rd := Vector2(rc - cc).length()
				if rd <= Main.ACTIVE_COLS:
					active = true
				if rd <= Main.GRASS_COLS:
					decor = true
		rn.visible = shown
		for ch in rn.get_children():
			if ch is MultiMeshInstance3D:
				ch.visible = decor
		rn.process_mode = Node.PROCESS_MODE_INHERIT if (shown and active) else Node.PROCESS_MODE_DISABLED

	evict_far(center, cc)

	m.water.stream(center)

# ---------- Forgetting what is far behind ----------
# Without this, memory would grow with every step. Far terrain, scenery and water drawings are
# thrown away and rebuilt identically if you come back. Ground you dug is never forgotten.

func evict_far(center: Vector3, cc: Vector2i) -> void:
	var done := 0
	for c in col_data.keys():
		if Vector2(c - cc).length() <= Main.EVICT_COLS or edited_cols.has(c) or col_meshed.has(c):
			continue
		col_data.erase(c)
		col_deep_from.erase(c)
		for cy in range(Main.CY_MIN, Main.HEIGHT_CHUNKS):
			m.world.chunks.erase(Vector3i(c.x, cy, c.y))
			m.terrain.solid_chunks.erase(Vector3i(c.x, cy, c.y))
		done += 1
		if done >= 8:
			break

	var far := (Main.EVICT_COLS + 1.0) * Chunk.SIZE
	var here := Vector2(center.x, center.z)
	done = 0
	for key in region_nodes.keys():
		var mid := (Vector2(key) + Vector2(0.5, 0.5)) * Main.REGION_SIZE
		if mid.distance_to(here) <= far:
			continue
		region_nodes[key].queue_free()
		region_nodes.erase(key)
		region_done.erase(key)
		obstacles_by_region.erase(key)
		var kept := []
		for d in decor_sets:
			var rect: Rect2 = d["rect"]
			if region_key(rect.position.x + 1.0, rect.position.y + 1.0) != key:
				kept.append(d)
		decor_sets = kept
		done += 1
		if done >= 4:
			break

	m.water.forget_far(here, far)

# What the ant's biome does to it, and a message on crossing into a new one.
# Blocking load of the area around the start, so the game opens on solid ground.
func preload_world(center: Vector3) -> void:
	stream_update(center, 7.0, 5.0)
	gen_step(1.0e9)
	stream_update(center, 7.0, 5.0)
	gen_step(1.0e9)   # the deep ground around the start, so nothing is left to build once the game opens
	stream_update(center, 7.0, 5.0)
	m.content.region_step(1.0e9)
	while not remesh_queue.is_empty():
		var first: Vector3i = remesh_queue.pop_front()
		remesh_set.erase(first)
		build_chunk_node(first)

func stream_world(delta: float) -> void:
	# The ant waits while the ground under it is still being built.
	var grounded := ground_ready(m.ant.global_position)
	if not grounded and m.ant.is_physics_processing():
		m.ant.velocity = Vector3.ZERO
	m.ant.set_physics_process(grounded)

	# Invisible walls at the edge of the world.
	var lim := float(Main.HALF) - 1.5
	var ap := m.ant.global_position
	if absf(ap.x) > lim or absf(ap.z) > lim:
		m.ant.global_position = Vector3(clampf(ap.x, -lim, lim), ap.y, clampf(ap.z, -lim, lim))

	gen_step(Main.GEN_BUDGET_MS)
	m.content.region_step(Main.REGION_BUDGET_MS)
	stream_timer -= delta
	if stream_timer <= 0.0:
		stream_timer = 0.3
		stream_update(m.ant.global_position, Main.DATA_RADIUS, Main.MESH_RADIUS)

# ---------- Chunks ----------

# Edited chunks are rebuilt a few per frame instead of all at once, so a dig or
# smooth never freezes the game. The chunks nearest the edit go first.
func queue_remesh(chunks: Array, point: Vector3) -> void:
	remesh_focus = point
	for c in chunks:
		if not remesh_set.has(c):
			remesh_set[c] = true
			remesh_queue.append(c)

# Chunk meshes are built on worker threads, a few at a time, so building them never stalls a frame.
# The main thread looks up each chunk's neighbors, hands them to a worker, and later picks up the
# finished mesh. Digging queues the chunk again, so a result that is already out of date is replaced.
const MAX_MESH_JOBS := 3
var mesh_mutex := Mutex.new()
var mesh_done: Array = []     # finished meshes, as [chunk, mesh]
var mesh_inflight := {}       # chunks a worker is building right now

func mesh_worker(cpos: Vector3i, near: Array) -> void:
	var mesh := SurfaceMesher.build_with(near, cpos)
	mesh_mutex.lock()
	mesh_done.append([cpos, mesh])
	mesh_mutex.unlock()

# Picks up finished meshes, then starts workers on the waiting chunk nearest the last edit or the ant.
func process_remesh_queue() -> void:
	mesh_mutex.lock()
	var done := mesh_done
	mesh_done = []
	mesh_mutex.unlock()
	for r in done:
		var cp: Vector3i = r[0]
		mesh_inflight.erase(cp)
		if col_meshed.has(Vector2i(cp.x, cp.z)):   # skip chunks whose column was unloaded meanwhile
			apply_chunk_mesh(cp, r[1])

	var started := 0
	while mesh_inflight.size() < MAX_MESH_JOBS and started < 6 and not remesh_queue.is_empty():
		var best := -1
		var best_d := INF
		for i in remesh_queue.size():
			var c: Vector3i = remesh_queue[i]
			if mesh_inflight.has(c):
				continue   # a worker has it; it goes again after that one finishes
			var d := (Vector3(c * Chunk.SIZE) + Vector3.ONE * (Chunk.SIZE * 0.5)).distance_squared_to(remesh_focus)
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			break
		var nxt: Vector3i = remesh_queue[best]
		remesh_queue.remove_at(best)
		remesh_set.erase(nxt)
		if not col_meshed.has(Vector2i(nxt.x, nxt.z)):
			continue
		if m.terrain.is_buried_solid(nxt) or m.world.get_chunk(nxt) == null:
			free_chunk_node(nxt)   # deep, solid and hidden: nothing to draw
			continue
		mesh_inflight[nxt] = true
		started += 1
		WorkerThreadPool.add_task(mesh_worker.bind(nxt, SurfaceMesher.neighbors_of(m.world, nxt)))

func free_chunk_node(cpos: Vector3i) -> void:
	if chunk_nodes.has(cpos):
		chunk_nodes[cpos].queue_free()
		chunk_nodes.erase(cpos)

# Builds a chunk's mesh right now on this thread. Only used while the game is opening.
func build_chunk_node(cpos: Vector3i) -> void:
	free_chunk_node(cpos)
	if m.terrain.is_buried_solid(cpos):
		return
	apply_chunk_mesh(cpos, SurfaceMesher.build(m.world, cpos))

func apply_chunk_mesh(cpos: Vector3i, mesh: ArrayMesh) -> void:
	free_chunk_node(cpos)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m.material
	mi.position = Vector3(cpos * Chunk.SIZE)
	m.add_child(mi)
	chunk_nodes[cpos] = mi
	# Ground near you is solid. Far ground is only a picture until you get close.
	if m.ant == null or chunk_dist(cpos, col_of(m.ant.global_position)) <= Main.COLLISION_COLS:
		attach_collision(mi)

func chunk_dist(cpos: Vector3i, cc: Vector2i) -> float:
	return Vector2(cpos.x - cc.x, cpos.z - cc.y).length()

func attach_collision(mi: MeshInstance3D) -> void:
	if mi.has_meta("solid"):
		return
	mi.set_meta("solid", true)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := (mi.mesh as ArrayMesh).create_trimesh_shape()
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	mi.add_child(body)

# Makes ground solid as you approach it, and drops the collision of ground you left behind.
func update_collision(cc: Vector2i) -> void:
	var added := 0
	for cpos in chunk_nodes:
		var mi: MeshInstance3D = chunk_nodes[cpos]
		var d := chunk_dist(cpos, cc)
		if d <= Main.COLLISION_COLS:
			if not mi.has_meta("solid") and added < 8:
				attach_collision(mi)
				added += 1
		elif d > Main.COLLISION_COLS + 2.0 and mi.has_meta("solid"):
			mi.remove_meta("solid")
			for ch in mi.get_children():
				ch.queue_free()

# The ground under something is only safe to stand on once it is solid.
func ensure_solid(c: Vector2i) -> void:
	for cy in range(Main.CY_MIN, Main.HEIGHT_CHUNKS):
		var cpos := Vector3i(c.x, cy, c.y)
		if chunk_nodes.has(cpos):
			attach_collision(chunk_nodes[cpos])

# The look of the ground: grain and bumps projected from all sides, and the fade into the distant land.
func setup_terrain_material() -> void:
	m.material.vertex_color_use_as_albedo = true
	m.material.roughness = 1.0
	# The detailed ground melts away into the distant land with a fine dither, so it never pops in.
	# (Max is smaller than min on purpose: fully solid up to max, fully gone at min.)
	m.material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.material.distance_fade_max_distance = Main.TERRAIN_FADE_START
	m.material.distance_fade_min_distance = Main.TERRAIN_FADE_END

	# Fine grain and bumps projected from all sides, so the ground isn't smooth plastic.
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.frequency = 0.08
	grain.fractal_octaves = 4

	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.7, 0.7, 0.7))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))

	var albedo_tex := NoiseTexture2D.new()
	albedo_tex.noise = grain
	albedo_tex.seamless = true
	albedo_tex.width = 256
	albedo_tex.height = 256
	albedo_tex.color_ramp = ramp

	var normal_tex := NoiseTexture2D.new()
	normal_tex.noise = grain
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 6.0
	normal_tex.width = 256
	normal_tex.height = 256

	m.material.albedo_texture = albedo_tex
	m.material.normal_enabled = true
	m.material.normal_texture = normal_tex
	m.material.uv1_triplanar = true
	m.material.uv1_world_triplanar = true
	m.material.uv1_scale = Vector3(0.4, 0.4, 0.4)
