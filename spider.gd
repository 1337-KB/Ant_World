class_name Spider
extends Creature

# A night hunter. It wanders until it sees an ant, chases it down, and bites.
# It walks on whatever ground is under it (hills, rocks, tunnel floors), found with rays.
# It runs a little slower than a sprinting ant, so sprinting is how you escape.

enum State { WANDER, CHASE, ATTACK, FLEE }

const WANDER_SPEED := 2.0
const CHASE_SPEED := 5.5
const FLEE_SPEED := 6.5
const SIGHT_RANGE := 16.0     # notices an ant this close, if nothing is in the way
const LOSE_RANGE := 26.0      # gives up the chase beyond this
const BITE_RANGE := 2.4
const BITE_DAMAGE := 10.0
const BITE_INTERVAL := 1.0
const WANDER_RADIUS := 12.0
const FLEE_BELOW := 0.3       # runs away when health falls below this fraction

var state := State.WANDER
var target := Vector3.ZERO
var wait := 0.0
var bite_cd := 0.0
var flee_time := 0.0
var time := 0.0
var walk_phase := 0.0
var moving := false
var up := Vector3.UP
var forward := Vector3.FORWARD
var fall_speed := 0.0
var dead := false
var death_time := 0.0
var legs: Array = []          # each: {"node": Node3D, "side": float, "base": float, "phase": float}
var body_root: Node3D

func _ready() -> void:
	max_health = 80.0
	super()
	nocturnal = true
	build_model()
	forward = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	pick_target()

func loot_kind() -> String:
	return "silk"

# Dies by flipping onto its back, lying there a moment, then shrinking away.
# The loot drops the moment it dies.
func die() -> void:
	if dead:
		return
	dead = true
	remove_from_group("creatures")   # can't be hit or counted any more
	died.emit(self)

func on_hurt() -> void:
	if health < max_health * FLEE_BELOW and state != State.FLEE:
		state = State.FLEE
		flee_time = 4.0

# ---------- Model ----------

func build_model() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.17, 0.11, 0.08)
	dark.roughness = 0.6
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.2, 0.15)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.1, 0.05)
	eye_mat.emission_energy_multiplier = 2.5

	body_root = Node3D.new()
	add_child(body_root)
	add_blob(dark, Vector3(1.0, 0.75, 1.15), Vector3(0, 1.0, -0.55))   # front body
	add_blob(dark, Vector3(1.45, 1.15, 1.8), Vector3(0, 1.1, 0.8))     # abdomen
	for e in [Vector3(-0.22, 1.2, -1.05), Vector3(0.22, 1.2, -1.05), Vector3(-0.12, 1.32, -1.1), Vector3(0.12, 1.32, -1.1)]:
		add_blob(eye_mat, Vector3(0.14, 0.14, 0.14), e)

	# Eight legs: four on each side, fanned from front to back.
	var fan := [0.7, 0.25, -0.25, -0.7]
	for i in 4:
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.4, 1.0, -0.55 + i * 0.35)
			var knee := Vector3(side * 1.3, 0.75, 0.0)
			var foot := Vector3(side * 2.3, -0.98, 0.0)
			pivot.add_child(make_segment(Vector3.ZERO, knee, 0.09, dark))
			pivot.add_child(make_segment(knee, foot, 0.07, dark))
			body_root.add_child(pivot)
			var base: float = fan[i] if side > 0.0 else -float(fan[i])
			pivot.rotation.y = base
			legs.append({"node": pivot, "side": side, "base": base, "phase": float(i) * PI * 0.5 + (0.0 if side > 0.0 else PI)})

func add_blob(mat: StandardMaterial3D, size: Vector3, pos: Vector3) -> void:
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
	body_root.add_child(mi)

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

# ---------- Behavior ----------

func _physics_process(delta: float) -> void:
	if dead:
		death_time += delta
		stick_to_ground(delta)
		var t := minf(1.0, death_time / 0.4)
		var angle := t * PI
		body_root.rotation.z = angle
		# Turn about the middle of the body so it ends up on its back above the ground.
		body_root.position = Vector3(sin(angle), 1.0 - cos(angle), 0.0)
		if death_time > 2.0:
			body_root.scale = Vector3.ONE * maxf(0.0, 1.0 - (death_time - 2.0) * 2.0)
		if death_time > 2.5:
			queue_free()
		return
	if not active:
		return   # hiding for the day
	time += delta
	bite_cd -= delta
	moving = false

	var to_ant := ant.global_position - global_position
	var dist := to_ant.length()

	match state:
		State.WANDER:
			if dist < SIGHT_RANGE and can_see_ant():
				state = State.CHASE
			else:
				wander(delta)
		State.CHASE:
			if dist > LOSE_RANGE:
				state = State.WANDER
				pick_target()
			elif dist < BITE_RANGE:
				state = State.ATTACK
			else:
				walk_toward(ant.global_position, CHASE_SPEED, delta)
		State.ATTACK:
			face(to_ant)
			if dist > BITE_RANGE * 1.5:
				state = State.CHASE
			elif bite_cd <= 0.0:
				bite_cd = BITE_INTERVAL
				ant.take_damage(BITE_DAMAGE)
		State.FLEE:
			flee_time -= delta
			walk_toward(global_position - to_ant, FLEE_SPEED, delta)
			if flee_time <= 0.0:
				state = State.WANDER
				pick_target()

	stick_to_ground(delta)
	animate(delta)

func wander(delta: float) -> void:
	if wait > 0.0:
		wait -= delta
		return
	if global_position.distance_to(target) < 1.5:
		wait = randf_range(1.0, 3.0)
		pick_target()
		return
	walk_toward(target, WANDER_SPEED, delta)

func pick_target() -> void:
	var a := randf() * TAU
	var r := randf_range(3.0, WANDER_RADIUS)
	target = home + Vector3(cos(a) * r, 0, sin(a) * r)

func face(dir: Vector3) -> void:
	var flat := dir - up * dir.dot(up)
	if flat.length() > 0.01:
		forward = flat.normalized()

# Walk toward a point along the ground, going around steep obstacles.
func walk_toward(point: Vector3, speed: float, delta: float) -> void:
	var dir := point - global_position
	var flat := dir - up * dir.dot(up)
	if flat.length() < 0.05:
		return
	flat = flat.normalized()
	var step := speed * delta
	var chosen := Vector3.ZERO
	for turn in [0.0, 0.9, -0.9, 1.6, -1.6]:
		var d := flat.rotated(up, turn)
		if not blocked(d, step + 1.0):
			chosen = d
			break
	if chosen == Vector3.ZERO:
		return
	forward = forward.lerp(chosen, minf(1.0, 10.0 * delta)).normalized()
	global_position += chosen * step
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
func blocked(dir: Vector3, length: float) -> bool:
	var from := global_position + up * 0.8
	var hit := cast(from, from + dir * length)
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	return n.dot(up) < 0.55   # a gentle slope is walkable, a wall is not

func can_see_ant() -> bool:
	var from := global_position + up * 1.2
	var hit := cast(from, ant.global_position + Vector3(0, 0.5, 0))
	return hit.is_empty()

# Rest on the ground below, tilt with it, and fall if there isn't any.
# A ray that hits a surface from behind means we have ended up inside the ground,
# so in that case we climb back out instead of sinking further.
func stick_to_ground(delta: float) -> void:
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

func animate(delta: float) -> void:
	if moving:
		walk_phase += delta * (14.0 if state != State.WANDER else 8.0)
	for leg in legs:
		var node: Node3D = leg["node"]
		var swing := sin(walk_phase + float(leg["phase"])) * 0.22 if moving else 0.0
		node.rotation.y = float(leg["base"]) + swing * float(leg["side"])
	# A quick lunge forward when biting.
	var lunge := 0.0
	if state == State.ATTACK:
		lunge = maxf(0.0, bite_cd) / BITE_INTERVAL
		lunge = (1.0 - lunge) * 0.0 + (1.0 - absf(lunge * 2.0 - 1.0)) * 0.3
	body_root.position.z = -lunge
