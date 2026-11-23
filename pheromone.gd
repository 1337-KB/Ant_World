class_name Pheromone
extends Node3D

# A trail of scent an ant lays as it walks, so the way back is easy to find. It is drawn as a
# faint colored mist: soft overlapping puffs laid a short step apart that blend into one ribbon,
# show at night, and thin out and fade away after a while like the real thing. Every ant has its own trail and its own color, so later
# other players' trails can be shown beside yours.

const SPACING := 0.45       # distance between puffs, small enough that they blend into one mist
const MAX_DROPS := 6000     # the oldest puffs are replaced after this many
const LIFETIME := 900.0     # seconds until a puff has faded away
const PUFF_SIZE := 0.8      # width of one puff of mist
const PUFF_ALPHA := 0.3     # how strong one puff is (they overlap, so the mist builds up)
const FADE_UPDATE := 0.5    # how often the fading is refreshed
const SEE_DISTANCE := 130.0 # drops farther than this are not drawn

var ant: Ant
var trail_color := Color(0.3, 1.0, 0.25)
var laying := false

var drops_pos := PackedVector3Array()
var drops_time := PackedFloat32Array()
var next_slot := 0
var count := 0
var last_pos := Vector3(INF, INF, INF)
var fade_timer := 0.0
var mm: MultiMesh
var mmi: MultiMeshInstance3D

func _ready() -> void:
	drops_pos.resize(MAX_DROPS)
	drops_time.resize(MAX_DROPS)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	mm.mesh = qm
	mm.instance_count = MAX_DROPS
	mm.visible_instance_count = 0
	# Each puff is a flat square that always faces you, fading softly to nothing at its edge.
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = soft
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 4000.0
	mmi.visibility_range_end = SEE_DISTANCE
	mmi.visibility_range_end_margin = 20.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	top_level = true

func toggle() -> bool:
	laying = not laying
	last_pos = Vector3(INF, INF, INF)
	return laying

func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(delta: float) -> void:
	if ant == null:
		return
	if laying:
		# Drops go just under the ant, on whatever surface it is walking on (floor, wall or ceiling).
		var p := ant.global_position - ant.global_transform.basis.y * 0.35
		if p.distance_to(last_pos) >= SPACING:
			last_pos = p
			add_drop(p)
	fade_timer -= delta
	if fade_timer <= 0.0:
		fade_timer = FADE_UPDATE
		refresh()

func add_drop(p: Vector3) -> void:
	drops_pos[next_slot] = p
	drops_time[next_slot] = now()
	next_slot = (next_slot + 1) % MAX_DROPS
	count = mini(count + 1, MAX_DROPS)
	refresh()

# Redraws every drop, fading and shrinking the old ones and removing the ones that have faded.
func refresh() -> void:
	var t := now()
	mm.visible_instance_count = count
	for i in count:
		var age := t - drops_time[i]
		var life := clampf(1.0 - age / LIFETIME, 0.0, 1.0)
		var s := PUFF_SIZE * (0.6 + 0.4 * life)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), drops_pos[i] + Vector3.UP * 0.2))
		mm.set_instance_color(i, Color(trail_color.r, trail_color.g, trail_color.b, PUFF_ALPHA * life))

# The drops that are still fresh, as map positions (x, z).
func flat_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	var t := now()
	for i in count:
		if t - drops_time[i] < LIFETIME:
			out.append(Vector2(drops_pos[i].x, drops_pos[i].z))
	return out

func clear_trail() -> void:
	count = 0
	next_slot = 0
	mm.visible_instance_count = 0
