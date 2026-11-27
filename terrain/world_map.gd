class_name WorldMap
extends Control

# The full-screen map (toggle with M, change zoom with Z). It is centered on you and shows
# a window of the world: close up by default, the whole world when fully zoomed out. The land
# is painted by biome and unexplored parts stay darker until you walk near them. Landmarks:
# your start, your queen, and the termite mounds you have spotted (with a line to the nearest).
# Up on the map is the -Z direction of the world; right is +X.

const SIZE := 384                 # the map picture is SIZE x SIZE pixels for the whole world
const REVEAL_RADIUS := 1000.0     # world units around you that become explored
const FOG_ALPHA := 0.6            # how dark the unexplored land is (the biomes still show)
const ZOOMS := [1500.0, 4000.0, 14400.0]   # world units across the map window
const BIOME_COLORS := [
	Color(0.25, 0.60, 0.22),   # forest
	Color(0.90, 0.78, 0.45),   # desert
	Color(0.58, 0.54, 0.50),   # highlands
	Color(0.88, 0.95, 0.98),   # tundra
	Color(0.30, 0.42, 0.25),   # swamp
	Color(0.85, 0.68, 0.25),   # savanna
	Color(0.45, 0.80, 0.30),   # plains
]
const BIOME_NAMES := ["Forest", "Desert", "Highlands", "Tundra", "Swamp", "Savanna", "Plains"]
const WATER_COLOR := Color(0.2, 0.45, 0.75)

var half := Main.HALF * 1.0
var biome_fn: Callable         # (x, z) -> biome index
var edge_fn: Callable          # (x, z) -> distance to the world's edge
var river_width := 17.0

var base_img: Image
var base_tex: ImageTexture
var fog_img: Image
var fog_tex: ImageTexture
var next_row := 0              # the biome picture is painted a few rows per frame
var zoom_index := 0

var player_pos := Vector3.ZERO
var player_dir := Vector2(0, -1)
var start_pos := Vector2(8, 8)
var queen_pos := Vector2.INF
var mounds: Array = []         # {"pos": Vector2, "dead": bool}
var trail := PackedVector2Array()   # your pheromone drops, as world (x, z)
var lakes: Array = []          # {"pos": Vector2, "radius": float, "outline": PackedVector2Array}
var cabins: Array = []         # world (x, z) of log cabins you have come near
var reveal_timer := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	base_img.fill(Color(0.1, 0.1, 0.1))
	base_tex = ImageTexture.create_from_image(base_img)
	fog_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	fog_img.fill(Color(0.02, 0.02, 0.03, FOG_ALPHA))
	fog_tex = ImageTexture.create_from_image(fog_img)

func cycle_zoom() -> void:
	zoom_index = (zoom_index + 1) % ZOOMS.size()

# Paints a few more rows of the biome picture. Called every frame until it is done.
func paint_step(rows: int = 4) -> void:
	if next_row >= SIZE or not biome_fn.is_valid():
		return
	for r in rows:
		if next_row >= SIZE:
			break
		var py := next_row
		for px in SIZE:
			var wx := (float(px) + 0.5) / SIZE * half * 2.0 - half
			var wz := (float(py) + 0.5) / SIZE * half * 2.0 - half
			var c: Color
			if edge_fn.call(wx, wz) < river_width + 20.0:
				c = WATER_COLOR
			else:
				c = BIOME_COLORS[int(biome_fn.call(wx, wz))]
			base_img.set_pixel(px, py, c)
		next_row += 1
	base_tex.update(base_img)

func world_to_px(x: float, z: float) -> Vector2:
	return Vector2((x + half) / (half * 2.0), (z + half) / (half * 2.0)) * SIZE

# Marks the land around the player as explored.
func reveal(x: float, z: float) -> void:
	var c := world_to_px(x, z)
	var r := REVEAL_RADIUS / (half * 2.0) * SIZE
	var x0 := maxi(0, int(c.x - r) - 1)
	var x1 := mini(SIZE - 1, int(c.x + r) + 1)
	var y0 := maxi(0, int(c.y - r) - 1)
	var y1 := mini(SIZE - 1, int(c.y + r) + 1)
	for px in range(x0, x1 + 1):
		for py in range(y0, y1 + 1):
			var d := Vector2(px + 0.5, py + 0.5).distance_to(c)
			if d <= r:
				var a := clampf((d - r * 0.7) / (r * 0.3), 0.0, 1.0) * FOG_ALPHA
				if a < fog_img.get_pixel(px, py).a:
					fog_img.set_pixel(px, py, Color(0.02, 0.02, 0.03, a))
	fog_tex.update(fog_img)

func update_player(pos: Vector3, forward: Vector3, delta: float) -> void:
	player_pos = pos
	player_dir = Vector2(forward.x, forward.z).normalized()
	reveal_timer -= delta
	if reveal_timer <= 0.0:
		reveal_timer = 0.5
		reveal(pos.x, pos.z)

func note_mound(pos: Vector2, dead: bool) -> void:
	for m in mounds:
		if (m["pos"] as Vector2).distance_to(pos) < 1.0:
			m["dead"] = dead
			return
	mounds.append({"pos": pos, "dead": dead})

func note_cabin(pos: Vector2) -> void:
	for c in cabins:
		if (c as Vector2).distance_to(pos) < 1.0:
			return
	cabins.append(pos)

func note_lake(pos: Vector2, radius: float, outline: PackedVector2Array) -> void:
	for l in lakes:
		if (l["pos"] as Vector2).distance_to(pos) < 1.0:
			return
	lakes.append({"pos": pos, "radius": radius, "outline": outline})

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func compass(v: Vector2) -> String:
	var a := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)   # 0 = north (-Z), 90 = east (+X)
	var names := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
	return names[int(roundf(a / 45.0)) % 8]

func _draw() -> void:
	var vp := size
	var side := minf(vp.x, vp.y) * 0.84
	var origin := (vp - Vector2(side, side)) * 0.5
	var rect := Rect2(origin, Vector2(side, side))
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.75))
	draw_rect(rect, Color(0.08, 0.08, 0.1))

	# The window of the world being shown.
	var span: float = ZOOMS[zoom_index]
	var ppos := Vector2(player_pos.x, player_pos.z)
	var vc := ppos if span < half * 2.0 else Vector2.ZERO
	var vmin := vc - Vector2(span, span) * 0.5
	var vmax := vc + Vector2(span, span) * 0.5
	# Part of that window that is inside the world, as a source region of the picture.
	var wmin := Vector2(maxf(vmin.x, -half), maxf(vmin.y, -half))
	var wmax := Vector2(minf(vmax.x, half), minf(vmax.y, half))
	var src := Rect2(world_to_px(wmin.x, wmin.y), world_to_px(wmax.x, wmax.y) - world_to_px(wmin.x, wmin.y))
	var dst := Rect2(origin + (wmin - vmin) / span * side, (wmax - wmin) / span * side)
	draw_texture_rect_region(base_tex, dst, src)
	draw_texture_rect_region(fog_tex, dst, src)
	draw_rect(rect, Color(0.95, 0.9, 0.75), false, 3.0)

	var to_screen := func(w: Vector2) -> Vector2:
		return origin + (w - vmin) / span * side
	var inside := func(p: Vector2) -> bool:
		return rect.grow(-10.0).has_point(p)

	# Lakes you have spotted, drawn to scale.
	var nearest_lake := -1
	var nearest_lake_d := INF
	for i in lakes.size():
		var l: Dictionary = lakes[i]
		var lp: Vector2 = to_screen.call(l["pos"])
		var lr := float(l["radius"]) / span * side
		if inside.call(lp):
			var poly := PackedVector2Array()
			for wp in l["outline"]:
				poly.append(to_screen.call(wp))
			draw_colored_polygon(poly, Color(0.2, 0.5, 0.95, 0.75))
			poly.append(poly[0])
			draw_polyline(poly, Color(0.85, 0.95, 1.0), 2.0)
			draw_string(font, lp + Vector2(-16, 6), "Lake", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0, 0, 0), 4)
			draw_string(font, lp + Vector2(-16, 6), "Lake", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.97, 1.0))
		var ld := ppos.distance_to(l["pos"]) - float(l["radius"])
		if ld < nearest_lake_d:
			nearest_lake_d = ld
			nearest_lake = i

	# Your pheromone trail.
	for tp in trail:
		var ts: Vector2 = to_screen.call(tp)
		if inside.call(ts):
			draw_circle(ts, 2.5, Color(0.3, 1.0, 0.25, 0.85))

	# Termite mounds you have spotted: red while the colony lives, grey once it is finished.
	var nearest := -1
	var nearest_d := INF
	for i in mounds.size():
		var m: Dictionary = mounds[i]
		if not m["dead"]:
			var d := ppos.distance_to(m["pos"])
			if d < nearest_d:
				nearest_d = d
				nearest = i
	if nearest >= 0:
		var np: Vector2 = to_screen.call(mounds[nearest]["pos"])
		var pp0: Vector2 = to_screen.call(ppos)
		if inside.call(np) and inside.call(pp0):
			draw_dashed_line(pp0, np, Color(1, 0.9, 0.3, 0.9), 2.0, 8.0)
	for m in mounds:
		var mp: Vector2 = to_screen.call(m["pos"])
		if not inside.call(mp):
			continue
		var col := Color(0.6, 0.6, 0.64) if m["dead"] else Color(0.95, 0.2, 0.1)
		var tri := PackedVector2Array([mp + Vector2(0, -15), mp + Vector2(13, 10), mp + Vector2(-13, 10)])
		draw_colored_polygon(tri, col)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0), 3.0)
		var label := "Colony gone" if m["dead"] else "Termite mound"
		draw_string(font, mp + Vector2(18, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0, 0, 0), 4)
		draw_string(font, mp + Vector2(18, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))

	# Log cabins.
	for cb in cabins:
		var cp: Vector2 = to_screen.call(cb)
		if not inside.call(cp):
			continue
		var roof := PackedVector2Array([cp + Vector2(-11, -1), cp + Vector2(0, -11), cp + Vector2(11, -1)])
		draw_rect(Rect2(cp + Vector2(-8, -1), Vector2(16, 10)), Color(0.55, 0.36, 0.18), true)
		draw_rect(Rect2(cp + Vector2(-8, -1), Vector2(16, 10)), Color(0, 0, 0), false, 2.0)
		draw_colored_polygon(roof, Color(0.7, 0.25, 0.15))
		draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[0]]), Color(0, 0, 0), 2.0)
		draw_string(font, cp + Vector2(14, 8), "Cabin", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0), 4)
		draw_string(font, cp + Vector2(14, 8), "Cabin", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))

	# Start.
	var sp: Vector2 = to_screen.call(start_pos)
	if inside.call(sp):
		draw_rect(Rect2(sp - Vector2(7, 7), Vector2(14, 14)), Color(1, 1, 1), true)
		draw_rect(Rect2(sp - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0), false, 3.0)
		draw_string(font, sp + Vector2(12, 22), "Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0), 4)
		draw_string(font, sp + Vector2(12, 22), "Start", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))

	# Your queen.
	if queen_pos != Vector2.INF:
		var qp: Vector2 = to_screen.call(queen_pos)
		if inside.call(qp):
			draw_circle(qp, 9.0, Color(1.0, 0.85, 0.3))
			draw_arc(qp, 9.0, 0, TAU, 24, Color(0, 0, 0), 3.0)
			draw_string(font, qp + Vector2(14, -6), "Your queen", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0), 4)
			draw_string(font, qp + Vector2(14, -6), "Your queen", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.5))

	# You: a big arrow pointing the way you face.
	var pp: Vector2 = to_screen.call(ppos)
	if inside.call(pp):
		var d := player_dir
		var sv := Vector2(-d.y, d.x)
		var arrow := PackedVector2Array([pp + d * 16.0, pp - d * 11.0 + sv * 10.0, pp - d * 5.0, pp - d * 11.0 - sv * 10.0])
		draw_colored_polygon(arrow, Color(1, 1, 0.2))
		draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]), Color(0, 0, 0), 3.0)

	# Top line: where you are, and where the nearest living mound is.
	var top := "Map   [M] close   [Z] zoom   you are at x %d, z %d" % [int(player_pos.x), int(player_pos.z)]
	draw_string(font, origin + Vector2(0, -34), top, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))
	var info := "No termite mound spotted yet. Explore, then check again."
	if nearest >= 0:
		var mpos: Vector2 = mounds[nearest]["pos"]
		info = "Nearest termite mound: %d units %s" % [int(nearest_d), compass(mpos - ppos)]
	draw_string(font, origin + Vector2(0, -10), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.4))
	var lake_info := "No lake spotted yet. Explore, then check again."
	if nearest_lake >= 0:
		var lpos: Vector2 = lakes[nearest_lake]["pos"]
		lake_info = "Nearest lake: %d units %s" % [maxi(0, int(nearest_lake_d)), compass(lpos - ppos)]
	draw_string(font, origin + Vector2(0, side + 44.0), lake_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.85, 1.0))
	draw_string(font, origin + Vector2(side - 260.0, side + 22.0), "Window: %d units across" % int(span), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.9, 0.9))
	var kx := origin.x
	for i in 6:
		draw_rect(Rect2(Vector2(kx, origin.y + side + 8.0), Vector2(14, 14)), BIOME_COLORS[i], true)
		draw_string(font, Vector2(kx + 20.0, origin.y + side + 21.0), BIOME_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
		kx += 78.0
