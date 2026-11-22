class_name FarTerrain
extends Node3D

# A cheap, simple picture of the land far beyond the detailed ground, so you can see the hills
# and the colors of the biomes out to the horizon. It is a plain grid of heights taken straight
# from the world's height formula (no digging, no tunnels, no scenery), built a little at a
# time so it never stutters, and rebuilt around you as you walk. The detailed ground is drawn
# over it near you, and the distance fog fades it into the haze.

const RADIUS := 900.0          # how far out the picture reaches
const STEP := 16.0             # distance between grid points
const HOLE := 56.0             # nothing is drawn this close to the middle (the detailed ground covers it)
const REBUILD_DIST := 32.0     # rebuild the picture when you are this far from its middle
const SLICE_MS := 4.0          # time spent building per frame
const SINK := 2.5              # drawn this far under the real ground, so the detailed ground always wins
const WATER_COLOR := Color(0.18, 0.42, 0.62)

var height_fn: Callable        # (x, z) -> ground height
var kind_fn: Callable          # (x, z) -> block id of the surface
var edge_fn: Callable          # (x, z) -> distance to the edge of the world (negative outside)
var river_width := 17.0
var river_level := 37.5

var n := 0                     # grid points per side
var mesh_node: MeshInstance3D
var center := Vector2(INF, INF)   # middle of the picture on show
var job: Dictionary = {}
var indices := PackedInt32Array()
var colors_cache := {}

func _ready() -> void:
	n = int(RADIUS * 2.0 / STEP) + 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh_node = MeshInstance3D.new()
	mesh_node.material_override = mat
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.extra_cull_margin = 2000.0
	add_child(mesh_node)
	# The triangles never change (the hole is always in the middle of the grid), so make them once.
	var mid := float(n - 1) * 0.5
	for r in n - 1:
		for c in n - 1:
			var qx := (float(c) + 0.5 - mid) * STEP
			var qz := (float(r) + 0.5 - mid) * STEP
			if Vector2(qx, qz).length() < HOLE:
				continue
			var i0 := r * n + c
			indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + n, i0 + 1, i0 + n + 1, i0 + n]))

func color_of(kind: int) -> Color:
	if not colors_cache.has(kind):
		colors_cache[kind] = SurfaceMesher.block_color(kind)
	return colors_cache[kind]

# Called every frame with where you are.
func update(pos: Vector2) -> void:
	if job.is_empty() and center.distance_to(pos) > REBUILD_DIST and height_fn.is_valid():
		var snap_pos := Vector2(roundf(pos.x / STEP) * STEP, roundf(pos.y / STEP) * STEP)
		job = {"center": snap_pos, "row": 0, "h": PackedFloat32Array(), "col": PackedColorArray(), "water": PackedByteArray()}
		(job["h"] as PackedFloat32Array).resize(n * n)
		(job["col"] as PackedColorArray).resize(n * n)
		(job["water"] as PackedByteArray).resize(n * n)
	if job.is_empty():
		return
	var start := Time.get_ticks_usec()
	var cen: Vector2 = job["center"]
	var hs: PackedFloat32Array = job["h"]
	var cs: PackedColorArray = job["col"]
	var ws: PackedByteArray = job["water"]
	while int(job["row"]) < n:
		var r := int(job["row"])
		for c in n:
			var x := cen.x - RADIUS + float(c) * STEP
			var z := cen.y - RADIUS + float(r) * STEP
			var i := r * n + c
			if float(edge_fn.call(x, z)) < river_width:
				hs[i] = river_level          # the river, and open water beyond the edge of the world
				cs[i] = WATER_COLOR
				ws[i] = 1
			else:
				hs[i] = float(height_fn.call(x, z)) - SINK
				cs[i] = color_of(int(kind_fn.call(x, z)))
				ws[i] = 0
		job["row"] = r + 1
		if (Time.get_ticks_usec() - start) / 1000.0 > SLICE_MS:
			return
	finish(cen, hs, cs, ws)

func finish(cen: Vector2, hs: PackedFloat32Array, cs: PackedColorArray, ws: PackedByteArray) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for r in n:
		for c in n:
			var i := r * n + c
			verts[i] = Vector3(cen.x - RADIUS + float(c) * STEP, hs[i], cen.y - RADIUS + float(r) * STEP)
			if ws[i] == 1:
				norms[i] = Vector3.UP
			else:
				var hl := hs[i - 1] if c > 0 else hs[i]
				var hr := hs[i + 1] if c < n - 1 else hs[i]
				var hu := hs[i - n] if r > 0 else hs[i]
				var hd := hs[i + n] if r < n - 1 else hs[i]
				norms[i] = Vector3(hl - hr, 2.0 * STEP, hu - hd).normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_node.mesh = mesh
	center = cen
	job = {}
