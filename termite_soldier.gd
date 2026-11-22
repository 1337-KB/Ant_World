class_name TermiteSoldier
extends Crawler

# A termite soldier: a big orange head with long jaws. It never leaves the mound's guard posts
# unless something threatens the colony. It chases ants that come near, rushes to anywhere
# the alarm was raised, and gives up (and returns to its post) if you get far from the mound.
# It is a little slower than a walking ant, so running away works. If the queen dies, soldiers
# lose their purpose and fade away.

enum State { GUARD, CHASE, ATTACK, RETURN }

const SIGHT_RANGE := 14.0
const ATTACK_RANGE := 2.4
const DAMAGE := 8.0
const BITE_INTERVAL := 1.1
const CHASE_SPEED := 5.2
const RETURN_SPEED := 6.0
const LEASH := 55.0           # does not chase an ant that is farther than this from the mound
const ALARM_LEASH := 80.0     # during an alarm, it chases farther

static var passive := true   # when true, soldiers never attack (toggled with [P] in main)
var colony: Dictionary
var state := State.GUARD
var bite_cd := 0.0
var fade_after := -1.0
var head: Node3D
var legs: Array = []

func _ready() -> void:
	max_health = 70.0
	wander_speed = 1.8
	wander_radius = 4.0
	super()

func loot_kind() -> String:
	if colony.get("dead", false):
		return ""
	return "pebble"

func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func on_hurt() -> void:
	colony["alarm_until"] = now() + 25.0
	if state == State.GUARD or state == State.RETURN:
		state = State.CHASE

func build_model() -> void:
	var skin := make_mat(Color(0.9, 0.84, 0.66), 0.7)
	var head_mat := make_mat(Color(0.78, 0.35, 0.08), 0.4, 0.15)
	var dark := make_mat(Color(0.2, 0.12, 0.07), 0.5)
	body_root = Node3D.new()
	add_child(body_root)
	add_blob(skin, Vector3(1.0, 0.8, 1.2), Vector3(0, 0.7, 0.65))      # abdomen
	add_blob(skin, Vector3(0.85, 0.7, 0.8), Vector3(0, 0.7, -0.15))    # thorax
	head = Node3D.new()
	head.position = Vector3(0, 0.75, -0.95)
	body_root.add_child(head)
	add_blob(head_mat, Vector3(0.85, 0.65, 1.15), Vector3.ZERO, head)  # the big armored head
	for side in [-1.0, 1.0]:
		# Long crossed jaws.
		head.add_child(make_segment(Vector3(side * 0.22, -0.05, -0.5), Vector3(side * -0.1, -0.1, -1.3), 0.09, dark))
		add_blob(dark, Vector3(0.1, 0.1, 0.1), Vector3(side * 0.28, 0.15, -0.35), head)
	for i in 3:
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.4, 0.55, -0.4 + i * 0.5)
			pivot.add_child(make_segment(Vector3.ZERO, Vector3(side * 0.6, -0.05, 0.0), 0.06, dark))
			pivot.add_child(make_segment(Vector3(side * 0.6, -0.05, 0.0), Vector3(side * 0.85, -0.55, 0.0), 0.05, dark))
			body_root.add_child(pivot)
			legs.append({"node": pivot, "side": side, "phase": float(i) * 2.1 + (0.0 if side > 0.0 else PI)})

func think(delta: float, to_ant: Vector3, dist: float) -> void:
	bite_cd -= delta
	if colony.get("dead", false):
		if fade_after < 0.0:
			fade_after = randf_range(15.0, 50.0)
		fade_after -= delta
		if fade_after <= 0.0:
			take_damage(9999.0)
			return
		wander(delta)
		return

	if passive:
		state = State.GUARD
		if global_position.distance_to(home) > 8.0:
			walk_toward(home, RETURN_SPEED, delta)
		else:
			wander(delta)
		return

	var center: Vector3 = colony["center"]
	var ant_off := Vector2(ant.global_position.x - center.x, ant.global_position.z - center.z).length()
	var alarmed := now() < float(colony["alarm_until"])
	var leash := ALARM_LEASH if alarmed else LEASH

	match state:
		State.GUARD:
			if dist < SIGHT_RANGE and ant_off < leash and can_see_ant():
				state = State.CHASE
			elif alarmed and ant_off < leash and dist < 60.0:
				state = State.CHASE
			else:
				wander(delta)
		State.CHASE:
			if ant_off > leash + 10.0 or dist > 70.0:
				state = State.RETURN
			elif dist < ATTACK_RANGE:
				state = State.ATTACK
			else:
				walk_toward(ant.global_position, CHASE_SPEED, delta)
		State.ATTACK:
			face(to_ant)
			if dist > ATTACK_RANGE * 1.5:
				state = State.CHASE
			elif bite_cd <= 0.0:
				bite_cd = BITE_INTERVAL
				ant.take_damage(DAMAGE)
		State.RETURN:
			walk_toward(home, RETURN_SPEED, delta)
			if global_position.distance_to(home) < 3.0:
				state = State.GUARD
				pick_target()
			elif dist < SIGHT_RANGE * 0.7 and ant_off < leash and can_see_ant():
				state = State.CHASE

func animate(delta: float) -> void:
	if moving:
		walk_phase += delta * (13.0 if state == State.CHASE or state == State.RETURN else 7.0)
	for leg in legs:
		var node: Node3D = leg["node"]
		var swing := sin(walk_phase + float(leg["phase"])) * 0.3 if moving else 0.0
		node.rotation.y = swing * float(leg["side"])
	# The head jerks forward with each bite.
	var lunge := 0.0
	if state == State.ATTACK:
		lunge = maxf(0.0, 1.0 - absf(bite_cd / BITE_INTERVAL * 2.0 - 1.0)) * 0.35
	head.position.z = -0.95 - lunge
