class_name Placeable
extends StaticBody3D

# A crafted item placed in the world (wooden box, water barrel).
# Its origin is the center of the item's bounding box, like the building pieces.

var type := "box"
var stock := {}   # what a box or barrel holds: kind -> amount

func _ready() -> void:
	collision_layer = 5   # layers 1 and 4, same as building pieces
	collision_mask = 0

	var info: Dictionary = Crafting.RECIPES[type]
	if info.has("caps"):
		add_to_group("containers")
	var size: Vector3 = info["size"]
	var wood := StandardMaterial3D.new()
	wood.albedo_color = info["color"]
	wood.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(info["color"]).darkened(0.45)
	dark.roughness = 0.8

	if type == "queen":
		var skin := StandardMaterial3D.new()
		skin.albedo_color = info["color"]
		skin.roughness = 0.7
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = Color(0.35, 0.22, 0.12)
		head_mat.roughness = 0.6
		# Big abdomen, smaller thorax, head.
		var parts := [
			[Vector3(size.x * 0.85, size.y * 0.8, size.z * 0.55), Vector3(0, -size.y * 0.1, size.z * 0.17), skin],
			[Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.24), Vector3(0, -size.y * 0.1, -size.z * 0.2), head_mat],
			[Vector3(size.x * 0.34, size.y * 0.34, size.z * 0.16), Vector3(0, -size.y * 0.05, -size.z * 0.4), head_mat],
		]
		for part in parts:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			mi.mesh = sm
			mi.scale = part[0]
			mi.position = part[1]
			mi.material_override = part[2]
			add_child(mi)
		var tag := Label3D.new()
		tag.text = "Queen"
		tag.font_size = 48
		tag.pixel_size = 0.02
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, size.y * 0.5 + 0.9, 0)
		add_child(tag)
	elif type == "lamp":
		# A small stand holding a glowing bead of firefly glow.
		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = size.x * 0.32
		bm.bottom_radius = size.x * 0.32
		bm.height = size.y * 0.2
		base.mesh = bm
		base.material_override = dark
		base.position.y = -size.y * 0.4
		add_child(base)
		var stem := MeshInstance3D.new()
		var stm := CylinderMesh.new()
		stm.top_radius = size.x * 0.07
		stm.bottom_radius = size.x * 0.07
		stm.height = size.y * 0.5
		stem.mesh = stm
		stem.material_override = dark
		stem.position.y = -size.y * 0.15
		add_child(stem)
		var glow_mat := StandardMaterial3D.new()
		glow_mat.albedo_color = Color(0.9, 1.0, 0.4)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(0.7, 1.0, 0.2)
		glow_mat.emission_energy_multiplier = 2.5
		var bead := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = size.x * 0.4
		gm.height = size.x * 0.8
		bead.mesh = gm
		bead.material_override = glow_mat
		bead.position.y = size.y * 0.25
		add_child(bead)
		var light := OmniLight3D.new()
		light.light_color = Color(0.8, 1.0, 0.35)
		light.light_energy = 1.8
		light.omni_range = 13.0
		light.shadow_enabled = true   # set true for shadows, but many lamps with shadows gets slow
		light.position.y = size.y * 0.25
		add_child(light)
	elif type == "barrel":
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = size.x * 0.45
		cm.bottom_radius = size.x * 0.45
		cm.height = size.y
		body.mesh = cm
		body.material_override = wood
		add_child(body)
		for y in [-0.3, 0.3]:
			var band := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = size.x * 0.48
			bm.bottom_radius = size.x * 0.48
			bm.height = size.y * 0.08
			band.mesh = bm
			band.material_override = dark
			band.position.y = size.y * y
			add_child(band)
	else:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		body.mesh = bm
		body.material_override = wood
		add_child(body)
		var lid := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(size.x * 1.06, size.y * 0.12, size.z * 1.06)
		lid.mesh = lm
		lid.material_override = dark
		lid.position.y = size.y * 0.5
		add_child(lid)
		for x in [-0.3, 0.3]:
			var strap := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(size.x * 0.1, size.y * 1.02, size.z * 1.04)
			strap.mesh = sm
			strap.material_override = dark
			strap.position.x = size.x * x
			add_child(strap)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	add_child(col)

# The most this item can hold of one kind of thing (0 if it can't hold it).
func cap(kind: String) -> float:
	var caps: Dictionary = Crafting.RECIPES[type].get("caps", {})
	return float(caps.get(kind, 0))

func total_stock() -> float:
	var t := 0.0
	for k in stock:
		t += float(stock[k])
	return t
