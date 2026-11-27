class_name Targeting
extends RefCounted

# Lock-on for fights. Toggle it and the ant keeps the chosen enemy in sight (the camera tracks it)
# until you toggle off. A and D then strafe around it instead of turning. When the target dies the
# lock moves to the nearest other enemy, and ends when none are left.
#   ` or middle mouse : lock on to the enemy nearest your crosshair / lock off
#   I                 : switch to the next enemy while locked

const RANGE := 45.0       # how far away an enemy can be picked
const BREAK_RANGE := 75.0  # the lock drops if the target gets this far away

var m: Main
var target: Creature
var marker: MeshInstance3D
var bar_timer := 0.0

func setup(main: Main) -> void:
	m = main

func is_locked() -> bool:
	return target != null

func name_of(c: Creature) -> String:
	if c.is_boss:
		return c.boss_name
	var script: Script = c.get_script()
	var n := String(script.get_global_name()) if script != null else "enemy"
	return n.capitalize()

# Anything that can hurt you. Fireflies and passive fish are left alone.
func is_hostile(c: Creature) -> bool:
	if c is Firefly:
		return false
	if c is Fish and not (c as Fish).aggressive:
		return false
	return true

func is_alive(c: Creature) -> bool:
	return is_instance_valid(c) and not c.is_queued_for_deletion() and c.health > 0.0 and c.active and c.visible

# Living enemies within range, nearest first.
func candidates() -> Array:
	var out: Array = []
	var here := m.ant.global_position
	for node in Registry.of("creatures"):
		var c := node as Creature
		if c == null or c == target or not is_alive(c) or not is_hostile(c):
			continue
		if c.global_position.distance_to(here) <= RANGE:
			out.append(c)
	out.sort_custom(func(a: Creature, b: Creature) -> bool:
		return a.global_position.distance_to(here) < b.global_position.distance_to(here))
	return out

func toggle() -> void:
	if target != null:
		release()
		m.show_message("Lock-on off.")
		return
	var pick := best_in_front()
	if pick == null:
		m.show_message("No enemy in range to lock on to.")
		return
	lock(pick)

# The enemy closest to where you are looking, falling back to the nearest one.
func best_in_front() -> Creature:
	var list := candidates()
	if list.is_empty():
		return null
	var cam := m.ant.camera
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var best: Creature = null
	var best_score := -INF
	for c in list:
		var off: Vector3 = (c as Creature).hit_center() - from
		var d := off.length()
		var score := off.normalized().dot(fwd) - d / RANGE * 0.4
		if score > best_score:
			best_score = score
			best = c
	return best

func cycle() -> void:
	if target == null:
		return
	var list := candidates()   # nearest first, never includes the current target
	if list.is_empty():
		m.show_message("No other enemy in range.")
		return
	lock(list[0])

func lock(c: Creature) -> void:
	clear_marker()
	target = c
	make_marker()
	bar_timer = 0.0
	m.show_message("Locked on: %s   (` to release, I for next)" % name_of(c))

func release() -> void:
	clear_marker()
	target = null
	m.ant.lock_target = null

func make_marker() -> void:
	marker = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.32
	cone.bottom_radius = 0.0
	cone.height = 0.6
	cone.radial_segments = 4
	cone.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.18, 0.12)
	mat.no_depth_test = true
	mat.render_priority = 10
	cone.material = mat
	marker.mesh = cone
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(marker)
	marker.position = Vector3(0, (target.bar_height + 0.8) , 0)

func clear_marker() -> void:
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
	marker = null

func process(delta: float) -> void:
	if target == null:
		return
	if not is_alive(target) or target.global_position.distance_to(m.ant.global_position) > BREAK_RANGE:
		var dead := not is_alive(target)
		clear_marker()
		target = null
		if dead:
			var list := candidates()
			if not list.is_empty():
				lock(list[0])   # on to the next enemy
				m.ant.lock_target = target
				return
			m.show_message("Target down. Lock-on off.")
		else:
			m.show_message("Target lost.")
		m.ant.lock_target = null
		return
	m.ant.lock_target = target
	if marker != null and is_instance_valid(marker):
		marker.position.y = target.bar_height + 0.8 + sin(Time.get_ticks_msec() / 220.0) * 0.12
		marker.rotation.y += delta * 2.5
	bar_timer -= delta
	if bar_timer <= 0.0:
		bar_timer = 2.0
		target.show_bar()   # keeps its health bar on while locked
