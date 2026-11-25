class_name RockChunk
extends Node3D

# A chunk of rock spat by the Elder Tunnel Worm. It arcs to where you stood, hurts anything under it
# when it lands, then stays for a while as a solid boulder you can hide behind.

const FLIGHT_TIME := 1.0
const ARC_HEIGHT := 5.0
const HIT_RADIUS := 2.4
const DAMAGE := 12.0
const LIFE := 14.0
const SIZE := 1.1

var ant: Ant
var from := Vector3.ZERO
var to := Vector3.ZERO
var age := 0.0
var landed := false

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = SIZE
	sm.height = SIZE * 2.0
	sm.radial_segments = 8
	sm.rings = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.4, 0.37)
	mat.roughness = 0.95
	sm.material = mat
	mi.mesh = sm
	mi.scale = Vector3(1.0, 0.85, 1.1)
	add_child(mi)
	global_position = from

func _physics_process(delta: float) -> void:
	age += delta
	if landed:
		if age > LIFE:
			queue_free()
		return
	var u := clampf(age / FLIGHT_TIME, 0.0, 1.0)
	var p := from.lerp(to, u)
	p.y += sin(u * PI) * ARC_HEIGHT
	global_position = p
	rotation.x += delta * 6.0
	if u >= 1.0:
		land()

func land() -> void:
	landed = true
	rotation = Vector3.ZERO
	global_position = to + Vector3(0, SIZE * 0.6, 0)
	Effects.impact(get_parent(), to, 1.8)
	if is_instance_valid(ant):
		var off := ant.global_position - to
		if Vector2(off.x, off.z).length() < HIT_RADIUS and off.y < 2.0:
			ant.take_damage(DAMAGE)
	# Now it is solid.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = SIZE
	col.shape = shape
	body.add_child(col)
	add_child(body)
