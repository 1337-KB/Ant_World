class_name RockShot
extends Node3D

# A rock thrown by a soldier ant. It flies in an arc and hurts the first creature it hits.
# Then it bounces, settles on the ground and stays there. A soldier can walk over it to pick it up again.

const GRAVITY := 22.0
const HIT_RADIUS := 2.0
const BOUNCE := 0.35         # how much speed is kept when it hits the ground
const FRICTION := 0.7        # sideways speed kept on each bounce
const REST_SPEED := 2.5      # slower than this and it stops
const REST_LIFE := 300.0     # a resting rock crumbles after this many seconds if nobody takes it
const PICKUP_DELAY := 0.5    # you cannot grab your own rock the instant you throw it

var world: World
var velocity := Vector3.ZERO
var damage := 40.0
var resting := false
var hit_something := false
var age := 0.0
var rest_time := 0.0
var check_timer := 0.0

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	sm.radial_segments = 10
	sm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.52)
	mat.roughness = 0.9
	sm.material = mat
	mi.mesh = sm
	mi.scale = Vector3(1.0, 0.85, 1.1)
	add_child(mi)

# True when it is resting and a soldier may take it.
func can_collect() -> bool:
	return resting and age > PICKUP_DELAY

func _surface_normal(p: Vector3) -> Vector3:
	var e := 0.4
	var n := Vector3(
		world.sample_density(p - Vector3(e, 0, 0)) - world.sample_density(p + Vector3(e, 0, 0)),
		world.sample_density(p - Vector3(0, e, 0)) - world.sample_density(p + Vector3(0, e, 0)),
		world.sample_density(p - Vector3(0, 0, e)) - world.sample_density(p + Vector3(0, 0, e)))
	if n.length() < 0.001:
		return Vector3.UP
	return n.normalized()

func _physics_process(delta: float) -> void:
	age += delta
	if resting:
		rest_time += delta
		if rest_time > REST_LIFE:
			queue_free()
			return
		# If the ground under it is dug away, it falls again.
		check_timer -= delta
		if check_timer <= 0.0:
			check_timer = 0.3
			if world != null and world.sample_density(global_position + Vector3(0, -0.3, 0)) <= 0.0:
				resting = false
				remove_from_group("rocks")
				velocity = Vector3.ZERO
		return

	var steps := 2
	var dt := delta / float(steps)
	for i in steps:
		velocity.y -= GRAVITY * dt
		var next := global_position + velocity * dt
		if not hit_something:
			for c in get_tree().get_nodes_in_group("creatures"):
				var cr := c as Creature
				if cr == null or not cr.active:
					continue
				var reach := HIT_RADIUS + (3.5 if cr is TermiteQueen else 0.0)
				if (cr.global_position + Vector3(0, 0.6, 0)).distance_to(next) < reach:
					cr.take_damage(damage)
					hit_something = true
					# It knocks off the target and drops.
					velocity = -velocity * 0.15 + Vector3(0, 3.0, 0)
					next = global_position + velocity * dt
					break
		if world != null and world.sample_density(next) > 0.0:
			var n := _surface_normal(next)
			var along := velocity.dot(n)
			if along < 0.0:
				velocity -= (1.0 + BOUNCE) * along * n
			var sideways := velocity - n * velocity.dot(n)
			velocity = n * velocity.dot(n) + sideways * FRICTION
			if velocity.length() < REST_SPEED:
				resting = true
				velocity = Vector3.ZERO
				rest_time = 0.0
				add_to_group("rocks")
				return
			continue   # stay where we were this step; we bounce next step
		global_position = next
	rotate_x(delta * 6.0)
