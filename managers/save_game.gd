class_name SaveGame
extends Node

# Saving and loading. The world is made from a seed, so only what you CHANGED is saved:
# the chunks you dug or filled, your structures and what they hold, your inventory and class,
# the time, the map you have uncovered, and which termite colonies you destroyed.
#
# F5 saves by hand. The game also saves every minute and when you close the window.
# Shift+F9 deletes the save and starts a new world.

const PATH := "user://colony_save.dat"
const TMP := "user://colony_save.tmp"
const VERSION := 1
const AUTOSAVE_SECONDS := 60.0
const SPAWN_CHECK_SECONDS := 0.5

var m: Main
var data := {}                 # what was read from disk. Empty on a new world.
var has_save := false
var chunk_cache := {}          # Vector3i -> {"d": density bytes, "m": material bytes}, one per changed chunk
var dirty_chunks := {}         # chunks changed since they were last copied into the cache
var saved_chunks := {}         # saved chunks waiting for their column to be generated
var pending_things: Array = [] # saved structures waiting for the ground under them to exist
var timer := 0.0
var spawn_timer := 0.0
var task_id := -1
var disabled := false          # true while starting a new world, so nothing saves over it

func setup(main: Main) -> void:
	m = main

# ---------- Reading ----------

func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var raw_size := int(f.get_64())
	var packed := f.get_buffer(f.get_length() - f.get_position())
	f.close()
	var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.is_empty():
		push_warning("Save file could not be read. Starting a new world.")
		return
	var d = bytes_to_var(raw)
	if typeof(d) != TYPE_DICTIONARY or int(d.get("version", 0)) != VERSION:
		push_warning("Save file is from another version. Starting a new world.")
		return
	data = d
	has_save = true
	chunk_cache = data.get("chunks", {})
	saved_chunks = chunk_cache.duplicate()
	pending_things = data.get("things", []).duplicate()

# Termite colonies you destroyed stay destroyed. Call after the noise is set up, before any ground exists.
func restore_early() -> void:
	if not has_save:
		return
	for cell in data.get("dead_mounds", []):
		var mm: Dictionary = m.terrain.mound_at_cell(cell)
		if not mm.is_empty():
			mm["dead"] = true
			mm["alive"] = false
	m.pop.restore_live_state(data.get("live_colonies", []))
	m.atmos.day_time = float(data.get("day_time", m.atmos.day_time))
	m.atmos.day_count = int(data.get("day_count", m.atmos.day_count))
	var pr: Dictionary = data.get("progress", {})
	if not pr.is_empty():
		m.progression.tier = int(pr.get("tier", 1))
		m.progression.done = (pr.get("done", {}) as Dictionary).duplicate()
		m.progression.colonies_destroyed = int(pr.get("colonies", 0))
		m.progression.great_destroyed = bool(pr.get("great", false))
		for k in pr.get("relics_taken", []):
			m.content.relics_taken[k] = true
		TermiteQueen.ward_up = not m.progression.done.has("relics")

# Called while ground is generated: swaps in your saved version of a chunk. True if it did.
func apply_saved_chunk(cpos: Vector3i) -> bool:
	if not saved_chunks.has(cpos):
		return false
	var e: Dictionary = saved_chunks[cpos]
	saved_chunks.erase(cpos)
	var chunk := m.world.get_or_create_chunk(cpos)
	chunk.density = (e["d"] as PackedByteArray).to_float32_array()
	chunk.material = e["m"]
	m.stream.edited_cols[Vector2i(cpos.x, cpos.z)] = true
	return true

func restore_ant() -> void:
	if not has_save:
		return
	var a: Dictionary = data.get("ant", {})
	if a.is_empty():
		return
	var ant: Ant = m.ant
	ant.global_transform = a["xf"]
	ant.role = int(a.get("role", 0))
	ant.max_health = ant.stat("health")
	ant.health = minf(float(a.get("health", ant.max_health)), ant.max_health)
	var inv: Dictionary = a.get("inv", {})
	for k in inv:
		if ant.inventory.has(k):
			ant.inventory[k] = int(inv[k])
	ant.armor = clampi(int(a.get("armor", 0)), 0, Ant.ARMOR_MAX)
	ant.show_armor()
	ant.soil = float(a.get("soil", 0.0))
	ant.water = float(a.get("water", 0.0))
	ant.energy = float(a.get("energy", ant.energy))
	ant.acid = float(a.get("acid", ant.acid))
	ant.rocks = int(a.get("rocks", 0))
	ant.spawn_point = a.get("spawn", ant.spawn_point)
	ant.apply_role_look()

func restore_crafting() -> void:
	if not has_save:
		return
	var c: Dictionary = data.get("craft", {})
	if c.is_empty():
		return
	m.crafting.items = (c["items"] as Dictionary).duplicate()
	var slots: Array = c["slots"]
	for i in mini(slots.size(), m.crafting.slots.size()):
		m.crafting.slots[i] = slots[i]
	m.crafting.refresh_hotbar()

func restore_map() -> void:
	if not has_save:
		return
	var mp: Dictionary = data.get("map", {})
	if mp.is_empty():
		return
	var wm: WorldMap = m.world_map
	var img := Image.new()
	if img.load_png_from_buffer(mp.get("fog", PackedByteArray())) == OK:
		img.convert(Image.FORMAT_RGBA8)
		if img.get_size() == wm.fog_img.get_size():
			wm.fog_img = img
			wm.fog_tex.update(img)
	wm.lakes = mp.get("lakes", []).duplicate()
	wm.mounds = mp.get("mounds", []).duplicate()

# ---------- Per frame ----------

func _process(delta: float) -> void:
	if disabled or m == null or m.ant == null:
		return
	timer += delta
	if timer >= AUTOSAVE_SECONDS:
		timer = 0.0
		save_now(false, false)
	spawn_timer -= delta
	if spawn_timer <= 0.0 and not pending_things.is_empty():
		spawn_timer = SPAWN_CHECK_SECONDS
		spawn_ready_things()

func note_edited(cpos: Vector3i) -> void:
	dirty_chunks[cpos] = true

# Saved structures appear once the ground under them exists, so they never fall into empty space.
func spawn_ready_things() -> void:
	for t in pending_things.duplicate():
		var pos: Vector3 = (t["xf"] as Transform3D).origin
		var col: Vector2i = m.stream.col_of(pos)
		if not m.stream.col_data.has(col):
			continue
		var layer := floori(pos.y / float(Chunk.SIZE))
		if layer - 1 < int(m.stream.col_deep_from.get(col, Main.CY_MIN)) and int(m.stream.col_deep_from.get(col, Main.CY_MIN)) > Main.CY_MIN:
			continue
		pending_things.erase(t)
		if t["kind"] == "piece":
			m.building.spawn_piece(t["type"], t["xf"])
		else:
			var p: Placeable = m.building.spawn_placeable(t["type"], t["xf"])
			p.stock = (t.get("stock", {}) as Dictionary).duplicate()
			p.health = float(t.get("health", p.health))
			p.uses_left = int(t.get("uses", p.uses_left))
			p.defense_uses = int(t.get("duses", p.defense_uses))
			if p.has_method("update_health_label"):
				p.update_health_label()

# ---------- Writing ----------

func capture() -> Dictionary:
	# Copy any chunks changed since the last save into the cache.
	for c in dirty_chunks:
		var chunk := m.world.get_chunk(c)
		if chunk != null:
			chunk_cache[c] = {"d": chunk.density.to_byte_array(), "m": chunk.material}
	dirty_chunks.clear()

	var things: Array = []
	for p in Registry.of("placeables"):
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			continue
		things.append({
			"kind": "placeable", "type": p.type, "xf": p.global_transform,
			"stock": p.stock.duplicate(), "health": p.health, "uses": p.uses_left, "duses": p.defense_uses,
		})
	for p in Registry.of("pieces"):
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			continue
		things.append({"kind": "piece", "type": p.type, "xf": p.global_transform})
	things.append_array(pending_things)

	var dead: Array = []
	for cell in m.terrain.mound_cells:
		var mm: Dictionary = m.terrain.mound_cells[cell]
		if not mm.is_empty() and mm.get("dead", false):
			dead.append(cell)

	var ant: Ant = m.ant
	var wm: WorldMap = m.world_map
	return {
		"version": VERSION,
		"chunks": chunk_cache.duplicate(),
		"things": things,
		"ant": {
			"xf": ant.global_transform, "health": ant.health, "role": ant.role,
			"inv": ant.inventory.duplicate(), "soil": ant.soil, "water": ant.water,
			"armor": ant.armor, "energy": ant.energy, "acid": ant.acid, "rocks": ant.rocks, "spawn": ant.spawn_point,
		},
		"craft": {"items": m.crafting.items.duplicate(), "slots": m.crafting.slots.duplicate()},
		"day_time": m.atmos.day_time,
		"day_count": m.atmos.day_count,
		"progress": {"tier": m.progression.tier, "done": m.progression.done.duplicate(), "colonies": m.progression.colonies_destroyed, "great": m.progression.great_destroyed, "relics_taken": m.content.relics_taken.keys()},
		"dead_mounds": dead,
		"live_colonies": m.pop.live_colony_state(),
		"map": {"fog": wm.fog_img.save_png_to_buffer(), "lakes": wm.lakes.duplicate(true), "mounds": wm.mounds.duplicate(true)},
	}

# Collecting the data is quick. Compressing and writing it happens on another thread, so there is no hitch.
func save_now(announce: bool = true, wait: bool = false) -> void:
	if disabled or m == null or m.ant == null or m.crafting == null:
		return
	if task_id >= 0:
		if not WorkerThreadPool.is_task_completed(task_id):
			if not wait:
				return
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
	var d := capture()
	if wait:
		write_file(d)
	else:
		task_id = WorkerThreadPool.add_task(write_file.bind(d))
	if announce:
		m.show_message("Game saved.")

func write_file(d: Dictionary) -> void:
	var raw := var_to_bytes(d)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write the save file.")
		return
	f.store_64(raw.size())
	f.store_buffer(packed)
	f.close()
	var tmp := ProjectSettings.globalize_path(TMP)
	var dst := ProjectSettings.globalize_path(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(dst)
	DirAccess.rename_absolute(tmp, dst)

func new_world() -> void:
	disabled = true
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	get_tree().reload_current_scene()
