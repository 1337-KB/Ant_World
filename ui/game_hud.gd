class_name GameHud
extends RefCounted

# All the on-screen interface that is not a menu: the crosshair, the hint text, the resource panel
# (what you carry and what is stored), the health/soil/water/energy/acid bars, the red hurt flash,
# the underwater tint, messages, and the world map. main.gd calls update_flash(), update_map() and
# update_hud() every frame, and show_message() from anywhere.

var m: Main

var hud: Label
var res_panel: PanelContainer
var res_rows := {}   # kind -> {"carry": Label, "stored": Label}
var soil_bar: ProgressBar
var water_bar: ProgressBar
var energy_bar: ProgressBar
var health_bar: ProgressBar
var acid_bar: ProgressBar
var flash_rect: ColorRect
var water_tint: ColorRect
var last_health := 100.0
var message := ""
var message_time := 0.0

func setup(main: Main) -> void:
	m = main

func show_message(text: String) -> void:
	message = text
	message_time = 2.0

# The red flash when you are hurt, and the blue tint when the camera is under water.
func update_flash(delta: float) -> void:
	water_tint.visible = m.water.camera_underwater()
	if m.ant.health < last_health - 0.01:
		flash_rect.color.a = 0.4   # flash red when hurt
	last_health = m.ant.health
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - delta * 1.5)

# The hint text, resource panel and bars.
func update_hud(delta: float) -> void:
	message_time -= delta
	var inv := m.ant.inventory
	var cap := int(m.ant.carry_cap("sugar"))
	var hours := fposmod(6.0 + m.atmos.day_time * 24.0, 24.0)
	var text := "[%s ant]   Day %d   %02d:%02d   %s\n" % [Ant.ROLE_NAMES[m.ant.role], m.atmos.day_count, int(hours), int((hours - floorf(hours)) * 60.0), Main.BIOME_NAMES[m.atmos.current_biome]]
	text = text.rstrip("\n") + "\n"
	for k in res_rows:
		var have := 0
		if k == "soil":
			have = int(m.ant.soil)
		elif k == "water":
			have = int(m.ant.water)
		elif k == "rock":
			have = m.ant.rocks
		else:
			have = int(inv[k])
		var limit := int(m.ant.carry_cap(k)) if k != "sugar" else cap
		if k == "soil":
			limit = int(m.ant.soil_cap())
		elif k == "water":
			limit = int(m.ant.water_cap())
		res_rows[k]["carry"].text = "%d/%d" % [have, limit]
		res_rows[k]["stored"].text = "-" if k == "rock" else str(m.building.stored(k))

	if m.building.build_mode:
		text += "\nBUILD MODE\n"
		for i in Main.PIECE_ORDER.size():
			var t: String = Main.PIECE_ORDER[i]
			var marker := ">" if i == m.building.selected else " "
			text += "%s [%d] %s (%s)\n" % [marker, i + 1, Piece.TYPES[t]["label"], m.building.cost_text(t)]
		text += "[R] rotate   [Left click] place   [Right click] remove   [B] exit"
	else:
		var held := m.crafting.held_type()
		if m.ant.swimming:
			text += "Swimming: [W/S] swim where you look   [Space] up   [Ctrl] dive\n"
		if held != "":
			text += "Holding: %s\n[Left click] place   [Right click] pick up   [Same number] put away   [R] rotate" % Crafting.RECIPES[held]["label"]
		else:
			if m.show_help:
				text += "[Hold click] dig   [Hold X + click] fill   [Hold right click] smooth   [E] open box or barrel\n"
				text += "[Hold F] drink   [Hold G] acid spray   [H] light fire   [Hold J] douse   [T] eat sugar   [Q] feed queen\n"
				text += "[Mouse wheel or [ ]] dig size   [Ctrl] dash (A/D/S + Ctrl to dodge)   [E at queen] change class"
				if m.ant.role == 1:
					text += "   [Y] soil to rock   [V] throw rock"
				text += "\n"
				text += "[Shift] sprint   [C] craft   [1-9] hold item   [B] build   [M] map   [U] termite tracker   [F5] save   [Backslash] test spots   [L] pheromone trail   [O] wipe trail   [N] skip 3 hours   [K] respawn   [F1] hide help"
			else:
				text += "[F1] controls   [M] map   [C] craft   [B] build"
			text += "\n" + m.progression.hud_line()
			var track_line := m.progression.tracker_line()
			if track_line != "":
				text += "\n" + track_line
			if m.pheromone.laying:
				text += "\nTRAIL ON  ([L] to stop)"

	if not m.water.water_source.is_empty():
		text += "\n[Hold F] drink water"
	if message_time > 0.0:
		text += "\n" + message
	hud.text = text
	hud.visible = not (m.crafting.is_open or m.storage_ui.is_open)
	res_panel.visible = hud.visible

	soil_bar.max_value = m.ant.soil_cap()
	water_bar.max_value = m.ant.water_cap()
	health_bar.max_value = m.ant.max_health
	soil_bar.value = m.ant.soil
	(soil_bar.get_child(0) as Label).text = "Soil  %d / %d" % [int(m.ant.soil), int(m.ant.soil_cap())]
	water_bar.value = m.ant.water
	(water_bar.get_child(0) as Label).text = "Water  %d / %d" % [int(m.ant.water), int(m.ant.water_cap())]
	health_bar.value = m.ant.health
	(health_bar.get_child(0) as Label).text = "Health  %d / %d" % [int(m.ant.health), int(m.ant.max_health)]
	acid_bar.value = m.ant.acid
	(acid_bar.get_child(0) as Label).text = "Acid  %d / %d" % [int(m.ant.acid), int(Ant.ACID_MAX)]
	energy_bar.value = m.ant.energy
	var tired := " (resting)" if m.ant.exhausted else ""
	(energy_bar.get_child(0) as Label).text = "Energy  %d / %d%s" % [int(m.ant.energy), int(Ant.ENERGY_MAX), tired]

func setup_crosshair() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "+"
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(label)
	m.add_child(layer)

func setup_map() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	m.world_map = WorldMap.new()
	m.world_map.half = float(Main.HALF)
	m.world_map.river_width = float(Main.RIVER_WIDTH)
	m.world_map.biome_fn = m.terrain.biome_at
	m.world_map.edge_fn = edge_at_xz
	m.world_map.start_pos = Main.STORAGE_XZ
	m.world_map.visible = false
	layer.add_child(m.world_map)
	m.add_child(layer)

func edge_at_xz(x: float, z: float) -> float:
	return m.terrain.edge_dist(x, z)

var map_timer := 0.0

func update_map(delta: float) -> void:
	m.world_map.paint_step(3)
	if m.world_map.visible:
		m.world_map.trail = m.pheromone.flat_points()
	m.world_map.update_player(m.ant.global_position, -m.ant.global_transform.basis.z, delta)
	if is_instance_valid(m.queen):
		m.world_map.queen_pos = Vector2(m.queen.global_position.x, m.queen.global_position.z)
	else:
		m.world_map.queen_pos = Vector2.INF
	map_timer -= delta
	if map_timer > 0.0:
		return
	map_timer = 0.5
	# Mounds show up on the map once you are within about 900 units of them.
	var cell := Vector2i(floori(m.ant.global_position.x / Main.MOUND_CELL), floori(m.ant.global_position.z / Main.MOUND_CELL))
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var mnd := m.terrain.mound_at_cell(cell + Vector2i(dx, dz))
			if mnd.is_empty():
				continue
			var mp := Vector2(float(mnd["x"]), float(mnd["z"]))
			if mp.distance_to(Vector2(m.ant.global_position.x, m.ant.global_position.z)) < 900.0:
				m.world_map.note_mound(mp, mnd["dead"])
	# Lakes show up the same way, within about 900 units.
	var pcell := Vector2i(floori(m.ant.global_position.x / Main.POOL_CELL), floori(m.ant.global_position.z / Main.POOL_CELL))
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			var qc := pcell + Vector2i(dx, dz)
			for lk in m.terrain.pools_at((float(qc.x) + 0.5) * Main.POOL_CELL, (float(qc.y) + 0.5) * Main.POOL_CELL):
				if lk.get("lake", false):
					var lp := Vector2(float(lk["x"]), float(lk["z"]))
					if lp.distance_to(Vector2(m.ant.global_position.x, m.ant.global_position.z)) < 900.0:
						m.world_map.note_lake(lp, float(lk["radius"]), m.terrain.lake_outline(lk))

func setup_hud() -> void:
	setup_boss_bar()
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
		["shell", "Shells", Pickup.KINDS["shell"]["color"]],
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
	box.offset_right = 300.0
	box.offset_top = -300.0
	box.offset_bottom = -126.0   # sits clear above the hotbar
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
	m.add_child(layer)

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

# ---------- Boss bar ----------
# A wide bar at the bottom middle of the screen with the boss's name. When it is hurt, a pale
# strip lingers and then drains down to the real health, like in Elden Ring.

const BOSS_BAR_W := 520.0
const BOSS_BAR_H := 14.0

var boss_root: Control
var boss_label: Label
var boss_trail: ColorRect
var boss_fill: ColorRect
var boss_trail_frac := 1.0
var boss_trail_hold := 0.0
var boss_last_frac := 1.0
var boss_last: Creature = null

func setup_boss_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	boss_root = Control.new()
	boss_root.anchor_left = 0.5
	boss_root.anchor_right = 0.5
	boss_root.anchor_top = 1.0
	boss_root.anchor_bottom = 1.0
	boss_root.offset_left = -BOSS_BAR_W * 0.5
	boss_root.offset_right = BOSS_BAR_W * 0.5
	boss_root.offset_top = -200.0
	boss_root.offset_bottom = -150.0
	boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_root.visible = false
	layer.add_child(boss_root)

	boss_label = Label.new()
	boss_label.position = Vector2(0, 0)
	boss_label.size = Vector2(BOSS_BAR_W, 28)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 22)
	boss_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	boss_label.add_theme_constant_override("outline_size", 6)
	boss_root.add_child(boss_label)

	var back := ColorRect.new()
	back.position = Vector2(0, 32)
	back.size = Vector2(BOSS_BAR_W, BOSS_BAR_H)
	back.color = Color(0.03, 0.03, 0.03, 0.75)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_root.add_child(back)
	boss_trail = ColorRect.new()
	boss_trail.position = Vector2(0, 32)
	boss_trail.size = Vector2(BOSS_BAR_W, BOSS_BAR_H)
	boss_trail.color = Color(0.9, 0.75, 0.25)
	boss_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_root.add_child(boss_trail)
	boss_fill = ColorRect.new()
	boss_fill.position = Vector2(0, 32)
	boss_fill.size = Vector2(BOSS_BAR_W, BOSS_BAR_H)
	boss_fill.color = Color(0.65, 0.1, 0.08)
	boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_root.add_child(boss_fill)
	m.add_child(layer)

# boss is the creature to show, or null to hide the bar.
func update_boss_bar(delta: float, boss: Creature) -> void:
	if boss == null or not is_instance_valid(boss):
		boss_root.visible = false
		boss_last = null
		return
	if boss != boss_last:
		boss_last = boss
		boss_trail_frac = 1.0
		boss_last_frac = 1.0
		boss_trail_hold = 0.0
	boss_root.visible = true
	boss_label.text = boss.boss_name
	var frac := clampf(boss.health / boss.max_health, 0.0, 1.0)
	if frac < boss_last_frac:
		boss_trail_hold = 0.8   # the pale strip waits a moment before it drains
	boss_last_frac = frac
	boss_trail_hold -= delta
	if boss_trail_frac > frac:
		if boss_trail_hold <= 0.0:
			boss_trail_frac = maxf(frac, boss_trail_frac - delta * 0.35)
	else:
		boss_trail_frac = frac
	boss_fill.size.x = BOSS_BAR_W * frac
	boss_trail.size.x = BOSS_BAR_W * boss_trail_frac
	boss_fill.color = Color(0.85, 0.15, 0.05) if boss.enraged else Color(0.65, 0.1, 0.08)
