class_name Graphics
extends RefCounted

# Picture quality in one place. Three levels, cycled with the minus key (-) while playing:
#   0 Low    : the plain look, the lightest on your computer.
#   1 Medium : depth-of-field blur, sharper shadows, smoother edges, floating dust and pollen.
#   2 High   : everything above plus bounced light, reflections, soft shadows and the smoothest edges.
# If the game runs slowly, press minus to step down a level. Set DEFAULT_QUALITY for the level you start at.
#
# What each effect does, in plain terms:
#   Ambient occlusion (SSAO): darkens creases, tunnel corners and the places where things touch the ground.
#   Bounced light (SSIL):     a lit surface tints the shaded surfaces beside it, like sunlit grass glowing green on a rock.
#   Reflections (SSR):        shiny things such as water and beetle shells mirror what is around them.
#   Depth of field:           the far distance goes slightly soft, like a macro photo, which suits a tiny ant.
#   Shadow splits:            shadows near you get more detail than shadows far away.
#   MSAA:                     smooths jagged edges.

const DEFAULT_QUALITY := 2
const NAMES := ["Low", "Medium", "High"]

static var globals_added := false   # the shader global may only be created once per run
var m: Main
var quality := DEFAULT_QUALITY
var attributes: CameraAttributesPractical
var motes: GPUParticles3D

func setup(main: Main) -> void:
	m = main
	# The grass shader reads where you are, so blades can lean away as you walk through them.
	if not globals_added:
		globals_added = true
		RenderingServer.global_shader_parameter_add("ant_pos", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.0, -1000.0, 0.0))

# Call once the ant and its camera exist.
func start() -> void:
	attributes = CameraAttributesPractical.new()
	m.ant.camera.attributes = attributes
	make_motes()
	apply()

func cycle() -> void:
	quality = (quality + 1) % NAMES.size()
	apply()
	m.show_message("Graphics: %s" % NAMES[quality])

func apply() -> void:
	var env := m.atmos.env
	var sun := m.atmos.sun
	var vp := m.get_viewport()
	var q := quality

	# Smooth edges and no banding in the sky gradient.
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	vp.use_debanding = true

	# Shadows: more detail close up, and soft edges on the higher levels.
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][q])
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06   # the first slice covers only what is right around you
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_blend_splits = q > 0
	sun.directional_shadow_fade_start = 0.85
	sun.light_angular_distance = 0.0 if q < 2 else 0.5   # the sun is a disc, not a point, so shadow edges soften with distance

	# Ambient occlusion: tighter and more detailed.
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.5
	env.ssao_power = 1.8
	env.ssao_detail = 0.6 if q > 0 else 0.0
	env.ssao_light_affect = 0.15

	# Bounced light and reflections (High only).
	env.ssil_enabled = q >= 2
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.9
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2

	# A little more bloom on bright things, and a slightly richer picture.
	env.glow_bloom = 0.04 if q > 0 else 0.0
	env.glow_hdr_scale = 2.0
	env.tonemap_white = 6.0
	env.adjustment_saturation = 1.2 if q == 0 else 1.28
	env.adjustment_contrast = 1.08 if q == 0 else 1.12

	# Depth of field: the far distance goes soft. Nothing near you is blurred, so the ant stays crisp.
	attributes.dof_blur_far_enabled = q >= 1
	attributes.dof_blur_far_distance = 45.0
	attributes.dof_blur_far_transition = 110.0
	attributes.dof_blur_amount = 0.06 if q == 1 else 0.08
	attributes.dof_blur_near_enabled = false

	motes.visible = q >= 1

# Dust and pollen drifting in the air around you. They ride along with the camera.
func make_motes() -> void:
	motes = GPUParticles3D.new()
	motes.amount = 220
	motes.lifetime = 16.0
	motes.preprocess = 16.0   # already floating when the game starts
	motes.local_coords = false
	motes.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	motes.position = Vector3(0, 1.5, 0)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 9, 22)
	pm.direction = Vector3(1, 0.15, 0.4)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.05, 0.0, 0.02)   # a faint breeze, no falling
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 3.0
	# Fade in, hang there, fade out, so they never pop.
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.2, Color(1, 1, 1, 1))
	grad.add_point(0.8, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	motes.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.96, 0.8, 0.75)
	mat.no_depth_test = false
	quad.material = mat
	motes.draw_pass_1 = quad
	m.ant.camera.add_child(motes)

# Each frame: motes only drift by day and out in the open, never underground or at night.
func update(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("ant_pos", m.ant.global_position)
	if motes == null:
		return
	var h := sin(m.atmos.day_time * TAU)
	motes.emitting = m.atmos.openness > 0.6 and h > 0.0
