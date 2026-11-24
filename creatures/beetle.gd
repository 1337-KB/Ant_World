class_name Beetle
extends Crawler

# A day beetle in a hard shell. It ignores you until you come close, then rears up and
# charges in a straight line. Dodge sideways and it crashes past, then rests, tired, with its
# shell open. Its armor cuts most damage while it is on its feet, but not while it rests.
# It only goes for ants, never the queen. Killing one drops resin.

enum State { WANDER, WINDUP, CHARGE, RECOVER, CURL, ROLL, STUN, SLAM_WIND }

const SIGHT_RANGE := 13.0
const WINDUP_TIME := 0.9      # how long it rears up before charging, your cue to move
const CHARGE_SPEED := 10.0    # faster than a sprinting ant, but only for a short run
const CHARGE_TIME := 1.1
const RECOVER_TIME := 2.2     # how long it is tired after a charge
const HIT_RANGE := 2.1
const HIT_DAMAGE := 16.0
const CURL_TIME := 1.0        # boss only: it tucks into a ball before rolling, your cue to get ready
const ROLL_TIME := 6.0        # how long it rolls
const ROLL_SPEED := 11.0
const ROLL_TURN := 1.0        # radians per second it can steer toward you: wide arcs, so you can sidestep
const ROLL_DAMAGE := 14.0
const ROLL_HIT_GAP := 0.7     # seconds between hits while it rolls over you
const ROLL_DIZZY := 3.0       # how long it lies dazed, shell open, afterwards
# Boss only: hitting a wall, tree or rock during a charge or roll stuns it and cracks its shell
# (more damage gets through every time). It also slams the ground around itself.
const WALL_STUN_TIME := 3.0
const CRACK_ARMOR := 0.12     # armor lost per crack
const MAX_CRACKS := 5
const SLAM_WINDUP := 1.1
const SLAM_RADIUS := 7.0
const SLAM_DAMAGE := 20.0
const ARMOR := 0.35           # fraction of damage that gets through while armored

var state := State.WANDER
var timer := 0.0
var charge_dir := Vector3.FORWARD
var hit_done := false
var cracks := 0
var roll_unlocked := false    # boss: below half health it learns to roll
var charges_since_roll := 0
var roll_dir := Vector3.FORWARD
var roll_hit_cd := 0.0
var roll_blocked := 0.0
var roll_spin := 0.0
var head: Node3D
var shell: Node3D
var legs: Array = []          # each: {"node": Node3D, "side": float, "phase": float}

func _ready() -> void:
	max_health = 120.0
	body_radius = 1.5
	wander_speed = 1.6
	diurnal = true
	super()

func loot_kind() -> String:
	return "resin"

# The shell shrugs off most damage, except while the beetle is resting after a charge.
func take_damage(amount: float) -> void:
	if state == State.STUN:
		amount *= 1.5     # dazed against a wall: it takes extra
	elif state != State.RECOVER:
		amount *= minf(0.95, ARMOR + CRACK_ARMOR * float(cracks))
	super(amount)

func on_hurt() -> void:
	if is_boss and not roll_unlocked and health > 0.0 and health < max_health * 0.5:
		roll_unlocked = true
		if state != State.ROLL:
			state = State.CURL
			timer = CURL_TIME
		return
	if state == State.WANDER:
		state = State.WINDUP
		timer = WINDUP_TIME

func build_model() -> void:
	var shell_mat := make_mat(Color(0.07, 0.16, 0.12), 0.25, 0.55)
	var dark := make_mat(Color(0.06, 0.05, 0.04), 0.5)
	var eye_mat := make_mat(Color(0.9, 0.8, 0.2))

	body_root = Node3D.new()
	add_child(body_root)

	shell = Node3D.new()
	shell.position = Vector3(0, 0.95, 0.15)
	body_root.add_child(shell)
	add_blob(shell_mat, Vector3(1.9, 1.25, 2.7), Vector3.ZERO, shell)
	# A seam down the back, where the wing cases meet.
	var seam := make_segment(Vector3(0, 0.6, -1.2), Vector3(0, 0.55, 1.25), 0.03, dark)
	shell.add_child(seam)

	head = Node3D.new()
	head.position = Vector3(0, 0.75, -1.35)
	body_root.add_child(head)
	add_blob(dark, Vector3(1.0, 0.7, 0.9), Vector3.ZERO, head)
	for side in [-1.0, 1.0]:
		add_blob(eye_mat, Vector3(0.14, 0.14, 0.14), Vector3(side * 0.32, 0.1, -0.35), head)
		# Two curved jaws.
		head.add_child(make_segment(Vector3(side * 0.2, -0.05, -0.4), Vector3(side * 0.12, -0.1, -1.0), 0.09, dark))

	# Six short legs.
	for i in 3:
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.7, 0.6, -0.7 + i * 0.7)
			pivot.add_child(make_segment(Vector3.ZERO, Vector3(side * 0.7, -0.15, 0.0), 0.08, dark))
			pivot.add_child(make_segment(Vector3(side * 0.7, -0.15, 0.0), Vector3(side * 1.0, -0.6, 0.0), 0.07, dark))
			body_root.add_child(pivot)
			legs.append({"node": pivot, "side": side, "phase": float(i) * 2.1 + (0.0 if side > 0.0 else PI)})

func think(delta: float, to_ant: Vector3, dist: float) -> void:
	if state == State.CURL or state == State.ROLL:
		roll_think(delta, to_ant, dist)
		return
	match state:
		State.WANDER:
			if dist < SIGHT_RANGE and can_see_ant():
				state = State.WINDUP
				timer = WINDUP_TIME
			else:
				wander(delta)
		State.WINDUP:
			face(to_ant)
			timer -= delta
			if timer <= 0.0:
				charge_dir = (to_ant - up * to_ant.dot(up)).normalized()   # it aims once, so you can dodge
				state = State.CHARGE
				charges_since_roll += 1
				timer = CHARGE_TIME
				hit_done = false
		State.CHARGE:
			timer -= delta
			walk_toward(global_position + charge_dir * 10.0, CHARGE_SPEED, delta)
			if not hit_done and dist < HIT_RANGE * size:
				hit_done = true
				ant.take_damage(HIT_DAMAGE * damage_mult)
			if not moving:
				if is_boss:
					wall_stun()   # ran into something: stunned, and the shell cracks
				else:
					state = State.RECOVER
					timer = RECOVER_TIME + 1.0
			elif timer <= 0.0:
				state = State.RECOVER
				timer = RECOVER_TIME
		State.SLAM_WIND:
			face(to_ant)
			set_ring(global_position, SLAM_RADIUS, true)
			timer -= delta
			if timer <= 0.0:
				set_ring(global_position, 1.0, false)
				var off := ant.global_position - global_position
				if Vector2(off.x, off.z).length() < SLAM_RADIUS and off.y < 0.9:   # jump over it, or get out
					ant.take_damage(SLAM_DAMAGE * damage_mult)
				state = State.RECOVER
				timer = RECOVER_TIME
		State.STUN:
			timer -= delta
			if timer <= 0.0:
				state = State.WINDUP if dist < SIGHT_RANGE * 1.5 else State.WANDER
				timer = WINDUP_TIME
		State.RECOVER:
			timer -= delta
			if timer <= 0.0:
				if is_boss and dist < SLAM_RADIUS * 1.3 and randf() < 0.45:
					state = State.SLAM_WIND
					timer = SLAM_WINDUP
				elif is_boss and roll_unlocked and charges_since_roll >= 2 and dist < SIGHT_RANGE * 2.0:
					state = State.CURL
					timer = CURL_TIME
				elif dist < SIGHT_RANGE * 1.5:
					state = State.WINDUP
					timer = WINDUP_TIME
				else:
					state = State.WANDER
					pick_target()

# Hit a wall: stunned for a few seconds, and a new crack opens in the shell.
func wall_stun() -> void:
	state = State.STUN
	timer = WALL_STUN_TIME
	cracks = mini(MAX_CRACKS, cracks + 1)
	var crack_mat := make_mat(Color(1.0, 0.75, 0.3), 0.4)
	var a := Vector3(randf_range(-0.5, 0.5), 0.62, randf_range(-1.0, 1.0))
	var c := a + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.5, 0.5))
	shell.add_child(make_segment(a, c, 0.04, crack_mat))

# The ball: it curls up, then rolls after you, steering slowly so you can sidestep it.
func roll_think(delta: float, to_ant: Vector3, dist: float) -> void:
	match state:
		State.CURL:
			face(to_ant)
			timer -= delta
			if timer <= 0.0:
				roll_dir = (to_ant - up * to_ant.dot(up)).normalized()
				state = State.ROLL
				timer = ROLL_TIME
				roll_hit_cd = 0.0
				roll_blocked = 0.0
				charges_since_roll = 0
		State.ROLL:
			timer -= delta
			roll_hit_cd -= delta
			var want := (to_ant - up * to_ant.dot(up)).normalized()
			var angle := roll_dir.angle_to(want)
			var most := ROLL_TURN * delta
			if angle <= most:
				roll_dir = want
			else:
				roll_dir = roll_dir.rotated(up, signf(roll_dir.cross(want).dot(up)) * most)
			walk_toward(global_position + roll_dir * 10.0, ROLL_SPEED, delta)
			if roll_hit_cd <= 0.0 and dist < HIT_RANGE * size * 1.2:
				roll_hit_cd = ROLL_HIT_GAP
				ant.take_damage(ROLL_DAMAGE * damage_mult)
			if moving:
				roll_blocked = 0.0
			else:
				roll_blocked += delta
			if roll_blocked > 0.4:
				wall_stun()   # rolled into something
			elif timer <= 0.0:
				state = State.RECOVER   # unrolls, dazed and without its armor
				timer = ROLL_DIZZY

func animate(delta: float) -> void:
	if moving:
		walk_phase += delta * (16.0 if state == State.CHARGE else 7.0)
	for leg in legs:
		var node: Node3D = leg["node"]
		var swing := sin(walk_phase + float(leg["phase"])) * 0.3 if moving else 0.0
		node.rotation.y = swing * float(leg["side"])
	# Rears up while winding up, lowers its head to charge, and opens the shell to rest.
	var head_pitch := 0.0
	var shell_open := 0.0
	match state:
		State.WINDUP:
			head_pitch = -0.5
		State.CHARGE:
			head_pitch = 0.35
		State.RECOVER, State.STUN:
			shell_open = 0.35
			head_pitch = 0.2
		State.SLAM_WIND:
			head_pitch = -0.7
	# Curled into a ball: the shell swells round, the head and legs tuck away, and it spins.
	var ball := state == State.CURL or state == State.ROLL
	var ball_scale := Vector3(1.0, 1.45, 0.75) if ball else Vector3.ONE
	shell.scale = shell.scale.lerp(ball_scale, minf(1.0, 9.0 * delta))
	head.visible = not (state == State.ROLL or (state == State.CURL and timer < CURL_TIME * 0.4))
	for leg in legs:
		(leg["node"] as Node3D).visible = not ball
	if state == State.ROLL:
		roll_spin = fposmod(roll_spin - ROLL_SPEED * delta / 0.95, TAU)
		shell.rotation.x = roll_spin
		body_root.rotation.x = 0.0
		return
	elif state == State.CURL:
		shell.rotation.x = lerpf(shell.rotation.x, 0.0, minf(1.0, 8.0 * delta))
		body_root.rotation.x = lerpf(body_root.rotation.x, -0.25, minf(1.0, 8.0 * delta))
		return
	head.rotation.x = lerpf(head.rotation.x, head_pitch, minf(1.0, 10.0 * delta))
	shell.rotation.x = lerpf(shell.rotation.x, -shell_open, minf(1.0, 8.0 * delta))
	var body_pitch := 0.0
	if state == State.WINDUP:
		body_pitch = -0.18
	elif state == State.SLAM_WIND:
		body_pitch = 0.6   # rears up on its back legs
	body_root.rotation.x = lerpf(body_root.rotation.x, body_pitch, minf(1.0, 8.0 * delta))
