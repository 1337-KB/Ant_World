class_name PoisonShot
extends Node3D

# A glob of poison lobbed by the Elder Centipede. It arcs through the air to the spot where you were
# standing when it was spat, and leaves a puddle there. Move and it lands behind you.

const FLIGHT_TIME := 1.0
const ARC_HEIGHT := 4.0

var ant: Ant
var from := Vector3.ZERO
var to := Vector3.ZERO
var age := 0.0

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.95, 0.2, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 0.1)
	mat.emission_energy_multiplier = 1.2
	sm.material = mat
	mi.mesh = sm
	add_child(mi)
	global_position = from

func _physics_process(delta: float) -> void:
	age += delta
	var u := clampf(age / FLIGHT_TIME, 0.0, 1.0)
	var p := from.lerp(to, u)
	p.y += sin(u * PI) * ARC_HEIGHT
	global_position = p
	if u >= 1.0:
		var puddle := PoisonPuddle.new()
		puddle.ant = ant
		get_parent().add_child(puddle)
		puddle.global_position = to
		queue_free()
