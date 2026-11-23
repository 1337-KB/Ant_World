class_name Ant
extends CharacterBody3D

signal deposit_requested
signal died

const BODY_SCALE := 0.65     # overall ant size. Lower = smaller ant (1.0 was the old size)
const SPEED := 6.0
const JUMP_SPEED := 7.0
const GRAVITY := 20.0
const STICK_FORCE := 3.0     # constant push into the surface we're walking on
const TURN_RATE := 4.0       # how fast "up" swings to a new surface
const CAMERA_FOLLOW := 5.0   # how quickly the camera catches up (lower = floatier)
const CAMERA_HEIGHT := 2.4 * BODY_SCALE   # how high the camera sits above the ant
const CAMERA_DISTANCE := 6.5 * BODY_SCALE # how far behind the ant it sits
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
# Dash: press Ctrl. Moving forward (or standing still) dashes at what is ahead and hurts what you hit.
# Holding A, D or S dashes sideways or back instead, and you cannot be hurt for a moment.
const DASH_KEY := KEY_CTRL
const DASH_SPEED := 40.0        # the peak speed of a dash
const DASH_TIME := 0.24         # a dash covers about 7 units
const DASH_RAMP := 0.15         # the first part of the dash eases up to full speed...
const DASH_HOLD := 0.3          # ...stays at full speed until here, then eases back down to walking speed
const DASH_COOLDOWN := 1.0
const DASH_COST := 20.0         # energy
const DASH_DAMAGE := 20.0       # forward dash damage for a worker. Soldiers multiply it (dash_dmg)
const DASH_HIT_RADIUS := 2.2
const EVADE_TIME := 0.35        # invulnerable this long after a side or back dash
const ROCK_SLOW := 0.12        # slowdown when carrying a full load of rocks
const ROCK_CAP := 12          # soldiers can carry this many rocks
# Classes. You change class by pressing E next to your queen.
const ROLE_NAMES := ["Worker", "Soldier"]
const ROLES := [
	# Worker: quickest, carries a lot, normal acid spray.
	{"speed": 1.2, "health": 100.0, "spray_range": 1.0, "spray_dmg": 1.0, "carry": 1.6, "soil": 1.5, "water": 1.5, "pickup": 1.6, "dig_max": 3.5, "dash_dmg": 1.0},
	# Soldier: normal speed, tough, a powerful long acid spray, carries only soil and water.
	{"speed": 1.0, "health": 160.0, "spray_range": 2.6, "spray_dmg": 1.3, "carry": 0.0, "soil": 1.0, "water": 1.0, "pickup": 1.0, "dig_max": 2.5, "dash_dmg": 2.25},
]
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
var role := 0                  # 0 = worker, 1 = soldier
var max_health := MAX_HEALTH
var rocks := 0                 # soldiers make these from soil and throw them
var eat_cd := 0.0
var dash_time := 0.0           # time left in the current dash
var dash_cd := 0.0
var dash_vec := Vector3.ZERO
var dash_forward := false
var dash_hit: Array = []       # creatures already hit by this dash
var invuln := 0.0              # no damage while above zero
var dash_key_down := false
signal dashed(forward: bool)
signal dash_hit_creature(c: Node)
var body_mat: StandardMaterial3D
var soldier_parts: Node3D
var terrain_speed := 1.0       # set by the biome: cold and mud slow the ant
var sprint_cost_mult := 1.0    # set by the biome: heat drains sprint energy faster
var has_queen := false   # set by main every frame
var water_surface: Callable   # (position) -> water level there, or a very low number if not in water. Set by main.
var swimming := false
var acid := ACID_MAX          # fuel for the acid spray
var acid_locked := false      # true after running dry, until it refills a bit
var energy := ENERGY_MAX      # sprint energy
var exhausted := false       # true after running out, until energy recovers
var sprinting := false
var controls_locked := false   # true while a menu is open: no walking, jumping, or depositing
var inventory := {"sugar": 0, "pebble": 0, "fiber": 0, "glow": 0, "silk": 0, "resin": 0, "crystal": 0, "relic": 0}
var soil := 0.0              # filled by digging
var water := 0.0             # filled by drinking at pools
var poison_time := 0.0        # seconds of poison left. Eating sugar cures it.
var poison_dps := 0.0
var poison_tick := 0.0

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
	sphere.radius = 0.4 * BODY_SCALE
	shape.shape = sphere
	shape.position = Vector3(0, 0.4 * BODY_SCALE, 0)
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
	model.position = Vector3(0, 0.4 * BODY_SCALE, 0)
	model.scale = Vector3.ONE * BODY_SCALE
	add_child(model)

	var mat := StandardMaterial3D.new()
	body_mat = mat
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

	# Soldier gear: a big armored head and long jaws. Hidden for workers.
	soldier_parts = Node3D.new()
	soldier_parts.visible = false
	model.add_child(soldier_parts)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.5, 0.1, 0.05)
	head_mat.roughness = 0.35
	head_mat.metallic = 0.2
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.27
	hm.height = 0.54
	hm.radial_segments = 16
	hm.rings = 8
	head.mesh = hm
	head.material_override = head_mat
	head.scale = Vector3(1.25, 1.0, 1.15)
	head.position = Vector3(0, 0.03, -0.52)
	soldier_parts.add_child(head)
	for s2 in [-1.0, 1.0]:
		var jaw_pivot := Node3D.new()
		jaw_pivot.position = Vector3(s2 * 0.14, -0.04, -0.7)
		jaw_pivot.rotation.y = -s2 * 0.4
		var jaw := MeshInstance3D.new()
		var jm := CylinderMesh.new()
		jm.top_radius = 0.012
		jm.bottom_radius = 0.04
		jm.height = 0.4
		jaw.mesh = jm
		jaw.material_override = mat
		jaw.rotation.x = PI / 2.0
		jaw.position = Vector3(0, 0, -0.18)
		jaw_pivot.add_child(jaw)
		soldier_parts.add_child(jaw_pivot)

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
		var frac := clampf(float(total) / maxf(1.0, carry_cap("sugar") * inventory.size()), 0.0, 1.0)
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
	var regen_cap := REGEN_CAP * max_health / MAX_HEALTH
	if has_queen and health < regen_cap:
		health = minf(regen_cap, health + HEALTH_REGEN * delta)
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
	eat_cd -= delta
	dash_cd -= delta
	invuln -= delta

	# Poison: a pulse of damage every second until it wears off.
	if poison_time > 0.0:
		poison_time -= delta
		poison_tick -= delta
		if poison_tick <= 0.0:
			poison_tick = 1.0
			take_damage(poison_dps)

	# Walk relative to where the ant is facing (always along its surface).
	var input := Vector3.ZERO
	if not controls_locked:
		if Input.is_key_pressed(KEY_W): input.z -= 1.0
		if Input.is_key_pressed(KEY_S): input.z += 1.0
	if not A_D_TURNS and not controls_locked:
		if Input.is_key_pressed(KEY_A): input.x -= 1.0
		if Input.is_key_pressed(KEY_D): input.x += 1.0
	var dir := (basis * input).normalized()

	var speed: float = SPEED * stat("speed") * (1.0 - load_slow()) * terrain_speed

	# Water: wading slows you down, and once your body is under the surface you swim.
	var surf := -INF
	if water_surface.is_valid():
		surf = water_surface.call(global_position)
	var wet: bool = surf > -1.0e8
	var depth: float = surf - (global_position.y + 0.4 * BODY_SCALE)    # how far under the surface the body's middle is
	swimming = wet and depth > 0.0
	if wet and not swimming:
		speed *= WADE_SLOW

	# Sprint: hold Shift while moving. Energy drains, and when it runs out you walk
	# until it refills past RECOVER_AT.
	sprinting = false
	if not controls_locked and not swimming and Input.is_key_pressed(KEY_SHIFT) and input.length() > 0.0 and not exhausted:
		sprinting = true
		speed *= SPRINT_MULT
		energy = maxf(0.0, energy - SPRINT_DRAIN * sprint_cost_mult * delta)
		if energy <= 0.0:
			exhausted = true
	else:
		energy = minf(ENERGY_MAX, energy + ENERGY_REGEN * delta)
		if exhausted and energy >= RECOVER_AT:
			exhausted = false

	# Dash
	var key_now := not controls_locked and Input.is_key_pressed(DASH_KEY)
	if key_now and not dash_key_down and not swimming and attached and dash_cd <= 0.0 and dash_time <= 0.0 and energy >= DASH_COST:
		start_dash()
	dash_key_down = key_now
	if dash_time > 0.0:
		dash_time -= delta
		dir = dash_vec
		# Eased: speeds up smoothly, then slows smoothly into your walking speed, so it never starts or stops with a jolt.
		var p := clampf(1.0 - dash_time / DASH_TIME, 0.0, 1.0)
		var burst := smoothstep(0.0, DASH_RAMP, p) * (1.0 - smoothstep(DASH_HOLD, 1.0, p))
		speed = lerpf(speed, DASH_SPEED, burst)
		if dash_forward:
			dash_strike()

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

	if global_position.y < -120.0:
		respawn()

func start_dash() -> void:
	var left := Input.is_key_pressed(KEY_A)
	var right := Input.is_key_pressed(KEY_D)
	var back := Input.is_key_pressed(KEY_S)
	dash_forward = true
	dash_vec = -basis.z
	if left and not right:
		dash_vec = -basis.x
		dash_forward = false
	elif right and not left:
		dash_vec = basis.x
		dash_forward = false
	elif back:
		dash_vec = basis.z
		dash_forward = false
	dash_vec = dash_vec.normalized()
	dash_time = DASH_TIME
	dash_cd = DASH_COOLDOWN
	energy -= DASH_COST
	dash_hit.clear()
	if not dash_forward:
		invuln = EVADE_TIME
	dashed.emit(dash_forward)

# During a forward dash, hurt each creature the ant runs into, once.
func dash_strike() -> void:
	var center := global_position + basis.y * 0.4 * BODY_SCALE + dash_vec * 0.9
	var dmg := DASH_DAMAGE * stat("dash_dmg")
	for node in get_tree().get_nodes_in_group("creatures"):
		var c := node as Creature
		if c == null or not c.active or dash_hit.has(c):
			continue
		if (c.hit_center() + Vector3(0, 0.5, 0)).distance_to(center) < DASH_HIT_RADIUS + c.hit_radius:
			dash_hit.append(c)
			c.take_damage(dmg)
			dash_hit_creature.emit(c)

# Returns the normal of the surface we should stick to, or null.
func find_surface(dir: Vector3) -> Variant:
	var up := basis.y
	var center := global_position + up * 0.4 * BODY_SCALE

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
	var center := global_position + basis.y * 0.4 * BODY_SCALE
	var reach := PICKUP_RANGE * stat("pickup")
	# Soldiers can take their thrown rocks back.
	if role == 1 and rocks < ROCK_CAP:
		for node in get_tree().get_nodes_in_group("rocks"):
			var r := node as RockShot
			if r != null and r.can_collect() and r.global_position.distance_to(center) <= reach + 1.0:
				rocks += 1
				r.queue_free()
				if rocks >= ROCK_CAP:
					break
	for node in get_tree().get_nodes_in_group("pickups"):
		var p := node as Pickup
		if p.amount <= 0 or p.global_position.distance_to(center) > reach:
			continue
		var cap := int(carry_cap(p.kind))
		if cap <= 0:
			# This class cannot carry it. A soldier eats sugar on the spot instead.
			if p.kind == "sugar" and eat_cd <= 0.0 and (health < max_health or poison_time > 0.0):
				if p.take(1) > 0:
					eat_cd = 0.3
					health = minf(max_health, health + SUGAR_HEAL)
					poison_time = 0.0
					poison_dps = 0.0
			continue
		var have: int = inventory[p.kind]
		var space := cap - have
		if space <= 0:
			continue
		inventory[p.kind] = have + p.take(space)

# ---------- Classes ----------

func stat(key: String) -> float:
	return float((ROLES[role] as Dictionary)[key])

func soil_cap() -> float:
	return SOIL_CAPACITY * stat("soil")

func water_cap() -> float:
	return WATER_CAPACITY * stat("water")

# Switches class. Anything the new class cannot carry is returned, so the caller can drop it.
func set_role(new_role: int) -> Dictionary:
	var fraction := clampf(health / max_health, 0.0, 1.0)
	role = new_role
	max_health = stat("health")
	health = fraction * max_health   # you keep the same fraction of health
	var overflow := {}
	if role != 1 and rocks > 0:
		inventory["pebble"] = int(inventory["pebble"]) + rocks   # rocks crumble into pebbles
		rocks = 0
	for k in inventory:
		var cap := int(carry_cap(k))
		var have := int(inventory[k])
		if have > cap:
			overflow[k] = have - cap
			inventory[k] = cap
	soil = minf(soil, soil_cap())
	water = minf(water, water_cap())
	apply_role_look()
	return overflow

func apply_role_look() -> void:
	var soldier := role == 1
	body_mat.albedo_color = Color(0.32, 0.07, 0.04) if soldier else Color(0.16, 0.07, 0.04)
	soldier_parts.visible = soldier
	model.scale = Vector3.ONE * BODY_SCALE * (1.18 if soldier else 1.0)

# Total slowdown from everything you're carrying.
func load_slow() -> float:
	if not LOAD_SLOWS_ANT:
		return 0.0
	var total := 0.0
	for k in inventory:
		total += float(inventory[k]) / float(CAPACITY) * float(Pickup.KINDS[k]["slow"])
	total += soil / soil_cap() * SOIL_SLOW
	total += water / water_cap() * WATER_SLOW
	total += float(rocks) / float(ROCK_CAP) * ROCK_SLOW
	return total

func take_damage(amount: float) -> void:
	if invuln > 0.0:
		return   # dodging
	health -= amount
	if health <= 0.0:
		died.emit()
		respawn()

func apply_poison(seconds: float, dps: float) -> void:
	poison_time = maxf(poison_time, seconds)
	poison_dps = maxf(poison_dps, dps)

# Eat one sugar from what you carry. Returns true if it worked.
func eat_sugar() -> bool:
	if int(inventory["sugar"]) <= 0 or health >= max_health:
		return false
	inventory["sugar"] = int(inventory["sugar"]) - 1
	health = minf(max_health, health + SUGAR_HEAL)
	poison_time = 0.0   # sugar cures poison
	poison_dps = 0.0
	return true

func respawn() -> void:
	health = (REGEN_CAP if has_queen else NO_QUEEN_RESPAWN_HEALTH) * max_health / MAX_HEALTH
	poison_time = 0.0
	poison_dps = 0.0
	global_position = spawn_point
	basis = Basis.IDENTITY
	velocity = Vector3.ZERO

# How much of a kind of thing you carry: sugar, pebble, fiber, soil, or water.
func carried(kind: String) -> float:
	match kind:
		"soil": return soil
		"water": return water
		"rock": return float(rocks)
	return float(inventory[kind])

func carry_cap(kind: String) -> float:
	match kind:
		"soil": return soil_cap()
		"water": return water_cap()
		"rock": return float(ROCK_CAP) if role == 1 else 0.0
	return float(CAPACITY) * stat("carry")

func set_carried(kind: String, value: float) -> void:
	match kind:
		"soil": soil = value
		"water": water = value
		"rock": rocks = int(value)
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
	if global_position.y < -120.0:
		respawn()
