class_name Crafting
extends CanvasLayer

# The craft menu (press C) and the hotbar. You craft items from the resources you
# are carrying. Crafted items go into the hotbar, and you place them from there.

signal crafted(type: String)

const SLOT_COUNT := 9

# Costs are paid from what you carry, not from storage. Change the numbers to tune.
const RECIPES := {
	"box": {
		"label": "Wooden box",
		"desc": "Stores resources and soil. Place it in a storage chamber.",
		"cost": {"fiber": 20},
		"size": Vector3(1.6, 1.2, 1.6),
		"color": Color(0.55, 0.36, 0.18),
		"caps": {"sugar": 100, "pebble": 100, "fiber": 100, "glow": 100, "silk": 100, "resin": 100, "crystal": 100, "relic": 20, "soil": 150},   # most one box holds of each
	},
	"barrel": {
		"label": "Water barrel",
		"desc": "Stores water for the whole colony.",
		"cost": {"fiber": 15, "pebble": 5},
		"size": Vector3(1.4, 1.8, 1.4),
		"color": Color(0.45, 0.30, 0.16),
		"caps": {"water": 300},
	},
	"lamp": {
		"label": "Glow lamp",
		"desc": "Glows softly. Place it in tunnels and chambers.",
		"cost": {"glow": 3},
		"size": Vector3(0.7, 1.0, 0.7),
		"color": Color(0.85, 1.0, 0.3),
	},
	"crystal_lamp": {
		"label": "Crystal lamp",
		"desc": "A cool violet light that reaches much farther than a glow lamp. Made from cave crystals.",
		"cost": {"crystal": 2},
		"size": Vector3(0.7, 1.0, 0.7),
		"color": Color(0.55, 0.5, 1.0),
	},
	"queen": {
		"label": "Queen",
		"desc": "Your colony's heart. You respawn here. Only one at a time.",
		"cost": {"sugar": 30, "fiber": 20, "pebble": 10},
		"size": Vector3(2.6, 1.8, 3.2),
		"color": Color(0.86, 0.76, 0.6),
	},
	"trap": {
		"label": "Silk trap",
		"desc": "A sticky web. Spiders that walk into it are slowed to a crawl. Catches 3 spiders, then wears out.",
		"cost": {"silk": 5},
		"size": Vector3(2.6, 0.3, 2.6),
		"color": Color(0.92, 0.95, 1.0),
	},
	"resin_trap": {
		"label": "Resin trap",
		"desc": "A sticky pool of resin. Any creature that steps in is held for 8 seconds. Catches 4, then hardens.",
		"cost": {"resin": 6},
		"size": Vector3(2.6, 0.3, 2.6),
		"color": Color(0.95, 0.6, 0.12),
	},
	"pit_trap": {
		"label": "Pit trap",
		"desc": "A hole covered with fiber. Whatever falls in is stuck for 6 seconds and takes 25 damage. Three uses.",
		"cost": {"fiber": 10, "pebble": 4},
		"size": Vector3(2.4, 0.3, 2.4),
		"color": Color(0.3, 0.22, 0.14),
	},
	"acid_trap": {
		"label": "Acid trap",
		"desc": "Bursts when stepped on and burns every creature nearby for 60 damage. Two uses.",
		"cost": {"resin": 4, "glow": 2},
		"size": Vector3(2.4, 0.3, 2.4),
		"color": Color(0.45, 0.9, 0.2),
	},
	"collapse_trap": {
		"label": "Collapse trap",
		"desc": "Seals a tunnel. When something steps on it, soil drops from the ceiling and buries the spot, hurting nearby creatures for 40. One use. You can dig through it later.",
		"cost": {"pebble": 8, "fiber": 6},
		"size": Vector3(2.4, 0.3, 2.4),
		"color": Color(0.55, 0.52, 0.5),
	},
}
const ORDER := ["box", "barrel", "lamp", "crystal_lamp", "queen", "trap", "resin_trap", "pit_trap", "acid_trap", "collapse_trap"]

var ant: Ant
var progression: Progression   # decides which recipes are unlocked
var items := {}              # item type -> how many you own
var slots: Array = []        # hotbar: the item type in each slot, or ""
var held_slot := -1          # the hotbar slot you are holding, or -1
var is_open := false

var menu: PanelContainer
var rows := {}               # recipe type -> {"cost": Label, "button": Button}
var slot_panels: Array = []
var slot_labels: Array = []

func _ready() -> void:
	for i in SLOT_COUNT:
		slots.append("")
	build_menu()
	build_hotbar()
	refresh_hotbar()

func _process(_delta: float) -> void:
	if is_open:
		refresh_menu()

# ---------- Items ----------

func is_unlocked(type: String) -> bool:
	return progression == null or progression.unlocked(type)

func can_craft(type: String) -> bool:
	if not is_unlocked(type):
		return false
	var cost: Dictionary = RECIPES[type]["cost"]
	for k in cost:
		if ant.inventory[k] < cost[k]:
			return false
	return true

func craft(type: String) -> void:
	if not can_craft(type):
		return
	var cost: Dictionary = RECIPES[type]["cost"]
	for k in cost:
		ant.inventory[k] -= cost[k]
	add_item(type)
	crafted.emit(type)
	refresh_menu()

func add_item(type: String, n: int = 1) -> void:
	items[type] = int(items.get(type, 0)) + n
	if not slots.has(type):
		var free := slots.find("")
		if free >= 0:
			slots[free] = type
	refresh_hotbar()

# The item type you are holding, or "" when your hands are empty.
func held_type() -> String:
	if held_slot < 0:
		return ""
	return slots[held_slot]

func consume_held() -> void:
	var t := held_type()
	if t == "":
		return
	items[t] = int(items[t]) - 1
	if items[t] <= 0:
		items.erase(t)
		slots[held_slot] = ""
		held_slot = -1
	refresh_hotbar()

func select_slot(i: int) -> void:
	if i < 0 or i >= SLOT_COUNT or slots[i] == "":
		return
	held_slot = -1 if held_slot == i else i
	refresh_hotbar()

func deselect() -> void:
	held_slot = -1
	refresh_hotbar()

func toggle_menu() -> void:
	is_open = not is_open
	menu.visible = is_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_open else Input.MOUSE_MODE_CAPTURED
	if is_open:
		refresh_menu()

# ---------- Craft menu ----------

func build_menu() -> void:
	menu = PanelContainer.new()
	menu.visible = false
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.custom_minimum_size = Vector2(460, 0)
	menu.add_theme_stylebox_override("panel", box_style(Color(0.08, 0.07, 0.06, 0.92), Color(0.8, 0.65, 0.35), 3))

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	menu.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	var title := Label.new()
	title.text = "Craft   (C to close)"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	var note := Label.new()
	note.text = "Costs come from the resources you are carrying."
	note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	col.add_child(note)

	# The list scrolls, so it never grows taller than the screen however many recipes there are.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	for type in ORDER:
		var info: Dictionary = RECIPES[type]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		list.add_child(row)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var name_label := Label.new()
		name_label.text = info["label"]
		name_label.add_theme_font_size_override("font_size", 18)
		text.add_child(name_label)
		var desc := Label.new()
		desc.text = info["desc"]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		text.add_child(desc)
		var cost_label := Label.new()
		text.add_child(cost_label)

		var button := Button.new()
		button.text = "Craft"
		button.custom_minimum_size = Vector2(90, 40)
		button.pressed.connect(craft.bind(type))
		row.add_child(button)
		rows[type] = {"cost": cost_label, "button": button}
	add_child(menu)

func refresh_menu() -> void:
	for type in ORDER:
		var cost: Dictionary = RECIPES[type]["cost"]
		var parts: Array[String] = []
		for k in cost:
			parts.append("%s %d/%d" % [Pickup.KINDS[k]["label"], ant.inventory[k], cost[k]])
		var ok := can_craft(type)
		var cost_label: Label = rows[type]["cost"]
		cost_label.text = "Needs: " + ",  ".join(parts)
		if not is_unlocked(type):
			cost_label.text = progression.locked_text(type)
			ok = false
		cost_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if ok else Color(1.0, 0.5, 0.45))
		(rows[type]["button"] as Button).disabled = not ok

# ---------- Hotbar ----------

func build_hotbar() -> void:
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -88.0
	bar.offset_bottom = -16.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	for i in SLOT_COUNT:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(70, 70)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		panel.add_child(label)
		bar.add_child(panel)
		slot_panels.append(panel)
		slot_labels.append(label)

func refresh_hotbar() -> void:
	if slot_panels.is_empty():
		return
	for i in SLOT_COUNT:
		var t: String = slots[i]
		var label: Label = slot_labels[i]
		if t == "":
			label.text = str(i + 1)
			label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		else:
			label.text = "%d\n%s\nx%d" % [i + 1, RECIPES[t]["label"], items[t]]
			label.add_theme_color_override("font_color", Color.WHITE)
		var border := Color(1.0, 0.85, 0.3) if i == held_slot else Color(1, 1, 1, 0.35)
		(slot_panels[i] as PanelContainer).add_theme_stylebox_override(
			"panel", box_style(Color(0, 0, 0, 0.5), border, 4 if i == held_slot else 2))

func box_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	return s
