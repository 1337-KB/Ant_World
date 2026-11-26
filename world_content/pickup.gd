class_name Pickup
extends RigidBody3D

# "slow" is how much a FULL stack (50) of this resource slows the ant.
const KINDS := {
	"sugar":  {"label": "Sugar",      "color": Color(1.0, 0.85, 0.3),  "size": 0.25, "slow": 0.10},
	"pebble": {"label": "Pebbles",    "color": Color(0.55, 0.55, 0.6), "size": 0.35, "slow": 0.30},
	"fiber":  {"label": "Leaf fiber", "color": Color(0.35, 0.75, 0.3), "size": 0.30, "slow": 0.20},
	"silk":   {"label": "Spider silk", "color": Color(0.92, 0.92, 0.96), "size": 0.25, "slow": 0.0},
	"resin":  {"label": "Resin", "color": Color(0.95, 0.6, 0.12), "size": 0.26, "slow": 0.0},
	"crystal": {"label": "Cave crystal", "color": Color(0.55, 0.5, 1.0), "size": 0.3, "slow": 0.15},
	"relic": {"label": "Biome relic", "color": Color(1.0, 0.88, 0.45), "size": 0.4, "slow": 0.0},
	"glow":   {"label": "Firefly glow", "color": Color(0.85, 1.0, 0.3), "size": 0.22, "slow": 0.0},
	"shell":  {"label": "Pearl shell", "color": Color(0.96, 0.78, 0.84), "size": 0.3, "slow": 0.12},
}

signal depleted   # emitted when the last of it is taken

var kind := "sugar"
var home := Vector3.ZERO   # the spot it spawned at; it returns here if it ever falls out of the world
var amount := 5            # how many units this pickup holds
var visual: Node3D

func _ready() -> void:
	Registry.add(self, "pickups")
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
		"crystal":
			# A cluster of glowing violet spikes, found deep underground.
			mat.roughness = 0.1
			mat.emission_enabled = true
			mat.emission = Color(0.45, 0.35, 1.0)
			mat.emission_energy_multiplier = 1.6
			for i in 4:
				var spike := MeshInstance3D.new()
				var cm2 := CylinderMesh.new()
				cm2.top_radius = 0.0
				cm2.bottom_radius = s * randf_range(0.35, 0.6)
				cm2.height = s * randf_range(2.4, 4.0)
				cm2.radial_segments = 5
				cm2.rings = 1
				spike.mesh = cm2
				spike.material_override = mat
				spike.position = Vector3(randf_range(-0.5, 0.5) * s, cm2.height * 0.4, randf_range(-0.5, 0.5) * s)
				spike.rotation = Vector3(randf_range(-0.45, 0.45), randf() * TAU, randf_range(-0.45, 0.45))
				visual.add_child(spike)
			var glint := OmniLight3D.new()
			glint.light_color = Color(0.55, 0.5, 1.0)
			glint.light_energy = 0.9
			glint.omni_range = 7.0
			glint.shadow_enabled = false
			glint.distance_fade_enabled = true
			glint.distance_fade_begin = 35.0
			glint.distance_fade_length = 15.0
			glint.position.y = s * 1.5
			visual.add_child(glint)
			var cshape := SphereShape3D.new()
			cshape.radius = s
			col.shape = cshape
		"relic":
			# A glowing golden shard on a plinth, with a tall faint beam of light so it can be seen from far away.
			mat.roughness = 0.1
			mat.metallic = 0.6
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.8, 0.3)
			mat.emission_energy_multiplier = 2.2
			var shard := MeshInstance3D.new()
			var sm2 := PrismMesh.new()
			sm2.size = Vector3(s * 1.6, s * 3.2, s * 1.6)
			shard.mesh = sm2
			shard.material_override = mat
			shard.position.y = s * 1.8
			shard.rotation.y = randf() * TAU
			visual.add_child(shard)
			var beam_mat := StandardMaterial3D.new()
			beam_mat.albedo_color = Color(1.0, 0.85, 0.4, 0.18)
			beam_mat.emission_enabled = true
			beam_mat.emission = Color(1.0, 0.8, 0.3)
			beam_mat.emission_energy_multiplier = 1.4
			beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			var beam := MeshInstance3D.new()
			var bm2 := CylinderMesh.new()
			bm2.top_radius = 0.25
			bm2.bottom_radius = 0.6
			bm2.height = 90.0
			bm2.radial_segments = 8
			bm2.rings = 1
			beam.mesh = bm2
			beam.material_override = beam_mat
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.position.y = 45.0
			add_child(beam)
			var rlight := OmniLight3D.new()
			rlight.light_color = Color(1.0, 0.85, 0.45)
			rlight.light_energy = 1.6
			rlight.omni_range = 14.0
			rlight.shadow_enabled = false
			rlight.position.y = s * 2.0
			add_child(rlight)
			var rshape := SphereShape3D.new()
			rshape.radius = s
			col.shape = rshape
		"resin":
			# A sticky amber drop that burns hot.
			mat.roughness = 0.1
			mat.emission_enabled = true
			mat.emission = Color(0.8, 0.35, 0.05)
			mat.emission_energy_multiplier = 0.7
			for i in 3:
				var drop := MeshInstance3D.new()
				var rm := SphereMesh.new()
				rm.radius = s * (1.0 if i == 0 else 0.6)
				rm.height = rm.radius * 2.4
				drop.mesh = rm
				drop.material_override = mat
				if i > 0:
					drop.position = Vector3(randf_range(-0.8, 0.8), -0.1, randf_range(-0.8, 0.8)) * s
				visual.add_child(drop)
			var resin_shape := SphereShape3D.new()
			resin_shape.radius = s
			col.shape = resin_shape
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
		"shell":
			# A ribbed pearly scallop with a faint shimmer.
			mat.roughness = 0.2
			mat.metallic = 0.25
			mat.emission_enabled = true
			mat.emission = Color(0.45, 0.3, 0.38)
			mat.emission_energy_multiplier = 0.5
			var ridge_mat := StandardMaterial3D.new()
			ridge_mat.albedo_color = Color(0.99, 0.93, 0.9)
			ridge_mat.roughness = 0.25
			ridge_mat.metallic = 0.2
			var disc := MeshInstance3D.new()
			var dsm := SphereMesh.new()
			dsm.radius = s * 1.2
			dsm.height = s * 2.4
			dsm.radial_segments = 12
			dsm.rings = 6
			disc.mesh = dsm
			disc.material_override = mat
			disc.scale = Vector3(1.0, 0.28, 0.85)
			visual.add_child(disc)
			for i in 7:
				var a := lerpf(-1.1, 1.1, float(i) / 6.0)
				var ridge := MeshInstance3D.new()
				var rbm := BoxMesh.new()
				rbm.size = Vector3(s * 0.12, s * 0.12, s * 1.9)
				ridge.mesh = rbm
				ridge.material_override = ridge_mat
				ridge.rotation.y = a
				ridge.position = Vector3(sin(a) * s * 0.55, s * 0.28, -cos(a) * s * 0.55 + s * 0.05)
				visual.add_child(ridge)
			var hinge := MeshInstance3D.new()
			var hbm := BoxMesh.new()
			hbm.size = Vector3(s * 0.8, s * 0.3, s * 0.3)
			hinge.mesh = hbm
			hinge.material_override = ridge_mat
			hinge.position = Vector3(0, s * 0.1, s * 0.95)
			visual.add_child(hinge)
			var shell_shape := SphereShape3D.new()
			shell_shape.radius = s
			col.shape = shell_shape
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
