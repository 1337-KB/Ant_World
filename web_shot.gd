class_name WebShot
extends Node3D

# A glob of web spat by the Broodmother Spider. It flies straight at where you were standing when
# it was fired, so moving sideways or dashing dodges it. If it hits you, you are stuck in place
# for a few seconds (you can still look around, spray and throw things, but not walk).

const SPEED := 17.0
const LIFE := 3.5
const HIT_RADIUS := 1.4
const STUCK_SECONDS := 5.0

var ant: Ant
var velocity := Vector3.ZERO
var age := 0.0

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	sm.radial_segments = 12
	sm.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.8
	sm.material = mat
	mi.mesh = sm
	add_child(mi)

func _physics_process(delta: float) -> void:
	age += delta
	if age > LIFE:
		queue_free()
		return
	var step := velocity * delta
	# Solid ground, rocks and trunks stop it.
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	q.collision_mask = 1
	if ant != null:
		q.exclude = [ant.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		queue_free()
		return
	global_position += step
	if is_instance_valid(ant):
		var target := ant.global_position + ant.basis.y * 0.4
		if global_position.distance_to(target) < HIT_RADIUS:
			ant.web_up(STUCK_SECONDS)
			queue_free()
