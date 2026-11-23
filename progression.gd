class_name Progression
extends CanvasLayer

# The colony's long-term goal. Your colony climbs tiers. Each tier has a few objectives; finishing them
# all unlocks the next tier and new recipes. Press Tab to see the goals.
# Part 2 will add biome relics and stronghold queens as the late objectives.

signal tier_changed(tier: int)

const FINAL_TIER := 4          # tier 4 is the last one. Finishing it wins the campaign.
const TIER_NAMES := {1: "Founding", 2: "Settlement", 3: "Stronghold", 4: "Dominion"}

# Which tier a recipe is unlocked at. Anything not listed is open from the start.
const RECIPE_TIERS := {
	"resin_trap": 2, "pit_trap": 2, "crystal_lamp": 2,
	"acid_trap": 3, "collapse_trap": 3,
}

# Each objective: id, text, goal. How far along you are is worked out in value().
const OBJECTIVES := {
	1: [
		{"id": "queen", "text": "Place your queen", "goal": 1},
		{"id": "box", "text": "Build a wooden box", "goal": 1},
		{"id": "sugar", "text": "Store sugar in your boxes", "goal": 40},
	],
	2: [
		{"id": "fiber", "text": "Store leaf fiber", "goal": 60},
		{"id": "water", "text": "Store water in a barrel", "goal": 100},
		{"id": "crystal", "text": "Store cave crystals (dig down to the caves)", "goal": 5},
	],
	3: [
		{"id": "resin", "text": "Store resin", "goal": 40},
		{"id": "traps", "text": "Place traps (any kind) around your colony", "goal": 2},
		{"id": "colony", "text": "Destroy a termite colony", "goal": 1},
	],
	4: [
		{"id": "relics", "text": "Store biome relics (golden beams in the far biomes). They break the Great Mound's ward", "goal": 3},
		{"id": "great", "text": "Destroy the Great Mound and its queen", "goal": 1},
	],
}

var m: Main
var tier := 1                 # the tier you are working on. FINAL_TIER + 1 once the campaign is won.
var done := {}                # objective id -> true, once reached (it stays done even if you spend the resources)
var colonies_destroyed := 0
var great_destroyed := false   # true once the Great Mound's queen is dead
var hint_timer := 0.0
var tracking := false         # the termite tracker (U) is on
var track_search := 0.0       # time until the nearest colony is looked up again
var track_target := {}        # {"pos": Vector2, "dist": float} of the nearest living colony
var relic_target := {}        # {"pos": Vector2, "dist": float} of the nearest relic, looked up while tier 4 needs relics
var relic_search := 0.0
var relic_hint := ""
var check_timer := 0.0
var panel: PanelContainer
var label: Label
var open := false

func setup(main: Main) -> void:
	m = main
	layer = 5
	panel = PanelContainer.new()
	panel.visible = false
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -430.0
	panel.offset_right = -16.0
	panel.offset_top = 150.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.05, 0.86)
	style.border_color = Color(0.8, 0.65, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 17)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(380, 0)
	panel.add_child(label)
	add_child(panel)

func toggle() -> void:
	open = not open
	panel.visible = open
	if open:
		refresh()

# ---------- Progress ----------

# How far along an objective is.
func value(id: String) -> int:
	match id:
		"queen":
			return 1 if is_instance_valid(m.queen) else 0
		"box":
			return get_tree().get_nodes_in_group("containers").size()
		"sugar", "fiber", "water", "crystal", "resin":
			return m.stored(id if id != "crystal" else "crystal")
		"traps":
			var n := 0
			for p in get_tree().get_nodes_in_group("placeables"):
				if is_instance_valid(p) and (p.type == "trap" or Placeable.DEFENSE.has(p.type)):
					n += 1
			return n
		"colony":
			return mini(colonies_destroyed, 1)
		"relics":
			return m.stored("relic")
		"great":
			return 1 if great_destroyed else 0
	return 0

func is_done(obj: Dictionary) -> bool:
	return done.has(obj["id"])

func unlocked(recipe: String) -> bool:
	return tier >= int(RECIPE_TIERS.get(recipe, 1))

func locked_text(recipe: String) -> String:
	var t := int(RECIPE_TIERS.get(recipe, 1))
	return "Locked. Reach tier %d (%s)." % [t, TIER_NAMES[t]]

func colony_destroyed(colony: Dictionary) -> void:
	colonies_destroyed += 1
	if colony.get("great", false):
		great_destroyed = true

func _process(delta: float) -> void:
	if m == null or m.ant == null:
		return
	check_timer -= delta
	if check_timer > 0.0:
		return
	check_timer = 0.5
	if tier == FINAL_TIER and not done.has("relics"):
		relic_search -= 0.5
		if relic_search <= 0.0:
			relic_search = 3.0
			relic_target = m.content.nearest_relic(Vector2(m.ant.global_position.x, m.ant.global_position.z))
	if tracking:
		track_search -= 0.5
		if track_search <= 0.0:
			track_search = 3.0
			track_target = nearest_colony()
	TermiteQueen.ward_up = not done.has("relics")   # the Great Mound queen is shielded until the relics are gathered
	if tier > FINAL_TIER:
		return
	var all_done := true
	for obj in OBJECTIVES[tier]:
		if is_done(obj):
			continue
		if value(obj["id"]) >= int(obj["goal"]):
			done[obj["id"]] = true
			announce("Goal reached: %s" % obj["text"])
		else:
			all_done = false
	if all_done:
		advance()
	hint_timer -= 0.5
	if open:
		refresh()

func advance() -> void:
	tier += 1
	if tier > FINAL_TIER:
		announce("Your colony rules the land. You have won! You can keep playing.")
	else:
		var opened: Array[String] = []
		for r in RECIPE_TIERS:
			if int(RECIPE_TIERS[r]) == tier:
				opened.append(Crafting.RECIPES[r]["label"])
		var extra := ("  New recipes: " + ", ".join(opened)) if not opened.is_empty() else ""
		announce("Tier %d reached: %s!%s" % [tier, TIER_NAMES[tier], extra])
	tier_changed.emit(tier)
	if open:
		refresh()

func announce(text: String) -> void:
	m.show_message(text)
	m.message_time = 6.0

# ---------- Termite tracker ----------

func toggle_tracker() -> bool:
	tracking = not tracking
	track_search = 0.0
	return tracking

# The nearest termite colony that is still alive, within about 2,200 units. The Great Mound is left out. It has its own hint.
func nearest_colony() -> Dictionary:
	var me := Vector2(m.ant.global_position.x, m.ant.global_position.z)
	var home := Vector2i(floori(me.x / Main.MOUND_CELL), floori(me.y / Main.MOUND_CELL))
	var best := {}
	var best_d := 1.0e9
	for dx in range(-7, 8):
		for dz in range(-7, 8):
			var cell := home + Vector2i(dx, dz)
			if cell == Main.GREAT_CELL:
				continue
			var site: Dictionary = m.terrain.mound_site(cell)
			if site.is_empty():
				continue
			var cached: Dictionary = m.terrain.mound_cells.get(cell, {})
			if not cached.is_empty() and cached.get("dead", false):
				continue
			var p := Vector2(float(site["x"]), float(site["z"]))
			var d := me.distance_to(p)
			if d < best_d:
				best_d = d
				best = {"pos": p, "dist": d, "cell": cell}
	return best

# The queen of the colony you are at, as a world position, or null when you are not at one.
func queen_position() -> Variant:
	var me3: Vector3 = m.ant.global_position
	var cells: Array = [Main.GREAT_CELL]
	if not track_target.is_empty():
		cells.append(track_target["cell"])
	for cell in cells:
		var mm: Dictionary = m.terrain.mound_cells.get(cell, {})
		if mm.is_empty() or mm.get("dead", false):
			continue
		var center: Vector3 = mm["center"]
		if Vector2(me3.x - center.x, me3.z - center.z).length() > float(mm["R"]) + 70.0:
			continue
		return mm["queen_pos"]
	return null

# Once you are at a colony, the tracker points to its queen: how far across and how far up or down.
func queen_line() -> String:
	var qp = queen_position()
	if qp == null:
		return ""
	var d: Vector3 = (qp as Vector3) - m.ant.global_position
	var across := Vector2(d.x, d.z)
	return "THE QUEEN is %d units %s of you and %d units %s you." % [int(across.length()), compass(across), int(absf(d.y)), "below" if d.y < 0.0 else "above"]

# What the compass at the top of the screen should mark.
func compass_targets() -> Array:
	var out: Array = []
	if tracking:
		var qp = queen_position()
		if qp != null:
			out.append({"pos": Vector2((qp as Vector3).x, (qp as Vector3).z), "label": "Queen", "color": Color(1.0, 0.9, 0.3)})
		elif not track_target.is_empty():
			out.append({"pos": track_target["pos"], "label": "Colony", "color": Color(1.0, 0.4, 0.3)})
	if tier == FINAL_TIER:
		var site: Dictionary = m.terrain.mound_site(Main.GREAT_CELL)
		if not site.is_empty() and not great_destroyed:
			out.append({"pos": Vector2(float(site["x"]), float(site["z"])), "label": "Great Mound", "color": Color(0.75, 0.5, 1.0)})
		if not done.has("relics") and not relic_target.is_empty():
			out.append({"pos": relic_target["pos"], "label": "Relic", "color": Color(1.0, 0.8, 0.3)})
	return out

func tracker_line() -> String:
	if not tracking:
		return ""
	var q := queen_line()
	if q != "":
		return q
	if track_target.is_empty():
		return "Termite tracker: no colony within about 2,200 units. Explore further."
	var me := Vector2(m.ant.global_position.x, m.ant.global_position.z)
	var dv: Vector2 = (track_target["pos"] as Vector2) - me
	return "Termite tracker: nearest colony about %d units %s   [U] off" % [int(dv.length()), compass(dv)]

# ---------- Hints ----------

func compass(v: Vector2) -> String:
	var names := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var idx := int(round(fposmod(v.angle(), TAU) / (TAU / 8.0))) % 8
	return names[idx]

func great_mound_hint() -> String:
	var site: Dictionary = m.terrain.mound_site(Main.GREAT_CELL)
	if site.is_empty():
		return ""
	var target := Vector2(float(site["x"]), float(site["z"]))
	var me := Vector2(m.ant.global_position.x, m.ant.global_position.z)
	var d := (target - me)
	return "The Great Mound lies about %d units %s of you." % [int(d.length()), compass(d)]

func relic_hint_text() -> String:
	if done.has("relics"):
		return "You have enough relics. The queen's ward is broken."
	if relic_target.is_empty():
		return "No relic within about 800 units. Explore the far biomes."
	var me := Vector2(m.ant.global_position.x, m.ant.global_position.z)
	var dv: Vector2 = (relic_target["pos"] as Vector2) - me
	return "Nearest relic: about %d units %s." % [int(dv.length()), compass(dv)]

# ---------- Display ----------

func hud_line() -> String:
	if tier > FINAL_TIER:
		return "Campaign won   [Tab] goals"
	var objs: Array = OBJECTIVES[tier]
	var n := 0
	for obj in objs:
		if is_done(obj):
			n += 1
	return "Tier %d: %s  (%d/%d)   [Tab] goals" % [tier, TIER_NAMES[tier], n, objs.size()]

func refresh() -> void:
	var t := ""
	if tier > FINAL_TIER:
		t = "CAMPAIGN WON\n\nYour colony rules the land."
		label.text = t
		return
	t = "TIER %d: %s\n" % [tier, TIER_NAMES[tier]]
	for obj in OBJECTIVES[tier]:
		var ok := is_done(obj)
		var have := mini(value(obj["id"]), int(obj["goal"])) if not ok else int(obj["goal"])
		t += "\n%s  %s" % ["[x]" if ok else "[ ]", obj["text"]]
		if int(obj["goal"]) > 1:
			t += "   %d / %d" % [have, int(obj["goal"])]
	var next_unlocks: Array[String] = []
	for r in RECIPE_TIERS:
		if int(RECIPE_TIERS[r]) == tier + 1:
			next_unlocks.append(Crafting.RECIPES[r]["label"])
	if tier == 3 and not done.has("colony"):
		t += "\n\nPress U to switch on the termite tracker. It points to the nearest living colony."
	if tier == FINAL_TIER:
		t += "\n\n" + great_mound_hint()
		t += "\n" + relic_hint_text()
	if tier < FINAL_TIER:
		t += "\n\nNext tier: %s" % TIER_NAMES[tier + 1]
		if not next_unlocks.is_empty():
			t += "\nUnlocks: " + ", ".join(next_unlocks)
	else:
		t += "\n\nFinish this to win the campaign."
	label.text = t
