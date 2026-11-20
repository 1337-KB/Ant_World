extends Node3D

const HALF := 32
const HEIGHT_CHUNKS := 4      # the world is 16 * this many units tall
const SURFACE_BASE := 44.0     # roughly how high the ground surface sits
const WATER_POCKETS := 7       # how many underground water pockets to try to place
const POOLS := 4               # how many pools of water on the surface
const SOIL_PER_VOLUME := 0.5   # soil gained per unit of ground dug out
const DRINK_RATE := 30.0       # water gained per second while holding F
const GRASS_CLUMPS := 450       # how many clumps to try to place
const GRASS_MIN_HEIGHT := 0.8
const GRASS_MAX_HEIGHT := 2.0
const PEBBLE_SOLID_MIN := 0.5   # pebbles at least this big are solid; smaller ones you walk over
const DIG_RADIUS := 2.0
const SMOOTH_RADIUS := 3.0
const HOLD_DELAY := 0.35       # a click digs once; holding past this repeats the dig
const DIG_INTERVAL := 0.14     # seconds between digs while holding
const REACH := 30.0
const STORAGE_XZ := Vector2(8, 8)
const STORAGE_RADIUS := 3.0
const PICKUP_SITES := 45               # how many places resources can appear
const PICKUP_RESPAWN_SECONDS := 90.0   # how long a spot takes to grow its resource back
const PIECE_ORDER := ["pebble_wall", "fiber_floor", "pillar"]

# Grass blades sway in the wind. The color varies per blade and brightens toward the tip.
const GRASS_SHADER = """
shader_type spatial;
render_mode cull_disabled;

uniform float sway_strength = 0.35;
uniform float sway_speed = 1.4;
varying float tip;
varying float rnd;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	tip = UV.y;
	vec3 origin = MODEL_MATRIX[3].xyz;
	rnd = hash21(origin.xz * 0.7);
	float phase = TIME * sway_speed + origin.x * 0.6 + origin.z * 0.45;
	float bend = sin(phase) * sway_strength * tip * tip;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.5;
}

void fragment() {
	vec3 base = mix(vec3(0.18, 0.42, 0.10), vec3(0.45, 0.62, 0.15), rnd);
	ALBEDO = mix(base * 0.5, base * 1.2, tip);
	ROUGHNESS = 0.85;
}
"""

# Water: a see-through surface with moving ripples and a brighter shine at glancing angles.
const WATER_SHADER = """
shader_type spatial;
render_mode cull_disabled;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	float dx = cos(p.x * 2.1 + t * 1.3) * 0.5 + cos((p.x + p.y) * 1.3 - t * 0.9) * 0.4;
	float dz = cos(p.y * 1.7 - t * 1.1) * 0.5 + cos((p.x - p.y) * 1.9 + t * 0.7) * 0.3;
	vec3 n_world = normalize(vec3(dx * 0.08, 1.0, dz * 0.08));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(vec3(0.05, 0.22, 0.36), vec3(0.35, 0.62, 0.82), fres);
	ALPHA = mix(0.62, 0.92, fres);
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
}
"""

var world := World.new()
var water_mat: ShaderMaterial
var water_timer := 0.0
var material := StandardMaterial3D.new()
var noise := FastNoiseLite.new()
var patch_noise := FastNoiseLite.new()
var pocket_noise := FastNoiseLite.new()
var patch_noise2 := FastNoiseLite.new()
var soil_noise := FastNoiseLite.new()
var soil_noise2 := FastNoiseLite.new()
var pockets := []   # water pockets: {pos, radii, rmin, level}
var pools := []     # surface pools: {x, z, radius, depth, rim, stock, ...}
var water_source := {}   # the pool or pocket you are standing in, if any
var soil_bar: ProgressBar
var water_bar: ProgressBar
var energy_bar: ProgressBar
var chunk_nodes := {}
var ant: Ant
var storage_pos := Vector3.ZERO
var storage_ui: StorageUI
var pickup_sites := []   # each: {pos, kind}
var queen: Placeable = null   # the colony's queen, once placed
var hud: Label
var message := ""
var message_time := 0.0

# Scenery (grass, pebbles). Each entry: {"mm": MultiMesh, "pos": Array, "hidden": Array}
var decor_sets := []

# Digging state
var dig_cooldown := 0.0
var remesh_queue: Array[Vector3i] = []   # chunks waiting to be rebuilt
var dig_lock := false   # after placing or menu use, ignore the held button until it is released
var dig_hold := -1.0   # -1 while no button is held
var has_last_dig := false
var last_dig_point := Vector3.ZERO

# Building state
var build_mode := false
var selected := 0
var yaw := 0.0
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var ghost_xform := Transform3D.IDENTITY
var ghost_valid := false
var target_piece: Piece = null
var target_placeable: Placeable = null
var crafting: Crafting

func _ready() -> void:
	setup_environment()
	setup_crosshair()
	setup_hud()
	setup_noise()
	setup_terrain_material()
	setup_ghost()

	generate_terrain()
	for cpos in world.chunks:
		build_chunk_node(cpos)

	create_storage()
	create_water()
	create_pool_water()
	scatter_landmarks()
	scatter_grass()
	scatter_pebbles()
	scatter_pickups()

	ant = Ant.new()
	add_child(ant)
	ant.position = storage_pos + Vector3(-6, 15, 0)
	ant.deposit_requested.connect(_on_deposit)

	crafting = Crafting.new()
	crafting.ant = ant
	add_child(crafting)
	storage_ui = StorageUI.new()
	storage_ui.ant = ant
	add_child(storage_ui)
	crafting.crafted.connect(func(t: String): show_message("Crafted %s. It is in your hotbar." % Crafting.RECIPES[t]["label"]))

# ---------- Per-frame updates ----------

func _process(delta: float) -> void:
	ant.controls_locked = crafting.is_open or storage_ui.is_open
	handle_dig(delta)
	process_remesh_queue()
	handle_water(delta)
	refresh_water(delta)

	message_time -= delta
	var inv := ant.inventory
	var cap := Ant.CAPACITY
	var text := "Carrying:  Sugar %d/%d   Pebbles %d/%d   Leaf fiber %d/%d\n" % [
		inv["sugar"], cap, inv["pebble"], cap, inv["fiber"], cap]
	text += "Stored:      Sugar %d   Pebbles %d   Leaf fiber %d   Soil %d   Water %d\n" % [
		stored("sugar"), stored("pebble"), stored("fiber"), stored("soil"), stored("water")]

	if build_mode:
		text += "\nBUILD MODE\n"
		for i in PIECE_ORDER.size():
			var t: String = PIECE_ORDER[i]
			var marker := ">" if i == selected else " "
			text += "%s [%d] %s (%s)\n" % [marker, i + 1, Piece.TYPES[t]["label"], cost_text(t)]
		text += "[R] rotate   [Left click] place   [Right click] remove   [B] exit"
	else:
		var held := crafting.held_type()
		if held != "":
			text += "Holding: %s\n[Left click] place   [Right click] pick up   [Same number] put away   [R] rotate" % Crafting.RECIPES[held]["label"]
		else:
			text += "[Walk over resources] collect   [E at a box or barrel] open it   [Hold click] dig   [Hold right click] smooth   [Hold F] drink   [Shift] sprint\n[C] craft   [1-9] hold an item   [B] build   [K] respawn"

	if not water_source.is_empty():
		text += "\n[Hold F] drink water"
	if message_time > 0.0:
		text += "\n" + message
	hud.text = text

	soil_bar.value = ant.soil
	(soil_bar.get_child(0) as Label).text = "Soil  %d / %d" % [int(ant.soil), int(Ant.SOIL_CAPACITY)]
	water_bar.value = ant.water
	(water_bar.get_child(0) as Label).text = "Water  %d / %d" % [int(ant.water), int(Ant.WATER_CAPACITY)]
	energy_bar.value = ant.energy
	var tired := " (resting)" if ant.exhausted else ""
	(energy_bar.get_child(0) as Label).text = "Energy  %d / %d%s" % [int(ant.energy), int(Ant.ENERGY_MAX), tired]

func _physics_process(_delta: float) -> void:
	target_piece = null
	target_placeable = null
	ghost_valid = false
	var held := crafting.held_type()
	if not build_mode and held == "":
		ghost.visible = false
		return

	# Ray from the camera through the crosshair.
	var cam := ant.camera
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH)
	q.exclude = [ant.get_rid()]
	q.collision_mask = 1
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		ghost.visible = false
		return

	if hit["collider"] is Piece:
		target_piece = hit["collider"]
	elif hit["collider"] is Placeable:
		target_placeable = hit["collider"]

	# Place the piece so it rests against the surface we hit.
	var type := ""
	var size: Vector3
	var affordable := true
	if build_mode:
		type = PIECE_ORDER[selected]
		size = Piece.TYPES[type]["size"]
		affordable = can_afford(type)
	else:
		size = Crafting.RECIPES[held]["size"]
	var h := size * 0.5
	var b := Basis(Vector3.UP, yaw)
	var n: Vector3 = hit["normal"]
	# How far the box reaches along the surface normal.
	var extent := absf(n.dot(b.x)) * h.x + absf(n.dot(b.y)) * h.y + absf(n.dot(b.z)) * h.z
	var pos: Vector3 = hit["position"] + n * (extent - 0.05)
	ghost_xform = Transform3D(b, pos)

	# Valid if affordable, not on top of the ant, and not inside another piece.
	var valid := affordable
	if valid and ant.global_position.distance_to(pos) < h.length() + 0.6:
		valid = false
	if valid:
		var box := BoxShape3D.new()
		box.size = size - Vector3.ONE * 0.2
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = box
		sq.transform = ghost_xform
		sq.collision_mask = 4
		if not space.intersect_shape(sq, 1).is_empty():
			valid = false
	ghost_valid = valid

	(ghost.mesh as BoxMesh).size = size
	ghost.visible = true
	ghost.global_transform = ghost_xform
	ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if valid else Color(1.0, 0.3, 0.3, 0.45)

# ---------- Input ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if storage_ui.is_open:
			if event.keycode == KEY_E:
				dig_lock = true
				storage_ui.close()
			return   # a box is open, so other controls are off
		if crafting.is_open and event.keycode != KEY_C:
			return   # the craft menu is open, so other controls are off
		match event.keycode:
			KEY_B:
				dig_lock = true
				build_mode = not build_mode
				if build_mode:
					crafting.deselect()
			KEY_C:
				dig_lock = true
				crafting.toggle_menu()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				dig_lock = true
				var n: int = event.keycode - KEY_1
				if build_mode:
					if n < PIECE_ORDER.size():
						selected = n
				else:
					crafting.select_slot(n)
			KEY_R:
				yaw += PI / 2.0
			KEY_K:
				ant.respawn()
				show_message("Respawned at your queen." if is_instance_valid(queen) else "Respawned at the start. Place a queen to set your spawn.")

	if event is InputEventMouseButton and event.pressed:
		if crafting.is_open or storage_ui.is_open:
			return   # a menu is open, so clicks belong to it
		# First click after pressing Esc just recaptures the mouse.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if build_mode:
			dig_lock = true
			if event.button_index == MOUSE_BUTTON_LEFT:
				place_piece()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				remove_piece()
		elif crafting.held_type() != "":
			dig_lock = true
			if event.button_index == MOUSE_BUTTON_LEFT:
				place_item()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				pick_up_item()

# ---------- Digging ----------

# Hold left mouse to dig a continuous tunnel. Hold right mouse to smooth walls.
func handle_dig(delta: float) -> void:
	dig_cooldown -= delta
	if dig_lock:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			dig_hold = -1.0
			has_last_dig = false
			return   # still holding the button from placing or a menu click
		dig_lock = false
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not build_mode and crafting.held_type() == ""
	var digging := active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var smoothing := active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	if not digging:
		has_last_dig = false   # stroke ended
	if not (digging or smoothing):
		dig_hold = -1.0
		return
	var first := false
	if dig_hold < 0.0:
		dig_hold = 0.0
		first = true           # a fresh click digs exactly once, right away
	else:
		dig_hold += delta
	if not first and (dig_hold < HOLD_DELAY or dig_cooldown > 0.0):
		return

	var cam := ant.camera
	var hit = world.raycast(cam.global_position, -cam.global_transform.basis.z, REACH)
	if hit == null:
		return
	var point: Vector3 = hit

	# The ground under and around water is too hard to dig.
	var reach := DIG_RADIUS if digging else SMOOTH_RADIUS
	var blocked := is_protected(point, reach)
	if digging and has_last_dig and not blocked:
		blocked = is_protected(last_dig_point.lerp(point, 0.5), reach)
	if blocked:
		if first:
			show_message("The ground here is too hard to dig.")
		return

	var dirty: Array[Vector3i]
	var clear_radius := SMOOTH_RADIUS + 1.0
	if digging:
		if has_last_dig and last_dig_point.distance_to(point) < 0.5:
			return   # barely moved, skip
		var from := point
		if has_last_dig and last_dig_point.distance_to(point) < 6.0:
			from = last_dig_point   # connect to the previous point
		dirty = world.dig_capsule(from, point, DIG_RADIUS)
		var gained := world.last_removed * SOIL_PER_VOLUME
		if gained > 0.0:
			if ant.soil + gained > Ant.SOIL_CAPACITY:
				show_message("Soil full. Extra is lost.")
			ant.soil = minf(Ant.SOIL_CAPACITY, ant.soil + gained)
		last_dig_point = point
		has_last_dig = true
		clear_radius = DIG_RADIUS + 2.0
	else:
		dirty = world.smooth_sphere(point, SMOOTH_RADIUS)

	dig_cooldown = DIG_INTERVAL
	queue_remesh(dirty, point)
	clear_decor_near(point, clear_radius)
	wake_pickups(point, clear_radius)
	mark_water_dirty(point, clear_radius)

# True if a dig of this radius at this point would touch ground that is locked
# around water: everything under and around a surface pool, and the ground
# below the waterline of an underground pocket.
func is_protected(point: Vector3, radius: float) -> bool:
	for p in pools:
		var reach := float(p["radius"]) * 1.5 + 1.0 + radius
		if Vector2(point.x - float(p["x"]), point.z - float(p["z"])).length() < reach \
				and point.y < float(p["rim"]) + 2.0 + radius:
			return true
	for o in obstacles:
		var op: Vector3 = o["pos"]
		if Vector2(point.x - op.x, point.z - op.z).length() < float(o["radius"]) + 1.5 + radius \
				and point.y < op.y + float(o["radius"]) + 2.0:
			return true
	for p in pockets:
		var pos: Vector3 = p["pos"]
		var r: Vector3 = p["radii"]
		var q := Vector3(
			(point.x - pos.x) / (r.x * 1.5 + radius),
			(point.y - pos.y) / (r.y * 1.5 + radius),
			(point.z - pos.z) / (r.z * 1.5 + radius))
		if q.length() < 1.0 and point.y - radius < float(p["level"]):
			return true
	return false

# Hide grass and pebbles whose ground has been dug away.
func clear_decor_near(point: Vector3, radius: float) -> void:
	for set in decor_sets:
		var mm: MultiMesh = set["mm"]
		var pos: Array = set["pos"]
		var hidden: Array = set["hidden"]
		for i in pos.size():
			if hidden[i] == 1:
				continue
			var p: Vector3 = pos[i]
			if Vector2(p.x - point.x, p.z - point.z).length() > radius:
				continue
			if world.sample_density(p - Vector3(0, 0.3, 0)) < 0.0:
				hidden[i] = 1
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))
				if set.has("bodies") and set["bodies"][i] != null:
					set["bodies"][i].queue_free()   # the pebble is gone, so its solid body goes too

# ---------- Building ----------

func can_afford(type: String) -> bool:
	var cost: Dictionary = Piece.TYPES[type]["cost"]
	for k in cost:
		if stored(k) < cost[k]:
			return false
	return true

func cost_text(type: String) -> String:
	var parts: Array[String] = []
	var cost: Dictionary = Piece.TYPES[type]["cost"]
	for k in cost:
		parts.append("%d %s" % [cost[k], str(Pickup.KINDS[k]["label"]).to_lower()])
	return ", ".join(parts)

func place_piece() -> void:
	if not ghost.visible:
		return
	var type: String = PIECE_ORDER[selected]
	if not can_afford(type):
		show_message("Not enough in your boxes.")
		return
	if not ghost_valid:
		show_message("Can't place that here.")
		return
	var cost: Dictionary = Piece.TYPES[type]["cost"]
	for k in cost:
		spend_stored(k, cost[k])
	var p := Piece.new()
	p.type = type
	add_child(p)
	p.global_transform = ghost_xform

func remove_piece() -> void:
	if target_piece == null:
		return
	# Full refund.
	var cost: Dictionary = Piece.TYPES[target_piece.type]["cost"]
	for k in cost:
		add_stored(k, cost[k])
	target_piece.queue_free()
	target_piece = null

func place_item() -> void:
	var held := crafting.held_type()
	if held == "" or not ghost.visible:
		return
	if not ghost_valid:
		show_message("Can't place that here.")
		return
	if held == "queen" and is_instance_valid(queen):
		show_message("Your colony already has a queen. Pick her up to move her.")
		return
	var p := Placeable.new()
	p.type = held
	add_child(p)
	p.global_transform = ghost_xform
	if held == "queen":
		queen = p
		ant.spawn_point = p.global_position + Vector3(0, 2.5, 0)
		show_message("The queen is placed. You will respawn here.")
	crafting.consume_held()

func pick_up_item() -> void:
	if target_placeable == null:
		return
	if target_placeable.total_stock() > 0.0:
		show_message("Empty it first. It still holds something.")
		return
	if target_placeable == queen:
		queen = null
		ant.spawn_point = Vector3(0, 70, 0)
	crafting.add_item(target_placeable.type)
	target_placeable.queue_free()
	target_placeable = null

func setup_ghost() -> void:
	ghost = MeshInstance3D.new()
	ghost.mesh = BoxMesh.new()
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45)
	ghost.material_override = ghost_mat
	ghost.visible = false
	ghost.top_level = true
	add_child(ghost)

# ---------- Depositing ----------

func show_message(text: String) -> void:
	message = text
	message_time = 2.0

# Pressing E opens the nearest box or barrel.
func _on_deposit() -> void:
	var best: Placeable = null
	var best_d := 4.5
	for c in get_tree().get_nodes_in_group("containers"):
		var d := ant.global_position.distance_to((c as Placeable).global_position)
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		show_message("No box or barrel nearby. Craft one with C.")
		return
	dig_lock = true
	storage_ui.open(best)

# ---------- Colony storage ----------
# What the colony owns is whatever sits in its boxes and barrels.

func containers() -> Array:
	return get_tree().get_nodes_in_group("containers")

func stored(kind: String) -> int:
	var total := 0.0
	for c in containers():
		total += float((c as Placeable).stock.get(kind, 0.0))
	return int(total)

func spend_stored(kind: String, amount: int) -> void:
	var left := float(amount)
	for c in containers():
		var p := c as Placeable
		var have := float(p.stock.get(kind, 0.0))
		var take := minf(have, left)
		if take > 0.0:
			p.stock[kind] = have - take
			left -= take
		if left <= 0.0:
			return

# Refunds go into any box with room. Anything that doesn't fit is lost.
func add_stored(kind: String, amount: int) -> void:
	var left := float(amount)
	for c in containers():
		var p := c as Placeable
		var room := p.cap(kind) - float(p.stock.get(kind, 0.0))
		var put := minf(room, left)
		if put > 0.0:
			p.stock[kind] = float(p.stock.get(kind, 0.0)) + put
			left -= put
		if left <= 0.0:
			return

# ---------- Terrain ----------

func setup_noise() -> void:
	noise.seed = 1234
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	noise.fractal_octaves = 3

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
	soil_noise.seed = 301
	soil_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	soil_noise.frequency = 0.07
	soil_noise.fractal_octaves = 2
	soil_noise2.seed = 302
	soil_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	soil_noise2.frequency = 0.15

# The hills before pools are carved into them.
func base_height(x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	return clampf(SURFACE_BASE + n * absf(n) * 12.0, SURFACE_BASE - 6.0, SURFACE_BASE + 4.0)

# The real ground height. Around each pool the ground is flattened to a level rim,
# then a shallow bowl is pressed into the middle of it.
func ground_height(x: float, z: float) -> float:
	var h := base_height(x, z)
	for p in pools:
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		var d := Vector2(x - px, z - pz).length()
		if d > r * 1.9:
			continue
		var flat := 1.0 - smoothstep(r, r * 1.9, d)
		h = lerpf(h, float(p["rim"]), flat)
		h -= float(p["depth"]) * (1.0 - smoothstep(r * 0.3, r, d))
	return h

# What the very top layer of ground is made of at this spot.
func surface_kind(x: float, z: float) -> int:
	for p in pools:
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		var d := Vector2(x - px, z - pz).length()
		if d < r * 1.1:
			return Blocks.MUD
		if d < r * 1.5:
			return Blocks.SAND
	var n := patch_noise.get_noise_2d(x, z)
	if n > 0.32:
		return Blocks.SAND
	if n < -0.38:
		return Blocks.CLAY
	if patch_noise2.get_noise_2d(x, z) > 0.55:
		return Blocks.GRAVEL
	return Blocks.GRASS

func generate_terrain() -> void:
	generate_pools()
	generate_pockets()
	var cmax := ceili(float(HALF) / Chunk.SIZE)
	for cx in range(-cmax, cmax):
		for cz in range(-cmax, cmax):
			for cy in HEIGHT_CHUNKS:
				fill_chunk(Vector3i(cx, cy, cz))

# Fills one chunk straight from the height function. Chunks that are all open
# air are never created, so the empty sky costs nothing.
func fill_chunk(cpos: Vector3i) -> void:
	var size := Chunk.SIZE
	var origin := cpos * size
	var near := pockets_near_chunk(cpos)
	var chunk: Chunk = null
	for lx in size:
		for lz in size:
			var x := origin.x + lx
			var z := origin.z + lz
			var h := ground_height(x, z)
			var kind := surface_kind(x, z)
			var under := kind if kind != Blocks.GRASS else Blocks.DIRT
			for ly in size:
				var y := origin.y + ly
				var depth := h - y
				if depth <= -1.0:
					continue   # open air; a new chunk already starts as air
				if chunk == null:
					chunk = world.get_or_create_chunk(cpos)
				var dens := clampf(depth, -1.0, 1.0)
				var mat := Blocks.AIR
				if depth > 0.0:
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

				chunk.set_voxel(lx, ly, lz, dens, mat)

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

# Picks a few pool sites, well apart from each other and from the storage.
func generate_pools() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var tries := 0
	while pools.size() < POOLS and tries < 300:
		tries += 1
		var x := rng.randf_range(-HALF + 10, HALF - 10)
		var z := rng.randf_range(-HALF + 10, HALF - 10)
		var radius := rng.randf_range(3.5, 6.0)
		var depth := rng.randf_range(1.8, 2.6)
		if Vector2(x, z).distance_to(STORAGE_XZ) < radius + 14.0:
			continue
		var clear := true
		for other in pools:
			var ox: float = other["x"]
			var oz: float = other["z"]
			if Vector2(x - ox, z - oz).length() < 22.0:
				clear = false
				break
		if not clear:
			continue
		pools.append({
			"x": x, "z": z, "radius": radius, "depth": depth,
			"rim": base_height(x, z),
			"stock": radius * radius * 10.0,
			"stock_max": radius * radius * 10.0,
		})

func near_pool(x: float, z: float, scale: float = 1.3) -> bool:
	for p in pools:
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		if Vector2(x - px, z - pz).length() < r * scale:
			return true
	return false

# The water sits a little below the rim, filling the bowl. Like the underground
# water, it is only a visual for now.
func create_pool_water() -> void:
	for p in pools:
		var rim: float = p["rim"]
		var depth: float = p["depth"]
		p["floor"] = rim - depth                 # lowest point of the bowl
		p["level0"] = rim - 0.45 * depth         # water line when the pool is full
		var bound := float(p["radius"]) * 1.5 + 2.0
		p["bound"] = Vector2(bound, bound)
		p["seed"] = Vector2(float(p["x"]), float(p["z"]))
		add_water_body(p)

# ---------- Water pockets ----------

# Picks where the pockets go. They are sealed cavities underground that you find by digging.
func generate_pockets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var tries := 0
	while pockets.size() < WATER_POCKETS and tries < 600:
		tries += 1
		var x := rng.randf_range(-HALF + 8, HALF - 8)
		var z := rng.randf_range(-HALF + 8, HALF - 8)
		var radii := Vector3(
			rng.randf_range(3.0, 6.5), rng.randf_range(2.0, 3.5), rng.randf_range(3.0, 6.5))
		var h := ground_height(x, z)
		var min_y := World.BEDROCK_Y + radii.y + 3.0
		var max_y := h - radii.y - 6.0
		if max_y <= min_y:
			continue
		var y := rng.randf_range(min_y, max_y)
		var pos := Vector3(x, y, z)

		# Keep pockets apart from each other.
		var clear := true
		for other in pockets:
			var other_pos: Vector3 = other["pos"]
			if other_pos.distance_to(pos) < 12.0:
				clear = false
				break
		if not clear:
			continue

		pockets.append({
			"pos": pos,
			"radii": radii,
			"rmin": minf(radii.x, minf(radii.y, radii.z)),
			"level": y - radii.y * 0.2,   # water fills the lower part of the cavity
			"stock": radii.x * radii.z * 4.0,
			"stock_max": radii.x * radii.z * 4.0,
		})

# Only the pockets close enough to touch this chunk, so most chunks check none.
func pockets_near_chunk(cpos: Vector3i) -> Array:
	var lo := Vector3(cpos * Chunk.SIZE)
	var hi := lo + Vector3.ONE * Chunk.SIZE
	var margin := 4.0
	var result := []
	for p in pockets:
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

# A translucent body of water filling the bottom of each cavity. It is only a visual for now:
# you can walk through it, and it has no gathering yet.
func create_water() -> void:
	for p in pockets:
		var pos: Vector3 = p["pos"]
		var r: Vector3 = p["radii"]
		p["floor"] = pos.y - r.y
		p["level0"] = p["level"]
		p["bound"] = Vector2(r.x + 2.0, r.z + 2.0)
		p["seed"] = Vector2(pos.x, pos.z)
		add_water_body(p)
	print("WATER V2: built surfaces for ", pools.size(), " pools and ", pockets.size(), " pockets")

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

func rebuild_water(p: Dictionary) -> void:
	p["dirty"] = false
	var body: MeshInstance3D = p["mesh"]
	var fill := float(p["stock"]) / float(p["stock_max"])
	var floor_y: float = p["floor"]
	var level := floor_y + (float(p["level0"]) - floor_y) * fill
	if fill < 0.03 or level - floor_y < 0.5:
		body.mesh = null
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
		body.mesh = null    # the floor was dug out, so the water has drained away
		return

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for c in queue:
		var b := verts.size()
		verts.append(Vector3(c.x - 0.5, level, c.y - 0.5))
		verts.append(Vector3(c.x + 0.5, level, c.y - 0.5))
		verts.append(Vector3(c.x + 0.5, level, c.y + 0.5))
		verts.append(Vector3(c.x - 0.5, level, c.y + 0.5))
		for k in 4:
			norms.append(Vector3.UP)
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	body.mesh = mesh

# Called after digging, so water near the dig is redrawn to match the new ground.
func mark_water_dirty(point: Vector3, radius: float) -> void:
	for group in [pools, pockets]:
		for p in group:
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
	if not remesh_queue.is_empty():
		return   # let the terrain finish rebuilding first
	# One water body per tick, so several never rebuild in the same frame.
	for group in [pools, pockets]:
		for p in group:
			if p["dirty"]:
				rebuild_water(p)
				return

# ---------- Drinking ----------

# The pool or underground pocket the ant is standing in, or an empty dictionary.
func find_water_source() -> Dictionary:
	var a := ant.global_position
	for p in pools:
		if float(p["stock"]) <= 0.0:
			continue
		var d := Vector2(a.x - float(p["x"]), a.z - float(p["z"])).length()
		var rim: float = p["rim"]
		if d < float(p["radius"]) * 0.7 + 1.5 and a.y < rim + 2.5 and a.y > rim - float(p["depth"]) - 2.0:
			return p
	for p in pockets:
		if float(p["stock"]) <= 0.0:
			continue
		var pos: Vector3 = p["pos"]
		var r: Vector3 = p["radii"]
		var q := Vector3((a.x - pos.x) / r.x, (a.y - pos.y) / r.y, (a.z - pos.z) / r.z)
		if q.length() < 1.25 and a.y < float(p["level"]) + 1.5:
			return p
	return {}

# Hold F at the water to fill your bar. The water gets lower as you drink.
func handle_water(delta: float) -> void:
	water_source = find_water_source()
	if water_source.is_empty():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or crafting.is_open or storage_ui.is_open or not Input.is_key_pressed(KEY_F):
		return
	if ant.water >= Ant.WATER_CAPACITY - 0.01:
		show_message("Your water bar is full.")
		return
	var amount := minf(DRINK_RATE * delta, minf(Ant.WATER_CAPACITY - ant.water, float(water_source["stock"])))
	ant.water += amount
	water_source["stock"] = float(water_source["stock"]) - amount
	water_source["dirty"] = true
	if float(water_source["stock"]) <= 0.0:
		show_message("This water is all gone.")

func setup_terrain_material() -> void:
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0

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

	material.albedo_texture = albedo_tex
	material.normal_enabled = true
	material.normal_texture = normal_tex
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(0.4, 0.4, 0.4)

# The starting spot. There is no marker: your storage is the boxes you build.
func create_storage() -> void:
	storage_pos = Vector3(STORAGE_XZ.x, ground_height(STORAGE_XZ.x, STORAGE_XZ.y), STORAGE_XZ.y)

# ---------- Trees and boulders ----------
# Trees are enormous at ant scale: towering trunks you can climb, with a canopy far overhead.
# Boulders are solid rock. The ground around both is too hard to dig, so nothing is left floating.

const TREES := 7
const BOULDERS := 14

var obstacles := []   # each: {pos, radius}, used to keep other things clear and the ground undiggable
var grain_albedo: NoiseTexture2D
var grain_normal: NoiseTexture2D

func near_obstacle(x: float, z: float, margin: float = 1.5) -> bool:
	for o in obstacles:
		var op: Vector3 = o["pos"]
		if Vector2(x - op.x, z - op.z).length() < float(o["radius"]) + margin:
			return true
	return false

# A rough, grainy material projected from all sides. uv_scale stretches the grain along an axis.
func make_grain_material(color: Color, uv_scale: Vector3, bump: float) -> StandardMaterial3D:
	if grain_albedo == null:
		var grain := FastNoiseLite.new()
		grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		grain.frequency = 0.08
		grain.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.6, 0.6, 0.6))
		ramp.set_color(1, Color(1, 1, 1))
		grain_albedo = NoiseTexture2D.new()
		grain_albedo.noise = grain
		grain_albedo.seamless = true
		grain_albedo.width = 256
		grain_albedo.height = 256
		grain_albedo.color_ramp = ramp
		grain_normal = NoiseTexture2D.new()
		grain_normal.noise = grain
		grain_normal.seamless = true
		grain_normal.as_normal_map = true
		grain_normal.bump_strength = 6.0
		grain_normal.width = 256
		grain_normal.height = 256
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = grain_albedo
	m.normal_enabled = true
	m.normal_texture = grain_normal
	m.normal_scale = bump
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = uv_scale
	return m

func scatter_landmarks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337

	# Trees, well spaced and away from pools and the start.
	var bark := make_grain_material(Color(0.42, 0.29, 0.18), Vector3(0.7, 0.07, 0.7), 1.5)
	var placed := 0
	var tries := 0
	while placed < TREES and tries < 400:
		tries += 1
		var x := rng.randf_range(-HALF + 8, HALF - 8)
		var z := rng.randf_range(-HALF + 8, HALF - 8)
		if near_pool(x, z, 2.8) or near_obstacle(x, z, 10.0):
			continue
		if Vector2(x, z).distance_to(STORAGE_XZ) < 10.0:
			continue
		add_tree(x, z, rng, bark)
		placed += 1

	# Boulders, some with smaller rocks leaning against them.
	placed = 0
	tries = 0
	while placed < BOULDERS and tries < 600:
		tries += 1
		var x := rng.randf_range(-HALF + 3, HALF - 3)
		var z := rng.randf_range(-HALF + 3, HALF - 3)
		var r := 1.2 + pow(rng.randf(), 2.0) * 3.6
		if near_pool(x, z, 1.8) or near_obstacle(x, z, r + 1.5):
			continue
		if Vector2(x, z).distance_to(STORAGE_XZ) < 6.0 + r:
			continue
		add_rock(x, z, r, rng)
		placed += 1
		if r > 2.5:
			for k in 2:
				var a := rng.randf_range(0.0, TAU)
				var dist := r * rng.randf_range(1.1, 1.6)
				var sx := x + cos(a) * dist
				var sz := z + sin(a) * dist
				var sr := r * rng.randf_range(0.3, 0.5)
				if near_pool(sx, sz, 1.8) or near_obstacle(sx, sz, sr + 0.5):
					continue
				add_rock(sx, sz, sr, rng)

func add_tree(x: float, z: float, rng: RandomNumberGenerator, bark: StandardMaterial3D) -> void:
	var r := rng.randf_range(2.4, 3.4)          # trunk radius
	var h := rng.randf_range(26.0, 38.0)        # height above the ground
	var base_y := ground_height(x, z)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	body.global_position = Vector3(x, base_y - 2.0, z)   # sunk a little so it never floats

	# The trunk flares wider at the foot and narrows toward the top.
	var tm := CylinderMesh.new()
	tm.bottom_radius = r * 1.5
	tm.top_radius = r * 0.75
	tm.height = h + 2.0
	tm.radial_segments = 16
	tm.rings = 4
	var trunk := MeshInstance3D.new()
	trunk.mesh = tm
	trunk.material_override = bark
	trunk.position = Vector3(0, (h + 2.0) * 0.5, 0)
	body.add_child(trunk)
	var col := CollisionShape3D.new()
	col.shape = tm.create_convex_shape(true, true)
	col.position = trunk.position
	body.add_child(col)

	# A clump of leaf masses far overhead.
	for i in rng.randi_range(5, 7):
		var leaf_mat := StandardMaterial3D.new()
		var g := rng.randf_range(0.8, 1.2)
		leaf_mat.albedo_color = Color(0.14 * g, 0.36 * g, 0.10 * g)
		leaf_mat.roughness = 0.9
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 14
		sm.rings = 8
		var leaves := MeshInstance3D.new()
		leaves.mesh = sm
		leaves.material_override = leaf_mat
		var s := rng.randf_range(6.0, 10.0)
		leaves.scale = Vector3(s, s * 0.7, s)
		leaves.position = Vector3(rng.randf_range(-6.0, 6.0), h + 2.0 + rng.randf_range(-3.0, 4.0), rng.randf_range(-6.0, 6.0))
		body.add_child(leaves)

	obstacles.append({"pos": Vector3(x, base_y, z), "radius": r * 1.5})

func add_rock(x: float, z: float, r: float, rng: RandomNumberGenerator) -> void:
	var mesh := make_rock_mesh(rng, r)
	var g := rng.randf_range(0.42, 0.62)
	var tint := Color(g, g * rng.randf_range(0.93, 1.0), g * rng.randf_range(0.85, 0.97))
	var mat := make_grain_material(tint, Vector3(0.5, 0.5, 0.5), 2.0)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	body.global_position = Vector3(x, ground_height(x, z) + r * 0.1, z)
	body.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_convex_shape(true, true)
	body.add_child(col)

	obstacles.append({"pos": Vector3(x, ground_height(x, z), z), "radius": r * 1.1})

# A lumpy boulder: a sphere with its surface pushed in and out by noise, flat on the bottom.
func make_rock_mesh(rng: RandomNumberGenerator, r: float) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var stretch := Vector3(rng.randf_range(0.85, 1.3), rng.randf_range(0.7, 1.0), rng.randf_range(0.85, 1.3))
	var rings := 10
	var segs := 14

	var verts := PackedVector3Array()
	for i in range(rings + 1):
		var phi := PI * float(i) / rings
		for j in segs:
			var theta := TAU * float(j) / segs
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var d := 1.0 + noise.get_noise_3d(dir.x * 1.6, dir.y * 1.6, dir.z * 1.6) * 0.4
			var p := dir * d * r * stretch
			p.y = maxf(p.y, -r * 0.5)
			verts.append(p)

	var idx := PackedInt32Array()
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for i in rings:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			var c := (i + 1) * segs + j
			var e := (i + 1) * segs + (j + 1) % segs
			idx.append_array([a, c, b, b, c, e])
			var n1 := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			var n2 := (verts[e] - verts[b]).cross(verts[c] - verts[b])
			for v in [a, b, c]:
				norms[v] += n1
			for v in [b, e, c]:
				norms[v] += n2
	for k in norms.size():
		norms[k] = norms[k].normalized() if norms[k].length() > 0.0001 else Vector3.UP

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ---------- Scenery ----------

func make_blade_mesh() -> ArrayMesh:
	var w := 0.12
	var verts := PackedVector3Array([
		Vector3(-w, 0.0, 0.0), Vector3(w, 0.0, 0.0),
		Vector3(-w * 0.7, 0.5, 0.05), Vector3(w * 0.7, 0.5, 0.05),
		Vector3(0.0, 1.0, 0.2),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 1),
	])
	var norms := PackedVector3Array()
	for i in 5:
		norms.append(Vector3(0, 0, 1))
	var idx := PackedInt32Array([0, 1, 2, 1, 3, 2, 2, 3, 4])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func scatter_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var xforms: Array[Transform3D] = []
	var positions := []

	# Grass grows in clumps, thick in some areas and thin or bare in others.
	var dense := FastNoiseLite.new()
	dense.seed = 555
	dense.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dense.frequency = 0.07
	for c in GRASS_CLUMPS:
		var cx := rng.randf_range(-HALF + 3, HALF - 3)
		var cz := rng.randf_range(-HALF + 3, HALF - 3)
		if surface_kind(cx, cz) != Blocks.GRASS:
			continue
		if near_obstacle(cx, cz, 2.5):
			continue
		var d := dense.get_noise_2d(cx, cz)
		if d < -0.45:
			continue   # a bare patch
		var blades := roundi(lerpf(2.0, 10.0, smoothstep(-0.2, 0.5, d)))
		if Vector2(cx - storage_pos.x, cz - storage_pos.z).length() < STORAGE_RADIUS + 1.0:
			continue
		for b in blades:
			var x := cx + rng.randf_range(-1.1, 1.1)
			var z := cz + rng.randf_range(-1.1, 1.1)
			if surface_kind(x, z) != Blocks.GRASS:
				continue
			var base := Vector3(x, ground_height(x, z) - 0.1, z)
			var height := rng.randf_range(GRASS_MIN_HEIGHT, GRASS_MAX_HEIGHT)
			var lean := Vector3(
				rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))
			var bs := Basis.from_euler(lean) * Basis().scaled(Vector3(1.0, height, 1.0))
			xforms.append(Transform3D(bs, base))
			positions.append(base)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = make_blade_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])

	var shader := Shader.new()
	shader.code = GRASS_SHADER
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = shader

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	var hidden := []
	hidden.resize(positions.size())
	hidden.fill(0)
	decor_sets.append({"mm": mm, "pos": positions, "hidden": hidden})

func scatter_pebbles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var xforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var positions := []
	var bodies := []

	for i in 350:
		var x := rng.randf_range(-HALF + 2, HALF - 2)
		var z := rng.randf_range(-HALF + 2, HALF - 2)
		if Vector2(x - storage_pos.x, z - storage_pos.z).length() < STORAGE_RADIUS + 1.0:
			continue
		if near_pool(x, z) or near_obstacle(x, z, 1.0):
			continue
		var size := rng.randf_range(0.25, 1.0)
		if rng.randf() < 0.1:
			size *= 1.8
		var squash := Vector3(size, size * rng.randf_range(0.5, 0.85), size * rng.randf_range(0.7, 1.0))
		var rot := Vector3(
			rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, TAU), rng.randf_range(-0.3, 0.3))
		var bs := Basis.from_euler(rot) * Basis().scaled(squash)
		var base := Vector3(x, ground_height(x, z), z)
		var pos := base - Vector3(0, size * 0.12, 0)
		var g := rng.randf_range(0.35, 0.6)
		xforms.append(Transform3D(bs, pos))
		tints.append(Color(g, g * rng.randf_range(0.92, 1.0), g * rng.randf_range(0.8, 0.95)))
		positions.append(pos)

		# Bigger pebbles are solid, so the ant can't walk through them.
		var body: StaticBody3D = null
		if size >= PEBBLE_SOLID_MIN:
			body = StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var ss := SphereShape3D.new()
			ss.radius = size * 0.5 * 0.8
			cs.shape = ss
			body.add_child(cs)
			add_child(body)
			body.global_position = pos
		bodies.append(body)

	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 5

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sphere
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, tints[i])

	var pebble_mat := StandardMaterial3D.new()
	pebble_mat.vertex_color_use_as_albedo = true
	pebble_mat.roughness = 1.0

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = pebble_mat
	add_child(mmi)

	var hidden := []
	hidden.resize(positions.size())
	hidden.fill(0)
	decor_sets.append({"mm": mm, "pos": positions, "hidden": hidden, "bodies": bodies})

# Resources sit at fixed spots scattered at random over the field. Each spot grows its
# resource back some time after you take it.
func scatter_pickups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var kinds: Array[String] = ["sugar", "pebble", "fiber"]
	var tries := 0
	while pickup_sites.size() < PICKUP_SITES and tries < 600:
		tries += 1
		var x := rng.randf_range(-HALF + 4, HALF - 4)
		var z := rng.randf_range(-HALF + 4, HALF - 4)
		if Vector2(x, z).distance_to(Vector2(storage_pos.x, storage_pos.z)) < 6.0:
			continue
		if near_pool(x, z) or near_obstacle(x, z, 2.0):
			continue
		pickup_sites.append({
			"pos": Vector3(x, ground_height(x, z) + 0.3, z),
			"kind": kinds[pickup_sites.size() % 3],
		})
	for i in pickup_sites.size():
		spawn_pickup(i)

func spawn_pickup(i: int) -> void:
	var site: Dictionary = pickup_sites[i]
	var pos: Vector3 = site["pos"]
	var p := Pickup.new()
	p.kind = site["kind"]
	p.amount = randi_range(4, 10)
	p.home = pos
	# Held still where it sits, so it never drops from the sky or slides about.
	# It is released only if the ground under it gets dug away.
	p.freeze = world.sample_density(pos - Vector3(0, 0.6, 0)) > 0.0
	p.depleted.connect(func(): get_tree().create_timer(PICKUP_RESPAWN_SECONDS).timeout.connect(spawn_pickup.bind(i)))
	add_child(p)
	p.global_position = pos

# After a dig, let nearby resources fall into the new hole instead of hovering.
func wake_pickups(point: Vector3, radius: float) -> void:
	for p in get_tree().get_nodes_in_group("pickups"):
		if (p as Pickup).global_position.distance_to(point) < radius + 2.0:
			(p as Pickup).freeze = false

# ---------- Chunks ----------

# Edited chunks are rebuilt a few per frame instead of all at once, so a dig or
# smooth never freezes the game. The chunks nearest the edit go first.
func queue_remesh(chunks: Array, point: Vector3) -> void:
	for c in chunks:
		if not remesh_queue.has(c):
			remesh_queue.append(c)
	remesh_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var ca := Vector3(a * Chunk.SIZE) + Vector3.ONE * (Chunk.SIZE * 0.5)
		var cb := Vector3(b * Chunk.SIZE) + Vector3.ONE * (Chunk.SIZE * 0.5)
		return ca.distance_squared_to(point) < cb.distance_squared_to(point))

const REMESH_BUDGET_MS := 5.0   # time spent rebuilding chunks per frame (at least one chunk)

func process_remesh_queue() -> void:
	if remesh_queue.is_empty():
		return
	var start := Time.get_ticks_usec()
	while not remesh_queue.is_empty():
		build_chunk_node(remesh_queue.pop_front())
		if (Time.get_ticks_usec() - start) / 1000.0 > REMESH_BUDGET_MS:
			break

func build_chunk_node(cpos: Vector3i) -> void:
	if chunk_nodes.has(cpos):
		chunk_nodes[cpos].queue_free()
		chunk_nodes.erase(cpos)

	var mesh := SurfaceMesher.build(world, cpos)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = Vector3(cpos * Chunk.SIZE)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	mi.add_child(body)

	add_child(mi)
	chunk_nodes[cpos] = mi

# ---------- UI and environment ----------

func setup_crosshair() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "+"
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(label)
	add_child(layer)

func setup_hud() -> void:
	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.anchor_right = 1.0
	hud.offset_left = 16.0
	hud.offset_top = 12.0
	hud.offset_right = -16.0
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long hint lines wrap instead of running off screen
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("outline_size", 6)   # dark outline so it reads on bright ground
	layer.add_child(hud)

	# Soil and water bars in the bottom left corner.
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 0.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 16.0
	box.offset_right = 316.0
	box.offset_top = -216.0
	box.offset_bottom = -100.0   # sits above the hotbar
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	soil_bar = make_bar(box, Color(0.55, 0.36, 0.18), Ant.SOIL_CAPACITY)
	water_bar = make_bar(box, Color(0.25, 0.55, 0.9), Ant.WATER_CAPACITY)
	energy_bar = make_bar(box, Color(0.95, 0.8, 0.2), Ant.ENERGY_MAX)
	add_child(layer)

func make_bar(parent: Control, color: Color, max_v: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(300, 28)
	bar.max_value = max_v
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	back.set_corner_radius_all(4)
	back.set_border_width_all(2)
	back.border_color = Color(1, 1, 1, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	bar.add_child(label)
	parent.add_child(bar)
	return bar

func setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.50, 0.85)
	sky_mat.sky_horizon_color = Color(0.65, 0.78, 0.92)
	sky_mat.ground_horizon_color = Color(0.65, 0.78, 0.92)
	sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.3)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = 0.002

	# Ambient occlusion darkens creases and tunnels (Forward+ renderer only).
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.5

	# A soft glow on bright things, and a little extra color.
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# A warm sun with shadows that reach far enough to cover the field.
	var sun: DirectionalLight3D = $DirectionalLight3D
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
