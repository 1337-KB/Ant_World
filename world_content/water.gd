class_name Water
extends Node3D

# Everything about water: the bodies of water, how they are drawn, drinking, and when they
# appear as the world streams. main.gd owns the world; this script asks it for what it needs.

var m: Main
var world: World
var water_mat: ShaderMaterial
var water_timer := 0.0
var water_source := {}          # the pool or pocket you are standing in, if any
var built_water: Array = []     # water bodies that have been drawn
var unbuilt_water: Array = []   # water bodies waiting for the ground around them to exist
var unbuilt_rivers: Array = []

func setup(main: Main) -> void:
	m = main
	world = main.world

const WATER_SHADER = """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// How much water lies between the surface and whatever is behind it.
	float d = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	v.xyz /= v.w;
	float thick = max(0.0, (-v.z) - (-VERTEX.z));
	float deep = 1.0 - exp(-thick * 0.55);

	// Gentle moving ripples in the surface.
	vec2 p = wpos.xz;
	float t = TIME;
	float dx = cos(p.x * 2.1 + t * 1.3) * 0.5 + cos((p.x + p.y) * 1.3 - t * 0.9) * 0.4;
	float dz = cos(p.y * 1.7 - t * 1.1) * 0.5 + cos((p.x - p.y) * 1.9 + t * 0.7) * 0.3;
	vec3 n_world = normalize(vec3(dx * 0.08, 1.0, dz * 0.08));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	// Shallow water is light and see-through. Deep water is dark and nearly opaque.
	vec3 shallow = vec3(0.32, 0.65, 0.80);
	vec3 deepc = vec3(0.02, 0.12, 0.26);
	ALBEDO = mix(mix(shallow, deepc, deep), vec3(0.5, 0.75, 0.9), fres * 0.5);
	ALPHA = clamp(mix(0.30, 0.96, deep) + fres * 0.15, 0.0, 0.97);
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
}
"""

# ---------- Water surfaces ----------
# Water is not a solid shape. Each body is a flat surface at its water line, drawn only
# over ground that is actually open air with ground underneath. So it follows the real
# shape of the pool or cavity, and if you dig out the floor, the water drains away there.

func add_water_body(p: Dictionary) -> void:
	if water_mat == null:
		var shader := Shader.new()
		shader.code = WATER_SHADER
		water_mat = ShaderMaterial.new()
		water_mat.shader = shader
	var body := MeshInstance3D.new()
	body.material_override = water_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	p["mesh"] = body
	p["dirty"] = false
	p["built"] = true
	unbuilt_water.erase(p)
	unbuilt_rivers.erase(p)
	built_water.append(p)
	rebuild_water(p)

# Open air at the water line, with ground below to hold the water.
func is_water_cell(x: int, z: int, level: float, support: int) -> bool:
	if world.sample_density(Vector3(x, level, z)) > 0.0:
		return false
	var y0 := floori(level)
	for k in range(1, support + 1):
		if world.get_density(x, y0 - k, z) > 0.0:
			return true
	return false

# True once the ground around a lake's whole bound has been generated.
func water_ground_ready(p: Dictionary) -> bool:
	var seed_v: Vector2 = p["seed"]
	var bound: Vector2 = p["bound"]
	var lo := m.stream.col_of(Vector3(seed_v.x - bound.x - 2.0, 0, seed_v.y - bound.y - 2.0))
	var hi := m.stream.col_of(Vector3(seed_v.x + bound.x + 2.0, 0, seed_v.y + bound.y + 2.0))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var cq := Vector2i(cx, cz)
			if m.stream.col_in_world(cq) and not m.stream.col_data.has(cq):
				return false
	return true

# A flat sheet of water drawn straight from the lake's shape, with no need for any ground data.
# It shows the moment the lake is in range, and is swapped for the exact water once the ground exists.
func quick_lake_mesh(p: Dictionary, level: float) -> ArrayMesh:
	var pts := m.terrain.lake_outline(p)
	var cx := float(p["x"])
	var cz := float(p["z"])
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3(cx, level, cz))
	norms.append(Vector3.UP)
	for q in pts:
		verts.append(Vector3(cx + (q.x - cx) * 0.9, level, cz + (q.y - cz) * 0.9))
		norms.append(Vector3.UP)
	var n := pts.size()
	for i in n:
		idx.append_array([0, 1 + (i + 1) % n, 1 + i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var out_mesh := ArrayMesh.new()
	out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out_mesh

func rebuild_water(p: Dictionary) -> void:
	p["dirty"] = false
	var body: MeshInstance3D = p["mesh"]
	var fill := float(p["stock"]) / float(p["stock_max"])
	var floor_y: float = p["floor"]
	var level := floor_y + (float(p["level0"]) - floor_y) * fill
	if fill < 0.03 or level - floor_y < 0.5:
		body.mesh = null
		p["cells"] = {}
		return

	if p.get("lake", false) and not water_ground_ready(p):
		body.mesh = quick_lake_mesh(p, level)
		p["cells"] = {}
		p["dirty"] = true
		return

	var bound: Vector2 = p["bound"]
	var seed_v: Vector2 = p["seed"]
	var cx := roundi(seed_v.x)
	var cz := roundi(seed_v.y)
	var bx := ceili(bound.x)
	var bz := ceili(bound.y)
	var support := ceili(level - floor_y + 1.5)

	# Start from the middle and spread outward over every connected wet cell.
	var queue: Array[Vector2i] = []
	var seen := {}
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c := Vector2i(cx + dx, cz + dz)
			seen[c] = true
			if is_water_cell(c.x, c.y, level, support):
				queue.append(c)
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		for d in steps:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			seen[n] = true
			if absi(n.x - cx) > bx or absi(n.y - cz) > bz:
				continue
			if is_water_cell(n.x, n.y, level, support):
				queue.append(n)

	if queue.is_empty():
		body.mesh = null    # the floor was dug out, or the ground is not loaded yet
		p["cells"] = {}
		p["dirty"] = true   # try again next tick, so the water appears as soon as the ground is ready
		return

	# Find the ground under every wet cell, so the water can be drawn as a solid body.
	var floors := {}
	var y0 := floori(level)
	for c in queue:
		var fl := floor_y
		for k in range(0, support + 2):
			var dd := world.get_density(c.x, y0 - k, c.y)
			if dd > 0.0:
				var d_up := world.get_density(c.x, y0 - k + 1, c.y)
				var t := dd / (dd - d_up) if dd != d_up else 0.0
				fl = float(y0 - k) + clampf(t, 0.0, 1.0)
				break
		floors[c] = minf(fl, level - 0.2)
	p["cells"] = floors
	p["level_now"] = level

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for c in queue:
		# The top surface.
		var b0 := verts.size()
		verts.append(Vector3(c.x - 0.5, level, c.y - 0.5))
		verts.append(Vector3(c.x + 0.5, level, c.y - 0.5))
		verts.append(Vector3(c.x + 0.5, level, c.y + 0.5))
		verts.append(Vector3(c.x - 0.5, level, c.y + 0.5))
		for k in 4:
			norms.append(Vector3.UP)
		idx.append_array([b0, b0 + 1, b0 + 2, b0, b0 + 2, b0 + 3])

		# A wall down to the ground wherever the water meets a solid bank. These show
		# in any cutaway, so the pool reads as a body of water and not a thin sheet.
		var f: float = floors[c]
		for dir in steps:
			var nb: Vector2i = c + dir
			if floors.has(nb):
				continue
			if world.sample_density(Vector3(nb.x, level, nb.y)) <= 0.0:
				continue
			var mid := Vector2(c) + Vector2(dir) * 0.5
			var perp := Vector2(dir.y, dir.x) * 0.5
			var p0 := mid - perp
			var p1 := mid + perp
			var w0 := verts.size()
			verts.append(Vector3(p0.x, f, p0.y))
			verts.append(Vector3(p1.x, f, p1.y))
			verts.append(Vector3(p1.x, level, p1.y))
			verts.append(Vector3(p0.x, level, p0.y))
			for k in 4:
				norms.append(Vector3(dir.x, 0, dir.y))
			idx.append_array([w0, w0 + 1, w0 + 2, w0, w0 + 2, w0 + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	body.mesh = mesh

func water_surface_at(pos: Vector3) -> float:
	var cell := Vector2i(roundi(pos.x), roundi(pos.z))
	for p in built_water:
		var seed_v: Vector2 = p["seed"]
		var bound: Vector2 = p["bound"]
		if absf(pos.x - seed_v.x) > bound.x + 2.0 or absf(pos.z - seed_v.y) > bound.y + 2.0:
			continue
		var cells: Dictionary = p.get("cells", {})
		if cells.is_empty() or not cells.has(cell):
			continue
		var level := float(p["level_now"])
		if pos.y < level and pos.y > float(cells[cell]) - 1.0:
			return level
	return -INF

func camera_underwater() -> bool:
	var pos := m.ant.camera.global_position
	var cell := Vector2i(roundi(pos.x), roundi(pos.z))
	for p in built_water:
		var seed_v: Vector2 = p["seed"]
		var bound: Vector2 = p["bound"]
		if absf(pos.x - seed_v.x) > bound.x + 2.0 or absf(pos.z - seed_v.y) > bound.y + 2.0:
			continue
		var cells: Dictionary = p.get("cells", {})
		if cells.is_empty() or not cells.has(cell):
			continue
		if pos.y < float(p["level_now"]) and pos.y > float(cells[cell]):
			return true
	return false

func mark_water_dirty(point: Vector3, radius: float) -> void:
	for p in built_water:
		var seed_v: Vector2 = p["seed"]
		var bound: Vector2 = p["bound"]
		if absf(point.x - seed_v.x) > bound.x + radius or absf(point.z - seed_v.y) > bound.y + radius:
			continue
		if point.y < float(p["floor"]) - radius - 3.0 or point.y > float(p["level0"]) + radius + 3.0:
			continue
		p["dirty"] = true

# Redraws flagged water a few times a second, not every frame.
func refresh_water(delta: float) -> void:
	water_timer -= delta
	if water_timer > 0.0:
		return
	water_timer = 0.25
	# Wait until the digging stops, so the dig itself stays smooth.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return
	# One water body per tick, so several never rebuild in the same frame.
	for p in built_water:
		if p["dirty"]:
			if p.get("lake", false) and not water_ground_ready(p):
				continue   # already showing its quick sheet; wait for the ground
			rebuild_water(p)
			return

# ---------- Drinking ----------

func find_water_source() -> Dictionary:
	var a := m.ant.global_position
	for p in built_water:
		if float(p["stock"]) <= 0.0:
			continue
		var seed_v: Vector2 = p["seed"]
		var bound: Vector2 = p["bound"]
		if absf(a.x - seed_v.x) > bound.x + 3.0 or absf(a.z - seed_v.y) > bound.y + 3.0:
			continue
		match p["kind"]:
			"pool":
				var d := m.terrain.pool_dist(p, a.x, a.z)
				var rim: float = p["rim"]
				if d < float(p["radius"]) * 0.7 + 1.5 and a.y < rim + 2.5 and a.y > rim - float(p["depth"]) - 2.0:
					return p
				if near_water_cell(p, a):
					return p   # standing on the bank, within reach of the water
			"pocket":
				var pos: Vector3 = p["pos"]
				var r: Vector3 = p["radii"]
				var q := Vector3((a.x - pos.x) / r.x, (a.y - pos.y) / r.y, (a.z - pos.z) / r.z)
				if q.length() < 1.25 and a.y < float(p["level"]) + 1.5:
					return p
			"river":
				if m.terrain.edge_dist(a.x, a.z) < Main.RIVER_WIDTH and a.y < Main.RIVER_LEVEL + 1.5 and a.y > Main.RIVER_BED_Y - 1.0:
					return p
	return {}

# True when the ant stands within a few units of a cell that really holds water, so you can drink from the bank.
func near_water_cell(p: Dictionary, a: Vector3) -> bool:
	var cells: Dictionary = p.get("cells", {})
	if cells.is_empty():
		return false
	var level := float(p["level_now"])
	if a.y > level + 2.5 or a.y < level - 6.0:
		return false
	var cx := roundi(a.x)
	var cz := roundi(a.z)
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			if cells.has(Vector2i(cx + dx, cz + dz)):
				return true
	return false

# Hold F at the water to fill your bar. The water gets lower as you drink.
func handle_water(delta: float) -> void:
	water_source = find_water_source()
	if water_source.is_empty():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or m.crafting.is_open or m.storage_ui.is_open or not Input.is_key_pressed(KEY_F):
		return
	if m.ant.water >= m.ant.water_cap() - 0.01:
		m.show_message("Your water bar is full.")
		return
	var amount := minf(Main.DRINK_RATE * delta, minf(m.ant.water_cap() - m.ant.water, float(water_source["stock"])))
	m.ant.water += amount
	water_source["stock"] = float(water_source["stock"]) - amount
	water_source["dirty"] = true
	if float(water_source["stock"]) <= 0.0:
		m.show_message("This water is all gone.")


# Called as the world streams. Lakes are drawn at once from their shape; rivers and pockets wait for the ground.
func stream(center: Vector3) -> void:
	var candidates: Array = unbuilt_water.duplicate()
	if m.terrain.edge_dist(center.x, center.z) < 300.0:
		candidates = unbuilt_water + unbuilt_rivers
	var water_built := 0
	for p in candidates:
		var seed_v: Vector2 = p["seed"]
		var bound: Vector2 = p["bound"]
		var is_lake: bool = p.get("lake", false)
		var reach := 420.0 if is_lake else 300.0
		if absf(seed_v.x - center.x) > reach or absf(seed_v.y - center.z) > reach:
			continue
		if is_lake:
			add_water_body(p)   # drawn at once from its shape, refined when the ground arrives
			continue
		if p.get("kind", "") == "pocket" and int(m.stream.col_deep_from.get(m.stream.col_of(Vector3(seed_v.x, 0, seed_v.y)), Main.CY_MIN)) > Main.CY_MIN:
			continue   # the deep ground around an underground pool is not generated yet
		if water_ground_ready(p):
			add_water_body(p)
			water_built += 1
			if water_built >= 2:
				break
	for p in built_water:
		(p["mesh"] as MeshInstance3D).visible = true   # show the water at once, even before the ground around it is drawn

# Drops the bodies that are far behind you. They come back when you return.
func forget_far(here: Vector2, far: float) -> void:
	var done := 0
	for p in built_water.duplicate():
		var seed_v: Vector2 = p["seed"]
		if seed_v.distance_to(here) <= far + 40.0:
			continue
		(p["mesh"] as MeshInstance3D).queue_free()
		p.erase("mesh")
		p.erase("cells")
		p["built"] = false
		p["dirty"] = false
		built_water.erase(p)
		if p["kind"] == "river":
			unbuilt_rivers.append(p)
		else:
			unbuilt_water.append(p)
		done += 1
		if done >= 4:
			break
