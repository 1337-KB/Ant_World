class_name Piece
extends StaticBody3D

# Everything about each buildable piece lives in this table.
# Costs are paid from the colony's stored resources.
const TYPES := {
	"pebble_wall": {
		"label": "Pebble wall", "size": Vector3(3.0, 2.0, 0.6),
		"color": Color(0.5, 0.5, 0.55), "cost": {"pebble": 8},
	},
	"fiber_floor": {
		"label": "Fiber floor", "size": Vector3(3.0, 0.3, 3.0),
		"color": Color(0.4, 0.65, 0.3), "cost": {"fiber": 6},
	},
	"pillar": {
		"label": "Mortared pillar", "size": Vector3(0.8, 3.0, 0.8),
		"color": Color(0.7, 0.6, 0.4), "cost": {"pebble": 5, "sugar": 3},
	},
}

var type := "pebble_wall"

func _ready() -> void:
	add_to_group("pieces")
	var info: Dictionary = TYPES[type]
	var size: Vector3 = info["size"]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = info["color"]
	mat.roughness = 0.9

	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.material_override = mat
	add_child(mesh_node)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	add_child(col)

	# Layers are bits: 1 = terrain-like surfaces, 2 = pickups, 4 = built pieces.
	# Pieces sit on layers 1 and 4, so the ant can climb them (it looks at layer 1)
	# and the build preview can tell them apart from terrain (it looks at layer 4).
	collision_layer = 5
	collision_mask = 0
