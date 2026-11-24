class_name Crawler
extends Creature

# The shared body of every ground creature that walks the terrain (beetle, centipede...).
# It finds the ground with rays, tilts with it, goes around steep obstacles, gets stuck in
# silk traps, waits while the ground is not built yet, and flips over when it dies.
# Each animal extends this and fills in build_model(), think() and animate().

const STUCK_SPEED := 0.1       # speed multiplier while stuck in a web
const STUCK_SECONDS := 4.0
const WEB_COOLDOWN := 2.5      # after breaking free, it ignores webs for a moment
const WANDER_RADIUS := 12.0

var queen_getter: Callable     # returns the colony's queen (Placeable) or null. Set by main.
var wander_speed := 2.0
var wander_radius := WANDER_RADIUS   # how far from home it wanders
var wander_min := 3.0                # and how close to home it will not bother with
var target := Vector3.ZERO
var wait := 0.0
var stuck_time := 0.0
var web_immunity := 0.0
var time := 0.0
var walk_phase := 0.0
var moving := false
var dead := false
var death_time := 0.0
var body_root: Node3D
var ghost := false          # boss burrowing: ignores the ground and rock while it tunnels

func _ready() -> void:
	super()
	build_model()
	forward = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	pick_target()

# ---- Fill these in ----

func build_model() -> void:
	pass

# One step of the animal's decisions. to_ant is the vector to the player, dist its length.
func think(_delta: float, _to_ant: Vector3, _dist: float) -> void:
	pass

func animate(_delta: float) -> void:
	pass

# ---- Shared behavior ----

# Dies by flipping onto its back, lying there a moment, then shrinking away.
# The loot drops the moment it dies.
func die() -> void:
	if dead:
		return
	dead = true
	climbing = false   # a creature that dies up a tree falls out of it
	Registry.remove(self, "creatures")   # can't be hit or counted any more
	died.emit(self)

func _physics_process(delta: float) -> void:
	if dead:
		death_time += delta
		stick_to_ground(delta)
		var t := minf(1.0, death_time / 0.4)
		var angle := t * PI
		body_root.rotation.z = angle
		body_root.position = Vector3(sin(angle), 1.0 - cos(angle), 0.0) * size
		if death_time > 2.0:
			body_root.scale = Vector3.ONE * size * maxf(0.0, 1.0 - (death_time - 2.0) * 2.0)
		if death_time > 2.5:
			queue_free()
		return
	if is_loaded.is_valid() and not is_loaded.call(global_position):
		return   # the ground here is not built yet, so wait
	if not active:
		return   # hiding
	time += delta
	stuck_time -= delta
	web_immunity -= delta
	check_webs()
	moving = false

	var to_ant := ant.global_position - global_position
	if not fire_react(delta):   # near a fire it runs instead of thinking
		think(delta, to_ant, to_ant.length())

	ease_stop(delta)
	push_apart(delta)
	keep_clear_of_obstacles(delta)
	stick_to_ground(delta)
	apply_pain()
	if uses_trail:
		update_trail()
	animate(delta)

# Walk into a silk trap and you get stuck for a few seconds.
func check_webs() -> void:
	if stuck_time > 0.0 or web_immunity > 0.0:
		return
	for t in Registry.of("traps"):
		var web := t as Placeable
		var off := web.global_position - global_position
		if Vector2(off.x, off.z).length() < Placeable.TRAP_RADIUS and absf(off.y) < 2.0:
			if web.try_catch():
				stuck_time = STUCK_SECONDS
				web_immunity = STUCK_SECONDS + WEB_COOLDOWN
				return

func get_queen() -> Placeable:
	if not queen_getter.is_valid():
		return null
	var q = queen_getter.call()
	if is_instance_valid(q):
		return q
	return null

func wander(delta: float) -> void:
	if wait > 0.0:
		wait -= delta
		return
	if global_position.distance_to(target) < 1.5:
		wait = randf_range(1.0, 3.0)
		pick_target()
		return
	walk_toward(target, wander_speed, delta)

func pick_target() -> void:
	var a := randf() * TAU
	var r := randf_range(wander_min, wander_radius)
	target = home + Vector3(cos(a) * r, 0, sin(a) * r)

func face(dir: Vector3) -> void:
	var flat := dir - up * dir.dot(up)
	if flat.length() > 0.01:
		forward = flat.normalized()

# Walk toward a point along the ground, going around steep obstacles.
func walk_toward(goal: Vector3, speed: float, delta: float) -> void:
	var point := plan_climb(goal)   # may turn trunks into walkable ground, or send it back down
	var dir := point - global_position
	var flat := dir - up * dir.dot(up)
	if flat.length() < 0.05:
		return
	flat = spread(flat.normalized(), dir.length(), speed, delta)
	var step := speed * path_speed * delta * (STUCK_SPEED if stuck_time > 0.0 else 1.0)
	var chosen := Vector3.ZERO
	for turn in [0.0, 0.9, -0.9, 1.6, -1.6]:
		var d := flat.rotated(up, turn)
		if not blocked(d, step + 1.0):
			chosen = d
			break
	if chosen == Vector3.ZERO:
		for turn in [0.0, 0.9, -0.9]:
			var d2 := flat.rotated(up, turn)
			if not blocked(d2, step + 0.5, true):
				chosen = d2
				break
	if chosen == Vector3.ZERO:
		return
	forward = forward.lerp(chosen, minf(1.0, 10.0 * delta)).normalized()
	# Speeds up and turns gradually. Fast charges ramp up quickly so they still feel like charges.
	var top := speed * path_speed * (STUCK_SPEED if stuck_time > 0.0 else 1.0)
	cur_speed = move_toward(cur_speed, top, top * (8.0 if top > 9.5 else 3.0) * delta)
	var go := forward
	if blocked(go, cur_speed * delta + 0.5, true):
		go = chosen
	global_position += go * cur_speed * delta
	last_dir = go
	moving = true

func space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state

func cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	if ant != null:
		q.exclude = [ant.get_rid()]
	return space().intersect_ray(q)

# True if something steep or tall is in the way in this direction.
# Is there a wall, tree or rock ahead? Three rays (middle, left, right) are cast as wide as the
# body, so a big creature does not squeeze its sides through a gap or clip a trunk beside it.
# A narrow check (middle ray only) is the fallback when the wide check finds no way through.
func blocked(dir: Vector3, length: float, narrow: bool = false) -> bool:
	var r := (reach_radius if reach_radius > 0.0 else body_radius) * size
	var from := global_position + up * (0.8 * maxf(size, 1.0))
	var offsets := [0.0] if narrow else [0.0, -r * 0.5, r * 0.5, -r * 0.95, r * 0.95]
	var side := dir.cross(up).normalized()
	for o in offsets:
		var start: Vector3 = from + side * float(o)
		var hit := cast(start, start + dir * (length + (0.0 if narrow else r)))
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.dot(up) < 0.55:   # a gentle slope is walkable, a wall is not
			if climb_ok and (climbing or is_tree(hit)):
				continue   # a trunk it is climbing, or about to
			return true
	return false

func can_see_ant() -> bool:
	var from := global_position + up * 1.2
	var hit := cast(from, ant.global_position + Vector3(0, 0.5, 0))
	return hit.is_empty()

# Rest on the ground below, tilt with it, and fall if there isn't any.
# A ray that hits a surface from behind means we have ended up inside the ground,
# so in that case we climb back out instead of sinking further.
func stick_to_ground(delta: float) -> void:
	if ghost:
		return   # swimming through the rock: it does not follow the ground
	if not dead:
		try_mount()
		if climbing:
			climb_stick(delta)
			if climbing:
				return
	var found := false
	var inside := false
	for lift in [1.2, 0.5]:
		var from: Vector3 = global_position + Vector3.UP * float(lift)
		var hit := cast(from, global_position + Vector3.DOWN * 3.0)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.y <= 0.05:
			inside = true   # a back face or a ceiling: we are inside rock
			continue
		found = true
		fall_speed = 0.0
		up = up.slerp(n, minf(1.0, 8.0 * delta)).normalized()
		global_position = global_position.lerp(hit["position"], minf(1.0, 18.0 * delta))
		break
	if not found:
		if inside:
			global_position.y += 4.0 * delta   # climb out of the ground
		else:
			fall_speed += 20.0 * delta
			global_position.y -= fall_speed * delta
			if global_position.y < -20.0:
				global_position = home + Vector3(0, 5, 0)
				fall_speed = 0.0
	if not up.is_finite() or up.y < 0.2:
		up = Vector3.UP
	var f := forward - up * forward.dot(up)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	global_transform.basis = Basis.looking_at(f.normalized(), up)

# ---- Model helpers ----

func add_blob(mat: StandardMaterial3D, size: Vector3, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	(parent if parent != null else body_root).add_child(mi)
	return mi

# A thin cylinder stretched between two points.
func make_segment(a: Vector3, b: Vector3, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return mi

func make_mat(color: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

func glow_mat(color: Color) -> StandardMaterial3D:
	var m := make_mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.5
	return m
