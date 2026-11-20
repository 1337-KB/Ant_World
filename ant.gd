class_name Ant
extends CharacterBody3D

signal deposit_requested
signal died

const SPEED := 6.0
const JUMP_SPEED := 7.0
const GRAVITY := 20.0
const STICK_FORCE := 3.0     # constant push into the surface we're walking on
const TURN_RATE := 4.0       # how fast "up" swings to a new surface
const CAMERA_FOLLOW := 5.0   # how quickly the camera catches up (lower = floatier)
const CAMERA_HEIGHT := 2.4   # how high the camera sits above the ant
const CAMERA_DISTANCE := 6.5 # how far behind the ant it sits
const SENSITIVITY := 0.0015  # mouse look speed
const MOUSE_SMOOTH := 12.0   # how fast mouse movement is applied (lower = softer)
const A_D_TURNS := true      # true: A and D steer the ant. false: they strafe sideways.
const KEY_TURN_SPEED := 1.6  # radians per second when steering with A and D
const CAPACITY := 50         # max of each resource type
const PICKUP_RANGE := 1.6    # how close you must be to absorb a pickup
const SOIL_CAPACITY := 150.0 # how much soil you can carry
const WATER_CAPACITY := 100.0 # how much water you can carry
const SOIL_SLOW := 0.25      # slowdown at a full soil load
const WATER_SLOW := 0.15     # slowdown at a full water load
const LOAD_SLOWS_ANT := false # false: carrying things never slows you down
const SHOW_LOAD := false       # false: no bulge on the ant's back when carrying resources
const MAX_HEALTH := 100.0
const WADE_SLOW := 0.6       # walking speed in water, as a fraction of normal
const SWIM_SPEED := 3.6      # swimming speed
const FLOAT_DEPTH := 0.35    # how far under the surface the body rests when you just float
const ACID_MAX := 100.0
const HEALTH_REGEN := 0.5    # health gained per second, but only while the colony has a queen
const REGEN_CAP := 60.0      # the queen only heals you up to here. Above it you must eat sugar.
const SUGAR_HEAL := 15.0     # health from eating one sugar (press T)
const NO_QUEEN_RESPAWN_HEALTH := 30.0
const SPRINT_MULT := 1.7     # sprint speed compared with walking
const ENERGY_MAX := 100.0
const SPRINT_DRAIN := 25.0   # energy used per second while sprinting (4 seconds from full)
const ENERGY_REGEN := 12.0   # energy gained per second when not sprinting
const RECOVER_AT := 35.0     # after running out, you cannot sprint until energy reaches this

var rig: Node3D              # camera mount that follows the ant smoothly
var pivot: Node3D            # camera pitch (up and down)
var camera: Camera3D
var attached := false        # true while stuck to a surface
var detach_timer := 0.0      # after a jump, ignore surfaces briefly
var look_yaw := 0.0          # mouse turning waiting to be applied
var look_pitch := 0.0        # mouse tilting waiting to be applied
var key_turn := 0.0          # current A/D turning speed
var spawn_point := Vector3(0, 70, 0)   # where you respawn (the queen, once placed)
var health := MAX_HEALTH
var has_queen := false   # set by main every frame
var water_surface: Callable   # (position) -> water level there, or a very low number if not in water. Set by main.
var swimming := false
var acid := ACID_MAX          # fuel for the acid spray
var acid_locked := false      # true after running dry, until it refills a bit
var energy := ENERGY_MAX      # sprint energy
var exhausted := false       # true after running out, until energy recovers
var sprinting := false
var controls_locked := false   # true while a menu is open: no walking, jumping, or depositing
var inventory := {"sugar": 0, "pebble": 0, "fiber": 0, "glow": 0, "silk": 0, "resin": 0}
var soil := 0.0              # filled by digging
var water := 0.0             # filled by drinking at pools

# Visual model
var model: Node3D
var legs := []               # each entry: {"node": Node3D, "phase": float}
var walk_phase := 0.0
var load_bulge: MeshInstance3D
var load_mat: StandardMaterial3D

func _ready() -> void:
	# A sphere rotates cleanly around corners, unlike a long capsule.
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	shape.position = Vector3(0, 0.4, 0)
	add_child(shape)

	build_model()

	# Camera rig: ignores the ant's rotation, and eases toward it each frame.
	rig = Node3D.new()
	rig.top_level = true
	add_child(rig)

	pivot = Node3D.new()
	pivot.position = Vector3(0, CAMERA_HEIGHT, 0)
	pivot.rotation.x = -0.3  # start looking slightly down
	rig.add_child(pivot)

	# Spring arm so the camera never goes inside terrain.
	var arm := SpringArm3D.new()
	arm.spring_length = CAMERA_DISTANCE
	arm.margin = 0.3
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)

	camera = Camera3D.new()
	arm.add_child(camera)
	camera.make_current()

	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 0.5
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------- Model ----------

func build_model() -> void:
	model = Node3D.new()
	model.position = Vector3(0, 0.4, 0)
	add_child(model)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.07, 0.04)
	mat.roughness = 0.4
	mat.metallic = 0.1

	# Thorax, head, abdomen. The ant faces -Z.
	_blob(mat, 0.22, Vector3(1.0, 1.0, 1.3), Vector3(0, 0, 0))
	_blob(mat, 0.20, Vector3(1.0, 0.9, 1.0), Vector3(0, 0.02, -0.5))
	_blob(mat, 0.32, Vector3(1.0, 0.95, 1.35), Vector3(0, 0, 0.62))

	# Six legs: 0 right-front, 1 left-front, 2 right-mid, 3 left-mid, 4 right-hind, 5 left-hind.
	for i in 6:
		var side := 1.0 if i % 2 == 0 else -1.0
		var row := floori(i / 2.0)
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.1, -0.06, -0.18 + row * 0.18)
		leg.rotation.z = side * 0.9
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.022
		cyl.bottom_radius = 0.012
		cyl.height = 0.6
		seg.mesh = cyl
		seg.material_override = mat
		seg.position = Vector3(0, -0.3, 0)
		leg.add_child(seg)
		model.add_child(leg)
		# Tripod gait: three legs swing together while the other three swing opposite.
		var phase := 0.0 if (i == 0 or i == 3 or i == 4) else PI
		legs.append({"node": leg, "phase": phase})

	# Two antennae.
	for s in [-1.0, 1.0]:
		var ant_pivot := Node3D.new()
		ant_pivot.position = Vector3(s * 0.07, 0.1, -0.64)
		ant_pivot.rotation = Vector3(-1.1, 0.0, -s * 0.35)
		var stalk := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.008
		sc.bottom_radius = 0.014
		sc.height = 0.5
		stalk.mesh = sc
		stalk.material_override = mat
		stalk.position = Vector3(0, 0.25, 0)
		ant_pivot.add_child(stalk)
		model.add_child(ant_pivot)

	# The load carried on the abdomen. Grows with how full your inventory is.
	load_mat = StandardMaterial3D.new()
	load_mat.roughness = 0.6
	load_bulge = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.3
	lm.height = 0.6
	lm.radial_segments = 12
	lm.rings = 6
	load_bulge.mesh = lm
	load_bulge.material_override = load_mat
	load_bulge.position = Vector3(0, 0.27, 0.62)
	load_bulge.visible = false
	model.add_child(load_bulge)

func _blob(mat: StandardMaterial3D, radius: float, squash: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	mi.mesh = m
	mi.material_override = mat
	mi.scale = squash
	mi.position = pos
	model.add_child(mi)

func update_model(delta: float) -> void:
	# Legs swing faster the faster the ant moves.
	var moving := clampf(velocity.length() / SPEED, 0.0, 1.0)
	if not attached:
		moving = 0.15
	walk_phase += delta * 14.0 * moving
	for leg in legs:
		var node: Node3D = leg["node"]
		node.rotation.x = sin(walk_phase + float(leg["phase"])) * 0.5 * moving

	# Show the load, sized by how full the inventory is, tinted by the main resource.
	var total := 0
	var best_kind := ""
	var best_count := 0
	for k in inventory:
		total += inventory[k]
		if inventory[k] > best_count:
			best_count = inventory[k]
			best_kind = k
	load_bulge.visible = SHOW_LOAD and total > 0
	if SHOW_LOAD and total > 0:
		var frac := float(total) / float(CAPACITY * inventory.size())
		load_bulge.scale = Vector3.ONE * (0.4 + 1.3 * pow(frac, 0.7))
		load_mat.albedo_color = Pickup.KINDS[best_kind]["color"]

# ---------- Input and per-frame ----------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Queue the movement; _process applies it smoothly.
		look_yaw -= event.relative.x * SENSITIVITY
		look_pitch -= event.relative.y * SENSITIVITY
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and not controls_locked:
		deposit_requested.emit()

func _process(delta: float) -> void:
	if has_queen and health < REGEN_CAP:
		health = minf(REGEN_CAP, health + HEALTH_REGEN * delta)
	# Apply a fraction of the queued mouse movement each frame, so looking is soft.
	var k := minf(1.0, MOUSE_SMOOTH * delta)
	var step_yaw := look_yaw * k
	var step_pitch := look_pitch * k
	look_yaw -= step_yaw
	look_pitch -= step_pitch
	basis = basis.rotated(basis.y, step_yaw).orthonormalized()
	pivot.rotation.x = clampf(pivot.rotation.x + step_pitch, -1.3, 0.8)

	# A and D steer the ant, easing in and out. Left = positive turn.
	var turn_target := 0.0
	if A_D_TURNS and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not controls_locked:
		if Input.is_key_pressed(KEY_A): turn_target += 1.0
		if Input.is_key_pressed(KEY_D): turn_target -= 1.0
	key_turn = lerpf(key_turn, turn_target * KEY_TURN_SPEED, minf(1.0, 6.0 * delta))
	# A and D turn the whole ant, and the camera swings round with it.
	basis = basis.rotated(basis.y, key_turn * delta).orthonormalized()

	# Camera position follows the ant exactly, but orientation eases toward the ant's.
	rig.global_position = global_position
	var target := global_transform.basis.orthonormalized()
	var current := rig.global_transform.basis.orthonormalized()
	rig.global_transform.basis = current.slerp(target, minf(1.0, CAMERA_FOLLOW * delta)).orthonormalized()
	update_model(delta)

func _physics_process(delta: float) -> void:
	detach_timer -= delta

	# Walk relative to where the ant is facing (always along its surface).
	var input := Vector3.ZERO
	if not controls_locked:
		if Input.is_key_pressed(KEY_W): input.z -= 1.0
		if Input.is_key_pressed(KEY_S): input.z += 1.0
	if not A_D_TURNS and not controls_locked:
		if Input.is_key_pressed(KEY_A): input.x -= 1.0
		if Input.is_key_pressed(KEY_D): input.x += 1.0
	var dir := (basis * input).normalized()

	var speed: float = SPEED * (1.0 - load_slow())

	# Water: wading slows you down, and once your body is under the surface you swim.
	var surf := -INF
	if water_surface.is_valid():
		surf = water_surface.call(global_position)
	var wet: bool = surf > -1.0e8
	var depth: float = surf - (global_position.y + 0.4)    # how far under the surface the body's middle is
	swimming = wet and depth > 0.0
	if wet and not swimming:
		speed *= WADE_SLOW

	# Sprint: hold Shift while moving. Energy drains, and when it runs out you walk
	# until it refills past RECOVER_AT.
	sprinting = false
	if not controls_locked and not swimming and Input.is_key_pressed(KEY_SHIFT) and input.length() > 0.0 and not exhausted:
		sprinting = true
		speed *= SPRINT_MULT
		energy = maxf(0.0, energy - SPRINT_DRAIN * delta)
		if energy <= 0.0:
			exhausted = true
	else:
		energy = minf(ENERGY_MAX, energy + ENERGY_REGEN * delta)
		if exhausted and energy >= RECOVER_AT:
			exhausted = false

	if swimming:
		swim(delta, depth)
		return

	# 1. Find a surface to stick to. No surface means we're falling.
	var target_up := Vector3.UP
	attached = false
	if detach_timer <= 0.0:
		var n = find_surface(dir)
		if n != null:
			attached = true
			target_up = n

	# 2. Swing our up direction toward the surface normal.
	rotate_up_toward(target_up, minf(1.0, TURN_RATE * delta))
	up_direction = basis.y

	# 3. Move.
	if attached:
		velocity = dir * speed - basis.y * STICK_FORCE
		if Input.is_key_pressed(KEY_SPACE) and not controls_locked:
			velocity = dir * speed + basis.y * JUMP_SPEED
			detach_timer = 0.25
	else:
		velocity.y -= GRAVITY * delta
		# Limited steering in the air.
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		flat = flat.lerp(Vector3(dir.x, 0.0, dir.z) * speed, 4.0 * delta)
		velocity.x = flat.x
		velocity.z = flat.z

	move_and_slide()
	collect_nearby()

	if global_position.y < -20.0:
		respawn()

# Returns the normal of the surface we should stick to, or null.
func find_surface(dir: Vector3) -> Variant:
	var up := basis.y
	var center := global_position + up * 0.4

	# A: a wall straight ahead (inside corner). Climb onto it.
	if dir.length() > 0.1:
		var wall := cast_ray(center, center + dir * 0.9)
		if not wall.is_empty():
			return wall["normal"]

	# B: ground directly beneath us.
	var ground := cast_ray(center, center - up * 1.0)
	if not ground.is_empty():
		return ground["normal"]

	# C: the ground just ended (outside corner). Look back at the edge's face
	# from ahead and below, so we can wrap around it.
	if dir.length() > 0.1:
		var origin := center + dir * 0.9 - up * 0.9
		var edge := cast_ray(origin, origin - dir * 1.0)
		if not edge.is_empty():
			return edge["normal"]

	return null

func cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1  # terrain and built pieces only, never pickups
	query.hit_back_faces = false
	return get_world_3d().direct_space_state.intersect_ray(query)

# Rotate the whole body by the shortest turn that moves our up toward target.
func rotate_up_toward(target: Vector3, t: float) -> void:
	var cur := basis.y
	var d := cur.dot(target)
	if d > 0.9999:
		return
	if d < -0.999:
		target = basis.x  # exactly upside down: pass through sideways
	var next := cur.slerp(target.normalized(), t).normalized()
	basis = (Basis(Quaternion(cur, next)) * basis).orthonormalized()

# Absorb any pickup within reach, up to the capacity for its type.
func collect_nearby() -> void:
	var center := global_position + basis.y * 0.4
	for node in get_tree().get_nodes_in_group("pickups"):
		var p := node as Pickup
		if p.amount <= 0 or p.global_position.distance_to(center) > PICKUP_RANGE:
			continue
		var have: int = inventory[p.kind]
		var space := CAPACITY - have
		if space <= 0:
			continue
		inventory[p.kind] = have + p.take(space)

# Total slowdown from everything you're carrying.
func load_slow() -> float:
	if not LOAD_SLOWS_ANT:
		return 0.0
	var total := 0.0
	for k in inventory:
		total += float(inventory[k]) / CAPACITY * float(Pickup.KINDS[k]["slow"])
	total += soil / SOIL_CAPACITY * SOIL_SLOW
	total += water / WATER_CAPACITY * WATER_SLOW
	return total

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		died.emit()
		respawn()

# Eat one sugar from what you carry. Returns true if it worked.
func eat_sugar() -> bool:
	if int(inventory["sugar"]) <= 0 or health >= MAX_HEALTH:
		return false
	inventory["sugar"] = int(inventory["sugar"]) - 1
	health = minf(MAX_HEALTH, health + SUGAR_HEAL)
	return true

func respawn() -> void:
	health = REGEN_CAP if has_queen else NO_QUEEN_RESPAWN_HEALTH
	global_position = spawn_point
	basis = Basis.IDENTITY
	velocity = Vector3.ZERO

# How much of a kind of thing you carry: sugar, pebble, fiber, soil, or water.
func carried(kind: String) -> float:
	match kind:
		"soil": return soil
		"water": return water
	return float(inventory[kind])

func carry_cap(kind: String) -> float:
	match kind:
		"soil": return SOIL_CAPACITY
		"water": return WATER_CAPACITY
	return float(CAPACITY)

func set_carried(kind: String, value: float) -> void:
	match kind:
		"soil": soil = value
		"water": water = value
		_: inventory[kind] = int(value)

# Swimming: W and S go where the camera looks (look down to dive), Space rises, Ctrl sinks.
# With no input you float gently up to the surface.
func swim(delta: float, depth: float) -> void:
	attached = false
	rotate_up_toward(Vector3.UP, minf(1.0, 3.0 * delta))   # right yourself
	up_direction = basis.y

	var look := -camera.global_transform.basis.z
	var move := Vector3.ZERO
	var vertical := 0.0
	if not controls_locked:
		if Input.is_key_pressed(KEY_W): move += look
		if Input.is_key_pressed(KEY_S): move -= look
		if Input.is_key_pressed(KEY_SPACE): vertical += 1.0
		if Input.is_key_pressed(KEY_CTRL): vertical -= 1.0

	var target := Vector3.ZERO
	if move.length() > 0.0:
		target = move.normalized() * SWIM_SPEED
	target.y += vertical * SWIM_SPEED * 0.7
	if move.length() == 0.0 and vertical == 0.0:
		target.y = clampf((depth - FLOAT_DEPTH) * 1.5, -1.5, 2.0)   # drift up to the surface

	velocity = velocity.lerp(target, minf(1.0, 5.0 * delta))
	move_and_slide()
	collect_nearby()
	if global_position.y < -20.0:
		respawn()
