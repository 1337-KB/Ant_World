extends Node3D

const RIVER_WIDTH := 17          # the river and its banks take this much of the world's edge
const RIVER_CENTER := 9.0        # distance of the river's middle from the world edge
const RIVER_BED_Y := 32.0        # the riverbed, flat
const RIVER_LEVEL := 37.5        # the water line, 5.5 deep. Constant all the way around.
# Biomes. The order matches the arrays below.
const FOREST := 0
const DESERT := 1
const HIGHLANDS := 2
const TUNDRA := 3
const SWAMP := 4
const SAVANNA := 5
const BIOME_NAMES := ["Forest", "Desert dunes", "Rocky highlands", "Frozen tundra", "Swamp", "Savanna"]
const TREE_CHANCE := [1.0, 0.3, 0.3, 0.3, 0.6, 0.35]  # how likely a plant site is accepted, per biome (the plant differs by biome)
const ROCK_CHANCE := [0.4, 0.5, 1.0, 0.6, 0.15, 0.3]   # same for boulders
const FIREFLY_CHANCE := [0.5, 0.05, 0.1, 0.15, 1.0, 0.1]
const BIOME_WALK_SPEED := [1.0, 1.0, 1.0, 0.8, 0.85, 1.0]   # walking speed in each biome (cold, mud slow you)
const BIOME_SPRINT_COST := [1.0, 1.6, 1.0, 1.0, 1.0, 1.0]   # the heat drains sprint energy faster
const BIOME_TINT := [Color(1, 1, 1), Color(1.1, 1.0, 0.82), Color(0.96, 0.96, 1.0), Color(0.9, 0.96, 1.08), Color(0.86, 0.96, 0.86), Color(1.14, 1.02, 0.76)]   # haze and sun colour
const ROCK_TINT := [Color(1, 1, 1), Color(1.5, 1.2, 0.8), Color(0.7, 0.72, 0.82), Color(0.9, 1.0, 1.15), Color(0.8, 1.0, 0.8), Color(1.3, 0.95, 0.75)]
const BIOME_RESOURCES := [                             # what the resource sites in each biome hold
	["sugar", "pebble", "fiber", "resin"],
	["pebble", "resin", "resin", "sugar"],
	["pebble", "pebble", "pebble", "sugar"],
	["sugar", "sugar", "pebble", "fiber"],
	["fiber", "fiber", "resin", "sugar"],
	["sugar", "sugar", "fiber", "pebble"],
]
const HALF := 7200   # the world is 2 * HALF units across (multiple of 16). 7200 is about 20 minutes of walking from the start to the river.
const LAND := HALF - 24   # trees, pools, grass... stay inside this, clear of the river
const BIOME_FREQ := 0.002   # lower = bigger biomes. 0.002 means a biome is roughly 500 units across.
const HEIGHT_CHUNKS := 4      # the world is 16 * this many units tall
const SURFACE_BASE := 44.0     # roughly how high the ground surface sits
const POCKET_MIN_DEPTH := 22.0   # underground water starts at least this far below the surface
const POOL_CELL := 256         # the world is split into squares this big; each may hold one surface pool
const POOL_CHANCE := 0.4       # chance that a square has a pool at all (lower = rarer)
const POCKET_CELL := 64        # squares for underground water pockets
const POCKET_TRIES := 6        # pocket attempts per square
const SOIL_PER_VOLUME := 0.5   # soil gained per unit of ground dug out
const DRINK_RATE := 30.0       # water gained per second while holding F
# Per region (a 32 x 32 square): how much of each thing is placed. Lower = emptier world.
const TREES_PER_REGION := 1.6
const BOULDERS_PER_REGION := 4.0
const GRASS_CLUMPS_PER_REGION := 160
const PEBBLES_PER_REGION := 120
const PICKUPS_PER_REGION := 6.0
const FIREFLIES_PER_REGION := 0.8
const SPIDERS_PER_REGION := 0.3
const REGION_BUDGET_MS := 4.0   # time per frame spent building region content
const EVICT_COLS := 9.0         # terrain farther than this many columns (16 units each) away is forgotten, unless you dug it
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
const FIREFLY_RESPAWN_SECONDS := 60.0
const SPRAY_RANGE := 10.0              # how far the acid spray reaches
const SPRAY_DPS := 25.0                # damage per second to what it hits
const ACID_DRAIN := 25.0               # acid used per second of spraying
const ACID_REGEN := 12.0               # acid regained per second when not spraying
# World streaming: terrain is generated and drawn in columns of 16 x 16 units around the ant.
const DATA_RADIUS := 5        # columns of terrain data kept generated around the ant
const MESH_RADIUS := 4        # columns actually drawn, with collision
const REGION_SIZE := 32.0     # grass, rocks and trees are grouped in squares this big, shown only near the ant
const GEN_BUDGET_MS := 4.0    # time per frame spent generating terrain data
const DAY_LENGTH := 600.0              # seconds for a full day and night (10 minutes)
const SPIDER_RESPAWN_SECONDS := 120.0
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
varying vec2 kind;   // x: dry (golden savanna grass), y: dark (swamp)

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	tip = UV.y;
	kind = COLOR.rg;
	vec3 origin = MODEL_MATRIX[3].xyz;
	rnd = hash21(origin.xz * 0.7);
	float phase = TIME * sway_speed + origin.x * 0.6 + origin.z * 0.45;
	float bend = sin(phase) * sway_strength * tip * tip;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.5;
}

void fragment() {
	vec3 green = mix(vec3(0.10, 0.55, 0.06), vec3(0.40, 0.80, 0.10), rnd);
	vec3 dry = mix(vec3(0.62, 0.50, 0.16), vec3(0.88, 0.76, 0.36), rnd);
	vec3 base = mix(green, dry, kind.x);
	base = mix(base, base * vec3(0.5, 0.65, 0.55), kind.y);
	ALBEDO = mix(base * 0.6, base * 1.35, tip);
	ROUGHNESS = 0.85;
}
"""

# Water: a see-through surface with moving ripples and a brighter shine at glancing angles.
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

var world := World.new()
var water_mat: ShaderMaterial
var water_timer := 0.0
var material := StandardMaterial3D.new()
var noise := FastNoiseLite.new()
var temp_noise := FastNoiseLite.new()    # biomes: hot and cold
var moist_noise := FastNoiseLite.new()   # biomes: wet and dry
var ridge_noise := FastNoiseLite.new()   # shapes the rocky highlands
var current_biome := 0
var biome_tint := Color(1, 1, 1)         # colours the haze and sunlight, blended smoothly between biomes
var biome_tint_target := Color(1, 1, 1)
var biome_timer := 0.0
var patch_noise := FastNoiseLite.new()
var pocket_noise := FastNoiseLite.new()
var patch_noise2 := FastNoiseLite.new()
var soil_noise := FastNoiseLite.new()
var soil_noise2 := FastNoiseLite.new()
var pockets := []   # water pockets: {pos, radii, rmin, level}
var rivers := []    # the river around the world, in short pieces
var pools := []     # surface pools: {x, z, radius, depth, rim, stock, ...}
var water_source := {}   # the pool or pocket you are standing in, if any
var soil_bar: ProgressBar
var water_bar: ProgressBar
var energy_bar: ProgressBar
var chunk_nodes := {}
var col_data := {}       # Vector2i column -> true once all its chunks are generated
var col_meshed := {}     # Vector2i column -> true while it is drawn
var data_wanted: Array = []
var gen_job := {}
var stream_timer := 0.0
var region_nodes := {}   # Vector2i -> Node3D holding that square's grass, rocks and trees
var pool_cells := {}      # Vector2i -> pools in that square (made the first time it is looked at)
var pocket_cells := {}    # same for underground pockets
var built_water: Array = []     # water bodies that have been drawn
var unbuilt_water: Array = []   # water bodies waiting for the ground around them to exist
var obstacles_by_region := {}   # region -> trees and boulders inside it
var region_queue: Array = []
var region_job := {}
var region_done := {}
var region_sites := {}    # region -> its resource site numbers, so they come back the same
var edited_cols := {}     # columns you have dug or filled. Their terrain is never forgotten.
var unbuilt_rivers: Array = []
var bark_mat: StandardMaterial3D
var grass_mat_shared: ShaderMaterial
var blade_mesh_shared: ArrayMesh
var pebble_mesh_shared: SphereMesh
var pebble_mat_shared: StandardMaterial3D
var grass_density_noise: FastNoiseLite
var ant: Ant
var storage_pos := Vector3.ZERO
var storage_ui: StorageUI
var flash_rect: ColorRect
var water_tint: ColorRect
var last_health := 100.0
var sky_mat: ProceduralSkyMaterial
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var day_time := 0.08       # 0 = sunrise, 0.25 = noon, 0.5 = sunset, 0.75 = midnight
var day_count := 1
var night_creatures := false   # true while night creatures (fireflies) are out
var spray: CPUParticles3D
var douse_fx: CPUParticles3D
var fire_cd := 0.0
var res_panel: PanelContainer
var res_rows := {}   # kind -> {"carry": Label, "stored": Label}
var show_help := false   # F1 toggles the full controls list
var health_bar: ProgressBar
var acid_bar: ProgressBar
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

	create_storage()

	ant = Ant.new()
	add_child(ant)
	ant.position = storage_pos + Vector3(-6, 15, 0)
	ant.deposit_requested.connect(_on_deposit)
	ant.water_surface = water_surface_at

	preload_world(Vector3(2, SURFACE_BASE, 8))   # build the ground around the start before the game opens

	crafting = Crafting.new()
	crafting.ant = ant
	add_child(crafting)
	storage_ui = StorageUI.new()
	storage_ui.ant = ant
	add_child(storage_ui)
	setup_spray()
	setup_douse()
	ant.died.connect(func(): show_message("You were killed. Respawned at your queen." if is_instance_valid(queen) else "You were killed. Respawned at the start."))
	crafting.crafted.connect(func(t: String): show_message("Crafted %s. It is in your hotbar." % Crafting.RECIPES[t]["label"]))

# ---------- Per-frame updates ----------

func _process(delta: float) -> void:
	ant.controls_locked = crafting.is_open or storage_ui.is_open
	ant.has_queen = is_instance_valid(queen)
	update_daynight(delta)
	water_tint.visible = camera_underwater()
	if ant.health < last_health - 0.01:
		flash_rect.color.a = 0.4   # flash red when hurt
	last_health = ant.health
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - delta * 1.5)
	handle_dig(delta)
	handle_spray(delta)
	handle_fire(delta)
	stream_world(delta)
	update_biome(delta)
	process_remesh_queue()
	handle_water(delta)
	refresh_water(delta)

	message_time -= delta
	var inv := ant.inventory
	var cap := Ant.CAPACITY
	var hours := fposmod(6.0 + day_time * 24.0, 24.0)
	var text := "Day %d   %02d:%02d   %s\n" % [day_count, int(hours), int((hours - floorf(hours)) * 60.0), BIOME_NAMES[current_biome]]
	for k in res_rows:
		var have := 0
		if k == "soil":
			have = int(ant.soil)
		elif k == "water":
			have = int(ant.water)
		else:
			have = int(inv[k])
		var limit := cap
		if k == "soil":
			limit = int(Ant.SOIL_CAPACITY)
		elif k == "water":
			limit = int(Ant.WATER_CAPACITY)
		res_rows[k]["carry"].text = "%d/%d" % [have, limit]
		res_rows[k]["stored"].text = str(stored(k))

	if build_mode:
		text += "\nBUILD MODE\n"
		for i in PIECE_ORDER.size():
			var t: String = PIECE_ORDER[i]
			var marker := ">" if i == selected else " "
			text += "%s [%d] %s (%s)\n" % [marker, i + 1, Piece.TYPES[t]["label"], cost_text(t)]
		text += "[R] rotate   [Left click] place   [Right click] remove   [B] exit"
	else:
		var held := crafting.held_type()
		if ant.swimming:
			text += "Swimming: [W/S] swim where you look   [Space] up   [Ctrl] dive\n"
		if held != "":
			text += "Holding: %s\n[Left click] place   [Right click] pick up   [Same number] put away   [R] rotate" % Crafting.RECIPES[held]["label"]
		else:
			if show_help:
				text += "[Hold click] dig   [Hold X + click] fill   [Hold right click] smooth   [E] open box or barrel\n"
				text += "[Hold F] drink   [Hold G] acid spray   [H] light fire   [Hold J] douse   [T] eat sugar   [Q] feed queen\n"
				text += "[Shift] sprint   [C] craft   [1-9] hold item   [B] build   [N] skip 3 hours   [K] respawn   [F1] hide help"
			else:
				text += "[F1] controls   [C] craft   [B] build"

	if not water_source.is_empty():
		text += "\n[Hold F] drink water"
	if message_time > 0.0:
		text += "\n" + message
	hud.text = text
	hud.visible = not (crafting.is_open or storage_ui.is_open)
	res_panel.visible = hud.visible

	soil_bar.value = ant.soil
	(soil_bar.get_child(0) as Label).text = "Soil  %d / %d" % [int(ant.soil), int(Ant.SOIL_CAPACITY)]
	water_bar.value = ant.water
	(water_bar.get_child(0) as Label).text = "Water  %d / %d" % [int(ant.water), int(Ant.WATER_CAPACITY)]
	health_bar.value = ant.health
	(health_bar.get_child(0) as Label).text = "Health  %d / %d" % [int(ant.health), int(Ant.MAX_HEALTH)]
	acid_bar.value = ant.acid
	(acid_bar.get_child(0) as Label).text = "Acid  %d / %d" % [int(ant.acid), int(Ant.ACID_MAX)]
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
			KEY_T:
				if not ant.eat_sugar():
					show_message("Nothing to eat, or you are at full health. You need sugar on you.")
			KEY_Q:
				feed_queen()
			KEY_N:
				day_time = fposmod(day_time + 0.125, 1.0)
			KEY_F1:
				show_help = not show_help
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

	if digging and Input.is_key_pressed(KEY_X):
		has_last_dig = false
		fill_ground(point, -cam.global_transform.basis.z)
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
	mark_edited(dirty)
	queue_remesh(dirty, point)
	clear_decor_near(point, clear_radius)
	wake_pickups(point, clear_radius)
	mark_water_dirty(point, clear_radius)

# Hold X and click to spend carried soil and build ground back up where you aim.
const FILL_RADIUS := 1.8
const WATER_PER_FILL := 0.25   # water spent per unit of ground added. Dry soil will not pack, so it needs mixing into mud.

func fill_ground(point: Vector3, aim: Vector3) -> void:
	if ant.soil < 1.0:
		show_message("No soil. Dig some first, then hold X and click to fill.")
		dig_cooldown = 0.6
		return
	if ant.water < 1.0:
		show_message("No water. Soil needs water to pack into mud. Drink at a pool (hold F) first.")
		dig_cooldown = 0.6
		return
	# Center the blob a little in front of the surface so it grows outward from it.
	var center := point - aim.normalized() * FILL_RADIUS * 0.7
	if ant.global_position.distance_to(center) < FILL_RADIUS + 0.9 \
			or (ant.global_position + ant.basis.y * 0.4).distance_to(center) < FILL_RADIUS + 0.9:
		show_message("You are in the way. Step back to fill here.")
		dig_cooldown = 0.6
		return
	var dirty := world.fill_sphere(center, FILL_RADIUS)
	if dirty.is_empty():
		return
	ant.soil = maxf(0.0, ant.soil - world.last_added * SOIL_PER_VOLUME)
	ant.water = maxf(0.0, ant.water - world.last_added * WATER_PER_FILL)
	dig_cooldown = DIG_INTERVAL
	mark_edited(dirty)
	queue_remesh(dirty, center)
	wake_pickups(center, FILL_RADIUS + 1.0)
	mark_water_dirty(center, FILL_RADIUS + 1.0)

# Only a thin slab of ground is locked, so water and trees always have something under them.
# Pools and pockets lock the layer under their water, and trees and boulders lock the ground
# just under their base. Everything deeper, and everything beside them, is diggable.
const POOL_LOCK_DEPTH := 3.0       # how far below a pool or pocket floor stays solid
const OBSTACLE_LOCK_DEPTH := 5.0   # how far below a tree or boulder base stays solid

# True if a dig of this radius at this point would cut into one of those locked slabs.
func is_protected(point: Vector3, radius: float) -> bool:
	var top := point.y + radius      # the highest and lowest points the dig reaches
	var bottom := point.y - radius

	for p in pools_at(point.x, point.z):
		var reach := float(p["radius"]) * 1.4 + radius
		if Vector2(point.x - float(p["x"]), point.z - float(p["z"])).length() < reach \
				and top > float(p["floor"]) - POOL_LOCK_DEPTH and bottom < float(p["level0"]) + 0.5:
			return true

	if edge_dist(point.x, point.z) < RIVER_WIDTH + radius and top > RIVER_BED_Y - POOL_LOCK_DEPTH and bottom < RIVER_LEVEL + 0.5:
		return true   # the riverbed stays, so the river keeps its water

	for p in pockets_at_cell(Vector2i(floori(point.x / POCKET_CELL), floori(point.z / POCKET_CELL))):
		var pos: Vector3 = p["pos"]
		var r: Vector3 = p["radii"]
		var q := Vector2((point.x - pos.x) / (r.x * 1.3 + radius), (point.z - pos.z) / (r.z * 1.3 + radius))
		if q.length() < 1.0 and top > float(p["floor"]) - POOL_LOCK_DEPTH and bottom < float(p["level"]):
			return true

	for o in obstacles_near(point.x, point.z):
		var op: Vector3 = o["pos"]
		if Vector2(point.x - op.x, point.z - op.z).length() < float(o["radius"]) + radius * 0.5 \
				and top > op.y - OBSTACLE_LOCK_DEPTH and bottom < op.y + 2.0:
			return true
	return false

# Hide grass and pebbles whose ground has been dug away.
func clear_decor_near(point: Vector3, radius: float) -> void:
	for decor in decor_sets:
		var rect: Rect2 = decor["rect"]
		if not rect.grow(radius + 1.0).has_point(Vector2(point.x, point.z)):
			continue   # nothing of this square is near the dig
		var mm: MultiMesh = decor["mm"]
		var pos: Array = decor["pos"]
		var hidden: Array = decor["hidden"]
		for i in pos.size():
			if hidden[i] == 1:
				continue
			var p: Vector3 = pos[i]
			if Vector2(p.x - point.x, p.z - point.z).length() > radius:
				continue
			if world.sample_density(p - Vector3(0, 0.3, 0)) < 0.0:
				hidden[i] = 1
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))
				if decor.has("bodies") and decor["bodies"][i] != null:
					decor["bodies"][i].queue_free()   # the pebble is gone, so its solid body goes too

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
		p.destroyed.connect(_on_queen_destroyed)
		p.attacked.connect(_on_queen_attacked)
		ant.spawn_point = p.global_position + Vector3(0, 2.5, 0)
		show_message("The queen is placed. You will respawn here.")
	crafting.consume_held()

var queen_alarm_cd := 0.0

func _on_queen_attacked() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= queen_alarm_cd:
		queen_alarm_cd = now + 8.0
		show_message("The queen is under attack!")

# Press T to eat sugar, Q next to the queen to feed her sugar.
func feed_queen() -> void:
	if not is_instance_valid(queen):
		show_message("You have no queen to feed.")
	elif ant.global_position.distance_to(queen.global_position) > 6.0:
		show_message("Get closer to the queen to feed her.")
	elif queen.health >= Placeable.QUEEN_MAX_HEALTH:
		show_message("The queen is at full health.")
	elif int(ant.inventory["sugar"]) <= 0:
		show_message("You need sugar on you to feed her.")
	else:
		ant.inventory["sugar"] = int(ant.inventory["sugar"]) - 1
		queen.feed(Placeable.SUGAR_HEAL)

# Spiders killed the queen. She is gone and you must craft a new one.
func _on_queen_destroyed(p: Placeable) -> void:
	if p == queen:
		queen = null
		ant.spawn_point = Vector3(0, 70, 0)
	show_message("YOUR QUEEN WAS KILLED! Craft a new queen to restore your colony.")
	p.queue_free()

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
	noise.frequency = 0.012       # wide, gentle hills (one rise every ~80 units)
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.25     # the second layer is faint, so no small bumps

	# Biomes: big slow patterns, so each biome is a large region, found by exploring.
	temp_noise.seed = 4001
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.frequency = BIOME_FREQ
	moist_noise.seed = 4002
	moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moist_noise.frequency = BIOME_FREQ
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
	soil_noise.seed = 301
	soil_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	soil_noise.frequency = 0.07
	soil_noise.fractal_octaves = 2
	soil_noise2.seed = 302
	soil_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	soil_noise2.frequency = 0.15

# How much of each biome there is at a spot, as five numbers: desert, highlands, tundra,
# swamp, savanna. Whatever is left over is forest. The start and the river zone are always
# forest-like.
func biome_weights(x: float, z: float) -> PackedFloat32Array:
	var t := temp_noise.get_noise_2d(x, z)
	var m := moist_noise.get_noise_2d(x, z)
	var desert := smoothstep(0.12, 0.3, t) * smoothstep(0.08, -0.08, m)
	var tundra := smoothstep(-0.12, -0.3, t)
	var swamp := smoothstep(0.3, 0.48, m) * (1.0 - desert) * (1.0 - tundra)
	var high := smoothstep(-0.18, -0.36, m) * (1.0 - desert) * (1.0 - tundra)
	var savanna := smoothstep(0.04, 0.16, t) * smoothstep(-0.02, 0.1, m) * (1.0 - smoothstep(0.3, 0.42, m)) * (1.0 - desert)
	var w := PackedFloat32Array([desert, high, tundra, swamp, savanna])
	var total := 0.0
	for v in w:
		total += v
	var norm := 1.0
	if total > 1.0:
		norm = 1.0 / total
	norm *= smoothstep(26.0, 46.0, Vector2(x - 8.0, z - 8.0).length()) * smoothstep(4.0, 26.0, edge_dist(x, z))
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
		return FOREST
	return which + 1   # weights start at DESERT, which is 1

# The hills before pools are carved into them, shaped further by the biome.
func base_height(x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	var h := clampf(SURFACE_BASE + n * absf(n) * 12.0, SURFACE_BASE - 6.0, SURFACE_BASE + 4.0)
	var w := biome_weights(x, z)
	if w[0] + w[1] + w[2] + w[3] + w[4] <= 0.0:
		return h
	# Desert: rolling dunes.
	var dune := sin(x * 0.11 + 1.7 * sin(z * 0.06)) * cos(z * 0.08 + 1.3 * sin(x * 0.05))
	h += w[0] * (dune * 4.0 + 1.0)
	# Highlands: raised ridges with steep sides.
	var ridge := 1.0 - 2.0 * absf(ridge_noise.get_noise_2d(x, z))
	h += w[1] * 9.0 * smoothstep(0.0, 0.25, ridge)
	# Tundra: flatter ground. Swamp: low, flat and wet. Savanna: wide, gentle plains.
	h = lerpf(h, SURFACE_BASE - 1.0, w[2] * 0.7)
	h = lerpf(h, SURFACE_BASE - 4.5, w[3] * 0.85)
	h = lerpf(h, SURFACE_BASE + 0.5, w[4] * 0.92)   # savanna: very flat, wide plains
	return h

# How far inside the world's edge a spot is. 0 at the very edge.
func edge_dist(x: float, z: float) -> float:
	return float(HALF) - maxf(absf(x), absf(z))

# The real ground height. Around each pool the ground is flattened to a level rim,
# then a shallow bowl is pressed into the middle of it.
func ground_height(x: float, z: float) -> float:
	var h := base_height(x, z)
	for p in pools_at(x, z):
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		var d := Vector2(x - px, z - pz).length()
		if d > r * 1.9:
			continue
		var flat := 1.0 - smoothstep(r, r * 1.9, d)
		h = lerpf(h, float(p["rim"]), flat)
		h -= float(p["depth"]) * (1.0 - smoothstep(r * 0.3, r, d))

	# The river runs all the way around the edge, with a high wall of ground on its far side.
	var e := edge_dist(x, z)
	if e < RIVER_WIDTH + 8.0:
		var channel := 1.0 - smoothstep(5.0, 10.0, absf(e - RIVER_CENTER))
		h = lerpf(h, RIVER_BED_Y, channel)
		h += 14.0 * (1.0 - smoothstep(0.0, 4.0, e))
	return h

# What the very top layer of ground is made of at this spot.
func surface_kind(x: float, z: float) -> int:
	var e := edge_dist(x, z)
	if e < RIVER_WIDTH - 1.0:
		return Blocks.MUD    # riverbed
	if e < RIVER_WIDTH + 6.0:
		return Blocks.SAND   # banks
	for p in pools_at(x, z):
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		var d := Vector2(x - px, z - pz).length()
		if d < r * 1.1:
			return Blocks.MUD
		if d < r * 1.5:
			return Blocks.SAND
	match biome_at(x, z):
		DESERT:
			return Blocks.GRAVEL if patch_noise2.get_noise_2d(x, z) > 0.5 else Blocks.SAND
		HIGHLANDS:
			return Blocks.GRAVEL if patch_noise2.get_noise_2d(x, z) > 0.1 else Blocks.STONE
		TUNDRA:
			return Blocks.GRAVEL if patch_noise2.get_noise_2d(x, z) > 0.55 else Blocks.SNOW
		SWAMP:
			return Blocks.GRASS if patch_noise.get_noise_2d(x, z) > 0.0 else Blocks.MUD
		SAVANNA:
			return Blocks.CLAY if patch_noise2.get_noise_2d(x, z) > 0.45 else Blocks.DRY_GRASS
	var n := patch_noise.get_noise_2d(x, z)
	if n > 0.32:
		return Blocks.SAND
	if n < -0.38:
		return Blocks.CLAY
	if patch_noise2.get_noise_2d(x, z) > 0.55:
		return Blocks.GRAVEL
	return Blocks.GRASS

func generate_terrain() -> void:
	generate_river()
	# Pools and pockets are made per square as the ant gets near, and the terrain itself is
	# generated the same way. See the streaming section.

# Ground height and surface kind for every spot in one column, worked out once.
func gen_column_cache(col: Vector2i) -> Dictionary:
	var size := Chunk.SIZE
	var hs := PackedFloat32Array()
	var ks := PackedInt32Array()
	hs.resize(size * size)
	ks.resize(size * size)
	for lx in size:
		for lz in size:
			var x := col.x * size + lx
			var z := col.y * size + lz
			hs[lx * size + lz] = ground_height(x, z)
			ks[lx * size + lz] = surface_kind(x, z)
	return {"h": hs, "k": ks}

# Fills one chunk straight from the height function. Chunks that are all open
# air are never created, so the empty sky costs nothing.
func fill_chunk(cpos: Vector3i, cache: Dictionary) -> void:
	var size := Chunk.SIZE
	var origin := cpos * size
	var near := pockets_near_chunk(cpos)
	var chunk: Chunk = null
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
# The world is split into big squares. Each square may hold one pool, decided from the square's
# own number the first time anything looks there, so the same pool is always in the same place.

func cell_rng(cell: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, salt))
	return rng

func pools_at(x: float, z: float) -> Array:
	var cell := Vector2i(floori(x / POOL_CELL), floori(z / POOL_CELL))
	if not pool_cells.has(cell):
		gen_pool_cell(cell)
	return pool_cells[cell]

func gen_pool_cell(cell: Vector2i) -> void:
	var list := []
	pool_cells[cell] = list
	var rng := cell_rng(cell, 777)
	if rng.randf() > POOL_CHANCE:
		return
	var origin := Vector2(cell) * float(POOL_CELL)
	for t in 8:
		var x := origin.x + rng.randf_range(30.0, POOL_CELL - 30.0)   # always well inside its square
		var z := origin.y + rng.randf_range(30.0, POOL_CELL - 30.0)
		var radius := rng.randf_range(5.0, 8.0)
		var depth := rng.randf_range(5.0, 7.5)   # deep enough to dive in
		if edge_dist(x, z) < RIVER_WIDTH + 30.0:
			continue
		if Vector2(x, z).distance_to(STORAGE_XZ) < radius + 14.0:
			continue
		var wb := biome_weights(x, z)
		if wb[1] > 0.05 or wb[0] > 0.3:
			continue   # no pools on rocky ridges or deep in the desert
		if wb[3] < 0.5 and wb[4] < 0.5 and rng.randf() > 0.3:
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
		unbuilt_water.append(p)
		return

func near_pool(x: float, z: float, factor: float = 1.3) -> bool:
	for p in pools_at(x, z):
		var px: float = p["x"]
		var pz: float = p["z"]
		var r: float = p["radius"]
		if Vector2(x - px, z - pz).length() < r * factor:
			return true
	return false

# ---------- The river ----------
# A river runs around the whole world and is its boundary. It is built from short pieces,
# each a body of water like a pool, so each one is drawn only when the ground near it is.

func generate_river() -> void:
	var seg := 25   # cells along the river per piece. Odd, so each piece has a middle cell.
	var across := int(RIVER_WIDTH / 2.0)   # half-width of a piece, in cells
	var c := int(RIVER_CENTER)
	# North and south pieces run the full width. East and west skip the corners the others cover.
	var sides := [
		{"axis": "x", "lo": -HALF, "hi": HALF - 1, "pos": HALF - c},
		{"axis": "x", "lo": -HALF, "hi": HALF - 1, "pos": -(HALF - c)},
		{"axis": "z", "lo": -(HALF - RIVER_WIDTH) + 1, "hi": HALF - RIVER_WIDTH - 1, "pos": HALF - c},
		{"axis": "z", "lo": -(HALF - RIVER_WIDTH) + 1, "hi": HALF - RIVER_WIDTH - 1, "pos": -(HALF - c)},
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
				"kind": "river", "floor": RIVER_BED_Y, "level0": RIVER_LEVEL,
				"stock": 1.0e12, "stock_max": 1.0e12,   # a river never runs dry
				"built": false, "dirty": false,
			})
			unbuilt_rivers.append(rivers[rivers.size() - 1])
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
	var origin := Vector2(cell) * float(POCKET_CELL)
	for t in POCKET_TRIES:
		var x := origin.x + rng.randf_range(11.0, POCKET_CELL - 11.0)   # keeps each pocket inside its square
		var z := origin.y + rng.randf_range(11.0, POCKET_CELL - 11.0)
		var radii := Vector3(
			rng.randf_range(3.0, 6.5), rng.randf_range(2.0, 3.5), rng.randf_range(3.0, 6.5))
		if edge_dist(x, z) < HALF - LAND + 8:
			continue
		var h := ground_height(x, z)
		var min_y := World.BEDROCK_Y + radii.y + 3.0
		var max_y := h - radii.y - POCKET_MIN_DEPTH   # only deep down
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
		unbuilt_water.append(p)

func pockets_near_chunk(cpos: Vector3i) -> Array:
	var cell := Vector2i(floori(float(cpos.x * Chunk.SIZE) / POCKET_CELL), floori(float(cpos.z * Chunk.SIZE) / POCKET_CELL))
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
		p["cells"] = {}
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
	var pos := ant.camera.global_position
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
	if not remesh_queue.is_empty():
		return   # let the terrain finish rebuilding first
	# One water body per tick, so several never rebuild in the same frame.
	for p in built_water:
		if p["dirty"]:
			rebuild_water(p)
			return

# ---------- Drinking ----------

func find_water_source() -> Dictionary:
	var a := ant.global_position
	for p in built_water:
		if float(p["stock"]) <= 0.0:
			continue
		var seed_v: Vector2 = p["seed"]
		var bound: Vector2 = p["bound"]
		if absf(a.x - seed_v.x) > bound.x + 3.0 or absf(a.z - seed_v.y) > bound.y + 3.0:
			continue
		match p["kind"]:
			"pool":
				var d := Vector2(a.x - float(p["x"]), a.z - float(p["z"])).length()
				var rim: float = p["rim"]
				if d < float(p["radius"]) * 0.7 + 1.5 and a.y < rim + 2.5 and a.y > rim - float(p["depth"]) - 2.0:
					return p
			"pocket":
				var pos: Vector3 = p["pos"]
				var r: Vector3 = p["radii"]
				var q := Vector3((a.x - pos.x) / r.x, (a.y - pos.y) / r.y, (a.z - pos.z) / r.z)
				if q.length() < 1.25 and a.y < float(p["level"]) + 1.5:
					return p
			"river":
				if edge_dist(a.x, a.z) < RIVER_WIDTH and a.y < RIVER_LEVEL + 1.5 and a.y > RIVER_BED_Y - 1.0:
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

# ---------- Day and night ----------

# Moves the sun, recolors the sky, and sends fireflies out at dusk.
func update_daynight(delta: float) -> void:
	day_time += delta / DAY_LENGTH
	if day_time >= 1.0:
		day_time -= 1.0
		day_count += 1
	var phase := day_time * TAU
	var h := sin(phase)                                  # 1 at noon, -1 at midnight
	var day := smoothstep(-0.12, 0.3, h)                 # 0 = full night, 1 = full day
	var warm := (1.0 - smoothstep(0.0, 0.4, absf(h))) * 0.9   # orange glow near sunrise and sunset

	var top := Color(0.02, 0.03, 0.09).lerp(Color(0.30, 0.50, 0.85), day).lerp(Color(0.25, 0.3, 0.55), warm * 0.5)
	var horizon := Color(0.06, 0.08, 0.16).lerp(Color(0.65, 0.78, 0.92), day).lerp(Color(0.95, 0.5, 0.25), warm)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.03).lerp(Color(0.3, 0.35, 0.3), day)
	biome_tint = biome_tint.lerp(biome_tint_target, minf(1.0, delta * 0.8))
	env.fog_light_color = horizon * biome_tint
	env.ambient_light_energy = lerpf(0.2, 0.75, day)
	env.ambient_light_color = Color(0.4, 0.45, 0.65).lerp(Color(0.82, 0.82, 0.78), day)   # neutral by day, so shade stays grey, not blue

	sun.rotation_degrees = Vector3(-rad_to_deg(phase), -30.0, 0.0)
	sun.light_energy = 1.3 * smoothstep(-0.02, 0.25, h)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.3), warm) * biome_tint
	sun.shadow_enabled = h > 0.02
	moon.rotation_degrees = Vector3(-rad_to_deg(phase) + 180.0, -30.0, 0.0)
	moon.light_energy = 0.25 * smoothstep(0.0, 0.3, -h)

	# Fireflies come out as the light fades, and go to sleep at dawn.
	var night := day < 0.45
	if night != night_creatures:
		night_creatures = night
		for c in get_tree().get_nodes_in_group("creatures"):
			if (c as Creature).nocturnal:
				(c as Creature).set_active(night)

# ---------- Acid spray and creatures ----------

func setup_spray() -> void:
	spray = CPUParticles3D.new()
	spray.emitting = false
	spray.amount = 90
	spray.lifetime = 0.45
	spray.local_coords = false
	spray.direction = Vector3(0, 0, -1)   # straight ahead of the node; we aim the node itself
	spray.spread = 8.0
	spray.initial_velocity_min = 13.0
	spray.initial_velocity_max = 17.0
	spray.gravity = Vector3(0, -3.0, 0)
	var drop := SphereMesh.new()
	drop.radius = 0.1
	drop.height = 0.2
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 1.0, 0.25, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = mat
	spray.mesh = drop
	add_child(spray)

# Hold G to spray acid in front of the camera. It hurts creatures in a narrow cone.
func handle_spray(delta: float) -> void:
	var want := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ant.controls_locked \
			and not build_mode and Input.is_key_pressed(KEY_G)
	if ant.acid_locked and ant.acid >= 20.0:
		ant.acid_locked = false
	var spraying := want and ant.acid > 0.0 and not ant.acid_locked
	spray.emitting = spraying

	if not spraying:
		ant.acid = minf(Ant.ACID_MAX, ant.acid + ACID_REGEN * delta)
		return

	ant.acid = maxf(0.0, ant.acid - ACID_DRAIN * delta)
	if ant.acid <= 0.0:
		ant.acid_locked = true
		show_message("Out of acid.")

	var cam := ant.camera
	var aim := -cam.global_transform.basis.z
	var origin := ant.global_position + ant.basis.y * 0.7
	spray.global_transform = Transform3D(Basis.looking_at(aim, ant.basis.y), origin)

	for c in get_tree().get_nodes_in_group("creatures"):
		var to_c: Vector3 = (c as Node3D).global_position - origin
		var d := to_c.length()
		if not (c as Creature).active:
			continue
		if d < SPRAY_RANGE and d > 0.01 and to_c.normalized().dot(aim) > 0.88:
			(c as Creature).take_damage(SPRAY_DPS * delta)

# ---------- Fire ----------
# Fires only start when the ant lights one with resin (H). They burn, spread over grass,
# and hurt anything in them. Water (hold J) puts them out.

const FIRE_CAP := 30
const FIRE_RANGE := 9.0
const DOUSE_RANGE := 9.0
const WATER_DRAIN := 25.0   # water used per second of dousing

func setup_douse() -> void:
	douse_fx = CPUParticles3D.new()
	douse_fx.emitting = false
	douse_fx.amount = 90
	douse_fx.lifetime = 0.5
	douse_fx.local_coords = false
	douse_fx.direction = Vector3(0, 0, -1)
	douse_fx.spread = 10.0
	douse_fx.initial_velocity_min = 12.0
	douse_fx.initial_velocity_max = 16.0
	douse_fx.gravity = Vector3(0, -6.0, 0)
	var drop := SphereMesh.new()
	drop.radius = 0.1
	drop.height = 0.2
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.65, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = mat
	douse_fx.mesh = drop
	add_child(douse_fx)

func handle_fire(delta: float) -> void:
	fire_cd -= delta
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ant.controls_locked and not build_mode
	if active and fire_cd <= 0.0 and Input.is_key_pressed(KEY_H):
		fire_cd = 0.6
		light_fire()

	var dousing := active and Input.is_key_pressed(KEY_J) and ant.water > 0.0
	douse_fx.emitting = dousing
	if not dousing:
		return
	ant.water = maxf(0.0, ant.water - WATER_DRAIN * delta)
	var cam := ant.camera
	var aim := -cam.global_transform.basis.z
	var origin := ant.global_position + ant.basis.y * 0.7
	douse_fx.global_transform = Transform3D(Basis.looking_at(aim, ant.basis.y), origin)
	for f in get_tree().get_nodes_in_group("fires"):
		var to_f: Vector3 = (f as Node3D).global_position - origin
		var d := to_f.length()
		if d < DOUSE_RANGE and d > 0.01 and to_f.normalized().dot(aim) > 0.8:
			(f as Fire).douse(delta)

func light_fire() -> void:
	if int(ant.inventory["resin"]) <= 0:
		show_message("You need resin to light a fire. Collect the amber drops.")
		return
	var cam := ant.camera
	var hit = world.raycast(cam.global_position, -cam.global_transform.basis.z, FIRE_RANGE)
	if hit == null:
		show_message("Aim at the ground to light a fire.")
		return
	var pos: Vector3 = (hit as Vector3) + Vector3(0, 0.15, 0)
	if spawn_fire(pos):
		ant.inventory["resin"] = int(ant.inventory["resin"]) - 1
		show_message("Fire lit. Hold J to put it out with water.")

# Returns true if a fire was started.
func spawn_fire(pos: Vector3) -> bool:
	if get_tree().get_nodes_in_group("fires").size() >= FIRE_CAP:
		return false
	if water_surface_at(pos + Vector3(0, 0.3, 0)) > -1.0e8:
		return false   # nothing burns in water
	for f in get_tree().get_nodes_in_group("fires"):
		if (f as Node3D).global_position.distance_to(pos) < 1.2:
			return false
	var fire := Fire.new()
	fire.ant = ant
	fire.queen_getter = func(): return queen
	fire.spread_cb = spread_fire
	add_child(fire)
	fire.global_position = pos
	clear_decor_near(pos, 1.8)   # the grass here burns away
	return true

# Fire creeps across grass, and only across grass.
func spread_fire(from: Vector3) -> void:
	var ang := randf() * TAU
	var dist := randf_range(1.8, 3.0)
	var x := from.x + cos(ang) * dist
	var z := from.z + sin(ang) * dist
	if absf(x) > HALF - 1.0 or absf(z) > HALF - 1.0 or surface_kind(x, z) != Blocks.GRASS:
		return
	var hit = world.raycast(Vector3(x, from.y + 4.0, z), Vector3.DOWN, 10.0)
	if hit == null:
		return
	spawn_fire((hit as Vector3) + Vector3(0, 0.15, 0))

func spawn_firefly(pos: Vector3) -> void:
	var f := Firefly.new()
	f.ant = ant
	f.ground_at = ground_height
	f.home = pos
	f.died.connect(_on_creature_died)
	region_node(region_key(pos.x, pos.z)).add_child(f)
	f.global_position = pos
	f.set_active(night_creatures)

func spawn_spider(pos: Vector3) -> void:
	var sp := Spider.new()
	sp.ant = ant
	sp.queen_getter = func(): return queen
	sp.ground_at = ground_height
	sp.is_loaded = ground_ready
	sp.home = pos
	sp.died.connect(_on_creature_died)
	region_node(region_key(pos.x, pos.z)).add_child(sp)
	sp.global_position = pos
	sp.set_active(night_creatures)

# Brings a creature back, unless its region has been forgotten (a new one appears with the region).
func respawn_creature(home: Vector3, firefly: bool) -> void:
	if not region_done.has(region_key(home.x, home.z)):
		return
	if firefly:
		spawn_firefly(home)
	else:
		spawn_spider(home)

# A creature died: drop its loot, and for fireflies, bring a new one back later.
func _on_creature_died(c: Creature) -> void:
	var kind := c.loot_kind()
	if kind != "":
		var p := Pickup.new()
		p.kind = kind
		p.amount = randi_range(1, 3)
		add_child(p)
		p.global_position = c.global_position
	var home := c.home
	if c is Firefly:
		get_tree().create_timer(FIREFLY_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, true))
	elif c is Spider:
		get_tree().create_timer(SPIDER_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, false))

# ---------- Trees and boulders ----------
# Trees are enormous at ant scale: towering trunks you can climb, with a canopy far overhead.
# Boulders are solid rock. The ground around both is too hard to dig, so nothing is left floating.

const FOG_DENSITY := 0.007   # lower = clearer view, but the edge of the loaded world shows more (0.016 was the old value)

var grain_albedo: NoiseTexture2D
var grain_normal: NoiseTexture2D

func add_obstacle(o: Dictionary) -> void:
	var pos: Vector3 = o["pos"]
	var key := region_key(pos.x, pos.z)
	if not obstacles_by_region.has(key):
		obstacles_by_region[key] = []
	obstacles_by_region[key].append(o)

# The trees and boulders in this region and the eight around it.
func obstacles_near(x: float, z: float) -> Array:
	var key := region_key(x, z)
	var out := []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := key + Vector2i(dx, dz)
			if obstacles_by_region.has(k):
				out.append_array(obstacles_by_region[k])
	return out

func near_obstacle(x: float, z: float, margin: float = 1.5) -> bool:
	for o in obstacles_near(x, z):
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

# (Trees and boulders are placed per region. See the region content section.)

# What grows at a site depends on the biome: forest trees, willows in the swamp, flat-topped
# acacias on the savanna, cacti in the desert, bare dead trees and pines in the cold and the hills.
func add_plant(x: float, z: float, rng: RandomNumberGenerator, biome: int, bark: StandardMaterial3D) -> void:
	match biome:
		SWAMP:
			add_willow(x, z, rng)
		SAVANNA:
			add_acacia(x, z, rng)
		DESERT:
			add_cactus(x, z, rng)
		TUNDRA:
			if rng.randf() < 0.5:
				add_dead_tree(x, z, rng)
			else:
				add_pine(x, z, rng, Color(0.60, 0.76, 0.74))   # frosted
		HIGHLANDS:
			add_pine(x, z, rng, Color(0.08, 0.28, 0.14))
		_:
			add_round_tree(x, z, rng, bark)

# A static body for a plant, sunk slightly so it never floats.
func new_plant_body(x: float, z: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	region_node(region_key(x, z)).add_child(body)
	body.global_position = Vector3(x, ground_height(x, z) - 1.0, z)
	return body

func plant_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m

func plant_part(body: Node3D, mesh: Mesh, color: Color, pos: Vector3, orient: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = plant_mat(color)
	mi.transform = Transform3D(orient, pos)
	body.add_child(mi)
	return mi

func cylinder_mesh(top: float, bottom: float, height: float, segments: int = 10) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	return cm

func sphere_mesh() -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return sm

func trunk_collision(body: Node3D, mesh: CylinderMesh, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	col.shape = mesh.create_convex_shape(true, true)
	col.position = pos
	body.add_child(col)

# Desert: a saguaro-style cactus with two arms.
func add_cactus(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(12.0, 19.0)
	var r := rng.randf_range(1.4, 1.9)
	var green := Color(0.18, 0.48, 0.24)
	var trunk := CapsuleMesh.new()
	trunk.radius = r
	trunk.height = h
	trunk.radial_segments = 10
	plant_part(body, trunk, green, Vector3(0, h * 0.5, 0))
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = r
	shape.height = h
	col.shape = shape
	col.position = Vector3(0, h * 0.5, 0)
	body.add_child(col)
	var facing := rng.randf() * TAU
	for side in [-1.0, 1.0]:
		var arm_y := h * rng.randf_range(0.4, 0.6)
		var reach := r * 2.6
		var out := cylinder_mesh(r * 0.55, r * 0.55, reach, 8)
		var arm_basis := Basis(Vector3.UP, facing) * Basis(Vector3.BACK, PI * 0.5)
		plant_part(body, out, green, Basis(Vector3.UP, facing) * Vector3(side * reach * 0.5, arm_y, 0), arm_basis)
		var up := CapsuleMesh.new()
		up.radius = r * 0.55
		up.height = h * rng.randf_range(0.3, 0.45)
		up.radial_segments = 8
		plant_part(body, up, green, Basis(Vector3.UP, facing) * Vector3(side * reach, arm_y + up.height * 0.5, 0))
	add_obstacle({"pos": Vector3(x, ground_height(x, z), z), "radius": r * 2.2})

# Savanna: an acacia with a thin, curving trunk and a wide, layered, flat-topped canopy.
func add_acacia(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(18.0, 27.0)
	var r := rng.randf_range(1.0, 1.5)
	var facing := rng.randf() * TAU
	var lean := rng.randf_range(0.05, 0.2)
	var seg := (h + 1.0) / 3.0
	var pos := Vector3.ZERO
	for k in 3:
		var tb := Basis(Vector3.UP, facing) * Basis(Vector3.RIGHT, lean * float(k + 1) * (1.0 if k % 2 == 0 else -0.6))
		var tm := cylinder_mesh(r * (1.15 - 0.3 * float(k + 1)), r * (1.15 - 0.3 * float(k)), seg, 10)
		var mid := pos + tb * Vector3(0, seg * 0.5, 0)
		plant_part(body, tm, Color(0.34, 0.25, 0.17), mid, tb)
		var col := CollisionShape3D.new()
		col.shape = tm.create_convex_shape(true, true)
		col.transform = Transform3D(tb, mid)
		body.add_child(col)
		pos += tb * Vector3(0, seg, 0)
	# Layered canopy: darker underneath, lighter on top.
	for i in rng.randi_range(2, 3):
		var w := rng.randf_range(9.0, 14.0)
		var t := float(i) / 2.0
		var leaf := Color(0.22, 0.34, 0.10).lerp(Color(0.38, 0.52, 0.14), t)
		var mi := plant_part(body, sphere_mesh(), leaf,
				pos + Vector3(rng.randf_range(-3.0, 3.0), 0.9 * float(i), rng.randf_range(-3.0, 3.0)))
		mi.scale = Vector3(w, 1.0 + 0.2 * float(i), w)
	add_obstacle({"pos": Vector3(x, ground_height(x, z), z), "radius": r * 1.4})
	# Shrubs often grow in the tree's shade.
	if rng.randf() < 0.35:
		for i in rng.randi_range(1, 2):
			var ang := rng.randf() * TAU
			var d := rng.randf_range(4.0, 9.0)
			add_shrub(x + cos(ang) * d, z + sin(ang) * d, rng)

# A low, dark green bush made of a few overlapping lumps. Decoration only: you walk through it.
func add_shrub(x: float, z: float, rng: RandomNumberGenerator) -> void:
	if near_pool(x, z, 1.6) or near_obstacle(x, z, 1.5):
		return
	var root := Node3D.new()
	region_node(region_key(x, z)).add_child(root)
	root.global_position = Vector3(x, ground_height(x, z) - 0.3, z)
	for i in rng.randi_range(2, 3):
		var s := rng.randf_range(1.3, 2.3)
		var g := rng.randf_range(0.85, 1.15)
		var mi := plant_part(root, sphere_mesh(), Color(0.16 * g, 0.30 * g, 0.11 * g),
				Vector3(rng.randf_range(-1.4, 1.4), s * 0.5, rng.randf_range(-1.4, 1.4)))
		mi.scale = Vector3(s * 1.2, s * 0.9, s * 1.2)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# Swamp: a short, dark, drooping willow with hanging vines.
func add_willow(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(15.0, 22.0)
	var r := rng.randf_range(2.0, 2.8)
	var tm := cylinder_mesh(r * 0.7, r * 1.4, h + 1.0, 12)
	plant_part(body, tm, Color(0.24, 0.19, 0.13), Vector3(0, (h + 1.0) * 0.5, 0))
	trunk_collision(body, tm, Vector3(0, (h + 1.0) * 0.5, 0))
	for i in rng.randi_range(3, 5):
		var w := rng.randf_range(6.0, 9.0)
		var mi := plant_part(body, sphere_mesh(), Color(0.10, 0.32, 0.14),
				Vector3(rng.randf_range(-4.0, 4.0), h + rng.randf_range(-1.5, 2.0), rng.randf_range(-4.0, 4.0)))
		mi.scale = Vector3(w, w * 0.6, w)
	for i in 12:
		var ang := rng.randf() * TAU
		var d := rng.randf_range(3.0, 8.0)
		var vlen := rng.randf_range(5.0, 10.0)
		plant_part(body, cylinder_mesh(0.1, 0.16, vlen, 4), Color(0.20, 0.42, 0.20),
				Vector3(cos(ang) * d, h - vlen * 0.5 + 1.0, sin(ang) * d))
	add_obstacle({"pos": Vector3(x, ground_height(x, z), z), "radius": r * 1.4})

# Tundra: a bare, dead tree with crooked branches and no leaves.
func add_dead_tree(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(16.0, 25.0)
	var r := rng.randf_range(1.2, 1.8)
	var bark := Color(0.38, 0.33, 0.30)
	var tm := cylinder_mesh(r * 0.4, r * 1.2, h + 1.0, 8)
	plant_part(body, tm, bark, Vector3(0, (h + 1.0) * 0.5, 0))
	trunk_collision(body, tm, Vector3(0, (h + 1.0) * 0.5, 0))
	for i in rng.randi_range(4, 6):
		var blen := rng.randf_range(6.0, 10.0)
		var attach := Vector3(0, h * rng.randf_range(0.5, 0.95), 0)
		var tilt := rng.randf_range(0.8, 1.3)
		var bb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
		plant_part(body, cylinder_mesh(0.12, 0.45, blen, 6), bark, attach + bb * Vector3(0, blen * 0.5, 0), bb)
	add_obstacle({"pos": Vector3(x, ground_height(x, z), z), "radius": r * 1.3})

# Highlands and tundra: a tall pine made of stacked cones.
func add_pine(x: float, z: float, rng: RandomNumberGenerator, leaf: Color) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(22.0, 32.0)
	var r := rng.randf_range(1.2, 1.7)
	var tm := cylinder_mesh(r * 0.5, r * 1.2, h * 0.7, 10)
	plant_part(body, tm, Color(0.30, 0.20, 0.12), Vector3(0, h * 0.35, 0))
	trunk_collision(body, tm, Vector3(0, h * 0.35, 0))
	var layers := 4
	for i in layers:
		var t := float(i) / float(layers - 1)
		var cr := lerpf(7.5, 3.0, t)
		var ch := 9.0
		var g := rng.randf_range(0.9, 1.1)
		plant_part(body, cylinder_mesh(0.0, cr, ch, 12), Color(leaf.r * g, leaf.g * g, leaf.b * g),
				Vector3(0, h * 0.3 + t * h * 0.6 + ch * 0.4, 0))
	add_obstacle({"pos": Vector3(x, ground_height(x, z), z), "radius": r * 1.4})

func add_round_tree(x: float, z: float, rng: RandomNumberGenerator, bark: StandardMaterial3D) -> void:
	var r := rng.randf_range(2.4, 3.4)          # trunk radius
	var h := rng.randf_range(26.0, 38.0)        # height above the ground
	var base_y := ground_height(x, z)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	region_node(region_key(x, z)).add_child(body)
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
		leaf_mat.albedo_color = Color(0.10 * g, 0.50 * g, 0.08 * g)
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

	add_obstacle({"pos": Vector3(x, base_y, z), "radius": r * 1.5})

func add_rock(x: float, z: float, r: float, rng: RandomNumberGenerator, biome: int = 0) -> void:
	var mesh := make_rock_mesh(rng, r)
	var g := rng.randf_range(0.42, 0.62)
	var tint := Color(g, g * rng.randf_range(0.93, 1.0), g * rng.randf_range(0.85, 0.97))
	var bt: Color = ROCK_TINT[biome]
	tint = Color(minf(tint.r * bt.r, 1.0), minf(tint.g * bt.g, 1.0), minf(tint.b * bt.b, 1.0))
	var mat := make_grain_material(tint, Vector3(0.5, 0.5, 0.5), 2.0)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	region_node(region_key(x, z)).add_child(body)
	body.global_position = Vector3(x, ground_height(x, z) + r * 0.1, z)
	body.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_convex_shape(true, true)
	body.add_child(col)

	add_obstacle({"pos": Vector3(x, ground_height(x, z), z), "radius": r * 1.1})

# A lumpy boulder: a sphere with its surface pushed in and out by noise, flat on the bottom.
func make_rock_mesh(rng: RandomNumberGenerator, r: float) -> ArrayMesh:
	var rock_noise := FastNoiseLite.new()
	rock_noise.seed = rng.randi()
	rock_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var stretch := Vector3(rng.randf_range(0.85, 1.3), rng.randf_range(0.7, 1.0), rng.randf_range(0.85, 1.3))
	var rings := 10
	var segs := 14

	var verts := PackedVector3Array()
	for i in range(rings + 1):
		var phi := PI * float(i) / rings
		for j in segs:
			var theta := TAU * float(j) / segs
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var d := 1.0 + rock_noise.get_noise_3d(dir.x * 1.6, dir.y * 1.6, dir.z * 1.6) * 0.4
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

# Only if its region is still around. If not, the site comes back with the region.
func respawn_pickup(i: int) -> void:
	var sp: Vector3 = pickup_sites[i]["pos"]
	if region_done.has(region_key(sp.x, sp.z)):
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
	p.depleted.connect(func(): get_tree().create_timer(PICKUP_RESPAWN_SECONDS).timeout.connect(respawn_pickup.bind(i)))
	region_node(region_key(pos.x, pos.z)).add_child(p)
	p.global_position = pos

# After a dig, let nearby resources fall into the new hole instead of hovering.
func wake_pickups(point: Vector3, radius: float) -> void:
	for p in get_tree().get_nodes_in_group("pickups"):
		if (p as Pickup).global_position.distance_to(point) < radius + 2.0:
			(p as Pickup).freeze = false

# ---------- Region content ----------
# Everything that decorates the ground (trees, boulders, grass, pebbles, resources, creatures)
# is made one 32 x 32 region at a time, as the ground there appears. Each region is seeded from
# its own position, so it always comes out the same. The work is cut into small steps and done
# a few milliseconds per frame, so walking into new land never stutters.

func inland(x: float, z: float) -> bool:
	return edge_dist(x, z) >= float(HALF - LAND)

func region_step(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	while true:
		if region_job.is_empty():
			if region_queue.is_empty():
				return
			region_job = new_region_job(region_queue.pop_front())
		var items: Array = region_job["items"]
		if items.is_empty():
			region_job = {}
			continue
		var item: Array = items.pop_front()
		run_region_item(region_job, item)
		if (Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
			return

func new_region_job(key: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, 31337))
	var items := []
	for i in int(TREES_PER_REGION + rng.randf()):
		items.append(["tree"])
	for i in int(BOULDERS_PER_REGION + rng.randf()):
		items.append(["boulder"])
	for i in ceili(GRASS_CLUMPS_PER_REGION / 40.0):
		items.append(["grass", 40])
	items.append(["build_grass"])
	for i in ceili(PEBBLES_PER_REGION / 60.0):
		items.append(["pebbles", 60])
	items.append(["build_pebbles"])
	items.append(["pickups"])
	items.append(["creatures"])
	return {"key": key, "rng": rng, "items": items, "grass": {}, "pebbles": {}}

func run_region_item(job: Dictionary, item: Array) -> void:
	match item[0]:
		"tree":
			region_tree(job)
		"boulder":
			region_boulder(job)
		"grass":
			region_grass(job, item[1])
		"build_grass":
			build_grass(job)
		"pebbles":
			region_pebbles(job, item[1])
		"build_pebbles":
			build_pebbles(job)
		"pickups":
			region_pickups(job)
		"creatures":
			region_creatures(job)

# A random spot inside the region, kept this far from its edges.
func region_spot(job: Dictionary, margin: float) -> Vector2:
	var rng: RandomNumberGenerator = job["rng"]
	var rect := region_rect(job["key"])
	return Vector2(
		rect.position.x + rng.randf_range(margin, REGION_SIZE - margin),
		rect.position.y + rng.randf_range(margin, REGION_SIZE - margin))

func get_bark() -> StandardMaterial3D:
	if bark_mat == null:
		bark_mat = make_grain_material(Color(0.42, 0.29, 0.18), Vector3(0.7, 0.07, 0.7), 1.5)
	return bark_mat

# Trees are well spaced and keep away from pools and the start.
func region_tree(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var p := region_spot(job, 4.0)
	var x := p.x
	var z := p.y
	if not inland(x, z):
		return
	if near_pool(x, z, 2.8) or near_obstacle(x, z, 20.0):
		return
	if Vector2(x, z).distance_to(STORAGE_XZ) < 14.0:
		return
	var biome := biome_at(x, z)
	if rng.randf() > TREE_CHANCE[biome]:
		return
	add_plant(x, z, rng, biome, get_bark())

# Boulders, some with smaller rocks leaning against them.
func region_boulder(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var p := region_spot(job, 3.0)
	var x := p.x
	var z := p.y
	var r := 1.2 + pow(rng.randf(), 2.0) * 3.6
	if not inland(x, z):
		return
	if near_pool(x, z, 1.8) or near_obstacle(x, z, r + 1.5):
		return
	if Vector2(x, z).distance_to(STORAGE_XZ) < 6.0 + r:
		return
	var biome := biome_at(x, z)
	if rng.randf() > ROCK_CHANCE[biome]:
		return
	add_rock(x, z, r, rng, biome)
	if r > 2.5:
		for k in 2:
			var a := rng.randf_range(0.0, TAU)
			var dist := r * rng.randf_range(1.1, 1.6)
			var sx := x + cos(a) * dist
			var sz := z + sin(a) * dist
			var sr := r * rng.randf_range(0.3, 0.5)
			if near_pool(sx, sz, 1.8) or near_obstacle(sx, sz, sr + 0.5):
				continue
			add_rock(sx, sz, sr, rng, biome_at(sx, sz))

# Grass grows in clumps, thick in some areas and thin or bare in others.
func region_grass(job: Dictionary, count: int) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["grass"]
	if grass_density_noise == null:
		grass_density_noise = FastNoiseLite.new()
		grass_density_noise.seed = 555
		grass_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		grass_density_noise.frequency = 0.07
	for c in count:
		var sp := region_spot(job, 0.0)
		var cx := sp.x
		var cz := sp.y
		if not inland(cx, cz):
			continue
		var kind0 := surface_kind(cx, cz)
		if kind0 != Blocks.GRASS and kind0 != Blocks.DRY_GRASS:
			continue
		if near_obstacle(cx, cz, 2.5):
			continue
		var d := grass_density_noise.get_noise_2d(cx, cz)
		if d < -0.45:
			continue   # a bare patch
		var blades := roundi(lerpf(2.0, 10.0, smoothstep(-0.2, 0.5, d)))
		if kind0 == Blocks.DRY_GRASS:
			blades = mini(roundi(blades * 1.8), 14)   # savanna grass: thicker than normal, but capped for frame rate
		if Vector2(cx - storage_pos.x, cz - storage_pos.z).length() < STORAGE_RADIUS + 1.0:
			continue
		for b in blades:
			var x := cx + rng.randf_range(-1.1, 1.1)
			var z := cz + rng.randf_range(-1.1, 1.1)
			var kind1 := surface_kind(x, z)
			if kind1 != Blocks.GRASS and kind1 != Blocks.DRY_GRASS:
				continue
			var base := Vector3(x, ground_height(x, z) - 0.1, z)
			var height := rng.randf_range(GRASS_MIN_HEIGHT, GRASS_MAX_HEIGHT)
			var is_dry := kind1 == Blocks.DRY_GRASS
			if is_dry:
				height *= 1.7   # tall savanna grass
			var tint := Color(1.0 if is_dry else 0.0, 1.0 if biome_at(x, z) == SWAMP else 0.0, 0.0)
			var lean := Vector3(
				rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))
			var bs := Basis.from_euler(lean) * Basis().scaled(Vector3(1.0, height, 1.0))
			var key := region_key(x, z)
			if not buckets.has(key):
				buckets[key] = {"xf": [], "pos": [], "tint": []}
			buckets[key]["xf"].append(Transform3D(bs, base))
			buckets[key]["pos"].append(base)
			buckets[key]["tint"].append(tint)

func build_grass(job: Dictionary) -> void:
	var buckets: Dictionary = job["grass"]
	if grass_mat_shared == null:
		var shader := Shader.new()
		shader.code = GRASS_SHADER
		grass_mat_shared = ShaderMaterial.new()
		grass_mat_shared.shader = shader
		blade_mesh_shared = make_blade_mesh()
	for key in buckets:
		var xforms: Array = buckets[key]["xf"]
		var positions: Array = buckets[key]["pos"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = blade_mesh_shared
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, buckets[key]["tint"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = grass_mat_shared
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		region_node(key).add_child(mmi)
		var hidden := []
		hidden.resize(positions.size())
		hidden.fill(0)
		decor_sets.append({"mm": mm, "pos": positions, "hidden": hidden, "rect": region_rect(key)})
		recheck_dug_decor(decor_sets[decor_sets.size() - 1])

# Scenery rebuilt over ground you dug earlier must not float in the air.
func recheck_dug_decor(decor: Dictionary) -> void:
	var rect: Rect2 = decor["rect"]
	var c0 := col_of(Vector3(rect.position.x, 0, rect.position.y))
	var dug := false
	for dx in 2:
		for dz in 2:
			if edited_cols.has(c0 + Vector2i(dx, dz)):
				dug = true
	if not dug:
		return
	var mm: MultiMesh = decor["mm"]
	var pos: Array = decor["pos"]
	var hidden: Array = decor["hidden"]
	for i in pos.size():
		var p: Vector3 = pos[i]
		if world.sample_density(p - Vector3(0, 0.3, 0)) < 0.0:
			hidden[i] = 1
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))
			if decor.has("bodies") and decor["bodies"][i] != null:
				decor["bodies"][i].queue_free()

func region_pebbles(job: Dictionary, count: int) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["pebbles"]
	for i in count:
		var sp := region_spot(job, 0.0)
		var x := sp.x
		var z := sp.y
		if not inland(x, z):
			continue
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
		var key := region_key(x, z)
		if not buckets.has(key):
			buckets[key] = {"xf": [], "tint": [], "pos": [], "bodies": []}
		var b: Dictionary = buckets[key]
		b["xf"].append(Transform3D(bs, pos))
		b["tint"].append(Color(g, g * rng.randf_range(0.92, 1.0), g * rng.randf_range(0.8, 0.95)))
		b["pos"].append(pos)

		# Bigger pebbles are solid, so the ant can't walk through them.
		var body: StaticBody3D = null
		if size >= PEBBLE_SOLID_MIN:
			body = StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var ss := SphereShape3D.new()
			ss.radius = size * 0.5 * 0.8
			cs.shape = ss
			body.add_child(cs)
			region_node(key).add_child(body)
			body.global_position = pos
		b["bodies"].append(body)

func build_pebbles(job: Dictionary) -> void:
	var buckets: Dictionary = job["pebbles"]
	if pebble_mesh_shared == null:
		pebble_mesh_shared = SphereMesh.new()
		pebble_mesh_shared.radius = 0.5
		pebble_mesh_shared.height = 1.0
		pebble_mesh_shared.radial_segments = 8
		pebble_mesh_shared.rings = 5
		pebble_mat_shared = StandardMaterial3D.new()
		pebble_mat_shared.vertex_color_use_as_albedo = true
		pebble_mat_shared.roughness = 1.0
	for key in buckets:
		var b: Dictionary = buckets[key]
		var xforms: Array = b["xf"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = pebble_mesh_shared
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, b["tint"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = pebble_mat_shared
		region_node(key).add_child(mmi)
		var hidden := []
		hidden.resize(xforms.size())
		hidden.fill(0)
		decor_sets.append({"mm": mm, "pos": b["pos"], "hidden": hidden, "bodies": b["bodies"], "rect": region_rect(key)})
		recheck_dug_decor(decor_sets[decor_sets.size() - 1])

# Resources sit at fixed spots. Each spot grows its resource back some time after you take it.
func region_pickups(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var rkey: Vector2i = job["key"]
	if region_sites.has(rkey):
		for i in region_sites[rkey]:
			spawn_pickup(i)
		return
	region_sites[rkey] = []
	for i in int(PICKUPS_PER_REGION + rng.randf()):
		var sp := region_spot(job, 2.0)
		var x := sp.x
		var z := sp.y
		if not inland(x, z):
			continue
		if Vector2(x, z).distance_to(Vector2(storage_pos.x, storage_pos.z)) < 6.0:
			continue
		if near_pool(x, z) or near_obstacle(x, z, 2.0):
			continue
		var options: Array = BIOME_RESOURCES[biome_at(x, z)]
		pickup_sites.append({
			"pos": Vector3(x, ground_height(x, z) + 0.3, z),
			"kind": options[rng.randi() % options.size()],
		})
		region_sites[rkey].append(pickup_sites.size() - 1)
		spawn_pickup(pickup_sites.size() - 1)

func region_creatures(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	for i in int(FIREFLIES_PER_REGION + rng.randf()):
		var sp := region_spot(job, 3.0)
		if inland(sp.x, sp.y) and rng.randf() <= FIREFLY_CHANCE[biome_at(sp.x, sp.y)]:
			spawn_firefly(Vector3(sp.x, ground_height(sp.x, sp.y) + 3.0, sp.y))
	for i in int(SPIDERS_PER_REGION + rng.randf()):
		var sp := region_spot(job, 4.0)
		if not inland(sp.x, sp.y):
			continue
		if sp.distance_to(STORAGE_XZ) < 14.0 or near_pool(sp.x, sp.y, 2.0) or near_obstacle(sp.x, sp.y, 2.0):
			continue
		spawn_spider(Vector3(sp.x, ground_height(sp.x, sp.y) + 0.5, sp.y))


# ---------- World streaming ----------
# The world is much bigger than what is built at once. Terrain data is generated in
# 16 x 16 columns near the ant, a smaller ring of columns is drawn, and columns left far
# behind are un-drawn. Edits stay in memory, so dug ground is still dug when you return.

func col_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / Chunk.SIZE), floori(pos.z / Chunk.SIZE))

func col_in_world(c: Vector2i) -> bool:
	var m := int(HALF / float(Chunk.SIZE))
	return c.x >= -m and c.x < m and c.y >= -m and c.y < m

func region_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / REGION_SIZE), floori(z / REGION_SIZE))

func region_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key) * REGION_SIZE, Vector2(REGION_SIZE, REGION_SIZE))

func region_node(key: Vector2i) -> Node3D:
	if not region_nodes.has(key):
		var n := Node3D.new()
		add_child(n)
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
	for q in remesh_queue:
		if q.x == c.x and q.z == c.y:
			return false
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
		edited_cols[Vector2i(c.x, c.z)] = true

# Generates terrain data a chunk at a time, within a time budget.
func gen_step(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	while true:
		if gen_job.is_empty():
			var found = null
			while not data_wanted.is_empty():
				var c: Vector2i = data_wanted.pop_front()
				if not col_data.has(c):
					found = c
					break
			if found == null:
				return
			gen_job = {"col": found, "cy": 0, "cache": gen_column_cache(found)}
		var col: Vector2i = gen_job["col"]
		fill_chunk(Vector3i(col.x, gen_job["cy"], col.y), gen_job["cache"])
		gen_job["cy"] += 1
		if gen_job["cy"] >= HEIGHT_CHUNKS:
			gen_job = {}
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

	# Dug columns keep their data when you leave, so their regions need asking for again.
	for c in columns_around(cc, data_r):
		if col_data.has(c):
			try_queue_region(Vector2i(floori(c.x / 2.0), floori(c.y / 2.0)))

	for c in columns_around(cc, mesh_r):
		if col_meshed.has(c) or not neighbors_have_data(c):
			continue
		col_meshed[c] = true
		var chunks: Array = []
		for cy in HEIGHT_CHUNKS:
			if world.chunks.has(Vector3i(c.x, cy, c.y)):
				chunks.append(Vector3i(c.x, cy, c.y))
		queue_remesh(chunks, center)

	# Un-draw columns left far behind. Their data stays.
	for c in col_meshed.keys():
		if Vector2(c - cc).length() > mesh_r + 1.5:
			col_meshed.erase(c)
			for cy in HEIGHT_CHUNKS:
				var cpos := Vector3i(c.x, cy, c.y)
				if chunk_nodes.has(cpos):
					chunk_nodes[cpos].queue_free()
					chunk_nodes.erase(cpos)
				remesh_queue.erase(cpos)

	# Grass, rocks, trees and creatures are shown (and run) only over ground that is drawn.
	for key in region_nodes:
		var rn: Node3D = region_nodes[key]
		var shown := false
		for dx in 2:
			for dz in 2:
				if col_meshed.has(Vector2i(key.x * 2 + dx, key.y * 2 + dz)):
					shown = true
		rn.visible = shown
		rn.process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED

	evict_far(center, cc)

	# Water appears once the ground around it exists. One body per update, so it never stutters.
	var candidates: Array = unbuilt_water
	if edge_dist(center.x, center.z) < 300.0:
		candidates = unbuilt_water + unbuilt_rivers
	for p in candidates:
		var seed_v: Vector2 = p["seed"]
		var bound: Vector2 = p["bound"]
		if absf(seed_v.x - center.x) > 200.0 or absf(seed_v.y - center.z) > 200.0:
			continue
		var lo := col_of(Vector3(seed_v.x - bound.x - 2.0, 0, seed_v.y - bound.y - 2.0))
		var hi := col_of(Vector3(seed_v.x + bound.x + 2.0, 0, seed_v.y + bound.y + 2.0))
		var all_there := true
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var cq := Vector2i(cx, cz)
				if col_in_world(cq) and not col_data.has(cq):
					all_there = false
		if all_there:
			add_water_body(p)
			break
	for p in built_water:
		var seed_v: Vector2 = p["seed"]
		(p["mesh"] as MeshInstance3D).visible = col_meshed.has(col_of(Vector3(seed_v.x, 0, seed_v.y)))

# ---------- Forgetting what is far behind ----------
# Without this, memory would grow with every step. Far terrain, scenery and water drawings are
# thrown away and rebuilt identically if you come back. Ground you dug is never forgotten.

func evict_far(center: Vector3, cc: Vector2i) -> void:
	var done := 0
	for c in col_data.keys():
		if Vector2(c - cc).length() <= EVICT_COLS or edited_cols.has(c) or col_meshed.has(c):
			continue
		col_data.erase(c)
		for cy in HEIGHT_CHUNKS:
			world.chunks.erase(Vector3i(c.x, cy, c.y))
		done += 1
		if done >= 8:
			break

	var far := (EVICT_COLS + 1.0) * Chunk.SIZE
	var here := Vector2(center.x, center.z)
	done = 0
	for key in region_nodes.keys():
		var mid := (Vector2(key) + Vector2(0.5, 0.5)) * REGION_SIZE
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

	done = 0
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

# What the ant's biome does to it, and a message on crossing into a new one.
func update_biome(delta: float) -> void:
	biome_timer -= delta
	if biome_timer > 0.0:
		return
	biome_timer = 0.25
	var w := biome_weights(ant.global_position.x, ant.global_position.z)
	var rest := 1.0
	var mix := Color(0, 0, 0)
	for i in w.size():
		mix += (BIOME_TINT[i + 1] as Color) * w[i]
		rest -= w[i]
	biome_tint_target = mix + (BIOME_TINT[0] as Color) * maxf(rest, 0.0)
	var b := biome_at(ant.global_position.x, ant.global_position.z)
	ant.terrain_speed = BIOME_WALK_SPEED[b]
	ant.sprint_cost_mult = BIOME_SPRINT_COST[b]
	if b != current_biome:
		current_biome = b
		var note := ""
		if b == TUNDRA:
			note = " (the cold slows you)"
		elif b == DESERT:
			note = " (the heat drains your sprint)"
		elif b == SWAMP:
			note = " (the mud slows you)"
		show_message("Entered: %s%s" % [BIOME_NAMES[b], note])

# Blocking load of the area around the start, so the game opens on solid ground.
func preload_world(center: Vector3) -> void:
	stream_update(center, 3.0, 2.0)
	gen_step(1.0e9)
	stream_update(center, 3.0, 2.0)
	region_step(1.0e9)
	while not remesh_queue.is_empty():
		build_chunk_node(remesh_queue.pop_front())

func stream_world(delta: float) -> void:
	# The ant waits while the ground under it is still being built.
	var grounded := ground_ready(ant.global_position)
	if not grounded and ant.is_physics_processing():
		ant.velocity = Vector3.ZERO
	ant.set_physics_process(grounded)

	# Invisible walls at the edge of the world.
	var lim := float(HALF) - 1.5
	var ap := ant.global_position
	if absf(ap.x) > lim or absf(ap.z) > lim:
		ant.global_position = Vector3(clampf(ap.x, -lim, lim), ap.y, clampf(ap.z, -lim, lim))

	gen_step(GEN_BUDGET_MS)
	region_step(REGION_BUDGET_MS)
	stream_timer -= delta
	if stream_timer <= 0.0:
		stream_timer = 0.3
		stream_update(ant.global_position, DATA_RADIUS, MESH_RADIUS)

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
		var nxt: Vector3i = remesh_queue.pop_front()
		if col_meshed.has(Vector2i(nxt.x, nxt.z)):   # skip chunks whose column was unloaded meanwhile
			build_chunk_node(nxt)
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
	hud.offset_right = -300.0   # leaves room for the resource panel on the right
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long hint lines wrap instead of running off screen
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("outline_size", 6)   # dark outline so it reads on bright ground
	layer.add_child(hud)

	# Resource panel, top right: what you carry and what the colony has stored.
	res_panel = PanelContainer.new()
	res_panel.anchor_left = 1.0
	res_panel.anchor_right = 1.0
	res_panel.offset_left = -270.0
	res_panel.offset_right = -12.0
	res_panel.offset_top = 12.0
	res_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.55)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	res_panel.add_theme_stylebox_override("panel", sb)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	res_panel.add_child(grid)
	for header in ["", "", "Carry", "Stored"]:
		var hl := Label.new()
		hl.text = header
		hl.add_theme_font_size_override("font_size", 14)
		hl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(hl)
	var rows := [
		["sugar", "Sugar", Pickup.KINDS["sugar"]["color"]],
		["pebble", "Pebbles", Pickup.KINDS["pebble"]["color"]],
		["fiber", "Leaf fiber", Pickup.KINDS["fiber"]["color"]],
		["glow", "Glow", Pickup.KINDS["glow"]["color"]],
		["silk", "Silk", Pickup.KINDS["silk"]["color"]],
		["resin", "Resin", Pickup.KINDS["resin"]["color"]],
		["soil", "Soil", Color(0.55, 0.36, 0.18)],
		["water", "Water", Color(0.25, 0.55, 0.9)],
	]
	for r in rows:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = r[2]
		grid.add_child(swatch)
		var name_l := Label.new()
		name_l.text = r[1]
		name_l.add_theme_font_size_override("font_size", 17)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		var carry_l := Label.new()
		carry_l.add_theme_font_size_override("font_size", 17)
		carry_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(carry_l)
		var stored_l := Label.new()
		stored_l.add_theme_font_size_override("font_size", 17)
		stored_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stored_l.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
		grid.add_child(stored_l)
		res_rows[r[0]] = {"carry": carry_l, "stored": stored_l}
	layer.add_child(res_panel)

	# Soil and water bars in the bottom left corner.
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 0.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 16.0
	box.offset_right = 316.0
	box.offset_top = -272.0
	box.offset_bottom = -100.0   # sits above the hotbar
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	soil_bar = make_bar(box, Color(0.55, 0.36, 0.18), Ant.SOIL_CAPACITY)
	water_bar = make_bar(box, Color(0.25, 0.55, 0.9), Ant.WATER_CAPACITY)
	energy_bar = make_bar(box, Color(0.95, 0.8, 0.2), Ant.ENERGY_MAX)
	health_bar = make_bar(box, Color(0.85, 0.2, 0.2), Ant.MAX_HEALTH)
	acid_bar = make_bar(box, Color(0.55, 0.85, 0.2), Ant.ACID_MAX)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(0.8, 0.05, 0.05, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)
	water_tint = ColorRect.new()
	water_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	water_tint.color = Color(0.04, 0.25, 0.4, 0.45)
	water_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water_tint.visible = false
	layer.add_child(water_tint)
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
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.50, 0.85)
	sky_mat.sky_horizon_color = Color(0.65, 0.78, 0.92)
	sky_mat.ground_horizon_color = Color(0.65, 0.78, 0.92)
	sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.3)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.82, 0.78)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = FOG_DENSITY

	# Ambient occlusion darkens creases and tunnels (Forward+ renderer only).
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.5

	# A soft glow on bright things, and a little extra color.
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# A warm sun with shadows that reach far enough to cover the field.
	sun = $DirectionalLight3D
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0

	# A dim blue moon that shines opposite the sun.
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)
