class_name Ant
extends CharacterBody3D

const SPEED := 6.0
const JUMP_SPEED := 7.0
const GRAVITY := 20.0
const STICK_FORCE := 3.0
const TURN_RATE := 5.0        # was 10.0: slower swing onto new surfaces
const CAMERA_FOLLOW := 8.0    # how quickly the camera catches up (lower = floatier)
const SENSITIVITY := 0.002    # was 0.003: calmer mouse look

var pivot: Node3D           # camera pitch (up and down)
var rig: Node3D             # camera mount that follows the ant smoothly

signal deposit_requested

const CAPACITY := 50        # max of each resource type
const PICKUP_RANGE := 1.6   # how close you must be to absorb a pickup

var inventory := {"sugar": 0, "pebble": 0, "fiber": 0}

var camera: Camera3D
var attached := false       # true while stuck to a surface
var detach_timer := 0.0     # after a jump, ignore surfaces briefly

func _ready() -> void:
	# A sphere rotates cleanly around corners, unlike a long capsule.
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	shape.position = Vector3(0, 0.4, 0)
	add_child(shape)

	# Placeholder body so you can see which way the ant faces.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.08, 0.05)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.3
	body_mesh.height = 1.2
	body.mesh = body_mesh
	body.material_override = mat
	body.position = Vector3(0, 0.4, 0)
	body.rotation_degrees.x = 90  # lay the capsule along the Z axis
	add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.25
	head_mesh.height = 0.5
	head.mesh = head_mesh
	head.material_override = mat
	head.position = Vector3(0, 0.4, -0.65)
	add_child(head)

	rig = Node3D.new()
	rig.top_level = true   # ignore the ant's rotation; we steer it ourselves
	add_child(rig)

	pivot = Node3D.new()
	pivot.position = Vector3(0, 1.0, 0)
	rig.add_child(pivot)

	var arm := SpringArm3D.new()
	arm.spring_length = 5.0
	arm.margin = 0.3
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)

	camera = Camera3D.new()
	arm.add_child(camera)
	camera.make_current()

	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 0.5
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	# Position follows the ant exactly, but orientation eases toward the ant's.
	rig.global_position = global_position
	var target := global_transform.basis.orthonormalized()
	var current := rig.global_transform.basis.orthonormalized()
	rig.global_transform.basis = current.slerp(target, minf(1.0, CAMERA_FOLLOW * delta)).orthonormalized()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		deposit_requested.emit()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Turn around the ant's own up axis, not the world's.
		basis = basis.rotated(basis.y, -event.relative.x * SENSITIVITY).orthonormalized()
		pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * SENSITIVITY, -1.3, 0.8)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	detach_timer -= delta

	# Walk relative to where the ant is facing (always along its surface).
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_key_pressed(KEY_S): input.z += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	var dir := (basis * input).normalized()
	var speed: float = SPEED * (1.0 - load_slow())

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
		if Input.is_key_pressed(KEY_SPACE):
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
		global_position = Vector3(0, 25, 0)
		basis = Basis.IDENTITY
		velocity = Vector3.ZERO

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
	var total := 0.0
	for k in inventory:
		total += float(inventory[k]) / CAPACITY * float(Pickup.KINDS[k]["slow"])
	return total


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
	query.collision_mask = 1  # terrain only, so pickups never count as ground
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
