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
const PLAINS := 6
const BIOME_NAMES := ["Forest", "Desert dunes", "Rocky highlands", "Frozen tundra", "Swamp", "Savanna", "Plains"]
const TREE_CHANCE := [1.0, 0.3, 0.3, 0.3, 0.6, 0.35, 0.35]  # how likely a plant site is accepted, per biome (the plant differs by biome)
const ROCK_CHANCE := [0.4, 0.5, 1.0, 0.6, 0.15, 0.3, 0.15]   # same for boulders
const BEETLE_CHANCE := [1.0, 0.2, 0.3, 0.1, 0.6, 1.0, 0.8]       # per biome: forest, desert, highlands, tundra, swamp, savanna
const CENTIPEDE_CHANCE := [0.8, 0.2, 0.8, 0.0, 1.0, 0.1, 0.2]
const FIREFLY_CHANCE := [0.5, 0.05, 0.1, 0.15, 1.0, 0.1, 0.4]
const DRAGONFLY_CHANCE := [0.8, 0.5, 0.4, 0.1, 0.9, 1.0, 1.0]   # per biome: dragonflies like open, warm, wet places
const BIOME_WALK_SPEED := [1.0, 1.0, 1.0, 0.8, 0.85, 1.0, 1.0]   # walking speed in each biome (cold, mud slow you)
const BIOME_SPRINT_COST := [1.0, 1.6, 1.0, 1.0, 1.0, 1.0, 1.0]   # the heat drains sprint energy faster
const BIOME_TINT := [Color(1, 1, 1), Color(1.1, 1.0, 0.82), Color(0.96, 0.96, 1.0), Color(0.9, 0.96, 1.08), Color(0.86, 0.96, 0.86), Color(1.14, 1.02, 0.76), Color(0.97, 1.06, 0.93)]   # haze and sun colour
const ROCK_TINT := [Color(1, 1, 1), Color(1.5, 1.2, 0.8), Color(0.7, 0.72, 0.82), Color(0.9, 1.0, 1.15), Color(0.8, 1.0, 0.8), Color(1.3, 0.95, 0.75), Color(0.92, 1.0, 0.88)]
const BIOME_RESOURCES := [                             # what the resource sites in each biome hold
	["sugar", "pebble", "fiber", "resin"],
	["pebble", "resin", "resin", "sugar"],
	["pebble", "pebble", "pebble", "sugar"],
	["sugar", "sugar", "pebble", "fiber"],
	["fiber", "fiber", "resin", "sugar"],
	["sugar", "sugar", "fiber", "pebble"],
	["sugar", "fiber", "fiber", "pebble"],
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
const DRAGONFLIES_PER_REGION := 0.3
const BOSS_CHANCE := 0.12   # chance a region holds a boss creature
const REGION_BUDGET_MS := 4.0   # time per frame spent building region content
const ROYAL_WALL := 6.0          # how thick the undiggable walls around a living queen's cell are
const MOUND_CELL := 320         # the world is split into squares this big; each may hold a termite mound
const MOUND_CHANCE := [0.35, 0.4, 0.15, 0.0, 0.25, 0.9, 0.35]   # per biome: forest, desert, highlands, tundra, swamp, savanna
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
const DRAGONFLY_RESPAWN_SECONDS := 180.0
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
var debug := DebugTools.new()   # test teleports (backslash key) and printouts: see debug_tools.gd
var stream := Streaming.new()   # loading, meshing and forgetting the world: see streaming.gd
var disasters := Disasters.new()   # rockfall and other events: see disasters.gd
var dig := Digging.new()   # digging, filling, smoothing: see digging.gd
var abilities := Abilities.new()   # acid spray, classes, rocks, fire: see abilities.gd
var building := Building.new()   # placing things, the build ghost, colony storage: see building.gd
var ui := GameHud.new()   # HUD, bars, map updates, messages: see game_hud.gd
var pop := Population.new()   # creature spawns and termite colonies: see population.gd
var atmos := Atmosphere.new()   # sky, day and night, fog, biome tint: see atmosphere.gd
var gfx := Graphics.new()   # picture quality and effects, minus key cycles it: see graphics.gd
var water := Water.new()   # all the water: see water.gd   # all the water: see water.gd
var material := StandardMaterial3D.new()
const FLORA_PATCHES_PER_REGION := 22
const LANDMARK_CHANCE := 0.5   # chance a region has one landmark (log, stump, bottle cap, giant acorn)
var ant: Ant
var storage_pos := Vector3.ZERO
var storage_ui: StorageUI
var storage_open_frame := -1
var world_map: WorldMap
var pheromone: Pheromone
var sky_life: SkyLife
var far_terrain: FarTerrain
var show_help := false   # F1 toggles the full controls list
var queen: Placeable = null   # the colony's queen, once placed

# Scenery (grass, pebbles). Each entry: {"mm": MultiMesh, "pos": Array, "hidden": Array}

# Digging state

# Building state
var crafting: Crafting

# Saves when the window is closed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and save != null:
		save.save_now(false, true)

func _ready() -> void:
	stream.setup(self)
	atmos.setup(self)
	gfx.setup(self)
	pop.setup(self)
	ui.setup(self)
	building.setup(self)
	abilities.setup(self)
	dig.setup(self)
	disasters.setup(self)
	water.setup(self)
	terrain.setup(self)
	content.setup(self)
	save.setup(self)
	progression.setup(self)
	add_child(progression)
	add_child(water)
	add_child(content)
	add_child(save)
	atmos.setup_environment()
	ui.setup_crosshair()
	ui.setup_hud()
	ui.setup_map()
	terrain.setup_noise()
	save.load_file()      # reads your save, if there is one
	save.restore_early()  # destroyed colonies, time of day
	stream.setup_terrain_material()
	building.setup_ghost()

	stream.generate_terrain()

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
	atmos.setup_headlamp()   # needs the ant's camera, which exists once the ant is in the scene
	gfx.start()              # same: it adds depth of field and floating dust to that camera
	ant.position = storage_pos + Vector3(-6, 15, 0)
	ant.deposit_requested.connect(_on_deposit)
	ant.water_surface = water.water_surface_at

	debug.setup(self)
	debug.print_nearest_mounds()
	debug.print_nearest_lakes()
	if save.has_save:
		save.restore_ant()
		save.restore_map()
	stream.preload_world(ant.global_position if save.has_save else Vector3(2, SURFACE_BASE, 8))   # build the ground around you before the game opens

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
	abilities.setup_spray()
	abilities.build_class_menu()
	abilities.setup_douse()
	ant.died.connect(func(): show_message("You were killed. Respawned at your queen." if is_instance_valid(queen) else "You were killed. Respawned at the start."))
	ant.dash_hit_creature.connect(func(_c): show_message("Dash hit!"))
	crafting.crafted.connect(func(t: String): show_message("Crafted %s. It is in your hotbar." % Crafting.RECIPES[t]["label"]))

# ---------- Per-frame updates ----------

func _process(delta: float) -> void:
	ant.controls_locked = crafting.is_open or storage_ui.is_open or abilities.class_menu_open
	abilities.rock_cd -= delta
	abilities.update_class_menu()
	ant.has_queen = is_instance_valid(queen)
	atmos.update_cover(delta)
	ui.update_flash(delta)
	atmos.update_daynight(delta)
	gfx.update(delta)
	dig.handle_dig(delta)
	dig.update_brush_preview()
	abilities.handle_spray(delta)
	abilities.handle_fire(delta)
	stream.stream_world(delta)
	disasters.update(delta)
	atmos.update_biome(delta)
	pop.process_grey()
	pop.update_boss(delta)
	ui.update_map(delta)
	ui.update_hud(delta)
	stream.process_remesh_queue()
	water.handle_water(delta)
	water.refresh_water(delta)


func _physics_process(_delta: float) -> void:
	building.update_ghost()

# ---------- Input ----------

# Shows a short message on screen (the text lives in game_hud.gd; this is here so any script can call m.show_message).
func show_message(text: String) -> void:
	ui.show_message(text)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if abilities.class_menu_open:
			if event.keycode == KEY_E and Engine.get_process_frames() == abilities.class_open_frame:
				return   # this is the same key press that just opened the menu
			if event.keycode == KEY_E or event.keycode == KEY_ESCAPE:
				abilities.close_class_menu()
			elif event.keycode == KEY_1:
				abilities.choose_role(0)
			elif event.keycode == KEY_2:
				abilities.choose_role(1)
			return
		if storage_ui.is_open:
			if event.keycode == KEY_E:
				if Engine.get_process_frames() == storage_open_frame:
					return   # this is the same key press that just opened the box
				dig.dig_lock = true
				storage_ui.close()
			return   # a box is open, so other controls are off
		if crafting.is_open and event.keycode != KEY_C:
			return   # the craft menu is open, so other controls are off
		match event.keycode:
			KEY_B:
				dig.dig_lock = true
				building.build_mode = not building.build_mode
				if building.build_mode:
					crafting.deselect()
			KEY_C:
				dig.dig_lock = true
				crafting.toggle_menu()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				dig.dig_lock = true
				var n: int = event.keycode - KEY_1
				if building.build_mode:
					if n < PIECE_ORDER.size():
						building.selected = n
				else:
					crafting.select_slot(n)
			KEY_R:
				building.yaw += PI / 2.0
			KEY_T:
				if not ant.eat_sugar():
					show_message("Nothing to eat, or you are at full health. You need sugar on you.")
			KEY_Q:
				building.feed_queen()
			KEY_MINUS:
				gfx.cycle()
			KEY_BRACKETLEFT:
				dig.change_brush(-BRUSH_STEP)
			KEY_BRACKETRIGHT:
				dig.change_brush(BRUSH_STEP)
			KEY_Y:
				abilities.convert_soil_to_rock()
			KEY_V:
				abilities.throw_rock()
			KEY_N:
				atmos.day_time = fposmod(atmos.day_time + 0.125, 1.0)
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
			KEY_SEMICOLON:
				debug.force_worm()
			KEY_COMMA:
				debug.force_boss()
			KEY_PERIOD:
				debug.force_dragonfly()
			KEY_APOSTROPHE:
				disasters.force()
			KEY_BACKSLASH:
				debug.teleport(-1 if event.shift_pressed else 1)
			KEY_F1:
				show_help = not show_help
			KEY_K:
				ant.respawn()
				show_message("Respawned at your queen." if is_instance_valid(queen) else "Respawned at the start. Place a queen to set your spawn.")

	if event is InputEventMouseButton and event.pressed:
		if crafting.is_open or storage_ui.is_open or abilities.class_menu_open:
			return   # a menu is open, so clicks belong to it
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not building.build_mode:
				dig.change_brush(BRUSH_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else -BRUSH_STEP)
			return
		# First click after pressing Esc just recaptures the mouse.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if building.build_mode:
			dig.dig_lock = true
			if event.button_index == MOUSE_BUTTON_LEFT:
				building.place_piece()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				building.remove_piece()
		elif crafting.held_type() != "":
			dig.dig_lock = true
			if event.button_index == MOUSE_BUTTON_LEFT:
				building.place_item()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				building.pick_up_item()

# ---------- Depositing ----------


# Pressing E opens the nearest box or barrel.
func _on_deposit() -> void:
	var best: Placeable = null
	var best_d := 4.5
	var all_boxes := Registry.of("containers")
	for c in all_boxes:
		var d := ant.global_position.distance_to((c as Placeable).global_position)
		if d < best_d:
			best_d = d
			best = c
	if is_instance_valid(queen) and ant.global_position.distance_to(queen.global_position) < QUEEN_MENU_RANGE \
			and (best == null or ant.global_position.distance_to(queen.global_position) < best_d):
		dig.dig_lock = true
		abilities.open_class_menu()
		return
	if best == null:
		if is_instance_valid(queen):
			show_message("Too far from your queen (%.1f away, need under %.0f)." % [ant.global_position.distance_to(queen.global_position), QUEEN_MENU_RANGE])
		else:
			show_message("No box or barrel nearby, and no queen placed. Press E next to your own queen to change class.")
		return
	dig.dig_lock = true
	storage_open_frame = Engine.get_process_frames()
	storage_ui.open(best)

# The starting spot. There is no marker: your storage is the boxes you build.
func create_storage() -> void:
	storage_pos = Vector3(STORAGE_XZ.x, terrain.ground_height(STORAGE_XZ.x, STORAGE_XZ.y), STORAGE_XZ.y)
