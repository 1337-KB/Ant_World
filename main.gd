class_name Main
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
const BEETLE_CHANCE := [1.0, 0.2, 0.3, 0.1, 0.6, 1.0]       # per biome: forest, desert, highlands, tundra, swamp, savanna
const CENTIPEDE_CHANCE := [0.8, 0.2, 0.8, 0.0, 1.0, 0.1]
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
const HEIGHT_CHUNKS := 6      # chunks stack up to this layer, so the top of the world is 16 * this high (termite mounds are tall)
const CY_MIN := -5            # and down to this layer, so the ground is about three times as deep (the bottom is 16 * this)
const CAVE_THRESHOLD := 0.5   # higher = fewer, smaller caves
const SURFACE_BASE := 44.0     # roughly how high the ground surface sits
const POCKET_MIN_DEPTH := 22.0   # underground water starts at least this far below the surface
const POOL_CELL := 256         # the world is split into squares this big; each may hold one surface pool
const LAKE_CHANCE := 0.3       # chance that a forest square holds a big lake (the square with the start always does)
const POOL_CHANCE := 0.4       # chance that a square has a pool at all (lower = rarer)
const POCKET_CELL := 64        # squares for underground water pockets
const POCKET_TRIES := 6        # pocket attempts per square
const SOIL_PER_VOLUME := 0.5   # soil gained per unit of ground dug out
const DRINK_RATE := 30.0       # water gained per second while holding F
# Per region (a 32 x 32 square): how much of each thing is placed. Lower = emptier world.
const TREES_PER_REGION := 6.0
const BOULDERS_PER_REGION := 4.0
const GRASS_CLUMPS_PER_REGION := 160
const PEBBLES_PER_REGION := 120
const PICKUPS_PER_REGION := 6.0
const FIREFLIES_PER_REGION := 0.8
const SPIDERS_PER_REGION := 0.3
const BEETLES_PER_REGION := 0.3
const CENTIPEDES_PER_REGION := 0.25
const REGION_BUDGET_MS := 4.0   # time per frame spent building region content
const ROYAL_WALL := 6.0          # how thick the undiggable walls around a living queen's cell are
const MOUND_CELL := 320         # the world is split into squares this big; each may hold a termite mound
const MOUND_CHANCE := [0.35, 0.4, 0.15, 0.0, 0.25, 0.9]   # per biome: forest, desert, highlands, tundra, swamp, savanna
const GREAT_CELL := Vector2i(8, -6)   # the square holding the Great Mound, about 3,300 units from the start
const MOUND_START_CLEAR := 150.0    # no mounds this close to the start, and rarer out to 700
const EVICT_COLS := 24.0         # terrain farther than this many columns (16 units each) away is forgotten, unless you dug it
const GRASS_MIN_HEIGHT := 0.8
const GRASS_MAX_HEIGHT := 2.0
const PEBBLE_SOLID_MIN := 0.5   # pebbles at least this big are solid; smaller ones you walk over
const DIG_RADIUS := 2.0
const SMOOTH_RADIUS := 3.0
const BRUSH_MIN := 1.4          # smallest dig size
const BRUSH_MAX := 3.5          # largest dig size for any ant. Each class has its own limit (dig_max in ant.gd).
const BRUSH_STEP := 0.4         # change per mouse wheel notch or [ ] press
var brush := DIG_RADIUS         # current dig radius. Smoothing and filling scale with it.
const HOLD_DELAY := 0.35       # a click digs once; holding past this repeats the dig
const DIG_INTERVAL := 0.14     # seconds between digs while holding
const REACH := 30.0
const STORAGE_XZ := Vector2(8, 8)
const STORAGE_RADIUS := 3.0
const FIREFLY_RESPAWN_SECONDS := 60.0
const SPRAY_RANGE := 10.0              # how far the acid spray reaches
const SPRAY_DPS := 25.0                # damage per second to what it hits
const QUEEN_MENU_RANGE := 6.0          # how close to your queen to change class
const SOIL_PER_ROCK := 15.0            # soil used to make one rock (Y, soldiers)
const ROCK_SPEED := 32.0
const ROCK_DAMAGE := 40.0
const ROCK_COOLDOWN := 0.55
const ACID_DRAIN := 25.0               # acid used per second of spraying
const ACID_REGEN := 12.0               # acid regained per second when not spraying
# World streaming: terrain is generated and drawn in columns of 16 x 16 units around the ant.
const DATA_RADIUS := 20       # columns of terrain data kept generated around the ant
const MESH_RADIUS := 17       # columns actually drawn (about 272 units)
const COLLISION_COLS := 7.0   # only ground this close is solid; farther ground is just a picture, which is much cheaper
const TERRAIN_FADE_START := 200.0   # the detailed ground starts to thin out here...
const TERRAIN_FADE_END := 262.0    # ...and is gone here, where the distant land takes over
const TREE_FADE_END := 170.0        # trees and rocks fade out by about here
const GRASS_FADE_START := 60.0
const GRASS_FADE_END := 95.0
const GRASS_COLS := 8.0       # grass and pebbles are drawn only this close (there are far too many to draw all the way out)
# The deep ground is only generated when you are near it. Far columns get just the surface layers,
# which is what you see, so the land ahead of you appears much faster.
const DEEP_COLS := 5.0          # columns around you whose deep ground is generated too
const DEEP_SHALLOW := 24.0      # a far column is generated this far below its lowest ground
const DEEP_NEAR_MOUND := 62.0   # near a termite mound it goes much deeper, because the colony lives there
const ACTIVE_COLS := 4.0      # creatures only move and think this close
const REGION_SIZE := 32.0     # grass, rocks and trees are grouped in squares this big, shown only near the ant
const GEN_BUDGET_MS := 8.0    # time per frame spent generating terrain data
const DAY_LENGTH := 600.0              # seconds for a full day and night (10 minutes)
const SPIDER_RESPAWN_SECONDS := 120.0
const BEETLE_RESPAWN_SECONDS := 150.0
const CENTIPEDE_RESPAWN_SECONDS := 150.0
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
varying float dist;
uniform float fade_start = 50.0;
uniform float fade_end = 78.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	tip = UV.y;
	kind = COLOR.rg;
	vec3 origin = MODEL_MATRIX[3].xyz;
	dist = length(origin - INV_VIEW_MATRIX[3].xyz);
	rnd = hash21(origin.xz * 0.7);
	float phase = TIME * sway_speed + origin.x * 0.6 + origin.z * 0.45;
	float bend = sin(phase) * sway_strength * tip * tip;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.5;
}

void fragment() {
	// Blades thin out with a fine dither toward the edge of the grass, so it never pops in.
	if (hash21(FRAGCOORD.xy) > 1.0 - smoothstep(fade_start, fade_end, dist)) {
		discard;
	}
	vec3 green = mix(vec3(0.10, 0.55, 0.06), vec3(0.40, 0.80, 0.10), rnd);
	vec3 dry = mix(vec3(0.62, 0.50, 0.16), vec3(0.88, 0.76, 0.36), rnd);
	vec3 base = mix(green, dry, kind.x);
	base = mix(base, base * vec3(0.5, 0.65, 0.55), kind.y);
	ALBEDO = mix(base * 0.6, base * 1.35, tip);
	ROUGHNESS = 0.85;
}
"""

# Water: a see-through surface with moving ripples and a brighter shine at glancing angles.

var world := World.new()
var terrain := Terrain.new()   # ground, biomes, caves, lakes: see terrain.gd
var content := Content.new()   # trees, flora, pickups, cave contents: see content.gd
var compass := Compass.new()   # the compass strip at the top of the screen: see compass.gd
var progression := Progression.new()   # tiers and goals: see progression.gd
var save := SaveGame.new()   # saving and loading: see save_game.gd
var water := Water.new()   # all the water: see water.gd   # all the water: see water.gd
var material := StandardMaterial3D.new()
var current_biome := 0
var biome_tint := Color(1, 1, 1)         # colours the haze and sunlight, blended smoothly between biomes
var biome_tint_target := Color(1, 1, 1)
var biome_timer := 0.0
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
var grey_jobs: Array = []   # chunks of a dead mound waiting to turn grey
var obstacles_by_region := {}   # region -> trees and boulders inside it
var region_queue: Array = []
var region_done := {}
var edited_cols := {}     # columns you have dug or filled. Their terrain is never forgotten.
const FLORA_PATCHES_PER_REGION := 22
const LANDMARK_CHANCE := 0.5   # chance a region has one landmark (log, stump, bottle cap, giant acorn)
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
var rock_cd := 0.0
var class_menu_open := false
var class_open_frame := -1
var storage_open_frame := -1
var class_layer: CanvasLayer
var class_buttons: Array = []
var douse_fx: CPUParticles3D
var fire_cd := 0.0
var res_panel: PanelContainer
var res_rows := {}   # kind -> {"carry": Label, "stored": Label}
var world_map: WorldMap
var pheromone: Pheromone
var sky_life: SkyLife
var far_terrain: FarTerrain
var show_help := false   # F1 toggles the full controls list
var health_bar: ProgressBar
var acid_bar: ProgressBar
var brush_preview: MeshInstance3D
var brush_show := 0.0          # seconds the dig size display stays on screen after you change it
const BRUSH_SHOW_TIME := 2.5
var queen: Placeable = null   # the colony's queen, once placed
var hud: Label
var message := ""
var message_time := 0.0

# Scenery (grass, pebbles). Each entry: {"mm": MultiMesh, "pos": Array, "hidden": Array}
var decor_sets := []

# Digging state
var dig_cooldown := 0.0
var remesh_queue: Array[Vector3i] = []   # chunks waiting to be rebuilt
var remesh_set := {}                    # the same chunks, for a quick 'is it already waiting' check
var remesh_focus := Vector3.ZERO        # the chunks nearest this point are rebuilt first
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

# Saves when the window is closed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and save != null:
		save.save_now(false, true)

func _ready() -> void:
	water.setup(self)
	terrain.setup(self)
	content.setup(self)
	save.setup(self)
	progression.setup(self)
	add_child(progression)
	add_child(water)
	add_child(content)
	add_child(save)
	setup_environment()
	setup_crosshair()
	setup_hud()
	setup_map()
	terrain.setup_noise()
	save.load_file()      # reads your save, if there is one
	save.restore_early()  # destroyed colonies, time of day
	setup_terrain_material()
	setup_ghost()

	generate_terrain()

	create_storage()

	ant = Ant.new()
	add_child(ant)
	pheromone = Pheromone.new()
	pheromone.ant = ant
	add_child(pheromone)
	sky_life = SkyLife.new()
	add_child(sky_life)
	far_terrain = FarTerrain.new()
	far_terrain.height_fn = terrain.ground_height
	far_terrain.kind_fn = terrain.surface_kind
	far_terrain.edge_fn = terrain.edge_dist
	far_terrain.biome_fn = terrain.biome_at
	far_terrain.lake_fn = terrain.far_lake_level
	far_terrain.mounds_fn = terrain.far_mounds
	far_terrain.river_width = float(RIVER_WIDTH)
	far_terrain.river_level = RIVER_LEVEL
	add_child(far_terrain)
	setup_headlamp()   # needs the ant's camera, which exists once the ant is in the scene
	ant.position = storage_pos + Vector3(-6, 15, 0)
	ant.deposit_requested.connect(_on_deposit)
	ant.water_surface = water.water_surface_at

	print_nearest_mounds()
	print_nearest_lakes()
	if save.has_save:
		save.restore_ant()
		save.restore_map()
	preload_world(ant.global_position if save.has_save else Vector3(2, SURFACE_BASE, 8))   # build the ground around you before the game opens

	crafting = Crafting.new()
	crafting.ant = ant
	add_child(crafting)
	storage_ui = StorageUI.new()
	storage_ui.ant = ant
	add_child(storage_ui)
	crafting.progression = progression
	save.restore_crafting()
	compass.setup(self)
	add_child(compass)
	setup_spray()
	build_class_menu()
	setup_douse()
	ant.died.connect(func(): show_message("You were killed. Respawned at your queen." if is_instance_valid(queen) else "You were killed. Respawned at the start."))
	ant.dash_hit_creature.connect(func(_c): show_message("Dash hit!"))
	crafting.crafted.connect(func(t: String): show_message("Crafted %s. It is in your hotbar." % Crafting.RECIPES[t]["label"]))

# ---------- Per-frame updates ----------

func _process(delta: float) -> void:
	ant.controls_locked = crafting.is_open or storage_ui.is_open or class_menu_open
	rock_cd -= delta
	update_class_menu()
	ant.has_queen = is_instance_valid(queen)
	update_cover(delta)
	update_daynight(delta)
	water_tint.visible = water.camera_underwater()
	if ant.health < last_health - 0.01:
		flash_rect.color.a = 0.4   # flash red when hurt
	last_health = ant.health
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - delta * 1.5)
	handle_dig(delta)
	update_brush_preview()
	handle_spray(delta)
	handle_fire(delta)
	stream_world(delta)
	update_biome(delta)
	process_grey()
	update_map(delta)
	process_remesh_queue()
	water.handle_water(delta)
	water.refresh_water(delta)

	message_time -= delta
	var inv := ant.inventory
	var cap := int(ant.carry_cap("sugar"))
	var hours := fposmod(6.0 + day_time * 24.0, 24.0)
	var text := "[%s ant]   Day %d   %02d:%02d   %s\n" % [Ant.ROLE_NAMES[ant.role], day_count, int(hours), int((hours - floorf(hours)) * 60.0), BIOME_NAMES[current_biome]]
	text = text.rstrip("\n") + "\n"
	for k in res_rows:
		var have := 0
		if k == "soil":
			have = int(ant.soil)
		elif k == "water":
			have = int(ant.water)
		elif k == "rock":
			have = ant.rocks
		else:
			have = int(inv[k])
		var limit := int(ant.carry_cap(k)) if k != "sugar" else cap
		if k == "soil":
			limit = int(ant.soil_cap())
		elif k == "water":
			limit = int(ant.water_cap())
		res_rows[k]["carry"].text = "%d/%d" % [have, limit]
		res_rows[k]["stored"].text = "-" if k == "rock" else str(stored(k))

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
				text += "[Mouse wheel or [ ]] dig size   [Ctrl] dash (A/D/S + Ctrl to dodge)   [E at queen] change class"
				if ant.role == 1:
					text += "   [Y] soil to rock   [V] throw rock"
				text += "\n"
				text += "[Shift] sprint   [C] craft   [1-9] hold item   [B] build   [M] map   [U] termite tracker   [F5] save   [L] pheromone trail   [O] wipe trail   [N] skip 3 hours   [K] respawn   [F1] hide help"
			else:
				text += "[F1] controls   [M] map   [C] craft   [B] build"
			text += "\n" + progression.hud_line()
			var track_line := progression.tracker_line()
			if track_line != "":
				text += "\n" + track_line
			if pheromone.laying:
				text += "\nTRAIL ON  ([L] to stop)"

	if not water.water_source.is_empty():
		text += "\n[Hold F] drink water"
	if message_time > 0.0:
		text += "\n" + message
	hud.text = text
	hud.visible = not (crafting.is_open or storage_ui.is_open)
	res_panel.visible = hud.visible

	soil_bar.max_value = ant.soil_cap()
	water_bar.max_value = ant.water_cap()
	health_bar.max_value = ant.max_health
	soil_bar.value = ant.soil
	(soil_bar.get_child(0) as Label).text = "Soil  %d / %d" % [int(ant.soil), int(ant.soil_cap())]
	water_bar.value = ant.water
	(water_bar.get_child(0) as Label).text = "Water  %d / %d" % [int(ant.water), int(ant.water_cap())]
	health_bar.value = ant.health
	(health_bar.get_child(0) as Label).text = "Health  %d / %d" % [int(ant.health), int(ant.max_health)]
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
		if class_menu_open:
			if event.keycode == KEY_E and Engine.get_process_frames() == class_open_frame:
				return   # this is the same key press that just opened the menu
			if event.keycode == KEY_E or event.keycode == KEY_ESCAPE:
				close_class_menu()
			elif event.keycode == KEY_1:
				choose_role(0)
			elif event.keycode == KEY_2:
				choose_role(1)
			return
		if storage_ui.is_open:
			if event.keycode == KEY_E:
				if Engine.get_process_frames() == storage_open_frame:
					return   # this is the same key press that just opened the box
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
			KEY_BRACKETLEFT:
				change_brush(-BRUSH_STEP)
			KEY_BRACKETRIGHT:
				change_brush(BRUSH_STEP)
			KEY_Y:
				convert_soil_to_rock()
			KEY_V:
				throw_rock()
			KEY_N:
				day_time = fposmod(day_time + 0.125, 1.0)
			KEY_M:
				world_map.visible = not world_map.visible
			KEY_L:
				if pheromone.toggle():
					show_message("Pheromone trail ON. You are leaving a faint scent mist. Press L to stop.")
				else:
					show_message("Pheromone trail off. Your old trail fades over time.")
			KEY_O:
				pheromone.clear_trail()
				show_message("Your trail was wiped away.")
			KEY_P:
				TermiteSoldier.passive = not TermiteSoldier.passive
				show_message("Termite soldiers are now passive. They will not attack." if TermiteSoldier.passive else "Termite soldiers are hostile again.")
			KEY_Z:
				if world_map.visible:
					world_map.cycle_zoom()
			KEY_U:
				if progression.toggle_tracker():
					show_message("Termite tracker on. Its direction shows below the controls.")
				else:
					show_message("Termite tracker off.")
			KEY_TAB:
				progression.toggle()
			KEY_F5:
				save.save_now()
			KEY_F9:
				if event.shift_pressed:
					show_message("Starting a new world...")
					save.new_world()
			KEY_F1:
				show_help = not show_help
			KEY_K:
				ant.respawn()
				show_message("Respawned at your queen." if is_instance_valid(queen) else "Respawned at the start. Place a queen to set your spawn.")

	if event is InputEventMouseButton and event.pressed:
		if crafting.is_open or storage_ui.is_open or class_menu_open:
			return   # a menu is open, so clicks belong to it
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not build_mode:
				change_brush(BRUSH_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else -BRUSH_STEP)
			return
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
	var reach := brush if digging else brush * (SMOOTH_RADIUS / DIG_RADIUS)
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
	var clear_radius := brush * (SMOOTH_RADIUS / DIG_RADIUS) + 1.0
	if digging:
		if has_last_dig and last_dig_point.distance_to(point) < 0.5:
			return   # barely moved, skip
		var from := point
		if has_last_dig and last_dig_point.distance_to(point) < 6.0:
			from = last_dig_point   # connect to the previous point
		dirty = world.dig_capsule(from, point, brush)
		var gained := world.last_removed * SOIL_PER_VOLUME
		if gained > 0.0:
			if ant.soil + gained > ant.soil_cap():
				show_message("Soil full. Extra is lost.")
			ant.soil = minf(ant.soil_cap(), ant.soil + gained)
		last_dig_point = point
		has_last_dig = true
		clear_radius = brush + 2.0
	else:
		dirty = world.smooth_sphere(point, brush * (SMOOTH_RADIUS / DIG_RADIUS))

	dig_cooldown = DIG_INTERVAL
	mark_edited(dirty)
	queue_remesh(dirty, point)
	clear_decor_near(point, clear_radius)
	content.wake_pickups(point, clear_radius)
	water.mark_water_dirty(point, clear_radius)

# A see-through ball at the aim point shows how big a hole you will dig.
func update_brush_preview() -> void:
	if brush_preview == null:
		brush_preview = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 24
		sm.rings = 12
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.95, 0.7, 0.18)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = false
		sm.material = mat
		brush_preview.mesh = sm
		brush_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		brush_preview.visible = false
		add_child(brush_preview)
	brush_show -= get_process_delta_time()
	var on := brush_show > 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not build_mode and crafting.held_type() == "" \
			and not ant.controls_locked and not ant.swimming
	if not on:
		brush_preview.visible = false
		return
	var cam := ant.camera
	var hit = world.raycast(cam.global_position, -cam.global_transform.basis.z, REACH)
	if hit == null:
		brush_preview.visible = false
		return
	var point: Vector3 = hit
	var smoothing := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var filling := Input.is_key_pressed(KEY_X)
	var r := brush
	var mat2 := (brush_preview.mesh as SphereMesh).material as StandardMaterial3D
	if smoothing:
		r = brush * (SMOOTH_RADIUS / DIG_RADIUS)
		mat2.albedo_color = Color(0.6, 0.8, 1.0, 0.18)
	elif filling:
		r = FILL_RADIUS * brush / DIG_RADIUS
		point -= -cam.global_transform.basis.z * r * 0.7
		mat2.albedo_color = Color(0.7, 0.5, 0.3, 0.22)
	else:
		mat2.albedo_color = Color(1.0, 0.95, 0.7, 0.18)
	var fade := clampf(brush_show / 0.7, 0.0, 1.0)   # fades out over the last 0.7 seconds
	mat2.albedo_color.a *= fade
	brush_preview.global_position = point
	brush_preview.scale = Vector3.ONE * r
	brush_preview.visible = true

func change_brush(amount: float) -> void:
	brush = clampf(snappedf(brush + amount, 0.1), BRUSH_MIN, ant.stat("dig_max"))
	brush_show = BRUSH_SHOW_TIME

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
	var fr := FILL_RADIUS * brush / DIG_RADIUS
	var center := point - aim.normalized() * fr * 0.7
	if ant.global_position.distance_to(center) < fr + 0.9 \
			or (ant.global_position + ant.basis.y * 0.4).distance_to(center) < fr + 0.9:
		show_message("You are in the way. Step back to fill here.")
		dig_cooldown = 0.6
		return
	var dirty := world.fill_sphere(center, fr)
	if dirty.is_empty():
		return
	ant.soil = maxf(0.0, ant.soil - world.last_added * SOIL_PER_VOLUME)
	ant.water = maxf(0.0, ant.water - world.last_added * WATER_PER_FILL)
	dig_cooldown = DIG_INTERVAL
	mark_edited(dirty)
	queue_remesh(dirty, center)
	content.wake_pickups(center, fr + 1.0)
	water.mark_water_dirty(center, fr + 1.0)

# Only a thin slab of ground is locked, so water and trees always have something under them.
# Pools and pockets lock the layer under their water, and trees and boulders lock the ground
# just under their base. Everything deeper, and everything beside them, is diggable.
const POOL_LOCK_DEPTH := 3.0       # how far below a pool or pocket floor stays solid
const OBSTACLE_LOCK_DEPTH := 5.0   # how far below a tree or boulder base stays solid

# True if a dig of this radius at this point would cut into one of those locked slabs.
func is_protected(point: Vector3, radius: float) -> bool:
	var top := point.y + radius      # the highest and lowest points the dig reaches
	var bottom := point.y - radius

	for p in terrain.pools_at(point.x, point.z):
		var reach := float(p["radius"]) * (1.12 if p.get("lake", false) else 1.4) + radius
		if terrain.pool_dist(p, point.x, point.z) < reach \
				and top > float(p["floor"]) - POOL_LOCK_DEPTH and bottom < float(p["level0"]) + 0.5:
			return true

	if terrain.edge_dist(point.x, point.z) < RIVER_WIDTH + radius and top > RIVER_BED_Y - POOL_LOCK_DEPTH and bottom < RIVER_LEVEL + 0.5:
		return true   # the riverbed stays, so the river keeps its water

	# The royal cell has thick walls while its colony lives: the only way in is the guarded antechamber.
	var mm := terrain.mound_near(point.x, point.z)
	if not mm.is_empty() and not bool(mm["dead"]):
		var rc: Vector3 = mm["royal"]
		var rr: Vector3 = mm["royal_r"]
		var rq := Vector3((point.x - rc.x) / rr.x, (point.y - rc.y) / rr.y, (point.z - rc.z) / rr.z)
		if (rq.length() - 1.0) * 6.6 < ROYAL_WALL + radius:
			return true

	for p in terrain.pockets_at_cell(Vector2i(floori(point.x / POCKET_CELL), floori(point.z / POCKET_CELL))):
		var pos: Vector3 = p["pos"]
		var r: Vector3 = p["radii"]
		var q := Vector2((point.x - pos.x) / (r.x * 1.3 + radius), (point.z - pos.z) / (r.z * 1.3 + radius))
		if q.length() < 1.0 and top > float(p["floor"]) - POOL_LOCK_DEPTH and bottom < float(p["level"]):
			return true

	for o in content.obstacles_near(point.x, point.z):
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
	spawn_piece(type, ghost_xform)

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
	spawn_placeable(held, ghost_xform)
	if held == "queen":
		show_message("The queen is placed. You will respawn here.")
	crafting.consume_held()

# Makes one placed item (box, barrel, lamp, queen, trap) and wires it up. Used when you place one and when a save loads.
func spawn_placeable(type: String, xform: Transform3D) -> Placeable:
	var p := Placeable.new()
	p.type = type
	p.world = world
	p.moved.connect(_on_placeable_moved)
	if Placeable.DEFENSE.has(type):
		p.collapsed.connect(_on_trap_collapsed)
	p.add_to_group("placeables")
	add_child(p)
	p.global_transform = xform
	if type == "queen":
		queen = p
		p.destroyed.connect(_on_queen_destroyed)
		p.attacked.connect(_on_queen_attacked)
		ant.spawn_point = p.global_position + Vector3(0, 2.5, 0)
	return p

func spawn_piece(type: String, xform: Transform3D) -> Piece:
	var p := Piece.new()
	p.type = type
	p.add_to_group("pieces")
	add_child(p)
	p.global_transform = xform
	return p

var queen_alarm_cd := 0.0

# A collapse trap went off: soil drops and fills the spot, sealing the tunnel.
func _on_trap_collapsed(center: Vector3, radius: float) -> void:
	if ant.global_position.distance_to(center) < radius + 1.6:
		show_message("A collapse trap went off beside you, but you were too close for it to bury the tunnel.")
		return
	var dirty := world.fill_sphere(center, radius)
	if dirty.is_empty():
		return
	mark_edited(dirty)
	queue_remesh(dirty, center)
	content.wake_pickups(center, radius + 1.0)
	water.mark_water_dirty(center, radius + 1.0)
	show_message("A collapse trap sealed the tunnel!")

# A placed item fell after the ground under it was dug away. If it is the queen, respawn moves with her.
func _on_placeable_moved(p: Placeable) -> void:
	if p == queen:
		ant.spawn_point = p.global_position + Vector3(0, 2.5, 0)

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
	var all_boxes := get_tree().get_nodes_in_group("containers")
	for c in all_boxes:
		var d := ant.global_position.distance_to((c as Placeable).global_position)
		if d < best_d:
			best_d = d
			best = c
	if is_instance_valid(queen) and ant.global_position.distance_to(queen.global_position) < QUEEN_MENU_RANGE \
			and (best == null or ant.global_position.distance_to(queen.global_position) < best_d):
		dig_lock = true
		open_class_menu()
		return
	if best == null:
		if is_instance_valid(queen):
			show_message("Too far from your queen (%.1f away, need under %.0f)." % [ant.global_position.distance_to(queen.global_position), QUEEN_MENU_RANGE])
		else:
			show_message("No box or barrel nearby, and no queen placed. Press E next to your own queen to change class.")
		return
	dig_lock = true
	storage_open_frame = Engine.get_process_frames()
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

func generate_terrain() -> void:
	terrain.generate_river()
	# Pools and pockets are made per square as the ant gets near, and the terrain itself is
	# generated the same way. See the streaming section.

# The lowest chunk layer a column gets generated down to before you are near it.
var col_deep_from := {}   # column -> its lowest generated layer (CY_MIN once the deep ground is done too)
var deep_wanted: Array = []

# The deep ground of a column was just generated, so it and its neighbors are drawn again to include it.
func finish_deep(col: Vector2i) -> void:
	col_deep_from[col] = CY_MIN
	content.spawn_cave_contents(col)
	var list: Array = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var n := col + Vector2i(dx, dz)
			if col_meshed.has(n):
				for cy in range(CY_MIN, HEIGHT_CHUNKS):
					if world.chunks.has(Vector3i(n.x, cy, n.y)):
						list.append(Vector3i(n.x, cy, n.y))
	if not list.is_empty():
		queue_remesh(list, remesh_focus)

func setup_terrain_material() -> void:
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	# The detailed ground melts away into the distant land with a fine dither, so it never pops in.
	# (Max is smaller than min on purpose: fully solid up to max, fully gone at min.)
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	material.distance_fade_max_distance = TERRAIN_FADE_START
	material.distance_fade_min_distance = TERRAIN_FADE_END

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
	storage_pos = Vector3(STORAGE_XZ.x, terrain.ground_height(STORAGE_XZ.x, STORAGE_XZ.y), STORAGE_XZ.y)

# ---------- Day and night ----------

const MIN_DARK := 0.015        # how much sky light is left in total darkness (0 = pitch black)
const HEADLAMP_ENERGY := 0.5   # your own glow, so you can see a little when it is dark. 0 removes it.

var openness := 1.0            # 1 = open sky above you, 0 = buried
var openness_target := 1.0
var cover_timer := 0.0
var headlamp: OmniLight3D

func setup_headlamp() -> void:
	headlamp = OmniLight3D.new()
	headlamp.light_color = Color(1.0, 0.85, 0.6)
	headlamp.omni_range = 18.0
	headlamp.omni_attenuation = 1.4
	headlamp.shadow_enabled = true
	headlamp.shadow_bias = 0.08          # stops the dark flecks that shadows can leave on nearby walls
	headlamp.shadow_normal_bias = 2.0
	headlamp.light_energy = 0.0
	headlamp.visible = false
	ant.camera.add_child(headlamp)
	headlamp.position = Vector3(0, 0.3, -0.6)

# Checks how much solid ground is over your head: one ray straight up and four slanted ones.
func update_cover(delta: float) -> void:
	cover_timer -= delta
	if cover_timer <= 0.0:
		cover_timer = 0.15
		var o := ant.camera.global_position
		var open := 0
		var dirs := [Vector3.UP, Vector3(1, 1.2, 0), Vector3(-1, 1.2, 0), Vector3(0, 1.2, 1), Vector3(0, 1.2, -1)]
		for d in dirs:
			if world.raycast(o, d, 45.0, 1.0) == null:
				open += 1
		openness_target = float(open) / float(dirs.size())
	openness = move_toward(openness, openness_target, delta * 2.0)


# Moves the sun, recolors the sky, and sends fireflies out at dusk.
# Morning mist: thick at dawn, thin by midday, a little at dusk. Swamps and forests get the most.
# With VOLUMETRIC_MIST on, the mist also catches the low sun and shows light shafts between trees.
const VOLUMETRIC_MIST := true
const MIST_BY_BIOME := [0.8, 0.1, 0.7, 0.5, 1.0, 0.35]   # forest, desert, highlands, tundra, swamp, savanna
var mist_now := 0.0

const MOON_ENERGY := 0.6   # how bright the moon is. Raise for brighter nights.

func update_mist(delta: float, h: float, phase: float) -> void:
	var low_sun := 1.0 - smoothstep(0.0, 0.4, absf(h))
	var morning := 1.0 if cos(phase) > 0.0 else 0.3
	var target := low_sun * morning * float(MIST_BY_BIOME[clampi(current_biome, 0, 5)]) * openness
	mist_now = lerpf(mist_now, target, minf(1.0, delta * 0.5))
	if "fog_depth_end" in env:
		env.set("fog_depth_end", lerpf(content.FOG_FULL_AT, content.FOG_FULL_AT * 0.4, mist_now))
	env.fog_light_color = env.fog_light_color.lerp(Color(0.85, 0.85, 0.82), mist_now * 0.5)
	if VOLUMETRIC_MIST and "volumetric_fog_enabled" in env:
		env.set("volumetric_fog_enabled", mist_now > 0.05)
		env.set("volumetric_fog_density", 0.012 * mist_now)
		env.set("volumetric_fog_albedo", Color(0.9, 0.88, 0.8))
		env.set("volumetric_fog_length", 90.0)
		env.set("volumetric_fog_anisotropy", 0.6)

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
	sky_life.moon_dir = moon.global_transform.basis.z
	sky_life.update(delta, ant.camera.global_position, horizon * biome_tint, day, warm, current_biome, openness)
	env.ambient_light_energy = lerpf(0.3, 0.75, day)
	env.ambient_light_color = Color(0.3, 0.4, 0.7).lerp(Color(0.82, 0.82, 0.78), day)   # neutral by day, so shade stays grey, not blue

	sun.rotation_degrees = Vector3(-rad_to_deg(phase), -30.0, 0.0)
	sun.light_energy = 1.3 * smoothstep(-0.02, 0.25, h)
	update_mist(delta, h, phase)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.3), warm) * biome_tint
	sun.shadow_enabled = h > 0.02
	moon.rotation_degrees = Vector3(-rad_to_deg(phase) + 180.0, -30.0, 0.0)
	moon.light_energy = MOON_ENERGY * smoothstep(0.0, 0.3, -h)
	moon.shadow_enabled = h < -0.05   # moonlight casts shadows too, so the night has shape
	env.glow_intensity = lerpf(1.0, 0.6, day)                 # emissive things (glow mushrooms, fireflies) bloom more at night
	env.glow_hdr_threshold = lerpf(0.7, 1.0, day)

	# Underground it is dark: the sky's light only reaches you in proportion to how open the sky is above you.
	var lit := lerpf(MIN_DARK, 1.0, openness * openness)   # squared, so even a little cover darkens quickly
	env.ambient_light_energy *= lit
	env.fog_light_color *= lerpf(0.15, 1.0, openness)
	sun.light_energy *= openness
	moon.light_energy *= openness
	headlamp.light_energy = HEADLAMP_ENERGY * (1.0 - openness)
	headlamp.visible = openness < 0.97

	# Fireflies come out as the light fades, and go to sleep at dawn.
	var night := day < 0.45
	if night != night_creatures:
		night_creatures = night
		for c in get_tree().get_nodes_in_group("creatures"):
			if (c as Creature).nocturnal:
				(c as Creature).set_active(night)
			elif (c as Creature).diurnal:
				(c as Creature).set_active(not night)

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

	var spray_reach := SPRAY_RANGE * ant.stat("spray_range")
	var cone_cos := minf(0.96, 0.88 + 0.04 * (ant.stat("spray_range") - 1.0))
	var cone_tan := sqrt(1.0 - cone_cos * cone_cos) / cone_cos
	for c in get_tree().get_nodes_in_group("creatures"):
		var cr := c as Creature
		if not cr.active:
			continue
		# Is any part of the creature inside the spray? A big body (the termite queen) counts by its whole size, not just its middle.
		var to_c: Vector3 = cr.hit_center() - origin
		var along := to_c.dot(aim)
		if along <= 0.01 or along > spray_reach + cr.hit_radius:
			continue
		var off_axis := (to_c - aim * along).length()
		if off_axis < along * cone_tan + cr.hit_radius:
			cr.take_damage(SPRAY_DPS * ant.stat("spray_dmg") * delta)

# ---------- Ant classes ----------
# Press E next to your queen to pick a class. Worker: fast, carries a lot. Soldier: tough,
# strong long acid spray, carries only soil and water, and turns soil into rocks to throw.

func open_class_menu() -> void:
	refresh_class_menu()
	class_layer.visible = true
	class_menu_open = true
	class_open_frame = Engine.get_process_frames()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_class_menu() -> void:
	class_menu_open = false
	dig_lock = true
	if class_layer != null:
		class_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func update_class_menu() -> void:
	if class_menu_open and (not is_instance_valid(queen) or ant.global_position.distance_to(queen.global_position) > QUEEN_MENU_RANGE + 2.0):
		close_class_menu()

func build_class_menu() -> void:
	class_layer = CanvasLayer.new()
	class_layer.layer = 6
	class_layer.visible = false
	add_child(class_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.05, 0.95)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Your queen can change what kind of ant you are"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var descs := [
		"WORKER  [1]\nQuickest ant. Carries a lot of every resource and picks things up from further away. Average acid spray.",
		"SOLDIER  [2]\nTougher, with a longer health bar and a powerful long acid spray. Carries only soil and water, eats sugar on the spot. Press Y to turn soil into rocks, V to throw them.",
	]
	class_buttons.clear()
	for i in 2:
		var b := Button.new()
		b.custom_minimum_size = Vector2(540, 96)
		b.pressed.connect(choose_role.bind(i))
		var l := Label.new()
		l.text = descs[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.offset_left = 12.0
		l.offset_right = -12.0
		l.offset_top = 8.0
		l.offset_bottom = -8.0
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)
		box.add_child(b)
		class_buttons.append(b)
	var hint := Label.new()
	hint.text = "Anything your new class cannot carry is dropped next to you. Press E or Esc to close."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(540, 0)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(hint)

func refresh_class_menu() -> void:
	for i in class_buttons.size():
		var b := class_buttons[i] as Button
		b.disabled = (i == ant.role)   # the class you already are is greyed out

func choose_role(i: int) -> void:
	if i == ant.role:
		return
	var overflow := ant.set_role(i)
	var dropped := 0
	for k in overflow:
		var n := int(overflow[k])
		if n <= 0:
			continue
		dropped += n
		var p := Pickup.new()
		p.kind = k
		p.amount = n
		add_child(p)
		p.global_position = ant.global_position + Vector3(randf_range(-1.5, 1.5), 0.6, randf_range(-1.5, 1.5))
	apply_spray_role()
	brush = minf(brush, ant.stat("dig_max"))
	var msg := "You are now a %s ant." % Ant.ROLE_NAMES[i]
	if dropped > 0:
		msg += " You dropped %d items you cannot carry." % dropped
	show_message(msg)
	close_class_menu()

# Longer range for soldiers: the drops fly faster and live longer.
func apply_spray_role() -> void:
	var m: float = ant.stat("spray_range")
	spray.initial_velocity_min = 13.0 * m
	spray.initial_velocity_max = 17.0 * m
	spray.lifetime = 0.45 * (1.0 + 0.35 * (m - 1.0))

func convert_soil_to_rock() -> void:
	if ant.role != 1 or build_mode or ant.controls_locked:
		return
	if ant.rocks >= Ant.ROCK_CAP:
		show_message("You cannot carry more rocks.")
	elif ant.soil < SOIL_PER_ROCK:
		show_message("You need %d soil to make a rock." % int(SOIL_PER_ROCK))
	else:
		ant.soil -= SOIL_PER_ROCK
		ant.rocks += 1

func throw_rock() -> void:
	if ant.role != 1 or build_mode or ant.controls_locked or rock_cd > 0.0:
		return
	if ant.rocks <= 0:
		show_message("No rocks. Press Y to turn soil into rocks.")
		return
	ant.rocks -= 1
	rock_cd = ROCK_COOLDOWN
	var aim := -ant.camera.global_transform.basis.z
	var rock := RockShot.new()
	rock.world = world
	rock.damage = ROCK_DAMAGE
	rock.velocity = (aim + Vector3(0, 0.12, 0)).normalized() * ROCK_SPEED
	add_child(rock)
	rock.global_position = ant.global_position + ant.basis.y * 0.9 + aim * 1.2

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
	if water.water_surface_at(pos + Vector3(0, 0.3, 0)) > -1.0e8:
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
	if absf(x) > HALF - 1.0 or absf(z) > HALF - 1.0 or terrain.surface_kind(x, z) != Blocks.GRASS:
		return
	var hit = world.raycast(Vector3(x, from.y + 4.0, z), Vector3.DOWN, 10.0)
	if hit == null:
		return
	spawn_fire((hit as Vector3) + Vector3(0, 0.15, 0))

func spawn_firefly(pos: Vector3) -> void:
	var f := Firefly.new()
	f.ant = ant
	f.ground_at = terrain.ground_height
	f.home = pos
	f.died.connect(_on_creature_died)
	region_node(region_key(pos.x, pos.z)).add_child(f)
	f.global_position = pos
	f.set_active(night_creatures)

func spawn_spider(pos: Vector3) -> void:
	var sp := Spider.new()
	sp.ant = ant
	sp.queen_getter = func(): return queen
	sp.ground_at = terrain.ground_height
	sp.is_loaded = ground_ready
	sp.home = pos
	sp.died.connect(_on_creature_died)
	region_node(region_key(pos.x, pos.z)).add_child(sp)
	sp.global_position = pos
	sp.set_active(night_creatures)

# Brings a creature back, unless its region has been forgotten (a new one appears with the region).
func respawn_creature(home: Vector3, kind: String) -> void:
	if not region_done.has(region_key(home.x, home.z)):
		return
	match kind:
		"firefly":
			spawn_firefly(home)
		"spider":
			spawn_spider(home)
		"beetle":
			spawn_beetle(home)
		"centipede":
			spawn_centipede(home)

func spawn_beetle(pos: Vector3) -> void:
	var b := Beetle.new()
	b.ant = ant
	b.queen_getter = func(): return queen
	b.ground_at = terrain.ground_height
	b.is_loaded = ground_ready
	b.home = pos
	b.died.connect(_on_creature_died)
	region_node(region_key(pos.x, pos.z)).add_child(b)
	b.global_position = pos
	b.set_active(not night_creatures)

func spawn_centipede(pos: Vector3) -> void:
	var c := Centipede.new()
	c.ant = ant
	c.queen_getter = func(): return queen
	c.ground_at = terrain.ground_height
	c.is_loaded = ground_ready
	c.home = pos
	c.died.connect(_on_creature_died)
	region_node(region_key(pos.x, pos.z)).add_child(c)
	c.global_position = pos
	c.set_active(night_creatures)

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
	if c is TermiteQueen:
		colony_destroyed((c as TermiteQueen).colony)
		return
	elif c is TermiteWorker:
		var wc: Dictionary = (c as TermiteWorker).colony
		wc["workers"] = maxi(0, int(wc["workers"]) - 1)
		return
	elif c is TermiteSoldier:
		var sc: Dictionary = (c as TermiteSoldier).colony
		sc["soldiers"] = maxi(0, int(sc["soldiers"]) - 1)
		return
	if c is Firefly:
		get_tree().create_timer(FIREFLY_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "firefly"))
	elif c is Spider:
		get_tree().create_timer(SPIDER_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "spider"))
	elif c is Beetle:
		get_tree().create_timer(BEETLE_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "beetle"))
	elif c is Centipede:
		get_tree().create_timer(CENTIPEDE_RESPAWN_SECONDS).timeout.connect(respawn_creature.bind(home, "centipede"))

# Prints the closest mounds to the start in the Output panel, so you can walk straight to one.
func print_nearest_mounds() -> void:
	var found := []
	for cx in range(-12, 13):
		for cz in range(-12, 13):
			var m := terrain.mound_at_cell(Vector2i(cx, cz))
			if not m.is_empty():
				found.append(Vector2(float(m["x"]), float(m["z"])))
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	print("Nearest termite mounds (x, z):")
	for i in mini(6, found.size()):
		print("  ", found[i].round(), "  distance ", int(found[i].length()))

func print_nearest_lakes() -> void:
	var found := []
	for cx in range(-4, 5):
		for cz in range(-4, 5):
			for lk in terrain.pools_at((float(cx) + 0.5) * POOL_CELL, (float(cz) + 0.5) * POOL_CELL):
				if lk.get("lake", false):
					found.append(Vector2(float(lk["x"]), float(lk["z"])))
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	print("Nearest lakes (x, z):")
	for i in mini(5, found.size()):
		print("  ", found[i].round(), "  distance ", int(found[i].length()))

# ---------- Termite colonies ----------
# When the region holding a mound is built, its colony moves in: the queen in her cell, a few
# soldiers at the guard posts, and workers. The queen keeps laying more (up to a limit). When
# she dies the colony is finished: nothing more spawns, what is left fades, and the mound
# turns grey.

const GREY_CHUNKS_PER_FRAME := 2

func region_colony(job: Dictionary) -> void:
	var rect := region_rect(job["key"])
	var seen := {}
	for corner in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y), rect.end]:
		var cell := Vector2i(floori(corner.x / MOUND_CELL), floori(corner.y / MOUND_CELL))
		if seen.has(cell):
			continue
		seen[cell] = true
		var m := terrain.mound_at_cell(cell)
		if m.is_empty():
			continue
		if rect.has_point(Vector2(float(m["x"]), float(m["z"]))):
			spawn_colony(m, job["key"])

func spawn_colony(m: Dictionary, key: Vector2i) -> void:
	m["workers"] = 0
	m["soldiers"] = 0
	if m["dead"]:
		return
	var rn := region_node(key)
	var q := TermiteQueen.new()
	q.colony = m
	q.spawn_cb = spawn_termite
	TermiteQueen.ward_message = func(): show_message("A shimmering ward protects the Great Mound queen. Gather biome relics to break it.")
	q.is_loaded = ground_ready
	q.ant = ant
	q.home = m["queen_pos"]
	q.died.connect(_on_creature_died)
	rn.add_child(q)
	q.global_position = m["queen_pos"]
	q.rotation.y = 0.6
	# Dim lights so the royal cell and the great hall are not pitch black.
	for lp in [Vector3(m["royal"]), Vector3(m["hall"])]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.light_energy = 1.2
		l.omni_range = 16.0
		rn.add_child(l)
		l.global_position = lp + Vector3(0, 2.0, 0)
	for i in (14 if m.get("great", false) else 6):
		spawn_termite(m, "soldier")
	for i in 4:
		spawn_termite(m, "worker")

func spawn_termite(m: Dictionary, kind: String) -> void:
	if m["dead"]:
		return
	var key := region_key(float(m["x"]), float(m["z"]))
	if not region_nodes.has(key):
		return
	var rn := region_node(key)
	var c: Crawler
	var pos: Vector3
	if kind == "soldier":
		var s := TermiteSoldier.new()
		s.colony = m
		var posts: Array = m["posts"]
		pos = posts[randi() % posts.size()]
		m["soldiers"] = int(m["soldiers"]) + 1
		c = s
	else:
		var w := TermiteWorker.new()
		w.colony = m
		w.wander_min = float(m["R"]) + 6.0
		w.wander_radius = 45.0
		pos = m["entrance_in"]
		m["workers"] = int(m["workers"]) + 1
		c = w
	c.ant = ant
	c.queen_getter = func(): return null
	c.ground_at = terrain.ground_height
	c.is_loaded = ground_ready
	c.home = pos if kind == "soldier" else Vector3(m["center"])
	c.died.connect(_on_creature_died)
	rn.add_child(c)
	c.global_position = pos + Vector3(randf_range(-1.0, 1.0), 0.6, randf_range(-1.0, 1.0))

func colony_destroyed(m: Dictionary) -> void:
	if m["dead"]:
		return
	m["alive"] = false
	m["dead"] = true
	progression.colony_destroyed(m)
	show_message("The termite queen is dead. The colony is finished!")
	# Everything the workers stored spills out of the royal cell, plus a reward of sugar.
	var qp: Vector3 = m["queen_pos"]
	var stock: Dictionary = m["stock"]
	stock["sugar"] = int(stock.get("sugar", 0)) + 6
	for k in stock:
		var left := int(stock[k])
		while left > 0:
			var n := mini(left, 4)
			left -= n
			var p := Pickup.new()
			p.kind = k
			p.amount = n
			add_child(p)
			p.global_position = qp + Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
		stock[k] = 0
	# Queue every loaded chunk of the mound to turn grey.
	var center: Vector3 = m["center"]
	var reach := float(m["R"]) + 30.0
	var lo := Vector2i(floori((center.x - reach) / Chunk.SIZE), floori((center.z - reach) / Chunk.SIZE))
	var hi := Vector2i(floori((center.x + reach) / Chunk.SIZE), floori((center.z + reach) / Chunk.SIZE))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			for cy in range(CY_MIN, HEIGHT_CHUNKS):
				var cp := Vector3i(cx, cy, cz)
				if world.chunks.has(cp):
					grey_jobs.append(cp)

func process_grey() -> void:
	var n := 0
	while not grey_jobs.is_empty() and n < GREY_CHUNKS_PER_FRAME:
		var cp: Vector3i = grey_jobs.pop_front()
		var ch: Chunk = world.get_chunk(cp)
		if ch == null:
			continue
		var changed := false
		for lx in Chunk.SIZE:
			for ly in Chunk.SIZE:
				for lz in Chunk.SIZE:
					if ch.get_material(lx, ly, lz) == Blocks.MOUND:
						ch.set_voxel(lx, ly, lz, ch.get_density(lx, ly, lz), Blocks.DEAD_MOUND)
						changed = true
		n += 1
		if changed:
			save.note_edited(cp)   # so the grey colour is kept in your save
			queue_remesh([cp], Vector3(cp * Chunk.SIZE))

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
		terrain.solid_chunks.erase(c)
		edited_cols[Vector2i(c.x, c.z)] = true
		save.note_edited(c)

# Generates terrain data a chunk at a time, within a time budget.
func gen_step(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	while true:
		if gen_job.is_empty():
			var found = null
			var deep := false
			while not deep_wanted.is_empty():   # ground right around you comes first
				var dc: Vector2i = deep_wanted.pop_front()
				if col_data.has(dc) and int(col_deep_from.get(dc, CY_MIN)) > CY_MIN:
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
			var cache := terrain.gen_column_cache(found)
			if deep:
				gen_job = {"col": found, "cy": CY_MIN, "end": int(col_deep_from[found]), "cache": cache, "deep": true}
			else:
				var first := terrain.shallow_layer(found, cache)
				col_deep_from[found] = first
				gen_job = {"col": found, "cy": first, "end": HEIGHT_CHUNKS, "cache": cache, "deep": false}
		var col: Vector2i = gen_job["col"]
		var gen_cpos := Vector3i(col.x, gen_job["cy"], col.y)
		if not save.apply_saved_chunk(gen_cpos):   # your dug version of it, if you changed it
			terrain.fill_chunk(gen_cpos, gen_job["cache"])
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
	if ant != null:
		var heading := Vector2(ant.velocity.x, ant.velocity.z)
		if heading.length() > 1.0:
			heading = heading.normalized()
			data_wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var da := Vector2(a - cc)
				var db := Vector2(b - cc)
				return da.length() - 0.6 * da.dot(heading) < db.length() - 0.6 * db.dot(heading))
	deep_wanted = []
	for c in columns_around(cc, DEEP_COLS):
		if col_data.has(c) and int(col_deep_from.get(c, CY_MIN)) > CY_MIN:
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
		for cy in range(CY_MIN, HEIGHT_CHUNKS):
			if world.chunks.has(Vector3i(c.x, cy, c.y)):
				chunks.append(Vector3i(c.x, cy, c.y))
		queue_remesh(chunks, center)

	# Un-draw columns left far behind. Their data stays.
	for c in col_meshed.keys():
		if Vector2(c - cc).length() > mesh_r + 1.5:
			col_meshed.erase(c)
			for cy in range(CY_MIN, HEIGHT_CHUNKS):
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
				if rd <= ACTIVE_COLS:
					active = true
				if rd <= GRASS_COLS:
					decor = true
		rn.visible = shown
		for ch in rn.get_children():
			if ch is MultiMeshInstance3D:
				ch.visible = decor
		rn.process_mode = Node.PROCESS_MODE_INHERIT if (shown and active) else Node.PROCESS_MODE_DISABLED

	evict_far(center, cc)

	water.stream(center)

# ---------- Forgetting what is far behind ----------
# Without this, memory would grow with every step. Far terrain, scenery and water drawings are
# thrown away and rebuilt identically if you come back. Ground you dug is never forgotten.

func evict_far(center: Vector3, cc: Vector2i) -> void:
	var done := 0
	for c in col_data.keys():
		if Vector2(c - cc).length() <= EVICT_COLS or edited_cols.has(c) or col_meshed.has(c):
			continue
		col_data.erase(c)
		col_deep_from.erase(c)
		for cy in range(CY_MIN, HEIGHT_CHUNKS):
			world.chunks.erase(Vector3i(c.x, cy, c.y))
			terrain.solid_chunks.erase(Vector3i(c.x, cy, c.y))
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

	water.forget_far(here, far)

# What the ant's biome does to it, and a message on crossing into a new one.
func update_biome(delta: float) -> void:
	biome_timer -= delta
	if biome_timer > 0.0:
		return
	biome_timer = 0.25
	var w := terrain.biome_weights(ant.global_position.x, ant.global_position.z)
	var rest := 1.0
	var mix := Color(0, 0, 0)
	for i in w.size():
		mix += (BIOME_TINT[i + 1] as Color) * w[i]
		rest -= w[i]
	biome_tint_target = mix + (BIOME_TINT[0] as Color) * maxf(rest, 0.0)
	var b := terrain.biome_at(ant.global_position.x, ant.global_position.z)
	ant.terrain_speed = BIOME_WALK_SPEED[b]
	ant.sprint_cost_mult = BIOME_SPRINT_COST[b]
	var mm := terrain.mound_near(ant.global_position.x, ant.global_position.z)
	if not mm.is_empty() and not mm["dead"]:
		var md := Vector2(ant.global_position.x - float(mm["x"]), ant.global_position.z - float(mm["z"])).length()
		if md < 70.0 and not mm["alerted"]:
			mm["alerted"] = true
			show_message("A termite mound! Soldiers guard it. Find the queen deep below.")
		elif md > 140.0:
			mm["alerted"] = false
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
	stream_update(center, 7.0, 5.0)
	gen_step(1.0e9)
	stream_update(center, 7.0, 5.0)
	gen_step(1.0e9)   # the deep ground around the start, so nothing is left to build once the game opens
	stream_update(center, 7.0, 5.0)
	content.region_step(1.0e9)
	while not remesh_queue.is_empty():
		var first: Vector3i = remesh_queue.pop_front()
		remesh_set.erase(first)
		build_chunk_node(first)

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
	content.region_step(REGION_BUDGET_MS)
	stream_timer -= delta
	if stream_timer <= 0.0:
		stream_timer = 0.3
		stream_update(ant.global_position, DATA_RADIUS, MESH_RADIUS)

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
		if terrain.is_buried_solid(nxt) or world.get_chunk(nxt) == null:
			free_chunk_node(nxt)   # deep, solid and hidden: nothing to draw
			continue
		mesh_inflight[nxt] = true
		started += 1
		WorkerThreadPool.add_task(mesh_worker.bind(nxt, SurfaceMesher.neighbors_of(world, nxt)))

func free_chunk_node(cpos: Vector3i) -> void:
	if chunk_nodes.has(cpos):
		chunk_nodes[cpos].queue_free()
		chunk_nodes.erase(cpos)

# Builds a chunk's mesh right now on this thread. Only used while the game is opening.
func build_chunk_node(cpos: Vector3i) -> void:
	free_chunk_node(cpos)
	if terrain.is_buried_solid(cpos):
		return
	apply_chunk_mesh(cpos, SurfaceMesher.build(world, cpos))

func apply_chunk_mesh(cpos: Vector3i, mesh: ArrayMesh) -> void:
	free_chunk_node(cpos)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = Vector3(cpos * Chunk.SIZE)
	add_child(mi)
	chunk_nodes[cpos] = mi
	# Ground near you is solid. Far ground is only a picture until you get close.
	if ant == null or chunk_dist(cpos, col_of(ant.global_position)) <= COLLISION_COLS:
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
		if d <= COLLISION_COLS:
			if not mi.has_meta("solid") and added < 8:
				attach_collision(mi)
				added += 1
		elif d > COLLISION_COLS + 2.0 and mi.has_meta("solid"):
			mi.remove_meta("solid")
			for ch in mi.get_children():
				ch.queue_free()

# The ground under something is only safe to stand on once it is solid.
func ensure_solid(c: Vector2i) -> void:
	for cy in range(CY_MIN, HEIGHT_CHUNKS):
		var cpos := Vector3i(c.x, cy, c.y)
		if chunk_nodes.has(cpos):
			attach_collision(chunk_nodes[cpos])

# ---------- UI and environment ----------

func setup_crosshair() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "+"
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(label)
	add_child(layer)

func setup_map() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	world_map = WorldMap.new()
	world_map.half = float(HALF)
	world_map.river_width = float(RIVER_WIDTH)
	world_map.biome_fn = terrain.biome_at
	world_map.edge_fn = edge_at_xz
	world_map.start_pos = STORAGE_XZ
	world_map.visible = false
	layer.add_child(world_map)
	add_child(layer)

func edge_at_xz(x: float, z: float) -> float:
	return terrain.edge_dist(x, z)

var map_timer := 0.0

func update_map(delta: float) -> void:
	world_map.paint_step(3)
	if world_map.visible:
		world_map.trail = pheromone.flat_points()
	world_map.update_player(ant.global_position, -ant.global_transform.basis.z, delta)
	if is_instance_valid(queen):
		world_map.queen_pos = Vector2(queen.global_position.x, queen.global_position.z)
	else:
		world_map.queen_pos = Vector2.INF
	map_timer -= delta
	if map_timer > 0.0:
		return
	map_timer = 0.5
	# Mounds show up on the map once you are within about 900 units of them.
	var cell := Vector2i(floori(ant.global_position.x / MOUND_CELL), floori(ant.global_position.z / MOUND_CELL))
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var m := terrain.mound_at_cell(cell + Vector2i(dx, dz))
			if m.is_empty():
				continue
			var mp := Vector2(float(m["x"]), float(m["z"]))
			if mp.distance_to(Vector2(ant.global_position.x, ant.global_position.z)) < 900.0:
				world_map.note_mound(mp, m["dead"])
	# Lakes show up the same way, within about 900 units.
	var pcell := Vector2i(floori(ant.global_position.x / POOL_CELL), floori(ant.global_position.z / POOL_CELL))
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			var qc := pcell + Vector2i(dx, dz)
			for lk in terrain.pools_at((float(qc.x) + 0.5) * POOL_CELL, (float(qc.y) + 0.5) * POOL_CELL):
				if lk.get("lake", false):
					var lp := Vector2(float(lk["x"]), float(lk["z"]))
					if lp.distance_to(Vector2(ant.global_position.x, ant.global_position.z)) < 900.0:
						world_map.note_lake(lp, float(lk["radius"]), terrain.lake_outline(lk))

func setup_hud() -> void:
	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(16, 84)
	hud.anchor_right = 1.0
	hud.offset_left = 16.0
	hud.offset_top = 84.0   # below the compass strip
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
		["crystal", "Crystal", Pickup.KINDS["crystal"]["color"]],
		["relic", "Relics", Pickup.KINDS["relic"]["color"]],
		["resin", "Resin", Pickup.KINDS["resin"]["color"]],
		["soil", "Soil", Color(0.55, 0.36, 0.18)],
		["water", "Water", Color(0.25, 0.55, 0.9)],
		["rock", "Rocks", Color(0.55, 0.55, 0.58)],
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
	soil_bar = make_bar(box, Color(0.55, 0.36, 0.18), Ant.SOIL_CAPACITY * 1.5)
	water_bar = make_bar(box, Color(0.25, 0.55, 0.9), Ant.WATER_CAPACITY * 1.5)
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
	env.fog_density = content.FOG_DENSITY
	# Newer Godot versions can fade the world out by distance, so its far edge melts into the haze
	# instead of ending in a visible line. Older versions just keep the plain fog above.
	if "fog_depth_end" in env:
		env.set("fog_mode", 1)
		env.set("fog_depth_begin", content.FOG_CLEAR_UNTIL)
		env.set("fog_depth_end", content.FOG_FULL_AT)
		env.set("fog_depth_curve", 1.0)
		env.fog_density = 1.0

	# Ambient occlusion darkens creases and tunnels (Forward+ renderer only).
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.5

	# A soft glow on bright things, and a little extra color.
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.08

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
	moon.light_color = Color(0.55, 0.68, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.directional_shadow_max_distance = 120.0
	moon.shadow_bias = 0.08
	moon.shadow_normal_bias = 2.0
	add_child(moon)
