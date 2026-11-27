class_name PlantBurn
extends Node3D

# A bush or tree on fire. It is added as a child of the plant, so it goes when the plant's region
# is forgotten. Flames climb the plant, smoke pours off it and embers rain down and can start new
# fires. When it finishes the leaves are gone: a bush vanishes, a tree is left as a charred trunk,
# and the ground under it is blackened.

const BASE_TIME := 9.0
const EMBER_INTERVAL := 1.8

var spread_cb: Callable       # (position, reach_multiplier) -> void
var fire_cb: Callable         # (position, fuel) -> bool, a ground fire at the foot
var plant: Node3D
var height := 6.0
var radius := 1.5
var life := 0.0
var burn_time := BASE_TIME
var ember_t := 1.0
var seed_t := randf() * 100.0
var flames: CPUParticles3D
var smoke: CPUParticles3D
var embers: CPUParticles3D
var light: OmniLight3D
var finished := false

static var char_mat: StandardMaterial3D

func _ready() -> void:
	plant = get_parent() as Node3D
	measure()
	burn_time = BASE_TIME + height * 0.15
	var amt := clampi(int(height * 2.5), 18, 80)

	smoke = Effects.make(clampi(int(height), 12, 36), 4.0, 3.2, false,
		[Color(0.12, 0.11, 0.1, 0.0), Color(0.17, 0.15, 0.14, 0.45), Color(0.3, 0.3, 0.3, 0.0)], [0.5, 1.0, 2.0])
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 3.5
	smoke.gravity = Vector3(0.6, 0.8, 0.2)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(radius * 0.7, 0.5, radius * 0.7)
	smoke.position.y = height * 0.7
	add_child(smoke)

	flames = Effects.make(amt, 1.1, 2.4, true,
		[Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.6, 0.15, 0.8), Color(0.9, 0.25, 0.05, 0.4), Color(0.5, 0.06, 0.02, 0.0)], [0.7, 1.0, 0.7, 0.0])
	flames.direction = Vector3.UP
	flames.spread = 15.0
	flames.initial_velocity_min = 2.0
	flames.initial_velocity_max = 4.5
	flames.gravity = Vector3(0.4, 2.5, 0.1)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(radius * 0.8, height * 0.3, radius * 0.8)
	flames.position.y = height * 0.4
	add_child(flames)

	embers = Effects.make(26, 2.6, 0.14, true,
		[Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.4, 0.08, 0.9), Color(0.8, 0.1, 0.02, 0.0)], [1.0, 0.8, 0.0])
	embers.direction = Vector3.UP
	embers.spread = 60.0
	embers.initial_velocity_min = 2.0
	embers.initial_velocity_max = 6.0
	embers.gravity = Vector3(1.2, -3.0, 0.4)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(radius * 0.8, height * 0.3, radius * 0.8)
	embers.position.y = height * 0.5
	add_child(embers)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = clampf(height * 1.2, 9.0, 30.0)
	light.light_energy = 3.0
	light.shadow_enabled = false
	light.position.y = height * 0.4
	add_child(light)

	# A ground fire at the foot hurts anything close and frightens animals away.
	if fire_cb.is_valid():
		fire_cb.call(plant.global_position + Vector3(0, 1.0, 0), 9.0)

# How tall and wide the plant is, from its parts.
func measure() -> void:
	var top := 2.0
	var wide := 1.0
	for c in plant.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh == null:
				continue
			var box := mi.mesh.get_aabb()
			top = maxf(top, mi.position.y + (box.position.y + box.size.y) * mi.scale.y)
			wide = maxf(wide, maxf(box.size.x * mi.scale.x, box.size.z * mi.scale.z) * 0.5)
	height = clampf(top, 2.0, 50.0)
	radius = clampf(wide, 1.0, 7.0)

func _physics_process(delta: float) -> void:
	if finished:
		return
	life += delta
	var ramp := clampf(life / 1.5, 0.05, 1.0)   # it takes a moment to catch
	flames.scale = Vector3.ONE * ramp
	light.light_energy = (2.6 + sin((life + seed_t) * 15.0) * 0.4 + randf() * 0.4) * ramp
	ember_t -= delta
	if ember_t <= 0.0:
		ember_t = EMBER_INTERVAL
		if spread_cb.is_valid():
			spread_cb.call(plant.global_position, 3.0)   # embers carry the fire well beyond its edge
	if life >= burn_time:
		finish()

static func charcoal() -> StandardMaterial3D:
	if char_mat == null:
		char_mat = StandardMaterial3D.new()
		char_mat.albedo_color = Color(0.04, 0.035, 0.03)
		char_mat.roughness = 1.0
	return char_mat

# Leaves and needles are spheres and cones; trunks and branches are cylinders.
func is_leafy(mi: MeshInstance3D) -> bool:
	if mi.has_meta("leafy"):
		return true
	if mi.mesh is SphereMesh:
		return true
	if mi.mesh is CylinderMesh:
		return (mi.mesh as CylinderMesh).top_radius < 0.05
	return false

func finish() -> void:
	finished = true
	flames.emitting = false
	embers.emitting = false
	smoke.amount = maxi(4, smoke.amount / 3)
	light.visible = false
	var bare := true
	for c in plant.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if is_leafy(mi):
				mi.visible = false
			else:
				mi.material_override = charcoal()
				bare = false
	Effects.ash(plant.get_parent(), plant.global_position, clampf(radius * 1.6, 2.5, 7.0))
	plant.set_meta("burnt", true)
	plant.set_meta("burning", false)
	Registry.remove(plant, "plants")
	if bare:
		plant.get_tree().create_timer(5.0).timeout.connect(plant.queue_free)   # a bush burns away completely
	else:
		plant.get_tree().create_timer(5.0).timeout.connect(queue_free)
