class_name Content
extends Node3D

# Everything that decorates the ground: trees, boulders, grass, flowers, resources, creatures,
# and what lives in the caves. It is built one 32 x 32 region at a time as the ground appears.
# main.gd owns the world and the streaming; this script asks it for what it needs.

var m: Main
var world: World
var terrain: Terrain
var water: Water

func setup(main: Main) -> void:
	m = main
	world = main.world
	terrain = main.terrain
	water = main.water

var region_job := {}
var region_sites := {}    # region -> its resource site numbers, so they come back the same
var bark_mat: StandardMaterial3D
var grass_mat_shared: ShaderMaterial
var blade_mesh_shared: ArrayMesh
var pebble_mesh_shared: SphereMesh
var landmark_mat: StandardMaterial3D
var flora_mats := {}   # species id -> shared material
var pebble_mat_shared: StandardMaterial3D
var grass_density_noise: FastNoiseLite
var pickup_sites := []   # each: {pos, kind}
var lake_sites_made := {}   # regions whose lake-bed shells already have sites
# ---------- Cave contents ----------
# Once a column's deep ground exists, look for cave floors in it and furnish them:
# glowing mushroom patches (which also drop Glow) and crystal clusters (more of them the deeper you go).
const RELIC_CHANCE := 0.002   # chance a region holds a relic (never in the forest)
var relics_taken := {}        # region key -> true once its relic was collected, so it never comes back

var cave_decor: Array = []   # mushroom patches stuck to cave surfaces, so they can drop away when the ground is dug
var cave_shroom_mat: StandardMaterial3D
var cave_stem_mat: StandardMaterial3D

func spawn_cave_contents(col: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(col) ^ 90210
	var x0 := col.x * Chunk.SIZE
	var z0 := col.y * Chunk.SIZE
	var top_guess := int(terrain.base_height(float(x0 + 8), float(z0 + 8))) - 10
	var bottom := int(World.BEDROCK_Y) + 3
	if top_guess <= bottom + 4:
		return
	var placed := 0
	for attempt in 14:
		if placed >= 6:
			break
		var x := x0 + rng.randi_range(1, Chunk.SIZE - 2)
		var z := z0 + rng.randi_range(1, Chunk.SIZE - 2)
		var top := int(terrain.ground_height(float(x), float(z))) - 8
		var y := top
		var spot := -9999
		var air_run := 0
		while y > bottom:
			if world.get_density(x, y, z) <= 0.0:
				air_run += 1
			else:
				if air_run >= 3:
					spot = y + 1
					break
				air_run = 0
			y -= 1
		if spot == -9999:
			continue
		var cy := floori(float(spot) / float(Chunk.SIZE))
		var cpos := Vector3i(col.x, cy, col.y)
		if not terrain.pockets_near_chunk(cpos).is_empty():
			continue   # an underground pool is here
		var mound := terrain.mounds_near_chunk(cpos)
		if not (mound.get("cones", []) as Array).is_empty() or not (mound.get("prims", []) as Array).is_empty():
			continue   # keep the termite mounds as they are
		# Pick a surface of the cave: the floor, a wall or the ceiling.
		var origin := Vector3(float(x) + 0.5, float(spot) + 1.5, float(z) + 0.5)
		var dir := Vector3.DOWN
		var kind_roll := rng.randf()
		if kind_roll < 0.45:
			var ang := rng.randf() * TAU
			dir = Vector3(cos(ang), 0.0, sin(ang))
		elif kind_roll < 0.58:
			dir = Vector3.UP
		var hit := cave_surface_hit(origin, dir)
		if not hit["ok"] and dir != Vector3.DOWN:
			dir = Vector3.DOWN
			hit = cave_surface_hit(origin, dir)
		if not hit["ok"]:
			continue
		var pos: Vector3 = hit["pos"]
		var nrm := cave_surface_normal(pos)
		var surf_basis := basis_from_up(nrm)
		var depth_t := clampf(float(top - spot) / 60.0, 0.0, 1.0)
		var roll := rng.randf()
		if roll < 0.28 + 0.3 * depth_t:
			var p := Pickup.new()
			p.kind = "crystal"
			p.amount = rng.randi_range(3, 8)
			p.home = pos + nrm * 0.3
			p.freeze = true
			m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(p)
			p.global_transform = Transform3D(surf_basis, pos + nrm * 0.05)
			placed += 1
		elif roll < 0.85:
			add_glow_shrooms(pos, nrm, surf_basis, rng)
			placed += 1

# Walks from open air in a direction until it meets solid ground, then pins down the exact surface.
func cave_surface_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var prev := origin
	var t := 0.5
	while t <= 12.0:
		var p := origin + dir * t
		if world.sample_density(p) > 0.0:
			var lo := prev
			var hi := p
			for i in 6:
				var mid := (lo + hi) * 0.5
				if world.sample_density(mid) > 0.0:
					hi = mid
				else:
					lo = mid
			return {"ok": true, "pos": lo}
		prev = p
		t += 0.5
	return {"ok": false}

# Which way the surface faces: away from the solid ground.
func cave_surface_normal(p: Vector3) -> Vector3:
	var e := 0.6
	var g := Vector3(
		world.sample_density(p + Vector3(e, 0, 0)) - world.sample_density(p - Vector3(e, 0, 0)),
		world.sample_density(p + Vector3(0, e, 0)) - world.sample_density(p - Vector3(0, e, 0)),
		world.sample_density(p + Vector3(0, 0, e)) - world.sample_density(p - Vector3(0, 0, e)))
	if g.length() < 0.001:
		return Vector3.UP
	return (-g).normalized()

# A rotation whose up direction is the given surface normal.
func basis_from_up(n: Vector3) -> Basis:
	var x := Vector3.RIGHT if absf(n.dot(Vector3.UP)) > 0.99 else Vector3.UP.cross(n).normalized()
	var z := x.cross(n).normalized()
	return Basis(x, n, z)

func add_glow_shrooms(pos: Vector3, nrm: Vector3, surf_basis: Basis, rng: RandomNumberGenerator) -> void:
	if cave_shroom_mat == null:
		cave_shroom_mat = StandardMaterial3D.new()
		cave_shroom_mat.albedo_color = Color(0.3, 0.9, 0.8)
		cave_shroom_mat.emission_enabled = true
		cave_shroom_mat.emission = Color(0.15, 0.9, 0.75)
		cave_shroom_mat.emission_energy_multiplier = 1.8
		cave_stem_mat = StandardMaterial3D.new()
		cave_stem_mat.albedo_color = Color(0.75, 0.8, 0.7)
		cave_stem_mat.roughness = 0.9
	var node := Node3D.new()
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(node)
	node.global_transform = Transform3D(surf_basis, pos + nrm * 0.03)
	cave_decor.append(node)
	for i in rng.randi_range(3, 6):
		var h := rng.randf_range(0.5, 1.3)
		var off := Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
		var stem := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.05
		sm.bottom_radius = 0.08
		sm.height = h
		sm.radial_segments = 6
		sm.rings = 1
		stem.mesh = sm
		stem.material_override = cave_stem_mat
		stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stem.position = off + Vector3(0, h * 0.5, 0)
		node.add_child(stem)
		var cap := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = rng.randf_range(0.22, 0.4)
		cm.height = cm.radius * 1.1
		cm.radial_segments = 8
		cm.rings = 3
		cap.mesh = cm
		cap.material_override = cave_shroom_mat
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.position = off + Vector3(0, h, 0)
		node.add_child(cap)
	if rng.randf() < 0.5:
		var light := OmniLight3D.new()
		light.light_color = Color(0.3, 1.0, 0.85)
		light.light_energy = 0.8
		light.omni_range = 7.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 35.0
		light.distance_fade_length = 15.0
		light.position = Vector3(0, 1.0, 0)
		node.add_child(light)
	# Glow to gather, sitting among the mushrooms.
	var g := Pickup.new()
	g.kind = "glow"
	g.amount = rng.randi_range(2, 5)
	g.home = pos + nrm * 0.4
	g.freeze = true
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(g)   # not a child of the mushrooms, so it survives if they are dug away
	g.global_position = node.global_transform * Vector3(0.5, 0.3, 0.4)

# ---------- Trees and boulders ----------
# Trees are enormous at ant scale: towering trunks you can climb, with a canopy far overhead.
# Boulders are solid rock. The ground around both is too hard to dig, so nothing is left floating.

const FOG_CLEAR_UNTIL := 40.0   # distance fog: nothing is hazy up to here...
const FOG_FULL_AT := 600.0      # ...and everything is fully hazy here, at the far edge of the distant land
const FOG_DENSITY := 0.007   # lower = clearer view, but the edge of the loaded world shows more (0.016 was the old value)

var grain_albedo: NoiseTexture2D
var grain_normal: NoiseTexture2D

func add_obstacle(o: Dictionary) -> void:
	var pos: Vector3 = o["pos"]
	var key := m.stream.region_key(pos.x, pos.z)
	if not m.stream.obstacles_by_region.has(key):
		m.stream.obstacles_by_region[key] = []
	m.stream.obstacles_by_region[key].append(o)

# The trees and boulders in this region and the eight around it.
func obstacles_near(x: float, z: float) -> Array:
	var key := m.stream.region_key(x, z)
	var out := []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := key + Vector2i(dx, dz)
			if m.stream.obstacles_by_region.has(k):
				out.append_array(m.stream.obstacles_by_region[k])
	return out

func near_obstacle(x: float, z: float, margin: float = 1.5) -> bool:
	if terrain.near_mound(x, z, margin):
		return true
	for o in obstacles_near(x, z):
		var op: Vector3 = o["pos"]
		if Vector2(x - op.x, z - op.z).length() < float(o["radius"]) + margin:
			return true
	return false

# A rough, grainy material projected from all sides. uv_scale stretches the grain along an axis.
func make_grain_material(color: Color, uv_scale: Vector3, bump: float) -> StandardMaterial3D:
	if grain_albedo == null:
		var grain := FastNoiseLite.new()
		grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		grain.frequency = 0.08
		grain.fractal_octaves = 4
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.6, 0.6, 0.6))
		ramp.set_color(1, Color(1, 1, 1))
		grain_albedo = NoiseTexture2D.new()
		grain_albedo.noise = grain
		grain_albedo.seamless = true
		grain_albedo.width = 256
		grain_albedo.height = 256
		grain_albedo.color_ramp = ramp
		grain_normal = NoiseTexture2D.new()
		grain_normal.noise = grain
		grain_normal.seamless = true
		grain_normal.as_normal_map = true
		grain_normal.bump_strength = 6.0
		grain_normal.width = 256
		grain_normal.height = 256
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = grain_albedo
	mat.normal_enabled = true
	mat.normal_texture = grain_normal
	mat.normal_scale = bump
	mat.roughness = 1.0
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = uv_scale
	return mat

# (Trees and boulders are placed per region. See the region content section.)

# What grows at a site depends on the biome: forest trees, willows in the swamp, flat-topped
# acacias on the savanna, cacti in the desert, bare dead trees and pines in the cold and the hills.
func add_plant(x: float, z: float, rng: RandomNumberGenerator, biome: int, bark: StandardMaterial3D) -> void:
	match biome:
		Main.SWAMP:
			add_willow(x, z, rng)
		Main.SAVANNA:
			add_acacia(x, z, rng)
		Main.DESERT:
			add_cactus(x, z, rng)
		Main.TUNDRA:
			if rng.randf() < 0.5:
				add_dead_tree(x, z, rng)
			else:
				add_pine(x, z, rng, Color(0.60, 0.76, 0.74))   # frosted
		Main.HIGHLANDS:
			add_pine(x, z, rng, Color(0.08, 0.28, 0.14))
		Main.PLAINS:
			# Open grassland: a lone tree now and then, otherwise a few low bushes.
			if rng.randf() < 0.12:
				add_round_tree(x, z, rng, bark)
			else:
				add_shrub(x, z, rng)
				if rng.randf() < 0.5:
					add_shrub(x + rng.randf_range(-3.0, 3.0), z + rng.randf_range(-3.0, 3.0), rng)
		_:
			if rng.randf() < 0.45:
				add_spruce(x, z, rng)
			else:
				add_round_tree(x, z, rng, bark)

# A static body for a plant, sunk slightly so it never floats.
func new_plant_body(x: float, z: float, burns: bool = true, burn_r: float = 2.5) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	m.stream.region_node(m.stream.region_key(x, z)).add_child(body)
	body.global_position = Vector3(x, terrain.ground_height(x, z) - 1.0, z)
	body.set_meta("climbable", true)   # beetles, spiders and termites can climb it
	if burns:
		body.set_meta("burn_r", burn_r)
		Registry.add(body, "plants")   # fire can catch it
	return body

func plant_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat

# Scenery fades out smoothly toward the edge of the drawn world instead of appearing suddenly.
func fade_far(mi: MeshInstance3D) -> void:
	mi.visibility_range_end = Main.TREE_FADE_END
	mi.visibility_range_end_margin = 12.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

# sway > 0 makes the part move in the wind (leaves, needles, bushes); 0 keeps it rigid (trunks, branches).
func plant_part(body: Node3D, mesh: Mesh, color: Color, pos: Vector3, orient: Basis = Basis.IDENTITY, sway: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = PlantSway.leaf_material(color, mesh, sway) if sway > 0.0 else plant_mat(color)
	mi.transform = Transform3D(orient, pos)
	fade_far(mi)
	body.add_child(mi)
	return mi

func cylinder_mesh(top: float, bottom: float, height: float, segments: int = 10) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	return cm

func sphere_mesh() -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return sm

func trunk_collision(body: Node3D, mesh: CylinderMesh, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	col.shape = mesh.create_convex_shape(true, true)
	col.position = pos
	body.add_child(col)

# Desert: a saguaro-style cactus with two arms.
func add_cactus(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z, false)   # a cactus is too wet to burn
	var h := rng.randf_range(12.0, 19.0)
	var r := rng.randf_range(1.4, 1.9)
	var green := Color(0.18, 0.48, 0.24)
	var trunk := CapsuleMesh.new()
	trunk.radius = r
	trunk.height = h
	trunk.radial_segments = 10
	plant_part(body, trunk, green, Vector3(0, h * 0.5, 0))
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = r
	shape.height = h
	col.shape = shape
	col.position = Vector3(0, h * 0.5, 0)
	body.add_child(col)
	var facing := rng.randf() * TAU
	for side in [-1.0, 1.0]:
		var arm_y := h * rng.randf_range(0.4, 0.6)
		var reach := r * 2.6
		var out := cylinder_mesh(r * 0.55, r * 0.55, reach, 8)
		var arm_basis := Basis(Vector3.UP, facing) * Basis(Vector3.BACK, PI * 0.5)
		plant_part(body, out, green, Basis(Vector3.UP, facing) * Vector3(side * reach * 0.5, arm_y, 0), arm_basis)
		var up := CapsuleMesh.new()
		up.radius = r * 0.55
		up.height = h * rng.randf_range(0.3, 0.45)
		up.radial_segments = 8
		plant_part(body, up, green, Basis(Vector3.UP, facing) * Vector3(side * reach, arm_y + up.height * 0.5, 0))
	add_obstacle({"pos": Vector3(x, terrain.ground_height(x, z), z), "radius": r * 2.2})

# Savanna: an acacia with a thin, curving trunk and a wide, layered, flat-topped canopy.
func add_acacia(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(18.0, 27.0)
	var r := rng.randf_range(1.0, 1.5)
	var facing := rng.randf() * TAU
	var lean := rng.randf_range(0.05, 0.2)
	var seg := (h + 1.0) / 3.0
	var pos := Vector3.ZERO
	for k in 3:
		var tb := Basis(Vector3.UP, facing) * Basis(Vector3.RIGHT, lean * float(k + 1) * (1.0 if k % 2 == 0 else -0.6))
		var tm := cylinder_mesh(r * (1.15 - 0.3 * float(k + 1)), r * (1.15 - 0.3 * float(k)), seg, 10)
		var mid := pos + tb * Vector3(0, seg * 0.5, 0)
		plant_part(body, tm, Color(0.34, 0.25, 0.17), mid, tb)
		var col := CollisionShape3D.new()
		col.shape = tm.create_convex_shape(true, true)
		col.transform = Transform3D(tb, mid)
		body.add_child(col)
		pos += tb * Vector3(0, seg, 0)
	# Layered canopy: darker underneath, lighter on top.
	for i in rng.randi_range(2, 3):
		var w := rng.randf_range(9.0, 14.0)
		var t := float(i) / 2.0
		var leaf := Color(0.22, 0.34, 0.10).lerp(Color(0.38, 0.52, 0.14), t)
		var mi := plant_part(body, sphere_mesh(), leaf,
				pos + Vector3(rng.randf_range(-3.0, 3.0), 0.9 * float(i), rng.randf_range(-3.0, 3.0)), Basis.IDENTITY, 0.5)
		mi.scale = Vector3(w, 1.0 + 0.2 * float(i), w)
	add_obstacle({"pos": Vector3(x, terrain.ground_height(x, z), z), "radius": r * 1.4})
	# Shrubs often grow in the tree's shade.
	if rng.randf() < 0.35:
		for i in rng.randi_range(1, 2):
			var ang := rng.randf() * TAU
			var d := rng.randf_range(4.0, 9.0)
			add_shrub(x + cos(ang) * d, z + sin(ang) * d, rng)

# A low, dark green bush made of a few overlapping lumps. Decoration only: you walk through it.
func add_shrub(x: float, z: float, rng: RandomNumberGenerator) -> void:
	if terrain.near_pool(x, z, 1.6) or near_obstacle(x, z, 1.5):
		return
	var root := Node3D.new()
	m.stream.region_node(m.stream.region_key(x, z)).add_child(root)
	root.global_position = Vector3(x, terrain.ground_height(x, z) - 0.3, z)
	root.set_meta("burn_r", 2.2)
	Registry.add(root, "plants")
	for i in rng.randi_range(2, 3):
		var s := rng.randf_range(1.3, 2.3)
		var g := rng.randf_range(0.85, 1.15)
		var mi := plant_part(root, sphere_mesh(), Color(0.16 * g, 0.30 * g, 0.11 * g),
				Vector3(rng.randf_range(-1.4, 1.4), s * 0.5, rng.randf_range(-1.4, 1.4)), Basis.IDENTITY, 0.16)
		mi.scale = Vector3(s * 1.2, s * 0.9, s * 1.2)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# Swamp: a short, dark, drooping willow with hanging vines.
func add_willow(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(15.0, 22.0)
	var r := rng.randf_range(2.0, 2.8)
	var tm := cylinder_mesh(r * 0.7, r * 1.4, h + 1.0, 12)
	plant_part(body, tm, Color(0.24, 0.19, 0.13), Vector3(0, (h + 1.0) * 0.5, 0))
	trunk_collision(body, tm, Vector3(0, (h + 1.0) * 0.5, 0))
	for i in rng.randi_range(3, 5):
		var w := rng.randf_range(6.0, 9.0)
		var mi := plant_part(body, sphere_mesh(), Color(0.10, 0.32, 0.14),
				Vector3(rng.randf_range(-4.0, 4.0), h + rng.randf_range(-1.5, 2.0), rng.randf_range(-4.0, 4.0)), Basis.IDENTITY, 0.5)
		mi.scale = Vector3(w, w * 0.6, w)
	for i in 12:
		var ang := rng.randf() * TAU
		var d := rng.randf_range(3.0, 8.0)
		var vlen := rng.randf_range(5.0, 10.0)
		plant_part(body, cylinder_mesh(0.1, 0.16, vlen, 4), Color(0.20, 0.42, 0.20),
				Vector3(cos(ang) * d, h - vlen * 0.5 + 1.0, sin(ang) * d))
	add_obstacle({"pos": Vector3(x, terrain.ground_height(x, z), z), "radius": r * 1.4})

# Tundra: a bare, dead tree with crooked branches and no leaves.
func add_dead_tree(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(16.0, 25.0)
	var r := rng.randf_range(1.2, 1.8)
	var bark := Color(0.38, 0.33, 0.30)
	var tm := cylinder_mesh(r * 0.4, r * 1.2, h + 1.0, 8)
	plant_part(body, tm, bark, Vector3(0, (h + 1.0) * 0.5, 0))
	trunk_collision(body, tm, Vector3(0, (h + 1.0) * 0.5, 0))
	for i in rng.randi_range(4, 6):
		var blen := rng.randf_range(6.0, 10.0)
		var attach := Vector3(0, h * rng.randf_range(0.5, 0.95), 0)
		var tilt := rng.randf_range(0.8, 1.3)
		var bb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
		plant_part(body, cylinder_mesh(0.12, 0.45, blen, 6), bark, attach + bb * Vector3(0, blen * 0.5, 0), bb)
	add_obstacle({"pos": Vector3(x, terrain.ground_height(x, z), z), "radius": r * 1.3})

# Highlands and tundra: a tall pine made of stacked cones.
func add_pine(x: float, z: float, rng: RandomNumberGenerator, leaf: Color) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(22.0, 32.0)
	var r := rng.randf_range(1.2, 1.7)
	var tm := cylinder_mesh(r * 0.5, r * 1.2, h * 0.7, 10)
	plant_part(body, tm, Color(0.30, 0.20, 0.12), Vector3(0, h * 0.35, 0))
	trunk_collision(body, tm, Vector3(0, h * 0.35, 0))
	var layers := 4
	for i in layers:
		var t := float(i) / float(layers - 1)
		var cr := lerpf(7.5, 3.0, t)
		var ch := 9.0
		var g := rng.randf_range(0.9, 1.1)
		plant_part(body, cylinder_mesh(0.0, cr, ch, 12), Color(leaf.r * g, leaf.g * g, leaf.b * g),
				Vector3(0, h * 0.3 + t * h * 0.6 + ch * 0.4, 0), Basis.IDENTITY, 0.4)
	add_obstacle({"pos": Vector3(x, terrain.ground_height(x, z), z), "radius": r * 1.4})

# A tall forest spruce: a thin trunk and many stacked, narrowing skirts of needles that droop at the tips.
func add_spruce(x: float, z: float, rng: RandomNumberGenerator) -> void:
	var body := new_plant_body(x, z)
	var h := rng.randf_range(30.0, 46.0)
	var r := rng.randf_range(0.9, 1.4)
	var tm := cylinder_mesh(r * 0.45, r * 1.1, h * 0.8, 10)
	plant_part(body, tm, Color(0.27, 0.18, 0.11), Vector3(0, h * 0.4, 0))
	trunk_collision(body, tm, Vector3(0, h * 0.4, 0))
	var base := Color(0.07, 0.24, 0.13).lerp(Color(0.12, 0.32, 0.17), rng.randf())
	var layers := rng.randi_range(6, 8)
	var widest := rng.randf_range(6.5, 8.5)
	for i in layers:
		var t := float(i) / float(layers - 1)
		var cr := lerpf(widest, 1.2, pow(t, 0.9))
		var ch := lerpf(8.0, 5.0, t)
		var g := rng.randf_range(0.85, 1.12)
		plant_part(body, cylinder_mesh(0.0, cr, ch, 12), Color(base.r * g, base.g * g, base.b * g),
				Vector3(0, h * 0.2 + t * h * 0.74 + ch * 0.4, 0), Basis.IDENTITY, 0.4)
	add_obstacle({"pos": Vector3(x, terrain.ground_height(x, z), z), "radius": r * 1.4})

func add_round_tree(x: float, z: float, rng: RandomNumberGenerator, bark: StandardMaterial3D) -> void:
	var r := rng.randf_range(2.4, 3.4)          # trunk radius
	var h := rng.randf_range(26.0, 38.0)        # height above the ground
	var base_y := terrain.ground_height(x, z)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	m.stream.region_node(m.stream.region_key(x, z)).add_child(body)
	body.global_position = Vector3(x, base_y - 2.0, z)   # sunk a little so it never floats
	body.set_meta("climbable", true)   # beetles, spiders and termites can climb it
	body.set_meta("burn_r", 5.0)
	Registry.add(body, "plants")

	# The trunk flares wider at the foot and narrows toward the top.
	var tm := CylinderMesh.new()
	tm.bottom_radius = r * 1.5
	tm.top_radius = r * 0.75
	tm.height = h + 2.0
	tm.radial_segments = 16
	tm.rings = 4
	var trunk := MeshInstance3D.new()
	trunk.mesh = tm
	trunk.material_override = bark
	trunk.position = Vector3(0, (h + 2.0) * 0.5, 0)
	fade_far(trunk)
	body.add_child(trunk)
	var col := CollisionShape3D.new()
	col.shape = tm.create_convex_shape(true, true)
	col.position = trunk.position
	body.add_child(col)

	# A clump of leaf masses far overhead.
	for i in rng.randi_range(5, 7):
		var g := rng.randf_range(0.8, 1.2)
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 14
		sm.rings = 8
		var leaf_mat := PlantSway.leaf_material(Color(0.10 * g, 0.50 * g, 0.08 * g), sm, 0.5)   # canopies move in the wind
		var leaves := MeshInstance3D.new()
		leaves.mesh = sm
		leaves.material_override = leaf_mat
		fade_far(leaves)
		var s := rng.randf_range(6.0, 10.0)
		leaves.scale = Vector3(s, s * 0.7, s)
		leaves.position = Vector3(rng.randf_range(-6.0, 6.0), h + 2.0 + rng.randf_range(-3.0, 4.0), rng.randf_range(-6.0, 6.0))
		body.add_child(leaves)

	add_obstacle({"pos": Vector3(x, base_y, z), "radius": r * 1.5})

func add_rock(x: float, z: float, r: float, rng: RandomNumberGenerator, biome: int = 0) -> void:
	var mesh := make_rock_mesh(rng, r)
	var g := rng.randf_range(0.42, 0.62)
	var tint := Color(g, g * rng.randf_range(0.93, 1.0), g * rng.randf_range(0.85, 0.97))
	var bt: Color = Main.ROCK_TINT[biome]
	tint = Color(minf(tint.r * bt.r, 1.0), minf(tint.g * bt.g, 1.0), minf(tint.b * bt.b, 1.0))
	var mat := make_grain_material(tint, Vector3(0.5, 0.5, 0.5), 2.0)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	m.stream.region_node(m.stream.region_key(x, z)).add_child(body)
	body.global_position = Vector3(x, terrain.ground_height(x, z) + r * 0.1, z)
	body.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	fade_far(mi)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_convex_shape(true, true)
	body.add_child(col)

	add_obstacle({"pos": Vector3(x, terrain.ground_height(x, z), z), "radius": r * 1.1})

# A lumpy boulder: a sphere with its surface pushed in and out by noise, flat on the bottom.
func make_rock_mesh(rng: RandomNumberGenerator, r: float) -> ArrayMesh:
	var rock_noise := FastNoiseLite.new()
	rock_noise.seed = rng.randi()
	rock_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var stretch := Vector3(rng.randf_range(0.85, 1.3), rng.randf_range(0.7, 1.0), rng.randf_range(0.85, 1.3))
	var rings := 10
	var segs := 14

	var verts := PackedVector3Array()
	for i in range(rings + 1):
		var phi := PI * float(i) / rings
		for j in segs:
			var theta := TAU * float(j) / segs
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var d := 1.0 + rock_noise.get_noise_3d(dir.x * 1.6, dir.y * 1.6, dir.z * 1.6) * 0.4
			var p := dir * d * r * stretch
			p.y = maxf(p.y, -r * 0.5)
			verts.append(p)

	var idx := PackedInt32Array()
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for i in rings:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			var c := (i + 1) * segs + j
			var e := (i + 1) * segs + (j + 1) % segs
			idx.append_array([a, c, b, b, c, e])
			var n1 := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			var n2 := (verts[e] - verts[b]).cross(verts[c] - verts[b])
			for v in [a, b, c]:
				norms[v] += n1
			for v in [b, e, c]:
				norms[v] += n2
	for k in norms.size():
		norms[k] = norms[k].normalized() if norms[k].length() > 0.0001 else Vector3.UP

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ---------- Scenery ----------

func make_blade_mesh() -> ArrayMesh:
	var w := 0.12
	var verts := PackedVector3Array([
		Vector3(-w, 0.0, 0.0), Vector3(w, 0.0, 0.0),
		Vector3(-w * 0.7, 0.5, 0.05), Vector3(w * 0.7, 0.5, 0.05),
		Vector3(0.0, 1.0, 0.2),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 1),
	])
	var norms := PackedVector3Array()
	for i in 5:
		norms.append(Vector3(0, 0, 1))
	var idx := PackedInt32Array([0, 1, 2, 1, 3, 2, 2, 3, 4])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# Only if its region is still around. If not, the site comes back with the region.
func respawn_pickup(i: int) -> void:
	var sp: Vector3 = pickup_sites[i]["pos"]
	if m.stream.region_done.has(m.stream.region_key(sp.x, sp.z)):
		spawn_pickup(i)

func spawn_pickup(i: int) -> void:
	var site: Dictionary = pickup_sites[i]
	var pos: Vector3 = site["pos"]
	var p := Pickup.new()
	p.kind = site["kind"]
	p.amount = randi_range(4, 10)
	p.home = pos
	# Held still where it sits, so it never drops from the sky or slides about.
	# It is released only if the ground under it gets dug away.
	p.freeze = world.sample_density(pos - Vector3(0, 0.6, 0)) > 0.0
	p.depleted.connect(func(): get_tree().create_timer(Main.PICKUP_RESPAWN_SECONDS).timeout.connect(respawn_pickup.bind(i)))
	m.stream.region_node(m.stream.region_key(pos.x, pos.z)).add_child(p)
	p.global_position = pos

# After a dig, let nearby resources fall into the new hole instead of hovering.
func wake_pickups(point: Vector3, radius: float) -> void:
	# Mushrooms whose surface was dug away are removed instead of floating.
	for node in cave_decor.duplicate():
		if not is_instance_valid(node):
			cave_decor.erase(node)
			continue
		var n3 := node as Node3D
		if n3.global_position.distance_to(point) > radius + 5.0:
			continue
		var probe := n3.global_position - n3.global_transform.basis.y * 0.35
		if world.sample_density(probe) <= 0.0:
			n3.queue_free()
			cave_decor.erase(node)
	for p in Registry.of("pickups"):
		if (p as Pickup).global_position.distance_to(point) < radius + 2.0:
			(p as Pickup).freeze = false

# ---------- Biome relics ----------
# Rare glowing relics lie in the far biomes. Each one marks a tall beam of light. Collect them to break
# the ward on the Great Mound's queen.

# Where a region's relic is, or null when it has none. The same answer every time.
func relic_site(key: Vector2i) -> Variant:
	if relics_taken.has(key):
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 77041
	if rng.randf() > RELIC_CHANCE:
		return null
	var rect: Rect2 = m.stream.region_rect(key)
	var x := rng.randf_range(rect.position.x + 6.0, rect.end.x - 6.0)
	var z := rng.randf_range(rect.position.y + 6.0, rect.end.y - 6.0)
	var rb := terrain.biome_at(x, z)
	if not inland(x, z) or rb == Main.FOREST or rb == Main.PLAINS:   # relics lie only in the far biomes
		return null
	if terrain.near_pool(x, z, 1.8) or terrain.near_mound(x, z, 12.0):
		return null
	return Vector2(x, z)

func region_relic(job: Dictionary) -> void:
	var key: Vector2i = job["key"]
	var site = relic_site(key)
	if site == null:
		return
	var p := Pickup.new()
	p.kind = "relic"
	p.amount = 1
	var pos := Vector3(site.x, terrain.ground_height(site.x, site.y) + 0.3, site.y)
	p.home = pos
	p.freeze = true
	p.depleted.connect(func(): relics_taken[key] = true)
	m.stream.region_node(key).add_child(p)
	p.global_position = pos

# The closest relic to a spot, as {pos, dist}, or an empty dictionary if none lies within about 800 units.
func nearest_relic(from: Vector2) -> Dictionary:
	var home := m.stream.region_key(from.x, from.y)
	var best := {}
	var best_d := 1.0e9
	for dx in range(-26, 27):
		for dz in range(-26, 27):
			var site = relic_site(home + Vector2i(dx, dz))
			if site == null:
				continue
			var d: float = from.distance_to(site)
			if d < best_d:
				best_d = d
				best = {"pos": site, "dist": d}
	return best

# ---------- Region content ----------
# Everything that decorates the ground (trees, boulders, grass, pebbles, resources, creatures)
# is made one 32 x 32 region at a time, as the ground there appears. Each region is seeded from
# its own position, so it always comes out the same. The work is cut into small steps and done
# a few milliseconds per frame, so walking into new land never stutters.

func inland(x: float, z: float) -> bool:
	return terrain.edge_dist(x, z) >= float(Main.HALF - Main.LAND)

func region_step(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	while true:
		if region_job.is_empty():
			if m.stream.region_queue.is_empty():
				return
			region_job = new_region_job(m.stream.region_queue.pop_front())
		var items: Array = region_job["items"]
		if items.is_empty():
			region_job = {}
			continue
		var item: Array = items.pop_front()
		run_region_item(region_job, item)
		if (Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
			return

func new_region_job(key: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, 31337))
	var items := []
	for i in int(Main.TREES_PER_REGION + rng.randf()):
		items.append(["tree"])
	for i in int(Main.BOULDERS_PER_REGION + rng.randf()):
		items.append(["boulder"])
	items.append(["landmark"])
	for i in ceili(Main.GRASS_CLUMPS_PER_REGION / 40.0):
		items.append(["grass", 40])
	items.append(["build_grass"])
	for i in ceili(Main.PEBBLES_PER_REGION / 60.0):
		items.append(["pebbles", 60])
	items.append(["build_pebbles"])
	for i in ceili(Main.FLORA_PATCHES_PER_REGION / 6.0):
		items.append(["flora", 6])
	items.append(["shore", 90])
	items.append(["glade", 60])
	items.append(["build_flora"])
	items.append(["pickups"])
	items.append(["lake"])
	items.append(["relic"])
	items.append(["creatures"])
	items.append(["colony"])
	return {"key": key, "rng": rng, "items": items, "grass": {}, "pebbles": {}, "flora": {}}

func run_region_item(job: Dictionary, item: Array) -> void:
	match item[0]:
		"tree":
			region_tree(job)
		"boulder":
			region_boulder(job)
		"grass":
			region_grass(job, item[1])
		"build_grass":
			build_grass(job)
		"pebbles":
			region_pebbles(job, item[1])
		"build_pebbles":
			build_pebbles(job)
		"landmark":
			region_landmark(job)
		"flora":
			region_flora(job, item[1])
		"shore":
			region_shore(job, item[1])
		"glade":
			region_glade(job, item[1])
		"build_flora":
			build_flora(job)
		"pickups":
			region_pickups(job)
		"lake":
			region_lake(job)
		"relic":
			region_relic(job)
		"creatures":
			region_creatures(job)
		"colony":
			m.pop.region_colony(job)

# A random spot inside the region, kept this far from its edges.
func region_spot(job: Dictionary, margin: float) -> Vector2:
	var rng: RandomNumberGenerator = job["rng"]
	var rect := m.stream.region_rect(job["key"])
	return Vector2(
		rect.position.x + rng.randf_range(margin, Main.REGION_SIZE - margin),
		rect.position.y + rng.randf_range(margin, Main.REGION_SIZE - margin))

func get_bark() -> StandardMaterial3D:
	if bark_mat == null:
		bark_mat = make_grain_material(Color(0.42, 0.29, 0.18), Vector3(0.7, 0.07, 0.7), 1.5)
	return bark_mat

# Trees are well spaced and keep away from pools and the start.
func region_tree(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var p := region_spot(job, 4.0)
	var x := p.x
	var z := p.y
	if not inland(x, z):
		return
	if terrain.near_pool(x, z, 2.8) or near_obstacle(x, z, 6.0):
		return
	if Vector2(x, z).distance_to(Main.STORAGE_XZ) < 14.0:
		return
	var biome := terrain.biome_at(x, z)
	if rng.randf() > Main.TREE_CHANCE[biome]:
		return
	var glade := terrain.glade_at(x, z)
	if glade > 0.0 and rng.randf() < glade * 1.25:
		return   # an open meadow: no trees
	add_plant(x, z, rng, biome, get_bark())

# Boulders, some with smaller rocks leaning against them.
func region_boulder(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var p := region_spot(job, 3.0)
	var x := p.x
	var z := p.y
	var r := 1.2 + pow(rng.randf(), 2.0) * 3.6
	if not inland(x, z):
		return
	if terrain.near_pool(x, z, 1.8) or near_obstacle(x, z, r + 1.5):
		return
	if Vector2(x, z).distance_to(Main.STORAGE_XZ) < 6.0 + r:
		return
	if terrain.glade_at(x, z) > 0.3:
		return   # no boulders in a meadow
	var biome := terrain.biome_at(x, z)
	if rng.randf() > Main.ROCK_CHANCE[biome]:
		return
	add_rock(x, z, r, rng, biome)
	if r > 2.5:
		for k in 2:
			var a := rng.randf_range(0.0, TAU)
			var dist := r * rng.randf_range(1.1, 1.6)
			var sx := x + cos(a) * dist
			var sz := z + sin(a) * dist
			var sr := r * rng.randf_range(0.3, 0.5)
			if terrain.near_pool(sx, sz, 1.8) or near_obstacle(sx, sz, sr + 0.5):
				continue
			add_rock(sx, sz, sr, rng, terrain.biome_at(sx, sz))

# Grass grows in clumps, thick in some areas and thin or bare in others.
func region_grass(job: Dictionary, count: int) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["grass"]
	if grass_density_noise == null:
		grass_density_noise = FastNoiseLite.new()
		grass_density_noise.seed = 555
		grass_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		grass_density_noise.frequency = 0.07
	for c in count:
		var sp := region_spot(job, 0.0)
		var cx := sp.x
		var cz := sp.y
		if not inland(cx, cz):
			continue
		var kind0 := terrain.surface_kind(cx, cz)
		if kind0 != Blocks.GRASS and kind0 != Blocks.DRY_GRASS:
			continue
		if near_obstacle(cx, cz, 2.5):
			continue
		var d := grass_density_noise.get_noise_2d(cx, cz)
		var glade := terrain.glade_at(cx, cz)
		if glade > 0.0:
			d = lerpf(d, 0.55, glade)   # a meadow is thick, even grass with no bare patches
		if d < -0.45:
			continue   # a bare patch
		var blades := roundi(lerpf(2.0, 10.0, smoothstep(-0.2, 0.5, d)))
		if kind0 == Blocks.DRY_GRASS:
			blades = mini(roundi(blades * 1.8), 14)   # savanna grass: thicker than normal, but capped for frame rate
		if Vector2(cx - m.storage_pos.x, cz - m.storage_pos.z).length() < Main.STORAGE_RADIUS + 1.0:
			continue
		for b in blades:
			var x := cx + rng.randf_range(-1.1, 1.1)
			var z := cz + rng.randf_range(-1.1, 1.1)
			var kind1 := terrain.surface_kind(x, z)
			if kind1 != Blocks.GRASS and kind1 != Blocks.DRY_GRASS:
				continue
			var base := Vector3(x, terrain.ground_height(x, z) - 0.1, z)
			var height := rng.randf_range(Main.GRASS_MIN_HEIGHT, Main.GRASS_MAX_HEIGHT)
			var is_dry := kind1 == Blocks.DRY_GRASS
			if is_dry:
				height *= 1.7   # tall savanna grass
			var tint := Color(1.0 if is_dry else 0.0, 1.0 if terrain.biome_at(x, z) == Main.SWAMP else 0.0, 0.0)
			var lean := Vector3(
				rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))
			var bs := Basis.from_euler(lean) * Basis().scaled(Vector3(1.0, height, 1.0))
			var key := m.stream.region_key(x, z)
			if not buckets.has(key):
				buckets[key] = {"xf": [], "pos": [], "tint": []}
			buckets[key]["xf"].append(Transform3D(bs, base))
			buckets[key]["pos"].append(base)
			buckets[key]["tint"].append(tint)

func build_grass(job: Dictionary) -> void:
	var buckets: Dictionary = job["grass"]
	if grass_mat_shared == null:
		var shader := Shader.new()
		shader.code = Main.GRASS_SHADER
		grass_mat_shared = ShaderMaterial.new()
		grass_mat_shared.shader = shader
		grass_mat_shared.set_shader_parameter("fade_start", Main.GRASS_FADE_START)
		grass_mat_shared.set_shader_parameter("fade_end", Main.GRASS_FADE_END)
		blade_mesh_shared = make_blade_mesh()
	for key in buckets:
		var xforms: Array = buckets[key]["xf"]
		var positions: Array = buckets[key]["pos"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = blade_mesh_shared
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, buckets[key]["tint"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = grass_mat_shared
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.stream.region_node(key).add_child(mmi)
		var hidden := []
		hidden.resize(positions.size())
		hidden.fill(0)
		m.stream.decor_sets.append({"mm": mm, "pos": positions, "hidden": hidden, "rect": m.stream.region_rect(key)})
		recheck_dug_decor(m.stream.decor_sets[m.stream.decor_sets.size() - 1])

# Scenery rebuilt over ground you dug earlier must not float in the air.
func recheck_dug_decor(decor: Dictionary) -> void:
	var rect: Rect2 = decor["rect"]
	var c0 := m.stream.col_of(Vector3(rect.position.x, 0, rect.position.y))
	var dug := false
	for dx in 2:
		for dz in 2:
			if m.stream.edited_cols.has(c0 + Vector2i(dx, dz)):
				dug = true
	if not dug:
		return
	var mm: MultiMesh = decor["mm"]
	var pos: Array = decor["pos"]
	var hidden: Array = decor["hidden"]
	for i in pos.size():
		var p: Vector3 = pos[i]
		if world.sample_density(p - Vector3(0, 0.3, 0)) < 0.0:
			hidden[i] = 1
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))
			if decor.has("bodies") and decor["bodies"][i] != null:
				decor["bodies"][i].queue_free()

func region_pebbles(job: Dictionary, count: int) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["pebbles"]
	for i in count:
		var sp := region_spot(job, 0.0)
		var x := sp.x
		var z := sp.y
		if not inland(x, z):
			continue
		if Vector2(x - m.storage_pos.x, z - m.storage_pos.z).length() < Main.STORAGE_RADIUS + 1.0:
			continue
		if terrain.near_pool(x, z) or near_obstacle(x, z, 1.0):
			continue
		var size := rng.randf_range(0.25, 1.0)
		if rng.randf() < 0.1:
			size *= 1.8
		var squash := Vector3(size, size * rng.randf_range(0.5, 0.85), size * rng.randf_range(0.7, 1.0))
		var rot := Vector3(
			rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, TAU), rng.randf_range(-0.3, 0.3))
		var bs := Basis.from_euler(rot) * Basis().scaled(squash)
		var base := Vector3(x, terrain.ground_height(x, z), z)
		var pos := base - Vector3(0, size * 0.12, 0)
		var g := rng.randf_range(0.35, 0.6)
		var key := m.stream.region_key(x, z)
		if not buckets.has(key):
			buckets[key] = {"xf": [], "tint": [], "pos": [], "bodies": []}
		var b: Dictionary = buckets[key]
		b["xf"].append(Transform3D(bs, pos))
		b["tint"].append(Color(g, g * rng.randf_range(0.92, 1.0), g * rng.randf_range(0.8, 0.95)))
		b["pos"].append(pos)

		# Bigger pebbles are solid, so the ant can't walk through them.
		var body: StaticBody3D = null
		if size >= Main.PEBBLE_SOLID_MIN:
			body = StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var ss := SphereShape3D.new()
			ss.radius = size * 0.5 * 0.8
			cs.shape = ss
			body.add_child(cs)
			m.stream.region_node(key).add_child(body)
			body.global_position = pos
		b["bodies"].append(body)

func build_pebbles(job: Dictionary) -> void:
	var buckets: Dictionary = job["pebbles"]
	if pebble_mesh_shared == null:
		pebble_mesh_shared = SphereMesh.new()
		pebble_mesh_shared.radius = 0.5
		pebble_mesh_shared.height = 1.0
		pebble_mesh_shared.radial_segments = 8
		pebble_mesh_shared.rings = 5
		pebble_mat_shared = StandardMaterial3D.new()
		pebble_mat_shared.vertex_color_use_as_albedo = true
		pebble_mat_shared.roughness = 1.0
		pebble_mat_shared.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		pebble_mat_shared.distance_fade_max_distance = Main.GRASS_FADE_START
		pebble_mat_shared.distance_fade_min_distance = Main.GRASS_FADE_END
	for key in buckets:
		var b: Dictionary = buckets[key]
		var xforms: Array = b["xf"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = pebble_mesh_shared
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, b["tint"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = pebble_mat_shared
		m.stream.region_node(key).add_child(mmi)
		var hidden := []
		hidden.resize(xforms.size())
		hidden.fill(0)
		m.stream.decor_sets.append({"mm": mm, "pos": b["pos"], "hidden": hidden, "bodies": b["bodies"], "rect": m.stream.region_rect(key)})
		recheck_dug_decor(m.stream.decor_sets[m.stream.decor_sets.size() - 1])

# One big solid thing now and then: a fallen log, a hollow stump, a half-buried bottle cap or a giant acorn.
func region_landmark(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	if rng.randf() > Main.LANDMARK_CHANCE:
		return
	var sp := region_spot(job, 6.0)
	var x := sp.x
	var z := sp.y
	if not inland(x, z) or terrain.near_pool(x, z, 1.8) or near_obstacle(x, z, 4.5):
		return
	if Vector2(x, z).distance_to(Main.STORAGE_XZ) < 12.0:
		return
	var kind := Flora.pick_landmark(terrain.biome_at(x, z), rng.randf())
	if kind < 0:
		return
	var variant := rng.randi() % (3 if kind == 2 else 2)
	var gy := terrain.ground_height(x, z)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	m.stream.region_node(m.stream.region_key(x, z)).add_child(body)
	var sink: float = [0.25, 0.2, 0.3, 0.2][kind]
	body.global_position = Vector3(x, gy - sink, z)
	var tilt_x := rng.randf_range(0.15, 0.35) if kind == 2 else 0.0
	var tilt_z := rng.randf_range(-0.2, 0.2) if kind == 2 else 0.0
	body.rotation = Vector3(tilt_x, rng.randf_range(0.0, TAU), tilt_z)

	var mi := MeshInstance3D.new()
	mi.mesh = Flora.get_landmark_mesh(kind, variant)
	if landmark_mat == null:
		landmark_mat = Flora.landmark_material()
	mi.material_override = landmark_mat
	fade_far(mi)
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var radius := 1.5
	match kind:
		0:
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.9
			cyl.height = 7.0
			col.shape = cyl
			col.transform = Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(0, 0.9, 0))
			radius = 3.8
		1:
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.05
			cyl.height = 1.7
			col.shape = cyl
			col.position = Vector3(0, 0.85, 0)
			radius = 1.5
		2:
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.5
			cyl.height = 0.55
			col.shape = cyl
			col.position = Vector3(0, 0.275, 0)
			radius = 1.8
		3:
			var sph := SphereShape3D.new()
			sph.radius = 1.1
			col.shape = sph
			col.position = Vector3(0, 1.3, 0)
			radius = 1.4
	body.add_child(col)
	add_obstacle({"pos": Vector3(x, gy, z), "radius": radius})

# Flowers, mushrooms, cacti and moss. Each patch is one kind, picked from the biome's list (see flora.gd).
func region_flora(job: Dictionary, count: int) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["flora"]
	for c in count:
		var sp := region_spot(job, 0.0)
		var cx := sp.x
		var cz := sp.y
		if not inland(cx, cz) or terrain.near_pool(cx, cz):
			continue
		var kind0 := terrain.surface_kind(cx, cz)
		if kind0 == Blocks.MOUND or kind0 == Blocks.DEAD_MOUND or kind0 == Blocks.STONE or kind0 == Blocks.AIR:
			continue
		if Vector2(cx - m.storage_pos.x, cz - m.storage_pos.z).length() < Main.STORAGE_RADIUS + 3.0:
			continue
		var species := Flora.pick(terrain.biome_at(cx, cz), rng.randf())
		if species < 0:
			continue
		var info: Array = Flora.PATCH[species]
		var n := rng.randi_range(int(info[0]), int(info[1]))
		var spread := float(info[2])
		for i in n:
			var x := cx + rng.randf_range(-spread, spread)
			var z := cz + rng.randf_range(-spread, spread)
			add_flora_instance(buckets, species, x, z, rng)

# Plants one flora instance if the spot allows it.
func add_flora_instance(buckets: Dictionary, species: int, x: float, z: float, rng: RandomNumberGenerator, need_dry: bool = true) -> void:
	if not inland(x, z) or terrain.near_pool(x, z) or near_obstacle(x, z, 0.8):
		return
	var k := terrain.surface_kind(x, z)
	if k == Blocks.MOUND or k == Blocks.DEAD_MOUND or k == Blocks.STONE or k == Blocks.AIR:
		return
	var base := Vector3(x, terrain.ground_height(x, z) - 0.08, z)
	var sc := rng.randf_range(0.75, 1.3)
	var tilt := Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(0.0, TAU), rng.randf_range(-0.07, 0.07))
	var bs := Basis.from_euler(tilt) * Basis.from_scale(Vector3.ONE * sc)
	var key := m.stream.region_key(x, z)
	if not buckets.has(key):
		buckets[key] = {}
	if not buckets[key].has(species):
		buckets[key][species] = {"xf": [], "pos": []}
	buckets[key][species]["xf"].append(Transform3D(bs, base))
	buckets[key][species]["pos"].append(base)

# Lake banks: cattails at the water's edge, then bushes, ferns and flowers up the bank.
func region_shore(job: Dictionary, tries: int) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["flora"]
	var mid := region_spot(job, Main.REGION_SIZE * 0.5 - 0.01)
	var lakes := []
	for p in terrain.pools_at(mid.x, mid.y):
		if p.get("lake", false):
			lakes.append(p)
	if lakes.is_empty():
		return
	for t in tries:
		var sp := region_spot(job, 0.0)
		for p in lakes:
			var r: float = p["radius"]
			var d := terrain.pool_dist(p, sp.x, sp.y)
			if d < r * 0.78 or d > r * 1.7:
				continue
			var gh := terrain.ground_height(sp.x, sp.y)
			var level: float = p["level0"]
			if gh < level - 0.2:
				continue   # underwater
			var species := 6   # cattail
			if gh > level + 0.8:
				var roll := rng.randf()
				if roll < 0.45:
					species = 27   # hedge bush
				elif roll < 0.65:
					species = 20   # berry bush
				elif roll < 0.8:
					species = 18   # fern
				elif roll < 0.9:
					species = 0    # daisy
				else:
					species = 3    # buttercup
			var n := 3 if species == 6 else rng.randi_range(1, 3)
			for i in n:
				add_flora_instance(buckets, species, sp.x + rng.randf_range(-1.6, 1.6), sp.y + rng.randf_range(-1.6, 1.6), rng)

# Meadow flowers and mushrooms: dense patches of wildflowers with clusters of mushrooms among them.
const GLADE_FLOWERS := [0, 0, 1, 2, 3, 3, 4, 19, 22]      # daisy, poppy, lupine, buttercup, pink bloom, clover, dandelion
const GLADE_MUSHROOMS := [12, 13, 14, 15, 16]             # fly agaric, porcini, parasol, cluster, chanterelle

func region_glade(job: Dictionary, tries: int) -> void:
	var mid := region_spot(job, Main.REGION_SIZE * 0.5 - 0.01)
	var near := terrain.glade_at(mid.x, mid.y)
	var half := Main.REGION_SIZE * 0.5
	for o in [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half)]:
		near = maxf(near, terrain.glade_at(mid.x + o.x, mid.y + o.y))
	if near <= 0.0:
		return   # no glade anywhere in this square
	var rng: RandomNumberGenerator = job["rng"]
	var buckets: Dictionary = job["flora"]
	for t in tries:
		var sp := region_spot(job, 0.0)
		var g := terrain.glade_at(sp.x, sp.y)
		if g < 0.25 or rng.randf() > g:
			continue
		if not inland(sp.x, sp.y) or terrain.near_pool(sp.x, sp.y):
			continue
		if Vector2(sp.x - m.storage_pos.x, sp.y - m.storage_pos.z).length() < Main.STORAGE_RADIUS + 3.0:
			continue
		var mushroom := rng.randf() < 0.28
		var species: int = GLADE_MUSHROOMS[rng.randi() % GLADE_MUSHROOMS.size()] if mushroom else GLADE_FLOWERS[rng.randi() % GLADE_FLOWERS.size()]
		var info: Array = Flora.PATCH[species]
		var n := rng.randi_range(int(info[0]), int(info[1]))
		var spread := float(info[2])
		for i in n:
			add_flora_instance(job["flora"], species, sp.x + rng.randf_range(-spread, spread), sp.y + rng.randf_range(-spread, spread), rng)

func build_flora(job: Dictionary) -> void:
	var buckets: Dictionary = job["flora"]
	for key in buckets:
		for species in buckets[key]:
			if not flora_mats.has(species):
				flora_mats[species] = Flora.make_material(species, Main.GRASS_FADE_START, Main.GRASS_FADE_END)
			var xforms: Array = buckets[key][species]["xf"]
			var positions: Array = buckets[key][species]["pos"]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Flora.get_mesh(species)
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = flora_mats[species]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.stream.region_node(key).add_child(mmi)
			var hidden := []
			hidden.resize(positions.size())
			hidden.fill(0)
			m.stream.decor_sets.append({"mm": mm, "pos": positions, "hidden": hidden, "rect": m.stream.region_rect(key)})
			recheck_dug_decor(m.stream.decor_sets[m.stream.decor_sets.size() - 1])

# Resources sit at fixed spots. Each spot grows its resource back some time after you take it.
# ---------- Under the lake ----------
# Lake regions get shells on the bed, sea plants, lily pads on the surface and fish. Shells are
# ordinary pickup sites (so they come back after being taken); the rest is rebuilt with the region.

func region_lake(job: Dictionary) -> void:
	var rkey: Vector2i = job["key"]
	var rect := m.stream.region_rect(rkey)
	var cx := rect.position.x + Main.REGION_SIZE * 0.5
	var cz := rect.position.y + Main.REGION_SIZE * 0.5
	var lake: Dictionary = {}
	for p in terrain.pools_at(cx, cz):
		if p.get("lake", false):
			lake = p
	if lake.is_empty():
		return
	var r: float = lake["radius"]
	var mid_d := terrain.pool_dist(lake, cx, cz) / r   # as a share of the lake's radius
	if mid_d > 0.82 + 26.0 / r:
		return   # this region is nowhere near the water
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(rkey.x, rkey.y, 9001))
	var level: float = lake["level0"]
	var node := m.stream.region_node(rkey)

	# Shell sites on the bed (first time only: after that the site list brings them back).
	if not lake_sites_made.has(rkey):
		lake_sites_made[rkey] = true
		if not region_sites.has(rkey):
			region_sites[rkey] = []
		for t in Main.LAKE_SHELL_TRIES:
			var sp := lake_spot(rect, rng)
			var f := terrain.pool_dist(lake, sp.x, sp.y) / r
			if f < 0.22 or f > 0.78:
				continue
			var gh := terrain.ground_height(sp.x, sp.y)
			if gh > level - 2.0:
				continue
			pickup_sites.append({"pos": Vector3(sp.x, gh + 0.3, sp.y), "kind": "shell"})
			region_sites[rkey].append(pickup_sites.size() - 1)
			spawn_pickup(pickup_sites.size() - 1)

	# Sea plants.
	for t in Main.LAKE_PLANT_TRIES:
		var sp := lake_spot(rect, rng)
		var f := terrain.pool_dist(lake, sp.x, sp.y) / r
		if f < 0.12 or f > 0.8:
			continue
		var gh := terrain.ground_height(sp.x, sp.y)
		var water_h := level - gh
		if water_h < 1.6:
			continue
		var pos := Vector3(sp.x, gh - 0.05, sp.y)
		var roll := rng.randf()
		if roll < 0.28:
			LakeLife.kelp(node, pos, water_h - 0.6, rng)
		elif roll < 0.78:
			LakeLife.seagrass(node, pos, rng)
		else:
			LakeLife.sea_cabbage(node, pos, rng)

	# Lily pads: small clusters, so there is usually one to swim to.
	var placed: Array[Vector2] = []
	var clusters := 1 + (1 if rng.randf() < 0.45 else 0)
	for c_i in clusters:
		for t in 12:
			var sp := lake_spot(rect, rng)
			var f := terrain.pool_dist(lake, sp.x, sp.y) / r
			if f < 0.3 or f > 0.8:
				continue
			if level - terrain.ground_height(sp.x, sp.y) < 1.6:
				continue
			var ok := true
			for q in placed:
				if q.distance_to(sp) < 6.0:
					ok = false
			if not ok:
				continue
			var n := rng.randi_range(1, 3)
			for i in n:
				var a := rng.randf() * TAU
				var off := Vector2(cos(a), sin(a)) * (0.0 if i == 0 else rng.randf_range(2.4, 3.6))
				var pp := sp + off
				if terrain.pool_dist(lake, pp.x, pp.y) / r > 0.82 or level - terrain.ground_height(pp.x, pp.y) < 1.2:
					continue
				var pad := LilyPad.new()
				pad.lake = lake
				pad.radius = rng.randf_range(1.7, 2.6)
				pad.flower = rng.randf() < 0.3
				node.add_child(pad)
				pad.global_position = Vector3(pp.x, level + 0.02, pp.y)
				placed.append(pp)
			break

	# Fish: only where the water is deep, a few aggressive among many passive.
	if mid_d < 0.72:
		for i in int(Main.FISH_PER_REGION + rng.randf()):
			var sp := lake_spot(rect, rng)
			if terrain.pool_dist(lake, sp.x, sp.y) / r > 0.7:
				continue
			var gh := terrain.ground_height(sp.x, sp.y)
			if level - gh < 2.5:
				continue
			var y := rng.randf_range(gh + 0.8, level - 0.9)
			m.pop.spawn_fish(Vector3(sp.x, y, sp.y), lake, rng.randf() < Main.FISH_AGGRESSIVE_SHARE)

# A random point inside a region.
func lake_spot(rect: Rect2, rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rect.position.x + rng.randf_range(1.0, Main.REGION_SIZE - 1.0),
		rect.position.y + rng.randf_range(1.0, Main.REGION_SIZE - 1.0))

func region_pickups(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	var rkey: Vector2i = job["key"]
	if region_sites.has(rkey):
		for i in region_sites[rkey]:
			spawn_pickup(i)
		return
	region_sites[rkey] = []
	for i in int(Main.PICKUPS_PER_REGION + rng.randf()):
		var sp := region_spot(job, 2.0)
		var x := sp.x
		var z := sp.y
		if not inland(x, z):
			continue
		if Vector2(x, z).distance_to(Vector2(m.storage_pos.x, m.storage_pos.z)) < 6.0:
			continue
		if terrain.near_pool(x, z) or near_obstacle(x, z, 2.0):
			continue
		var options: Array = Main.BIOME_RESOURCES[terrain.biome_at(x, z)]
		pickup_sites.append({
			"pos": Vector3(x, terrain.ground_height(x, z) + 0.3, z),
			"kind": options[rng.randi() % options.size()],
		})
		region_sites[rkey].append(pickup_sites.size() - 1)
		spawn_pickup(pickup_sites.size() - 1)

func region_creatures(job: Dictionary) -> void:
	var rng: RandomNumberGenerator = job["rng"]
	for i in int(Main.FIREFLIES_PER_REGION + rng.randf()):
		var sp := region_spot(job, 3.0)
		if inland(sp.x, sp.y) and rng.randf() <= Main.FIREFLY_CHANCE[terrain.biome_at(sp.x, sp.y)]:
			m.pop.spawn_firefly(Vector3(sp.x, terrain.ground_height(sp.x, sp.y) + 3.0, sp.y))
	for i in int(Main.SPIDERS_PER_REGION + rng.randf()):
		var sp := region_spot(job, 4.0)
		if not inland(sp.x, sp.y):
			continue
		if sp.distance_to(Main.STORAGE_XZ) < 14.0 or terrain.near_pool(sp.x, sp.y, 2.0) or near_obstacle(sp.x, sp.y, 2.0):
			continue
		m.pop.spawn_spider(Vector3(sp.x, terrain.ground_height(sp.x, sp.y) + 0.5, sp.y))
	for i in int(Main.BEETLES_PER_REGION + rng.randf()):
		var sp := region_spot(job, 4.0)
		if not inland(sp.x, sp.y) or rng.randf() > Main.BEETLE_CHANCE[terrain.biome_at(sp.x, sp.y)]:
			continue
		if sp.distance_to(Main.STORAGE_XZ) < 14.0 or terrain.near_pool(sp.x, sp.y, 2.0) or near_obstacle(sp.x, sp.y, 2.0):
			continue
		m.pop.spawn_beetle(Vector3(sp.x, terrain.ground_height(sp.x, sp.y) + 0.5, sp.y))
	for i in int(Main.CENTIPEDES_PER_REGION + rng.randf()):
		var sp := region_spot(job, 4.0)
		if not inland(sp.x, sp.y) or rng.randf() > Main.CENTIPEDE_CHANCE[terrain.biome_at(sp.x, sp.y)]:
			continue
		if sp.distance_to(Main.STORAGE_XZ) < 14.0 or terrain.near_pool(sp.x, sp.y, 2.0) or near_obstacle(sp.x, sp.y, 2.0):
			continue
		m.pop.spawn_centipede(Vector3(sp.x, terrain.ground_height(sp.x, sp.y) + 0.5, sp.y))
	for i in int(Main.DRAGONFLIES_PER_REGION + rng.randf()):
		var sp := region_spot(job, 4.0)
		if not inland(sp.x, sp.y) or rng.randf() > Main.DRAGONFLY_CHANCE[terrain.biome_at(sp.x, sp.y)]:
			continue
		if sp.distance_to(Main.STORAGE_XZ) < 30.0:
			continue   # none right over the start
		m.pop.spawn_dragonfly(Vector3(sp.x, terrain.ground_height(sp.x, sp.y) + randf_range(7.0, 12.0), sp.y))
	# Now and then a region holds a boss: one big, tough creature of the same kinds.
	if rng.randf() < Main.BOSS_CHANCE:
		var bp := region_spot(job, 6.0)
		var kind: String = Population.BOSS_KINDS[rng.randi() % Population.BOSS_KINDS.size()]
		if inland(bp.x, bp.y) and bp.distance_to(Main.STORAGE_XZ) > 80.0 and not terrain.near_pool(bp.x, bp.y, 3.0) and not near_obstacle(bp.x, bp.y, 3.0):
			m.pop.spawn_boss(kind, Vector3(bp.x, terrain.ground_height(bp.x, bp.y) + 0.5, bp.y))
