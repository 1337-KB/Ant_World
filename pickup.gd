class_name Pickup
extends RigidBody3D

# "slow" is how much a FULL stack (50) of this resource slows the ant.
const KINDS := {
	"sugar":  {"label": "Sugar",      "color": Color(1.0, 0.85, 0.3),  "size": 0.25, "slow": 0.10},
	"pebble": {"label": "Pebbles",    "color": Color(0.55, 0.55, 0.6), "size": 0.35, "slow": 0.30},
	"fiber":  {"label": "Leaf fiber", "color": Color(0.35, 0.75, 0.3), "size": 0.30, "slow": 0.20},
	"silk":   {"label": "Spider silk", "color": Color(0.92, 0.92, 0.96), "size": 0.25, "slow": 0.0},
	"glow":   {"label": "Firefly glow", "color": Color(0.85, 1.0, 0.3), "size": 0.22, "slow": 0.0},
}

signal depleted   # emitted when the last of it is taken

var kind := "sugar"
var home := Vector3.ZERO   # the spot it spawned at; it returns here if it ever falls out of the world
var amount := 5            # how many units this pickup holds
var visual: Node3D

func _ready() -> void:
	add_to_group("pickups")
	var info: Dictionary = KINDS[kind]
	var s: float = info["size"]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = info["color"]
	mat.roughness = 0.8

	visual = Node3D.new()
	add_child(visual)

	var col := CollisionShape3D.new()
	match kind:
		"sugar":
			# A cluster of glossy crystals.
			mat.roughness = 0.15
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.38, 0.05)
			for i in 4:
				var crystal := MeshInstance3D.new()
				var bm := BoxMesh.new()
				var cs := s * randf_range(0.7, 1.1)
				bm.size = Vector3(cs, cs * 1.4, cs)
				crystal.mesh = bm
				crystal.material_override = mat
				crystal.position = Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.4), randf_range(-0.6, 0.6)) * s
				crystal.rotation = Vector3(randf(), randf(), randf()) * TAU
				visual.add_child(crystal)
			var shape := SphereShape3D.new()
			shape.radius = s
			col.shape = shape
		"pebble":
			# A small heap of lumpy stones.
			for i in 3:
				var rock := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = s * (1.0 if i == 0 else 0.55)
				sm.height = sm.radius * 2.0
				sm.radial_segments = 7
				sm.rings = 4
				rock.mesh = sm
				rock.material_override = mat
				rock.scale = Vector3(1.0, randf_range(0.6, 0.85), randf_range(0.8, 1.0))
				rock.rotation = Vector3(randf(), randf(), randf()) * TAU
				if i > 0:
					rock.position = Vector3(randf_range(-0.9, 0.9), -0.1, randf_range(-0.9, 0.9)) * s
				visual.add_child(rock)
			var shape := SphereShape3D.new()
			shape.radius = s
			col.shape = shape
		"silk":
			# A loose white bundle of threads.
			mat.roughness = 0.9
			for i in 4:
				var thread := MeshInstance3D.new()
				var tm := SphereMesh.new()
				tm.radius = s
				tm.height = s * 2.0
				thread.mesh = tm
				thread.material_override = mat
				thread.scale = Vector3(0.25, 0.25, 1.4)
				thread.rotation = Vector3(randf(), randf(), randf()) * TAU
				visual.add_child(thread)
			var silk_shape := SphereShape3D.new()
			silk_shape.radius = s
			col.shape = silk_shape
		"glow":
			# A small glowing bead.
			mat.roughness = 0.2
			mat.emission_enabled = true
			mat.emission = Color(0.6, 0.9, 0.1)
			mat.emission_energy_multiplier = 2.0
			var bead := MeshInstance3D.new()
			var gm := SphereMesh.new()
			gm.radius = s
			gm.height = s * 2.0
			bead.mesh = gm
			bead.material_override = mat
			visual.add_child(bead)
			var gshape := SphereShape3D.new()
			gshape.radius = s
			col.shape = gshape
		_:
			# Leaf fiber: a few flat curled chips stacked together.
			for i in 3:
				var chip := MeshInstance3D.new()
				var cm := SphereMesh.new()
				cm.radius = s * 1.2
				cm.height = cm.radius * 2.0
				cm.radial_segments = 10
				cm.rings = 5
				chip.mesh = cm
				chip.material_override = mat
				chip.scale = Vector3(1.0, 0.12, 0.6)
				chip.position = Vector3(0, i * s * 0.18, 0)
				chip.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
				visual.add_child(chip)
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(s * 2.4, s * 0.5, s * 1.6)
			col.shape = box_shape
	add_child(col)
	update_look()

	mass = 0.2
	# Layer 2 = pickups, layer 1 = terrain.
	collision_layer = 2
	collision_mask = 3

# Bigger piles look bigger.
func update_look() -> void:
	visual.scale = Vector3.ONE * (0.7 + 0.06 * amount)

# Remove up to n units. Returns how many were actually taken.
func take(n: int) -> int:
	var got := mini(n, amount)
	if got <= 0:
		return 0
	amount -= got
	if amount <= 0:
		depleted.emit()
		queue_free()
	else:
		update_look()
	return got

func _physics_process(_delta: float) -> void:
	if global_position.y < -20.0:
		linear_velocity = Vector3.ZERO
		if home != Vector3.ZERO:
			global_position = home
			freeze = true
		else:
			global_position.y = 70.0
