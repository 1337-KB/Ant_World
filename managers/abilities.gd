class_name Abilities
extends RefCounted

# Everything the ant can DO besides digging and building: spraying acid (hold G), choosing a class
# at your queen (E), the soldier's rocks (Y to make, V to throw), lighting fires (H) and putting
# them out with water (hold J), and how fire spreads. main.gd calls handle_spray(), handle_fire()
# and update_class_menu() every frame and forwards the key presses.

var m: Main

var spray: CPUParticles3D
var rock_cd := 0.0
var class_menu_open := false
var class_open_frame := -1
var class_layer: CanvasLayer
var class_buttons: Array = []
var douse_fx: CPUParticles3D
var fire_cd := 0.0

func setup(main: Main) -> void:
	m = main

func setup_spray() -> void:
	spray = CPUParticles3D.new()
	spray.emitting = false
	spray.amount = 90
	spray.lifetime = 0.45
	spray.local_coords = false
	spray.direction = Vector3(0, 0, -1)   # straight ahead of the node; we aim the node itself
	spray.spread = 8.0
	spray.initial_velocity_min = 13.0
	spray.initial_velocity_max = 17.0
	spray.gravity = Vector3(0, -3.0, 0)
	var drop := SphereMesh.new()
	drop.radius = 0.1
	drop.height = 0.2
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 1.0, 0.25, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = mat
	spray.mesh = drop
	m.add_child(spray)

# Hold G to spray acid in front of the camera. It hurts creatures in a narrow cone.
func handle_spray(delta: float) -> void:
	var want := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not m.ant.controls_locked \
			and not m.building.build_mode and Input.is_key_pressed(KEY_G)
	if m.ant.acid_locked and m.ant.acid >= 20.0:
		m.ant.acid_locked = false
	var spraying := want and m.ant.acid > 0.0 and not m.ant.acid_locked
	spray.emitting = spraying

	if not spraying:
		m.ant.acid = minf(Ant.ACID_MAX, m.ant.acid + Main.ACID_REGEN * delta)
		return

	m.ant.acid = maxf(0.0, m.ant.acid - Main.ACID_DRAIN * delta)
	if m.ant.acid <= 0.0:
		m.ant.acid_locked = true
		m.show_message("Out of acid.")

	var cam := m.ant.camera
	var aim := -cam.global_transform.basis.z
	var origin := m.ant.global_position + m.ant.basis.y * 0.7
	spray.global_transform = Transform3D(Basis.looking_at(aim, m.ant.basis.y), origin)

	var spray_reach := Main.SPRAY_RANGE * m.ant.stat("spray_range")
	var cone_cos := minf(0.96, 0.88 + 0.04 * (m.ant.stat("spray_range") - 1.0))
	var cone_tan := sqrt(1.0 - cone_cos * cone_cos) / cone_cos
	for c in Registry.of("creatures"):
		var cr := c as Creature
		if not cr.active:
			continue
		# Is any part of the creature inside the spray? A big body (the termite queen) counts by its whole size, not just its middle.
		var to_c: Vector3 = cr.hit_center() - origin
		var along := to_c.dot(aim)
		if along <= 0.01 or along > spray_reach + cr.hit_radius:
			continue
		var off_axis := (to_c - aim * along).length()
		if off_axis < along * cone_tan + cr.hit_radius:
			cr.take_damage(Main.SPRAY_DPS * m.ant.stat("spray_dmg") * delta)

# ---------- Ant classes ----------
# Press E next to your queen to pick a class. Worker: fast, carries a lot. Soldier: tough,
# strong long acid spray, carries only soil and water, and turns soil into rocks to throw.

func open_class_menu() -> void:
	refresh_class_menu()
	class_layer.visible = true
	class_menu_open = true
	class_open_frame = Engine.get_process_frames()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_class_menu() -> void:
	class_menu_open = false
	m.dig.dig_lock = true
	if class_layer != null:
		class_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func update_class_menu() -> void:
	if class_menu_open and (not is_instance_valid(m.queen) or m.ant.global_position.distance_to(m.queen.global_position) > Main.QUEEN_MENU_RANGE + 2.0):
		close_class_menu()

func build_class_menu() -> void:
	class_layer = CanvasLayer.new()
	class_layer.layer = 6
	class_layer.visible = false
	m.add_child(class_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.05, 0.95)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Your queen can change what kind of ant you are"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var descs := [
		"WORKER  [1]\nQuickest ant. Carries a lot of every resource and picks things up from further away. Average acid spray.",
		"SOLDIER  [2]\nTougher, with a longer health bar and a powerful long acid spray. Carries only soil and water, eats sugar on the spot. Press Y to turn soil into rocks, V to throw them.",
	]
	class_buttons.clear()
	for i in 2:
		var b := Button.new()
		b.custom_minimum_size = Vector2(540, 96)
		b.pressed.connect(choose_role.bind(i))
		var l := Label.new()
		l.text = descs[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.offset_left = 12.0
		l.offset_right = -12.0
		l.offset_top = 8.0
		l.offset_bottom = -8.0
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(l)
		box.add_child(b)
		class_buttons.append(b)
	var hint := Label.new()
	hint.text = "Anything your new class cannot carry is dropped next to you. Press E or Esc to close."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(540, 0)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(hint)

func refresh_class_menu() -> void:
	for i in class_buttons.size():
		var b := class_buttons[i] as Button
		b.disabled = (i == m.ant.role)   # the class you already are is greyed out

func choose_role(i: int) -> void:
	if i == m.ant.role:
		return
	var overflow := m.ant.set_role(i)
	var dropped := 0
	for k in overflow:
		var n := int(overflow[k])
		if n <= 0:
			continue
		dropped += n
		var p := Pickup.new()
		p.kind = k
		p.amount = n
		m.add_child(p)
		p.global_position = m.ant.global_position + Vector3(randf_range(-1.5, 1.5), 0.6, randf_range(-1.5, 1.5))
	apply_spray_role()
	m.dig.brush = minf(m.dig.brush, m.ant.stat("dig_max"))
	var msg := "You are now a %s ant." % Ant.ROLE_NAMES[i]
	if dropped > 0:
		msg += " You dropped %d items you cannot carry." % dropped
	m.show_message(msg)
	close_class_menu()

# Longer range for soldiers: the drops fly faster and live longer.
func apply_spray_role() -> void:
	var m: float = m.ant.stat("spray_range")
	spray.initial_velocity_min = 13.0 * m
	spray.initial_velocity_max = 17.0 * m
	spray.lifetime = 0.45 * (1.0 + 0.35 * (m - 1.0))

func convert_soil_to_rock() -> void:
	if m.ant.role != 1 or m.building.build_mode or m.ant.controls_locked:
		return
	if m.ant.rocks >= Ant.ROCK_CAP:
		m.show_message("You cannot carry more rocks.")
	elif m.ant.soil < Main.SOIL_PER_ROCK:
		m.show_message("You need %d soil to make a rock." % int(Main.SOIL_PER_ROCK))
	else:
		m.ant.soil -= Main.SOIL_PER_ROCK
		m.ant.rocks += 1

func throw_rock() -> void:
	if m.ant.role != 1 or m.building.build_mode or m.ant.controls_locked or rock_cd > 0.0:
		return
	if m.ant.rocks <= 0:
		m.show_message("No rocks. Press Y to turn soil into rocks.")
		return
	m.ant.rocks -= 1
	rock_cd = Main.ROCK_COOLDOWN
	var aim := -m.ant.camera.global_transform.basis.z
	var rock := RockShot.new()
	rock.world = m.world
	rock.damage = Main.ROCK_DAMAGE
	rock.velocity = (aim + Vector3(0, 0.12, 0)).normalized() * Main.ROCK_SPEED
	m.add_child(rock)
	rock.global_position = m.ant.global_position + m.ant.basis.y * 0.9 + aim * 1.2

# ---------- Fire ----------
# Fires only start when the ant lights one with resin (H). They burn, spread over grass,
# and hurt anything in them. Water (hold J) puts them out.

const FIRE_CAP := 30
const FIRE_RANGE := 9.0
const DOUSE_RANGE := 9.0
const WATER_DRAIN := 25.0   # water used per second of dousing

func setup_douse() -> void:
	douse_fx = CPUParticles3D.new()
	douse_fx.emitting = false
	douse_fx.amount = 90
	douse_fx.lifetime = 0.5
	douse_fx.local_coords = false
	douse_fx.direction = Vector3(0, 0, -1)
	douse_fx.spread = 10.0
	douse_fx.initial_velocity_min = 12.0
	douse_fx.initial_velocity_max = 16.0
	douse_fx.gravity = Vector3(0, -6.0, 0)
	var drop := SphereMesh.new()
	drop.radius = 0.1
	drop.height = 0.2
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.65, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = mat
	douse_fx.mesh = drop
	m.add_child(douse_fx)

func handle_fire(delta: float) -> void:
	fire_cd -= delta
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not m.ant.controls_locked and not m.building.build_mode
	if active and fire_cd <= 0.0 and Input.is_key_pressed(KEY_H):
		fire_cd = 0.6
		light_fire()

	var dousing := active and Input.is_key_pressed(KEY_J) and m.ant.water > 0.0
	douse_fx.emitting = dousing
	if not dousing:
		return
	m.ant.water = maxf(0.0, m.ant.water - WATER_DRAIN * delta)
	var cam := m.ant.camera
	var aim := -cam.global_transform.basis.z
	var origin := m.ant.global_position + m.ant.basis.y * 0.7
	douse_fx.global_transform = Transform3D(Basis.looking_at(aim, m.ant.basis.y), origin)
	for f in Registry.of("fires"):
		var to_f: Vector3 = (f as Node3D).global_position - origin
		var d := to_f.length()
		if d < DOUSE_RANGE and d > 0.01 and to_f.normalized().dot(aim) > 0.8:
			(f as Fire).douse(delta)

func light_fire() -> void:
	if int(m.ant.inventory["resin"]) <= 0:
		m.show_message("You need resin to light a fire. Collect the amber drops.")
		return
	var cam := m.ant.camera
	var hit = m.world.raycast(cam.global_position, -cam.global_transform.basis.z, FIRE_RANGE)
	if hit == null:
		m.show_message("Aim at the ground to light a fire.")
		return
	var pos: Vector3 = (hit as Vector3) + Vector3(0, 0.15, 0)
	if spawn_fire(pos):
		m.ant.inventory["resin"] = int(m.ant.inventory["resin"]) - 1
		m.show_message("Fire lit. Hold J to put it out with water.")

# Returns true if a fire was started.
func spawn_fire(pos: Vector3) -> bool:
	if Registry.of("fires").size() >= FIRE_CAP:
		return false
	if m.water.water_surface_at(pos + Vector3(0, 0.3, 0)) > -1.0e8:
		return false   # nothing burns in water
	for f in Registry.of("fires"):
		if (f as Node3D).global_position.distance_to(pos) < 1.2:
			return false
	var fire := Fire.new()
	fire.ant = m.ant
	fire.queen_getter = func(): return m.queen
	fire.spread_cb = spread_fire
	m.add_child(fire)
	fire.global_position = pos
	m.dig.clear_decor_near(pos, 1.8)   # the grass here burns away
	return true

# Fire creeps across grass, and only across grass.
func spread_fire(from: Vector3) -> void:
	var ang := randf() * TAU
	var dist := randf_range(1.8, 3.0)
	var x := from.x + cos(ang) * dist
	var z := from.z + sin(ang) * dist
	if absf(x) > Main.HALF - 1.0 or absf(z) > Main.HALF - 1.0 or m.terrain.surface_kind(x, z) != Blocks.GRASS:
		return
	var hit = m.world.raycast(Vector3(x, from.y + 4.0, z), Vector3.DOWN, 10.0)
	if hit == null:
		return
	spawn_fire((hit as Vector3) + Vector3(0, 0.15, 0))
