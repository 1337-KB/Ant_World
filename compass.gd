class_name Compass
extends CanvasLayer

# A compass strip across the top of the screen. It shows which way you are facing (N, E, S, W)
# and little markers for what you are tracking: termite colonies, the queen, the Great Mound, relics.
# A marker that is off to the side sits at the edge of the strip with an arrow. Turn toward it until it is in the middle.
# North is the direction of -Z on the map. East is +X.

const WIDTH := 600.0
const HEIGHT := 54.0
const SPAN := PI   # the strip shows 90 degrees either side of where you face

var m: Main
var strip: Control

func setup(main: Main) -> void:
	m = main
	layer = 4
	strip = Control.new()
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.offset_left = -WIDTH * 0.5
	strip.offset_right = WIDTH * 0.5
	strip.offset_top = 8.0
	strip.offset_bottom = 8.0 + HEIGHT
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.draw.connect(_draw_strip)
	add_child(strip)

func _process(_delta: float) -> void:
	if m == null or m.ant == null or m.crafting == null or m.storage_ui == null:
		return
	strip.visible = not (m.crafting.is_open or m.storage_ui.is_open)
	if strip.visible:
		strip.queue_redraw()

# 0 = north, 90 = east, clockwise. For a direction on the ground given as (x, z).
func bearing(v: Vector2) -> float:
	return atan2(v.x, -v.y)

func heading() -> float:
	var f: Vector3 = -m.ant.camera.global_transform.basis.z
	return atan2(f.x, -f.z)

func x_for(rel: float) -> float:
	return WIDTH * 0.5 + rel / SPAN * WIDTH

func _draw_strip() -> void:
	var font := ThemeDB.fallback_font
	strip.draw_rect(Rect2(0, 0, WIDTH, HEIGHT), Color(0.05, 0.05, 0.05, 0.6))
	strip.draw_rect(Rect2(0, 0, WIDTH, HEIGHT), Color(0.8, 0.65, 0.35, 0.8), false, 2.0)
	var h := heading()

	# Tick marks every 15 degrees, with the compass points labelled.
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	for deg in range(0, 360, 15):
		var rel := wrapf(deg_to_rad(float(deg)) - h, -PI, PI)
		if absf(rel) > SPAN * 0.5:
			continue
		var x := x_for(rel)
		if names.has(deg):
			var big := deg % 90 == 0
			strip.draw_line(Vector2(x, 0), Vector2(x, 10), Color(1, 1, 1, 0.9), 2.0)
			strip.draw_string(font, Vector2(x - 20, 29), names[deg], HORIZONTAL_ALIGNMENT_CENTER, 40.0,
					22 if big else 16, Color(1.0, 0.85, 0.4) if deg == 0 else Color(1, 1, 1, 0.95 if big else 0.7))
		else:
			strip.draw_line(Vector2(x, 0), Vector2(x, 6), Color(1, 1, 1, 0.45), 1.0)

	# Where you are facing.
	strip.draw_colored_polygon(PackedVector2Array([Vector2(WIDTH * 0.5 - 6, HEIGHT), Vector2(WIDTH * 0.5 + 6, HEIGHT), Vector2(WIDTH * 0.5, HEIGHT - 9)]), Color(1, 1, 1, 0.95))

	# What you are tracking.
	var me := Vector2(m.ant.global_position.x, m.ant.global_position.z)
	for t in m.progression.compass_targets():
		var dv: Vector2 = (t["pos"] as Vector2) - me
		var rel := wrapf(bearing(dv) - h, -PI, PI)
		var off := absf(rel) > SPAN * 0.5
		var x := x_for(clampf(rel, -SPAN * 0.5, SPAN * 0.5))
		var col: Color = t["color"]
		var y := 36.0
		if off:
			var dir := 1.0 if rel > 0.0 else -1.0
			strip.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 8), Vector2(x, y + 8), Vector2(x + dir * 10, y)]), col)
		else:
			strip.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 9), Vector2(x + 8, y), Vector2(x, y + 9), Vector2(x - 8, y)]), col)
			strip.draw_polyline(PackedVector2Array([Vector2(x, y - 9), Vector2(x + 8, y), Vector2(x, y + 9), Vector2(x - 8, y), Vector2(x, y - 9)]), Color(0, 0, 0, 0.8), 1.5)
		var label := "%s %d" % [t["label"], int(dv.length())]
		var lx := clampf(x - 50, 2.0, WIDTH - 102.0)
		strip.draw_string(font, Vector2(lx, HEIGHT + 16), label, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 14, col)
