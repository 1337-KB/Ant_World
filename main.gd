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
var cave_noise := FastNoiseLite.new()
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
var mound_cells := {}     # same for termite mounds ({} when a square has none)
var grey_jobs: Array = []   # chunks of a dead mound waiting to turn grey
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
var landmark_mat: StandardMaterial3D
var flora_mats := {}   # species id -> shared material
const FLORA_PATCHES_PER_REGION := 22
const LANDMARK_CHANCE := 0.5   # chance a region has one landmark (log, stump, bottle cap, giant acorn)
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
var rock_cd := 0.0
var class_menu_open := false
var class_open_frame := -1
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

func _ready() -> void:
	setup_environment()
	setup_crosshair()
	setup_hud()
	setup_map()
	setup_noise()
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
	far_terrain.height_fn = ground_height
	far_terrain.kind_fn = surface_kind
	far_terrain.edge_fn = edge_dist
	far_terrain.biome_fn = biome_at
	far_terrain.lake_fn = far_lake_level
	far_terrain.mounds_fn = far_mounds
	far_terrain.river_width = float(RIVER_WIDTH)
	far_terrain.river_level = RIVER_LEVEL
	add_child(far_terrain)
	setup_headlamp()   # needs the ant's camera, which exists once the ant is in the scene
	ant.position = storage_pos + Vector3(-6, 15, 0)
	ant.deposit_requested.connect(_on_deposit)
	ant.water_surface = water_surface_at

	print_nearest_mounds()
	print_nearest_lakes()
	preload_world(Vector3(2, SURFACE_BASE, 8))   # build the ground around the start before the game opens

	crafting = Crafting.new()
	crafting.ant = ant
	add_child(crafting)
	storage_ui = StorageUI.new()
	storage_ui.ant = ant
	add_child(storage_ui)
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
	water_tint.visible = camera_underwater()
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
	handle_water(delta)
	refresh_water(delta)

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
				text += "[Shift] sprint   [C] craft   [1-9] hold item   [B] build   [M] map   [L] pheromone trail   [O] wipe trail   [N] skip 3 hours   [K] respawn   [F1] hide help"
			else:
				text += "[F1] controls   [M] map   [C] craft   [B] build"
			if pheromone.laying:
				text += "\nTRAIL ON  ([L] to stop)"

	if not water_source.is_empty():
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
	wake_pickups(point, clear_radius)
	mark_water_dirty(point, clear_radius)

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
	wake_pickups(center, fr + 1.0)
	mark_water_dirty(center, fr + 1.0)

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
		var reach := float(p["radius"]) * (1.12 if p.get("lake", false) else 1.4) + radius
		if pool_dist(p, point.x, point.z) < reach \
				and top > float(p["floor"]) - POOL_LOCK_DEPTH and bottom < float(p["level0"]) + 0.5:
			return true

	if edge_dist(point.x, point.z) < RIVER_WIDTH + radius and top > RIVER_BED_Y - POOL_LOCK_DEPTH and bottom < RIVER_LEVEL + 0.5:
		return true   # the riverbed stays, so the river keeps its water

	# The royal cell has thick walls while its colony lives: the only way in is the guarded antechamber.
	var mm := mound_near(point.x, point.z)
	if not mm.is_empty() and not bool(mm["dead"]):
		var rc: Vector3 = mm["royal"]
		var rr: Vector3 = mm["royal_r"]
		var rq := Vector3((point.x - rc.x) / rr.x, (point.y - rc.y) / rr.y, (point.z - rc.z) / rr.z)
		if (rq.length() - 1.0) * 6.6 < ROYAL_WALL + radius:
			return true

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
	p.world = world
	p.moved.connect(_on_placeable_moved)
	if Placeable.DEFENSE.has(held):
		p.collapsed.connect(_on_trap_collapsed)
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
	wake_pickups(center, radius + 1.0)
	mark_water_dirty(center, radius + 1.0)
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
	print("E pressed. queen valid: ", is_instance_valid(queen), "  class menu built: ", class_layer != null)
	var best: Placeable = null
	var best_d := 4.5
	for c in get_tree().get_nodes_in_group("containers"):
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
	temp_noise.fractal_octaves = 2      # Godot's default is 5, which made biomes patchy at every scale
	temp_noise.fractal_gain = 0.2
	moist_noise.seed = 4002
	moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moist_noise.frequency = BIOME_FREQ
	moist_noise.fractal_octaves = 2
	moist_noise.fractal_gain = 0.2
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
		var d := pool_dist(p, x, z)
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

# The lowest chunk layer a column gets generated down to before you are near it.
var col_deep_from := {}   # column -> its lowest generated layer (CY_MIN once the deep ground is done too)
var deep_wanted: Array = []

func shallow_layer(col: Vector2i, cache: Dictionary) -> int:
	var margin := DEEP_SHALLOW
	var mx := (float(col.x) + 0.5) * Chunk.SIZE
	var mz := (float(col.y) + 0.5) * Chunk.SIZE
	var ms := mound_site(Vector2i(floori(mx / MOUND_CELL), floori(mz / MOUND_CELL)))
	if not ms.is_empty() and Vector2(mx - float(ms["x"]), mz - float(ms["z"])).length() < float(ms["R"]) + 60.0:
		margin = DEEP_NEAR_MOUND
	return clampi(floori((float(cache["min"]) - margin) / Chunk.SIZE), CY_MIN, HEIGHT_CHUNKS - 1)

# The deep ground of a column was just generated, so it and its neighbors are drawn again to include it.
func finish_deep(col: Vector2i) -> void:
	col_deep_from[col] = CY_MIN
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
					if depth < 12.0 or blk_c[bi] > CAVE_THRESHOLD - 0.25:
						var cave_n := cave_noise.get_noise_3d(float(x), float(y) * 1.6, float(z))
						if cave_n > CAVE_THRESHOLD:
							dens = minf(dens, clampf((CAVE_THRESHOLD - cave_n) * 14.0, -1.0, 1.0))

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

# A chunk that is solid all through, and so are all its neighbors, has no surface to draw. Most of
# the deep ground is like this, so it is never meshed. Digging into it clears the mark.
var solid_chunks := {}

func is_buried_solid(cpos: Vector3i) -> bool:
	if not solid_chunks.has(cpos):
		return false
	for oy in range(-1, 2):
		for oz in range(-1, 2):
			for ox in range(-1, 2):
				var n := cpos + Vector3i(ox, oy, oz)
				if n.y < CY_MIN:
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
	return mound_at_cell(Vector2i(floori(x / MOUND_CELL), floori(z / MOUND_CELL)))

# Is this spot on or close to a mound? Used to keep trees, grass and so on off it.
func near_mound(x: float, z: float, margin: float) -> bool:
	var m := mound_near(x, z)
	if m.is_empty():
		return false
	return Vector2(x - float(m["x"]), z - float(m["z"])).length() < float(m["R"]) + margin + 6.0

# The mound whose shapes could touch this chunk (a mound always fits inside its own square).
func mounds_near_chunk(cpos: Vector3i) -> Dictionary:
	var m := mound_at_cell(Vector2i(floori(float(cpos.x * Chunk.SIZE) / MOUND_CELL), floori(float(cpos.z * Chunk.SIZE) / MOUND_CELL)))
	if m.is_empty():
		return {}
	var lo := Vector3(cpos * Chunk.SIZE)
	var hi := lo + Vector3.ONE * Chunk.SIZE
	var cones := []
	for cn in m["cones"]:
		if aabb_hits(cn["lo"], cn["hi"], lo, hi):
			cones.append(cn)
	var prims := []
	for pr in m["prims"]:
		if aabb_hits(pr["lo"], pr["hi"], lo, hi):
			prims.append(pr)
	if cones.is_empty() and prims.is_empty():
		return {}
	return {"cones": cones, "prims": prims, "dead": m["dead"]}

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

# Just where a mound stands and how big it is, without its inside. The far view uses this to draw
# every mound out to the horizon. It follows gen_mound_cell's first rolls exactly, so they agree.
var mound_sites: Dictionary = {}

func mound_site(cell: Vector2i) -> Dictionary:
	if mound_sites.has(cell):
		return mound_sites[cell]
	var site := {}
	var rng := cell_rng(cell, 9090)
	var origin := Vector2(cell) * float(MOUND_CELL)
	var x := origin.x + rng.randf_range(64.0, MOUND_CELL - 64.0)
	var z := origin.y + rng.randf_range(64.0, MOUND_CELL - 64.0)
	var chance := float(MOUND_CHANCE[biome_at(x, z)]) * smoothstep(MOUND_START_CLEAR, 400.0, Vector2(x, z).length())
	if rng.randf() <= chance:
		for t in 8:
			x = origin.x + rng.randf_range(64.0, MOUND_CELL - 64.0)
			z = origin.y + rng.randf_range(64.0, MOUND_CELL - 64.0)
			var rad := rng.randf_range(15.0, 25.0)
			if edge_dist(x, z) < 140.0:
				continue
			var wet := false
			for p in pools_at(x, z):
				if Vector2(x - float(p["x"]), z - float(p["z"])).length() < float(p["radius"]) * 1.5 + rad + 12.0:
					wet = true
			if wet:
				continue
			var gh := ground_height(x, z)
			if gh < 40.0 or gh > 54.0:
				continue
			var flat := true
			for off in [Vector2(rad, 0), Vector2(-rad, 0), Vector2(0, rad), Vector2(0, -rad)]:
				if absf(ground_height(x + off.x, z + off.y) - gh) > 4.0:
					flat = false
			if flat:
				site = {"x": x, "z": z, "gh": gh, "R": rad, "H": minf(rng.randf_range(34.0, 52.0), 100.0 - gh)}
				break
	mound_sites[cell] = site
	return site

# Every mound within reach of the far view, as {x, z, gh, R, H}.
func far_mounds(center: Vector2, radius: float) -> Array:
	var out := []
	var lo := Vector2i(floori((center.x - radius) / MOUND_CELL), floori((center.y - radius) / MOUND_CELL))
	var hi := Vector2i(floori((center.x + radius) / MOUND_CELL), floori((center.y + radius) / MOUND_CELL))
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
	var origin := Vector2(cell) * float(MOUND_CELL)
	# One roll decides whether this square has a mound: unlikely near the start, likelier far out.
	var x := origin.x + rng.randf_range(64.0, MOUND_CELL - 64.0)
	var z := origin.y + rng.randf_range(64.0, MOUND_CELL - 64.0)
	var chance := float(MOUND_CHANCE[biome_at(x, z)]) * smoothstep(MOUND_START_CLEAR, 400.0, Vector2(x, z).length())
	if rng.randf() > chance:
		return {}
	var rad := 0.0
	var gh := 0.0
	var found := false
	for t in 8:
		x = origin.x + rng.randf_range(64.0, MOUND_CELL - 64.0)
		z = origin.y + rng.randf_range(64.0, MOUND_CELL - 64.0)
		rad = rng.randf_range(15.0, 25.0)
		if edge_dist(x, z) < 140.0:
			continue
		var wet := false
		for p in pools_at(x, z):
			if Vector2(x - float(p["x"]), z - float(p["z"])).length() < float(p["radius"]) * 1.5 + rad + 12.0:
				wet = true
		if wet:
			continue
		gh = ground_height(x, z)
		if gh < 40.0 or gh > 54.0:
			continue
		var flat := true
		for off in [Vector2(rad, 0), Vector2(-rad, 0), Vector2(0, rad), Vector2(0, -rad)]:
			if absf(ground_height(x + off.x, z + off.y) - gh) > 4.0:
				flat = false
		if flat:
			found = true
			break
	if not found:
		return {}

	var height := minf(rng.randf_range(34.0, 52.0), 100.0 - gh)
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
		"kind": "mound", "x": x, "z": z, "gh": gh, "R": rad, "H": height, "royal_r": royal_r,
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
	var cell := Vector2i(floori(x / POOL_CELL), floori(z / POOL_CELL))
	if not pool_cells.has(cell):
		gen_pool_cell(cell)
	return pool_cells[cell]

# A big, deep forest lake with grassy banks. The square holding the start always gets one, a short walk away.
# It has to sit well inside its square, because ground_height() only looks at the square's own water.
func try_lake(cell: Vector2i, origin: Vector2, list: Array) -> bool:
	var rng := cell_rng(cell, 4242)
	var is_start := cell == Vector2i(0, 0)
	if not is_start and rng.randf() > LAKE_CHANCE:
		return false
	for t in 10:
		var radius := rng.randf_range(50.0, 60.0)
		var margin := radius * 1.9 + 4.0
		if margin > POOL_CELL * 0.5 - 6.0:
			radius = (POOL_CELL * 0.5 - 10.0 - 4.0) / 1.9
			margin = radius * 1.9 + 4.0
		var x := origin.x + rng.randf_range(margin, POOL_CELL - margin)
		var z := origin.y + rng.randf_range(margin, POOL_CELL - margin)
		if edge_dist(x, z) < RIVER_WIDTH + radius * 1.9 + 10.0:
			continue
		if Vector2(x, z).distance_to(STORAGE_XZ) < radius * 1.5 + 60.0:
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
		unbuilt_water.append(p)
		return true
	return false

func gen_pool_cell(cell: Vector2i) -> void:
	var list := []
	pool_cells[cell] = list
	var rng := cell_rng(cell, 777)
	var origin := Vector2(cell) * float(POOL_CELL)
	if try_lake(cell, origin, list):
		return
	if rng.randf() > POOL_CHANCE:
		return
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

# True once the ground around a lake's whole bound has been generated.
func water_ground_ready(p: Dictionary) -> bool:
	var seed_v: Vector2 = p["seed"]
	var bound: Vector2 = p["bound"]
	var lo := col_of(Vector3(seed_v.x - bound.x - 2.0, 0, seed_v.y - bound.y - 2.0))
	var hi := col_of(Vector3(seed_v.x + bound.x + 2.0, 0, seed_v.y + bound.y + 2.0))
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var cq := Vector2i(cx, cz)
			if col_in_world(cq) and not col_data.has(cq):
				return false
	return true

# A flat sheet of water drawn straight from the lake's shape, with no need for any ground data.
# It shows the moment the lake is in range, and is swapped for the exact water once the ground exists.
func quick_lake_mesh(p: Dictionary, level: float) -> ArrayMesh:
	var pts := lake_outline(p)
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
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

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
	# One water body per tick, so several never rebuild in the same frame.
	for p in built_water:
		if p["dirty"]:
			if p.get("lake", false) and not water_ground_ready(p):
				continue   # already showing its quick sheet; wait for the ground
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
				var d := pool_dist(p, a.x, a.z)
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
	if ant.water >= ant.water_cap() - 0.01:
		show_message("Your water bar is full.")
		return
	var amount := minf(DRINK_RATE * delta, minf(ant.water_cap() - ant.water, float(water_source["stock"])))
	ant.water += amount
	water_source["stock"] = float(water_source["stock"]) - amount
	water_source["dirty"] = true
	if float(water_source["stock"]) <= 0.0:
		show_message("This water is all gone.")

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
	storage_pos = Vector3(STORAGE_XZ.x, ground_height(STORAGE_XZ.x, STORAGE_XZ.y), STORAGE_XZ.y)

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
		env.set("fog_depth_end", lerpf(FOG_FULL_AT, FOG_FULL_AT * 0.4, mist_now))
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
	b.ground_at = ground_height
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
	c.ground_at = ground_height
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
			var m := mound_at_cell(Vector2i(cx, cz))
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
			for lk in pools_at((float(cx) + 0.5) * POOL_CELL, (float(cz) + 0.5) * POOL_CELL):
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
		var m := mound_at_cell(cell)
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
	for i in 6:
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
	c.ground_at = ground_height
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
			queue_remesh([cp], Vector3(cp * Chunk.SIZE))

# ---------- Trees and boulders ----------
# Trees are enormous at ant scale: towering trunks you can climb, with a canopy far overhead.
# Boulders are solid rock. The ground around both is too hard to dig, so nothing is left floating.

const FOG_CLEAR_UNTIL := 40.0   # distance fog: nothing is hazy up to here...
const FOG_FULL_AT := 600.0      # ...and everything is fully hazy here, at the far edge of the distant land
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
	if near_mound(x, z, margin):
		return true
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
			if rng.randf() < 0.45:
				add_spruce(x, z, rng)
			else:
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

# Scenery fades out smoothly toward the edge of the drawn world instead of appearing suddenly.
func fade_far(mi: MeshInstance3D) -> void:
	mi.visibility_range_end = TREE_FADE_END
	mi.visibility_range_end_margin = 12.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func plant_part(body: Node3D, mesh: Mesh, color: Color, pos: Vector3, orient: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = plant_mat(color)
	mi.transform = Transform3D(orient, pos)
	fade_far(mi)
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

# A tall forest spruce: a thin trunk and many stacked, narrowing skirts of needles that droop at the tips.
func add_spruce(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(30.0, 46.0)
	var r := rng.randf_range(0.9, 1.4)
	var tm := cylinder_mesh(r * 0.45, r * 1.1, h * 0.8, 10)
	plant_part(body, tm, Color(0.27, 0.18, 0.11), Vector3(0, h * 0.4, 0))
	trunk_collision(body, tm, Vector3(0, h * 0.4, 0))
	var base := Color(0.07, 0.24, 0.13).lerp(Color(0.12, 0.32, 0.17), rng.randf())
	var layers := rng.randi_range(6, 8)
	var widest := rng.randf_range(6.5, 8.5)
	for i in layers:
		var t := float(i) / float(layers - 1)
		var cr := lerpf(widest, 1.2, pow(t, 0.9))
		var ch := lerpf(8.0, 5.0, t)
		var g := rng.randf_range(0.85, 1.12)
		plant_part(body, cylinder_mesh(0.0, cr, ch, 12), Color(base.r * g, base.g * g, base.b * g),
				Vector3(0, h * 0.2 + t * h * 0.74 + ch * 0.4, 0))
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
	fade_far(trunk)
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
		fade_far(leaves)
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
	fade_far(mi)
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
	items.append(["landmark"])
	for i in ceili(GRASS_CLUMPS_PER_REGION / 40.0):
		items.append(["grass", 40])
	items.append(["build_grass"])
	for i in ceili(PEBBLES_PER_REGION / 60.0):
		items.append(["pebbles", 60])
	items.append(["build_pebbles"])
	for i in ceili(FLORA_PATCHES_PER_REGION / 6.0):
		items.append(["flora", 6])
	items.append(["shore", 90])
	items.append(["build_flora"])
	items.append(["pickups"])
	items.append(["creatures"])
	items.append(["colony"])
	return {"key": key, "rng": rng, "items": items, "grass": {}, "pebbles": {}, "flora": {}}

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
		"landmark":
			region_landmark(job)
		"flora":
			region_flora(job, item[1])
		"shore":
			region_shore(job, item[1])
		"build_flora":
			build_flora(job)
		"pickups":
			region_pickups(job)
		"creatures":
			region_creatures(job)
		"colony":
			region_colony(job)

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
	if near_pool(x, z, 2.8) or near_obstacle(x, z, 6.0):
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
		grass_mat_shared.set_shader_parameter("fade_start", GRASS_FADE_START)
		grass_mat_shared.set_shader_parameter("fade_end", GRASS_FADE_END)
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
		pebble_mat_shared.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		pebble_mat_shared.distance_fade_max_distance = GRASS_FADE_START
		pebble_mat_shared.distance_fade_min_distance = GRASS_FADE_END
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

# One big solid thing now and then: a fallen log, a hollow stump, a half-buried bottle cap or a giant acorn.
func region_landmark(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	if rng.randf() > LANDMARK_CHANCE:
		return
	var sp := region_spot(job, 6.0)
	var x := sp.x
	var z := sp.y
	if not inland(x, z) or near_pool(x, z, 1.8) or near_obstacle(x, z, 4.5):
		return
	if Vector2(x, z).distance_to(STORAGE_XZ) < 12.0:
		return
	var kind := Flora.pick_landmark(biome_at(x, z), rng.randf())
	if kind < 0:
		return
	var variant := rng.randi() % (3 if kind == 2 else 2)
	var gy := ground_height(x, z)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	region_node(region_key(x, z)).add_child(body)
	var sink: float = [0.25, 0.2, 0.3, 0.2][kind]
	body.global_position = Vector3(x, gy - sink, z)
	var tilt_x := rng.randf_range(0.15, 0.35) if kind == 2 else 0.0
	var tilt_z := rng.randf_range(-0.2, 0.2) if kind == 2 else 0.0
	body.rotation = Vector3(tilt_x, rng.randf_range(0.0, TAU), tilt_z)

	var mi := MeshInstance3D.new()
	mi.mesh = Flora.get_landmark_mesh(kind, variant)
	if landmark_mat == null:
		landmark_mat = Flora.landmark_material()
	mi.material_override = landmark_mat
	fade_far(mi)
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var radius := 1.5
	match kind:
		0:
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.9
			cyl.height = 7.0
			col.shape = cyl
			col.transform = Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(0, 0.9, 0))
			radius = 3.8
		1:
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.05
			cyl.height = 1.7
			col.shape = cyl
			col.position = Vector3(0, 0.85, 0)
			radius = 1.5
		2:
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.5
			cyl.height = 0.55
			col.shape = cyl
			col.position = Vector3(0, 0.275, 0)
			radius = 1.8
		3:
			var sph := SphereShape3D.new()
			sph.radius = 1.1
			col.shape = sph
			col.position = Vector3(0, 1.3, 0)
			radius = 1.4
	body.add_child(col)
	add_obstacle({"pos": Vector3(x, gy, z), "radius": radius})

# Flowers, mushrooms, cacti and moss. Each patch is one kind, picked from the biome's list (see flora.gd).
func region_flora(job: Dictionary, count: int) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["flora"]
	for c in count:
		var sp := region_spot(job, 0.0)
		var cx := sp.x
		var cz := sp.y
		if not inland(cx, cz) or near_pool(cx, cz):
			continue
		var kind0 := surface_kind(cx, cz)
		if kind0 == Blocks.MOUND or kind0 == Blocks.DEAD_MOUND or kind0 == Blocks.STONE or kind0 == Blocks.AIR:
			continue
		if Vector2(cx - storage_pos.x, cz - storage_pos.z).length() < STORAGE_RADIUS + 3.0:
			continue
		var species := Flora.pick(biome_at(cx, cz), rng.randf())
		if species < 0:
			continue
		var info: Array = Flora.PATCH[species]
		var n := rng.randi_range(int(info[0]), int(info[1]))
		var spread := float(info[2])
		for i in n:
			var x := cx + rng.randf_range(-spread, spread)
			var z := cz + rng.randf_range(-spread, spread)
			add_flora_instance(buckets, species, x, z, rng)

# Plants one flora instance if the spot allows it.
func add_flora_instance(buckets: Dictionary, species: int, x: float, z: float, rng: RandomNumberGenerator, need_dry: bool = true) -> void:
	if not inland(x, z) or near_pool(x, z) or near_obstacle(x, z, 0.8):
		return
	var k := surface_kind(x, z)
	if k == Blocks.MOUND or k == Blocks.DEAD_MOUND or k == Blocks.STONE or k == Blocks.AIR:
		return
	var base := Vector3(x, ground_height(x, z) - 0.08, z)
	var sc := rng.randf_range(0.75, 1.3)
	var tilt := Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(0.0, TAU), rng.randf_range(-0.07, 0.07))
	var bs := Basis.from_euler(tilt) * Basis.from_scale(Vector3.ONE * sc)
	var key := region_key(x, z)
	if not buckets.has(key):
		buckets[key] = {}
	if not buckets[key].has(species):
		buckets[key][species] = {"xf": [], "pos": []}
	buckets[key][species]["xf"].append(Transform3D(bs, base))
	buckets[key][species]["pos"].append(base)

# Lake banks: cattails at the water's edge, then bushes, ferns and flowers up the bank.
func region_shore(job: Dictionary, tries: int) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["flora"]
	var mid := region_spot(job, REGION_SIZE * 0.5 - 0.01)
	var lakes := []
	for p in pools_at(mid.x, mid.y):
		if p.get("lake", false):
			lakes.append(p)
	if lakes.is_empty():
		return
	for t in tries:
		var sp := region_spot(job, 0.0)
		for p in lakes:
			var r: float = p["radius"]
			var d := pool_dist(p, sp.x, sp.y)
			if d < r * 0.78 or d > r * 1.7:
				continue
			var gh := ground_height(sp.x, sp.y)
			var level: float = p["level0"]
			if gh < level - 0.2:
				continue   # underwater
			var species := 6   # cattail
			if gh > level + 0.8:
				var roll := rng.randf()
				if roll < 0.45:
					species = 27   # hedge bush
				elif roll < 0.65:
					species = 20   # berry bush
				elif roll < 0.8:
					species = 18   # fern
				elif roll < 0.9:
					species = 0    # daisy
				else:
					species = 3    # buttercup
			var n := 3 if species == 6 else rng.randi_range(1, 3)
			for i in n:
				add_flora_instance(buckets, species, sp.x + rng.randf_range(-1.6, 1.6), sp.y + rng.randf_range(-1.6, 1.6), rng)

func build_flora(job: Dictionary) -> void:
	var buckets: Dictionary = job["flora"]
	for key in buckets:
		for species in buckets[key]:
			if not flora_mats.has(species):
				flora_mats[species] = Flora.make_material(species, GRASS_FADE_START, GRASS_FADE_END)
			var xforms: Array = buckets[key][species]["xf"]
			var positions: Array = buckets[key][species]["pos"]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Flora.get_mesh(species)
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = flora_mats[species]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			region_node(key).add_child(mmi)
			var hidden := []
			hidden.resize(positions.size())
			hidden.fill(0)
			decor_sets.append({"mm": mm, "pos": positions, "hidden": hidden, "rect": region_rect(key)})
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
	for i in int(BEETLES_PER_REGION + rng.randf()):
		var sp := region_spot(job, 4.0)
		if not inland(sp.x, sp.y) or rng.randf() > BEETLE_CHANCE[biome_at(sp.x, sp.y)]:
			continue
		if sp.distance_to(STORAGE_XZ) < 14.0 or near_pool(sp.x, sp.y, 2.0) or near_obstacle(sp.x, sp.y, 2.0):
			continue
		spawn_beetle(Vector3(sp.x, ground_height(sp.x, sp.y) + 0.5, sp.y))
	for i in int(CENTIPEDES_PER_REGION + rng.randf()):
		var sp := region_spot(job, 4.0)
		if not inland(sp.x, sp.y) or rng.randf() > CENTIPEDE_CHANCE[biome_at(sp.x, sp.y)]:
			continue
		if sp.distance_to(STORAGE_XZ) < 14.0 or near_pool(sp.x, sp.y, 2.0) or near_obstacle(sp.x, sp.y, 2.0):
			continue
		spawn_centipede(Vector3(sp.x, ground_height(sp.x, sp.y) + 0.5, sp.y))


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
		solid_chunks.erase(c)
		edited_cols[Vector2i(c.x, c.z)] = true

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
			var cache := gen_column_cache(found)
			if deep:
				gen_job = {"col": found, "cy": CY_MIN, "end": int(col_deep_from[found]), "cache": cache, "deep": true}
			else:
				var first := shallow_layer(found, cache)
				col_deep_from[found] = first
				gen_job = {"col": found, "cy": first, "end": HEIGHT_CHUNKS, "cache": cache, "deep": false}
		var col: Vector2i = gen_job["col"]
		fill_chunk(Vector3i(col.x, gen_job["cy"], col.y), gen_job["cache"])
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

	# Water appears once the ground around it exists. One body per update, so it never stutters.
	var candidates: Array = unbuilt_water.duplicate()
	if edge_dist(center.x, center.z) < 300.0:
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
		if p.get("kind", "") == "pocket" and int(col_deep_from.get(col_of(Vector3(seed_v.x, 0, seed_v.y)), CY_MIN)) > CY_MIN:
			continue   # the deep ground around an underground pool is not generated yet
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
			water_built += 1
			if water_built >= 2:
				break
	for p in built_water:
		var seed_v: Vector2 = p["seed"]
		(p["mesh"] as MeshInstance3D).visible = true   # show the water at once, even before the ground around it is drawn

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
			solid_chunks.erase(Vector3i(c.x, cy, c.y))
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
	var mm := mound_near(ant.global_position.x, ant.global_position.z)
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
	region_step(1.0e9)
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
	region_step(REGION_BUDGET_MS)
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
		if is_buried_solid(nxt) or world.get_chunk(nxt) == null:
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
	if is_buried_solid(cpos):
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
	world_map.biome_fn = biome_at
	world_map.edge_fn = edge_at_xz
	world_map.start_pos = STORAGE_XZ
	world_map.visible = false
	layer.add_child(world_map)
	add_child(layer)

func edge_at_xz(x: float, z: float) -> float:
	return edge_dist(x, z)

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
			var m := mound_at_cell(cell + Vector2i(dx, dz))
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
			for lk in pools_at((float(qc.x) + 0.5) * POOL_CELL, (float(qc.y) + 0.5) * POOL_CELL):
				if lk.get("lake", false):
					var lp := Vector2(float(lk["x"]), float(lk["z"]))
					if lp.distance_to(Vector2(ant.global_position.x, ant.global_position.z)) < 900.0:
						world_map.note_lake(lp, float(lk["radius"]), lake_outline(lk))

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
	env.fog_density = FOG_DENSITY
	# Newer Godot versions can fade the world out by distance, so its far edge melts into the haze
	# instead of ending in a visible line. Older versions just keep the plain fog above.
	if "fog_depth_end" in env:
		env.set("fog_mode", 1)
		env.set("fog_depth_begin", FOG_CLEAR_UNTIL)
		env.set("fog_depth_end", FOG_FULL_AT)
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
