class_name Effects
extends RefCounted

# Shared particle effects. Every fire, spray, dust cloud and impact in the game is built from the
# same soft round sprite, so they all look like part of one world instead of hard little balls.
#   additive = true  : the sprites add light together (fire, sparks, acid glow, magic).
#   additive = false : the sprites blend like smoke or dust.
# make() builds an emitter you can tweak; the other functions are ready-made one-shot effects.

static var soft: Texture2D
static var mats := {}

# A white dot that fades smoothly to nothing at its edge.
static func soft_texture() -> Texture2D:
	if soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.6))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		soft = t
	return soft

static func material(additive: bool) -> StandardMaterial3D:
	var key := 1 if additive else 0
	if not mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = soft_texture()
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.disable_receive_shadows = true
		mats[key] = mat
	return mats[key]

static func ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, colors[0])
	g.set_color(1, colors[colors.size() - 1])
	for i in range(1, colors.size() - 1):
		g.add_point(float(i) / float(colors.size() - 1), colors[i])
	return g

# A curve through the given values, evenly spaced from the start to the end of a particle's life.
static func curve(vals: Array) -> Curve:
	var c := Curve.new()
	c.clear_points()
	for i in vals.size():
		c.add_point(Vector2(float(i) / float(vals.size() - 1), float(vals[i])))
	return c

# A ready emitter. size is the sprite's width in world units; sizes is how it changes over life
# (for example [0.5, 1.0, 0.0] grows then shrinks to nothing).
static func make(amount: int, life: float, size: float, additive: bool, colors: Array, sizes: Array = [1.0, 0.0]) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material(additive)
	p.mesh = quad
	p.color_ramp = ramp(colors)
	p.scale_amount_curve = curve(sizes)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# Puts a finished one-shot emitter in the world and removes it when it has run its course.
static func fire_once(parent: Node, pos: Vector3, p: CPUParticles3D, linger: float) -> void:
	p.one_shot = true
	p.emitting = true
	parent.add_child(p)
	p.global_position = pos
	parent.get_tree().create_timer(linger).timeout.connect(p.queue_free)

# A rolling cloud of dust. scale 1.0 is a footstep-sized puff; a boss slam uses 2 or 3.
static func dust(parent: Node, pos: Vector3, power: float = 1.0, color: Color = Color(0.55, 0.47, 0.38)) -> void:
	var c0 := Color(color.r, color.g, color.b, 0.0)
	var c1 := Color(color.r, color.g, color.b, 0.55)
	var c2 := Color(color.r * 1.1, color.g * 1.1, color.b * 1.1, 0.0)
	var p := make(int(26.0 * power), 1.5, 1.1 * power, false, [c0, c1, c2], [0.4, 1.0, 1.5])
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.0 * power
	p.initial_velocity_max = 4.0 * power
	p.gravity = Vector3(0, 0.2, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4 * power
	fire_once(parent, pos, p, 2.2)

# Chunky bits that fly out and fall. They are small solid cubes so they read as stone or soil.
static func debris(parent: Node, pos: Vector3, color: Color, count: int = 14, power: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = 1.1
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 65.0
	p.initial_velocity_min = 3.0 * power
	p.initial_velocity_max = 8.0 * power
	p.gravity = Vector3(0, -20.0, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var bit := BoxMesh.new()
	bit.size = Vector3(0.12, 0.1, 0.14) * power
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	bit.material = mat
	p.mesh = bit
	fire_once(parent, pos, p, 1.6)

# Where a rock lands or a boss slams: a dust ring and flying stone.
static func impact(parent: Node, pos: Vector3, power: float = 1.0, color: Color = Color(0.5, 0.44, 0.38)) -> void:
	dust(parent, pos + Vector3(0, 0.2, 0), power, color.lightened(0.15))
	debris(parent, pos + Vector3(0, 0.3, 0), color, int(10.0 * power) + 4, power)

# A ring of dust thrown outward across the ground, for a slam that hits a wide area.
static func shockwave(parent: Node, pos: Vector3, radius: float) -> void:
	var c0 := Color(0.6, 0.52, 0.42, 0.0)
	var c1 := Color(0.6, 0.52, 0.42, 0.5)
	var c2 := Color(0.65, 0.57, 0.47, 0.0)
	var p := make(int(clampf(radius * 7.0, 20.0, 90.0)), 1.3, 1.6, false, [c0, c1, c2], [0.5, 1.0, 1.4])
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius * 0.85
	p.emission_ring_inner_radius = radius * 0.6
	p.emission_ring_height = 0.2
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.1, 0)
	fire_once(parent, pos + Vector3(0, 0.3, 0), p, 2.0)
	debris(parent, pos + Vector3(0, 0.3, 0), Color(0.45, 0.4, 0.34), 16, 1.2)

# A quick puff where a creature is hit. Pale for most; pass the creature's blood or sap colour.
static func hit_puff(parent: Node, pos: Vector3, color: Color = Color(0.9, 0.85, 0.7)) -> void:
	var p := make(7, 0.45, 0.5, true, [Color(color.r, color.g, color.b, 0.8), Color(color.r, color.g, color.b, 0.0)], [0.6, 1.2])
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3.ZERO
	fire_once(parent, pos, p, 0.8)

# A bigger burst when something dies, with a few sparks.
static func death_puff(parent: Node, pos: Vector3, size: float = 1.0) -> void:
	dust(parent, pos, 0.8 * size, Color(0.6, 0.55, 0.45))
	var p := make(int(12.0 * size) + 4, 0.8, 0.22, true, [Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.5, 0.15, 0.0)], [1.0, 0.0])
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0 * size
	p.gravity = Vector3(0, -6.0, 0)
	fire_once(parent, pos + Vector3(0, 0.3, 0), p, 1.2)

# Acid hitting the ground: a hissing green splash.
static func acid_splash(parent: Node, pos: Vector3) -> void:
	var p := make(8, 0.5, 0.3, true, [Color(0.7, 1.0, 0.3, 0.9), Color(0.2, 0.8, 0.1, 0.0)], [1.0, 0.2])
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -9.0, 0)
	fire_once(parent, pos + Vector3(0, 0.15, 0), p, 0.9)

# Water hitting something: a bright spray of drops and a little mist.
static func water_splash(parent: Node, pos: Vector3) -> void:
	var p := make(8, 0.5, 0.26, true, [Color(0.6, 0.85, 1.0, 0.85), Color(0.3, 0.6, 1.0, 0.0)], [1.0, 0.2])
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -9.0, 0)
	fire_once(parent, pos + Vector3(0, 0.15, 0), p, 0.9)

# The cloud of steam when a fire goes out.
static func steam(parent: Node, pos: Vector3) -> void:
	var p := make(18, 1.6, 1.3, false, [Color(0.9, 0.9, 0.9, 0.0), Color(0.9, 0.9, 0.9, 0.4), Color(0.9, 0.9, 0.9, 0.0)], [0.5, 1.0, 1.8])
	p.explosiveness = 0.6
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 0.8, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	fire_once(parent, pos + Vector3(0, 0.4, 0), p, 2.2)

# ---------- Burnt ground ----------
static var ash_tex: Texture2D

static func ash_texture() -> Texture2D:
	if ash_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.035, 0.03, 0.025, 0.95))
		g.set_color(1, Color(0.04, 0.035, 0.03, 0.0))
		g.add_point(0.55, Color(0.045, 0.04, 0.032, 0.8))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		ash_tex = t
	return ash_tex

# A dark scorch mark painted onto whatever ground is there (a decal follows slopes and holes).
# It lingers for `life` seconds, then fades.
static func ash(parent: Node, pos: Vector3, radius: float, life: float = 240.0) -> void:
	var d := Decal.new()
	d.texture_albedo = ash_texture()
	d.size = Vector3(radius * 2.0, 10.0, radius * 2.0)
	d.distance_fade_enabled = true
	d.distance_fade_begin = 90.0
	d.distance_fade_length = 30.0
	parent.add_child(d)
	d.global_position = pos
	d.rotation.y = randf() * TAU
	var tw := d.create_tween()
	tw.tween_interval(life)
	tw.tween_property(d, "modulate:a", 0.0, 40.0)
	tw.tween_callback(d.queue_free)
