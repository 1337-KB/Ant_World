class_name Beetle
extends Crawler

# A day beetle in a hard shell. It ignores you until you come close, then rears up and
# charges in a straight line. Dodge sideways and it crashes past, then rests, tired, with its
# shell open. Its armor cuts most damage while it is on its feet, but not while it rests.
# It only goes for ants, never the queen. Killing one drops resin.

enum State { WANDER, WINDUP, CHARGE, RECOVER }

const SIGHT_RANGE := 13.0
const WINDUP_TIME := 0.9      # how long it rears up before charging, your cue to move
const CHARGE_SPEED := 10.0    # faster than a sprinting ant, but only for a short run
const CHARGE_TIME := 1.1
const RECOVER_TIME := 2.2     # how long it is tired after a charge
const HIT_RANGE := 2.1
const HIT_DAMAGE := 16.0
const ARMOR := 0.35           # fraction of damage that gets through while armored

var state := State.WANDER
var timer := 0.0
var charge_dir := Vector3.FORWARD
var hit_done := false
var head: Node3D
var shell: Node3D
var legs: Array = []          # each: {"node": Node3D, "side": float, "phase": float}

func _ready() -> void:
	max_health = 120.0
	wander_speed = 1.6
	diurnal = true
	super()

func loot_kind() -> String:
	return "resin"

# The shell shrugs off most damage, except while the beetle is resting after a charge.
func take_damage(amount: float) -> void:
	if state != State.RECOVER:
		amount *= ARMOR
	super(amount)

func on_hurt() -> void:
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
				timer = CHARGE_TIME
				hit_done = false
		State.CHARGE:
			timer -= delta
			walk_toward(global_position + charge_dir * 10.0, CHARGE_SPEED, delta)
			if not hit_done and dist < HIT_RANGE:
				hit_done = true
				ant.take_damage(HIT_DAMAGE)
			if not moving:
				state = State.RECOVER   # ran into something
				timer = RECOVER_TIME + 1.0
			elif timer <= 0.0:
				state = State.RECOVER
				timer = RECOVER_TIME
		State.RECOVER:
			timer -= delta
			if timer <= 0.0:
				if dist < SIGHT_RANGE * 1.5:
					state = State.WINDUP
					timer = WINDUP_TIME
				else:
					state = State.WANDER
					pick_target()

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
		State.RECOVER:
			shell_open = 0.35
			head_pitch = 0.2
	head.rotation.x = lerpf(head.rotation.x, head_pitch, minf(1.0, 10.0 * delta))
	shell.rotation.x = lerpf(shell.rotation.x, -shell_open, minf(1.0, 8.0 * delta))
	body_root.rotation.x = lerpf(body_root.rotation.x, -0.18 if state == State.WINDUP else 0.0, minf(1.0, 8.0 * delta))
