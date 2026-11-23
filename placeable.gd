class_name Placeable
extends StaticBody3D

# A crafted item placed in the world (wooden box, water barrel).
# Its origin is the center of the item's bounding box, like the building pieces.

var type := "box"
var stock := {}   # what a box or barrel holds: kind -> amount

# The queen can be hurt. If her health reaches zero she dies and the colony loses her.
signal destroyed(p: Placeable)
signal attacked
const QUEEN_MAX_HEALTH := 400.0
const QUEEN_REGEN := 1.0          # she heals herself, but slowly (health per second)
const QUEEN_REGEN_DELAY := 10.0   # only after this many seconds without being bitten
const SUGAR_HEAL := 25.0          # health she gains from one sugar you feed her
var health := QUEEN_MAX_HEALTH
var since_hit := 99.0
var health_label: Label3D

# Silk trap: catches spiders, a few times, then wears out.
const TRAP_USES := 3
const TRAP_RADIUS := 1.5
const TRAP_HOLD_SECONDS := 4.0
var uses_left := TRAP_USES
var web: Node3D

# Defense traps (resin, pit, acid, collapse). Unlike the silk trap, these watch for creatures
# themselves. "hold" is how long a creature is stuck, "burst" is the radius of an area blast.
const DEFENSE := {
	"resin_trap": {"uses": 4, "radius": 1.6, "hold": 8.0},
	"pit_trap": {"uses": 3, "radius": 1.3, "hold": 6.0, "damage": 25.0},
	"acid_trap": {"uses": 2, "radius": 1.5, "burst": 3.4, "damage": 60.0},
	"collapse_trap": {"uses": 1, "radius": 1.4, "burst": 3.2, "damage": 40.0},
}
signal collapsed(center: Vector3, radius: float)
var defense_uses := 0
var defense_timer := 0.0
var caught := {}          # creature id -> when it can set this trap off again
var trap_vis: Node3D

# Gravity. If the ground under a placed item is dug away, it falls until something holds it.
signal moved(p: Placeable)
const FALL_GRAVITY := 28.0
const FALL_LIMIT := 40.0
var world: World
var fall_speed := 0.0
var fall_dist := 0.0
var support_timer := randf() * 0.3
var falling := false

func _ready() -> void:
	collision_layer = 0 if (type == "trap" or DEFENSE.has(type)) else 5   # layers 1 and 4, same as building pieces. Traps are walked over.
	collision_mask = 0

	var info: Dictionary = Crafting.RECIPES[type]
	if info.has("caps"):
		add_to_group("containers")
	var size: Vector3 = info["size"]
	var wood := StandardMaterial3D.new()
	wood.albedo_color = info["color"]
	wood.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(info["color"]).darkened(0.45)
	dark.roughness = 0.8

	if type == "trap":
		add_to_group("traps")
		web = Node3D.new()
		add_child(web)
		var web_mat := StandardMaterial3D.new()
		web_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.55)
		web_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		web_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		web_mat.roughness = 0.4
		web_mat.emission_enabled = true
		web_mat.emission = Color(0.8, 0.85, 1.0)
		web_mat.emission_energy_multiplier = 0.4
		# A flat disc with rings and spokes so it reads as a web.
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = TRAP_RADIUS * 0.95
		dm.bottom_radius = TRAP_RADIUS * 0.95
		dm.height = 0.04
		disc.mesh = dm
		disc.material_override = web_mat
		disc.position.y = -size.y * 0.35
		web.add_child(disc)
		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = Color(1, 1, 1)
		line_mat.emission_enabled = true
		line_mat.emission = Color(1, 1, 1)
		line_mat.emission_energy_multiplier = 0.6
		for i in 8:
			var spoke := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(TRAP_RADIUS * 1.9, 0.05, 0.05)
			spoke.mesh = sb
			spoke.material_override = line_mat
			spoke.rotation.y = PI * float(i) / 8.0
			spoke.position.y = -size.y * 0.3
			web.add_child(spoke)
		for r in [0.35, 0.65, 0.95]:
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = TRAP_RADIUS * r - 0.03
			tm.outer_radius = TRAP_RADIUS * r + 0.03
			ring.mesh = tm
			ring.material_override = line_mat
			ring.scale.y = 0.5
			ring.position.y = -size.y * 0.3
			web.add_child(ring)
		return   # no collision shape: ants and spiders walk straight over it
	if DEFENSE.has(type):
		defense_uses = int(DEFENSE[type]["uses"])
		build_defense_visual(size)
		return   # no collision shape: everything walks straight over it
	if type == "queen":
		var skin := StandardMaterial3D.new()
		skin.albedo_color = info["color"]
		skin.roughness = 0.7
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = Color(0.35, 0.22, 0.12)
		head_mat.roughness = 0.6
		# Big abdomen, smaller thorax, head.
		var parts := [
			[Vector3(size.x * 0.85, size.y * 0.8, size.z * 0.55), Vector3(0, -size.y * 0.1, size.z * 0.17), skin],
			[Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.24), Vector3(0, -size.y * 0.1, -size.z * 0.2), head_mat],
			[Vector3(size.x * 0.34, size.y * 0.34, size.z * 0.16), Vector3(0, -size.y * 0.05, -size.z * 0.4), head_mat],
		]
		for part in parts:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			mi.mesh = sm
			mi.scale = part[0]
			mi.position = part[1]
			mi.material_override = part[2]
			add_child(mi)
		var tag := Label3D.new()
		tag.text = "Queen"
		tag.font_size = 48
		tag.pixel_size = 0.02
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, size.y * 0.5 + 0.9, 0)
		add_child(tag)
		health_label = Label3D.new()
		health_label.font_size = 40
		health_label.pixel_size = 0.016
		health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		health_label.no_depth_test = true
		health_label.position = Vector3(0, size.y * 0.5 + 0.35, 0)
		add_child(health_label)
		update_health_label()
	elif type == "lamp" or type == "crystal_lamp":
		var violet := type == "crystal_lamp"
		# A small stand holding a glowing bead of firefly glow.
		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = size.x * 0.32
		bm.bottom_radius = size.x * 0.32
		bm.height = size.y * 0.2
		base.mesh = bm
		base.material_override = dark
		base.position.y = -size.y * 0.4
		add_child(base)
		var stem := MeshInstance3D.new()
		var stm := CylinderMesh.new()
		stm.top_radius = size.x * 0.07
		stm.bottom_radius = size.x * 0.07
		stm.height = size.y * 0.5
		stem.mesh = stm
		stem.material_override = dark
		stem.position.y = -size.y * 0.15
		add_child(stem)
		var glow_mat := StandardMaterial3D.new()
		glow_mat.albedo_color = Color(0.7, 0.65, 1.0) if violet else Color(0.9, 1.0, 0.4)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(0.5, 0.4, 1.0) if violet else Color(0.7, 1.0, 0.2)
		glow_mat.emission_energy_multiplier = 2.5
		var bead := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = size.x * 0.4
		gm.height = size.x * 0.8
		bead.mesh = gm
		bead.material_override = glow_mat
		bead.position.y = size.y * 0.25
		add_child(bead)
		var light := OmniLight3D.new()
		light.light_color = Color(0.6, 0.55, 1.0) if violet else Color(0.8, 1.0, 0.35)
		light.light_energy = 2.4 if violet else 1.8
		light.omni_range = 22.0 if violet else 13.0
		light.shadow_enabled = false   # set true for shadows, but many lamps with shadows gets slow
		light.position.y = size.y * 0.25
		add_child(light)
	elif type == "barrel":
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = size.x * 0.45
		cm.bottom_radius = size.x * 0.45
		cm.height = size.y
		body.mesh = cm
		body.material_override = wood
		add_child(body)
		for y in [-0.3, 0.3]:
			var band := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = size.x * 0.48
			bm.bottom_radius = size.x * 0.48
			bm.height = size.y * 0.08
			band.mesh = bm
			band.material_override = dark
			band.position.y = size.y * y
			add_child(band)
	else:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		body.mesh = bm
		body.material_override = wood
		add_child(body)
		var lid := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(size.x * 1.06, size.y * 0.12, size.z * 1.06)
		lid.mesh = lm
		lid.material_override = dark
		lid.position.y = size.y * 0.5
		add_child(lid)
		for x in [-0.3, 0.3]:
			var strap := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(size.x * 0.1, size.y * 1.02, size.z * 1.04)
			strap.mesh = sm
			strap.material_override = dark
			strap.position.x = size.x * x
			add_child(strap)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	add_child(col)

func trap_disc(radius: float, y: float, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.05
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	mi.material_override = m
	mi.position.y = y
	trap_vis.add_child(mi)
	return mi

func trap_blob(radius: float, pos: Vector3, color: Color, glow: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	mi.material_override = m
	mi.position = pos
	trap_vis.add_child(mi)

func build_defense_visual(size: Vector3) -> void:
	trap_vis = Node3D.new()
	add_child(trap_vis)
	var y := -size.y * 0.35
	var r: float = float(DEFENSE[type]["radius"])
	match type:
		"resin_trap":
			trap_disc(r * 0.95, y, Color(0.9, 0.55, 0.1, 1.0), 0.5)
			trap_blob(0.35, Vector3(0.5, y + 0.1, 0.2), Color(1.0, 0.7, 0.2), 0.7)
			trap_blob(0.25, Vector3(-0.4, y + 0.08, -0.5), Color(1.0, 0.7, 0.2), 0.7)
			trap_blob(0.2, Vector3(-0.3, y + 0.07, 0.6), Color(1.0, 0.75, 0.25), 0.7)
		"pit_trap":
			trap_disc(r * 1.05, y, Color(0.32, 0.23, 0.14))
			trap_disc(r * 0.8, y + 0.03, Color(0.04, 0.03, 0.02))
			for i in 8:
				var a := TAU * float(i) / 8.0
				trap_blob(0.12, Vector3(cos(a) * r * 0.85, y + 0.08, sin(a) * r * 0.85), Color(0.4, 0.3, 0.18))
		"acid_trap":
			trap_disc(r * 0.95, y, Color(0.4, 0.9, 0.15), 1.1)
			trap_blob(0.22, Vector3(0.4, y + 0.12, 0.1), Color(0.6, 1.0, 0.3), 1.6)
			trap_blob(0.16, Vector3(-0.35, y + 0.1, -0.3), Color(0.6, 1.0, 0.3), 1.6)
			trap_blob(0.14, Vector3(0.1, y + 0.1, -0.55), Color(0.6, 1.0, 0.3), 1.6)
			var light := OmniLight3D.new()
			light.light_color = Color(0.5, 1.0, 0.25)
			light.light_energy = 0.8
			light.omni_range = 5.0
			light.shadow_enabled = false
			light.position.y = y + 0.5
			trap_vis.add_child(light)
		"collapse_trap":
			for i in 7:
				var a := TAU * float(i) / 7.0
				trap_blob(randf_range(0.28, 0.45), Vector3(cos(a) * 0.55, y + 0.15, sin(a) * 0.55), Color(0.5, 0.48, 0.46).darkened(randf_range(0.0, 0.25)))
			trap_blob(0.5, Vector3(0, y + 0.25, 0), Color(0.55, 0.52, 0.5))

# Looks for creatures standing on the trap, a few times a second.
func tick_defense(delta: float) -> void:
	if defense_uses <= 0:
		return
	defense_timer -= delta
	if defense_timer > 0.0:
		return
	defense_timer = 0.1
	var info: Dictionary = DEFENSE[type]
	var r: float = info["radius"]
	var now := Time.get_ticks_msec() / 1000.0
	for c in get_tree().get_nodes_in_group("creatures"):
		var cr := c as Creature
		if cr == null or cr is Firefly or not cr.active:
			continue
		var off := cr.global_position - global_position
		if Vector2(off.x, off.z).length() > r or absf(off.y) > 2.0:
			continue
		var id := cr.get_instance_id()
		if float(caught.get(id, 0.0)) > now:
			continue
		caught[id] = now + float(info.get("hold", 1.0)) + 2.5
		spring(cr)
		if defense_uses <= 0:
			return

func hold_creature(cr: Creature, seconds: float) -> void:
	if "stuck_time" in cr:
		cr.set("stuck_time", seconds)
		cr.set("web_immunity", seconds + 2.5)

# A creature stepped on the trap.
func spring(cr: Creature) -> void:
	defense_uses -= 1
	var info: Dictionary = DEFENSE[type]
	match type:
		"resin_trap":
			hold_creature(cr, float(info["hold"]))
		"pit_trap":
			hold_creature(cr, float(info["hold"]))
			cr.take_damage(float(info["damage"]))
		"acid_trap", "collapse_trap":
			var burst: float = info["burst"]
			for c in get_tree().get_nodes_in_group("creatures"):
				var other := c as Creature
				if other == null or other is Firefly or not other.active:
					continue
				var off := other.global_position - global_position
				if Vector2(off.x, off.z).length() <= burst and absf(off.y) < 3.0:
					other.take_damage(float(info["damage"]))
			if type == "collapse_trap":
				collapsed.emit(global_position + Vector3.UP * 1.2, 2.4)
	var frac := float(defense_uses) / float(info["uses"])
	if defense_uses <= 0:
		trap_vis.scale = Vector3.ONE * 0.5
		get_tree().create_timer(3.0 if type == "resin_trap" else 1.0).timeout.connect(queue_free)
	else:
		trap_vis.scale = Vector3.ONE * (0.6 + 0.4 * frac)

# A spider touched the web. Returns true if it got stuck. The web shrinks as it wears out.
func try_catch() -> bool:
	if type != "trap" or uses_left <= 0:
		return false
	uses_left -= 1
	if uses_left <= 0:
		get_tree().create_timer(TRAP_HOLD_SECONDS).timeout.connect(queue_free)
		web.scale = Vector3.ONE * 0.5
	else:
		web.scale = Vector3.ONE * (0.55 + 0.45 * float(uses_left) / float(TRAP_USES))
	return true

func feed(amount: float) -> void:
	health = minf(QUEEN_MAX_HEALTH, health + amount)
	update_health_label()

func take_damage(amount: float) -> void:
	if type != "queen" or health <= 0.0:
		return
	health -= amount
	since_hit = 0.0
	attacked.emit()
	update_health_label()
	if health <= 0.0:
		destroyed.emit(self)

# Is something solid right under the bottom of this item? Terrain by density, or another placed thing / building piece.
func supported() -> bool:
	if world == null:
		return true
	var info: Dictionary = Crafting.RECIPES[type]
	var size: Vector3 = info["size"]
	var half := size * 0.5
	var down := -global_transform.basis.y
	var base := global_position + down * (half.y + 0.2)
	for off in [Vector3.ZERO, Vector3(half.x * 0.7, 0, 0), Vector3(-half.x * 0.7, 0, 0), Vector3(0, 0, half.z * 0.7), Vector3(0, 0, -half.z * 0.7)]:
		if world.sample_density(base + global_transform.basis * off) > 0.0:
			return true
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + down * (half.y + 0.35), 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		if col is Placeable or col is Piece:
			return true
	return false

func _physics_process(delta: float) -> void:
	if DEFENSE.has(type):
		tick_defense(delta)
	if world == null:
		return
	if not falling:
		support_timer -= delta
		if support_timer > 0.0:
			return
		support_timer = 0.3
		if supported():
			return
		falling = true
		fall_speed = 0.0
		fall_dist = 0.0
	fall_speed += FALL_GRAVITY * delta
	var step := fall_speed * delta
	global_position.y -= step
	fall_dist += step
	if supported() or fall_dist > FALL_LIMIT:
		falling = false
		support_timer = 0.3
		moved.emit(self)

func _process(delta: float) -> void:
	if type != "queen" or health <= 0.0:
		return
	since_hit += delta
	if since_hit > QUEEN_REGEN_DELAY and health < QUEEN_MAX_HEALTH:
		health = minf(QUEEN_MAX_HEALTH, health + QUEEN_REGEN * delta)
		update_health_label()

func update_health_label() -> void:
	if health_label == null:
		return
	var frac := clampf(health / QUEEN_MAX_HEALTH, 0.0, 1.0)
	var filled := roundi(frac * 10.0)
	health_label.text = "[" + "|".repeat(filled) + ".".repeat(10 - filled) + "]"
	health_label.modulate = Color(0.4, 1.0, 0.4).lerp(Color(1.0, 0.3, 0.2), 1.0 - frac)

# The most this item can hold of one kind of thing (0 if it can't hold it).
func cap(kind: String) -> float:
	var caps: Dictionary = Crafting.RECIPES[type].get("caps", {})
	return float(caps.get(kind, 0))

func total_stock() -> float:
	var t := 0.0
	for k in stock:
		t += float(stock[k])
	return t
