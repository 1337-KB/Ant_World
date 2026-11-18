class_name Pickup
extends RigidBody3D

# "slow" is how much a FULL stack (50) of this resource slows the ant.
# Carrying a full stack of everything adds up to a 60% slowdown.
const KINDS := {
	"sugar":  {"label": "Sugar",      "color": Color(1.0, 0.85, 0.3),  "size": 0.25, "slow": 0.10},
	"pebble": {"label": "Pebbles",    "color": Color(0.55, 0.55, 0.6), "size": 0.35, "slow": 0.30},
	"fiber":  {"label": "Leaf fiber", "color": Color(0.35, 0.75, 0.3), "size": 0.30, "slow": 0.20},
}

var kind := "sugar"
var amount := 5            # how many units this pickup holds
var mesh_node: MeshInstance3D

func _ready() -> void:
	add_to_group("pickups")
	var info: Dictionary = KINDS[kind]
	var s: float = info["size"]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = info["color"]
	mat.roughness = 0.8

	mesh_node = MeshInstance3D.new()
	var col := CollisionShape3D.new()
	if kind == "fiber":
		var box := BoxMesh.new()
		box.size = Vector3(s * 2.4, s * 0.5, s * 1.6)
		mesh_node.mesh = box
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size
		col.shape = box_shape
	else:
		var sphere := SphereMesh.new()
		sphere.radius = s
		sphere.height = s * 2.0
		mesh_node.mesh = sphere
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = s
		col.shape = sphere_shape
	mesh_node.material_override = mat
	add_child(mesh_node)
	add_child(col)
	update_look()

	mass = 0.2
	# Layer 2 = pickups, layer 1 = terrain.
	collision_layer = 2
	collision_mask = 3

# Bigger piles look bigger.
func update_look() -> void:
	mesh_node.scale = Vector3.ONE * (0.7 + 0.06 * amount)

# Remove up to n units. Returns how many were actually taken.
func take(n: int) -> int:
	var got := mini(n, amount)
	if got <= 0:
		return 0
	amount -= got
	if amount <= 0:
		queue_free()
	else:
		update_look()
	return got

func _physics_process(_delta: float) -> void:
	if global_position.y < -20.0:
		global_position.y = 30.0
		linear_velocity = Vector3.ZERO
