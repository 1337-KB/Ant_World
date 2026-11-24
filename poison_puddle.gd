class_name PoisonPuddle
extends Node3D

# A puddle of poison on the ground. Standing in it hurts every second. It dries up after a while.
# Jumping does not help: get out of it.

const RADIUS := 2.8
const LIFE := 6.0
const DPS := 7.0

var ant: Ant
var age := 0.0

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RADIUS
	cm.bottom_radius = RADIUS
	cm.height = 0.1
	cm.radial_segments = 24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 0.15, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.7, 0.1)
	mat.emission_energy_multiplier = 0.6
	cm.material = mat
	mi.mesh = cm
	mi.position.y = 0.1
	add_child(mi)

func _physics_process(delta: float) -> void:
	age += delta
	if age > LIFE:
		queue_free()
		return
	if is_instance_valid(ant):
		var off := ant.global_position - global_position
		if Vector2(off.x, off.z).length() < RADIUS and absf(off.y) < 1.5:
			ant.take_damage(DPS * delta)
