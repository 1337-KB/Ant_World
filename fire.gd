class_name Fire
extends Node3D

# A fire the ant lit with resin. It burns for a while, hurts anything standing in it,
# and spreads across grass. Water puts it out (hold J). It never starts on its own.

const BURN_TIME := 24.0
const SPREAD_INTERVAL := 3.0
const SPREAD_CHANCE := 0.65
const DAMAGE_RADIUS := 2.0
const ANT_DPS := 10.0
const CREATURE_DPS := 20.0
const QUEEN_DPS := 5.0
const QUEEN_RADIUS := 3.6
const DOUSE_NEEDED := 1.2       # seconds of water to put it out

var ant: Ant
var queen_getter: Callable      # returns the colony's queen, or null
var spread_cb: Callable         # (position) -> void. Main decides if it can spread there.
var life := 0.0
var wet := 0.0
var spread_timer := 0.0
var out := false
var flames: CPUParticles3D
var light: OmniLight3D

func _ready() -> void:
	add_to_group("fires")
	flames = CPUParticles3D.new()
	flames.amount = 28
	flames.lifetime = 0.9
	flames.local_coords = false
	flames.direction = Vector3.UP
	flames.spread = 22.0
	flames.initial_velocity_min = 1.4
	flames.initial_velocity_max = 2.6
	flames.gravity = Vector3(0, 1.0, 0)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.7
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.2, 0.95))
	ramp.set_color(1, Color(0.9, 0.15, 0.05, 0.0))
	flames.color_ramp = ramp
	var puff := SphereMesh.new()
	puff.radius = 0.28
	puff.height = 0.56
	puff.radial_segments = 6
	puff.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = mat
	flames.mesh = puff
	add_child(flames)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.5
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position.y = 0.8
	add_child(light)

func douse(delta: float) -> void:
	wet += delta
	if wet >= DOUSE_NEEDED:
		put_out()

func put_out() -> void:
	if out:
		return
	out = true
	remove_from_group("fires")
	flames.emitting = false
	light.visible = false
	get_tree().create_timer(1.0).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	if out:
		return
	life += delta
	if life >= BURN_TIME:
		put_out()
		return
	var fade := 1.0 - clampf(life / BURN_TIME, 0.0, 1.0) * 0.6
	light.light_energy = (2.0 + randf() * 1.0) * fade
	flames.scale = Vector3.ONE * fade

	# Burns what stands in it.
	if is_instance_valid(ant):
		var off := ant.global_position - global_position
		if Vector2(off.x, off.z).length() < DAMAGE_RADIUS and absf(off.y) < 2.5:
			ant.take_damage(ANT_DPS * delta)
	for c in get_tree().get_nodes_in_group("creatures"):
		var cr := c as Creature
		if cr.active and cr.global_position.distance_to(global_position) < DAMAGE_RADIUS:
			cr.take_damage(CREATURE_DPS * delta)
	if queen_getter.is_valid():
		var q = queen_getter.call()
		if is_instance_valid(q) and q.global_position.distance_to(global_position) < QUEEN_RADIUS:
			q.take_damage(QUEEN_DPS * delta)

	spread_timer += delta
	if spread_timer >= SPREAD_INTERVAL:
		spread_timer = 0.0
		if randf() < SPREAD_CHANCE and spread_cb.is_valid():
			spread_cb.call(global_position)
