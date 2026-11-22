class_name Centipede
extends Crawler

# A fast night hunter, long and segmented. Its bite is weak but poisons: you keep losing
# health for a few seconds afterwards, until you eat sugar. It is a little slower than a
# sprinting ant, so sprint away. It also goes for the queen, but bites her gently.
# Killing one drops sugar.

enum State { WANDER, CHASE, ATTACK, FLEE, RAID }

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

var state := State.WANDER
var bite_cd := 0.0
var flee_time := 0.0
var segs: Array = []          # each: {"node": Node3D, "z": float, "legs": Array}

func _ready() -> void:
	max_health = 60.0
	wander_speed = 3.0
	nocturnal = true
	super()

func loot_kind() -> String:
	return "sugar"

func on_hurt() -> void:
	if health < max_health * FLEE_BELOW and state != State.FLEE:
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
				ant.apply_poison(POISON_SECONDS, POISON_DPS)
		State.FLEE:
			flee_time -= delta
			walk_toward(global_position - to_ant, FLEE_SPEED, delta)
			if flee_time <= 0.0:
				state = State.WANDER
				pick_target()

func animate(delta: float) -> void:
	if moving:
		walk_phase += delta * (20.0 if state != State.WANDER else 10.0)
	for i in segs.size():
		var s: Dictionary = segs[i]
		var node: Node3D = s["node"]
		# The body ripples from head to tail while moving.
		var wave := sin(walk_phase - float(i) * 0.7) * 0.3 if moving else 0.0
		node.position.x = wave
		for leg in s["legs"]:
			var pivot: Node3D = leg["node"]
			var swing := sin(walk_phase * 1.0 - float(i) * 0.7 + (0.0 if float(leg["side"]) > 0.0 else PI)) * 0.4 if moving else 0.0
			pivot.rotation.y = swing
	# The front rears back a little when biting.
	var rear := 0.0
	if state == State.ATTACK:
		rear = maxf(0.0, 1.0 - absf(bite_cd / BITE_INTERVAL * 2.0 - 1.0)) * 0.25
	body_root.rotation.x = -rear
