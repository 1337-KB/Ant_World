class_name TunnelWorm
extends Crawler

# A tunnel worm. It lives in the rock deep underground and cannot be seen until you dig into it:
# now and then the ground you dig bursts open and it lunges out. It is big, soft and slow but hits
# hard, so you cannot just dig on and ignore it. You have to beat it: spray acid, throw rocks, dash
# into it, or run (it is slower than a walking ant and gives up if you get far away).
# Killing one drops sugar. The ambush is started by Population.maybe_worm() while you dig.

enum State { EMERGE, CHASE, ATTACK, REAR, DIVE, TUNNEL, RUMBLE, STUN, SPIT, QUAKE_WIND, QUAKE }

signal collapse_requested(point: Vector3)

const EMERGE_TIME := 0.8       # it bursts out, growing from small, and cannot bite yet
const CHASE_SPEED := 4.6
const BITE_RANGE := 2.9
const BITE_DAMAGE := 12.0
const BITE_INTERVAL := 1.3
const GIVE_UP_RANGE := 45.0    # if you get this far away it burrows back into the rock
const SEGMENTS := 7
const SEG_SPACING := 0.8

# Boss moves (Elder Tunnel Worm). It rears up and slams the spot where you stood (a red ring shows
# where it will land), or dives into the rock and bursts up under you (a ring shows where).
# Either way its head is stuck or dazed afterwards, so that is when to hit it.
const MOVE_GAP_MIN := 6.0
const MOVE_GAP_MAX := 9.0
const SLAM_RANGE := 16.0       # it only slams a spot this close to it
const REAR_TIME := 1.2
const SLAM_RADIUS := 4.8
const SLAM_DAMAGE := 24.0
const DIVE_TIME := 0.6
const TUNNEL_SPEED := 15.0
const RUMBLE_TIME := 1.3
const BURST_RADIUS := 5.5
const BURST_DAMAGE := 26.0
const STUN_TIME := 1.8
const SPIT_WINDUP := 1.0
const SPIT_COUNT := 3
const QUAKE_WINDUP := 1.1
const QUAKE_SPEED := 15.0     # how fast the shockwave spreads
const QUAKE_MAX := 26.0
const QUAKE_DAMAGE := 16.0

var state := State.EMERGE
var state_time := 0.0
var bite_cd := 0.5
var segs: Array = []           # each: {"node": Node3D, "z": float}
var head: Node3D
var move_cd := 4.0
var wave: MeshInstance3D
var wave_r := 0.0
var wave_hit := false
var phase_time := 0.0
var dive := 0.0
var rear := 0.0
var target_point := Vector3.ZERO

func _ready() -> void:
	max_health = 90.0
	can_climb = false   # it tunnels, it does not climb
	uses_trail = true
	body_radius = 1.4
	wander_speed = 2.0
	bar_height = 2.2
	bar_scale = 1.3
	hit_radius = 1.7
	hit_offset = Vector3(0, 0.7, 2.0)   # the middle of the long body, behind the head
	super()

func loot_kind() -> String:
	return "sugar"

func build_model() -> void:
	var skin := make_mat(Color(0.78, 0.5, 0.48), 0.55)
	var band := make_mat(Color(0.6, 0.36, 0.36), 0.6)
	var mouth := make_mat(Color(0.25, 0.07, 0.08), 0.5)
	var tooth := make_mat(Color(0.95, 0.92, 0.8), 0.4)
	body_root = Node3D.new()
	add_child(body_root)

	# The head: a rounded front with a dark mouth ringed by teeth.
	head = Node3D.new()
	head.position = Vector3(0, 0.6, -0.2)
	body_root.add_child(head)
	add_blob(skin, Vector3(1.2, 1.0, 1.3), Vector3.ZERO, head)
	add_blob(mouth, Vector3(0.7, 0.6, 0.35), Vector3(0, -0.05, -0.55), head)
	for k in 6:
		var a := float(k) / 6.0 * TAU
		var tip := Vector3(cos(a) * 0.3, sin(a) * 0.26 - 0.05, -0.75)
		var root := Vector3(cos(a) * 0.34, sin(a) * 0.3 - 0.05, -0.55)
		head.add_child(make_segment(root, tip, 0.045, tooth))

	# Ring-shaped segments behind it that get a little thinner toward the tail.
	for i in SEGMENTS:
		var node := Node3D.new()
		var z := 0.7 + float(i) * SEG_SPACING
		node.position = Vector3(0, 0.55, z)
		body_root.add_child(node)
		var taper := 1.0 - 0.07 * float(i)
		add_blob(skin if i % 2 == 0 else band, Vector3(1.1 * taper, 0.9 * taper, 1.0), Vector3.ZERO, node)
		segs.append({"node": node, "z": z})

# Underground it cannot be hurt, and it takes extra damage while stunned after a move.
func take_damage(amount: float) -> void:
	if is_boss and (state == State.DIVE or state == State.TUNNEL or state == State.RUMBLE):
		return
	if state == State.STUN:
		amount *= 1.5
	super(amount)

func think(delta: float, to_ant: Vector3, dist: float) -> void:
	bite_cd -= delta
	state_time += delta
	if is_boss and state != State.EMERGE:
		if boss_think(delta, to_ant, dist):
			return
	if dist > GIVE_UP_RANGE and state != State.EMERGE and not is_boss:
		queue_free()   # burrows away: no loot, and a new one can ambush you later
		return
	match state:
		State.EMERGE:
			face(to_ant)
			if state_time >= EMERGE_TIME:
				state = State.CHASE
		State.CHASE:
			if dist < BITE_RANGE * size:
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

# ---------- Boss moves ----------

# Returns true while a special move is running (the normal chase and bite are skipped).
func boss_think(delta: float, to_ant: Vector3, dist: float) -> bool:
	phase_time += delta
	var flat := to_ant - up * to_ant.dot(up)
	match state:
		State.CHASE, State.ATTACK:
			move_cd -= delta * (1.4 if enraged else 1.0)
			if move_cd <= 0.0 and dist < 34.0:
				move_cd = randf_range(MOVE_GAP_MIN, MOVE_GAP_MAX)
				phase_time = 0.0
				var pick := randf()
				if dist < SLAM_RANGE and pick < 0.4:
					state = State.REAR
					target_point = ant.global_position   # it aims once, so you can step away
					target_point.y = burrow_y(target_point)
				elif dist < QUAKE_MAX - 2.0 and pick < 0.65:
					state = State.QUAKE_WIND
				elif dist > 8.0 and pick < 0.85:
					state = State.SPIT
				else:
					state = State.DIVE
				return true
		State.SPIT:
			face(to_ant)
			if phase_time >= SPIT_WINDUP:
				spit_rocks()
				state = State.STUN
				phase_time = 0.0
			return true
		State.QUAKE_WIND:
			face(to_ant)
			if phase_time >= QUAKE_WINDUP:
				state = State.QUAKE
				phase_time = 0.0
				wave_r = 1.0
				wave_hit = false
			return true
		State.QUAKE:
			# A shockwave spreads out along the ground. Jump when it reaches you.
			wave_r += QUAKE_SPEED * delta
			set_wave(wave_r, true)
			if not wave_hit:
				var off := ant.global_position - global_position
				var along := Vector2(off.x, off.z).length()
				if absf(along - wave_r) < 1.4:
					wave_hit = true
					if off.y < 0.9:
						ant.take_damage(QUAKE_DAMAGE * damage_mult)
			if wave_r >= QUAKE_MAX:
				set_wave(0.0, false)
				state = State.STUN
				phase_time = 0.0
			return true
			return false
		State.REAR:
			face(target_point - global_position)
			set_ring(target_point, SLAM_RADIUS, true)
			if phase_time >= REAR_TIME:
				slam()
			return true
		State.DIVE:
			solid = false
			dive = minf(1.0, dive + delta / DIVE_TIME)
			if dive >= 1.0:
				state = State.TUNNEL
				ghost = true
				phase_time = 0.0
			return true
		State.TUNNEL:
			var dir := flat.normalized() if flat.length() > 0.01 else forward
			global_position += dir * TUNNEL_SPEED * delta
			global_position.y = lerpf(global_position.y, burrow_y(global_position), minf(1.0, 3.0 * delta))
			forward = dir
			if flat.length() < 14.0 or phase_time > 5.0:
				target_point = ant.global_position
				target_point.y = burrow_y(target_point)   # comes up on the ground, never on a tree
				state = State.RUMBLE
				phase_time = 0.0
			return true
		State.RUMBLE:
			set_ring(target_point, BURST_RADIUS, true)
			ring.scale = Vector3(BURST_RADIUS, 1.0, BURST_RADIUS) * (1.0 + 0.06 * sin(phase_time * 25.0))
			var to_pt := target_point - global_position
			to_pt.y = 0.0
			if to_pt.length() > 0.5:
				global_position += to_pt.normalized() * minf(to_pt.length(), TUNNEL_SPEED * 1.3 * delta)
			global_position.y = lerpf(global_position.y, target_point.y, minf(1.0, 4.0 * delta))
			if phase_time >= RUMBLE_TIME:
				burst()
			return true
		State.STUN:
			solid = true
			dive = maxf(0.0, dive - delta * 4.0)
			if phase_time >= STUN_TIME:
				state = State.CHASE
			return true
	return false

# A ring that spreads along the ground, the quake's shockwave.
func set_wave(radius: float, shown: bool) -> void:
	if wave == null:
		wave = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.95
		tm.outer_radius = 1.0
		tm.rings = 48
		tm.ring_segments = 6
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.9, 0.7, 0.4, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.material = mat
		wave.mesh = tm
		wave.top_level = true
		add_child(wave)
	wave.visible = shown
	if shown:
		wave.global_position = global_position + Vector3(0, 0.3, 0)
		wave.scale = Vector3(radius, radius * 0.3, radius)

# Spits three chunks of rock around where you stand. They land as boulders you can hide behind.
func spit_rocks() -> void:
	for i in SPIT_COUNT:
		var chunk := RockChunk.new()
		chunk.ant = ant
		chunk.from = global_position + up * (2.2 * size) + forward * (1.2 * size)
		var spot := ant.global_position
		if i > 0:
			var a := randf() * TAU
			spot += Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 6.0)
		chunk.to = spot
		get_parent().add_child(chunk)

# The head comes down on the marked spot.
func slam() -> void:
	set_ring(target_point, 1.0, false)
	var off := ant.global_position - target_point
	if Vector2(off.x, off.z).length() < SLAM_RADIUS and off.y < 2.0:
		ant.take_damage(SLAM_DAMAGE * damage_mult)
		ant.knock_up(6.0)
	state = State.STUN
	phase_time = 0.0

# Comes up out of the rock under the marked spot, throwing anything there into the air.
func burst() -> void:
	set_ring(target_point, 1.0, false)
	trail.clear()
	var off := ant.global_position - target_point
	if Vector2(off.x, off.z).length() < BURST_RADIUS and off.y < 2.0:
		ant.take_damage(BURST_DAMAGE * damage_mult)
		ant.knock_up(11.0)
	state = State.STUN
	phase_time = 0.0
	solid = true
	ghost = false
	collapse_requested.emit(target_point)   # the burst shakes the ceiling loose, if there is one

func animate(delta: float) -> void:
	if moving:
		walk_phase += delta * 9.0
	if state == State.EMERGE:
		# Bursts out of the rock: grows from small with an overshoot.
		var t := clampf(state_time / EMERGE_TIME, 0.0, 1.0)
		var s := lerpf(0.15, 1.0, t) + sin(t * PI) * 0.12
		body_root.scale = Vector3.ONE * s * size
	else:
		body_root.scale = Vector3.ONE * size
	var burrowed := state == State.DIVE or state == State.TUNNEL or state == State.RUMBLE
	if burrowed and state != State.DIVE:
		dive = 1.0
	body_root.position.y = -3.5 * size * dive
	body_root.visible = dive < 0.95
	# Rears up before a slam, then drops fast.
	rear = lerpf(rear, 0.6 if state == State.REAR else (0.35 if (state == State.SPIT or state == State.QUAKE_WIND) else 0.0), minf(1.0, (6.0 if state == State.REAR else 14.0) * delta))
	body_root.rotation.x = rear
	# Pivot about the tail, so the head lifts instead of the tail sinking into the ground.
	var tail_z := (0.7 + float(SEGMENTS - 1) * SEG_SPACING) * size
	body_root.position.y += tail_z * sin(rear)
	body_root.position.z = tail_z * (1.0 - cos(rear))
	for i in segs.size():
		var node: Node3D = (segs[i] as Dictionary)["node"]
		# A wave runs down the body while it crawls.
		var wave := sin(walk_phase - float(i) * 0.8) * 0.3 if moving else 0.0
		node.position.x = wave
		node.position.y = 0.55 + absf(sin(walk_phase * 0.5 - float(i) * 0.4)) * 0.08 if moving else 0.55
	# The body follows the path the head took.
	follow_trail(body_root, segs, -0.2, 0.55)
	# The head rears back and lunges forward with each bite.
	var lunge := 0.0
	var bite_rear := 0.0
	if state == State.ATTACK:
		var phase := clampf(1.0 - bite_cd / BITE_INTERVAL, 0.0, 1.0)
		bite_rear = sin(phase * PI) * 0.35
		lunge = maxf(0.0, sin(phase * PI * 2.0)) * 0.3
	head.rotation.x = bite_rear
	head.position.z = -0.2 - lunge
