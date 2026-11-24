class_name Spider
extends Creature

# A night hunter. It wanders until it sees an ant, chases it down, and bites.
# It walks on whatever ground is under it (hills, rocks, tunnel floors), found with rays.
# It runs a little slower than a sprinting ant, so sprinting is how you escape.

enum State { WANDER, CHASE, ATTACK, FLEE, RAID, STEPBACK, WEBS, SUMMON, GUARD, CROUCH, LEAP, STUNNED, CURTAIN }

signal summon_requested(spider: Spider, count: int)

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
const QUEEN_SIGHT := 45.0     # smells the queen from this far away and goes for her
const QUEEN_BITE_RANGE := 3.4 # measured to the queen's center, she is big
const QUEEN_BITE_DAMAGE := 4.0
const STUCK_SPEED := 0.1       # speed multiplier while stuck in a web
const STUCK_SECONDS := 4.0
const WEB_COOLDOWN := 2.5     # after breaking free, a spider ignores webs for a moment
const BACKOFF_DIST := 15.0    # the boss retreats this far before spitting webs
const WEB_COUNT := 4
const WEB_WINDUP := 1.1
const WEB_GAP := 0.8
const BROOD_COUNT := 5
const LAST_BROOD_COUNT := 3   # the second, smaller brood at a quarter health

# Boss moves she uses from the start: a pounce (a red ring marks where she lands) and a web
# curtain (a line of web patches across the ground; jump them or go through the gap).
const MOVE_GAP_MIN := 6.0
const MOVE_GAP_MAX := 9.0
const CROUCH_TIME := 1.0
const LEAP_TIME := 0.8
const LEAP_HEIGHT := 7.0
const POUNCE_RADIUS := 4.5
const POUNCE_DAMAGE := 22.0
const STUN_TIME := 1.5
const CURTAIN_WINDUP := 0.9
const CURTAIN_PATCHES := 9
const CURTAIN_SPACING := 2.3
const ANT_PRIORITY := 9.0     # a raiding spider turns on an ant this close

var state := State.WANDER
var queen_getter: Callable   # returns the colony's queen (Placeable) or null. Set by main.
var target := Vector3.ZERO
var wait := 0.0
var bite_cd := 0.0
var stuck_time := 0.0
var web_immunity := 0.0
var flee_time := 0.0
var time := 0.0
var walk_phase := 0.0
var moving := false
var dead := false
var death_time := 0.0
var ghost := false
var move_cd := 5.0
var phase_time := 0.0
var leap_from := Vector3.ZERO
var leap_to := Vector3.ZERO
var phase_three_done := false
var brood_count := BROOD_COUNT
var phase_two_done := false   # boss only: the web and brood phase happens once, at half health
var phase_timer := 0.0
var webs_left := 0
var raise := 0.0
var brood: Array = []
var legs: Array = []          # each: {"node": Node3D, "side": float, "base": float, "phase": float}
var body_root: Node3D

func _ready() -> void:
	max_health = 80.0
	body_radius = 1.4
	reach_radius = 2.1   # the legs stick out about this far to each side
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
	climbing = false   # a spider that dies up a tree falls out of it
	Registry.remove(self, "creatures")   # can't be hit or counted any more
	died.emit(self)

# While her brood is out, the Broodmother cannot be hurt: clear the little ones first.
func take_damage(amount: float) -> void:
	if is_boss and (state == State.SUMMON or state == State.GUARD):
		return
	if state == State.STUNNED:
		amount *= 1.5
	super(amount)

func on_hurt() -> void:
	if is_boss and not phase_two_done and health > 0.0 and health < max_health * 0.5:
		phase_two_done = true
		state = State.STEPBACK
		phase_timer = 2.5
		return
	if is_boss and phase_two_done and not phase_three_done and health > 0.0 and health < max_health * 0.25 and state != State.SUMMON and state != State.GUARD:
		phase_three_done = true   # a second, smaller brood
		brood_count = LAST_BROOD_COUNT
		state = State.SUMMON
		phase_timer = 1.3
		return
	if not is_boss and health < max_health * FLEE_BELOW and state != State.FLEE:
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
		body_root.position = Vector3(sin(angle), 1.0 - cos(angle), 0.0) * size
		if death_time > 2.0:
			body_root.scale = Vector3.ONE * size * maxf(0.0, 1.0 - (death_time - 2.0) * 2.0)
		if death_time > 2.5:
			queue_free()
		return
	if is_loaded.is_valid() and not is_loaded.call(global_position):
		return   # the ground here is not built yet, so wait
	if not active:
		return   # hiding for the day
	time += delta
	bite_cd -= delta
	stuck_time -= delta
	web_immunity -= delta
	check_webs()
	moving = false

	var to_ant := ant.global_position - global_position
	var dist := to_ant.length()

	var panic := fire_react(delta)   # near a fire she runs instead of hunting
	var handled := panic or (is_boss and boss_think(delta, to_ant, dist))
	if not handled:
		match state:
			State.WANDER:
				if dist < SIGHT_RANGE and can_see_ant():
					state = State.CHASE
				elif queen_in_reach():
					state = State.RAID
				else:
					wander(delta)
			State.RAID:
				var q := get_queen()
				if q == null or global_position.distance_to(q.global_position) > QUEEN_SIGHT * 1.3:
					state = State.WANDER
					pick_target()
				elif dist < ANT_PRIORITY and can_see_ant():
					state = State.CHASE
				else:
					var qd := global_position.distance_to(q.global_position)
					if qd < QUEEN_BITE_RANGE:
						face(q.global_position - global_position)
						if bite_cd <= 0.0:
							bite_cd = BITE_INTERVAL
							q.take_damage(QUEEN_BITE_DAMAGE)
					else:
						walk_toward(q.global_position, CHASE_SPEED * 0.8, delta)
			State.CHASE:
				if dist > LOSE_RANGE:
					state = State.WANDER
					pick_target()
				elif dist < BITE_RANGE * size:
					state = State.ATTACK
				else:
					walk_toward(ant.global_position, CHASE_SPEED, delta)
			State.ATTACK:
				face(to_ant)
				if dist > BITE_RANGE * size * 1.5:
					state = State.CHASE
				elif bite_cd <= 0.0:
					bite_cd = BITE_INTERVAL
					ant.take_damage(BITE_DAMAGE * damage_mult)
			State.STEPBACK:
				# Backs away so you have room to see the webs coming.
				phase_timer -= delta
				walk_toward(global_position - to_ant, CHASE_SPEED * 1.3, delta)
				if dist >= BACKOFF_DIST or phase_timer <= 0.0:
					state = State.WEBS
					phase_timer = WEB_WINDUP
					webs_left = WEB_COUNT
			State.WEBS:
				face(to_ant)
				phase_timer -= delta
				if phase_timer <= 0.0:
					if webs_left > 0:
						webs_left -= 1
						spit_web(to_ant)
						phase_timer = WEB_GAP
					else:
						state = State.SUMMON
						phase_timer = 1.3
			State.SUMMON:
				face(to_ant)
				phase_timer -= delta
				if phase_timer <= 0.0:
					brood.clear()
					summon_requested.emit(self, brood_count)
					state = State.GUARD
					phase_timer = 1.0   # a moment for the brood to appear before checking on them
			State.GUARD:
				face(to_ant)
				phase_timer -= delta
				if phase_timer <= 0.0 and brood_cleared():
					state = State.CHASE   # the brood is dead: back to the boss
			State.FLEE:
				flee_time -= delta
				walk_toward(global_position - to_ant, FLEE_SPEED, delta)
				if flee_time <= 0.0:
					state = State.WANDER
					pick_target()

	ease_stop(delta)
	push_apart(delta)
	keep_clear_of_obstacles(delta)
	stick_to_ground(delta)
	apply_pain()
	animate(delta)

# ---------- Boss moves ----------

# Returns true while a pounce, stun or curtain is running (the normal chase and bite are skipped).
func boss_think(delta: float, to_ant: Vector3, dist: float) -> bool:
	phase_time += delta
	match state:
		State.CHASE, State.ATTACK:
			move_cd -= delta * (1.4 if enraged else 1.0)
			if move_cd <= 0.0 and dist < 26.0:
				move_cd = randf_range(MOVE_GAP_MIN, MOVE_GAP_MAX)
				phase_time = 0.0
				var target := ant.global_position
				target.y = burrow_y(target)
				if dist > 7.0 and dist < 22.0 and randf() < 0.6 and pounce_ok(target):
					state = State.CROUCH
					leap_to = target   # she aims once, so you can step away
				else:
					state = State.CURTAIN
				return true
			return false
		State.CROUCH:
			face(leap_to - global_position)
			set_ring(leap_to, POUNCE_RADIUS, true)
			if phase_time >= CROUCH_TIME:
				state = State.LEAP
				phase_time = 0.0
				leap_from = global_position
				ghost = true
			return true
		State.LEAP:
			var u := clampf(phase_time / LEAP_TIME, 0.0, 1.0)
			var p := leap_from.lerp(leap_to, u)
			p.y += sin(u * PI) * LEAP_HEIGHT
			global_position = p
			set_ring(leap_to, POUNCE_RADIUS, true)
			if u >= 1.0:
				land()
			return true
		State.STUNNED:
			if phase_time >= STUN_TIME:
				state = State.CHASE
			return true
		State.CURTAIN:
			face(to_ant)
			if phase_time >= CURTAIN_WINDUP:
				spawn_curtain(to_ant)
				state = State.CHASE
				phase_time = 0.0
			return true
	return false

# A pounce only makes sense when you are on the ground and nothing solid is on the way or at the
# landing spot. Up a tree, behind a trunk or beside a rock she uses the web curtain instead.
func pounce_ok(target: Vector3) -> bool:
	if climbing:
		return false   # no leaping off a trunk
	if ground_at.is_valid():
		var g := float(ground_at.call(target.x, target.z))
		if ant.global_position.y > g + 2.5:
			return false   # you are up a tree or on a rock
	var lift := Vector3(0.0, 1.5, 0.0)
	if not cast(global_position + lift, target + lift).is_empty():
		return false   # something solid on the way
	var r := reach_radius * size
	for i in 8:
		var a := TAU * float(i) / 8.0
		var edge := target + lift + Vector3(cos(a), 0.0, sin(a)) * r
		if not cast(target + lift, edge).is_empty():
			return false   # landing spot is against a trunk or rock
	return true

func land() -> void:
	ghost = false
	set_ring(leap_to, 1.0, false)
	var off := ant.global_position - leap_to
	if Vector2(off.x, off.z).length() < POUNCE_RADIUS and off.y < 2.0:
		ant.take_damage(POUNCE_DAMAGE * damage_mult)
	state = State.STUNNED
	phase_time = 0.0

# A line of web patches across the ground between her and you, with a gap to slip through.
func spawn_curtain(to_ant: Vector3) -> void:
	var flat := to_ant - up * to_ant.dot(up)
	if flat.length() < 0.1:
		return
	var along := flat.normalized()
	var across := along.cross(Vector3.UP).normalized()
	var centre := global_position + along * minf(flat.length() * 0.6, 9.0)
	var gap := randi_range(2, CURTAIN_PATCHES - 3)
	for i in CURTAIN_PATCHES:
		if i == gap or i == gap + 1:
			continue
		var pos := centre + across * (float(i) - float(CURTAIN_PATCHES - 1) * 0.5) * CURTAIN_SPACING
		if ground_at.is_valid():
			pos.y = float(ground_at.call(pos.x, pos.z))
		var patch := WebPatch.new()
		patch.ant = ant
		get_parent().add_child(patch)
		patch.global_position = pos

# Spits one glob of web at where you are now.
func spit_web(to_ant: Vector3) -> void:
	var shot := WebShot.new()
	shot.ant = ant
	var from := global_position + up * (1.8 * size) + forward * (1.2 * size)
	var aim := (ant.global_position + ant.basis.y * 0.4) - from
	shot.velocity = aim.normalized() * WebShot.SPEED
	get_parent().add_child(shot)
	shot.global_position = from

func brood_cleared() -> bool:
	for b in brood:
		if is_instance_valid(b) and not bool(b.get("dead")):
			return false
	return true

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

func queen_in_reach() -> bool:
	var q := get_queen()
	return q != null and global_position.distance_to(q.global_position) < QUEEN_SIGHT

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
				continue   # a trunk she is climbing, or about to
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
		return   # mid-leap: it follows its arc, not the ground
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
	# Rears up while it winds up its webs and when it calls the brood.
	var raise_to := 0.0
	if state == State.SUMMON:
		raise_to = 0.7
	elif state == State.WEBS and phase_timer > WEB_GAP * 0.5:
		raise_to = 0.55
	elif state == State.CROUCH:
		raise_to = -0.3
	elif state == State.LEAP:
		raise_to = 0.4
	raise = lerpf(raise, raise_to, minf(1.0, 8.0 * delta))
	body_root.rotation.x = raise
