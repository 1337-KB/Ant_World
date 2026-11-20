class_name StorageUI
extends CanvasLayer

# The panel for a wooden box or water barrel. Press E near one to open it.
# Put moves what you carry into it. Take moves what it holds back to you.

const NAMES := {"soil": "Soil", "water": "Water"}

var ant: Ant
var is_open := false
var container: Placeable = null

var panel: PanelContainer
var title: Label
var rows_box: VBoxContainer
var rows := {}   # kind -> Label

func _ready() -> void:
	panel = PanelContainer.new()
	panel.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	style.border_color = Color(0.8, 0.65, 0.35)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	title = Label.new()
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 10)
	col.add_child(rows_box)
	add_child(panel)

func open(c: Placeable) -> void:
	container = c
	is_open = true
	title.text = "%s   (E to close)" % Crafting.RECIPES[c.type]["label"]

	for child in rows_box.get_children():
		child.queue_free()
	rows.clear()
	var caps: Dictionary = Crafting.RECIPES[c.type]["caps"]
	for kind in caps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var put := Button.new()
		put.text = "Put"
		put.custom_minimum_size = Vector2(70, 36)
		put.pressed.connect(move_in.bind(kind))
		row.add_child(put)
		var take := Button.new()
		take.text = "Take"
		take.custom_minimum_size = Vector2(70, 36)
		take.pressed.connect(move_out.bind(kind))
		row.add_child(take)
		rows_box.add_child(row)
		rows[kind] = label

	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()

func close() -> void:
	is_open = false
	container = null
	panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	if not is_open:
		return
	# Walked away, or the container is gone.
	if not is_instance_valid(container) or container.global_position.distance_to(ant.global_position) > 8.0:
		close()
		return
	refresh()

func kind_name(kind: String) -> String:
	if NAMES.has(kind):
		return NAMES[kind]
	return Pickup.KINDS[kind]["label"]

func refresh() -> void:
	for kind in rows:
		var label: Label = rows[kind]
		label.text = "%s     stored %d / %d     carrying %d / %d" % [
			kind_name(kind), int(container.stock.get(kind, 0.0)), int(container.cap(kind)),
			int(ant.carried(kind)), int(ant.carry_cap(kind))]

# Everything you carry of this kind that fits.
func move_in(kind: String) -> void:
	var have := ant.carried(kind)
	var room := container.cap(kind) - float(container.stock.get(kind, 0.0))
	var n := minf(have, room)
	if kind != "soil" and kind != "water":
		n = floorf(n)
	if n <= 0.0:
		return
	ant.set_carried(kind, have - n)
	container.stock[kind] = float(container.stock.get(kind, 0.0)) + n
	refresh()

# As much as you have room to carry.
func move_out(kind: String) -> void:
	var stored := float(container.stock.get(kind, 0.0))
	var room := ant.carry_cap(kind) - ant.carried(kind)
	var n := minf(stored, room)
	if kind != "soil" and kind != "water":
		n = floorf(n)
	if n <= 0.0:
		return
	ant.set_carried(kind, ant.carried(kind) + n)
	container.stock[kind] = stored - n
	refresh()
