class_name DebugTools
extends RefCounted

# Test helpers. The backslash key (\) teleports you to the next test spot (Shift+\ goes back): the start, the nearest
# lake shore, the nearest termite mound, the Great Mound, the river edge, and a chunk corner far
# from the start (to test streaming). The world loads around you after the jump, and the ant waits
# on the spot until the ground under it is ready, so you will not fall through. Use these spots to
# check terrain edits, water, colonies and streaming after any big change.

var m: Main
var spots: Array = []
var current := -1

func setup(main: Main) -> void:
	m = main

func build_spots() -> void:
	spots.clear()
	spots.append({"name": "Start", "xz": Main.STORAGE_XZ})
	var lake := nearest_lake()
	if lake.size() == 2:
		spots.append({"name": "Nearest lake shore", "xz": lake[0] + Vector2(float(lake[1]) + 4.0, 0.0)})
	var mound := nearest_mound()
	if not mound.is_empty():
		spots.append({"name": "Nearest termite mound", "xz": Vector2(float(mound["x"]), float(mound["z"])) + Vector2(float(mound["R"]) + 8.0, 0.0)})
	var great := m.terrain.mound_at_cell(Main.GREAT_CELL)
	if not great.is_empty():
		spots.append({"name": "Great Mound", "xz": Vector2(float(great["x"]), float(great["z"])) + Vector2(float(great["R"]) + 8.0, 0.0)})
	# The nearest spot of every biome, found by scanning outward from the start. The Output panel
	# also prints how much of the scanned world each biome covers.
	var nearest := {}
	var counts := {}
	var total := 0
	for ix in range(-70, 71):
		for iz in range(-70, 71):
			var p := Vector2(float(ix), float(iz)) * 60.0
			var b := m.terrain.biome_at(p.x, p.y)
			counts[b] = int(counts.get(b, 0)) + 1
			total += 1
			if b != Main.FOREST and (not nearest.has(b) or p.length() < (nearest[b] as Vector2).length()):
				nearest[b] = p
	for b in counts:
		print("[biome] %s: %.1f%% of the scanned area" % [Main.BIOME_NAMES[b], 100.0 * float(counts[b]) / float(total)])
	for b in nearest:
		spots.append({"name": "Nearest " + String(Main.BIOME_NAMES[b]), "xz": nearest[b]})
	spots.append({"name": "River edge", "xz": Vector2(float(Main.HALF - Main.RIVER_WIDTH - 6), 0.0)})
	spots.append({"name": "Chunk corner far away", "xz": Vector2(640.0, 640.0)})

func nearest_lake() -> Array:
	var best := []
	var best_d := INF
	for cx in range(-4, 5):
		for cz in range(-4, 5):
			for lk in m.terrain.pools_at((float(cx) + 0.5) * Main.POOL_CELL, (float(cz) + 0.5) * Main.POOL_CELL):
				if lk.get("lake", false):
					var p := Vector2(float(lk["x"]), float(lk["z"]))
					if p.length() < best_d:
						best_d = p.length()
						best = [p, float(lk["radius"])]
	return best

func nearest_mound() -> Dictionary:
	var best := {}
	var best_d := INF
	for cx in range(-12, 13):
		for cz in range(-12, 13):
			var cell := Vector2i(cx, cz)
			if cell == Main.GREAT_CELL:
				continue
			var mc := m.terrain.mound_at_cell(cell)
			if mc.is_empty():
				continue
			var d := Vector2(float(mc["x"]), float(mc["z"])).length()
			if d < best_d:
				best_d = d
				best = mc
	return best

# Period key: a dragonfly appears high in front of you (awake even at night), for testing.
func force_dragonfly() -> void:
	var cam := m.ant.camera
	var spot := m.ant.global_position - cam.global_transform.basis.z * 20.0
	spot.y = m.terrain.ground_height(spot.x, spot.z) + 10.0
	var d := m.pop.spawn_dragonfly(spot)
	d.set_active(true)

# Semicolon key: a tunnel worm bursts out of the ground a few steps in front of you, for testing.
func force_worm() -> void:
	var cam := m.ant.camera
	var spot := m.ant.global_position - cam.global_transform.basis.z * 5.0 + m.ant.basis.y * 0.8
	m.pop.spawn_worm(spot)

# Comma key: a boss bursts out in front of you, cycling spider, beetle, centipede, worm. For testing.
var boss_index := 0
func force_boss() -> void:
	var cam := m.ant.camera
	var spot := m.ant.global_position - cam.global_transform.basis.z * 14.0
	spot.y = m.terrain.ground_height(spot.x, spot.z) + 0.5
	var kinds := ["spider", "beetle", "centipede", "worm"]
	var kind: String = kinds[boss_index % kinds.size()]
	boss_index += 1
	if kind == "worm":
		m.pop.spawn_worm(m.ant.global_position - cam.global_transform.basis.z * 6.0 + m.ant.basis.y * 0.8, true)
	else:
		m.pop.spawn_boss(kind, spot)

func teleport(step: int) -> void:
	if spots.is_empty():
		build_spots()
	current = posmod(current + step, spots.size())
	var s: Dictionary = spots[current]
	var xz: Vector2 = s["xz"]
	var y := m.terrain.ground_height(xz.x, xz.y) + 3.0
	m.ant.global_position = Vector3(xz.x, y, xz.y)
	m.ant.velocity = Vector3.ZERO
	m.show_message("Test spot %d/%d: %s (%d, %d)" % [current + 1, spots.size(), s["name"], int(xz.x), int(xz.y)])

# Prints the closest mounds to the start in the Output panel, so you can walk straight to one.
func print_nearest_mounds() -> void:
	var found := []
	for cx in range(-12, 13):
		for cz in range(-12, 13):
			var mc := m.terrain.mound_at_cell(Vector2i(cx, cz))
			if not mc.is_empty():
				found.append(Vector2(float(mc["x"]), float(mc["z"])))
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	print("Nearest termite mounds (x, z):")
	for i in mini(6, found.size()):
		print("  ", found[i].round(), "  distance ", int(found[i].length()))

func print_nearest_lakes() -> void:
	var found := []
	for cx in range(-4, 5):
		for cz in range(-4, 5):
			for lk in m.terrain.pools_at((float(cx) + 0.5) * Main.POOL_CELL, (float(cz) + 0.5) * Main.POOL_CELL):
				if lk.get("lake", false):
					found.append(Vector2(float(lk["x"]), float(lk["z"])))
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	print("Nearest lakes (x, z):")
	for i in mini(5, found.size()):
		print("  ", found[i].round(), "  distance ", int(found[i].length()))
