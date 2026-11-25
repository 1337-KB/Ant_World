class_name Fire
extends Node3D

# A fire the ant lit with resin. It burns for a while, hurts anything standing in it,
# and spreads across grass. Water puts it out (hold J). It never starts on its own.

const BURN_TIME := 45.0          # no fire lasts longer than this, however much there is to burn
const FUEL_PER_ITEM := 0.12     # seconds of burning each blade of grass or flower adds
const FUEL_MAX := 14.0
const MIN_BURN := 4.0
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
var spread_cb: Callable         # (position, reach) -> void. Main decides if it can spread there.
var burn_cb: Callable           # (position, radius) -> int. Burns the plants there and says how many.
var heat_cb: Callable           # (position, seconds) -> void. Heats nearby bushes and trees.
var fuel := 3.0                 # seconds it can keep burning; grass and flowers add more
var burn_timer := randf() * 0.5
var life := 0.0
var wet := 0.0
var spread_timer := 0.0
var out := false
var flames: CPUParticles3D       # the bright body of the fire
var tongues: CPUParticles3D      # taller, dimmer flames
var embers: CPUParticles3D
var smoke: CPUParticles3D
var light: OmniLight3D
var seed_t := randf() * 100.0

func _ready() -> void:
	Registry.add(self, "fires")

	# Smoke first so the flames draw over it.
	smoke = Effects.make(12, 2.6, 1.5, false,
		[Color(0.12, 0.11, 0.1, 0.0), Color(0.18, 0.16, 0.15, 0.4), Color(0.3, 0.3, 0.3, 0.0)], [0.4, 1.0, 1.9])
	smoke.direction = Vector3.UP
	smoke.spread = 14.0
	smoke.initial_velocity_min = 1.2
	smoke.initial_velocity_max = 2.2
	smoke.gravity = Vector3(0.3, 0.7, 0.1)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.5
	smoke.position.y = 1.0
	add_child(smoke)

	tongues = Effects.make(16, 1.1, 1.5, true,
		[Color(1.0, 0.6, 0.15, 0.0), Color(1.0, 0.45, 0.08, 0.45), Color(0.7, 0.1, 0.02, 0.0)], [0.7, 1.0, 0.0])
	tongues.direction = Vector3.UP
	tongues.spread = 16.0
	tongues.initial_velocity_min = 1.6
	tongues.initial_velocity_max = 3.0
	tongues.gravity = Vector3(0.2, 1.8, 0.0)
	tongues.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	tongues.emission_sphere_radius = 0.55
	add_child(tongues)

	flames = Effects.make(22, 0.8, 1.2, true,
		[Color(1.0, 0.95, 0.6, 0.0), Color(1.0, 0.85, 0.35, 0.85), Color(1.0, 0.4, 0.05, 0.5), Color(0.6, 0.08, 0.02, 0.0)], [0.8, 1.0, 0.6, 0.0])
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.initial_velocity_min = 1.0
	flames.initial_velocity_max = 2.2
	flames.gravity = Vector3(0.15, 1.4, 0.0)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.4
	flames.position.y = 0.1
	add_child(flames)

	embers = Effects.make(10, 1.8, 0.1, true,
		[Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.4, 0.08, 0.9), Color(0.8, 0.1, 0.02, 0.0)], [1.0, 0.8, 0.0])
	embers.direction = Vector3.UP
	embers.spread = 35.0
	embers.initial_velocity_min = 2.0
	embers.initial_velocity_max = 4.5
	embers.gravity = Vector3(0.6, 0.5, 0.2)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.5
	embers.position.y = 0.4
	add_child(embers)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.5
	light.omni_range = 7.5
	light.shadow_enabled = false
	light.position.y = 0.9
	add_child(light)

func douse(delta: float) -> void:
	wet += delta
	if wet >= DOUSE_NEEDED:
		put_out()

func put_out() -> void:
	if out:
		return
	out = true
	var scorch := get_parent()
	Effects.ash(scorch, global_position, 2.6)
	Registry.remove(self, "fires")
	flames.emitting = false
	tongues.emitting = false
	embers.emitting = false
	smoke.emitting = false
	light.visible = false
	if wet >= DOUSE_NEEDED:
		Effects.steam(get_parent(), global_position)   # water makes steam; a fire that ran out of fuel just fades
	get_tree().create_timer(2.5).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	if out:
		return
	life += delta
	if life >= BURN_TIME:
		put_out()
		return
	# It eats what is around it. Plants add fuel; with nothing left it shrinks and goes out.
	burn_timer -= delta
	if burn_timer <= 0.0:
		burn_timer = 0.7
		if burn_cb.is_valid():
			fuel = minf(fuel + float(burn_cb.call(global_position, DAMAGE_RADIUS + 0.4)) * FUEL_PER_ITEM, FUEL_MAX)
		if heat_cb.is_valid():
			heat_cb.call(global_position, 0.7)
	fuel -= delta
	if fuel <= 0.0 and life > MIN_BURN:
		put_out()
		return
	var fade := clampf(fuel / 3.0, 0.35, 1.0)
	# The glow flickers in a few overlapping rhythms, like a real flame.
	var t := life * 1.0 + seed_t
	light.light_energy = (2.1 + sin(t * 17.0) * 0.35 + sin(t * 29.0 + 1.3) * 0.3 + randf() * 0.25) * fade
	light.position.y = 0.9 + sin(t * 11.0) * 0.08
	for e in [flames, tongues, embers, smoke]:
		(e as Node3D).scale = Vector3.ONE * fade

	# Burns what stands in it.
	if is_instance_valid(ant):
		var off := ant.global_position - global_position
		if Vector2(off.x, off.z).length() < DAMAGE_RADIUS and absf(off.y) < 2.5:
			ant.take_damage(ANT_DPS * delta)
	for c in Registry.of("creatures"):
		var cr := c as Creature
		if cr.active and cr.global_position.distance_to(global_position) < DAMAGE_RADIUS:
			cr.take_damage(CREATURE_DPS * delta)
			cr.scorched()   # it shudders in pain and runs
	if queen_getter.is_valid():
		var q = queen_getter.call()
		if is_instance_valid(q) and q.global_position.distance_to(global_position) < QUEEN_RADIUS:
			q.take_damage(QUEEN_DPS * delta)

	spread_timer += delta
	if spread_timer >= SPREAD_INTERVAL:
		spread_timer = 0.0
		if randf() < SPREAD_CHANCE and spread_cb.is_valid():
			spread_cb.call(global_position, 1.0)
