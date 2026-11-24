class_name Disasters
extends RefCounted

# Natural disasters. So far: ROCKFALL, a cave-in underground.
#
# How it works: every few minutes, if you are down in a tunnel, the game picks a spot in the tunnel
# near you where there is a ceiling, and warns you (a rumble, dust falling, the screen shaking).
# After the warning the ceiling comes down and fills that spot with rock, which can block the tunnel.
#   - You are never buried: the spot is always a few steps away from you.
#   - A pillar you built near the spot holds the ceiling up and cancels the collapse.
#   - Ground that is protected (the royal cell, under lakes, under trees) never collapses.
#   - The rubble drops a few pebbles and sometimes a crystal (the "exposed minerals").
#   - Bigger colonies (higher tiers) get slightly bigger collapses.
# main.gd calls update() every frame. The backslash-adjacent apostrophe key (') forces one for testing.

const FIRST_DELAY := 240.0        # seconds of play before the first rockfall can happen
const MIN_INTERVAL := 300.0       # then one every 5 to 10 minutes
const MAX_INTERVAL := 600.0
const WARNING_TIME := 4.0         # seconds between the rumble and the collapse
const BASE_RADIUS := 2.2          # size of the collapse; grows 0.3 per tier above 1
const SPOT_MIN := 5.0             # the collapse is at least this far from you...
const SPOT_MAX := 11.0            # ...and at most this far
const SUPPORT_RANGE := 7.0        # a pillar this close to the spot holds the ceiling up
const BURIED_BELOW := 0.4         # you count as underground when the open sky is below this (0 to 1)
const SHAKE := 0.05               # how hard the screen shakes during the warning

var m: Main
var timer := FIRST_DELAY
var warning := 0.0                # counts down during a warning; 0 means no event is happening
var spot := Vector3.ZERO
var radius := BASE_RADIUS
var dust: CPUParticles3D

func setup(main: Main) -> void:
	m = main

func update(delta: float) -> void:
	if warning > 0.0:
		warning -= delta
		shake_camera()
		if warning <= 0.0:
			collapse()
		return
	timer -= delta
	if timer <= 0.0:
		if try_start():
			timer = randf_range(MIN_INTERVAL, MAX_INTERVAL)
		else:
			timer = 20.0   # no good tunnel right now, look again soon

# Starts a rockfall right now (used by the apostrophe key for testing).
func force() -> void:
	if warning > 0.0:
		return
	if not try_start():
		m.show_message("No tunnel ceiling nearby for a rockfall. Dig a tunnel and stand in it.")

func try_start() -> bool:
	if m.atmos.openness > BURIED_BELOW:
		return false   # only when you are under the ground
	var found := find_spot()
	if found.is_empty():
		return false
	spot = found["pos"]
	radius = BASE_RADIUS + 0.3 * float(maxi(0, m.progression.tier - 1))
	warning = WARNING_TIME
	start_dust()
	m.show_message("The ground rumbles. Dust falls from the ceiling. Get clear of the tunnel roof!")
	return true

# A point in open tunnel air a few steps away from you, with a ceiling just above it.
func find_spot() -> Dictionary:
	var origin := m.ant.global_position + m.ant.basis.y * 0.6
	for i in 24:
		var ang := randf() * TAU
		var dist := randf_range(SPOT_MIN, SPOT_MAX)
		var p := origin + Vector3(cos(ang) * dist, randf_range(-1.0, 1.5), sin(ang) * dist)
		if m.world.sample_density(p) > -0.3:
			continue   # not clearly open air
		var ceiling = m.world.raycast(p, Vector3.UP, 5.0, 0.25)
		if ceiling == null:
			continue
		var center: Vector3 = (ceiling as Vector3) - Vector3.UP * 0.9
		if m.dig.is_protected(center, radius + 1.0):
			continue
		if too_close_to_things(center):
			continue
		return {"pos": center}
	return {}

# Do not drop a ceiling on your queen, your boxes and traps, or anything alive nearby.
func too_close_to_things(center: Vector3) -> bool:
	for p in Registry.of("placeables"):
		if (p as Node3D).global_position.distance_to(center) < BASE_RADIUS + 4.0:
			return true
	return false

func supported() -> bool:
	for p in Registry.of("pieces"):
		if p.type == "pillar" and (p as Node3D).global_position.distance_to(spot) < SUPPORT_RANGE:
			return true
	return false

func collapse() -> void:
	stop_dust()
	reset_camera()
	if supported():
		m.show_message("A pillar held the ceiling up. The rumbling stops.")
		return
	if m.ant.global_position.distance_to(spot) < radius + 1.6:
		m.show_message("The ceiling came down close to you, but you got clear in time.")
		# Still collapses, but the sphere is centered a bit farther away so you are not buried.
		spot += (spot - m.ant.global_position).normalized() * (radius + 2.0)
	var dirty := m.world.fill_sphere(spot, radius)
	if dirty.is_empty():
		return
	m.stream.mark_edited(dirty)
	m.stream.queue_remesh(dirty, spot)
	m.content.wake_pickups(spot, radius + 1.0)
	m.water.mark_water_dirty(spot, radius + 1.0)
	drop_minerals()
	m.show_message("ROCKFALL! The tunnel roof collapsed. Dig through the rubble.")

# The collapse exposes a few pebbles and, now and then, a crystal.
func drop_minerals() -> void:
	var n := randi_range(2, 4)
	for i in n:
		spawn_pickup("pebble", randi_range(1, 3))
	if randf() < 0.35:
		spawn_pickup("crystal", 1)

func spawn_pickup(kind: String, amount: int) -> void:
	var p := Pickup.new()
	p.kind = kind
	p.amount = amount
	m.add_child(p)
	p.global_position = spot + Vector3(randf_range(-radius, radius), radius + 0.5, randf_range(-radius, radius))

# ---------- Warning effects ----------

func shake_camera() -> void:
	if m.ant.camera == null:
		return
	m.ant.camera.h_offset = randf_range(-SHAKE, SHAKE)
	m.ant.camera.v_offset = randf_range(-SHAKE, SHAKE)

func reset_camera() -> void:
	if m.ant.camera != null:
		m.ant.camera.h_offset = 0.0
		m.ant.camera.v_offset = 0.0

func start_dust() -> void:
	stop_dust()
	dust = CPUParticles3D.new()
	dust.amount = 60
	dust.lifetime = 1.4
	dust.local_coords = false
	dust.direction = Vector3(0, -1, 0)
	dust.spread = 25.0
	dust.initial_velocity_min = 0.5
	dust.initial_velocity_max = 1.5
	dust.gravity = Vector3(0, -1.2, 0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = radius
	var puff := SphereMesh.new()
	puff.radius = 0.07
	puff.height = 0.14
	puff.radial_segments = 6
	puff.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.45, 0.35, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = mat
	dust.mesh = puff
	m.add_child(dust)
	dust.global_position = spot + Vector3(0, 0.8, 0)

func stop_dust() -> void:
	if dust != null and is_instance_valid(dust):
		dust.queue_free()
	dust = null
