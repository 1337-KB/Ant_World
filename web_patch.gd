class_name WebPatch
extends Node3D

# A patch of web lying on the ground, left by the Broodmother's web curtain. Walk into it and you
# are stuck for a couple of seconds. Jump over it, or go through a gap in the line. It rots away.

const RADIUS := 1.7
const LIFE := 9.0
const STUCK_SECONDS := 2.5

var ant: Ant
var age := 0.0

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RADIUS
	cm.bottom_radius = RADIUS
	cm.height = 0.08
	cm.radial_segments = 20
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.75, 0.9)
	mat.emission_energy_multiplier = 0.5
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
		if Vector2(off.x, off.z).length() < RADIUS and off.y < 0.9 and ant.webbed_time <= 0.0:
			ant.web_up(STUCK_SECONDS)
			queue_free()
