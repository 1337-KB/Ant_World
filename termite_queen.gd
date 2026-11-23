class_name TermiteQueen
extends Creature

# The termite queen: a huge, swollen, pale body that cannot move, deep in the royal cell at the
# bottom of the mound. She lays the colony's workers and soldiers, up to a limit. If she is
# killed (acid spray or fire), the colony is finished: no more termites, the mound turns grey,
# and what the workers stored spills out. Hurting her raises the alarm.

const SPAWN_INTERVAL := 22.0
const WORKER_CAP := 10
const SOLDIER_CAP := 8

var colony: Dictionary
var spawn_cb: Callable        # (colony, kind) -> void, set by main
var timer := 8.0
var time := 0.0
var abdomen: MeshInstance3D

func _ready() -> void:
	max_health = 400.0
	hit_radius = 3.4
	hit_offset = Vector3(0, 1.7, 1.0)
	bar_height = 5.0
	bar_scale = 2.0
	super()
	build_model()

func loot_kind() -> String:
	return ""   # main drops the colony's stores instead

func on_hurt() -> void:
	colony["alarm_until"] = Time.get_ticks_msec() / 1000.0 + 40.0

func build_model() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.95, 0.9, 0.74)
	skin.roughness = 0.55
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.72, 0.6, 0.38)
	band.roughness = 0.6
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.78, 0.5, 0.2)
	head_mat.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.1, 0.07)

	var body := Node3D.new()
	add_child(body)
	# The enormous egg-laying abdomen, with darker bands.
	abdomen = add_part(body, skin, Vector3(3.8, 3.2, 6.6), Vector3(0, 1.7, 3.2))
	for i in 5:
		add_part(body, band, Vector3(3.9, 3.3, 0.18), Vector3(0, 1.7, 0.9 + i * 1.15))
	add_part(body, skin, Vector3(1.8, 1.5, 1.8), Vector3(0, 1.3, -0.6))             # thorax
	add_part(body, head_mat, Vector3(1.5, 1.2, 1.5), Vector3(0, 1.2, -1.9))         # head
	for side in [-1.0, 1.0]:
		add_part(body, dark, Vector3(0.2, 0.2, 0.2), Vector3(side * 0.5, 1.5, -2.5))
		var jaw := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.12
		cm.height = 0.9
		jaw.mesh = cm
		jaw.material_override = dark
		jaw.position = Vector3(side * 0.35, 0.9, -2.7)
		jaw.rotation = Vector3(1.2, 0, side * 0.3)
		body.add_child(jaw)
	# Six short legs.
	for i in 3:
		for side in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.08
			lm.bottom_radius = 0.06
			lm.height = 1.0
			leg.mesh = lm
			leg.material_override = dark
			leg.position = Vector3(side * 0.9, 0.5, -1.0 + i * 0.7)
			leg.rotation = Vector3(0, 0, side * 0.9)
			body.add_child(leg)

func add_part(parent: Node3D, mat: StandardMaterial3D, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _physics_process(delta: float) -> void:
	if is_loaded.is_valid() and not is_loaded.call(global_position):
		return
	time += delta
	# She breathes slowly.
	abdomen.scale = Vector3(3.8, 3.2, 6.6) * (1.0 + 0.04 * sin(time * 1.6))
	timer -= delta
	if timer <= 0.0:
		timer = SPAWN_INTERVAL * randf_range(0.8, 1.2)
		var w := int(colony["workers"])
		var s := int(colony["soldiers"])
		var want := ""
		if float(s) / SOLDIER_CAP < float(w) / WORKER_CAP:
			want = "soldier" if s < SOLDIER_CAP else ""
		else:
			want = "worker" if w < WORKER_CAP else ""
		if want == "" and w < WORKER_CAP:
			want = "worker"
		if want != "" and spawn_cb.is_valid():
			spawn_cb.call(colony, want)
