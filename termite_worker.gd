class_name TermiteWorker
extends Crawler

# A pale, blind-looking termite worker. It walks out from the mound to find resources lying on
# the ground (sugar, pebbles, leaf fiber), takes one at a time back through the entrance and
# adds it to the colony's stores. It is weak and runs from ants, but it raises the alarm, so
# the soldiers come. If the colony's queen dies, workers wander lost and soon fade away.

enum State { SEEK, FETCH, HAUL, FLEE }

const FETCH_SPEED := 4.0
const HAUL_SPEED := 3.6
const FLEE_SPEED := 5.6
const FORAGE_RANGE := 60.0     # looks for resources this far from the mound
const FLEE_RANGE := 9.0
const FOOD := ["sugar", "pebble", "fiber"]

var colony: Dictionary
var state := State.SEEK
var carrying := ""
var fetch_node: Pickup
var haul_stage := 0            # 0: head for the entrance, 1: go inside to the store
var search_cd := 0.0
var flee_time := 0.0
var fade_after := -1.0         # after the queen dies, seconds until it fades away
var carry_mesh: MeshInstance3D
var legs: Array = []

func _ready() -> void:
	max_health = 25.0
	wander_speed = 3.0
	super()

func loot_kind() -> String:
	if colony.get("dead", false):
		return ""
	return carrying if carrying != "" else "fiber"

func build_model() -> void:
	var skin := make_mat(Color(0.93, 0.88, 0.72), 0.7)
	var head_mat := make_mat(Color(0.8, 0.62, 0.35), 0.5)
	var dark := make_mat(Color(0.25, 0.2, 0.15), 0.6)
	body_root = Node3D.new()
	add_child(body_root)
	add_blob(skin, Vector3(0.8, 0.65, 0.95), Vector3(0, 0.55, 0.45))     # abdomen
	add_blob(skin, Vector3(0.65, 0.55, 0.6), Vector3(0, 0.55, -0.2))     # thorax
	add_blob(head_mat, Vector3(0.6, 0.5, 0.55), Vector3(0, 0.55, -0.75)) # head
	for side in [-1.0, 1.0]:
		body_root.add_child(make_segment(Vector3(side * 0.12, 0.5, -1.0), Vector3(side * 0.1, 0.4, -1.3), 0.05, dark))
	for i in 3:
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.3, 0.45, -0.45 + i * 0.4)
			pivot.add_child(make_segment(Vector3.ZERO, Vector3(side * 0.45, -0.05, 0.0), 0.04, dark))
			pivot.add_child(make_segment(Vector3(side * 0.45, -0.05, 0.0), Vector3(side * 0.65, -0.45, 0.0), 0.035, dark))
			body_root.add_child(pivot)
			legs.append({"node": pivot, "side": side, "phase": float(i) * 2.1 + (0.0 if side > 0.0 else PI)})
	# What it carries, held up over its back.
	carry_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	carry_mesh.mesh = sm
	carry_mesh.position = Vector3(0, 1.15, 0.1)
	carry_mesh.visible = false
	body_root.add_child(carry_mesh)

func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func raise_alarm() -> void:
	colony["alarm_until"] = now() + 25.0

func on_hurt() -> void:
	raise_alarm()
	if state != State.FLEE:
		state = State.FLEE
		flee_time = 3.0

func set_carrying(kind: String) -> void:
	carrying = kind
	carry_mesh.visible = kind != ""
	if kind != "":
		var info: Dictionary = Pickup.KINDS[kind]
		var m := make_mat(info["color"], 0.5)
		carry_mesh.material_override = m

func find_pickup() -> Pickup:
	var center: Vector3 = colony["center"]
	var best: Pickup = null
	var best_d := 60.0
	for n in get_tree().get_nodes_in_group("pickups"):
		var p := n as Pickup
		if p == null or not FOOD.has(p.kind):
			continue
		if Vector2(p.global_position.x - center.x, p.global_position.z - center.z).length() > FORAGE_RANGE:
			continue
		if p.has_meta("claimed_by"):
			var other = instance_from_id(int(p.get_meta("claimed_by")))
			if other != null and other != self:
				continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	if best != null:
		best.set_meta("claimed_by", get_instance_id())
	return best

# Where to walk while hauling: around the mound's outside to the entrance, then in.
func haul_point() -> Vector3:
	var center: Vector3 = colony["center"]
	var eo: Vector3 = colony["entrance_out"]
	var ei: Vector3 = colony["entrance_in"]
	if haul_stage == 1:
		return ei
	var rad := float(colony["R"])
	var from_c := Vector2(global_position.x - center.x, global_position.z - center.z)
	var to_e := Vector2(eo.x - center.x, eo.z - center.z)
	if from_c.length() < rad + 12.0:
		var diff := wrapf(to_e.angle() - from_c.angle(), -PI, PI)
		if absf(diff) > 0.6:
			# Circle around the outside of the mound toward the entrance side.
			var ang := from_c.angle() + signf(diff) * 0.7
			var p2 := Vector2(center.x, center.z) + Vector2(cos(ang), sin(ang)) * (rad + 6.0)
			return Vector3(p2.x, global_position.y, p2.y)
	return eo

func think(delta: float, to_ant: Vector3, dist: float) -> void:
	if colony.get("dead", false):
		if fade_after < 0.0:
			fade_after = randf_range(15.0, 50.0)
		fade_after -= delta
		if fade_after <= 0.0:
			take_damage(9999.0)
			return
		wander(delta)
		return

	if state != State.FLEE and dist < FLEE_RANGE and can_see_ant():
		raise_alarm()
		state = State.FLEE
		flee_time = 3.0

	match state:
		State.SEEK:
			search_cd -= delta
			if search_cd <= 0.0:
				search_cd = 2.5
				fetch_node = find_pickup()
				if fetch_node != null:
					state = State.FETCH
			if state == State.SEEK:
				wander(delta)
		State.FETCH:
			if not is_instance_valid(fetch_node):
				state = State.SEEK
				search_cd = 0.0
			else:
				walk_toward(fetch_node.global_position, FETCH_SPEED, delta)
				if global_position.distance_to(fetch_node.global_position) < 1.6:
					var kind := fetch_node.kind
					if fetch_node.take(1) > 0:
						set_carrying(kind)
						haul_stage = 0
						state = State.HAUL
					else:
						state = State.SEEK
		State.HAUL:
			var pt := haul_point()
			walk_toward(pt, HAUL_SPEED, delta)
			if haul_stage == 0 and global_position.distance_to(colony["entrance_out"]) < 3.5:
				haul_stage = 1
			if haul_stage == 1 and global_position.distance_to(colony["entrance_in"]) < 2.5:
				var stock: Dictionary = colony["stock"]
				stock[carrying] = int(stock.get(carrying, 0)) + 1
				set_carrying("")
				state = State.SEEK
				search_cd = 0.0
		State.FLEE:
			flee_time -= delta
			walk_toward(global_position - to_ant, FLEE_SPEED, delta)
			if flee_time <= 0.0:
				if carrying != "":
					state = State.HAUL
				else:
					state = State.SEEK

func animate(delta: float) -> void:
	if moving:
		walk_phase += delta * (14.0 if state == State.FLEE else 9.0)
	for leg in legs:
		var node: Node3D = leg["node"]
		var swing := sin(walk_phase + float(leg["phase"])) * 0.35 if moving else 0.0
		node.rotation.y = swing * float(leg["side"])
