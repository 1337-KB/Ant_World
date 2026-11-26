class_name LilyPad
extends StaticBody3D

# A floating lily pad. It is solid on top, so the ant can climb onto it and stand above the water,
# out of reach of the fish. It rides the lake's water level up and down and bobs a little.
# Swim into the edge of a pad and the ant hops up onto it (see Ant.swim).

var lake: Dictionary = {}
var radius := 2.0
var flower := false
var phase := randf() * TAU
var time := 0.0
var base_y := 0.0

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0

	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.13, 0.46, 0.17).lerp(Color(0.22, 0.58, 0.2), randf())
	leaf.roughness = 0.45
	var vein := StandardMaterial3D.new()
	vein.albedo_color = Color(0.4, 0.72, 0.3)
	vein.roughness = 0.5

	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 0.96
	cm.height = 0.14
	cm.radial_segments = 24
	disc.mesh = cm
	disc.material_override = leaf
	add_child(disc)
	# Raised rim and a few veins so it reads as a leaf and not a plate.
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.07
	tm.outer_radius = radius + 0.02
	tm.rings = 20
	tm.ring_segments = 6
	rim.mesh = tm
	rim.material_override = leaf
	rim.position.y = 0.05
	rim.scale.y = 0.8
	add_child(rim)
	for i in 6:
		var v := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(radius * 0.9, 0.02, 0.05)
		v.mesh = bm
		v.material_override = vein
		var a := TAU * float(i) / 6.0
		v.rotation.y = a
		v.position = Vector3(cos(a) * radius * 0.45, 0.075, -sin(a) * radius * 0.45)
		add_child(v)

	if flower:
		build_flower()

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 0.7
	col.shape = shape
	col.position.y = -0.28   # top of the shape sits at the top of the leaf
	add_child(col)
	base_y = global_position.y

# A pink lotus bloom sitting on the pad's far side.
func build_flower() -> void:
	var petal := StandardMaterial3D.new()
	petal.albedo_color = Color(1.0, 0.62, 0.78)
	petal.roughness = 0.4
	petal.emission_enabled = true
	petal.emission = Color(0.6, 0.2, 0.35)
	petal.emission_energy_multiplier = 0.25
	var centre := StandardMaterial3D.new()
	centre.albedo_color = Color(1.0, 0.85, 0.2)
	centre.emission_enabled = true
	centre.emission = Color(0.8, 0.6, 0.05)
	var holder := Node3D.new()
	holder.position = Vector3(radius * 0.45, 0.1, 0)
	add_child(holder)
	for ring in 2:
		for i in 7:
			var p := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 8
			sm.rings = 4
			p.mesh = sm
			p.material_override = petal
			p.scale = Vector3(0.22, 0.55, 0.08)
			var a := TAU * float(i) / 7.0 + float(ring) * 0.45
			var tilt := 0.35 + float(ring) * 0.35
			p.position = Vector3(cos(a) * 0.12, 0.25 - float(ring) * 0.05, sin(a) * 0.12)
			p.rotation = Vector3(0, -a, 0)
			p.rotate_object_local(Vector3(0, 0, 1), -tilt)
			holder.add_child(p)
	var c := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.14
	cs.height = 0.28
	c.mesh = cs
	c.material_override = centre
	c.position.y = 0.18
	holder.add_child(c)

func _physics_process(delta: float) -> void:
	if lake.is_empty():
		return
	time += delta
	var level := float(lake.get("level_now", lake.get("level0", base_y)))
	var y := level + 0.02 + sin(time * 0.9 + phase) * 0.025
	if absf(global_position.y - y) > 0.002:
		global_position.y = y
