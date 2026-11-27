class_name Atmosphere
extends RefCounted

# Everything about the sky and light: the sun and moon, the day and night cycle, fog and morning
# mist, your headlamp, how buried you are (openness), and the biome you are standing in (which
# tints the haze and changes how fast you walk). main.gd calls setup_environment() and
# setup_headlamp() once, then update_cover(), update_daynight() and update_biome() every frame.

var m: Main

var sky_mat: ProceduralSkyMaterial
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var day_time := 0.08       # 0 = sunrise, 0.25 = noon, 0.5 = sunset, 0.75 = midnight
var day_count := 1
var night_creatures := false   # true while night creatures (fireflies) are out
var current_biome := 0
var biome_tint := Color(1, 1, 1)         # colours the haze and sunlight, blended smoothly between biomes
var biome_tint_target := Color(1, 1, 1)
var biome_timer := 0.0

func setup(main: Main) -> void:
	m = main

const MIN_DARK := 0.015        # how much sky light is left in total darkness (0 = pitch black)
const HEADLAMP_ENERGY := 0.5   # your own glow, so you can see a little when it is dark. 0 removes it.

var openness := 1.0            # 1 = open sky above you, 0 = buried
var openness_target := 1.0
var cover_timer := 0.0
var headlamp: OmniLight3D

func setup_headlamp() -> void:
	headlamp = OmniLight3D.new()
	headlamp.light_color = Color(1.0, 0.85, 0.6)
	headlamp.omni_range = 18.0
	headlamp.omni_attenuation = 1.4
	headlamp.shadow_enabled = true
	headlamp.shadow_bias = 0.08          # stops the dark flecks that shadows can leave on nearby walls
	headlamp.shadow_normal_bias = 2.0
	headlamp.light_energy = 0.0
	headlamp.visible = false
	m.ant.camera.add_child(headlamp)
	headlamp.position = Vector3(0, 0.3, -0.6)

# Checks how much solid ground is over your head: one ray straight up and four slanted ones.
func update_cover(delta: float) -> void:
	cover_timer -= delta
	if cover_timer <= 0.0:
		cover_timer = 0.15
		var o := m.ant.camera.global_position
		var open := 0
		var dirs := [Vector3.UP, Vector3(1, 1.2, 0), Vector3(-1, 1.2, 0), Vector3(0, 1.2, 1), Vector3(0, 1.2, -1)]
		for d in dirs:
			if m.world.raycast(o, d, 45.0, 1.0) == null:
				open += 1
		openness_target = float(open) / float(dirs.size())
	openness = move_toward(openness, openness_target, delta * 2.0)


# Moves the sun, recolors the sky, and sends fireflies out at dusk.
# Morning mist: thick at dawn, thin by midday, a little at dusk. Swamps and forests get the most.
# With VOLUMETRIC_MIST on, the mist also catches the low sun and shows light shafts between trees.
const VOLUMETRIC_MIST := true
const MIST_BY_BIOME := [0.8, 0.1, 0.7, 0.5, 1.0, 0.35, 0.6]   # forest, desert, highlands, tundra, swamp, savanna, plains
var mist_now := 0.0

const MOON_ENERGY := 0.6   # how bright the moon is. Raise for brighter nights.

func update_mist(delta: float, h: float, phase: float) -> void:
	var low_sun := 1.0 - smoothstep(0.0, 0.4, absf(h))
	var morning := 1.0 if cos(phase) > 0.0 else 0.3
	var target := low_sun * morning * float(MIST_BY_BIOME[clampi(current_biome, 0, 6)]) * openness
	mist_now = lerpf(mist_now, target, minf(1.0, delta * 0.5))
	if "fog_depth_end" in env:
		env.set("fog_depth_end", lerpf(m.content.FOG_FULL_AT, m.content.FOG_FULL_AT * 0.4, mist_now))
	env.fog_light_color = env.fog_light_color.lerp(Color(0.85, 0.85, 0.82), mist_now * 0.5)
	if VOLUMETRIC_MIST and "volumetric_fog_enabled" in env:
		env.set("volumetric_fog_enabled", mist_now > 0.05)
		env.set("volumetric_fog_density", 0.012 * mist_now)
		env.set("volumetric_fog_albedo", Color(0.9, 0.88, 0.8))
		env.set("volumetric_fog_length", 90.0)
		env.set("volumetric_fog_anisotropy", 0.6)

func update_daynight(delta: float) -> void:
	day_time += delta / Main.DAY_LENGTH
	if day_time >= 1.0:
		day_time -= 1.0
		day_count += 1
	var phase := day_time * TAU
	var h := sin(phase)                                  # 1 at noon, -1 at midnight
	var day := smoothstep(-0.12, 0.2, h)                 # 0 = full night, 1 = full day
	var warm := (1.0 - smoothstep(0.0, 0.4, absf(h))) * 0.9   # orange glow near sunrise and sunset

	var top := Color(0.02, 0.03, 0.09).lerp(Color(0.30, 0.50, 0.85), day).lerp(Color(0.25, 0.3, 0.55), warm * 0.5)
	var horizon := Color(0.06, 0.08, 0.16).lerp(Color(0.65, 0.78, 0.92), day).lerp(Color(0.95, 0.5, 0.25), warm)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.03).lerp(Color(0.3, 0.35, 0.3), day)
	biome_tint = biome_tint.lerp(biome_tint_target, minf(1.0, delta * 0.8))
	env.fog_light_color = horizon * biome_tint
	m.sky_life.moon_dir = moon.global_transform.basis.z
	m.sky_life.update(delta, m.ant.camera.global_position, horizon * biome_tint, day, warm, current_biome, openness)
	env.ambient_light_energy = lerpf(0.34, 0.75, day)
	env.ambient_light_color = Color(0.3, 0.4, 0.7).lerp(Color(0.82, 0.82, 0.78), day)   # neutral by day, so shade stays grey, not blue

	sun.rotation_degrees = Vector3(-rad_to_deg(phase), -30.0, 0.0)
	sun.light_energy = 1.3 * smoothstep(-0.04, 0.15, h)   # the sun is already strong a little after sunrise
	update_mist(delta, h, phase)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.3), warm) * biome_tint
	sun.shadow_enabled = h > 0.02
	moon.rotation_degrees = Vector3(-rad_to_deg(phase) + 180.0, -30.0, 0.0)
	moon.light_energy = MOON_ENERGY * smoothstep(0.0, 0.3, -h)
	moon.shadow_enabled = h < -0.05   # moonlight casts shadows too, so the night has shape
	env.glow_intensity = lerpf(1.0, 0.6, day)                 # emissive things (glow mushrooms, fireflies) bloom more at night
	env.glow_hdr_threshold = lerpf(0.7, 1.0, day)

	# Underground it is dark: the sky's light only reaches you in proportion to how open the sky is above you.
	var lit := lerpf(MIN_DARK, 1.0, openness * openness)   # squared, so even a little cover darkens quickly
	env.ambient_light_energy *= lit
	env.fog_light_color *= lerpf(0.15, 1.0, openness)
	sun.light_energy *= openness
	moon.light_energy *= openness
	headlamp.light_energy = HEADLAMP_ENERGY * (1.0 - openness)
	headlamp.visible = openness < 0.97

	# Fireflies come out as the light fades, and go to sleep at dawn.
	var night := day < 0.45
	if night != night_creatures:
		night_creatures = night
		for c in Registry.of("creatures"):
			if (c as Creature).nocturnal:
				(c as Creature).set_active(night)
			elif (c as Creature).diurnal:
				(c as Creature).set_active(not night)

func update_biome(delta: float) -> void:
	biome_timer -= delta
	if biome_timer > 0.0:
		return
	biome_timer = 0.25
	var w := m.terrain.biome_weights(m.ant.global_position.x, m.ant.global_position.z)
	var rest := 1.0
	var mix := Color(0, 0, 0)
	for i in w.size():
		mix += (Main.BIOME_TINT[i + 1] as Color) * w[i]
		rest -= w[i]
	biome_tint_target = mix + (Main.BIOME_TINT[0] as Color) * maxf(rest, 0.0)
	var b := m.terrain.biome_at(m.ant.global_position.x, m.ant.global_position.z)
	m.ant.terrain_speed = Main.BIOME_WALK_SPEED[b]
	m.ant.sprint_cost_mult = Main.BIOME_SPRINT_COST[b]
	var mm := m.terrain.mound_near(m.ant.global_position.x, m.ant.global_position.z)
	if not mm.is_empty() and not mm["dead"]:
		var md := Vector2(m.ant.global_position.x - float(mm["x"]), m.ant.global_position.z - float(mm["z"])).length()
		if md < 70.0 and not mm["alerted"]:
			mm["alerted"] = true
			m.show_message("A termite mound! Soldiers guard it. Find the queen deep below.")
		elif md > 140.0:
			mm["alerted"] = false
	if b != current_biome:
		current_biome = b
		var note := ""
		if b == Main.TUNDRA:
			note = " (the cold slows you)"
		elif b == Main.DESERT:
			note = " (the heat drains your sprint)"
		elif b == Main.SWAMP:
			note = " (the mud slows you)"
		m.show_message("Entered: %s%s" % [Main.BIOME_NAMES[b], note])

func setup_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.50, 0.85)
	sky_mat.sky_horizon_color = Color(0.65, 0.78, 0.92)
	sky_mat.ground_horizon_color = Color(0.65, 0.78, 0.92)
	sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.3)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.82, 0.78)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = m.content.FOG_DENSITY
	# Newer Godot versions can fade the world out by distance, so its far edge melts into the haze
	# instead of ending in a visible line. Older versions just keep the plain fog above.
	if "fog_depth_end" in env:
		env.set("fog_mode", 1)
		env.set("fog_depth_begin", m.content.FOG_CLEAR_UNTIL)
		env.set("fog_depth_end", m.content.FOG_FULL_AT)
		env.set("fog_depth_curve", 1.0)
		env.fog_density = 1.0

	# Ambient occlusion darkens creases and tunnels (Forward+ renderer only).
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.5

	# A soft glow on bright things, and a little extra color.
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.05

	var we := WorldEnvironment.new()
	we.environment = env
	m.add_child(we)

	# A warm sun with shadows that reach far enough to cover the field.
	sun = m.get_node("DirectionalLight3D")
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0

	# A dim blue moon that shines opposite the sun.
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.68, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.directional_shadow_max_distance = 120.0
	moon.shadow_bias = 0.08
	moon.shadow_normal_bias = 2.0
	m.add_child(moon)
