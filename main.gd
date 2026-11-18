extends Node3D

const HALF := 32
const DIG_RADIUS := 1.5
const REACH := 30.0
const STORAGE_XZ := Vector2(8, 8)
const STORAGE_RADIUS := 3.0

var world := World.new()
var material := StandardMaterial3D.new()
var noise := FastNoiseLite.new()
var chunk_nodes := {}
var ant: Ant
var storage_pos := Vector3.ZERO
var counts := {"sugar": 0, "pebble": 0, "fiber": 0}
var hud: Label
var message := ""
var message_time := 0.0

func _ready() -> void:
	setup_environment()
	setup_crosshair()
	setup_hud()
	setup_noise()

	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0

	generate_terrain()
	for cpos in world.chunks:
		build_chunk_node(cpos)

	create_storage()
	scatter_pickups()

	$DirectionalLight3D.rotation_degrees = Vector3(-50, -30, 0)

	ant = Ant.new()
	add_child(ant)
	ant.position = storage_pos + Vector3(-6, 15, 0)  # drops in near the storage
	ant.deposit_requested.connect(_on_deposit)


func _process(delta: float) -> void:
	message_time -= delta
	var inv := ant.inventory
	var cap := Ant.CAPACITY
	var text := "Carrying:  Sugar %d/%d   Pebbles %d/%d   Leaf fiber %d/%d\n" % [
		inv["sugar"], cap, inv["pebble"], cap, inv["fiber"], cap]
	text += "Stored:      Sugar %d   Pebbles %d   Leaf fiber %d\n" % [
		counts["sugar"], counts["pebble"], counts["fiber"]]
	text += "[Walk over resources to collect]   [E at storage] deposit   [Click] dig"
	if message_time > 0.0:
		text += "\n" + message
	hud.text = text

func show_message(text: String) -> void:
	message = text
	message_time = 2.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			dig()

func dig() -> void:
	var cam := ant.camera
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var hit = world.raycast(origin, dir, REACH)
	if hit == null:
		return
	var dirty := world.dig_sphere(hit, DIG_RADIUS)
	for cpos in dirty:
		build_chunk_node(cpos)

# Deposit everything you're carrying, if you're standing at the storage.
func _on_deposit() -> void:
	var dx := ant.global_position.x - storage_pos.x
	var dz := ant.global_position.z - storage_pos.z
	var dy := ant.global_position.y - storage_pos.y
	if Vector2(dx, dz).length() > STORAGE_RADIUS + 1.0 or absf(dy) > 4.0:
		show_message("Get closer to the storage.")
		return
	var total := 0
	for k in ant.inventory:
		counts[k] += ant.inventory[k]
		total += ant.inventory[k]
		ant.inventory[k] = 0
	if total > 0:
		show_message("Deposited %d items." % total)
	else:
		show_message("You aren't carrying anything.")

func setup_noise() -> void:
	noise.seed = 1234
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	noise.fractal_octaves = 3

# One place that answers "how high is the ground here?"
func ground_height(x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	return clampf(10.0 + n * absf(n) * 12.0, 6.0, 14.0)

func generate_terrain() -> void:
	for x in range(-HALF, HALF):
		for z in range(-HALF, HALF):
			var h := ground_height(x, z)
			for y in range(0, 16):
				var depth := h - y
				var mat := Blocks.AIR
				if depth > 0.0:
					if depth < 1.5:
						mat = Blocks.GRASS
					elif depth < 4.0:
						mat = Blocks.DIRT
					else:
						mat = Blocks.STONE
				world.set_voxel(x, y, z, clampf(depth, -1.0, 1.0), mat)

func create_storage() -> void:
	storage_pos = Vector3(STORAGE_XZ.x, ground_height(STORAGE_XZ.x, STORAGE_XZ.y), STORAGE_XZ.y)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.8, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.5, 0.1)

	# A glowing disc on the ground marks the drop-off area.
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = STORAGE_RADIUS
	disc_mesh.bottom_radius = STORAGE_RADIUS
	disc_mesh.height = 0.3
	disc.mesh = disc_mesh
	disc.material_override = mat
	disc.position = storage_pos + Vector3(0, 0.1, 0)
	add_child(disc)

	# A tall thin beacon so you can spot it from far away.
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.15
	beam_mesh.bottom_radius = 0.15
	beam_mesh.height = 10.0
	beam.mesh = beam_mesh
	beam.material_override = mat
	beam.position = storage_pos + Vector3(0, 5.0, 0)
	add_child(beam)

	var label := Label3D.new()
	label.text = "Storage"
	label.font_size = 64
	label.pixel_size = 0.03
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = storage_pos + Vector3(0, 11.5, 0)
	add_child(label)

func scatter_pickups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var kinds: Array[String] = ["sugar", "pebble", "fiber"]
	for i in 45:
		var x := rng.randf_range(-HALF + 4, HALF - 4)
		var z := rng.randf_range(-HALF + 4, HALF - 4)
		if Vector2(x, z).distance_to(Vector2(storage_pos.x, storage_pos.z)) < 6.0:
			continue
		var p := Pickup.new()
		p.kind = kinds[i % 3]
		p.amount = rng.randi_range(4, 10)
		add_child(p)
		p.global_position = Vector3(x, ground_height(x, z) + 1.0, z)

func build_chunk_node(cpos: Vector3i) -> void:
	if chunk_nodes.has(cpos):
		chunk_nodes[cpos].queue_free()
		chunk_nodes.erase(cpos)

	var mesh := SurfaceMesher.build(world, cpos)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = Vector3(cpos * Chunk.SIZE)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	mi.add_child(body)

	add_child(mi)
	chunk_nodes[cpos] = mi

func setup_crosshair() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "+"
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(label)
	add_child(layer)

func setup_hud() -> void:
	var layer := CanvasLayer.new()
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	layer.add_child(hud)
	add_child(layer)

func setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.6, 0.75, 0.9)
	sky_mat.ground_horizon_color = Color(0.6, 0.75, 0.9)
	sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.3)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = 0.002

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	$DirectionalLight3D.shadow_enabled = true
