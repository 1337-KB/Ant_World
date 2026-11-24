class_name Firefly
extends Creature

# A glowing insect that drifts around near its home and flees when an ant gets close.
# Killing one drops firefly glow, the material for building lights.

enum State { DRIFT, FLEE }

const WANDER_RADIUS := 14.0   # how far from home it drifts
const DRIFT_SPEED := 1.6
const FLEE_SPEED := 5.0
const FLEE_RANGE := 7.0       # an ant closer than this scares it
const CALM_RANGE := 11.0      # it settles again once the ant is this far away
const FIELD_LIMIT := 7000.0   # never leave the world (the world is about 14400 wide, centred on 0)

var state := State.DRIFT
var target := Vector3.ZERO
var wait := 0.0
var time := 0.0
var phase := 0.0
var flash := 0.0              # brief extra glow when hit
var glow_mat: StandardMaterial3D
var light: OmniLight3D
var wings: Array[MeshInstance3D] = []

func _ready() -> void:
	max_health = 30.0
	solid = false
	super()
	nocturnal = true
	phase = randf() * TAU
	build_model()
	pick_target()

func loot_kind() -> String:
	return "glow"

func on_hurt() -> void:
	flash = 1.0
	state = State.FLEE

func build_model() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.1, 0.08)
	dark.roughness = 0.7
	glow_mat = StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.9, 1.0, 0.4)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.7, 1.0, 0.2)
	glow_mat.emission_energy_multiplier = 2.0

	# Body: a small dark thorax and head, and a glowing abdomen behind them.
	add_blob(dark, Vector3(0.22, 0.18, 0.34), Vector3(0, 0, 0))
	add_blob(dark, Vector3(0.16, 0.14, 0.16), Vector3(0, 0.02, -0.28))
	add_blob(glow_mat, Vector3(0.26, 0.22, 0.4), Vector3(0, -0.02, 0.38))

	# Two thin wings that flap.
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.85, 0.9, 0.8, 0.5)
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.02, 0.22)
		wing.mesh = bm
		wing.material_override = wing_mat
		wing.position = Vector3(0.3 * side, 0.12, 0.05)
		add_child(wing)
		wings.append(wing)

	light = OmniLight3D.new()
	light.light_color = Color(0.8, 1.0, 0.3)
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0, 0.4)
	add_child(light)

func add_blob(mat: StandardMaterial3D, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.scale = size * 1.8
	mi.position = pos
	mi.material_override = mat
	add_child(mi)

func _physics_process(delta: float) -> void:
	if not active:
		return   # asleep for the day
	if is_loaded.is_valid() and not is_loaded.call(global_position):
		return   # the ground here is not built yet, so wait
	time += delta
	var dist := INF
	if ant != null:
		dist = (ant.global_position - global_position).length()

	match state:
		State.DRIFT:
			if dist < FLEE_RANGE:
				state = State.FLEE
			else:
				drift(delta)
		State.FLEE:
			if dist > CALM_RANGE:
				state = State.DRIFT
				pick_target()
			else:
				var away := (global_position - ant.global_position).normalized()
				away.y += 0.35
				move(away.normalized() * FLEE_SPEED * delta)

	animate(delta)

func drift(delta: float) -> void:
	if wait > 0.0:
		wait -= delta
		global_position.y += sin(time * 2.0 + phase) * 0.2 * delta   # hover and bob
		return
	var to_target := target - global_position
	if to_target.length() < 1.0:
		wait = randf_range(0.5, 2.0)
		pick_target()
		return
	move(to_target.normalized() * DRIFT_SPEED * delta)

func pick_target() -> void:
	var x := clampf(home.x + randf_range(-WANDER_RADIUS, WANDER_RADIUS), -FIELD_LIMIT, FIELD_LIMIT)
	var z := clampf(home.z + randf_range(-WANDER_RADIUS, WANDER_RADIUS), -FIELD_LIMIT, FIELD_LIMIT)
	var g := 40.0
	if ground_at.is_valid():
		g = ground_at.call(x, z)
	target = Vector3(x, g + randf_range(1.8, 6.0), z)

func move(step: Vector3) -> void:
	if step.length() < 0.0001:
		return
	look_at(global_position + step, Vector3.UP)

	# Solid things in the way (trunks, boulders, ground) stop it, and it slides along them.
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step + step.normalized() * 0.7)
	q.collision_mask = 1
	if ant != null:
		q.exclude = [ant.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		step = step.slide(n) + n * 0.02
		if state == State.DRIFT:
			wait = 0.0
			pick_target()   # find another way
	global_position += step
	# Stay above the ground and inside the world.
	var p := global_position
	p.x = clampf(p.x, -FIELD_LIMIT, FIELD_LIMIT)
	p.z = clampf(p.z, -FIELD_LIMIT, FIELD_LIMIT)
	if ground_at.is_valid():
		p.y = maxf(p.y, float(ground_at.call(p.x, p.z)) + 1.2)
	global_position = p

func animate(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 3.0)
	var pulse := 0.5 + 0.5 * sin(time * 3.0 + phase)
	glow_mat.emission_energy_multiplier = 1.0 + 2.0 * pulse + 3.0 * flash
	light.light_energy = 0.4 + 0.9 * pulse + flash
	var flap := sin(time * 40.0) * 0.6
	wings[0].rotation.z = flap
	wings[1].rotation.z = -flap
