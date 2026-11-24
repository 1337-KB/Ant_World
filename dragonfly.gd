class_name Dragonfly
extends Creature

# A daytime flying hunter. It patrols high over the ground, and once it spots you it circles
# above, then hovers and marks you with a red disc (your cue) before it dives straight at that
# spot. Step out of the disc and it misses and swoops back up. If it hits a tree or rock on the
# way down it crashes and lies stunned, taking extra damage. It is fragile, so acid spray and
# thrown rocks bring it down quickly. It only hunts you. Killing one drops leaf fiber.

enum State { PATROL, STALK, TELL, DIVE, RECOVER, CRASHED }

const SIGHT_RANGE := 40.0
const LOSE_RANGE := 62.0
const PATROL_SPEED := 6.0
const STALK_SPEED := 11.0
const STALK_RADIUS := 12.0     # how wide it circles above you
const STALK_HEIGHT := 9.0      # how high above you it circles
const TELL_TIME := 0.9         # how long it hovers and marks you before the dive
const DIVE_SPEED := 26.0
const DIVE_RADIUS := 2.4       # a dive hits you if you are this close when it passes
const DIVE_DAMAGE := 18.0
const RECOVER_TIME := 1.5
const CRASH_TIME := 2.6
const ACCEL := 22.0
const FIELD_LIMIT := 7000.0    # never leave the world

var state := State.PATROL
var vel := Vector3.ZERO
var target := Vector3.ZERO
var time := 0.0
var timer := 0.0
var cd := 2.0                  # time until it may start another dive
var circle := randf() * TAU
var circle_dir := 1.0 if randf() < 0.5 else -1.0
var dive_to := Vector3.ZERO
var dive_dir := Vector3.FORWARD
var hit_done := false
var recover_goal := Vector3.ZERO
var wings: Array = []          # each: {"node": Node3D, "side": float}

func _ready() -> void:
	max_health = 45.0
	solid = false                # flyers pass through others
	hit_radius = 2.2             # a fast flyer is hit anywhere close to its middle
	bar_height = 2.2
	bar_scale = 1.2
	super()
	diurnal = true
	build_model()
	pick_target()

func loot_kind() -> String:
	return "fiber"

# Lying stunned after a crash it takes extra damage.
func take_damage(amount: float) -> void:
	if state == State.CRASHED:
		amount *= 1.5
	super(amount)

func on_hurt() -> void:
	if state == State.PATROL:
		state = State.STALK
		cd = 0.8

# ---------- Model ----------

func blob(mat: StandardMaterial3D, size: Vector3, pos: Vector3, parent: Node3D = null) -> void:
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
	(parent if parent != null else self).add_child(mi)

func make_mat(color: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	return mat

func build_model() -> void:
	var teal := make_mat(Color(0.08, 0.5, 0.62), 0.3, 0.5)
	var dark := make_mat(Color(0.05, 0.12, 0.18), 0.4, 0.3)
	var eye := make_mat(Color(0.2, 0.75, 0.55), 0.15)
	eye.emission_enabled = true
	eye.emission = Color(0.1, 0.6, 0.4)
	eye.emission_energy_multiplier = 0.8

	# It flies toward -Z. Thorax, big-eyed head, and a long banded abdomen behind.
	blob(teal, Vector3(0.95, 0.85, 1.4), Vector3(0, 0, -0.2))
	blob(dark, Vector3(0.95, 0.8, 0.85), Vector3(0, -0.04, -1.25))
	for side in [-1.0, 1.0]:
		blob(eye, Vector3(0.5, 0.55, 0.6), Vector3(side * 0.38, 0.04, -1.38))
	for i in 7:
		var t := float(i) / 6.0
		var r := lerpf(0.34, 0.16, t)
		blob(teal if i % 2 == 0 else dark, Vector3(r * 2.0, r * 2.0, 0.78), Vector3(0, 0.02, 0.6 + float(i) * 0.62))

	# Four long, clear wings that beat.
	var wing_mat := make_mat(Color(0.85, 0.95, 1.0, 0.35), 0.2)
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for z in [-0.55, 0.15]:
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.3, 0.38, z)
			add_child(pivot)
			var wing := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(3.4, 0.03, 0.85)
			wing.mesh = bm
			wing.material_override = wing_mat
			wing.position = Vector3(side * 1.7, 0, 0)
			pivot.add_child(wing)
			wings.append({"node": pivot, "side": side})

# ---------- Behaviour ----------

func ground_y(p: Vector3) -> float:
	if ground_at.is_valid():
		return float(ground_at.call(p.x, p.z))
	return 0.0

func pick_target() -> void:
	var a := randf() * TAU
	var r := randf_range(8.0, 30.0)
	var x := clampf(home.x + cos(a) * r, -FIELD_LIMIT, FIELD_LIMIT)
	var z := clampf(home.z + sin(a) * r, -FIELD_LIMIT, FIELD_LIMIT)
	target = Vector3(x, ground_y(Vector3(x, 0, z)) + randf_range(7.0, 13.0), z)

# It only bothers with you when you are out on the surface, not deep in a tunnel.
func ant_exposed() -> bool:
	return ant.global_position.y > ground_y(ant.global_position) - 3.0

func cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	if ant != null:
		q.exclude = [ant.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

func _physics_process(delta: float) -> void:
	if not active:
		return   # asleep for the night
	if is_loaded.is_valid() and not is_loaded.call(global_position):
		return   # the ground here is not built yet, so wait
	time += delta
	cd -= delta
	var to_ant := ant.global_position - global_position
	var dist := to_ant.length()

	match state:
		State.PATROL:
			if dist < SIGHT_RANGE and ant_exposed():
				state = State.STALK
				cd = randf_range(1.2, 2.4)
			else:
				if global_position.distance_to(target) < 3.0:
					pick_target()
				fly((target - global_position).normalized() * PATROL_SPEED, ACCEL * 0.5, delta, true)
		State.STALK:
			if dist > LOSE_RANGE or not ant_exposed():
				state = State.PATROL
				pick_target()
			else:
				circle += delta * 0.8 * circle_dir
				var goal := ant.global_position + Vector3(cos(circle), 0.0, sin(circle)) * STALK_RADIUS
				goal.y = ant.global_position.y + STALK_HEIGHT
				var off := goal - global_position
				var speed := STALK_SPEED * clampf(off.length() / 6.0, 0.25, 1.0)
				fly(off.normalized() * speed, ACCEL, delta, true)
				var flat := Vector2(to_ant.x, to_ant.z).length()
				if cd <= 0.0 and flat < 26.0 and global_position.y > ant.global_position.y + 4.0:
					begin_tell()
		State.TELL:
			fly(Vector3.ZERO, ACCEL * 1.5, delta, false)
			face(dive_to - global_position, delta)
			timer -= delta
			if timer <= 0.0:
				state = State.DIVE
				dive_dir = (dive_to - global_position).normalized()
				hit_done = false
				timer = 2.0
		State.DIVE:
			dive(delta)
		State.RECOVER:
			timer -= delta
			var off2 := recover_goal - global_position
			fly(off2.normalized() * 16.0, ACCEL * 2.0, delta, true)
			if timer <= 0.0 or off2.length() < 3.0:
				state = State.STALK
		State.CRASHED:
			crash_fall(delta)

	animate(delta)

# Hovers and marks where it is about to strike. It aims once, so you can step away.
func begin_tell() -> void:
	state = State.TELL
	timer = TELL_TIME
	dive_to = ant.global_position + ant.basis.y * 0.4
	set_ring(dive_to, DIVE_RADIUS + 0.4, true)

func dive(delta: float) -> void:
	timer -= delta
	set_ring(dive_to, DIVE_RADIUS + 0.4, true)
	vel = dive_dir * DIVE_SPEED
	var step := vel * delta
	var hit := cast(global_position, global_position + step + dive_dir * 0.8)
	if not hit.is_empty():
		var hp: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		if hp.distance_to(ant.global_position) < 3.5 or n.y > 0.5:
			global_position = hp + n * 0.5   # reached you, or the ground: the dive is over
			check_dive_hit()
			end_dive()
		else:
			crash()   # flew into a trunk or rock
		return
	global_position += step
	face(dive_dir, delta)
	check_dive_hit()
	if timer <= 0.0 or global_position.distance_to(dive_to) < 1.2:
		end_dive()

func check_dive_hit() -> void:
	if hit_done:
		return
	if global_position.distance_to(ant.global_position) < DIVE_RADIUS:
		hit_done = true
		ant.take_damage(DIVE_DAMAGE * damage_mult)
		ant.knock_up(4.0)

func end_dive() -> void:
	set_ring(dive_to, 1.0, false)
	state = State.RECOVER
	timer = RECOVER_TIME
	cd = randf_range(2.5, 4.5)
	var away := global_position - ant.global_position
	away.y = 0.0
	if away.length() < 0.5:
		away = Vector3(cos(circle), 0.0, sin(circle))
	recover_goal = ant.global_position + away.normalized() * 16.0 + Vector3.UP * (STALK_HEIGHT + 2.0)
	vel = Vector3.UP * 8.0

func crash() -> void:
	set_ring(dive_to, 1.0, false)
	state = State.CRASHED
	timer = CRASH_TIME
	vel = Vector3(0.0, -2.0, 0.0)
	cd = randf_range(2.5, 4.0)

func crash_fall(delta: float) -> void:
	var floor_y := ground_y(global_position) + 0.6
	if global_position.y > floor_y + 0.05:
		vel.y -= 35.0 * delta
		global_position.y = maxf(floor_y, global_position.y + vel.y * delta)
	else:
		vel = Vector3.ZERO   # lying on the ground, dazed
		timer -= delta
		if timer <= 0.0:
			state = State.RECOVER
			timer = RECOVER_TIME
			recover_goal = global_position + Vector3.UP * 12.0

# Smoothly speeds up toward a wanted velocity, slides around anything solid in the way, and
# never drops below the ground or leaves the world.
func fly(want: Vector3, accel: float, delta: float, avoid: bool) -> void:
	vel = vel.move_toward(want, accel * delta)
	if vel.length() < 0.01:
		return
	var step := vel * delta
	if avoid:
		var hit := cast(global_position, global_position + step + vel.normalized() * 2.0)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			vel = vel.slide(n)
			vel.y += 14.0 * delta   # lift over the obstacle
			step = vel * delta
	global_position += step
	var p := global_position
	p.x = clampf(p.x, -FIELD_LIMIT, FIELD_LIMIT)
	p.z = clampf(p.z, -FIELD_LIMIT, FIELD_LIMIT)
	p.y = maxf(p.y, ground_y(p) + 1.2)
	global_position = p
	if vel.length() > 1.5:
		face(vel, delta)

# Turns the nose toward a direction, smoothly.
func face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.1:
		return
	var flat := Vector2(dir.x, dir.z).length()
	if flat < 0.05:
		return   # straight up or down: keep the current heading
	var want := Basis.looking_at(dir.normalized(), Vector3.UP)
	var q := basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), minf(1.0, 9.0 * delta))
	basis = Basis(q)

func animate(_delta: float) -> void:
	var rate := 46.0
	var amp := 0.7
	match state:
		State.TELL:
			rate = 75.0   # a loud, fast buzz
			amp = 0.9
		State.DIVE:
			amp = 0.15    # wings pulled in
		State.CRASHED:
			amp = 0.0
	var flap := sin(time * rate) * amp
	for w in wings:
		(w["node"] as Node3D).rotation.z = flap * float(w["side"])
