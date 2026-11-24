class_name Building
extends RefCounted

# Everything about putting things in the world: the build ghost (the see-through preview of what you
# are about to place), placing and removing wall pieces, placing boxes, barrels, lamps, traps and the
# queen, what happens when a trap goes off or the queen is hurt or killed, and the colony's storage
# (what is in all your boxes and barrels). main.gd just calls update_ghost() every physics frame.

var m: Main

var build_mode := false
var selected := 0
var yaw := 0.0
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var ghost_xform := Transform3D.IDENTITY
var ghost_valid := false
var target_piece: Piece = null
var target_placeable: Placeable = null

func setup(main: Main) -> void:
	m = main

# Aims the ghost where the crosshair points and works out whether a piece fits there.
func update_ghost() -> void:
	target_piece = null
	target_placeable = null
	ghost_valid = false
	var held := m.crafting.held_type()
	if not build_mode and held == "":
		ghost.visible = false
		return

	# Ray from the camera through the crosshair.
	var cam := m.ant.camera
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * Main.REACH)
	q.exclude = [m.ant.get_rid()]
	q.collision_mask = 1
	var space := m.get_world_3d().direct_space_state
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		ghost.visible = false
		return

	if hit["collider"] is Piece:
		target_piece = hit["collider"]
	elif hit["collider"] is Placeable:
		target_placeable = hit["collider"]

	# Place the piece so it rests against the surface we hit.
	var type := ""
	var size: Vector3
	var affordable := true
	if build_mode:
		type = Main.PIECE_ORDER[selected]
		size = Piece.TYPES[type]["size"]
		affordable = can_afford(type)
	else:
		size = Crafting.RECIPES[held]["size"]
	var h := size * 0.5
	var b := Basis(Vector3.UP, yaw)
	var n: Vector3 = hit["normal"]
	# How far the box reaches along the surface normal.
	var extent := absf(n.dot(b.x)) * h.x + absf(n.dot(b.y)) * h.y + absf(n.dot(b.z)) * h.z
	var pos: Vector3 = hit["position"] + n * (extent - 0.05)
	ghost_xform = Transform3D(b, pos)

	# Valid if affordable, not on top of the ant, and not inside another piece.
	var valid := affordable
	if valid and m.ant.global_position.distance_to(pos) < h.length() + 0.6:
		valid = false
	if valid:
		var box := BoxShape3D.new()
		box.size = size - Vector3.ONE * 0.2
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = box
		sq.transform = ghost_xform
		sq.collision_mask = 4
		if not space.intersect_shape(sq, 1).is_empty():
			valid = false
	ghost_valid = valid

	(ghost.mesh as BoxMesh).size = size
	ghost.visible = true
	ghost.global_transform = ghost_xform
	ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if valid else Color(1.0, 0.3, 0.3, 0.45)

# ---------- Placing things ----------

func can_afford(type: String) -> bool:
	var cost: Dictionary = Piece.TYPES[type]["cost"]
	for k in cost:
		if stored(k) < cost[k]:
			return false
	return true

func cost_text(type: String) -> String:
	var parts: Array[String] = []
	var cost: Dictionary = Piece.TYPES[type]["cost"]
	for k in cost:
		parts.append("%d %s" % [cost[k], str(Pickup.KINDS[k]["label"]).to_lower()])
	return ", ".join(parts)

func place_piece() -> void:
	if not ghost.visible:
		return
	var type: String = Main.PIECE_ORDER[selected]
	if not can_afford(type):
		m.show_message("Not enough in your boxes.")
		return
	if not ghost_valid:
		m.show_message("Can't place that here.")
		return
	var cost: Dictionary = Piece.TYPES[type]["cost"]
	for k in cost:
		spend_stored(k, cost[k])
	spawn_piece(type, ghost_xform)

func remove_piece() -> void:
	if target_piece == null:
		return
	# Full refund.
	var cost: Dictionary = Piece.TYPES[target_piece.type]["cost"]
	for k in cost:
		add_stored(k, cost[k])
	target_piece.queue_free()
	target_piece = null

func place_item() -> void:
	var held := m.crafting.held_type()
	if held == "" or not ghost.visible:
		return
	if not ghost_valid:
		m.show_message("Can't place that here.")
		return
	if held == "queen" and is_instance_valid(m.queen):
		m.show_message("Your colony already has a queen. Pick her up to move her.")
		return
	spawn_placeable(held, ghost_xform)
	if held == "queen":
		m.show_message("The queen is placed. You will respawn here.")
	m.crafting.consume_held()

# Makes one placed item (box, barrel, lamp, queen, trap) and wires it up. Used when you place one and when a save loads.
func spawn_placeable(type: String, xform: Transform3D) -> Placeable:
	var p := Placeable.new()
	p.type = type
	p.world = m.world
	p.moved.connect(_on_placeable_moved)
	if Placeable.DEFENSE.has(type):
		p.collapsed.connect(_on_trap_collapsed)
	Registry.add(p, "placeables")
	m.add_child(p)
	p.global_transform = xform
	if type == "queen":
		m.queen = p
		p.destroyed.connect(_on_queen_destroyed)
		p.attacked.connect(_on_queen_attacked)
		m.ant.spawn_point = p.global_position + Vector3(0, 2.5, 0)
	return p

func spawn_piece(type: String, xform: Transform3D) -> Piece:
	var p := Piece.new()
	p.type = type
	Registry.add(p, "pieces")
	m.add_child(p)
	p.global_transform = xform
	return p

var queen_alarm_cd := 0.0

# A collapse trap went off: soil drops and fills the spot, sealing the tunnel.
func _on_trap_collapsed(center: Vector3, radius: float) -> void:
	if m.ant.global_position.distance_to(center) < radius + 1.6:
		m.show_message("A collapse trap went off beside you, but you were too close for it to bury the tunnel.")
		return
	var dirty := m.world.fill_sphere(center, radius)
	if dirty.is_empty():
		return
	m.stream.mark_edited(dirty)
	m.stream.queue_remesh(dirty, center)
	m.content.wake_pickups(center, radius + 1.0)
	m.water.mark_water_dirty(center, radius + 1.0)
	m.show_message("A collapse trap sealed the tunnel!")

# A placed item fell after the ground under it was dug away. If it is the queen, respawn moves with her.
func _on_placeable_moved(p: Placeable) -> void:
	if p == m.queen:
		m.ant.spawn_point = p.global_position + Vector3(0, 2.5, 0)

func _on_queen_attacked() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= queen_alarm_cd:
		queen_alarm_cd = now + 8.0
		m.show_message("The queen is under attack!")

# Press T to eat sugar, Q next to the queen to feed her sugar.
func feed_queen() -> void:
	if not is_instance_valid(m.queen):
		m.show_message("You have no queen to feed.")
	elif m.ant.global_position.distance_to(m.queen.global_position) > 6.0:
		m.show_message("Get closer to the queen to feed her.")
	elif m.queen.health >= Placeable.QUEEN_MAX_HEALTH:
		m.show_message("The queen is at full health.")
	elif int(m.ant.inventory["sugar"]) <= 0:
		m.show_message("You need sugar on you to feed her.")
	else:
		m.ant.inventory["sugar"] = int(m.ant.inventory["sugar"]) - 1
		m.queen.feed(Placeable.SUGAR_HEAL)

# Spiders killed the queen. She is gone and you must craft a new one.
func _on_queen_destroyed(p: Placeable) -> void:
	if p == m.queen:
		m.queen = null
		m.ant.spawn_point = Vector3(0, 70, 0)
	m.show_message("YOUR QUEEN WAS KILLED! Craft a new queen to restore your colony.")
	p.queue_free()

func pick_up_item() -> void:
	if target_placeable == null:
		return
	if target_placeable.total_stock() > 0.0:
		m.show_message("Empty it first. It still holds something.")
		return
	if target_placeable == m.queen:
		m.queen = null
		m.ant.spawn_point = Vector3(0, 70, 0)
	m.crafting.add_item(target_placeable.type)
	target_placeable.queue_free()
	target_placeable = null

func setup_ghost() -> void:
	ghost = MeshInstance3D.new()
	ghost.mesh = BoxMesh.new()
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45)
	ghost.material_override = ghost_mat
	ghost.visible = false
	ghost.top_level = true
	m.add_child(ghost)

# ---------- Colony storage ----------
# What the colony owns is whatever sits in its boxes and barrels.

# What the colony owns is whatever sits in its boxes and barrels.

func containers() -> Array:
	return Registry.of("containers")

func stored(kind: String) -> int:
	var total := 0.0
	for c in containers():
		total += float((c as Placeable).stock.get(kind, 0.0))
	return int(total)

func spend_stored(kind: String, amount: int) -> void:
	var left := float(amount)
	for c in containers():
		var p := c as Placeable
		var have := float(p.stock.get(kind, 0.0))
		var take := minf(have, left)
		if take > 0.0:
			p.stock[kind] = have - take
			left -= take
		if left <= 0.0:
			return

# Refunds go into any box with room. Anything that doesn't fit is lost.
func add_stored(kind: String, amount: int) -> void:
	var left := float(amount)
	for c in containers():
		var p := c as Placeable
		var room := p.cap(kind) - float(p.stock.get(kind, 0.0))
		var put := minf(room, left)
		if put > 0.0:
			p.stock[kind] = float(p.stock.get(kind, 0.0)) + put
			left -= put
		if left <= 0.0:
			return
