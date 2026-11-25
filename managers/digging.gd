class_name Digging
extends RefCounted

# Digging, filling and smoothing the ground: holding the mouse to dig a continuous tunnel, the dig
# size (mouse wheel or [ ]), the preview sphere that shows where you will dig, filling with soil
# (hold X), the rules that keep some ground undiggable (the royal cell, under pools and trees), and
# clearing grass and pebbles where the ground changes. main.gd calls handle_dig() and
# update_brush_preview() every frame.

var m: Main

var brush := Main.DIG_RADIUS         # current dig radius. Smoothing and filling scale with it.
var brush_preview: MeshInstance3D
var brush_show := 0.0          # seconds the dig size display stays on screen after you change it
const BRUSH_SHOW_TIME := 2.5
var dig_cooldown := 0.0
var dig_lock := false   # after placing or menu use, ignore the held button until it is released
var dig_hold := -1.0   # -1 while no button is held
var has_last_dig := false
var last_dig_point := Vector3.ZERO

func setup(main: Main) -> void:
	m = main

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
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not m.building.build_mode and m.crafting.held_type() == ""
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
	if not first and (dig_hold < Main.HOLD_DELAY or dig_cooldown > 0.0):
		return

	var cam := m.ant.camera
	var hit = m.world.raycast(cam.global_position, -cam.global_transform.basis.z, Main.REACH)
	if hit == null:
		return
	var point: Vector3 = hit

	# The ground under and around water is too hard to dig.
	var reach := brush if digging else brush * (Main.SMOOTH_RADIUS / Main.DIG_RADIUS)
	var blocked := is_protected(point, reach)
	if digging and has_last_dig and not blocked:
		blocked = is_protected(last_dig_point.lerp(point, 0.5), reach)
	if blocked:
		if first:
			m.show_message("The ground here is too hard to dig.")
		return

	if digging and Input.is_key_pressed(KEY_X):
		has_last_dig = false
		fill_ground(point, -cam.global_transform.basis.z)
		return

	var dirty: Array[Vector3i]
	var clear_radius := brush * (Main.SMOOTH_RADIUS / Main.DIG_RADIUS) + 1.0
	if digging:
		if has_last_dig and last_dig_point.distance_to(point) < 0.5:
			return   # barely moved, skip
		var from := point
		if has_last_dig and last_dig_point.distance_to(point) < 6.0:
			from = last_dig_point   # connect to the previous point
		dirty = m.world.dig_capsule(from, point, brush)
		var gained := m.world.last_removed * Main.SOIL_PER_VOLUME
		if gained > 0.0:
			if m.ant.soil + gained > m.ant.soil_cap():
				m.show_message("Soil full. Extra is lost.")
			m.ant.soil = minf(m.ant.soil_cap(), m.ant.soil + gained)
		last_dig_point = point
		has_last_dig = true
		clear_radius = brush + 2.0
	else:
		dirty = m.world.smooth_sphere(point, brush * (Main.SMOOTH_RADIUS / Main.DIG_RADIUS))

	dig_cooldown = Main.DIG_INTERVAL
	m.stream.mark_edited(dirty)
	m.stream.queue_remesh(dirty, point)
	clear_decor_near(point, clear_radius)
	m.content.wake_pickups(point, clear_radius)
	m.water.mark_water_dirty(point, clear_radius)
	if digging:
		m.pop.maybe_worm(point)   # deep underground, the rock may burst open

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
		m.add_child(brush_preview)
	brush_show -= m.get_process_delta_time()
	var on := brush_show > 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not m.building.build_mode and m.crafting.held_type() == "" \
			and not m.ant.controls_locked and not m.ant.swimming
	if not on:
		brush_preview.visible = false
		return
	var cam := m.ant.camera
	var hit = m.world.raycast(cam.global_position, -cam.global_transform.basis.z, Main.REACH)
	if hit == null:
		brush_preview.visible = false
		return
	var point: Vector3 = hit
	var smoothing := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var filling := Input.is_key_pressed(KEY_X)
	var r := brush
	var mat2 := (brush_preview.mesh as SphereMesh).material as StandardMaterial3D
	if smoothing:
		r = brush * (Main.SMOOTH_RADIUS / Main.DIG_RADIUS)
		mat2.albedo_color = Color(0.6, 0.8, 1.0, 0.18)
	elif filling:
		r = FILL_RADIUS * brush / Main.DIG_RADIUS
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
	brush = clampf(snappedf(brush + amount, 0.1), Main.BRUSH_MIN, m.ant.stat("dig_max"))
	brush_show = BRUSH_SHOW_TIME

# Hold X and click to spend carried soil and build ground back up where you aim.
const FILL_RADIUS := 1.8
const WATER_PER_FILL := 0.25   # water spent per unit of ground added. Dry soil will not pack, so it needs mixing into mud.

func fill_ground(point: Vector3, aim: Vector3) -> void:
	if m.ant.soil < 1.0:
		m.show_message("No soil. Dig some first, then hold X and click to fill.")
		dig_cooldown = 0.6
		return
	if m.ant.water < 1.0:
		m.show_message("No water. Soil needs water to pack into mud. Drink at a pool (hold F) first.")
		dig_cooldown = 0.6
		return
	# Center the blob a little in front of the surface so it grows outward from it.
	var fr := FILL_RADIUS * brush / Main.DIG_RADIUS
	var center := point - aim.normalized() * fr * 0.7
	if m.ant.global_position.distance_to(center) < fr + 0.9 \
			or (m.ant.global_position + m.ant.basis.y * 0.4).distance_to(center) < fr + 0.9:
		m.show_message("You are in the way. Step back to fill here.")
		dig_cooldown = 0.6
		return
	var dirty := m.world.fill_sphere(center, fr)
	if dirty.is_empty():
		return
	m.ant.soil = maxf(0.0, m.ant.soil - m.world.last_added * Main.SOIL_PER_VOLUME)
	m.ant.water = maxf(0.0, m.ant.water - m.world.last_added * WATER_PER_FILL)
	dig_cooldown = Main.DIG_INTERVAL
	m.stream.mark_edited(dirty)
	m.stream.queue_remesh(dirty, center)
	m.content.wake_pickups(center, fr + 1.0)
	m.water.mark_water_dirty(center, fr + 1.0)

# Only a thin slab of ground is locked, so water and trees always have something under them.
# Pools and pockets lock the layer under their water, and trees and boulders lock the ground
# just under their base. Everything deeper, and everything beside them, is diggable.
const POOL_LOCK_DEPTH := 3.0       # how far below a pool or pocket floor stays solid
const OBSTACLE_LOCK_DEPTH := 5.0   # how far below a tree or boulder base stays solid

# True if a dig of this radius at this point would cut into one of those locked slabs.
func is_protected(point: Vector3, radius: float) -> bool:
	var top := point.y + radius      # the highest and lowest points the dig reaches
	var bottom := point.y - radius

	for p in m.terrain.pools_at(point.x, point.z):
		var reach := float(p["radius"]) * (1.12 if p.get("lake", false) else 1.4) + radius
		if m.terrain.pool_dist(p, point.x, point.z) < reach \
				and top > float(p["floor"]) - POOL_LOCK_DEPTH and bottom < float(p["level0"]) + 0.5:
			return true

	if m.terrain.edge_dist(point.x, point.z) < Main.RIVER_WIDTH + radius and top > Main.RIVER_BED_Y - POOL_LOCK_DEPTH and bottom < Main.RIVER_LEVEL + 0.5:
		return true   # the riverbed stays, so the river keeps its water

	# The royal cell has thick walls while its colony lives: the only way in is the guarded antechamber.
	var mm := m.terrain.mound_near(point.x, point.z)
	if not mm.is_empty() and not bool(mm["dead"]):
		var rc: Vector3 = mm["royal"]
		var rr: Vector3 = mm["royal_r"]
		var rq := Vector3((point.x - rc.x) / rr.x, (point.y - rc.y) / rr.y, (point.z - rc.z) / rr.z)
		if (rq.length() - 1.0) * 6.6 < Main.ROYAL_WALL + radius:
			return true

	for p in m.terrain.pockets_at_cell(Vector2i(floori(point.x / Main.POCKET_CELL), floori(point.z / Main.POCKET_CELL))):
		var pos: Vector3 = p["pos"]
		var r: Vector3 = p["radii"]
		var q := Vector2((point.x - pos.x) / (r.x * 1.3 + radius), (point.z - pos.z) / (r.z * 1.3 + radius))
		if q.length() < 1.0 and top > float(p["floor"]) - POOL_LOCK_DEPTH and bottom < float(p["level"]):
			return true

	for o in m.content.obstacles_near(point.x, point.z):
		var op: Vector3 = o["pos"]
		if Vector2(point.x - op.x, point.z - op.z).length() < float(o["radius"]) + radius * 0.5 \
				and top > op.y - OBSTACLE_LOCK_DEPTH and bottom < op.y + 2.0:
			return true
	return false

# Hide grass and pebbles whose ground has been dug away. Returns how many were hidden.
# With burn = true it is a fire: only plants go (grass, flowers, ferns), never pebbles.
func clear_decor_near(point: Vector3, radius: float, burn: bool = false) -> int:
	var count := 0
	for decor in m.stream.decor_sets:
		var rect: Rect2 = decor["rect"]
		if not rect.grow(radius + 1.0).has_point(Vector2(point.x, point.z)):
			continue   # nothing of this square is near the dig
		if burn and decor.has("bodies"):
			continue   # pebbles do not burn
		var mm: MultiMesh = decor["mm"]
		var pos: Array = decor["pos"]
		var hidden: Array = decor["hidden"]
		for i in pos.size():
			if hidden[i] == 1:
				continue
			var p: Vector3 = pos[i]
			if Vector2(p.x - point.x, p.z - point.z).length() > radius:
				continue
			if m.world.sample_density(p - Vector3(0, 0.3, 0)) < 0.0:
				hidden[i] = 1
				count += 1
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))
				if decor.has("bodies") and decor["bodies"][i] != null:
					decor["bodies"][i].queue_free()   # the pebble is gone, so its solid body goes too
	return count

# How many plants stand within radius of a point and could burn (counts only, changes nothing).
func fuel_near(point: Vector3, radius: float) -> int:
	var count := 0
	for decor in m.stream.decor_sets:
		var rect: Rect2 = decor["rect"]
		if not rect.grow(radius + 1.0).has_point(Vector2(point.x, point.z)) or decor.has("bodies"):
			continue
		var pos: Array = decor["pos"]
		var hidden: Array = decor["hidden"]
		for i in pos.size():
			if hidden[i] == 1:
				continue
			var p: Vector3 = pos[i]
			if Vector2(p.x - point.x, p.z - point.z).length() <= radius:
				count += 1
	return count
