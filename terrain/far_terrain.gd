class_name FarTerrain
extends Node3D

# A cheap, simple picture of the land far beyond the detailed ground, so you can see the hills
# and the colors of the biomes out to the horizon. It is a plain grid of heights taken straight
# from the world's height formula (no digging, no tunnels, no scenery), built a little at a
# time so it never stutters, and rebuilt around you as you walk. The detailed ground is drawn
# over it near you, and the distance fog fades it into the haze.

const SLICE_MS := 3.0          # time spent building per frame
const WATER_COLOR := Color(0.18, 0.42, 0.62)

# The game uses two of these: a finer one for the middle distance and a coarse one for the horizon.
# Their settings are given when they are made (see make_far_terrain in main.gd).
var radius := 900.0            # how far out the picture reaches
var step := 16.0               # distance between grid points
var hole := 24.0               # nothing is drawn this close to the middle (the detailed ground, or a finer picture, covers it)
var rebuild_dist := 32.0       # rebuild the picture when you are this far from its middle
var sink := 2.5                # drawn this far under the real ground, so the detailed ground always wins
var tree_skip := 285.0         # real trees are drawn up to about here, so none are added closer
var tree_chance := 0.55        # share of grid points that get a tree, in wooded biomes
var draw_mounds := true

var height_fn: Callable        # (x, z) -> ground height
var kind_fn: Callable          # (x, z) -> block id of the surface
var edge_fn: Callable          # (x, z) -> distance to the edge of the world (negative outside)
var glade_fn: Callable         # (x, z) -> how much of a meadow this is (0 to 1); no stand-in trees grow there
var biome_fn: Callable         # (x, z) -> biome number
var lake_fn: Callable          # (x, z) -> lake water level, or a huge negative number when not over a lake
var mounds_fn: Callable        # (center, radius) -> mounds as {x, z, gh, R, H}
var river_width := 17.0
var river_level := 37.5

var n := 0                     # grid points per side
var mesh_node: MeshInstance3D
var center := Vector2(INF, INF)   # middle of the picture on show
var job: Dictionary = {}
var indices := PackedInt32Array()
var colors_cache := {}
var trees_node: MultiMeshInstance3D
var mounds_node: MultiMeshInstance3D


func _ready() -> void:
	n = int(radius * 2.0 / step) + 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh_node = MeshInstance3D.new()
	mesh_node.material_override = mat
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.extra_cull_margin = 2000.0
	add_child(mesh_node)

	var tree_mat := StandardMaterial3D.new()
	tree_mat.vertex_color_use_as_albedo = true
	tree_mat.roughness = 1.0
	tree_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	trees_node = MultiMeshInstance3D.new()
	trees_node.material_override = tree_mat
	trees_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trees_node.extra_cull_margin = 2000.0
	add_child(trees_node)
	var mound_mat := StandardMaterial3D.new()
	mound_mat.albedo_color = Color(0.5, 0.35, 0.24)
	mound_mat.roughness = 1.0
	mound_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mounds_node = MultiMeshInstance3D.new()
	mounds_node.material_override = mound_mat
	mounds_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mounds_node.extra_cull_margin = 2000.0
	add_child(mounds_node)
	# The triangles never change (the hole is always in the middle of the grid), so make them once.
	var mid := float(n - 1) * 0.5
	for r in n - 1:
		for c in n - 1:
			var qx := (float(c) + 0.5 - mid) * step
			var qz := (float(r) + 0.5 - mid) * step
			if Vector2(qx, qz).length() < hole:
				continue
			var i0 := r * n + c
			indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + n, i0 + 1, i0 + n + 1, i0 + n]))

# A solid of revolution from (radius, height) points, bottom to top, with smooth outward normals.
func lathe(points: Array, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var p0: Vector2 = points[i]
		var p1: Vector2 = points[i + 1]
		var slope := (p0.x - p1.x) / maxf(p1.y - p0.y, 0.001)
		for j in segments:
			var a0 := TAU * float(j) / float(segments)
			var a1 := TAU * float(j + 1) / float(segments)
			var n0 := Vector3(cos(a0), slope, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), slope, sin(a1)).normalized()
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			for tri in [[v00, n0, v10, n0, v01, n1], [v01, n1, v10, n0, v11, n1]]:
				for k in 3:
					st.set_normal(tri[k * 2 + 1])
					st.add_vertex(tri[k * 2])
	return st.commit()

func tree_mesh() -> ArrayMesh:
	# Three stacked skirts on a short trunk, about 1 unit wide and 1 unit tall, scaled per tree.
	return lathe([Vector2(0.05, 0.0), Vector2(0.05, 0.12), Vector2(0.5, 0.12), Vector2(0.14, 0.45), Vector2(0.4, 0.4), Vector2(0.1, 0.72), Vector2(0.28, 0.66), Vector2(0.0, 1.0)], 7)

func mound_mesh() -> ArrayMesh:
	var pts := []
	for i in 9:
		var t := float(i) / 8.0
		pts.append(Vector2(pow(1.0 - t, 0.7) * (1.0 if i < 8 else 0.0), t))
	return lathe(pts, 14)

func tree_color(biome: int, h: int) -> Color:
	var g := 0.85 + 0.3 * float((h >> 16) & 255) / 255.0
	match biome:
		0:
			return Color(0.07 * g, 0.26 * g, 0.13 * g)
		2:
			return Color(0.08 * g, 0.28 * g, 0.14 * g)
		3:
			return Color(0.6 * g, 0.76 * g, 0.74 * g)
	return Color(0, 0, 0, 0)

func color_of(kind: int) -> Color:
	if not colors_cache.has(kind):
		colors_cache[kind] = SurfaceMesher.block_color(kind)
	return colors_cache[kind]

# Called every frame with where you are.
func update(pos: Vector2) -> void:
	if job.is_empty() and center.distance_to(pos) > rebuild_dist and height_fn.is_valid():
		var snap_pos := Vector2(roundf(pos.x / step) * step, roundf(pos.y / step) * step)
		# Packed arrays are copied when read from a dictionary, so they are sized first and then stored.
		var h0 := PackedFloat32Array()
		var c0 := PackedColorArray()
		var w0 := PackedByteArray()
		h0.resize(n * n)
		c0.resize(n * n)
		w0.resize(n * n)
		job = {"center": snap_pos, "row": 0, "h": h0, "col": c0, "water": w0, "trees": []}
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
			var x := cen.x - radius + float(c) * step
			var z := cen.y - radius + float(r) * step
			var i := r * n + c
			if Vector2(x - cen.x, z - cen.y).length() < hole - 2.0 * step:
				continue   # inside the hole nothing is drawn, so do not spend time on it
			var lake := -1.0e9
			if lake_fn.is_valid():
				lake = float(lake_fn.call(x, z))
			if float(edge_fn.call(x, z)) < river_width:
				hs[i] = river_level          # the river, and open water beyond the edge of the world
				cs[i] = WATER_COLOR
				ws[i] = 1
			elif lake > -1.0e8:
				hs[i] = lake - 0.2           # a lake, so far-off lakes show as water instead of dry bowls
				cs[i] = WATER_COLOR
				ws[i] = 1
			else:
				hs[i] = float(height_fn.call(x, z)) - sink
				cs[i] = color_of(int(kind_fn.call(x, z)))
				ws[i] = 0
				if biome_fn.is_valid() and Vector2(x - cen.x, z - cen.y).length() > tree_skip and not (glade_fn.is_valid() and float(glade_fn.call(x, z)) > 0.1):
					var hh := hash(Vector2i(roundi(x / step), roundi(z / step)))
					if float(hh & 255) / 255.0 < tree_chance:
						var tc := tree_color(int(biome_fn.call(x, z)), hh)
						if tc.a > 0.0:
							(job["trees"] as Array).append([x + float((hh >> 8) & 15) - 7.5, hs[i] + sink, z + float((hh >> 12) & 15) - 7.5, 0.8 + 0.6 * float((hh >> 24) & 255) / 255.0, tc])
		job["row"] = r + 1
		if (Time.get_ticks_usec() - start) / 1000.0 > SLICE_MS:
			job["h"] = hs      # store the work so far; the arrays above are copies
			job["col"] = cs
			job["water"] = ws
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
			verts[i] = Vector3(cen.x - radius + float(c) * step, hs[i], cen.y - radius + float(r) * step)
			if ws[i] == 1:
				norms[i] = Vector3.UP
			else:
				var hl := hs[i - 1] if c > 0 else hs[i]
				var hr := hs[i + 1] if c < n - 1 else hs[i]
				var hu := hs[i - n] if r > 0 else hs[i]
				var hd := hs[i + n] if r < n - 1 else hs[i]
				norms[i] = Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
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
	build_props(cen, job["trees"])
	job = {}

# Trees and termite mounds standing on the far ground, so forests and mounds show out to the horizon.
func build_props(cen: Vector2, trees: Array) -> void:
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.use_colors = true
	tm.mesh = tree_mesh()
	tm.instance_count = trees.size()
	for i in trees.size():
		var t: Array = trees[i]
		var sc: float = t[3]
		tm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(7.0 * sc, 40.0 * sc, 7.0 * sc)), Vector3(t[0], t[1], t[2])))
		tm.set_instance_color(i, t[4])
	trees_node.multimesh = tm

	var ms := []
	if mounds_fn.is_valid() and draw_mounds:
		ms = mounds_fn.call(cen, radius)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mound_mesh()
	mm.instance_count = ms.size()
	for i in ms.size():
		var m: Dictionary = ms[i]
		var r: float = float(m["R"]) * 0.9     # a little inside the real mound, so the real one covers it up close
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, float(m["H"]) * 0.97, r)), Vector3(m["x"], float(m["gh"]) - 8.0, m["z"])))
	mounds_node.multimesh = mm
