class_name Fish
extends Creature

# A lake fish. It never leaves its lake. Most are passive: they drift about in loose shoals and
# dart away when you swim close. A few are aggressive: red, toothed, and fast. They only attack
# while you are SWIMMING in their lake. Climb onto a lily pad (or the shore) and they cannot
# reach you, though a hunting fish will circle underneath and wait.
# Passive fish drop sugar. Aggressive ones drop pearl shells.

const PASSIVE_SPEED := 1.8
const FLEE_SPEED := 6.5
const HUNT_SIGHT := 18.0        # how far an aggressive fish notices a swimmer
const HUNT_LOSE := 30.0
const HUNT_SPEED := 6.8
const BITE_RANGE := 1.5
const BITE_DAMAGE := 7.0
const BITE_COOLDOWN := 1.1
const LURK_RANGE := 12.0        # a hunter circles under you this close when you are out of the water
const ACCEL := 9.0
const ACTIVE_RANGE := 80.0      # farther than this from you, fish just hold still

var aggressive := false
var lake: Dictionary = {}
var terrain: Terrain
var vel := Vector3.ZERO
var target := Vector3.ZERO
var time := randf() * 10.0
var flee_time := 0.0
var bite_cd := 1.0
var retreat := 0.0
var wander_wait := 0.0
var fish_size := 1.0
var tail: Node3D
var species := 0
var tail_rate := 6.0

func _ready() -> void:
	max_health = 40.0 if aggressive else 16.0
	solid = false
	fish_size = randf_range(0.8, 1.3) if not aggressive else randf_range(1.2, 1.5)
	species = randi() % 3
	hit_radius = 0.9 * fish_size
	bar_height = 1.0
	super()
	build_model()
	pick_target()

func loot_kind() -> String:
	return "shell" if aggressive else "sugar"

func on_hurt() -> void:
	if aggressive:
		return
	flee_time = 3.0

# ---------- Model ----------

func blob(mat: StandardMaterial3D, size: Vector3, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	(parent if parent != null else self).add_child(mi)
	return mi

func make_mat(color: Color, rough: float = 0.4, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	return mat

func build_model() -> void:
	var back: Color
	var belly: Color
	var fin: Color
	if aggressive:
		back = Color(0.45, 0.07, 0.06)
		belly = Color(0.85, 0.5, 0.3)
		fin = Color(0.7, 0.12, 0.08)
	else:
		match species:
			0:
				back = Color(0.95, 0.5, 0.12)    # orange
				belly = Color(1.0, 0.85, 0.6)
				fin = Color(1.0, 0.65, 0.25)
			1:
				back = Color(0.35, 0.5, 0.65)    # blue silver
				belly = Color(0.88, 0.92, 0.95)
				fin = Color(0.5, 0.65, 0.8)
			_:
				back = Color(0.85, 0.75, 0.2)    # yellow
				belly = Color(1.0, 0.95, 0.7)
				fin = Color(0.95, 0.85, 0.35)
	var body_mat := make_mat(back, 0.3, 0.35)
	var belly_mat := make_mat(belly, 0.35, 0.25)
	var fin_mat := make_mat(fin, 0.5)
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var eye_white := make_mat(Color(0.95, 0.95, 0.9), 0.2)
	var eye_dark := make_mat(Color(0.03, 0.03, 0.04), 0.1)
	if aggressive:
		eye_dark = make_mat(Color(1.0, 0.1, 0.05), 0.2)
		eye_dark.emission_enabled = true
		eye_dark.emission = Color(1.0, 0.1, 0.05)
		eye_dark.emission_energy_multiplier = 1.6

	var root := Node3D.new()
	root.scale = Vector3.ONE * fish_size
	add_child(root)
	# It swims toward -Z.
	blob(body_mat, Vector3(0.62, 0.72, 1.7), Vector3.ZERO, root)
	blob(belly_mat, Vector3(0.5, 0.45, 1.45), Vector3(0, -0.14, 0.02), root)
	tail = Node3D.new()
	tail.position = Vector3(0, 0, 0.75)
	root.add_child(tail)
	blob(fin_mat, Vector3(0.05, 0.75, 0.55), Vector3(0, 0, 0.32), tail)
	blob(body_mat, Vector3(0.28, 0.3, 0.5), Vector3(0, 0, 0.0), tail)
	blob(fin_mat, Vector3(0.05, 0.42, 0.7), Vector3(0, 0.4, -0.55), root)           # back fin
	for side in [-1.0, 1.0]:
		var pec := blob(fin_mat, Vector3(0.5, 0.05, 0.3), Vector3(side * 0.36, -0.12, -0.35), root)
		pec.rotation.z = side * 0.4
		blob(eye_white, Vector3(0.2, 0.2, 0.2), Vector3(side * 0.24, 0.12, -0.62), root)
		blob(eye_dark, Vector3(0.11, 0.11, 0.11), Vector3(side * 0.31, 0.12, -0.66), root)
	if aggressive:
		# A heavy lower jaw with teeth, and spines along the back.
		blob(body_mat, Vector3(0.5, 0.25, 0.6), Vector3(0, -0.2, -0.72), root)
		var tooth_mat := make_mat(Color(0.97, 0.96, 0.9), 0.3)
		for i in 5:
			var tooth := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.0
			tm.bottom_radius = 0.045
			tm.height = 0.17
			tooth.mesh = tm
			tooth.material_override = tooth_mat
			tooth.position = Vector3(lerpf(-0.18, 0.18, float(i) / 4.0), -0.07, -0.92)
			root.add_child(tooth)
		for i in 4:
			var spine := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.0
			sm.bottom_radius = 0.04
			sm.height = 0.3
			spine.mesh = sm
			spine.material_override = fin_mat
			spine.position = Vector3(0, 0.42, lerpf(-0.45, 0.3, float(i) / 3.0))
			root.add_child(spine)

# ---------- Water ----------

func level() -> float:
	return float(lake.get("level_now", lake.get("level0", 0.0)))

func in_lake(x: float, z: float, frac: float) -> bool:
	return terrain.pool_dist(lake, x, z) < float(lake["radius"]) * frac

func floor_at(x: float, z: float) -> float:
	return terrain.ground_height(x, z)

# The deepest and shallowest this fish will swim at a spot, or an empty array when it is too shallow.
func band(x: float, z: float) -> Array:
	var lo := floor_at(x, z) + 0.55
	var hi := level() - 0.7
	if hi - lo < 0.4:
		return []
	return [lo, hi]

func pick_target() -> void:
	for i in 8:
		var a := randf() * TAU
		var r := randf_range(3.0, 14.0)
		var x := home.x + cos(a) * r
		var z := home.z + sin(a) * r
		if not in_lake(x, z, 0.76):
			continue
		var b := band(x, z)
		if b.is_empty():
			continue
		target = Vector3(x, randf_range(b[0], b[1]), z)
		return
	target = Vector3(home.x, level() - 1.5, home.z)

func ant_in_lake() -> bool:
	return ant.swimming and in_lake(ant.global_position.x, ant.global_position.z, 0.9)

# ---------- Behaviour ----------

func _physics_process(delta: float) -> void:
	if not active or ant == null or lake.is_empty() or terrain == null:
		return
	var to_ant := ant.global_position - global_position
	var dist := to_ant.length()
	if dist > ACTIVE_RANGE:
		return
	time += delta
	bite_cd -= delta
	flee_time -= delta
	retreat -= delta

	var want := Vector3.ZERO
	if aggressive:
		want = hunt(to_ant, dist)
	else:
		want = shy(to_ant, dist)
	if retreat > 0.0:
		want = -to_ant.normalized() * 4.5
	move_fish(want, delta)

	# Tail wag follows how fast it swims.
	tail_rate = lerpf(tail_rate, 5.0 + vel.length() * 2.2, minf(1.0, 4.0 * delta))
	if tail != null:
		tail.rotation.y = sin(time * tail_rate) * (0.25 + 0.05 * vel.length())

func wander(speed: float, delta: float) -> Vector3:
	wander_wait -= delta
	if global_position.distance_to(target) < 1.5:
		if wander_wait <= 0.0 and randf() < 0.4:
			wander_wait = randf_range(1.0, 3.0)   # hang still for a moment
		pick_target()
	if wander_wait > 0.0:
		return Vector3.ZERO
	return (target - global_position).normalized() * speed

# A passive fish: drifts about, bolts away from a swimmer that gets close.
func shy(to_ant: Vector3, dist: float) -> Vector3:
	var swimmer_close := ant_in_lake() and dist < 5.0
	if swimmer_close or flee_time > 0.0:
		var away := -to_ant
		if absf(away.x) + absf(away.z) < 0.01:
			away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
		return away.normalized() * FLEE_SPEED
	return wander(PASSIVE_SPEED, get_physics_process_delta_time())

# An aggressive fish: hunts a swimmer, lurks under a pad, otherwise patrols.
func hunt(to_ant: Vector3, dist: float) -> Vector3:
	var swimmer := ant_in_lake()
	if swimmer and dist < HUNT_SIGHT:
		if dist < BITE_RANGE + 0.6 and bite_cd <= 0.0:
			bite()
		return to_ant.normalized() * HUNT_SPEED
	var out_of_water := not ant.swimming and in_lake(ant.global_position.x, ant.global_position.z, 0.95)
	if out_of_water and dist < LURK_RANGE:
		# You are on a lily pad: circle below you, close but out of reach.
		var a := time * 0.9 + float(get_instance_id() % 7)
		var spot := Vector3(ant.global_position.x + cos(a) * 3.0, level() - 1.6, ant.global_position.z + sin(a) * 3.0)
		return (spot - global_position).limit_length(3.0) * 2.2
	return wander(PASSIVE_SPEED * 1.5, get_physics_process_delta_time())

func bite() -> void:
	bite_cd = BITE_COOLDOWN
	retreat = 0.45   # a quick snap, then it backs off a moment
	ant.take_damage(BITE_DAMAGE * damage_mult)
	Effects.water_splash(get_parent(), ant.global_position + Vector3(0, 0.2, 0))

func move_fish(want: Vector3, delta: float) -> void:
	vel = vel.move_toward(want, ACCEL * delta)
	var next := global_position + vel * delta
	# Stay in the lake: turn back at the edge.
	if not in_lake(next.x, next.z, 0.8):
		var back := Vector3(home.x - global_position.x, 0.0, home.z - global_position.z).normalized()
		vel = vel.lerp(back * maxf(1.5, vel.length()), minf(1.0, 6.0 * delta))
		next = global_position + vel * delta
		if not in_lake(next.x, next.z, 0.84):
			next = global_position
			vel = Vector3.ZERO
			pick_target()
	var b := band(next.x, next.z)
	if b.is_empty():
		next.x = global_position.x
		next.z = global_position.z
		vel = Vector3.ZERO
		pick_target()
	else:
		next.y = clampf(next.y, b[0], b[1])
	global_position = next
	if vel.length() > 0.4:
		var dir := vel
		var flat := Vector2(dir.x, dir.z).length()
		if flat > 0.05:
			var look := Basis.looking_at(dir.normalized(), Vector3.UP)
			var q := basis.get_rotation_quaternion().slerp(look.get_rotation_quaternion(), minf(1.0, 7.0 * delta))
			basis = Basis(q)
