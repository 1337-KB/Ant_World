class_name Centipede
extends Crawler

# A fast night hunter, long and segmented. Its bite is weak but poisons: you keep losing
# health for a few seconds afterwards, until you eat sugar. It is a little slower than a
# sprinting ant, so sprint away. It also goes for the queen, but bites her gently.
# Killing one drops sugar.

enum State { WANDER, CHASE, ATTACK, FLEE, RAID, COIL, SWEEP, BURROW, TUNNEL, RUMBLE, STUN, SPIT, TAIL }

const CHASE_SPEED := 8.5
const FLEE_SPEED := 9.0
const SIGHT_RANGE := 20.0
const LOSE_RANGE := 32.0
const BITE_RANGE := 2.6
const BITE_DAMAGE := 5.0
const BITE_INTERVAL := 1.2
const POISON_SECONDS := 5.0
const POISON_DPS := 3.0
const FLEE_BELOW := 0.25
const QUEEN_SIGHT := 45.0
const QUEEN_BITE_RANGE := 3.6
const QUEEN_BITE_DAMAGE := 3.0
const ANT_PRIORITY := 9.0
const SEGMENTS := 9
const SEG_SPACING := 0.78

# Boss moves. The Elder Centipede coils up and whips its body round in a circle (get out of the
# red ring, or jump over it), and burrows to come up under you (move out of the ring where it
# will surface). Both leave it open to attack afterwards.
const SWEEP_RADIUS := 9.0
const COIL_TIME := 1.1
const SWEEP_TIME := 1.2
const SWEEP_DAMAGE := 18.0
const BURROW_TIME := 0.6
const TUNNEL_SPEED := 17.0
const RUMBLE_TIME := 1.2
const ERUPT_RADIUS := 5.5
const ERUPT_DAMAGE := 22.0
const STUN_TIME := 1.6
const SPIT_WINDUP := 0.8
const SPIT_COUNT := 3
const TAIL_WINDUP := 0.6
const TAIL_RADIUS := 5.0
const TAIL_DAMAGE := 14.0
const TAIL_GAP := 3.0          # seconds between tail whips
const MOVE_GAP_MIN := 6.0
const MOVE_GAP_MAX := 9.0

var state := State.WANDER
var bite_cd := 0.0
var flee_time := 0.0
var tail_cd := 2.0
var chain := 0                # burrows done in a row (below a quarter health it chains two)
var move_cd := 4.0            # boss: seconds until its next special move
var phase_time := 0.0
var sweep_hit := false
var spin := 0.0
var curl := 0.0               # 0 = stretched out, 1 = coiled tight
var dive := 0.0               # how far it has sunk into the ground (0..1)
var erupt_point := Vector3.ZERO
var segs: Array = []          # each: {"node": Node3D, "z": float, "legs": Array}

func _ready() -> void:
	max_health = 60.0
	can_climb = false   # too long and heavy for trunks
	body_radius = 1.0
	wander_speed = 3.0
	nocturnal = true
	uses_trail = true
	super()

func loot_kind() -> String:
	return "sugar"

# Underground it cannot be hurt, and it is easy prey while stunned after a move.
func take_damage(amount: float) -> void:
	if is_boss and (state == State.BURROW or state == State.TUNNEL or state == State.RUMBLE):
		return
	if state == State.STUN:
		amount *= 1.5
	super(amount)

func on_hurt() -> void:
	if not is_boss and health < max_health * FLEE_BELOW and state != State.FLEE:
		state = State.FLEE
		flee_time = 4.0

func build_model() -> void:
	var red := make_mat(Color(0.55, 0.14, 0.07), 0.45, 0.1)
	var orange := make_mat(Color(0.8, 0.38, 0.1), 0.45, 0.1)
	var leg_mat := make_mat(Color(0.85, 0.65, 0.2), 0.6)
	var eye_mat := glow_mat(Color(1.0, 0.85, 0.2))

	body_root = Node3D.new()
	add_child(body_root)

	# The head, with two curved fangs.
	var head := Node3D.new()
	head.position = Vector3(0, 0.55, -0.4)
	body_root.add_child(head)
	add_blob(red, Vector3(0.95, 0.6, 0.9), Vector3.ZERO, head)
	for side in [-1.0, 1.0]:
		add_blob(eye_mat, Vector3(0.12, 0.12, 0.12), Vector3(side * 0.28, 0.15, -0.35), head)
		head.add_child(make_segment(Vector3(side * 0.25, -0.1, -0.35), Vector3(side * 0.1, -0.15, -0.85), 0.07, red))
		# Long feelers.
		head.add_child(make_segment(Vector3(side * 0.2, 0.1, -0.4), Vector3(side * 0.7, 0.4, -1.3), 0.03, leg_mat))

	# A row of segments behind it, each with a pair of legs.
	for i in SEGMENTS:
		var node := Node3D.new()
		var z := 0.25 + i * SEG_SPACING
		node.position = Vector3(0, 0.55, z)
		body_root.add_child(node)
		var taper := 1.0 - 0.04 * i
		add_blob(red if i % 2 == 0 else orange, Vector3(0.95 * taper, 0.55, 0.95), Vector3.ZERO, node)
		var pair := []
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.4, -0.1, 0.0)
			pivot.add_child(make_segment(Vector3.ZERO, Vector3(side * 0.55, -0.15, 0.0), 0.05, leg_mat))
			pivot.add_child(make_segment(Vector3(side * 0.55, -0.15, 0.0), Vector3(side * 0.8, -0.5, 0.0), 0.045, leg_mat))
			node.add_child(pivot)
			pair.append({"node": pivot, "side": side})
		segs.append({"node": node, "z": z, "legs": pair})

func queen_in_reach() -> bool:
	var q := get_queen()
	return q != null and global_position.distance_to(q.global_position) < QUEEN_SIGHT

func think(delta: float, to_ant: Vector3, dist: float) -> void:
	bite_cd -= delta
	if is_boss:
		if boss_think(delta, to_ant, dist):
			return
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
					walk_toward(q.global_position, CHASE_SPEED * 0.7, delta)
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
				ant.apply_poison(POISON_SECONDS, POISON_DPS)
		State.FLEE:
			flee_time -= delta
			walk_toward(global_position - to_ant, FLEE_SPEED, delta)
			if flee_time <= 0.0:
				state = State.WANDER
				pick_target()

# ---------- Boss moves ----------

# Returns true when a special move is running (the normal chase and bite are skipped).
func boss_think(delta: float, to_ant: Vector3, dist: float) -> bool:
	phase_time += delta
	var flat := to_ant - up * to_ant.dot(up)
	match state:
		State.CHASE, State.ATTACK:
			move_cd -= delta * (1.4 if enraged else 1.0)
			tail_cd -= delta
			# Stand behind it and the tail whips round.
			var behind := forward.dot(flat.normalized()) < -0.2 if flat.length() > 0.1 else false
			if tail_cd <= 0.0 and behind and dist < TAIL_RADIUS * 2.0:
				state = State.TAIL
				phase_time = 0.0
				return true
			if move_cd <= 0.0 and dist < 32.0 and dist > 2.0:
				if dist > 11.0 and randf() < 0.5:
					state = State.SPIT
					phase_time = 0.0
					move_cd = randf_range(MOVE_GAP_MIN, MOVE_GAP_MAX)
				elif dist < SWEEP_RADIUS * 0.8 and randf() < 0.65:
					begin_sweep()
				else:
					begin_burrow()
				return true
			return false
		State.SPIT:
			face(to_ant)
			if phase_time >= SPIT_WINDUP:
				spit_poison()
				state = State.STUN   # a short breather after spitting
				phase_time = 0.0
			return true
		State.TAIL:
			var tail_pos := global_position - forward * (float(SEGMENTS) * SEG_SPACING * size * 0.45)
			set_ring(tail_pos, TAIL_RADIUS, true)
			if phase_time >= TAIL_WINDUP:
				set_ring(tail_pos, 1.0, false)
				var off := ant.global_position - tail_pos
				if Vector2(off.x, off.z).length() < TAIL_RADIUS and off.y < 2.0:
					ant.take_damage(TAIL_DAMAGE * damage_mult)
					ant.apply_poison(POISON_SECONDS, POISON_DPS)
				tail_cd = TAIL_GAP
				state = State.CHASE
			return true
		State.COIL:
			face(to_ant)
			set_ring(global_position, SWEEP_RADIUS, true)
			if phase_time >= COIL_TIME:
				state = State.SWEEP
				phase_time = 0.0
				sweep_hit = false
			return true
		State.SWEEP:
			spin += delta * TAU * 2.0 / SWEEP_TIME
			set_ring(global_position, SWEEP_RADIUS, true)
			# One hit, halfway through the spin: out of the ring, or in the air, and it misses.
			if not sweep_hit and phase_time >= SWEEP_TIME * 0.5:
				sweep_hit = true
				var off := ant.global_position - global_position
				var along := Vector2(off.x, off.z).length()
				if along < SWEEP_RADIUS and off.y < 0.9:
					ant.take_damage(SWEEP_DAMAGE * damage_mult)
					ant.apply_poison(POISON_SECONDS, POISON_DPS)
			if phase_time >= SWEEP_TIME:
				set_ring(global_position, 1.0, false)
				state = State.STUN
				phase_time = 0.0
				spin = 0.0
				move_cd = randf_range(MOVE_GAP_MIN, MOVE_GAP_MAX)
			return true
		State.BURROW:
			solid = false
			dive = minf(1.0, dive + delta / BURROW_TIME)
			if dive >= 1.0:
				state = State.TUNNEL
				ghost = true
				phase_time = 0.0
			return true
		State.TUNNEL:
			# Swims through the ground toward you, out of sight.
			var dir := flat.normalized() if flat.length() > 0.01 else forward
			global_position += dir * TUNNEL_SPEED * delta
			global_position.y = lerpf(global_position.y, burrow_y(global_position), minf(1.0, 3.0 * delta))
			forward = dir
			if flat.length() < 14.0 or phase_time > 5.0:
				erupt_point = ant.global_position
				erupt_point.y = burrow_y(erupt_point)   # comes up on the ground, never on a tree
				state = State.RUMBLE
				phase_time = 0.0
			return true
		State.RUMBLE:
			# It stops tracking you: the ring shows where it will come up.
			set_ring(erupt_point, ERUPT_RADIUS, true)
			ring.scale = Vector3(ERUPT_RADIUS, 1.0, ERUPT_RADIUS) * (1.0 + 0.06 * sin(phase_time * 25.0))
			var to_pt := erupt_point - global_position
			to_pt.y = 0.0
			if to_pt.length() > 0.5:
				global_position += to_pt.normalized() * minf(to_pt.length(), TUNNEL_SPEED * 1.3 * delta)
			global_position.y = lerpf(global_position.y, erupt_point.y, minf(1.0, 4.0 * delta))
			if phase_time >= RUMBLE_TIME * (0.6 if chain > 0 else 1.0):
				erupt()
			return true
		State.STUN:
			solid = true
			dive = maxf(0.0, dive - delta * 4.0)
			if phase_time >= STUN_TIME:
				state = State.CHASE
			return true
	return false

func begin_sweep() -> void:
	state = State.COIL
	phase_time = 0.0

func begin_burrow() -> void:
	state = State.BURROW
	phase_time = 0.0
	chain = 0
	move_cd = randf_range(MOVE_GAP_MIN, MOVE_GAP_MAX)

# Lobs three globs of poison around where you stand now.
func spit_poison() -> void:
	for i in SPIT_COUNT:
		var shot := PoisonShot.new()
		shot.ant = ant
		shot.from = global_position + up * (1.6 * size) + forward * (1.0 * size)
		var spot := ant.global_position
		if i > 0:
			var a := randf() * TAU
			spot += Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 5.0)
		shot.to = spot
		get_parent().add_child(shot)

# Bursts out of the ground: hits and throws anything in the ring, then lies stunned.
func erupt() -> void:
	set_ring(global_position, 1.0, false)
	trail.clear()   # it comes up with its body stretched out behind it
	var off := ant.global_position - erupt_point
	if Vector2(off.x, off.z).length() < ERUPT_RADIUS and off.y < 2.0:
		ant.take_damage(ERUPT_DAMAGE * damage_mult)
		ant.knock_up(9.0)
		ant.apply_poison(POISON_SECONDS, POISON_DPS)
	phase_time = 0.0
	if health < max_health * 0.25 and chain < 1:
		chain += 1   # nearly dead: it dives again at once, with a shorter warning
		state = State.BURROW
		return
	state = State.STUN
	solid = true
	ghost = false

# Each segment finds the ground under itself, so the body drapes over bumps and slopes instead of
# staying stiff and leaving half of it floating. It rises and falls with the ground and tilts to match it.
func ground_segments(delta: float) -> void:
	if ghost or dive > 0.3:
		return
	var inv := body_root.global_transform.basis.orthonormalized().inverse()
	var blend := minf(1.0, 14.0 * delta)
	for s in segs:
		var node: Node3D = s["node"]
		var p := body_root.to_global(node.position)
		var hit := cast(p + up * 1.6, p - up * 2.4)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.y <= 0.05:
			continue   # inside rock; leave it where the trail put it
		var n_local := (inv * n).normalized()
		node.position = body_root.to_local(hit["position"]) + n_local * 0.55
		# Tilt to the ground: pitch along the body, roll across it, measured in the segment's own heading.
		var in_heading := Basis(Vector3.UP, node.rotation.y).inverse() * n_local
		var roll := asin(clampf(-in_heading.x, -0.9, 0.9))
		var pitch := atan2(in_heading.z, in_heading.y)
		node.rotation.x = lerp_angle(node.rotation.x, pitch, blend)
		node.rotation.z = lerp_angle(node.rotation.z, roll, blend)

func animate(delta: float) -> void:
	if moving:
		walk_phase += delta * (20.0 if state != State.WANDER else 10.0)
	var curl_to := 1.0 if (state == State.COIL or state == State.SWEEP) else 0.0
	curl = lerpf(curl, curl_to, minf(1.0, 7.0 * delta))
	var burrowed := state == State.BURROW or state == State.TUNNEL or state == State.RUMBLE
	if burrowed and state != State.BURROW:
		dive = 1.0
	body_root.position.y = -3.5 * size * dive
	body_root.visible = dive < 0.95
	for i in segs.size():
		var s: Dictionary = segs[i]
		var node: Node3D = s["node"]
		node.position.z = lerpf(float(s["z"]), float(s["z"]) * 0.5, curl)
		# The body ripples from head to tail while moving.
		var wave := sin(walk_phase - float(i) * 0.7) * 0.3 if moving else 0.0
		node.position.x = wave
		for leg in s["legs"]:
			var pivot: Node3D = leg["node"]
			var swing := sin(walk_phase * 1.0 - float(i) * 0.7 + (0.0 if float(leg["side"]) > 0.0 else PI)) * 0.4 if moving else 0.0
			pivot.rotation.y = swing
	# The body follows the path the head took. While coiled for the sweep it uses the tight layout.
	if curl < 0.05 and state != State.COIL and state != State.SWEEP:
		follow_trail(body_root, segs, -0.4, 0.55)
		ground_segments(delta)
	else:
		for s in segs:
			(s["node"] as Node3D).rotation.y = 0.0
			(s["node"] as Node3D).position.y = 0.55
	# The front rears back a little when biting.
	var rear := 0.0
	if state == State.ATTACK:
		rear = maxf(0.0, 1.0 - absf(bite_cd / BITE_INTERVAL * 2.0 - 1.0)) * 0.25
	if state == State.COIL:
		rear = -0.35   # rears back as it coils
	body_root.rotation.x = lerpf(body_root.rotation.x, -rear, minf(1.0, 10.0 * delta))
	body_root.rotation.y = spin
